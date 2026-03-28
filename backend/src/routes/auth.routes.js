/**
 * WHAT: Registers auth endpoints for customer registration, login, refresh, logout, and session bootstrap.
 * WHY: Auth routes need consistent middleware ordering for rate limits, validation, and protected access.
 * HOW: Compose validators and middleware around thin controllers for each auth contract.
 */

const express = require("express");

const {
  loginController,
  logoutController,
  meController,
  refreshController,
  registerCustomerController,
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
  loginValidator,
} = require("../validators/auth.validators");

function createAuthRouter() {
  const router = express.Router();
  const authRateLimit =
    createAuthRateLimitMiddleware();

  router.post(
    "/customer/register",
    authRateLimit,
    customerRegisterValidator,
    validateRequest,
    registerCustomerController,
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
