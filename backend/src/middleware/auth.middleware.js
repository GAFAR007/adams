/**
 * WHAT: Enforces access-token authentication and role-based authorization.
 * WHY: Admin, staff, and customer areas need explicit protection before business logic runs.
 * HOW: Verify bearer tokens, attach the authenticated user context, and guard allowed roles.
 */

const jwt = require("jsonwebtoken");

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
} = require("../constants/app.constants");
const {
  env,
} = require("../config/env");
const {
  AppError,
} = require("../utils/app-error");
const {
  buildRequestLog,
  logInfo,
} = require("../utils/logger");

function requireAuth(req, res, next) {
  void res;

  const authorization =
    req.headers.authorization || "";
  const [scheme, token] =
    authorization.split(" ");

  // WHY: Reject malformed auth headers early so protected handlers never guess at caller identity.
  if (scheme !== "Bearer" || !token) {
    throw new AppError({
      message:
        "Authentication is required",
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_ACCESS_TOKEN_MISSING",
      resolutionHint:
        "Send a valid bearer access token",
      step: LOG_STEPS.AUTH_FAIL,
    });
  }

  try {
    // WHY: Verify the signed access token before trusting any user or role claims from the request.
    const payload = jwt.verify(
      token,
      env.jwtAccessSecret,
    );

    // WHY: Store only the minimum trusted auth context needed by downstream guards and services.
    req.authUser = {
      id: payload.sub,
      role: payload.role,
      email: payload.email,
    };

    // WHY: Emit an explicit auth success checkpoint so protected-request traces show access was granted.
    logInfo(
      buildRequestLog(req, {
        step: LOG_STEPS.AUTH_OK,
        layer: "middleware",
        operation: "RequireAuth",
        intent:
          "Allow authenticated access to protected resources",
      }),
    );

    next();
  } catch (error) {
    // WHY: Convert token verification failures into the shared safe auth error contract.
    throw new AppError({
      message: "Authentication failed",
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_ACCESS_TOKEN_INVALID",
      resolutionHint:
        "Log in again to obtain a fresh access token",
      step: LOG_STEPS.AUTH_FAIL,
    });
  }
}

function requireRoles(allowedRoles) {
  return function roleGuard(
    req,
    res,
    next,
  ) {
    void res;

    // WHY: Enforce role checks after auth so controllers do not need to duplicate access rules.
    if (
      !req.authUser ||
      !allowedRoles.includes(
        req.authUser.role,
      )
    ) {
      throw new AppError({
        message:
          "You do not have access to this resource",
        statusCode: 403,
        classification:
          ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
        errorCode:
          "AUTH_ROLE_FORBIDDEN",
        resolutionHint:
          "Use an account with the correct role for this action",
        step: LOG_STEPS.AUTH_FAIL,
      });
    }

    // WHY: Only hand off to the next layer when both authentication and role authorization passed.
    next();
  };
}

module.exports = {
  requireAuth,
  requireRoles,
};
