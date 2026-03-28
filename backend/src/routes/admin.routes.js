/**
 * WHAT: Registers admin-only endpoints for dashboard data, request assignment, and staff management.
 * WHY: Admin routes need shared auth and role guards before any operational actions run.
 * HOW: Gate the router with admin authorization and then attach validators plus controllers per endpoint.
 */

const express = require("express");

const {
  adminAssignRequestController,
  adminCreateRequestInvoiceController,
  adminCreateStaffInviteController,
  adminDeleteStaffInviteController,
  adminDashboardController,
  adminListRequestsController,
  adminListStaffController,
  adminListStaffInvitesController,
  adminReviewPaymentProofController,
} = require("../controllers/admin.controller");
const {
  createDirectInternalChatController,
  createGroupInternalChatController,
  listInternalChatsController,
  markInternalChatReadController,
  postInternalChatMessageController,
} = require("../controllers/internal-chat.controller");
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
  adminCreateRequestInvoiceValidator,
  adminCreateStaffInviteValidator,
  adminDeleteStaffInviteValidator,
  adminRequestFiltersValidator,
  adminReviewPaymentProofValidator,
} = require("../validators/admin.validators");
const {
  createDirectInternalChatValidator,
  createGroupInternalChatValidator,
  markInternalChatReadValidator,
  postInternalChatMessageValidator,
} = require("../validators/internal-chat.validators");

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
  router.post(
    "/requests/:requestId/invoice",
    adminCreateRequestInvoiceValidator,
    validateRequest,
    adminCreateRequestInvoiceController,
  );
  router.patch(
    "/requests/:requestId/invoice/proof/review",
    adminReviewPaymentProofValidator,
    validateRequest,
    adminReviewPaymentProofController,
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
  router.get(
    "/internal-chats",
    listInternalChatsController,
  );
  router.post(
    "/internal-chats/direct",
    createDirectInternalChatValidator,
    validateRequest,
    createDirectInternalChatController,
  );
  router.post(
    "/internal-chats/groups",
    createGroupInternalChatValidator,
    validateRequest,
    createGroupInternalChatController,
  );
  router.post(
    "/internal-chats/:threadId/messages",
    postInternalChatMessageValidator,
    validateRequest,
    postInternalChatMessageController,
  );
  router.post(
    "/internal-chats/:threadId/read",
    markInternalChatReadValidator,
    validateRequest,
    markInternalChatReadController,
  );

  return router;
}

module.exports = { createAdminRouter };
