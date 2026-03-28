/**
 * WHAT: Registers admin-only endpoints for dashboard data, request assignment, and staff management.
 * WHY: Admin routes need shared auth and role guards before any operational actions run.
 * HOW: Gate the router with admin authorization and then attach validators plus controllers per endpoint.
 */

const express = require("express");

const {
  adminAssignRequestController,
  adminCreateStaffInviteController,
  adminDeleteStaffInviteController,
  adminDashboardController,
  adminListRequestsController,
  adminListStaffController,
  adminListStaffInvitesController,
} = require("../controllers/admin.controller");
const {
  USER_ROLES,
} = require("../constants/app.constants");
const {
  requireAuth,
  requireRoles,
} = require("../middleware/auth.middleware");
const {
  validateRequest,
} = require("../middleware/validate.middleware");
const {
  adminAssignRequestValidator,
  adminCreateStaffInviteValidator,
  adminDeleteStaffInviteValidator,
  adminRequestFiltersValidator,
} = require("../validators/admin.validators");

function createAdminRouter() {
  const router = express.Router();

  router.use(
    requireAuth,
    requireRoles([USER_ROLES.ADMIN]),
  );

  router.get(
    "/dashboard",
    adminDashboardController,
  );
  router.get(
    "/requests",
    adminRequestFiltersValidator,
    validateRequest,
    adminListRequestsController,
  );
  router.patch(
    "/requests/:requestId/assign",
    adminAssignRequestValidator,
    validateRequest,
    adminAssignRequestController,
  );
  router.get(
    "/staff",
    adminListStaffController,
  );
  router.post(
    "/staff/invites",
    adminCreateStaffInviteValidator,
    validateRequest,
    adminCreateStaffInviteController,
  );
  router.delete(
    "/staff/invites/:inviteId",
    adminDeleteStaffInviteValidator,
    validateRequest,
    adminDeleteStaffInviteController,
  );
  router.get(
    "/staff/invites",
    adminListStaffInvitesController,
  );

  return router;
}

module.exports = { createAdminRouter };
