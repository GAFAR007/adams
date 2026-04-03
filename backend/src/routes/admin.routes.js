/**
 * WHAT: Registers admin-only endpoints for dashboard data, request assignment, and staff management.
 * WHY: Admin routes need shared auth and role guards before any operational actions run.
 * HOW: Gate the router with admin authorization and then attach validators plus controllers per endpoint.
 */

const express = require("express");

const {
  adminAssignRequestController,
  adminCalendarController,
  adminCreateRequestInvoiceController,
  adminCreateStaffInviteController,
  adminDeliverRequestController,
  adminDeleteStaffInviteController,
  adminDashboardController,
  adminListRequestsController,
  adminPostRequestMessageController,
  adminListStaffController,
  adminListStaffInvitesController,
  adminReviewPaymentProofController,
  adminSelectRequestEstimationController,
  adminUploadRequestAttachmentController,
} = require("../controllers/admin.controller");
const {
  createDirectInternalChatController,
  createGroupInternalChatController,
  listInternalChatsController,
  markInternalChatReadController,
  postInternalChatMessageController,
  suggestInternalChatReplyController,
  uploadInternalChatAttachmentController,
} = require("../controllers/internal-chat.controller");
const {
  USER_ROLES,
} = require("../constants/app.constants");
const {
  requestAttachmentUploadMiddleware,
} = require("../middleware/upload.middleware");
const {
  requireAuth,
  requireRoles,
} = require("../middleware/auth.middleware");
const {
  validateRequest,
} = require("../middleware/validate.middleware");
const {
  adminAssignRequestValidator,
  adminCalendarFiltersValidator,
  adminCreateRequestInvoiceValidator,
  adminCreateStaffInviteValidator,
  adminDeliverRequestValidator,
  adminDeleteStaffInviteValidator,
  adminPostRequestMessageValidator,
  adminRequestFiltersValidator,
  adminReviewPaymentProofValidator,
  adminSelectRequestEstimationValidator,
  adminUploadRequestAttachmentValidator,
} = require("../validators/admin.validators");
const {
  createDirectInternalChatValidator,
  createGroupInternalChatValidator,
  markInternalChatReadValidator,
  postInternalChatMessageValidator,
  suggestInternalChatReplyValidator,
  uploadInternalChatAttachmentValidator,
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
    "/calendar",
    adminCalendarFiltersValidator,
    validateRequest,
    adminCalendarController,
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
  router.patch(
    "/requests/:requestId/deliver",
    adminDeliverRequestValidator,
    validateRequest,
    adminDeliverRequestController,
  );
  router.patch(
    "/requests/:requestId/estimations/select",
    adminSelectRequestEstimationValidator,
    validateRequest,
    adminSelectRequestEstimationController,
  );
  router.post(
    "/requests/:requestId/messages",
    adminPostRequestMessageValidator,
    validateRequest,
    adminPostRequestMessageController,
  );
  router.post(
    "/requests/:requestId/messages/attachment",
    requestAttachmentUploadMiddleware,
    adminUploadRequestAttachmentValidator,
    validateRequest,
    adminUploadRequestAttachmentController,
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
    "/internal-chats/:threadId/messages/attachment",
    requestAttachmentUploadMiddleware,
    uploadInternalChatAttachmentValidator,
    validateRequest,
    uploadInternalChatAttachmentController,
  );
  router.post(
    "/internal-chats/:threadId/reply-assistant",
    suggestInternalChatReplyValidator,
    validateRequest,
    suggestInternalChatReplyController,
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
