/**
 * WHAT: Registers auth endpoints for customer registration, login, refresh, logout, and session bootstrap.
 * WHY: Auth routes need consistent middleware ordering for rate limits, validation, and protected access.
 * HOW: Compose validators and middleware around thin controllers for each auth contract.
 */

const express = require("express");

const {
  demoAccountsController,
  loginController,
  logoutController,
  meController,
  refreshController,
  registerCustomerController,
  requestCustomerRegistrationCodeController,
  verifyCustomerRegistrationCodeController,
} = require("../controllers/auth.controller");
const {
  requireAuth,
} = require("../middleware/auth.middleware");
const {
  createAuthRateLimitMiddleware,
} = require("../middleware/auth-rate-limit.middleware");
const {
  validateRequest,
} = require("../middleware/validate.middleware");
const {
  customerRegisterValidator,
  customerRegistrationCodeRequestValidator,
  customerRegistrationCodeVerifyValidator,
  demoAccountsValidator,
  loginValidator,
} = require("../validators/auth.validators");

function createAuthRouter() {
  const router = express.Router();
  const authRateLimit =
    createAuthRateLimitMiddleware();

  router.post(
    "/customer/register/request-code",
    authRateLimit,
    customerRegistrationCodeRequestValidator,
    validateRequest,
    requestCustomerRegistrationCodeController,
  );
  router.post(
    "/customer/register/verify-code",
    authRateLimit,
    customerRegistrationCodeVerifyValidator,
    validateRequest,
    verifyCustomerRegistrationCodeController,
  );
  router.post(
    "/customer/register",
    authRateLimit,
    customerRegisterValidator,
    validateRequest,
    registerCustomerController,
  );
  router.get(
    "/demo-accounts/:role",
    demoAccountsValidator,
    validateRequest,
    demoAccountsController,
  );
  router.post(
    "/login",
    authRateLimit,
    loginValidator,
    validateRequest,
    loginController,
  );
  router.post(
    "/refresh",
    authRateLimit,
    refreshController,
  );
  router.post(
    "/logout",
    logoutController,
  );
  router.get(
    "/me",
    requireAuth,
    meController,
  );

  return router;
}

module.exports = { createAuthRouter };
