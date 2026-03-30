/**
 * WHAT: Handles HTTP requests for internal admin/staff chat threads.
 * WHY: Internal chat needs a thin controller layer that delegates persistence and shaping to the shared service.
 * HOW: Build per-request log context, call the internal chat service, and return UI-ready payloads.
 */

const { LOG_STEPS } = require('../constants/app.constants');
const { asyncHandler } = require('../utils/async-handler');
const { buildRequestLog, logInfo } = require('../utils/logger');
const { emitInternalChatThreadUpdated } = require('../realtime/socket');
const internalChatService = require('../services/internal-chat.service');

const listInternalChatsController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'InternalChatList',
    intent: 'Fetch internal direct-message threads and directory contacts',
  });

  const result = await internalChatService.listInternalChats(
    req.authUser,
    logContext,
  );
  res.status(200).json(result);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const createDirectInternalChatController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'InternalChatCreateDirectThread',
    intent: 'Start a direct internal chat from a real admin or staff account',
  });

  const result = await internalChatService.createDirectThreadAndSendMessage(
    req.authUser,
    req.body.participantId,
    req.body.message,
    logContext,
  );
  res.status(200).json(result);
  emitInternalChatThreadUpdated(result.thread);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const createGroupInternalChatController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'InternalChatCreateGroupThread',
    intent: 'Start a group internal chat from real admin and staff accounts',
  });

  const result = await internalChatService.createGroupThreadAndSendMessage(
    req.authUser,
    req.body.title,
    req.body.participantIds,
    req.body.message,
    logContext,
  );
  res.status(200).json(result);
  emitInternalChatThreadUpdated(result.thread);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const postInternalChatMessageController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'InternalChatPostMessage',
    intent: 'Append a message to an existing internal direct-message thread',
  });

  const result = await internalChatService.postInternalChatMessage(
    req.authUser,
    req.params.threadId,
    req.body.message,
    logContext,
  );
  res.status(200).json(result);
  emitInternalChatThreadUpdated(result.thread);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

const markInternalChatReadController = asyncHandler(async (req, res) => {
  const logContext = buildRequestLog(req, {
    layer: 'controller',
    operation: 'InternalChatMarkRead',
    intent: 'Clear unread state when an admin or staff member opens an internal chat thread',
  });

  const result = await internalChatService.markInternalChatRead(
    req.authUser,
    req.params.threadId,
    logContext,
  );
  res.status(200).json(result);
  emitInternalChatThreadUpdated(result.thread);

  logInfo({
    ...logContext,
    step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
  });
});

module.exports = {
  createDirectInternalChatController,
  createGroupInternalChatController,
  listInternalChatsController,
  markInternalChatReadController,
  postInternalChatMessageController,
};
