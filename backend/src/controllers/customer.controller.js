/**
 * WHAT: Handles HTTP requests for customer-owned service request actions.
 * WHY: Customer request creation and listing need their own HTTP boundary separate from admin/staff flows.
 * HOW: Build controller log context, delegate to the customer service, and return safe request payloads.
 */

const { LOG_STEPS } = require('../constants/app.constants');
const { asyncHandler } = require('../utils/async-handler');
const { buildRequestLog, logInfo } = require('../utils/logger');
const customerService = require('../services/customer.service');

const customerCreateRequestController = asyncHandler(async (req, res) => {
  // WHY: Keep one trace context for the full customer-request creation flow.
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'CustomerCreateRequest',
    intent: 'Create a new service request for the signed-in customer',
  });

  // WHY: The service owns customer lookup and request persistence so request rules stay centralized.
  const result = await customerService.createRequest(req.authUser.id, req.body, logContext);
  res.status(201).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const customerListRequestsController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'CustomerListRequests',
    intent: 'Fetch only the signed-in customer request timeline',
  });

  // WHY: Request ownership filtering belongs in the service so customers can never widen their own scope.
  const result = await customerService.listRequests(req.authUser.id, logContext);
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const customerPostRequestMessageController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'CustomerPostRequestMessage',
    intent: 'Append a customer follow-up message to an owned service-request thread',
  });

  // WHY: Thread ownership and queue-wait behavior stay in the service so the controller only handles HTTP contract work.
  const result = await customerService.postRequestMessage(
    req.authUser.id,
    req.params.requestId,
    req.body.message,
    logContext,
  );
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const customerUpdateRequestController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'CustomerUpdateRequest',
    intent: 'Update an owned customer service request from the chat-driven follow-up flow',
  });

  const result = await customerService.updateRequest(
    req.authUser.id,
    req.params.requestId,
    req.body,
    logContext,
  );
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const customerUploadPaymentProofController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'CustomerUploadPaymentProof',
    intent: 'Upload customer payment proof for an invoice attached to an owned request',
  });

  const result = await customerService.uploadPaymentProof(
    req.authUser.id,
    req.params.requestId,
    req.file,
    req.body.note,
    logContext,
  );
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const customerUploadRequestAttachmentController = asyncHandler(
  async (req, res) => {
    const logContext = buildRequestLog(req, {
      layer: 'controller',
      operation: 'CustomerUploadRequestAttachment',
      intent:
          'Upload a customer chat attachment into an owned service-request thread',
    });

    const result = await customerService.uploadRequestAttachment(
      req.authUser.id,
      req.params.requestId,
      req.file,
      req.body.caption,
      logContext,
    );
    res.status(200).json(result);

    logInfo({
      ...logContext,
      step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
    });
  },
);

module.exports = {
  customerCreateRequestController,
  customerListRequestsController,
  customerPostRequestMessageController,
  customerUploadPaymentProofController,
  customerUploadRequestAttachmentController,
  customerUpdateRequestController,
};
