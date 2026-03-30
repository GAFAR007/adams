/**
 * WHAT: Hosts the authenticated Socket.IO layer used for live request-thread and internal-chat updates.
 * WHY: REST remains the source of truth for reads and writes, but the UI needs push events to feel live.
 * HOW: Authenticate with the existing JWT access token, place sockets into user/role rooms, and fan out safe change events after successful mutations.
 */

const { Server } = require('socket.io');

const { USER_ROLES } = require('../constants/app.constants');
const { env } = require('../config/env');
const { verifyAccessToken } = require('../services/token.service');
const { logError, logInfo } = require('../utils/logger');

let io = null;

function buildUserRoom(userId) {
  return `user:${String(userId)}`;
}

function buildRoleRoom(role) {
  return `role:${String(role)}`;
}

function extractSocketToken(socket) {
  const authToken = socket.handshake.auth?.token;
  if (typeof authToken === 'string' && authToken.trim().length > 0) {
    return authToken.trim();
  }

  const authorization = socket.handshake.headers.authorization || '';
  const [scheme, token] = String(authorization).split(' ');
  if (scheme === 'Bearer' && token) {
    return token;
  }

  return '';
}

function attachSocketServer(server) {
  if (io) {
    return io;
  }

  io = new Server(server, {
    cors: {
      origin: env.corsOrigins.length > 0 ? env.corsOrigins : true,
      credentials: true,
    },
  });

  logInfo({
    requestId: 'socket',
    route: 'SOCKET.IO',
    step: 'SERVICE_OK',
    layer: 'realtime',
    operation: 'SocketIoAttach',
    intent: 'Expose live authenticated realtime channels for chat updates',
  });

  io.use((socket, next) => {
    try {
      const token = extractSocketToken(socket);
      if (!token) {
        logError({
          requestId: 'socket',
          route: 'SOCKET.IO',
          step: 'AUTH_FAIL',
          layer: 'realtime',
          operation: 'SocketIoAuth',
          intent: 'Reject socket connections that do not send a bearer access token',
          classification: 'AUTHENTICATION_ERROR',
          error_code: 'AUTH_ACCESS_TOKEN_MISSING',
          resolution_hint: 'Send a valid bearer access token during the socket handshake',
          message: 'Authentication is required',
        });
        const error = new Error('AUTH_ACCESS_TOKEN_MISSING');
        error.data = {
          message: 'Authentication is required',
          errorCode: 'AUTH_ACCESS_TOKEN_MISSING',
          resolutionHint: 'Send a valid bearer access token',
        };
        next(error);
        return;
      }

      const payload = verifyAccessToken(token);
      socket.data.authUser = {
        id: String(payload.sub || ''),
        role: payload.role || '',
        email: payload.email || '',
      };
      next();
    } catch (error) {
      logError({
        requestId: 'socket',
        route: 'SOCKET.IO',
        step: 'AUTH_FAIL',
        layer: 'realtime',
        operation: 'SocketIoAuth',
        intent: 'Reject socket connections that present an invalid or expired bearer access token',
        classification: error.classification || 'AUTHENTICATION_ERROR',
        error_code: error.errorCode || 'AUTH_ACCESS_TOKEN_INVALID',
        resolution_hint:
          error.resolutionHint || 'Log in again to obtain a fresh access token',
        message: error.message || 'Authentication failed',
      });
      const socketError = new Error(error.errorCode || 'AUTH_ACCESS_TOKEN_INVALID');
      socketError.data = {
        message: error.message || 'Authentication failed',
        errorCode: error.errorCode || 'AUTH_ACCESS_TOKEN_INVALID',
        resolutionHint:
          error.resolutionHint || 'Log in again to obtain a fresh access token',
      };
      next(socketError);
    }
  });

  io.on('connection', (socket) => {
    const authUser = socket.data.authUser;
    if (!authUser?.id) {
      socket.disconnect(true);
      return;
    }

    socket.join(buildUserRoom(authUser.id));
    if (authUser.role) {
      socket.join(buildRoleRoom(authUser.role));
    }

    logInfo({
      requestId: socket.id,
      route: 'SOCKET.IO',
      step: 'AUTH_OK',
      layer: 'realtime',
      operation: 'SocketIoConnect',
      intent: 'Accept an authenticated socket client and join the role and user rooms',
      userId: authUser.id,
      userRole: authUser.role || '-',
    });

    socket.on('disconnect', (reason) => {
      logInfo({
        requestId: socket.id,
        route: 'SOCKET.IO',
        step: 'SERVICE_OK',
        layer: 'realtime',
        operation: 'SocketIoDisconnect',
        intent: 'Confirm the authenticated realtime client disconnected cleanly',
        userId: authUser.id,
        userRole: authUser.role || '-',
        reason,
      });
    });
  });

  return io;
}

function emitToRooms(roomNames, eventName, payload) {
  if (!io) {
    return;
  }

  for (const roomName of roomNames) {
    if (typeof roomName !== 'string' || roomName.trim().length === 0) {
      continue;
    }
    io.to(roomName).emit(eventName, payload);
  }
}

function emitRequestUpdated(request) {
  if (!request?.id) {
    return;
  }

  const customerId = request.customer?.id;
  const assignedStaffId = request.assignedStaff?.id;
  const emittedAt = new Date().toISOString();

  const updateRooms = new Set([buildRoleRoom(USER_ROLES.ADMIN)]);
  if (customerId) {
    updateRooms.add(buildUserRoom(customerId));
  }
  if (assignedStaffId) {
    updateRooms.add(buildUserRoom(assignedStaffId));
  }

  emitToRooms(updateRooms, 'request.updated', {
    emittedAt,
    requestId: request.id,
    request,
  });

  const listRooms = new Set([...updateRooms, buildRoleRoom(USER_ROLES.STAFF)]);
  emitToRooms(listRooms, 'request.list.changed', {
    emittedAt,
    requestId: request.id,
    status: request.status || '',
    customerId: customerId || null,
    assignedStaffId: assignedStaffId || null,
  });
}

function emitInternalChatThreadUpdated(thread) {
  if (!thread?.id) {
    return;
  }

  const emittedAt = new Date().toISOString();
  const participantRooms = new Set(
    (Array.isArray(thread.participants) ? thread.participants : [])
      .map((participant) => participant?.id)
      .filter(Boolean)
      .map(buildUserRoom),
  );

  emitToRooms(participantRooms, 'internal-chat.thread.updated', {
    emittedAt,
    threadId: thread.id,
    thread,
  });
  emitToRooms(participantRooms, 'internal-chat.list.changed', {
    emittedAt,
    threadId: thread.id,
  });
}

function emitInternalChatDirectoryUpdated(userId = null) {
  emitToRooms(
    new Set([
      buildRoleRoom(USER_ROLES.ADMIN),
      buildRoleRoom(USER_ROLES.STAFF),
      ...(userId ? [buildUserRoom(userId)] : []),
    ]),
    'internal-chat.directory.updated',
    {
      emittedAt: new Date().toISOString(),
      userId: userId ? String(userId) : null,
    },
  );
}

module.exports = {
  attachSocketServer,
  emitInternalChatDirectoryUpdated,
  emitInternalChatThreadUpdated,
  emitRequestUpdated,
};
