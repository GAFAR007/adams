library;

import '../../core/i18n/app_language.dart';
import '../../core/models/service_request_model.dart';

const String requestAttachmentCategoryRequestUpload = 'request_upload';
const String requestAttachmentCategoryRequestUpdateUpload =
    'request_update_upload';
const String requestAttachmentCategorySiteReviewUpload = 'site_review_upload';
const String requestAttachmentCategorySiteReviewProofUpload =
    'site_review_proof_upload';
const String requestAttachmentCategoryInvoiceUpload = 'invoice_upload';
const String requestAttachmentCategoryInvoiceProofUpload =
    'invoice_proof_upload';
const String requestAttachmentCategoryOtherUpload = 'other_upload';
const String requestAttachmentStageRequest = 'request_stage';
const String requestAttachmentStageSiteReview = 'site_review_stage';
const String requestAttachmentStageInvoice = 'invoice_stage';
const String requestAttachmentStageProof = 'proof_stage';
const String requestAttachmentStageOther = 'other_stage';

String requestAttachmentCategoryForMessage(RequestMessageModel message) {
  final payload = message.actionPayload ?? const <String, dynamic>{};
  final payloadCategory = payload['attachmentCategory'];
  if (payloadCategory is String && payloadCategory.trim().isNotEmpty) {
    return payloadCategory.trim();
  }

  final text = message.text.trim().toLowerCase();
  if (message.isCustomerUploadPaymentProof) {
    final invoiceKind = (payload['invoiceKind'] as String? ?? '')
        .trim()
        .toLowerCase();
    if (invoiceKind == requestReviewKindSiteReview ||
        text.contains('site review')) {
      return requestAttachmentCategorySiteReviewProofUpload;
    }

    return requestAttachmentCategoryInvoiceProofUpload;
  }

  if (text.startsWith('shared intake photo') ||
      text.startsWith('shared intake video')) {
    return requestAttachmentCategoryRequestUpload;
  }

  if (text.contains('site review')) {
    return requestAttachmentCategorySiteReviewUpload;
  }

  if (text.contains('invoice') || text.contains('quotation')) {
    return requestAttachmentCategoryInvoiceUpload;
  }

  if (text.startsWith('shared a file') || text.isNotEmpty) {
    return requestAttachmentCategoryRequestUpdateUpload;
  }

  return requestAttachmentCategoryOtherUpload;
}

String requestAttachmentStageForCategory(String category) {
  return switch (category) {
    requestAttachmentCategoryRequestUpload ||
    requestAttachmentCategoryRequestUpdateUpload =>
      requestAttachmentStageRequest,
    requestAttachmentCategorySiteReviewUpload =>
      requestAttachmentStageSiteReview,
    requestAttachmentCategoryInvoiceUpload => requestAttachmentStageInvoice,
    requestAttachmentCategorySiteReviewProofUpload ||
    requestAttachmentCategoryInvoiceProofUpload => requestAttachmentStageProof,
    _ => requestAttachmentStageOther,
  };
}

int requestAttachmentStageOrder(String stage) {
  return switch (stage) {
    requestAttachmentStageRequest => 0,
    requestAttachmentStageSiteReview => 1,
    requestAttachmentStageInvoice => 2,
    requestAttachmentStageProof => 3,
    _ => 4,
  };
}

String requestAttachmentStageLabel(
  String stage, {
  required AppLanguage language,
}) {
  return switch (stage) {
    requestAttachmentStageRequest => language.pick(
      en: 'Request uploads',
      de: 'Anfrage-Uploads',
    ),
    requestAttachmentStageSiteReview => language.pick(
      en: 'Site review uploads',
      de: 'Vor-Ort-Termin-Uploads',
    ),
    requestAttachmentStageInvoice => language.pick(
      en: 'Invoice uploads',
      de: 'Rechnungs-Uploads',
    ),
    requestAttachmentStageProof => language.pick(
      en: 'Proof uploads',
      de: 'Nachweis-Uploads',
    ),
    _ => language.pick(en: 'Other files', de: 'Weitere Dateien'),
  };
}

String requestAttachmentDisplayNameForMessage(
  RequestMessageModel message, {
  required AppLanguage language,
  int? categoryIndex,
}) {
  final category = requestAttachmentCategoryForMessage(message);
  final baseLabel = switch (category) {
    requestAttachmentCategoryRequestUpload ||
    requestAttachmentCategoryRequestUpdateUpload => language.pick(
      en: 'Request upload',
      de: 'Anfrage-Upload',
    ),
    requestAttachmentCategorySiteReviewUpload => language.pick(
      en: 'Site review upload',
      de: 'Vor-Ort-Termin-Upload',
    ),
    requestAttachmentCategorySiteReviewProofUpload => language.pick(
      en: 'Site review proof upload',
      de: 'Vor-Ort-Termin-Nachweis-Upload',
    ),
    requestAttachmentCategoryInvoiceUpload => language.pick(
      en: 'Invoice upload',
      de: 'Rechnungs-Upload',
    ),
    requestAttachmentCategoryInvoiceProofUpload => language.pick(
      en: 'Invoice proof upload',
      de: 'Rechnungs-Nachweis-Upload',
    ),
    _ => language.pick(en: 'Shared file', de: 'Geteilte Datei'),
  };

  if (categoryIndex == null || categoryIndex < 1) {
    return baseLabel;
  }

  return '$baseLabel ${categoryIndex.toString().padLeft(2, '0')}';
}
