/// WHAT: Calls the shared internal admin/staff chat endpoints.
/// WHY: Both admin and staff use the same direct-message backend contract and should share one repository implementation.
/// HOW: Route requests to the role-scoped path, parse thread/directory payloads, and expose simple chat actions.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/internal_chat_model.dart';
import '../../core/network/api_client.dart';
import '../../core/realtime/realtime_service.dart';

final internalChatRepositoryProvider = Provider<InternalChatRepository>((ref) {
  return InternalChatRepository(ref.read(apiClientProvider));
});

final internalChatUnreadCountProvider = StreamProvider.autoDispose
    .family<int, String>((ref, viewerRole) async* {
      final repository = ref.watch(internalChatRepositoryProvider);
      final events = ref.watch(realtimeServiceProvider).events;

      final initialBundle = await repository.fetchBundle(
        viewerRole: viewerRole,
      );
      yield initialBundle.totalUnreadCount;

      await for (final event in events) {
        if (!event.affectsInternalChats) {
          continue;
        }

        final bundle = await repository.fetchBundle(viewerRole: viewerRole);
        yield bundle.totalUnreadCount;
      }
    });

class InternalChatRepository {
  const InternalChatRepository(this._client);

  final ApiClient _client;

  String _normalizedUploadMimeType(String fileName, String mimeType) {
    final normalizedMimeType = mimeType.trim().toLowerCase();
    if (normalizedMimeType.isNotEmpty &&
        normalizedMimeType != 'application/octet-stream') {
      return normalizedMimeType;
    }

    final lowerCaseFileName = fileName.toLowerCase();
    if (lowerCaseFileName.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerCaseFileName.endsWith('.jpg') ||
        lowerCaseFileName.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lowerCaseFileName.endsWith('.webp')) {
      return 'image/webp';
    }
    if (lowerCaseFileName.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lowerCaseFileName.endsWith('.txt')) {
      return 'text/plain';
    }
    if (lowerCaseFileName.endsWith('.doc')) {
      return 'application/msword';
    }
    if (lowerCaseFileName.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }

    return 'application/octet-stream';
  }

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

  Future<InternalChatThreadModel> uploadAttachment({
    required String viewerRole,
    required String threadId,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    String? caption,
  }) async {
    final resolvedMimeType = _normalizedUploadMimeType(fileName, mimeType);
    final response = await _client.postFormData(
      '${_basePath(viewerRole)}/$threadId/messages/attachment',
      createData: () => FormData.fromMap(<String, dynamic>{
        'attachment': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(resolvedMimeType),
        ),
        if (caption != null && caption.trim().isNotEmpty)
          'caption': caption.trim(),
      }),
    );

    return InternalChatThreadModel.fromJson(
      response['thread'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<String> refineReply({
    required String viewerRole,
    required String threadId,
    required String draft,
  }) async {
    final response = await _client.postJson(
      '${_basePath(viewerRole)}/$threadId/reply-assistant',
      data: <String, dynamic>{'draft': draft},
    );

    return (response['assistant'] as Map<String, dynamic>? ??
                const <String, dynamic>{})['suggestion']
            as String? ??
        '';
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
