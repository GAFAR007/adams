/// WHAT: Defines the customer service-request model used across customer, admin, and staff screens.
/// WHY: Requests appear in multiple role-specific dashboards, so one parser should shape them once.
/// HOW: Parse the backend request payload and expose compact nested contact and assignment objects.
library;

import '../../config/app_config.dart';

class RequestParty {
  const RequestParty({
    required this.id,
    required this.fullName,
    required this.email,
    required this.staffAvailability,
  });

  final String id;
  final String fullName;
  final String email;
  final String? staffAvailability;

  factory RequestParty.fromJson(Map<String, dynamic> json) {
    return RequestParty(
      id: json['id'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      staffAvailability: json['staffAvailability'] as String?,
    );
  }
}

class RequestMessageModel {
  const RequestMessageModel({
    required this.id,
    required this.senderType,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String senderType;
  final String? senderId;
  final String senderName;
  final String text;
  final DateTime? createdAt;

  bool get isCustomer => senderType == 'customer';
  bool get isStaff => senderType == 'staff';
  bool get isAi => senderType == 'ai';
  bool get isSystem => senderType == 'system';

  factory RequestMessageModel.fromJson(Map<String, dynamic> json) {
    return RequestMessageModel(
      id: json['id'] as String? ?? '',
      senderType: json['senderType'] as String? ?? 'system',
      senderId: json['senderId'] as String?,
      senderName: json['senderName'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}

class ServiceRequestModel {
  const ServiceRequestModel({
    required this.id,
    required this.serviceType,
    required this.status,
    required this.source,
    required this.message,
    required this.addressLine1,
    required this.city,
    required this.postalCode,
    required this.preferredDate,
    required this.preferredTimeWindow,
    required this.contactFullName,
    required this.contactEmail,
    required this.contactPhone,
    required this.customer,
    required this.assignedStaff,
    required this.queueEnteredAt,
    required this.attendedAt,
    required this.closedAt,
    required this.messageCount,
    required this.messages,
    required this.createdAt,
  });

  final String id;
  final String serviceType;
  final String status;
  final String source;
  final String message;
  final String addressLine1;
  final String city;
  final String postalCode;
  final DateTime? preferredDate;
  final String preferredTimeWindow;
  final String contactFullName;
  final String contactEmail;
  final String contactPhone;
  final RequestParty? customer;
  final RequestParty? assignedStaff;
  final DateTime? queueEnteredAt;
  final DateTime? attendedAt;
  final DateTime? closedAt;
  final int messageCount;
  final List<RequestMessageModel> messages;
  final DateTime? createdAt;

  String get serviceLabel => AppConfig.serviceLabelFor(serviceType);

  factory ServiceRequestModel.fromJson(Map<String, dynamic> json) {
    final location =
        json['location'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final contact =
        json['contactSnapshot'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return ServiceRequestModel(
      id: json['id'] as String? ?? '',
      serviceType: json['serviceType'] as String? ?? '',
      status: json['status'] as String? ?? '',
      source: json['source'] as String? ?? 'form',
      message: json['message'] as String? ?? '',
      addressLine1: location['addressLine1'] as String? ?? '',
      city: location['city'] as String? ?? '',
      postalCode: location['postalCode'] as String? ?? '',
      preferredDate: DateTime.tryParse(json['preferredDate'] as String? ?? ''),
      preferredTimeWindow: json['preferredTimeWindow'] as String? ?? '',
      contactFullName: contact['fullName'] as String? ?? '',
      contactEmail: contact['email'] as String? ?? '',
      contactPhone: contact['phone'] as String? ?? '',
      customer: json['customer'] is Map<String, dynamic>
          ? RequestParty.fromJson(json['customer'] as Map<String, dynamic>)
          : null,
      assignedStaff: json['assignedStaff'] is Map<String, dynamic>
          ? RequestParty.fromJson(json['assignedStaff'] as Map<String, dynamic>)
          : null,
      queueEnteredAt: DateTime.tryParse(
        json['queueEnteredAt'] as String? ?? '',
      ),
      attendedAt: DateTime.tryParse(json['attendedAt'] as String? ?? ''),
      closedAt: DateTime.tryParse(json['closedAt'] as String? ?? ''),
      messageCount: json['messageCount'] as int? ?? 0,
      messages: (json['messages'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(RequestMessageModel.fromJson)
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}
