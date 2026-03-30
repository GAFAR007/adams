/**
 * WHAT: Handles HTTP requests for invite-based staff registration and staff dashboards.
 * WHY: Staff request ownership and invite flows need controllers tailored to their specific contract.
 * HOW: Build request-aware log context, delegate to staff services, and return safe payloads.
 */

const { LOG_STEPS } = require('../constants/app.constants');
const { asyncHandler } = require('../utils/async-handler');
const { buildRequestLog, logInfo } = require('../utils/logger');
const {
  emitInternalChatDirectoryUpdated,
  emitRequestUpdated,
} = require('../realtime/socket');
const { setRefreshCookie } = require('../services/token.service');
const staffService = require('../services/staff.service');

function buildClientMeta(req) {
  return {
    // WHY: Store request origin hints with issued staff sessions for security tracing.
    ipAddress: req.ip,
    userAgent: req.headers['user-agent'] || 'unknown',
  };
}

const staffRegisterController = asyncHandler(async (req, res) => {
  // WHY: Build one shared context so invite-registration logs can be correlated easily.
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffRegister',
    intent: 'Create a staff account from a valid invite token',
  });

  // WHY: Staff onboarding rules live in the service so the controller does not verify invites itself.
  const result = await staffService.registerFromInvite(req.body, buildClientMeta(req), logContext);
  // WHY: Set the refresh cookie during registration so invited staff land in an authenticated session immediately.
  setRefreshCookie(res, result.refreshToken);

  res.status(201).json({
    message: result.message,
    user: result.user,
    accessToken: result.accessToken,
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const staffDashboardController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffGetDashboard',
    intent: 'Fetch dashboard KPI and recent-assignment data for the signed-in staff member',
  });

  // WHY: Dashboard ownership and shaping stay in the service so staff never see unscoped data.
  const result = await staffService.getDashboard(req.authUser.id, logContext);
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const staffUpdateAvailabilityController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffUpdateAvailability',
    intent: 'Update whether the signed-in staff member is available to attend live queue work',
  });

  // WHY: Availability rules and persistence stay in the service so the controller remains a thin HTTP adapter.
  const result = await staffService.updateAvailability(
    req.authUser.id,
    req.body.availability,
    logContext,
  );
  res.status(200).json(result);
  emitInternalChatDirectoryUpdated(result.user?.id || req.authUser.id);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const staffAttendQueueRequestController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffAttendQueueRequest',
    intent: 'Let the signed-in staff member pick up a waiting request from the live queue',
  });

  // WHY: Queue claiming needs service-layer ownership and atomicity checks, not controller branching.
  const result = await staffService.attendQueueRequest(
    req.authUser.id,
    req.params.requestId,
    logContext,
  );
  res.status(200).json(result);
  emitRequestUpdated(result.request);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const staffListRequestsController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffListRequests',
    intent: 'Fetch the requests assigned to the signed-in staff member',
  });

  // WHY: The service applies assignment ownership and optional filters in one place.
  const result = await staffService.listAssignedRequests(req.authUser.id, req.query, logContext);
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const staffUpdateRequestStatusController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffUpdateRequestStatus',
    intent: 'Update a status on a request owned by the signed-in staff member',
  });

  // WHY: Status transitions must be validated centrally so staff cannot move requests into forbidden states.
  const result = await staffService.updateAssignedRequestStatus(
    req.authUser.id,
    req.params.requestId,
    req.body.status,
    logContext,
  );
  res.status(200).json(result);
  emitRequestUpdated(result.request);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const staffPostRequestMessageController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffPostRequestMessage',
    intent: 'Append a staff reply onto an assigned customer thread',
  });

  // WHY: Thread ownership enforcement belongs in the service so the controller does not duplicate assignment checks.
  const result = await staffService.postAssignedRequestMessage(
    req.authUser.id,
    req.params.requestId,
    req.body.message,
    req.body.actionType,
    logContext,
  );
  res.status(200).json(result);
  emitRequestUpdated(result.request);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const staffUploadRequestAttachmentController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffUploadRequestAttachment',
    intent: 'Upload a staff chat attachment into an assigned customer thread',
  });

  const result = await staffService.uploadAssignedRequestAttachment(
    req.authUser.id,
    req.params.requestId,
    req.file,
    req.body.caption,
    logContext,
  );
  res.status(200).json(result);
  emitRequestUpdated(result.request);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const staffUpdateRequestAiControlController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffUpdateRequestAiControl',
    intent: 'Toggle whether Naima is covering an assigned customer chat',
  });

  const result = await staffService.updateAssignedRequestAiControl(
    req.authUser.id,
    req.params.requestId,
    req.body.enabled,
    logContext,
  );
  res.status(200).json(result);
  emitRequestUpdated(result.request);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const staffCreateRequestInvoiceController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffCreateRequestInvoice',
    intent: 'Send an invoice and payment instructions from the assigned staff chat',
  });

  const result = await staffService.createAssignedRequestInvoice(
    req.authUser.id,
    req.params.requestId,
    req.body,
    logContext,
  );
  res.status(200).json(result);
  emitRequestUpdated(result.request);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const staffReviewPaymentProofController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'StaffReviewPaymentProof',
    intent: 'Approve or reject customer payment proof from the assigned staff chat',
  });

  const result = await staffService.reviewAssignedRequestPaymentProof(
    req.authUser.id,
    req.params.requestId,
    req.body.decision,
    req.body.reviewNote,
    logContext,
  );
  res.status(200).json(result);
  emitRequestUpdated(result.request);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

module.exports = {
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
};
