/// WHAT: Defines the customer service-request model used across customer, admin, and staff screens.
/// WHY: Requests appear in multiple role-specific dashboards, so one parser should shape them once.
/// HOW: Parse the backend request payload and expose compact nested contact and assignment objects.
library;

import '../../config/app_config.dart';
import '../i18n/app_language.dart';

const String requestMessageActionCustomerUpdateRequest =
    'customer_update_request';
const String requestMessageActionCustomerUpdateRequestCleared =
    'customer_update_request_cleared';
const String requestMessageActionCustomerUploadPaymentProof =
    'customer_upload_payment_proof';
const String requestMessageActionEstimateUpdated = 'estimate_updated';
// WHY: Site-review booking is a first-class workflow event and should be identifiable in typed thread consumers.
const String requestMessageActionSiteReviewBooked = 'site_review_booked';
const String requestMessageActionSiteReviewReadyForInternalReview =
    'site_review_ready_for_internal_review';
const String requestMessageActionQuoteReadyForInternalReview =
    'quote_ready_for_internal_review';
const String requestMessageActionInternalReviewUpdated =
    'internal_review_updated';
const String requestMessageActionSiteReviewReadyForCustomerCare =
    'site_review_ready_for_customer_care';
const String requestMessageActionQuotationReadyForCustomerCare =
    'quotation_ready_for_customer_care';
const String requestMessageActionQuotationInvalidated = 'quotation_invalidated';
const String requestMessageActionSiteReviewSent = 'site_review_sent';
const String requestMessageActionQuotationSent = 'quotation_sent';
const String requestMessageActionPaymentProofUploadUnlocked =
    'payment_proof_upload_unlocked';
const String paymentMethodSepaBankTransfer = 'sepa_bank_transfer';
const String paymentMethodCashOnCompletion = 'cash_on_completion';
const String paymentMethodStripeCheckout = 'stripe_checkout';
const String paymentRequestStatusSent = 'sent';
const String paymentRequestStatusProofSubmitted = 'proof_submitted';
const String paymentRequestStatusApproved = 'approved';
const String paymentRequestStatusRejected = 'rejected';
const String staffAvailabilityOnline = 'online';
const String requestReviewKindQuotation = 'quotation';
const String requestReviewKindSiteReview = 'site_review';
const String requestAssessmentTypeSiteReviewRequired = 'site_review_required';
const String requestAssessmentStatusSiteVisitCompleted = 'site_visit_completed';
const String requestWorkLogTypeSiteReview = 'site_review';
const String requestWorkLogTypeMainJob = 'main_job';
const String requestQuoteReadinessStatusSiteReviewReadyForInternalReview =
    'site_review_ready_for_internal_review';
const String requestQuoteReadinessStatusSiteReviewReadyForCustomerCare =
    'site_review_ready_for_customer_care';
const String requestQuoteReadinessStatusQuoteReadyForInternalReview =
    'quote_ready_for_internal_review';
const String requestQuoteReadinessStatusQuoteReadyForCustomerCare =
    'quote_ready_for_customer_care';
const int paymentProofWindowHours = 24;

String paymentMethodLabelFor(
  String paymentMethod, {
  AppLanguage language = AppLanguage.english,
}) {
  return switch (paymentMethod) {
    paymentMethodCashOnCompletion => language.pick(
      en: 'Cash on completion',
      de: 'Barzahlung bei Abschluss',
    ),
    paymentMethodStripeCheckout => language.pick(
      en: 'Online card / wallet payment',
      de: 'Online-Karte / Wallet-Zahlung',
    ),
    _ => language.pick(en: 'SEPA bank transfer', de: 'SEPA-Überweisung'),
  };
}

String requestStatusLabelFor(
  String status, {
  AppLanguage language = AppLanguage.english,
}) {
  return switch (status) {
    'submitted' => language.pick(
      en: 'pending estimation',
      de: 'Schätzung ausstehend',
    ),
    'under_review' => language.pick(
      en: 'estimate under review',
      de: 'Schätzung in Prüfung',
    ),
    'assigned' => language.pick(en: 'assigned', de: 'zugewiesen'),
    'quoted' => language.pick(en: 'quoted', de: 'angeboten'),
    'appointment_confirmed' => language.pick(
      en: 'appointment confirmed',
      de: 'Termin bestätigt',
    ),
    'pending_start' => language.pick(
      en: 'pending start',
      de: 'Start ausstehend',
    ),
    'project_started' => language.pick(
      en: 'project started',
      de: 'Arbeit gestartet',
    ),
    'work_done' => language.pick(en: 'work done', de: 'Arbeit erledigt'),
    'closed' => language.pick(en: 'closed', de: 'geschlossen'),
    _ => status.replaceAll('_', ' '),
  };
}

String requestCalendarStatusLabelFor(
  String status, {
  AppLanguage language = AppLanguage.english,
}) {
  return switch (status) {
    'pending_estimation' => language.pick(
      en: 'pending estimation',
      de: 'Schätzung ausstehend',
    ),
    'estimated' => language.pick(en: 'estimated', de: 'geschätzt'),
    'assigned' => language.pick(en: 'assigned', de: 'zugewiesen'),
    'quoted' => language.pick(en: 'quoted', de: 'angeboten'),
    'scheduled' => language.pick(en: 'scheduled', de: 'geplant'),
    'pending_start' => language.pick(
      en: 'pending start',
      de: 'Start ausstehend',
    ),
    'started' => language.pick(en: 'started', de: 'gestartet'),
    'finished' => language.pick(en: 'finished', de: 'fertig'),
    'completed' => language.pick(en: 'completed', de: 'abgeschlossen'),
    _ => requestStatusLabelFor(status, language: language),
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
    required this.role,
    required this.staffType,
    required this.staffAvailability,
  });

  final String id;
  final String fullName;
  final String email;
  final String? role;
  final String? staffType;
  final String? staffAvailability;

  String get staffTypeLabel {
    switch (staffType) {
      case 'customer_care':
        return 'Customer Care';
      case 'contractor':
        return 'Contractor';
      case 'technician':
        return 'Technician';
      default:
        return role == 'admin' ? 'Admin' : 'Staff';
    }
  }

  factory RequestParty.fromJson(Map<String, dynamic> json) {
    return RequestParty(
      id: json['id'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String?,
      staffType: json['staffType'] as String?,
      staffAvailability: json['staffAvailability'] as String?,
    );
  }
}

int? _daysBetweenInclusive(DateTime? start, DateTime? end) {
  if (start == null || end == null || end.isBefore(start)) {
    return null;
  }

  final startDay = DateTime(start.year, start.month, start.day);
  final endDay = DateTime(end.year, end.month, end.day);
  return endDay.difference(startDay).inDays + 1;
}

class RequestEstimationModel {
  const RequestEstimationModel({
    required this.id,
    required this.submittedBy,
    required this.submitterRole,
    required this.submitterStaffType,
    required this.assignmentType,
    required this.stage,
    required this.estimatedStartDate,
    required this.estimatedEndDate,
    required this.estimatedHours,
    required this.estimatedHoursPerDay,
    required this.estimatedDays,
    required this.estimatedDailySchedule,
    required this.cost,
    required this.note,
    required this.inspectionNote,
    required this.siteReviewDate,
    required this.siteReviewStartTime,
    required this.siteReviewEndTime,
    required this.siteReviewCost,
    required this.siteReviewNotes,
    required this.submittedAt,
    required this.isSelected,
    required this.isComplete,
  });

  final String id;
  final RequestParty? submittedBy;
  final String? submitterRole;
  final String? submitterStaffType;
  final String assignmentType;
  final String stage;
  final DateTime? estimatedStartDate;
  final DateTime? estimatedEndDate;
  final double? estimatedHours;
  final double? estimatedHoursPerDay;
  final int? estimatedDays;
  final List<RequestEstimationPlannedDayModel> estimatedDailySchedule;
  final double cost;
  final String note;
  final String inspectionNote;
  final DateTime? siteReviewDate;
  final String siteReviewStartTime;
  final String siteReviewEndTime;
  final double? siteReviewCost;
  final String siteReviewNotes;
  final DateTime? submittedAt;
  final bool isSelected;
  final bool isComplete;

  String get submitterStaffTypeLabel {
    switch (submitterStaffType) {
      case 'customer_care':
        return 'Customer Care';
      case 'contractor':
        return 'Contractor';
      case 'technician':
        return 'Technician';
      default:
        return 'Staff';
    }
  }

  int? get effectiveEstimatedDays =>
      estimatedDays ??
      _daysBetweenInclusive(estimatedStartDate, estimatedEndDate);

  bool get hasSiteReviewBooking =>
      siteReviewDate != null &&
      siteReviewStartTime.trim().isNotEmpty &&
      siteReviewEndTime.trim().isNotEmpty &&
      (siteReviewCost ?? 0) > 0;

  factory RequestEstimationModel.fromJson(Map<String, dynamic> json) {
    final costValue = json['cost'];
    final estimatedHoursValue = json['estimatedHours'];

    return RequestEstimationModel(
      id: json['id'] as String? ?? '',
      submittedBy: json['submittedBy'] is Map<String, dynamic>
          ? RequestParty.fromJson(json['submittedBy'] as Map<String, dynamic>)
          : null,
      submitterRole: json['submitterRole'] as String?,
      submitterStaffType: json['submitterStaffType'] as String?,
      assignmentType: json['assignmentType'] as String? ?? 'internal',
      stage: json['stage'] as String? ?? 'final',
      estimatedStartDate: DateTime.tryParse(
        json['estimatedStartDate'] as String? ?? '',
      ),
      estimatedEndDate: DateTime.tryParse(
        json['estimatedEndDate'] as String? ?? '',
      ),
      estimatedHours: estimatedHoursValue is num
          ? estimatedHoursValue.toDouble()
          : null,
      estimatedHoursPerDay: (json['estimatedHoursPerDay'] as num?)?.toDouble(),
      estimatedDays: json['estimatedDays'] as int?,
      estimatedDailySchedule:
          (json['estimatedDailySchedule'] as List<dynamic>? ??
                  const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(RequestEstimationPlannedDayModel.fromJson)
              .toList(),
      cost: costValue is num ? costValue.toDouble() : 0,
      note: json['note'] as String? ?? '',
      inspectionNote: json['inspectionNote'] as String? ?? '',
      siteReviewDate: DateTime.tryParse(
        json['siteReviewDate'] as String? ?? '',
      ),
      siteReviewStartTime: json['siteReviewStartTime'] as String? ?? '',
      siteReviewEndTime: json['siteReviewEndTime'] as String? ?? '',
      siteReviewCost: (json['siteReviewCost'] as num?)?.toDouble(),
      siteReviewNotes: json['siteReviewNotes'] as String? ?? '',
      submittedAt: DateTime.tryParse(json['submittedAt'] as String? ?? ''),
      isSelected: json['isSelected'] as bool? ?? false,
      isComplete: json['isComplete'] as bool? ?? false,
    );
  }
}

class RequestEstimationPlannedDayModel {
  const RequestEstimationPlannedDayModel({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.hours,
  });

  final DateTime? date;
  final String startTime;
  final String endTime;
  final double? hours;

  factory RequestEstimationPlannedDayModel.fromJson(Map<String, dynamic> json) {
    return RequestEstimationPlannedDayModel(
      date: DateTime.tryParse(json['date'] as String? ?? ''),
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      hours: (json['hours'] as num?)?.toDouble(),
    );
  }
}

class RequestWorkLogModel {
  const RequestWorkLogModel({
    required this.id,
    required this.actor,
    required this.actorRole,
    required this.workType,
    required this.startedAt,
    required this.stoppedAt,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final RequestParty? actor;
  final String? actorRole;
  final String? workType;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final String note;
  final DateTime? createdAt;

  double? get hoursWorked {
    final start = startedAt;
    final stop = stoppedAt;
    if (start == null || stop == null || stop.isBefore(start)) {
      return null;
    }

    return stop.difference(start).inMinutes / 60;
  }

  factory RequestWorkLogModel.fromJson(Map<String, dynamic> json) {
    return RequestWorkLogModel(
      id: json['id'] as String? ?? '',
      actor: json['actor'] is Map<String, dynamic>
          ? RequestParty.fromJson(json['actor'] as Map<String, dynamic>)
          : null,
      actorRole: json['actorRole'] as String?,
      workType: json['workType'] as String?,
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      stoppedAt: DateTime.tryParse(json['stoppedAt'] as String? ?? ''),
      note: json['note'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
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
    required this.actionPayload,
    required this.text,
    required this.attachment,
    required this.createdAt,
  });

  final String id;
  final String senderType;
  final String? senderId;
  final String senderName;
  final String? actionType;
  final Map<String, dynamic>? actionPayload;
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
  bool get isCustomerUpdateRequestCleared =>
      actionType == requestMessageActionCustomerUpdateRequestCleared;
  bool get isCustomerUploadPaymentProof =>
      actionType == requestMessageActionCustomerUploadPaymentProof;
  bool get isEstimateUpdated =>
      actionType == requestMessageActionEstimateUpdated;
  bool get isSiteReviewBooked =>
      actionType == requestMessageActionSiteReviewBooked;
  bool get isSiteReviewReadyForInternalReview =>
      actionType == requestMessageActionSiteReviewReadyForInternalReview;
  bool get isQuoteReadyForInternalReview =>
      actionType == requestMessageActionQuoteReadyForInternalReview;
  bool get isInternalReviewUpdated =>
      actionType == requestMessageActionInternalReviewUpdated;
  bool get isSiteReviewReadyForCustomerCare =>
      actionType == requestMessageActionSiteReviewReadyForCustomerCare;
  bool get isQuotationReadyForCustomerCare =>
      actionType == requestMessageActionQuotationReadyForCustomerCare;
  bool get isQuotationInvalidated =>
      actionType == requestMessageActionQuotationInvalidated;
  bool get isSiteReviewSent => actionType == requestMessageActionSiteReviewSent;
  bool get isQuotationSent => actionType == requestMessageActionQuotationSent;
  bool get isPaymentProofUploadUnlocked =>
      actionType == requestMessageActionPaymentProofUploadUnlocked;

  factory RequestMessageModel.fromJson(Map<String, dynamic> json) {
    return RequestMessageModel(
      id: json['id'] as String? ?? '',
      senderType: json['senderType'] as String? ?? 'system',
      senderId: json['senderId'] as String?,
      senderName: json['senderName'] as String? ?? '',
      actionType: json['actionType'] as String?,
      actionPayload: json['actionPayload'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['actionPayload'] as Map)
          : null,
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

class RequestAccessDetailsModel {
  const RequestAccessDetailsModel({
    required this.accessMethod,
    required this.arrivalContactName,
    required this.arrivalContactPhone,
    required this.accessNotes,
  });

  final String accessMethod;
  final String arrivalContactName;
  final String arrivalContactPhone;
  final String accessNotes;

  factory RequestAccessDetailsModel.fromJson(Map<String, dynamic> json) {
    return RequestAccessDetailsModel(
      accessMethod: json['accessMethod'] as String? ?? '',
      arrivalContactName: json['arrivalContactName'] as String? ?? '',
      arrivalContactPhone: json['arrivalContactPhone'] as String? ?? '',
      accessNotes: json['accessNotes'] as String? ?? '',
    );
  }
}

class RequestMediaSummaryModel {
  const RequestMediaSummaryModel({
    required this.photoCount,
    required this.videoCount,
    required this.documentCount,
  });

  final int photoCount;
  final int videoCount;
  final int documentCount;

  factory RequestMediaSummaryModel.fromJson(Map<String, dynamic> json) {
    return RequestMediaSummaryModel(
      photoCount: json['photoCount'] as int? ?? 0,
      videoCount: json['videoCount'] as int? ?? 0,
      documentCount: json['documentCount'] as int? ?? 0,
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

class RequestInvoicePlannedDayModel {
  const RequestInvoicePlannedDayModel({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.hours,
  });

  final DateTime? date;
  final String startTime;
  final String endTime;
  final double? hours;

  factory RequestInvoicePlannedDayModel.fromJson(Map<String, dynamic> json) {
    return RequestInvoicePlannedDayModel(
      date: DateTime.tryParse(json['date'] as String? ?? ''),
      startTime: json['startTime'] as String? ?? '',
      endTime: json['endTime'] as String? ?? '',
      hours: (json['hours'] as num?)?.toDouble(),
    );
  }
}

class RequestQuoteReviewModel {
  const RequestQuoteReviewModel({
    required this.kind,
    required this.quotedBaseAmount,
    required this.appServiceChargePercent,
    required this.appServiceChargeAmount,
    required this.adminServiceChargePercent,
    required this.adminServiceChargeAmount,
    required this.totalAmount,
    required this.currency,
    required this.selectedEstimationId,
    required this.dueDate,
    required this.siteReviewDate,
    required this.siteReviewStartTime,
    required this.siteReviewEndTime,
    required this.siteReviewNotes,
    required this.plannedStartDate,
    required this.plannedStartTime,
    required this.plannedEndTime,
    required this.plannedHoursPerDay,
    required this.plannedExpectedEndDate,
    required this.plannedDailySchedule,
    required this.paymentMethod,
    required this.paymentInstructions,
    required this.note,
    required this.reviewedAt,
    required this.reviewedByRole,
    required this.reviewedByName,
  });

  final String kind;
  final double quotedBaseAmount;
  final double? appServiceChargePercent;
  final double? appServiceChargeAmount;
  final double? adminServiceChargePercent;
  final double? adminServiceChargeAmount;
  final double totalAmount;
  final String currency;
  final String? selectedEstimationId;
  final DateTime? dueDate;
  final DateTime? siteReviewDate;
  final String siteReviewStartTime;
  final String siteReviewEndTime;
  final String siteReviewNotes;
  final DateTime? plannedStartDate;
  final String plannedStartTime;
  final String plannedEndTime;
  final double? plannedHoursPerDay;
  final DateTime? plannedExpectedEndDate;
  final List<RequestInvoicePlannedDayModel> plannedDailySchedule;
  final String paymentMethod;
  final String paymentInstructions;
  final String note;
  final DateTime? reviewedAt;
  final String? reviewedByRole;
  final String reviewedByName;

  bool get isSiteReview => kind == requestReviewKindSiteReview;
  bool get isQuotation => kind == requestReviewKindQuotation;

  factory RequestQuoteReviewModel.fromJson(Map<String, dynamic> json) {
    final quotedBaseAmountValue = json['quotedBaseAmount'];
    final totalAmountValue = json['totalAmount'];

    return RequestQuoteReviewModel(
      kind: json['kind'] as String? ?? requestReviewKindQuotation,
      quotedBaseAmount: quotedBaseAmountValue is num
          ? quotedBaseAmountValue.toDouble()
          : 0,
      appServiceChargePercent: (json['appServiceChargePercent'] as num?)
          ?.toDouble(),
      appServiceChargeAmount: (json['appServiceChargeAmount'] as num?)
          ?.toDouble(),
      adminServiceChargePercent: (json['adminServiceChargePercent'] as num?)
          ?.toDouble(),
      adminServiceChargeAmount: (json['adminServiceChargeAmount'] as num?)
          ?.toDouble(),
      totalAmount: totalAmountValue is num ? totalAmountValue.toDouble() : 0,
      currency: json['currency'] as String? ?? 'EUR',
      selectedEstimationId: json['selectedEstimationId'] as String?,
      dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
      siteReviewDate: DateTime.tryParse(
        json['siteReviewDate'] as String? ?? '',
      ),
      siteReviewStartTime: json['siteReviewStartTime'] as String? ?? '',
      siteReviewEndTime: json['siteReviewEndTime'] as String? ?? '',
      siteReviewNotes: json['siteReviewNotes'] as String? ?? '',
      plannedStartDate: DateTime.tryParse(
        json['plannedStartDate'] as String? ?? '',
      ),
      plannedStartTime: json['plannedStartTime'] as String? ?? '',
      plannedEndTime: json['plannedEndTime'] as String? ?? '',
      plannedHoursPerDay: (json['plannedHoursPerDay'] as num?)?.toDouble(),
      plannedExpectedEndDate: DateTime.tryParse(
        json['plannedExpectedEndDate'] as String? ?? '',
      ),
      plannedDailySchedule:
          (json['plannedDailySchedule'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(RequestInvoicePlannedDayModel.fromJson)
              .toList(),
      paymentMethod: json['paymentMethod'] as String? ?? '',
      paymentInstructions: json['paymentInstructions'] as String? ?? '',
      note: json['note'] as String? ?? '',
      reviewedAt: DateTime.tryParse(json['reviewedAt'] as String? ?? ''),
      reviewedByRole: json['reviewedByRole'] as String?,
      reviewedByName: json['reviewedByName'] as String? ?? '',
    );
  }
}

class RequestInvoiceModel {
  const RequestInvoiceModel({
    required this.kind,
    required this.invoiceNumber,
    required this.amount,
    required this.quotedBaseAmount,
    required this.appServiceChargePercent,
    required this.appServiceChargeAmount,
    required this.adminServiceChargePercent,
    required this.adminServiceChargeAmount,
    required this.currency,
    required this.dueDate,
    required this.proofUploadDeadlineAt,
    required this.proofUploadUnlockedAt,
    required this.proofUploadUnlockedByRole,
    required this.siteReviewDate,
    required this.siteReviewStartTime,
    required this.siteReviewEndTime,
    required this.siteReviewNotes,
    required this.plannedStartDate,
    required this.plannedStartTime,
    required this.plannedEndTime,
    required this.plannedHoursPerDay,
    required this.plannedExpectedEndDate,
    required this.plannedDailySchedule,
    required this.paymentMethod,
    required this.paymentInstructions,
    required this.note,
    required this.status,
    required this.sentAt,
    required this.sentByRole,
    required this.paymentProvider,
    required this.paymentLinkUrl,
    required this.providerPaymentId,
    required this.paymentReference,
    required this.paidAt,
    required this.providerReceiptUrl,
    required this.receiptNumber,
    required this.receiptRelativeUrl,
    required this.receiptIssuedAt,
    required this.reviewedAt,
    required this.reviewedByRole,
    required this.reviewNote,
    required this.proof,
  });

  final String kind;
  final String invoiceNumber;
  final double amount;
  final double quotedBaseAmount;
  final double? appServiceChargePercent;
  final double? appServiceChargeAmount;
  final double? adminServiceChargePercent;
  final double? adminServiceChargeAmount;
  final String currency;
  final DateTime? dueDate;
  final DateTime? proofUploadDeadlineAt;
  final DateTime? proofUploadUnlockedAt;
  final String? proofUploadUnlockedByRole;
  final DateTime? siteReviewDate;
  final String siteReviewStartTime;
  final String siteReviewEndTime;
  final String siteReviewNotes;
  final DateTime? plannedStartDate;
  final String plannedStartTime;
  final String plannedEndTime;
  final double? plannedHoursPerDay;
  final DateTime? plannedExpectedEndDate;
  final List<RequestInvoicePlannedDayModel> plannedDailySchedule;
  final String paymentMethod;
  final String paymentInstructions;
  final String note;
  final String status;
  final DateTime? sentAt;
  final String? sentByRole;
  final String? paymentProvider;
  final String? paymentLinkUrl;
  final String? providerPaymentId;
  final String? paymentReference;
  final DateTime? paidAt;
  final String? providerReceiptUrl;
  final String? receiptNumber;
  final String? receiptRelativeUrl;
  final DateTime? receiptIssuedAt;
  final DateTime? reviewedAt;
  final String? reviewedByRole;
  final String reviewNote;
  final RequestPaymentProofModel? proof;

  bool get isSiteReview => kind == requestReviewKindSiteReview;
  bool get isQuotation => kind == requestReviewKindQuotation;
  String get paymentMethodLabel => paymentMethodLabelFor(paymentMethod);
  String paymentMethodLabelForLanguage(AppLanguage language) =>
      paymentMethodLabelFor(paymentMethod, language: language);
  bool get requiresCustomerProof =>
      paymentMethod == paymentMethodSepaBankTransfer;
  bool get supportsOnlineCheckout =>
      paymentMethod == paymentMethodStripeCheckout;
  // WHY: Admin can choose every payment method, but customer-side online and cash collection are intentionally locked until those flows are fully operational.
  bool get isCustomerPaymentMethodLocked =>
      paymentMethod == paymentMethodStripeCheckout ||
      paymentMethod == paymentMethodCashOnCompletion;
  bool get isSent => status == paymentRequestStatusSent;
  bool get isProofSubmitted => status == paymentRequestStatusProofSubmitted;
  bool get isApproved => status == paymentRequestStatusApproved;
  bool get isRejected => status == paymentRequestStatusRejected;
  bool get isProofUploadUnlocked => proofUploadUnlockedAt != null;
  bool get isProofUploadExpired {
    final deadline = proofUploadDeadlineAt;
    if (deadline == null || isProofUploadUnlocked) {
      return false;
    }

    return DateTime.now().toUtc().isAfter(deadline.toUtc());
  }

  bool get canCustomerUploadProof =>
      requiresCustomerProof && (isSent || isRejected) && !isProofUploadExpired;
  bool get canCustomerPayOnline =>
      supportsOnlineCheckout &&
      !isCustomerPaymentMethodLocked &&
      !isApproved &&
      (paymentLinkUrl?.trim().isNotEmpty ?? false);
  String? get receiptFileUrl =>
      _resolveAbsoluteFileUrl(receiptRelativeUrl ?? '');
  String? get receiptUrl => receiptFileUrl ?? providerReceiptUrl;

  factory RequestInvoiceModel.fromJson(Map<String, dynamic> json) {
    final amountValue = json['amount'];
    final quotedBaseAmountValue = json['quotedBaseAmount'];

    return RequestInvoiceModel(
      kind: json['kind'] as String? ?? requestReviewKindQuotation,
      invoiceNumber: json['invoiceNumber'] as String? ?? '',
      amount: amountValue is num ? amountValue.toDouble() : 0,
      quotedBaseAmount: quotedBaseAmountValue is num
          ? quotedBaseAmountValue.toDouble()
          : 0,
      appServiceChargePercent: (json['appServiceChargePercent'] as num?)
          ?.toDouble(),
      appServiceChargeAmount: (json['appServiceChargeAmount'] as num?)
          ?.toDouble(),
      adminServiceChargePercent: (json['adminServiceChargePercent'] as num?)
          ?.toDouble(),
      adminServiceChargeAmount: (json['adminServiceChargeAmount'] as num?)
          ?.toDouble(),
      currency: json['currency'] as String? ?? 'EUR',
      dueDate: DateTime.tryParse(json['dueDate'] as String? ?? ''),
      proofUploadDeadlineAt: DateTime.tryParse(
        json['proofUploadDeadlineAt'] as String? ?? '',
      ),
      proofUploadUnlockedAt: DateTime.tryParse(
        json['proofUploadUnlockedAt'] as String? ?? '',
      ),
      proofUploadUnlockedByRole: json['proofUploadUnlockedByRole'] as String?,
      siteReviewDate: DateTime.tryParse(
        json['siteReviewDate'] as String? ?? '',
      ),
      siteReviewStartTime: json['siteReviewStartTime'] as String? ?? '',
      siteReviewEndTime: json['siteReviewEndTime'] as String? ?? '',
      siteReviewNotes: json['siteReviewNotes'] as String? ?? '',
      plannedStartDate: DateTime.tryParse(
        json['plannedStartDate'] as String? ?? '',
      ),
      plannedStartTime: json['plannedStartTime'] as String? ?? '',
      plannedEndTime: json['plannedEndTime'] as String? ?? '',
      plannedHoursPerDay: (json['plannedHoursPerDay'] as num?)?.toDouble(),
      plannedExpectedEndDate: DateTime.tryParse(
        json['plannedExpectedEndDate'] as String? ?? '',
      ),
      plannedDailySchedule:
          (json['plannedDailySchedule'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(RequestInvoicePlannedDayModel.fromJson)
              .toList(),
      paymentMethod: json['paymentMethod'] as String? ?? '',
      paymentInstructions: json['paymentInstructions'] as String? ?? '',
      note: json['note'] as String? ?? '',
      status: json['status'] as String? ?? '',
      sentAt: DateTime.tryParse(json['sentAt'] as String? ?? ''),
      sentByRole: json['sentByRole'] as String?,
      paymentProvider: json['paymentProvider'] as String?,
      paymentLinkUrl: json['paymentLinkUrl'] as String?,
      providerPaymentId: json['providerPaymentId'] as String?,
      paymentReference: json['paymentReference'] as String?,
      paidAt: DateTime.tryParse(json['paidAt'] as String? ?? ''),
      providerReceiptUrl: json['providerReceiptUrl'] as String?,
      receiptNumber: json['receiptNumber'] as String?,
      receiptRelativeUrl: json['receiptRelativeUrl'] as String?,
      receiptIssuedAt: DateTime.tryParse(
        json['receiptIssuedAt'] as String? ?? '',
      ),
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
    required this.accessDetails,
    required this.mediaSummary,
    required this.assessmentType,
    required this.assessmentStatus,
    required this.quoteReadinessStatus,
    required this.latestEstimateUpdatedAt,
    required this.internalReviewUpdatedAt,
    required this.quoteReadyAt,
    required this.quoteReview,
    required this.invoice,
    required this.contactFullName,
    required this.contactEmail,
    required this.contactPhone,
    required this.customer,
    required this.assignedStaff,
    required this.estimations,
    required this.selectedEstimation,
    required this.selectedEstimationId,
    required this.hasCompleteEstimation,
    required this.estimationCount,
    required this.completeEstimationCount,
    required this.calendarStatus,
    required this.calendarStartDate,
    required this.calendarEndDate,
    required this.calendarSource,
    required this.estimatedStartDate,
    required this.estimatedEndDate,
    required this.estimatedHours,
    required this.estimatedHoursPerDay,
    required this.estimatedDays,
    required this.estimatedCost,
    required this.actualStartDate,
    required this.actualEndDate,
    required this.totalHoursWorked,
    required this.totalDaysWorked,
    required this.aiControlEnabled,
    required this.queueEnteredAt,
    required this.attendedAt,
    required this.projectStartedAt,
    required this.finishedAt,
    required this.closedAt,
    required this.detailsUpdatedAt,
    required this.messageCount,
    required this.messages,
    required this.workLogs,
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
  final RequestAccessDetailsModel? accessDetails;
  final RequestMediaSummaryModel? mediaSummary;
  final String? assessmentType;
  final String? assessmentStatus;
  final String? quoteReadinessStatus;
  final DateTime? latestEstimateUpdatedAt;
  final DateTime? internalReviewUpdatedAt;
  final DateTime? quoteReadyAt;
  final RequestQuoteReviewModel? quoteReview;
  final RequestInvoiceModel? invoice;
  final String contactFullName;
  final String contactEmail;
  final String contactPhone;
  final RequestParty? customer;
  final RequestParty? assignedStaff;
  final List<RequestEstimationModel> estimations;
  final RequestEstimationModel? selectedEstimation;
  final String? selectedEstimationId;
  final bool hasCompleteEstimation;
  final int estimationCount;
  final int completeEstimationCount;
  final String calendarStatus;
  final DateTime? calendarStartDate;
  final DateTime? calendarEndDate;
  final String? calendarSource;
  final DateTime? estimatedStartDate;
  final DateTime? estimatedEndDate;
  final double? estimatedHours;
  final double? estimatedHoursPerDay;
  final int? estimatedDays;
  final double? estimatedCost;
  final DateTime? actualStartDate;
  final DateTime? actualEndDate;
  final double totalHoursWorked;
  final int totalDaysWorked;
  final bool aiControlEnabled;
  final DateTime? queueEnteredAt;
  final DateTime? attendedAt;
  final DateTime? projectStartedAt;
  final DateTime? finishedAt;
  final DateTime? closedAt;
  final DateTime? detailsUpdatedAt;
  final int messageCount;
  final List<RequestMessageModel> messages;
  final List<RequestWorkLogModel> workLogs;
  final DateTime? createdAt;

  String get serviceLabel => AppConfig.serviceLabelFor(serviceType);
  String serviceLabelForLanguage(AppLanguage language) =>
      AppConfig.serviceLabelFor(serviceType, language: language);

  RequestMessageModel? get latestMessage =>
      messages.isEmpty ? null : messages.last;

  RequestEstimationModel? get quoteReadyEstimation {
    if (selectedEstimation != null) {
      return selectedEstimation;
    }

    final completeEstimations = estimations.where((item) => item.isComplete);
    if (completeEstimations.isEmpty) {
      return null;
    }

    final sorted = completeEstimations.toList()
      ..sort((left, right) {
        final leftDate =
            left.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            right.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return leftDate.compareTo(rightDate);
      });
    return sorted.last;
  }

  RequestEstimationModel? get siteReviewReadyEstimation {
    if (selectedEstimation?.hasSiteReviewBooking == true) {
      return selectedEstimation;
    }

    final readyEstimations = estimations
        .where((item) => item.hasSiteReviewBooking)
        .toList(growable: false);
    if (readyEstimations.isEmpty) {
      return null;
    }

    final sorted = readyEstimations.toList()
      ..sort((left, right) {
        final leftDate =
            left.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightDate =
            right.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return leftDate.compareTo(rightDate);
      });
    return sorted.last;
  }

  bool get needsEstimation => !hasCompleteEstimation;
  bool get isQuoteReadyForInternalReview =>
      quoteReadinessStatus ==
      requestQuoteReadinessStatusQuoteReadyForInternalReview;
  bool get isSiteReviewReadyForInternalReview =>
      quoteReadinessStatus ==
      requestQuoteReadinessStatusSiteReviewReadyForInternalReview;
  bool get isQuoteReadyForCustomerCare =>
      quoteReadinessStatus ==
      requestQuoteReadinessStatusQuoteReadyForCustomerCare;
  bool get isSiteReviewReadyForCustomerCare =>
      quoteReadinessStatus ==
      requestQuoteReadinessStatusSiteReviewReadyForCustomerCare;
  bool get isQuotedReadyStateLocked => quoteReadinessStatus == 'quoted';
  bool get hasQuoteReview => quoteReview != null;
  bool get canCustomerCareSendQuotation =>
      (isQuoteReadyForCustomerCare || isSiteReviewReadyForCustomerCare) &&
      quoteReview != null &&
      (invoice == null ||
          (isQuoteReadyForCustomerCare && invoice?.isSiteReview == true) ||
          (isSiteReviewReadyForCustomerCare && invoice?.isQuotation == true));
  bool get isSiteReviewRequired =>
      assessmentType == requestAssessmentTypeSiteReviewRequired;
  bool get isSiteReviewPending =>
      isSiteReviewRequired &&
      assessmentStatus != requestAssessmentStatusSiteVisitCompleted;
  bool get isFinalEstimatePricingLocked => isSiteReviewPending;

  bool get estimationLocked =>
      status == 'quoted' ||
      status == 'appointment_confirmed' ||
      status == 'pending_start' ||
      status == 'project_started' ||
      status == 'work_done' ||
      status == 'closed';

  RequestEstimationModel? estimationForSubmitter(String userId) {
    if (userId.trim().isEmpty) {
      return null;
    }

    for (final estimation in estimations) {
      if (estimation.submittedBy?.id == userId) {
        return estimation;
      }
    }

    return null;
  }

  bool get isAssignedStaffOnline =>
      assignedStaff?.staffAvailability == staffAvailabilityOnline;

  bool get isAiInControl =>
      assignedStaff == null || aiControlEnabled || !isAssignedStaffOnline;

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
    final parsedEstimations =
        (json['estimations'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(RequestEstimationModel.fromJson)
            .toList()
          ..sort(compareRequestEstimationsBySubmittedAt);
    final parsedWorkLogs =
        (json['workLogs'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(RequestWorkLogModel.fromJson)
            .toList();

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
      accessDetails: json['accessDetails'] is Map<String, dynamic>
          ? RequestAccessDetailsModel.fromJson(
              json['accessDetails'] as Map<String, dynamic>,
            )
          : null,
      mediaSummary: json['mediaSummary'] is Map<String, dynamic>
          ? RequestMediaSummaryModel.fromJson(
              json['mediaSummary'] as Map<String, dynamic>,
            )
          : null,
      assessmentType: json['assessmentType'] as String?,
      assessmentStatus: json['assessmentStatus'] as String?,
      quoteReadinessStatus: json['quoteReadinessStatus'] as String?,
      latestEstimateUpdatedAt: DateTime.tryParse(
        json['latestEstimateUpdatedAt'] as String? ?? '',
      ),
      internalReviewUpdatedAt: DateTime.tryParse(
        json['internalReviewUpdatedAt'] as String? ?? '',
      ),
      quoteReadyAt: DateTime.tryParse(json['quoteReadyAt'] as String? ?? ''),
      quoteReview: json['quoteReview'] is Map<String, dynamic>
          ? RequestQuoteReviewModel.fromJson(
              json['quoteReview'] as Map<String, dynamic>,
            )
          : null,
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
      estimations: parsedEstimations,
      selectedEstimation: json['selectedEstimation'] is Map<String, dynamic>
          ? RequestEstimationModel.fromJson(
              json['selectedEstimation'] as Map<String, dynamic>,
            )
          : null,
      selectedEstimationId: json['selectedEstimationId'] as String?,
      hasCompleteEstimation: json['hasCompleteEstimation'] as bool? ?? false,
      estimationCount:
          json['estimationCount'] as int? ?? parsedEstimations.length,
      completeEstimationCount:
          json['completeEstimationCount'] as int? ??
          parsedEstimations.where((item) => item.isComplete).length,
      calendarStatus: json['calendarStatus'] as String? ?? 'pending_estimation',
      calendarStartDate: DateTime.tryParse(
        json['calendarStartDate'] as String? ?? '',
      ),
      calendarEndDate: DateTime.tryParse(
        json['calendarEndDate'] as String? ?? '',
      ),
      calendarSource: json['calendarSource'] as String?,
      estimatedStartDate: DateTime.tryParse(
        json['estimatedStartDate'] as String? ?? '',
      ),
      estimatedEndDate: DateTime.tryParse(
        json['estimatedEndDate'] as String? ?? '',
      ),
      estimatedHours: (json['estimatedHours'] as num?)?.toDouble(),
      estimatedHoursPerDay: (json['estimatedHoursPerDay'] as num?)?.toDouble(),
      estimatedDays: json['estimatedDays'] as int?,
      estimatedCost: (json['estimatedCost'] as num?)?.toDouble(),
      actualStartDate: DateTime.tryParse(
        json['actualStartDate'] as String? ?? '',
      ),
      actualEndDate: DateTime.tryParse(json['actualEndDate'] as String? ?? ''),
      totalHoursWorked: (json['totalHoursWorked'] as num?)?.toDouble() ?? 0,
      totalDaysWorked: json['totalDaysWorked'] as int? ?? 0,
      aiControlEnabled: json['aiControlEnabled'] as bool? ?? false,
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
      workLogs: parsedWorkLogs,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    );
  }
}

int compareRequestEstimationsBySubmittedAt(
  RequestEstimationModel a,
  RequestEstimationModel b,
) {
  final aDate = a.submittedAt;
  final bDate = b.submittedAt;

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
