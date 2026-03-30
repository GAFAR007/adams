/// WHAT: Maintains one authenticated Socket.IO connection for live request-thread and internal-chat updates.
/// WHY: REST remains the source of truth for reads and writes, but the UI needs push events to feel live.
/// HOW: Watch the current auth token, connect/disconnect the socket automatically, and expose a broadcast event stream for UI listeners.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../config/app_config.dart';
import '../../features/auth/application/auth_controller.dart';

enum RealtimeEventKind {
  requestUpdated,
  requestListChanged,
  internalChatThreadUpdated,
  internalChatListChanged,
  internalChatDirectoryUpdated,
}

class RealtimeEvent {
  const RealtimeEvent({
    required this.kind,
    this.requestId,
    this.threadId,
    this.userId,
  });

  final RealtimeEventKind kind;
  final String? requestId;
  final String? threadId;
  final String? userId;

  bool get affectsRequests =>
      kind == RealtimeEventKind.requestUpdated ||
      kind == RealtimeEventKind.requestListChanged;

  bool get affectsInternalChats =>
      kind == RealtimeEventKind.internalChatThreadUpdated ||
      kind == RealtimeEventKind.internalChatListChanged;

  bool get affectsInternalDirectory =>
      kind == RealtimeEventKind.internalChatDirectoryUpdated;
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService();
  service.updateAccessToken(ref.read(authControllerProvider).accessToken);

  ref.listen<String?>(
    authControllerProvider.select((state) => state.accessToken),
    (_, next) => service.updateAccessToken(next),
  );
  ref.onDispose(service.dispose);
  return service;
});

final realtimeEventsProvider = StreamProvider.autoDispose<RealtimeEvent>((ref) {
  return ref.watch(realtimeServiceProvider).events;
});

class RealtimeService {
  RealtimeService();

  final StreamController<RealtimeEvent> _eventsController =
      StreamController<RealtimeEvent>.broadcast();
  io.Socket? _socket;
  String? _accessToken;

  Stream<RealtimeEvent> get events => _eventsController.stream;

  void updateAccessToken(String? token) {
    final normalizedToken = token == null || token.trim().isEmpty
        ? null
        : token.trim();
    if (_accessToken == normalizedToken) {
      return;
    }

    _accessToken = normalizedToken;
    _disconnect();

    if (_accessToken == null) {
      return;
    }

    _connect(_accessToken!);
  }

  void _connect(String accessToken) {
    final socket = io.io(_socketBaseUrl, <String, dynamic>{
      'transports': <String>['websocket', 'polling'],
      'autoConnect': false,
      'forceNew': true,
      'reconnection': true,
      'reconnectionAttempts': 8,
      'reconnectionDelay': 1200,
      'auth': <String, dynamic>{'token': accessToken},
      'extraHeaders': <String, String>{'Authorization': 'Bearer $accessToken'},
    });

    socket.onConnect((_) {
      debugPrint('RealtimeService: socket connected');
    });
    socket.onDisconnect((dynamic reason) {
      debugPrint('RealtimeService: socket disconnected ($reason)');
    });
    socket.onConnectError((dynamic error) {
      debugPrint('RealtimeService: socket connect error $error');
    });
    socket.onError((dynamic error) {
      debugPrint('RealtimeService: socket error $error');
    });
    socket.on('request.updated', (dynamic payload) {
      _emit(
        RealtimeEvent(
          kind: RealtimeEventKind.requestUpdated,
          requestId: _stringField(payload, 'requestId'),
        ),
      );
    });
    socket.on('request.list.changed', (dynamic payload) {
      _emit(
        RealtimeEvent(
          kind: RealtimeEventKind.requestListChanged,
          requestId: _stringField(payload, 'requestId'),
        ),
      );
    });
    socket.on('internal-chat.thread.updated', (dynamic payload) {
      _emit(
        RealtimeEvent(
          kind: RealtimeEventKind.internalChatThreadUpdated,
          threadId: _stringField(payload, 'threadId'),
        ),
      );
    });
    socket.on('internal-chat.list.changed', (dynamic payload) {
      _emit(
        RealtimeEvent(
          kind: RealtimeEventKind.internalChatListChanged,
          threadId: _stringField(payload, 'threadId'),
        ),
      );
    });
    socket.on('internal-chat.directory.updated', (dynamic payload) {
      _emit(
        RealtimeEvent(
          kind: RealtimeEventKind.internalChatDirectoryUpdated,
          userId: _stringField(payload, 'userId'),
        ),
      );
    });

    _socket = socket;
    socket.connect();
  }

  void _disconnect() {
    _socket?.dispose();
    _socket = null;
  }

  void _emit(RealtimeEvent event) {
    if (_eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }

  String get _socketBaseUrl {
    final apiUri = Uri.tryParse(AppConfig.apiBaseUrl);
    if (apiUri == null) {
      return AppConfig.apiBaseUrl;
    }

    return apiUri.replace(path: '', query: null, fragment: null).toString();
  }

  String? _stringField(dynamic payload, String key) {
    if (payload is Map) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  void dispose() {
    _disconnect();
    _eventsController.close();
  }
}
