/**
 * WHAT: Implements customer registration, shared login, logout, refresh, and session bootstrap.
 * WHY: Authentication should stay in one service so every role follows the same security rules.
 * HOW: Validate account state, hash/check passwords, issue tokens, and return safe user payloads.
 */

const bcrypt = require("bcryptjs");

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  USER_ROLES,
  USER_STATUSES,
} = require("../constants/app.constants");
const {
  User,
} = require("../models/user.model");
const {
  AppError,
} = require("../utils/app-error");
const {
  logError,
  logInfo,
} = require("../utils/logger");
const {
  serializeUser,
} = require("../utils/serializers");
const {
  issueSessionTokens,
  revokeRefreshSession,
  rotateRefreshSession,
} = require("./token.service");

async function registerCustomer(
  payload,
  meta,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "RegisterCustomer",
    intent:
      "Create the customer account before the first service request is submitted",
  });

  // WHY: Check email ownership first so registration never creates duplicate customer accounts.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "RegisterCustomer",
    intent:
      "Check whether the requested customer email is already in use",
  });

  const existingUser =
    await User.findOne({
      email:
        payload.email.toLowerCase(),
    });

  // WHY: Stop here so the UI gets a clear account-exists answer before any password work happens.
  if (existingUser) {
    throw new AppError({
      message:
        "An account with this email already exists",
      statusCode: 409,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode:
        "CUSTOMER_REGISTER_EMAIL_TAKEN",
      resolutionHint:
        "Log in instead or use a different email address",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "RegisterCustomer",
    intent:
      "Confirm the new customer email is available",
  });

  // WHY: Hash the password only after uniqueness passes so rejected sign-ups do not waste crypto work.
  const passwordHash =
    await bcrypt.hash(
      payload.password,
      12,
    );

  // WHY: Persist the account in one place so later request flows can trust a real customer record exists.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "RegisterCustomer",
    intent:
      "Persist the new customer account in MongoDB",
  });

  const user = await User.create({
    firstName: payload.firstName,
    lastName: payload.lastName,
    email: payload.email.toLowerCase(),
    phone: payload.phone || "",
    role: USER_ROLES.CUSTOMER,
    status: USER_STATUSES.ACTIVE,
    passwordHash,
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "RegisterCustomer",
    intent:
      "Confirm the customer account was saved successfully",
  });

  // WHY: Start a session immediately so the new customer can continue without a second login step.
  const tokens =
    await issueSessionTokens(
      user,
      meta,
      logContext,
    );

  return {
    message:
      "Customer registered successfully",
    user: serializeUser(user),
    ...tokens,
  };
}

async function loginUser(
  payload,
  meta,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "LoginUser",
    intent:
      "Authenticate any active admin, staff, or customer user",
  });

  // WHY: Load the hidden password hash explicitly because normal queries never expose credential material.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "LoginUser",
    intent:
      "Load the matching account with its password hash for credential verification",
  });

  const user = await User.findOne({
    email: payload.email.toLowerCase(),
  }).select("+passwordHash");

  // WHY: Keep the failure generic so callers cannot discover which emails exist in the system.
  if (!user || !user.passwordHash) {
    throw new AppError({
      message:
        "Invalid email or password",
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_LOGIN_INVALID_CREDENTIALS",
      resolutionHint:
        "Check your email and password and try again",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "LoginUser",
    intent:
      "Confirm the account record is available for password comparison",
  });

  // WHY: Compare the submitted password only after the trusted account record is loaded.
  const passwordMatches =
    await bcrypt.compare(
      payload.password,
      user.passwordHash,
    );

  // WHY: Reuse the same safe message for a bad password so account discovery remains difficult.
  if (!passwordMatches) {
    throw new AppError({
      message:
        "Invalid email or password",
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_LOGIN_INVALID_CREDENTIALS",
      resolutionHint:
        "Check your email and password and try again",
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  // WHY: Block inactive accounts even if the credentials are valid so invite and disable states are respected.
  if (
    user.status !== USER_STATUSES.ACTIVE
  ) {
    throw new AppError({
      message:
        "Your account is not active",
      statusCode: 403,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_LOGIN_USER_INACTIVE",
      resolutionHint:
        "Complete your invite flow or contact an administrator",
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  // WHY: Keep token issuance centralized so login and refresh follow the same session rules.
  const tokens =
    await issueSessionTokens(
      user,
      meta,
      logContext,
    );

  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_OK,
    layer: "service",
    operation: "LoginUser",
    intent:
      "Return an authenticated session for the verified account",
  });

  return {
    message: "Login successful",
    user: serializeUser(user),
    ...tokens,
  };
}

async function refreshAuth(
  refreshToken,
  meta,
  logContext,
) {
  // WHY: Rotate the refresh session first so replayed refresh cookies stop working immediately.
  const tokens =
    await rotateRefreshSession(
      refreshToken,
      meta,
      logContext,
    );

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "RefreshAuth",
    intent:
      "Load the current user record after refresh-token rotation",
  });

  // WHY: Re-read the user from MongoDB so the client gets the latest persisted profile and role state.
  const decoded = await User.findById(
    jwtSafeSubject(tokens.accessToken),
  );
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "RefreshAuth",
    intent:
      "Confirm the refreshed session still maps to a valid user",
  });

  return {
    message:
      "Session refreshed successfully",
    user: serializeUser(decoded),
    ...tokens,
  };
}

function jwtSafeSubject(accessToken) {
  const tokenParts =
    accessToken.split(".");

  // WHY: Guard malformed access tokens before attempting to decode the payload segment.
  if (tokenParts.length < 2) {
    throw new AppError({
      message:
        "Unable to refresh this session",
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_REFRESH_ACCESS_DECODE_FAILED",
      resolutionHint:
        "Log in again to continue",
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  // WHY: Extract the signed subject so refresh uses the same identity encoded in the issued access token.
  const payload = JSON.parse(
    Buffer.from(
      tokenParts[1],
      "base64url",
    ).toString("utf8"),
  );
  return payload.sub;
}

async function logoutUser(
  refreshToken,
  logContext,
) {
  // WHY: Reuse refresh-session revocation so logout and token invalidation follow one path.
  await revokeRefreshSession(
    refreshToken,
    logContext,
  );

  return {
    message: "Logout successful",
  };
}

async function getCurrentUser(
  userId,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "GetCurrentUser",
    intent:
      "Bootstrap the frontend session with the current authenticated user",
  });

  // WHY: Resolve the user from MongoDB so deleted accounts are caught before the frontend trusts the session.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "GetCurrentUser",
    intent:
      "Load the authenticated user record for session bootstrap",
  });

  const user =
    await User.findById(userId);

  // WHY: Convert stale-token lookups into a controlled auth error before any client bootstrap continues.
  if (!user) {
    logError({
      ...logContext,
      step: LOG_STEPS.DB_QUERY_FAIL,
      layer: "service",
      operation: "GetCurrentUser",
      intent:
        "Reject stale access tokens that reference a missing account",
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      error_code:
        "AUTH_ME_USER_NOT_FOUND",
      resolution_hint:
        "Log in again to continue",
      message:
        "Authenticated user was not found",
    });

    throw new AppError({
      message:
        "Authenticated user not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_ME_USER_NOT_FOUND",
      resolutionHint:
        "Log in again to continue",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "GetCurrentUser",
    intent:
      "Confirm the frontend can bootstrap from a valid user record",
  });

  // WHY: Return the serialized user shape so the frontend never depends on raw Mongoose documents.
  return {
    message:
      "Authenticated user fetched successfully",
    user: serializeUser(user),
  };
}

module.exports = {
  getCurrentUser,
  loginUser,
  logoutUser,
  refreshAuth,
  registerCustomer,
};
