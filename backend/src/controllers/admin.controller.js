/**
 * WHAT: Handles HTTP requests for admin dashboard, request management, and staff invite workflows.
 * WHY: Admin HTTP concerns should stay separate from the underlying operational business logic.
 * HOW: Build controller log context, delegate to the admin service, and return UI-ready payloads.
 */

const { LOG_STEPS } = require('../constants/app.constants');
const { asyncHandler } = require('../utils/async-handler');
const { buildRequestLog, logInfo } = require('../utils/logger');
const adminService = require('../services/admin.service');

const adminDashboardController = asyncHandler(async (req, res) => {
  // WHY: Build the log context once so every dashboard checkpoint can be traced back to this request.
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'AdminGetDashboard',
    intent: 'Fetch KPI and recent-request data for the admin dashboard',
  });

  // WHY: Keep aggregation and data loading in the service so the controller only shapes HTTP behavior.
  const result = await adminService.getDashboard(logContext);
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const adminListRequestsController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'AdminListRequests',
    intent: 'Fetch filtered request inbox data for admin review',
  });

  // WHY: Pass raw query params to the service so filtering rules stay in one operational layer.
  const result = await adminService.listRequests(req.query, logContext);
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const adminAssignRequestController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'AdminAssignRequest',
    intent: 'Assign a customer request to a staff member from the admin dashboard',
  });

  // WHY: The service owns assignment validation so the controller does not duplicate staff/request checks.
  const result = await adminService.assignRequest(req.params.requestId, req.body.staffId, logContext);
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const adminListStaffController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'AdminListStaff',
    intent: 'Fetch active staff accounts for assignment and management UI',
  });

  // WHY: Staff shaping belongs in the service so assignment counts stay consistent everywhere.
  const result = await adminService.listStaff(logContext);
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const adminCreateStaffInviteController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'AdminCreateStaffInvite',
    intent: 'Generate a new invite-only registration link for staff onboarding',
  });

  // WHY: Pass the authenticated admin through so the invite record keeps an auditable creator.
  const result = await adminService.createStaffInvite(req.body, req.authUser, logContext);
  res.status(201).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const adminDeleteStaffInviteController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'AdminDeleteStaffInvite',
    intent: 'Remove an invite link from admin management without affecting accepted staff accounts',
  });

  // WHY: The service owns the pending-vs-accepted branching so the controller stays focused on HTTP behavior.
  const result = await adminService.deleteStaffInvite(req.params.inviteId, logContext);
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const adminListStaffInvitesController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'AdminListStaffInvites',
    intent: 'Fetch active invite links for admin staff-onboarding management',
  });

  // WHY: Invite filtering rules stay in the service so expired or consumed links are handled consistently.
  const result = await adminService.listStaffInvites(logContext);
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

module.exports = {
  adminAssignRequestController,
  adminCreateStaffInviteController,
  adminDeleteStaffInviteController,
  adminDashboardController,
  adminListRequestsController,
  adminListStaffController,
  adminListStaffInvitesController,
};
