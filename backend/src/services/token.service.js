/**
 * WHAT: Handles access tokens, refresh sessions, invite tokens, and auth cookies.
 * WHY: Centralizing token work keeps authentication rules consistent across controllers and services.
 * HOW: Sign JWTs, persist hashed refresh sessions, rotate sessions safely, and expose cookie helpers.
 */

const { randomUUID } = require('crypto');

const jwt = require('jsonwebtoken');

const { ERROR_CLASSIFICATIONS, LOG_STEPS } = require('../constants/app.constants');
const { env } = require('../config/env');
const { RefreshSession } = require('../models/refresh-session.model');
const { AppError } = require('../utils/app-error');
const { logError, logInfo } = require('../utils/logger');
const { hashValue } = require('../utils/security');

function decodeExpiryDate(token) {
  // WHY: Persist the expiry as a real date so session cleanup and validation can query it directly.
  const payload = jwt.decode(token);
  return new Date((payload?.exp || 0) * 1000);
}

function createAccessToken(user) {
  // WHY: Keep access-token creation centralized so every auth path signs the same minimal claim set.
  return jwt.sign(
    {
      sub: String(user._id || user.id),
      role: user.role,
      email: user.email,
    },
    env.jwtAccessSecret,
    { expiresIn: env.jwtAccessTtl },
  );
}

async function issueSessionTokens(user, meta, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'IssueSessionTokens',
    intent: 'Create access and refresh credentials for an authenticated user',
  });

  // WHY: Use a dedicated session id so each browser session can be revoked independently.
  const sessionId = randomUUID();
  const refreshToken = jwt.sign(
    {
      sub: String(user._id || user.id),
      sid: sessionId,
      role: user.role,
      tokenType: 'refresh',
    },
    env.jwtRefreshSecret,
    { expiresIn: env.jwtRefreshTtl },
  );

  try {
    // WHY: Store only a hash of the refresh token so database leakage does not expose a usable credential.
    logInfo({
      ...logContext,
      step: LOG_STEPS.DB_QUERY_START,
      layer: 'service',
      operation: 'IssueSessionTokens',
      intent: 'Persist the refresh session so logout and rotation remain enforceable',
    });

    await RefreshSession.create({
      sessionId,
      user: user._id || user.id,
      tokenHash: hashValue(refreshToken),
      ipAddress: meta.ipAddress || '',
      userAgent: meta.userAgent || '',
      expiresAt: decodeExpiryDate(refreshToken),
    });

    logInfo({
      ...logContext,
      step: LOG_STEPS.DB_QUERY_OK,
      layer: 'service',
      operation: 'IssueSessionTokens',
      intent: 'Confirm the refresh session is stored before returning credentials',
    });
  } catch (error) {
    // WHY: Abort login when session persistence fails, otherwise refresh and logout would become unreliable.
    logError({
      ...logContext,
      step: LOG_STEPS.DB_QUERY_FAIL,
      layer: 'service',
      operation: 'IssueSessionTokens',
      intent: 'Stop login flows when the refresh session cannot be persisted',
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      error_code: 'AUTH_REFRESH_SESSION_CREATE_FAILED',
      resolution_hint: 'Check MongoDB connectivity and try logging in again',
      message: error.message,
    });

    throw new AppError({
      message: 'We could not start your session',
      statusCode: 503,
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      errorCode: 'AUTH_REFRESH_SESSION_CREATE_FAILED',
      resolutionHint: 'Try again in a moment',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  // WHY: Issue the short-lived access token only after the refresh session is safely stored.
  const accessToken = createAccessToken(user);

  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_OK,
    layer: 'service',
    operation: 'IssueSessionTokens',
    intent: 'Return a complete authenticated session payload',
  });

  return { accessToken, refreshToken };
}

async function revokeSessionById(sessionId, logContext) {
  if (!sessionId) {
    return;
  }

  // WHY: Revoke by session id so only the intended browser session is invalidated.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'RevokeRefreshSession',
    intent: 'Invalidate the current refresh session so it cannot be reused',
  });

  await RefreshSession.findOneAndUpdate(
    { sessionId, revokedAt: null },
    { revokedAt: new Date() },
    { new: true },
  );

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'RevokeRefreshSession',
    intent: 'Confirm the refresh session has been invalidated',
  });
}

function verifyRefreshToken(refreshToken) {
  try {
    // WHY: Verify the signature before any database lookup so forged refresh tokens fail cheaply and early.
    return jwt.verify(refreshToken, env.jwtRefreshSecret);
  } catch (error) {
    throw new AppError({
      message: 'Your session has expired',
      statusCode: 401,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'AUTH_REFRESH_TOKEN_INVALID',
      resolutionHint: 'Log in again to continue',
      step: LOG_STEPS.AUTH_FAIL,
    });
  }
}

async function rotateRefreshSession(refreshToken, meta, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'RotateRefreshSession',
    intent: 'Exchange a valid refresh token for a fresh authenticated session',
  });

  // WHY: Decode and verify the refresh token before trusting any session id in it.
  const payload = verifyRefreshToken(refreshToken);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'RotateRefreshSession',
    intent: 'Load the persisted refresh session before issuing a replacement token',
  });

  const session = await RefreshSession.findOne({
    sessionId: payload.sid,
    user: payload.sub,
  }).populate('user');

  // WHY: Reject revoked, expired, or mismatched refresh tokens so replay attempts cannot mint new sessions.
  if (!session || session.revokedAt || session.tokenHash !== hashValue(refreshToken) || session.expiresAt <= new Date()) {
    throw new AppError({
      message: 'Your session can no longer be refreshed',
      statusCode: 401,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'AUTH_REFRESH_SESSION_INVALID',
      resolutionHint: 'Log in again to continue',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'RotateRefreshSession',
      intent: 'Confirm the existing refresh session is valid before rotation',
  });

  // WHY: Revoke the old session before issuing a replacement so refresh rotation stays one-time-use.
  await revokeSessionById(payload.sid, logContext);

  // WHY: Refresh must not silently reactivate accounts that were disabled after login.
  if (!session.user || session.user.status !== 'active') {
    throw new AppError({
      message: 'Your account is not active',
      statusCode: 403,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'AUTH_REFRESH_USER_INACTIVE',
      resolutionHint: 'Contact an administrator if you believe this is a mistake',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  // WHY: Reuse the standard session issuance path so login and refresh stay identical.
  return issueSessionTokens(session.user, meta, logContext);
}

async function revokeRefreshSession(refreshToken, logContext) {
  if (!refreshToken) {
    return;
  }

  try {
    // WHY: Revoke the persisted refresh session when the cookie is still valid and decodable.
    const payload = verifyRefreshToken(refreshToken);
    await revokeSessionById(payload.sid, logContext);
  } catch (error) {
    // WHY: Logout stays idempotent, so expired or bad cookies still count as already signed out.
    logInfo({
      ...logContext,
      step: LOG_STEPS.SERVICE_OK,
      layer: 'service',
      operation: 'RevokeRefreshSession',
      intent: 'Treat missing or expired refresh tokens as already logged out',
    });
  }
}

function signStaffInviteToken(invite) {
  // WHY: Sign invite claims so registration links cannot be forged or edited client-side.
  return jwt.sign(
    {
      inviteId: invite.inviteId,
      email: invite.email,
      tokenType: 'staff_invite',
    },
    env.jwtInviteSecret,
    { expiresIn: `${env.staffInviteTtlHours}h` },
  );
}

function verifyStaffInviteToken(inviteToken) {
  try {
    // WHY: Verify the invite token before any database lookup so only trusted invite ids reach MongoDB.
    return jwt.verify(inviteToken, env.jwtInviteSecret);
  } catch (error) {
    throw new AppError({
      message: 'This staff invite is invalid or expired',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_REGISTER_INVITE_INVALID',
      resolutionHint: 'Ask an admin to create a new invite link',
      step: LOG_STEPS.AUTH_FAIL,
    });
  }
}

function buildFrontendHashRoute(pathname) {
  // WHY: Flutter web currently uses hash-based routing, so invite links must include `/#/` to land on the intended screen.
  const baseUrl = String(env.frontendAppUrl || '').replace(/\/+$/, '');
  const normalizedPath = String(pathname || '').replace(/^\/+/, '');

  if (baseUrl.includes('/#/')) {
    return `${baseUrl}/${normalizedPath}`;
  }

  if (baseUrl.endsWith('/#')) {
    return `${baseUrl}/${normalizedPath}`;
  }

  return `${baseUrl}/#/${normalizedPath}`;
}

function buildStaffInviteLink(invite) {
  // WHY: Keep invite-link construction centralized so route changes happen in one place later.
  const token = signStaffInviteToken(invite);
  return buildFrontendHashRoute(`staff/register/${token}`);
}

function setRefreshCookie(res, refreshToken) {
  // WHY: Keep the refresh cookie HTTP-only so the browser can send it without exposing it to UI code.
  res.cookie(env.authCookieName, refreshToken, {
    httpOnly: true,
    secure: env.nodeEnv === 'production',
    sameSite: 'lax',
    path: '/api/v1/auth',
    maxAge: 7 * 24 * 60 * 60 * 1000,
  });
}

function clearRefreshCookie(res) {
  // WHY: Clear the cookie with the same attributes used when setting it so browsers actually remove it.
  res.clearCookie(env.authCookieName, {
    httpOnly: true,
    secure: env.nodeEnv === 'production',
    sameSite: 'lax',
    path: '/api/v1/auth',
  });
}

module.exports = {
  buildStaffInviteLink,
  clearRefreshCookie,
  issueSessionTokens,
  rotateRefreshSession,
  revokeRefreshSession,
  setRefreshCookie,
  verifyStaffInviteToken,
};
