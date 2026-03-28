/// WHAT: Calls backend customer endpoints for request creation and request history retrieval.
/// WHY: Customer screens should not know about raw HTTP details or backend JSON parsing.
/// HOW: Fetch and parse customer request payloads through the shared API client.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/service_request_model.dart';
import '../../../core/network/api_client.dart';

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref.read(apiClientProvider));
});

class CustomerRepository {
  const CustomerRepository(this._client);

  final ApiClient _client;

  Future<List<ServiceRequestModel>> fetchRequests() async {
    final response = await _client.getJson('/customer/requests');
    final items = response['requests'] as List<dynamic>? ?? const <dynamic>[];
    final requests =
        items
            .whereType<Map<String, dynamic>>()
            .map(ServiceRequestModel.fromJson)
            .toList()
          ..sort(compareServiceRequestsByLatestActivity);

    return requests;
  }

  Future<void> createRequest({
    required String serviceType,
    required String addressLine1,
    required String city,
    required String postalCode,
    required String preferredDate,
    required String preferredTimeWindow,
    required String message,
  }) async {
    await _client.postJson(
      '/customer/requests',
      data: <String, dynamic>{
        'serviceType': serviceType,
        'addressLine1': addressLine1,
        'city': city,
        'postalCode': postalCode,
        'preferredDate': preferredDate.isEmpty ? null : preferredDate,
        'preferredTimeWindow': preferredTimeWindow,
        'message': message,
      },
    );
  }

  Future<void> updateRequest({
    required String requestId,
    required String serviceType,
    required String addressLine1,
    required String city,
    required String postalCode,
    required String preferredDate,
    required String preferredTimeWindow,
    required String message,
  }) async {
    await _client.patchJson(
      '/customer/requests/$requestId',
      data: <String, dynamic>{
        'serviceType': serviceType,
        'addressLine1': addressLine1,
        'city': city,
        'postalCode': postalCode,
        'preferredDate': preferredDate.isEmpty ? null : preferredDate,
        'preferredTimeWindow': preferredTimeWindow,
        'message': message,
      },
    );
  }

  Future<void> sendMessage({
    required String requestId,
    required String message,
  }) async {
    await _client.postJson(
      '/customer/requests/$requestId/messages',
      data: <String, dynamic>{'message': message},
    );
  }

  Future<void> uploadRequestAttachment({
    required String requestId,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    String? caption,
  }) async {
    await _client.postFormData(
      '/customer/requests/$requestId/messages/attachment',
      data: FormData.fromMap(<String, dynamic>{
        'attachment': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(mimeType),
        ),
        if (caption != null && caption.trim().isNotEmpty)
          'caption': caption.trim(),
      }),
    );
  }

  Future<void> uploadPaymentProof({
    required String requestId,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    String? note,
  }) async {
    await _client.postFormData(
      '/customer/requests/$requestId/invoice/proof',
      data: FormData.fromMap(<String, dynamic>{
        'proof': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(mimeType),
        ),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      }),
    );
  }
}
