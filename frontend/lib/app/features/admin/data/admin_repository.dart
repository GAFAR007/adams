/// WHAT: Calls admin endpoints for dashboard overview, request assignment, staff, and invite management.
/// WHY: Admin screens need a single repository to gather the multiple payloads that feed the dashboard.
/// HOW: Fetch each compact endpoint, parse the returned models, and expose small admin actions.
library;

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

  Future<AdminDashboardBundle> fetchDashboardBundle() async {
    final dashboard = await _client.getJson('/admin/dashboard');
    final requests = await _client.getJson('/admin/requests');
    final staff = await _client.getJson('/admin/staff');
    final invites = await _client.getJson('/admin/staff/invites');

    final recentRequests =
        (dashboard['recentRequests'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(ServiceRequestModel.fromJson)
            .toList();
    final requestItems =
        (requests['requests'] as List<dynamic>? ?? const <dynamic>[])
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
      requests: requestItems,
      staff: staffItems,
      invites: inviteItems,
    );
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
