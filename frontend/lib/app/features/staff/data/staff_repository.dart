/// WHAT: Calls backend endpoints for invite registration, staff dashboards, queue pickup, and request-thread actions.
/// WHY: Staff screens should stay independent from backend wire details while still exposing the full live-queue workflow.
/// HOW: Use the shared API client to fetch the dashboard snapshot and send small queue, availability, status, and message actions.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/dashboard_models.dart';
import '../../../core/models/service_request_model.dart';
import '../../../core/network/api_client.dart';
import '../../auth/domain/auth_session.dart';

final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return StaffRepository(ref.read(apiClientProvider));
});

class StaffRepository {
  const StaffRepository(this._client);

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

  Future<AuthSession> registerFromInvite({
    required String inviteToken,
    required String firstName,
    required String lastName,
    required String phone,
    required String password,
  }) async {
    final response = await _client.postJson(
      '/staff/register',
      data: <String, dynamic>{
        'inviteToken': inviteToken,
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'password': password,
      },
    );

    return AuthSession.fromJson(response);
  }

  Future<StaffDashboardBundle> fetchDashboard() async {
    final response = await _client.getJson('/staff/dashboard');
    return StaffDashboardBundle.fromJson(response);
  }

  Future<void> updateAvailability({required String availability}) async {
    // WHY: Staff availability is a tiny state change, so the dashboard can simply refetch after the backend confirms it.
    await _client.patchJson(
      '/staff/availability',
      data: <String, dynamic>{'availability': availability},
    );
  }

  Future<ServiceRequestModel> attendQueueRequest({
    required String requestId,
  }) async {
    final response = await _client.postJson('/staff/queue/$requestId/attend');

    // WHY: Return the updated request row so callers can inspect the claimed queue item if they need immediate feedback.
    return ServiceRequestModel.fromJson(
      response['request'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<void> updateRequestStatus({
    required String requestId,
    required String status,
  }) async {
    await _client.patchJson(
      '/staff/requests/$requestId/status',
      data: <String, dynamic>{'status': status},
    );
  }

  Future<void> sendMessage({
    required String requestId,
    required String message,
    String? actionType,
  }) async {
    await _client.postJson(
      '/staff/requests/$requestId/messages',
      data: <String, dynamic>{'message': message, 'actionType': actionType},
    );
  }

  Future<void> uploadRequestAttachment({
    required String requestId,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    String? caption,
  }) async {
    final resolvedMimeType = _normalizedUploadMimeType(fileName, mimeType);

    await _client.postFormData(
      '/staff/requests/$requestId/messages/attachment',
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
  }

  Future<void> updateRequestAiControl({
    required String requestId,
    required bool enabled,
  }) async {
    await _client.patchJson(
      '/staff/requests/$requestId/ai-control',
      data: <String, dynamic>{'enabled': enabled},
    );
  }

  Future<void> sendInvoice({
    required String requestId,
    required double amount,
    required String dueDate,
    required String paymentMethod,
    required String paymentInstructions,
    String? note,
  }) async {
    await _client.postJson(
      '/staff/requests/$requestId/invoice',
      data: <String, dynamic>{
        'amount': amount,
        'dueDate': dueDate,
        'paymentMethod': paymentMethod,
        'paymentInstructions': paymentInstructions,
        'note': note,
      },
    );
  }

  Future<void> reviewPaymentProof({
    required String requestId,
    required String decision,
    String? reviewNote,
  }) async {
    await _client.patchJson(
      '/staff/requests/$requestId/invoice/proof/review',
      data: <String, dynamic>{'decision': decision, 'reviewNote': reviewNote},
    );
  }
}
