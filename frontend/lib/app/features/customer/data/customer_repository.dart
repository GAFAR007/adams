/// WHAT: Calls backend customer endpoints for request creation and request history retrieval.
/// WHY: Customer screens should not know about raw HTTP details or backend JSON parsing.
/// HOW: Fetch and parse customer request payloads through the shared API client.
library;

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
    return items.whereType<Map<String, dynamic>>().map(ServiceRequestModel.fromJson).toList();
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

  Future<void> sendMessage({
    required String requestId,
    required String message,
  }) async {
    await _client.postJson(
      '/customer/requests/$requestId/messages',
      data: <String, dynamic>{'message': message},
    );
  }
}
