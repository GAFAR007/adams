/**
 * WHAT: Implements internal direct and group chat for admin and staff users.
 * WHY: Internal coordination needs persistent one-to-one and multi-person chat threads instead of seeded frontend-only placeholders.
 * HOW: Resolve active participants from MongoDB, maintain one direct thread per user pair, create named group threads, and compute unread state per viewer.
 */

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  USER_ROLES,
  USER_STATUSES,
} = require('../constants/app.constants');
const { InternalChatThread } = require('../models/internal-chat-thread.model');
const { User } = require('../models/user.model');
const { AppError } = require('../utils/app-error');
const { logInfo } = require('../utils/logger');
const {
  serializeInternalChatThread,
  serializeUser,
} = require('../utils/serializers');

const INTERNAL_CHAT_ALLOWED_ROLES = [USER_ROLES.ADMIN, USER_ROLES.STAFF];
const USER_PUBLIC_FIELDS =
  'firstName lastName email phone role status staffAvailability createdAt updatedAt';

function buildParticipantKey(userIdA, userIdB) {
  return [String(userIdA), String(userIdB)].sort().join(':');
}

function buildFullName(user) {
  return `${user.firstName || ''} ${user.lastName || ''}`.trim();
}

function normalizeUniqueParticipantIds(participantIds = [], currentUserId) {
  return [...new Set((Array.isArray(participantIds) ? participantIds : []).map(String))]
    .filter((id) => id && id !== String(currentUserId));
}

async function loadActiveChatUser(userId) {
  return User.findOne({
    _id: userId,
    role: { $in: INTERNAL_CHAT_ALLOWED_ROLES },
    status: USER_STATUSES.ACTIVE,
  });
}

async function loadActiveChatUsers(userIds) {
  return User.find({
    _id: { $in: userIds },
    role: { $in: INTERNAL_CHAT_ALLOWED_ROLES },
    status: USER_STATUSES.ACTIVE,
  }).select(USER_PUBLIC_FIELDS);
}

async function populateInternalChatThread(threadId) {
  return InternalChatThread.findById(threadId)
    .populate('participants.user', USER_PUBLIC_FIELDS)
    .populate('messages.sender', USER_PUBLIC_FIELDS);
}

async function loadAccessibleThread(threadId, currentUserId) {
  return InternalChatThread.findOne({
    _id: threadId,
    'participants.user': currentUserId,
  })
    .populate('participants.user', USER_PUBLIC_FIELDS)
    .populate('messages.sender', USER_PUBLIC_FIELDS);
}

function touchParticipantReadState(thread, userId, timestamp) {
  const participant = thread.participants.find((item) => {
    return String(item.user?._id || item.user) === String(userId);
  });

  if (participant) {
    participant.lastReadAt = timestamp;
  }
}

function appendThreadMessage(thread, sender, message, timestamp) {
  thread.messages.push({
    sender: sender._id,
    senderName: buildFullName(sender),
    senderRole: sender.role,
    text: message,
    createdAt: timestamp,
  });
  thread.lastMessageAt = timestamp;
  touchParticipantReadState(thread, sender._id, timestamp);
}

async function listInternalChats(authUser, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'InternalChatList',
    intent: 'Load real internal direct and group chat threads plus the active operator directory',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'InternalChatList',
    intent: 'Fetch accessible internal chat threads and active admin/staff directory rows together',
  });

  const [currentUser, threads, directoryUsers] = await Promise.all([
    loadActiveChatUser(authUser.id),
    InternalChatThread.find({ 'participants.user': authUser.id })
      .populate('participants.user', USER_PUBLIC_FIELDS)
      .populate('messages.sender', USER_PUBLIC_FIELDS)
      .sort({ lastMessageAt: -1, updatedAt: -1 }),
    User.find({
      _id: { $ne: authUser.id },
      role: { $in: INTERNAL_CHAT_ALLOWED_ROLES },
      status: USER_STATUSES.ACTIVE,
    }).select(USER_PUBLIC_FIELDS),
  ]);

  if (!currentUser) {
    throw new AppError({
      message: 'Operator account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'INTERNAL_CHAT_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'InternalChatList',
    intent: 'Confirm internal chat threads and directory rows are ready for response shaping',
  });

  const sortedDirectory = [...directoryUsers].sort((left, right) => {
    const leftOnline = left.staffAvailability === 'online' ? 0 : 1;
    const rightOnline = right.staffAvailability === 'online' ? 0 : 1;
    if (leftOnline !== rightOnline) {
      return leftOnline - rightOnline;
    }

    if (left.role !== right.role) {
      return left.role === USER_ROLES.ADMIN ? -1 : 1;
    }

    return buildFullName(left).localeCompare(buildFullName(right));
  });

  return {
    message: 'Internal chats fetched successfully',
    threads: threads
      .map((thread) => serializeInternalChatThread(thread, authUser.id))
      .filter(Boolean),
    directory: sortedDirectory.map(serializeUser).filter(Boolean),
  };
}

async function createDirectThreadAndSendMessage(
  authUser,
  participantId,
  message,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'InternalChatCreateDirectThread',
    intent: 'Start or reuse a real direct internal chat thread and persist the first message',
  });

  if (String(authUser.id) === String(participantId)) {
    throw new AppError({
      message: 'Choose another person to start a chat',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'INTERNAL_CHAT_SELF_RECIPIENT',
      resolutionHint: 'Pick a different staff or admin account',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'InternalChatCreateDirectThread',
    intent: 'Validate both chat participants and load any existing direct thread before writing a message',
  });

  const [sender, recipient] = await Promise.all([
    loadActiveChatUser(authUser.id),
    loadActiveChatUser(participantId),
  ]);

  if (!sender) {
    throw new AppError({
      message: 'Operator account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'INTERNAL_CHAT_SENDER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!recipient) {
    throw new AppError({
      message: 'Recipient not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'INTERNAL_CHAT_RECIPIENT_NOT_FOUND',
      resolutionHint: 'Refresh the team list and choose an active account',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const participantKey = buildParticipantKey(sender._id, recipient._id);
  let thread = await InternalChatThread.findOne({ participantKey });
  const messageTimestamp = new Date();

  if (!thread) {
    thread = await InternalChatThread.create({
      threadType: 'direct',
      participantKey,
      participants: [
        { user: sender._id, lastReadAt: messageTimestamp },
        { user: recipient._id, lastReadAt: null },
      ],
      createdBy: sender._id,
      lastMessageAt: messageTimestamp,
      messages: [],
    });
  }

  appendThreadMessage(thread, sender, message, messageTimestamp);
  await thread.save();

  const populatedThread = await populateInternalChatThread(thread._id);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'InternalChatCreateDirectThread',
    intent: 'Confirm the direct chat thread exists and the first message was persisted',
  });

  return {
    message: 'Internal message sent successfully',
    thread: serializeInternalChatThread(populatedThread, authUser.id),
  };
}

async function createGroupThreadAndSendMessage(
  authUser,
  title,
  participantIds,
  message,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'InternalChatCreateGroupThread',
    intent: 'Create a real internal group chat thread and persist the first message',
  });

  const normalizedParticipantIds = normalizeUniqueParticipantIds(
    participantIds,
    authUser.id,
  );

  if (normalizedParticipantIds.length < 2) {
    throw new AppError({
      message: 'Choose at least two other people for a group chat',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'INTERNAL_CHAT_GROUP_TOO_SMALL',
      resolutionHint: 'Pick at least two active admin or staff accounts',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'InternalChatCreateGroupThread',
    intent: 'Validate the group creator and all requested participants before creating the thread',
  });

  const [sender, recipients] = await Promise.all([
    loadActiveChatUser(authUser.id),
    loadActiveChatUsers(normalizedParticipantIds),
  ]);

  if (!sender) {
    throw new AppError({
      message: 'Operator account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'INTERNAL_CHAT_SENDER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (recipients.length !== normalizedParticipantIds.length) {
    throw new AppError({
      message: 'One or more selected people are no longer available',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'INTERNAL_CHAT_GROUP_RECIPIENT_NOT_FOUND',
      resolutionHint: 'Refresh the team list and choose only active accounts',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const messageTimestamp = new Date();
  const thread = await InternalChatThread.create({
    threadType: 'group',
    title: String(title || '').trim(),
    participantKey: null,
    participants: [
      { user: sender._id, lastReadAt: messageTimestamp },
      ...recipients.map((user) => ({ user: user._id, lastReadAt: null })),
    ],
    createdBy: sender._id,
    lastMessageAt: messageTimestamp,
    messages: [],
  });

  appendThreadMessage(thread, sender, message, messageTimestamp);
  await thread.save();

  const populatedThread = await populateInternalChatThread(thread._id);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'InternalChatCreateGroupThread',
    intent: 'Confirm the group chat thread exists and the first message was persisted',
  });

  return {
    message: 'Internal group created successfully',
    thread: serializeInternalChatThread(populatedThread, authUser.id),
  };
}

async function postInternalChatMessage(authUser, threadId, message, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'InternalChatPostMessage',
    intent: 'Append a new message onto an existing internal chat thread',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'InternalChatPostMessage',
    intent: 'Load the thread and sender identity before persisting the new internal message',
  });

  const [sender, thread] = await Promise.all([
    loadActiveChatUser(authUser.id),
    loadAccessibleThread(threadId, authUser.id),
  ]);

  if (!sender) {
    throw new AppError({
      message: 'Operator account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'INTERNAL_CHAT_SENDER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!thread) {
    throw new AppError({
      message: 'Chat thread not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'INTERNAL_CHAT_THREAD_NOT_FOUND',
      resolutionHint: 'Refresh the chat list and open a valid thread',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const messageTimestamp = new Date();
  appendThreadMessage(thread, sender, message, messageTimestamp);
  await thread.save();

  const populatedThread = await populateInternalChatThread(thread._id);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'InternalChatPostMessage',
    intent: 'Confirm the internal chat message was saved on the accessible thread',
  });

  return {
    message: 'Internal message sent successfully',
    thread: serializeInternalChatThread(populatedThread, authUser.id),
  };
}

async function markInternalChatRead(authUser, threadId, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'InternalChatMarkRead',
    intent: 'Mark an internal thread as read for the current operator',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'InternalChatMarkRead',
    intent: 'Load the accessible thread before updating the participant read marker',
  });

  const thread = await loadAccessibleThread(threadId, authUser.id);

  if (!thread) {
    throw new AppError({
      message: 'Chat thread not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'INTERNAL_CHAT_THREAD_NOT_FOUND',
      resolutionHint: 'Refresh the chat list and open a valid thread',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const timestamp = new Date();
  touchParticipantReadState(thread, authUser.id, timestamp);
  await thread.save();

  const populatedThread = await populateInternalChatThread(thread._id);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'InternalChatMarkRead',
    intent: 'Confirm the current operator read marker was saved on the thread',
  });

  return {
    message: 'Internal chat marked as read',
    thread: serializeInternalChatThread(populatedThread, authUser.id),
  };
}

module.exports = {
  createDirectThreadAndSendMessage,
  createGroupThreadAndSendMessage,
  listInternalChats,
  markInternalChatRead,
  postInternalChatMessage,
};
