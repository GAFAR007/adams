/**
 * WHAT: Builds normalized request-chat message payloads for customer, staff, system, and AI events.
 * WHY: Queue and chat flows need one consistent message shape so services do not duplicate sender metadata rules.
 * HOW: Expose small helper builders that return message objects ready to append onto `ServiceRequest.messages`.
 */

const {
  REQUEST_ASSESSMENT_STATUSES,
  REQUEST_ASSESSMENT_TYPES,
  REQUEST_MESSAGE_SENDERS,
  REQUEST_REVIEW_KINDS,
  REQUEST_STATUSES,
} = require('../constants/app.constants');

const REQUEST_ATTACHMENT_CATEGORIES = Object.freeze({
  REQUEST_UPLOAD: 'request_upload',
  REQUEST_UPDATE_UPLOAD: 'request_update_upload',
  SITE_REVIEW_UPLOAD: 'site_review_upload',
  SITE_REVIEW_PROOF_UPLOAD: 'site_review_proof_upload',
  INVOICE_UPLOAD: 'invoice_upload',
  INVOICE_PROOF_UPLOAD: 'invoice_proof_upload',
});

function buildBaseMessage({
  senderType,
  senderId = null,
  senderName,
  text,
  actionType = null,
  actionPayload = null,
  attachment = null,
}) {
  // WHY: Trim message text once here so every caller stores the same clean payload shape.
  return {
    senderType,
    senderId,
    senderName,
    actionType,
    actionPayload,
    text: text.trim(),
    attachment,
    createdAt: new Date(),
  };
}

function buildRequestMessageAttachment(file, relativeUrl = file?.relativeUrl) {
  if (!file || !relativeUrl) {
    return null;
  }

  return {
    originalName: file.originalName || file.originalname || 'attachment',
    storedName: file.storedName || file.filename || '',
    mimeType: file.mimeType || file.mimetype || 'application/octet-stream',
    sizeBytes: file.sizeBytes || file.size || 0,
    relativeUrl,
  };
}

function resolveAttachmentMediaKind(mimeType = '') {
  if (mimeType.startsWith('image/')) {
    return 'image';
  }

  if (mimeType.startsWith('video/')) {
    return 'video';
  }

  if (
    mimeType.includes('pdf') ||
    mimeType.includes('word') ||
    mimeType.includes('document') ||
    mimeType.startsWith('text/')
  ) {
    return 'document';
  }

  return 'file';
}

function resolveWorkflowAttachmentCategory(request) {
  if (
    request?.status === REQUEST_STATUSES.QUOTED ||
    request?.invoice?.kind === REQUEST_REVIEW_KINDS.QUOTATION
  ) {
    return REQUEST_ATTACHMENT_CATEGORIES.INVOICE_UPLOAD;
  }

  const siteReviewStillActive =
    request?.assessmentType === REQUEST_ASSESSMENT_TYPES.SITE_REVIEW_REQUIRED ||
    request?.assessmentStatus ===
      REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_REQUIRED ||
    request?.assessmentStatus ===
      REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_SCHEDULED ||
    request?.assessmentStatus ===
      REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_COMPLETED ||
    request?.invoice?.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW;

  if (siteReviewStillActive) {
    return REQUEST_ATTACHMENT_CATEGORIES.SITE_REVIEW_UPLOAD;
  }

  return REQUEST_ATTACHMENT_CATEGORIES.REQUEST_UPDATE_UPLOAD;
}

function buildAttachmentActionPayload({
  attachmentCategory,
  mimeType = '',
  sequence = null,
  invoiceKind = null,
} = {}) {
  return {
    attachmentCategory,
    attachmentMediaKind: resolveAttachmentMediaKind(mimeType),
    attachmentSequence: sequence,
    invoiceKind,
  };
}

function buildCustomerMessage({
  customerId,
  customerName,
  text,
  actionType = null,
  actionPayload = null,
  attachment = null,
}) {
  // WHY: Customer messages should always carry the account owner id so later audit or threading work can trace authorship.
  return buildBaseMessage({
    senderType: REQUEST_MESSAGE_SENDERS.CUSTOMER,
    senderId: customerId,
    senderName: customerName,
    actionType,
    actionPayload,
    text,
    attachment,
  });
}

function buildStaffMessage({
  staffId,
  staffName,
  text,
  actionType = null,
  actionPayload = null,
  attachment = null,
}) {
  // WHY: Staff replies need the responder identity so customers know exactly who joined the thread.
  return buildBaseMessage({
    senderType: REQUEST_MESSAGE_SENDERS.STAFF,
    senderId: staffId,
    senderName: staffName,
    actionType,
    actionPayload,
    text,
    attachment,
  });
}

function buildAdminMessage({
  adminId,
  adminName,
  text,
  actionType = null,
  actionPayload = null,
  attachment = null,
}) {
  // WHY: Admin-authored workflow messages should still render like a human participant instead of a system note.
  return buildBaseMessage({
    senderType: REQUEST_MESSAGE_SENDERS.ADMIN,
    senderId: adminId,
    senderName: adminName,
    actionType,
    actionPayload,
    text,
    attachment,
  });
}

function buildSystemMessage(
  text,
  {
    actionType = null,
    actionPayload = null,
  } = {},
) {
  // WHY: System notices describe workflow changes without pretending to be a human participant.
  return buildBaseMessage({
    senderType: REQUEST_MESSAGE_SENDERS.SYSTEM,
    senderName: 'System',
    actionType,
    actionPayload,
    text,
  });
}

function buildAiMessage(text) {
  // WHY: AI placeholder messages should be clearly labeled so customers can tell they are not from staff.
  return buildBaseMessage({
    senderType: REQUEST_MESSAGE_SENDERS.AI,
    senderName: 'Naima AI',
    text,
  });
}

module.exports = {
  REQUEST_ATTACHMENT_CATEGORIES,
  buildAttachmentActionPayload,
  buildAdminMessage,
  buildAiMessage,
  buildCustomerMessage,
  buildRequestMessageAttachment,
  buildStaffMessage,
  buildSystemMessage,
  resolveWorkflowAttachmentCategory,
};
