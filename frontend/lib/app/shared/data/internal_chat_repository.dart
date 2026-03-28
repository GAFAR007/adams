/// WHAT: Calls the shared internal admin/staff chat endpoints.
/// WHY: Both admin and staff use the same direct-message backend contract and should share one repository implementation.
/// HOW: Route requests to the role-scoped path, parse thread/directory payloads, and expose simple chat actions.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/internal_chat_model.dart';
import '../../core/network/api_client.dart';

final internalChatRepositoryProvider = Provider<InternalChatRepository>((ref) {
  return InternalChatRepository(ref.read(apiClientProvider));
});

final internalChatUnreadCountProvider = StreamProvider.autoDispose
    .family<int, String>((ref, viewerRole) async* {
      final repository = ref.watch(internalChatRepositoryProvider);
      var isDisposed = false;
      ref.onDispose(() {
        isDisposed = true;
      });

      while (!isDisposed) {
        final bundle = await repository.fetchBundle(viewerRole: viewerRole);
        yield bundle.totalUnreadCount;

        await Future<void>.delayed(const Duration(seconds: 8));
      }
    });

class InternalChatRepository {
  const InternalChatRepository(this._client);

  final ApiClient _client;

  Future<InternalChatBundle> fetchBundle({required String viewerRole}) async {
    final response = await _client.getJson(_basePath(viewerRole));
    return InternalChatBundle.fromJson(response);
  }

  Future<InternalChatThreadModel> startDirectThread({
    required String viewerRole,
    required String participantId,
    required String message,
  }) async {
    final response = await _client.postJson(
      '${_basePath(viewerRole)}/direct',
      data: <String, dynamic>{
        'participantId': participantId,
        'message': message,
      },
    );

    return InternalChatThreadModel.fromJson(
      response['thread'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<InternalChatThreadModel> startGroupThread({
    required String viewerRole,
    required String title,
    required List<String> participantIds,
    required String message,
  }) async {
    final response = await _client.postJson(
      '${_basePath(viewerRole)}/groups',
      data: <String, dynamic>{
        'title': title,
        'participantIds': participantIds,
        'message': message,
      },
    );

    return InternalChatThreadModel.fromJson(
      response['thread'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<InternalChatThreadModel> sendMessage({
    required String viewerRole,
    required String threadId,
    required String message,
  }) async {
    final response = await _client.postJson(
      '${_basePath(viewerRole)}/$threadId/messages',
      data: <String, dynamic>{'message': message},
    );

    return InternalChatThreadModel.fromJson(
      response['thread'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<InternalChatThreadModel> markRead({
    required String viewerRole,
    required String threadId,
  }) async {
    final response = await _client.postJson(
      '${_basePath(viewerRole)}/$threadId/read',
    );

    return InternalChatThreadModel.fromJson(
      response['thread'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  String _basePath(String viewerRole) {
    return switch (viewerRole) {
      'admin' => '/admin/internal-chats',
      'staff' => '/staff/internal-chats',
      _ => throw const ApiException(
        'Internal chat is only available for admin and staff accounts.',
      ),
    };
  }
}
