/**
 * WHAT: Handles HTTP requests for customer registration and shared authentication flows.
 * WHY: Controllers should translate request/response concerns without owning auth business logic.
 * HOW: Build request-aware log context, delegate to services, and shape the auth response contract.
 */

const { LOG_STEPS } = require('../constants/app.constants');
const { env } = require('../config/env');
const { asyncHandler } = require('../utils/async-handler');
const { buildRequestLog, logInfo } = require('../utils/logger');
const { clearRefreshCookie, setRefreshCookie } = require('../services/token.service');
const authService = require('../services/auth.service');

function buildClientMeta(req) {
  return {
    // WHY: Persist request origin hints with sessions so refresh-token misuse can be investigated later.
    ipAddress: req.ip,
    userAgent: req.headers['user-agent'] || 'unknown',
  };
}

const registerCustomerController = asyncHandler(async (req, res) => {
  // WHY: Build one request-aware context so every auth log line carries the same tracing metadata.
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'RegisterCustomer',
    intent: 'Register a customer and start a session before service-request submission',
  });

  // WHY: Keep account creation inside the service so the controller only owns HTTP concerns.
  const result = await authService.registerCustomer(req.body, buildClientMeta(req), logContext);
  // WHY: Set the refresh cookie here so the browser can silently refresh without exposing the token to UI code.
  setRefreshCookie(res, result.refreshToken);

  // WHY: Return only the public auth contract instead of the internal refresh token.
  res.status(201).json({
    message: result.message,
    user: result.user,
    accessToken: result.accessToken,
  });

  // WHY: Emit the response checkpoint after the HTTP body is shaped and ready for the client.
  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const requestCustomerRegistrationCodeController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'RequestCustomerRegistrationCode',
    intent: 'Send a customer registration verification code before account creation',
  });

  const result = await authService.requestCustomerRegistrationCode(
    req.body,
    logContext,
  );

  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const verifyCustomerRegistrationCodeController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'VerifyCustomerRegistrationCode',
    intent: 'Verify the customer registration email code before account creation',
  });

  const result = await authService.verifyCustomerRegistrationCode(
    req.body,
    logContext,
  );

  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const demoAccountsController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'GetDemoAccounts',
    intent: 'Provide quick-fill login accounts for the requested public auth role',
  });

  // WHY: Keep the role lookup and response shaping in the service so the controller only owns the public HTTP contract.
  const result = await authService.getDemoAccounts(req.params.role, logContext);

  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const loginController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'LoginUser',
    intent: 'Authenticate an admin, staff, or customer account',
  });

  // WHY: Delegate credential checks and token issuance so auth policy stays in one service.
  const result = await authService.loginUser(req.body, buildClientMeta(req), logContext);
  // WHY: Refresh tokens stay in cookies so the frontend only handles short-lived access tokens directly.
  setRefreshCookie(res, result.refreshToken);

  res.status(200).json({
    message: result.message,
    user: result.user,
    accessToken: result.accessToken,
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const refreshController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'RefreshAuth',
    intent: 'Rotate the refresh session and recover an authenticated client state',
  });

  // WHY: Read the refresh token from the HTTP-only cookie so clients cannot forge refresh payloads in the body.
  const result = await authService.refreshAuth(req.cookies[env.authCookieName], buildClientMeta(req), logContext);
  // WHY: Replace the old refresh cookie immediately after rotation so only the newest session remains valid.
  setRefreshCookie(res, result.refreshToken);

  res.status(200).json({
    message: result.message,
    user: result.user,
    accessToken: result.accessToken,
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const logoutController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'LogoutUser',
    intent: 'End the current authenticated session safely',
  });

  // WHY: Revoke the server-side refresh session before clearing the browser cookie.
  const result = await authService.logoutUser(req.cookies[env.authCookieName], logContext);
  // WHY: Clear the cookie even when the server session was already expired so logout remains predictable.
  clearRefreshCookie(res);

  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const meController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'GetCurrentUser',
    intent: 'Bootstrap the authenticated frontend experience with the current user',
  });

  // WHY: Load the current user server-side so the frontend does not trust stale access-token claims alone.
  const result = await authService.getCurrentUser(req.authUser.id, logContext);

  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

module.exports = {
  demoAccountsController,
  loginController,
  logoutController,
  meController,
  refreshController,
  registerCustomerController,
  requestCustomerRegistrationCodeController,
  verifyCustomerRegistrationCodeController,
};
