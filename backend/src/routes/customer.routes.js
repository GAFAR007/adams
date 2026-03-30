/**
 * WHAT: Registers customer-only endpoints for service-request creation and listing.
 * WHY: Customer request ownership must be protected from other roles and anonymous traffic.
 * HOW: Apply customer auth guards, validate request payloads, and delegate to customer controllers.
 */

const express = require("express");

const {
  customerCreateRequestController,
  customerListRequestsController,
  customerPostRequestMessageController,
  customerReplaceRequestAttachmentController,
  customerUploadPaymentProofController,
  customerUploadRequestAttachmentController,
  customerUpdateRequestController,
  customerAutocompleteAddressController,
  customerVerifyAddressController,
} = require("../controllers/customer.controller");
const {
  USER_ROLES,
} = require("../constants/app.constants");
const {
  requireAuth,
  requireRoles,
} = require("../middleware/auth.middleware");
const {
  paymentProofUploadMiddleware,
  requestAttachmentUploadMiddleware,
} = require("../middleware/upload.middleware");
const {
  validateRequest,
} = require("../middleware/validate.middleware");
const {
  customerCreateRequestValidator,
  customerPostRequestMessageValidator,
  customerUploadPaymentProofValidator,
  customerUploadRequestAttachmentValidator,
  customerReplaceRequestAttachmentValidator,
  customerUpdateRequestValidator,
  customerAutocompleteAddressValidator,
  customerVerifyAddressValidator,
} = require("../validators/customer.validators");

function createCustomerRouter() {
  const router = express.Router();

  router.use(
    requireAuth,
    requireRoles([USER_ROLES.CUSTOMER]),
  );

  router.post(
    "/requests",
    customerCreateRequestValidator,
    validateRequest,
    customerCreateRequestController,
  );
  router.get(
    "/requests",
    customerListRequestsController,
  );
  router.get(
    "/address/autocomplete",
    customerAutocompleteAddressValidator,
    validateRequest,
    customerAutocompleteAddressController,
  );
  router.post(
    "/address/verify",
    customerVerifyAddressValidator,
    validateRequest,
    customerVerifyAddressController,
  );
  router.patch(
    "/requests/:requestId",
    customerUpdateRequestValidator,
    validateRequest,
    customerUpdateRequestController,
  );
  router.post(
    "/requests/:requestId/invoice/proof",
    paymentProofUploadMiddleware,
    customerUploadPaymentProofValidator,
    validateRequest,
    customerUploadPaymentProofController,
  );
  router.post(
    "/requests/:requestId/messages/attachment",
    requestAttachmentUploadMiddleware,
    customerUploadRequestAttachmentValidator,
    validateRequest,
    customerUploadRequestAttachmentController,
  );
  router.post(
    "/requests/:requestId/messages/:messageId/attachment/replace",
    requestAttachmentUploadMiddleware,
    customerReplaceRequestAttachmentValidator,
    validateRequest,
    customerReplaceRequestAttachmentController,
  );
  router.post(
    "/requests/:requestId/messages",
    customerPostRequestMessageValidator,
    validateRequest,
    customerPostRequestMessageController,
  );

  return router;
}

module.exports = {
  createCustomerRouter,
};
