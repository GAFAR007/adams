/// WHAT: Calls admin endpoints for dashboard overview, request assignment, staff, and invite management.
/// WHY: Admin screens need a single repository to gather the multiple payloads that feed the dashboard.
/// HOW: Fetch compact summary endpoints, load the queue with backend filters, and expose small admin actions.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/dashboard_models.dart';
import '../../../core/models/service_request_model.dart';
import '../../../core/network/api_client.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.read(apiClientProvider));
});

class AdminRepository {
  const AdminRepository(this._client);

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

  Future<AdminDashboardBundle> fetchDashboardBundle() async {
    // WHY: Keep the summary bundle focused on KPI, staffing, and invite data so queue filtering can refetch independently.
    final dashboard = await _client.getJson('/admin/dashboard');
    final staff = await _client.getJson('/admin/staff');
    final invites = await _client.getJson('/admin/staff/invites');

    final recentRequests =
        (dashboard['recentRequests'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ServiceRequestModel.fromJson)
            .toList();
    final staffItems = (staff['staff'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(StaffMemberSummary.fromJson)
        .toList();
    final inviteItems =
        (invites['invites'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(StaffInviteModel.fromJson)
            .toList();

    return AdminDashboardBundle(
      kpis: AdminKpis.fromJson(
        dashboard['kpis'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      recentRequests: recentRequests,
      staff: staffItems,
      invites: inviteItems,
    );
  }

  Future<List<ServiceRequestModel>> fetchRequests({
    String? status,
    String? search,
  }) async {
    // WHY: Push queue filtering to the backend so the admin request workspace remains usable as request volume grows.
    final response = await _client.getJson(
      '/admin/requests',
      queryParameters: <String, dynamic>{
        if (status != null && status.isNotEmpty) 'status': status,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );

    return (response['requests'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(ServiceRequestModel.fromJson)
        .toList();
  }

  Future<void> assignRequest({
    required String requestId,
    required String staffId,
  }) async {
    await _client.patchJson(
      '/admin/requests/$requestId/assign',
      data: <String, dynamic>{'staffId': staffId},
    );
  }

  Future<void> sendMessage({
    required String requestId,
    required String message,
    String? actionType,
  }) async {
    await _client.postJson(
      '/admin/requests/$requestId/messages',
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
      '/admin/requests/$requestId/messages/attachment',
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

  Future<void> sendInvoice({
    required String requestId,
    required double amount,
    required String dueDate,
    required String paymentMethod,
    required String paymentInstructions,
    String? note,
  }) async {
    await _client.postJson(
      '/admin/requests/$requestId/invoice',
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
      '/admin/requests/$requestId/invoice/proof/review',
      data: <String, dynamic>{'decision': decision, 'reviewNote': reviewNote},
    );
  }

  Future<void> createInvite({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
  }) async {
    await _client.postJson(
      '/admin/staff/invites',
      data: <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
      },
    );
  }

  Future<void> deleteInvite({required String inviteId}) async {
    await _client.deleteJson('/admin/staff/invites/$inviteId');
  }
}
