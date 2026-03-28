/**
 * WHAT: Registers public invite-registration and protected staff request-management routes.
 * WHY: Staff onboarding and dashboard access have different auth requirements but share one domain.
 * HOW: Keep public registration separate, then protect the remaining routes with staff-only guards.
 */

const express = require("express");

const {
  staffAttendQueueRequestController,
  staffDashboardController,
  staffListRequestsController,
  staffPostRequestMessageController,
  staffRegisterController,
  staffUpdateAvailabilityController,
  staffUpdateRequestStatusController,
} = require("../controllers/staff.controller");
const {
  USER_ROLES,
} = require("../constants/app.constants");
const {
  requireAuth,
  requireRoles,
} = require("../middleware/auth.middleware");
const {
  createAuthRateLimitMiddleware,
} = require("../middleware/auth-rate-limit.middleware");
const {
  validateRequest,
} = require("../middleware/validate.middleware");
const {
  staffAttendQueueRequestValidator,
  staffPostRequestMessageValidator,
  staffRegisterValidator,
  staffRequestFiltersValidator,
  staffUpdateAvailabilityValidator,
  staffUpdateRequestStatusValidator,
} = require("../validators/staff.validators");

function createStaffRouter() {
  const router = express.Router();
  const authRateLimit =
    createAuthRateLimitMiddleware();

  router.post(
    "/register",
    authRateLimit,
    staffRegisterValidator,
    validateRequest,
    staffRegisterController,
  );

  router.use(
    requireAuth,
    requireRoles([USER_ROLES.STAFF]),
  );

  router.get(
    "/dashboard",
    staffDashboardController,
  );
  router.patch(
    "/availability",
    staffUpdateAvailabilityValidator,
    validateRequest,
    staffUpdateAvailabilityController,
  );
  router.post(
    "/queue/:requestId/attend",
    staffAttendQueueRequestValidator,
    validateRequest,
    staffAttendQueueRequestController,
  );
  router.get(
    "/requests",
    staffRequestFiltersValidator,
    validateRequest,
    staffListRequestsController,
  );
  router.patch(
    "/requests/:requestId/status",
    staffUpdateRequestStatusValidator,
    validateRequest,
    staffUpdateRequestStatusController,
  );
  router.post(
    "/requests/:requestId/messages",
    staffPostRequestMessageValidator,
    validateRequest,
    staffPostRequestMessageController,
  );

  return router;
}

module.exports = { createStaffRouter };
