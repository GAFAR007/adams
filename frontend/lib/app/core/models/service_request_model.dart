/// WHAT: Defines the customer service-request model used across customer, admin, and staff screens.
/// WHY: Requests appear in multiple role-specific dashboards, so one parser should shape them once.
/// HOW: Parse the backend request payload and expose compact nested contact and assignment objects.
library;

import '../../config/app_config.dart';

const String requestMessageActionCustomerUpdateRequest =
    'customer_update_request';
const String requestMessageActionCustomerUploadPaymentProof =
    'customer_upload_payment_proof';
const String paymentMethodSepaBankTransfer = 'sepa_bank_transfer';
const String paymentMethodCashOnCompletion = 'cash_on_completion';
const String paymentRequestStatusSent = 'sent';
const String paymentRequestStatusProofSubmitted = 'proof_submitted';
const String paymentRequestStatusApproved = 'approved';
const String paymentRequestStatusRejected = 'rejected';

String paymentMethodLabelFor(String paymentMethod) {
  return switch (paymentMethod) {
    paymentMethodCashOnCompletion => 'Cash on completion',
    _ => 'SEPA bank transfer',
  };
}

String requestStatusLabelFor(String status) {
  return switch (status) {
    'appointment_confirmed' => 'appointment confirmed',
    'pending_start' => 'pending start',
    'project_started' => 'project started',
    'work_done' => 'work done',
    _ => status.replaceAll('_', ' '),
  };
}

String? _resolveAbsoluteFileUrl(String relativeUrl) {
  if (relativeUrl.trim().isEmpty) {
    return null;
  }

  final apiBaseUri = Uri.tryParse(AppConfig.apiBaseUrl);
  final relativeUri = Uri.tryParse(relativeUrl);
  if (apiBaseUri == null || relativeUri == null) {
    return relativeUrl;
  }

  return apiBaseUri.resolveUri(relativeUri).toString();
}

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
    required this.actionType,
    required this.text,
    required this.attachment,
    required this.createdAt,
  });

  final String id;
  final String senderType;
  final String? senderId;
  final String senderName;
  final String? actionType;
  final String text;
  final RequestMessageAttachmentModel? attachment;
  final DateTime? createdAt;

  bool get isCustomer => senderType == 'customer';
  bool get isStaff => senderType == 'staff';
  bool get isAdmin => senderType == 'admin';
  bool get isAi => senderType == 'ai';
  bool get isSystem => senderType == 'system';
  bool get isCustomerUpdateRequest =>
      actionType == requestMessageActionCustomerUpdateRequest;
  bool get isCustomerUploadPaymentProof =>
      actionType == requestMessageActionCustomerUploadPaymentProof;

  factory RequestMessageModel.fromJson(Map<String, dynamic> json) {
    return RequestMessageModel(
      id: json['id'] as String? ?? '',
      senderType: json['senderType'] as String? ?? 'system',
      senderId: json['senderId'] as String?,
      senderName: json['senderName'] as String? ?? '',
      actionType: json['actionType'] as String?,
      text: json['text'] as String? ?? '',
      attachment: json['attachment'] is Map<String, dynamic>
          ? RequestMessageAttachmentModel.fromJson(
              json['attachment'] as Map<String, dynamic>,
            )
          : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}

class RequestMessageAttachmentModel {
  const RequestMessageAttachmentModel({
    required this.originalName,
    required this.storedName,
    required this.mimeType,
    required this.sizeBytes,
    required this.relativeUrl,
  });

  final String originalName;
  final String storedName;
  final String mimeType;
  final int sizeBytes;
  final String relativeUrl;

  String? get fileUrl => _resolveAbsoluteFileUrl(relativeUrl);

  factory RequestMessageAttachmentModel.fromJson(Map<String, dynamic> json) {
    return RequestMessageAttachmentModel(
      originalName: json['originalName'] as String? ?? '',
      storedName: json['storedName'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      relativeUrl: json['relativeUrl'] as String? ?? '',
    );
  }
}

class RequestPaymentProofModel {
  const RequestPaymentProofModel({
    required this.originalName,
    required this.storedName,
    required this.mimeType,
    required this.sizeBytes,
    required this.relativeUrl,
    required this.uploadedAt,
    required this.note,
  });

  final String originalName;
  final String storedName;
  final String mimeType;
  final int sizeBytes;
  final String relativeUrl;
  final DateTime? uploadedAt;
  final String note;

  String? get fileUrl => _resolveAbsoluteFileUrl(relativeUrl);

  factory RequestPaymentProofModel.fromJson(Map<String, dynamic> json) {
    return RequestPaymentProofModel(
      originalName: json['originalName'] as String? ?? '',
      storedName: json['storedName'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      relativeUrl: json['relativeUrl'] as String? ?? '',
      uploadedAt: DateTime.tryParse(json['uploadedAt'] as String? ?? ''),
      note: json['note'] as String? ?? '',
    );
  }
}

class RequestInvoiceModel {
  const RequestInvoiceModel({
    required this.invoiceNumber,
    required this.amount,
    required this.currency,
    required this.dueDate,
    required this.paymentMethod,
    required this.paymentInstructions,
    required this.note,
    required this.status,
    required this.sentAt,
    required this.sentByRole,
    required this.reviewedAt,
    required this.reviewedByRole,
    required this.reviewNote,
    required this.proof,
  });

  final String invoiceNumber;
  final double amount;
  final String currency;
  final DateTime? dueDate;
  final String paymentMethod;
  final String paymentInstructions;
  final String note;
  final String status;
  final DateTime? sentAt;
  final String? sentByRole;
  final DateTime? reviewedAt;
  final String? reviewedByRole;
  final String reviewNote;
  final RequestPaymentProofModel? proof;

  String get paymentMethodLabel => paymentMethodLabelFor(paymentMethod);
  bool get requiresCustomerProof =>
      paymentMethod == paymentMethodSepaBankTransfer;
  bool get isSent => status == paymentRequestStatusSent;
  bool get isProofSubmitted => status == paymentRequestStatusProofSubmitted;
  bool get isApproved => status == paymentRequestStatusApproved;
  bool get isRejected => status == paymentRequestStatusRejected;
  bool get canCustomerUploadProof =>
      requiresCustomerProof && (isSent || isRejected);

  factory RequestInvoiceModel.fromJson(Map<String, dynamic> json) {
    final amountValue = json['amount'];

    return RequestInvoiceModel(
      invoiceNumber: json['invoiceNumber'] as String? ?? '',
      amount: amountValue is num ? amountValue.toDouble() : 0,
      currency: json['currency'] as String? ?? 'EUR',
      dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
      paymentMethod: json['paymentMethod'] as String? ?? '',
      paymentInstructions: json['paymentInstructions'] as String? ?? '',
      note: json['note'] as String? ?? '',
      status: json['status'] as String? ?? '',
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
      sentByRole: json['sentByRole'] as String?,
      reviewedAt: DateTime.tryParse(json['reviewedAt'] as String? ?? ''),
      reviewedByRole: json['reviewedByRole'] as String?,
      reviewNote: json['reviewNote'] as String? ?? '',
      proof: json['proof'] is Map<String, dynamic>
          ? RequestPaymentProofModel.fromJson(
              json['proof'] as Map<String, dynamic>,
            )
          : null,
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
    required this.invoice,
    required this.contactFullName,
    required this.contactEmail,
    required this.contactPhone,
    required this.customer,
    required this.assignedStaff,
    required this.queueEnteredAt,
    required this.attendedAt,
    required this.projectStartedAt,
    required this.finishedAt,
    required this.closedAt,
    required this.detailsUpdatedAt,
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
  final RequestInvoiceModel? invoice;
  final String contactFullName;
  final String contactEmail;
  final String contactPhone;
  final RequestParty? customer;
  final RequestParty? assignedStaff;
  final DateTime? queueEnteredAt;
  final DateTime? attendedAt;
  final DateTime? projectStartedAt;
  final DateTime? finishedAt;
  final DateTime? closedAt;
  final DateTime? detailsUpdatedAt;
  final int messageCount;
  final List<RequestMessageModel> messages;
  final DateTime? createdAt;

  String get serviceLabel => AppConfig.serviceLabelFor(serviceType);

  RequestMessageModel? get latestMessage =>
      messages.isEmpty ? null : messages.last;

  DateTime? get latestActivityAt {
    DateTime? latest;

    for (final candidate in <DateTime?>[
      createdAt,
      queueEnteredAt,
      attendedAt,
      closedAt,
      latestMessage?.createdAt,
    ]) {
      if (candidate == null) {
        continue;
      }

      if (latest == null || candidate.isAfter(latest)) {
        latest = candidate;
      }
    }

    return latest;
  }

  factory ServiceRequestModel.fromJson(Map<String, dynamic> json) {
    final location =
        json['location'] as Map<String, dynamic>? ?? const <String, dynamic>{};
    final contact =
        json['contactSnapshot'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final parsedMessages =
        (json['messages'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(RequestMessageModel.fromJson)
            .toList()
          ..sort(compareRequestMessagesByCreatedAt);

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
      invoice: json['invoice'] is Map<String, dynamic>
          ? RequestInvoiceModel.fromJson(
              json['invoice'] as Map<String, dynamic>,
            )
          : null,
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
      projectStartedAt: DateTime.tryParse(
        json['projectStartedAt'] as String? ?? '',
      ),
      finishedAt: DateTime.tryParse(json['finishedAt'] as String? ?? ''),
      closedAt: DateTime.tryParse(json['closedAt'] as String? ?? ''),
      detailsUpdatedAt: DateTime.tryParse(
        json['detailsUpdatedAt'] as String? ?? '',
      ),
      messageCount: json['messageCount'] as int? ?? 0,
      messages: parsedMessages,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}

int compareRequestMessagesByCreatedAt(
  RequestMessageModel a,
  RequestMessageModel b,
) {
  final aDate = a.createdAt;
  final bDate = b.createdAt;

  if (aDate == null && bDate == null) {
    return 0;
  }

  if (aDate == null) {
    return -1;
  }

  if (bDate == null) {
    return 1;
  }

  return aDate.compareTo(bDate);
}

int compareServiceRequestsByLatestActivity(
  ServiceRequestModel a,
  ServiceRequestModel b,
) {
  final aDate = a.latestActivityAt;
  final bDate = b.latestActivityAt;

  if (aDate == null && bDate == null) {
    return b.messageCount.compareTo(a.messageCount);
  }

  if (aDate == null) {
    return 1;
  }

  if (bDate == null) {
    return -1;
  }

  final dateCompare = bDate.compareTo(aDate);
  if (dateCompare != 0) {
    return dateCompare;
  }

  return b.messageCount.compareTo(a.messageCount);
}
