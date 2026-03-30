/**
 * WHAT: Registers public invite-registration and protected staff request-management routes.
 * WHY: Staff onboarding and dashboard access have different auth requirements but share one domain.
 * HOW: Keep public registration separate, then protect the remaining routes with staff-only guards.
 */

const express = require("express");

const {
  staffAttendQueueRequestController,
  staffCreateRequestInvoiceController,
  staffDashboardController,
  staffListRequestsController,
  staffPostRequestMessageController,
  staffReviewPaymentProofController,
  staffRegisterController,
  staffUploadRequestAttachmentController,
  staffUpdateAvailabilityController,
  staffUpdateRequestAiControlController,
  staffUpdateRequestStatusController,
} = require("../controllers/staff.controller");
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
  requestAttachmentUploadMiddleware,
} = require("../middleware/upload.middleware");
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
  staffCreateRequestInvoiceValidator,
  staffPostRequestMessageValidator,
  staffReviewPaymentProofValidator,
  staffRegisterValidator,
  staffRequestFiltersValidator,
  staffUploadRequestAttachmentValidator,
  staffUpdateAvailabilityValidator,
  staffUpdateRequestAiControlValidator,
  staffUpdateRequestStatusValidator,
} = require("../validators/staff.validators");
const {
  createDirectInternalChatValidator,
  createGroupInternalChatValidator,
  markInternalChatReadValidator,
  postInternalChatMessageValidator,
} = require("../validators/internal-chat.validators");

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
  router.post(
    "/requests/:requestId/messages/attachment",
    requestAttachmentUploadMiddleware,
    staffUploadRequestAttachmentValidator,
    validateRequest,
    staffUploadRequestAttachmentController,
  );
  router.patch(
    "/requests/:requestId/ai-control",
    staffUpdateRequestAiControlValidator,
    validateRequest,
    staffUpdateRequestAiControlController,
  );
  router.post(
    "/requests/:requestId/invoice",
    staffCreateRequestInvoiceValidator,
    validateRequest,
    staffCreateRequestInvoiceController,
  );
  router.patch(
    "/requests/:requestId/invoice/proof/review",
    staffReviewPaymentProofValidator,
    validateRequest,
    staffReviewPaymentProofController,
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

module.exports = { createStaffRouter };
