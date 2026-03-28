/// WHAT: Calls backend endpoints for invite registration, staff dashboards, queue pickup, and request-thread actions.
/// WHY: Staff screens should stay independent from backend wire details while still exposing the full live-queue workflow.
/// HOW: Use the shared API client to fetch the dashboard snapshot and send small queue, availability, status, and message actions.
library;

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

  Future<ServiceRequestModel> attendQueueRequest({required String requestId}) async {
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
  }) async {
    await _client.postJson(
      '/staff/requests/$requestId/messages',
      data: <String, dynamic>{'message': message},
    );
  }
}
