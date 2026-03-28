/// WHAT: Defines dashboard models for admin overview data, staff summary data, and staff invites.
/// WHY: Dashboard screens need typed access to KPIs and list payloads from multiple backend endpoints.
/// HOW: Parse the backend JSON contract into immutable Dart models once at the repository boundary.
library;

import 'service_request_model.dart';

class StaffMemberSummary {
  const StaffMemberSummary({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.staffAvailability,
    required this.assignedOpenRequestCount,
    required this.clearedTodayCount,
  });

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String? staffAvailability;
  final int assignedOpenRequestCount;
  final int clearedTodayCount;

  factory StaffMemberSummary.fromJson(Map<String, dynamic> json) {
    return StaffMemberSummary(
      id: json['id'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      staffAvailability: json['staffAvailability'] as String?,
      assignedOpenRequestCount: json['assignedOpenRequestCount'] as int? ?? 0,
      clearedTodayCount: json['clearedTodayCount'] as int? ?? 0,
    );
  }
}

class StaffInviteModel {
  const StaffInviteModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.expiresAt,
    required this.inviteLink,
  });

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final DateTime? expiresAt;
  final String inviteLink;

  factory StaffInviteModel.fromJson(Map<String, dynamic> json) {
    final firstName = json['firstName'] as String? ?? '';
    final lastName = json['lastName'] as String? ?? '';

    return StaffInviteModel(
      id: json['id'] as String? ?? '',
      fullName: '$firstName $lastName'.trim(),
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
      inviteLink: json['inviteLink'] as String? ?? '',
    );
  }
}

class AdminKpis {
  const AdminKpis({
    required this.totalRequests,
    required this.staffCount,
    required this.staffOnlineCount,
    required this.pendingInvitesCount,
    required this.waitingQueueCount,
    required this.activeQueueCount,
    required this.clearedTodayCount,
    required this.countsByStatus,
  });

  final int totalRequests;
  final int staffCount;
  final int staffOnlineCount;
  final int pendingInvitesCount;
  final int waitingQueueCount;
  final int activeQueueCount;
  final int clearedTodayCount;
  final Map<String, int> countsByStatus;

  factory AdminKpis.fromJson(Map<String, dynamic> json) {
    final rawCounts =
        json['countsByStatus'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return AdminKpis(
      totalRequests: json['totalRequests'] as int? ?? 0,
      staffCount: json['staffCount'] as int? ?? 0,
      staffOnlineCount: json['staffOnlineCount'] as int? ?? 0,
      pendingInvitesCount: json['pendingInvitesCount'] as int? ?? 0,
      waitingQueueCount: json['waitingQueueCount'] as int? ?? 0,
      activeQueueCount: json['activeQueueCount'] as int? ?? 0,
      clearedTodayCount: json['clearedTodayCount'] as int? ?? 0,
      countsByStatus: rawCounts.map(
        (key, value) => MapEntry(key, value as int? ?? 0),
      ),
    );
  }
}

class AdminDashboardBundle {
  const AdminDashboardBundle({
    required this.kpis,
    required this.recentRequests,
    required this.requests,
    required this.staff,
    required this.invites,
  });

  final AdminKpis kpis;
  final List<ServiceRequestModel> recentRequests;
  final List<ServiceRequestModel> requests;
  final List<StaffMemberSummary> staff;
  final List<StaffInviteModel> invites;
}

class StaffDashboardBundle {
  const StaffDashboardBundle({
    required this.currentAvailability,
    required this.waitingQueueCount,
    required this.assignedCount,
    required this.quotedCount,
    required this.confirmedCount,
    required this.clearedTodayCount,
    required this.queueRequests,
    required this.assignedRequests,
  });

  final String currentAvailability;
  final int waitingQueueCount;
  final int assignedCount;
  final int quotedCount;
  final int confirmedCount;
  final int clearedTodayCount;
  final List<ServiceRequestModel> queueRequests;
  final List<ServiceRequestModel> assignedRequests;

  factory StaffDashboardBundle.fromJson(Map<String, dynamic> json) {
    final kpis =
        json['kpis'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final queueRequests =
        json['queueRequests'] as List<dynamic>? ?? const <dynamic>[];
    final assignedRequests =
        json['assignedRequests'] as List<dynamic>? ?? const <dynamic>[];

    return StaffDashboardBundle(
      currentAvailability: json['currentAvailability'] as String? ?? 'offline',
      waitingQueueCount: kpis['waitingQueueCount'] as int? ?? 0,
      assignedCount: kpis['assignedCount'] as int? ?? 0,
      quotedCount: kpis['quotedCount'] as int? ?? 0,
      confirmedCount: kpis['confirmedCount'] as int? ?? 0,
      clearedTodayCount: kpis['clearedTodayCount'] as int? ?? 0,
      queueRequests: queueRequests
          .whereType<Map<String, dynamic>>()
          .map(ServiceRequestModel.fromJson)
          .toList(),
      assignedRequests: assignedRequests
          .whereType<Map<String, dynamic>>()
          .map(ServiceRequestModel.fromJson)
          .toList(),
    );
  }
}
