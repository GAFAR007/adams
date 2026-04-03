/**
 * WHAT: Builds and updates invoice/payment-proof payloads that live on service requests.
 * WHY: Staff, admin, and customer flows all touch the same billing state and should not duplicate that shape logic.
 * HOW: Expose small helpers for invoice creation, proof attachment, review decisions, and human-readable copy.
 */

const {
  PAYMENT_METHODS,
  PAYMENT_REQUEST_STATUSES,
  PRICING_RULES,
  REQUEST_REVIEW_KINDS,
} = require('../constants/app.constants');

function buildInvoiceNumber(requestId) {
  const now = new Date();
  const year = now.getFullYear().toString();
  const month = (now.getMonth() + 1).toString().padStart(2, '0');
  const day = now.getDate().toString().padStart(2, '0');
  const suffix = String(requestId || '').slice(-6).toUpperCase() || 'REQUEST';
  const serial = Math.floor(100 + Math.random() * 900);
  return `QTE-${year}${month}${day}-${suffix}-${serial}`;
}

function formatEuroAmount(amount) {
  return Number(amount || 0).toFixed(2);
}

function roundCurrency(value) {
  return Math.round(Number(value || 0) * 100) / 100;
}

function normalizeAdminServiceChargePercent(
  value,
  { kind = REQUEST_REVIEW_KINDS.QUOTATION } = {},
) {
  const parsedValue = Number(value);
  const maximumPercent =
    kind === REQUEST_REVIEW_KINDS.SITE_REVIEW
      ? PRICING_RULES.SITE_REVIEW_ADMIN_SERVICE_CHARGE_MAX_PERCENT
      : PRICING_RULES.ADMIN_SERVICE_CHARGE_MAX_PERCENT;
  if (!Number.isFinite(parsedValue)) {
    return PRICING_RULES.ADMIN_SERVICE_CHARGE_DEFAULT_PERCENT;
  }

  return Math.min(
    maximumPercent,
    Math.max(
      PRICING_RULES.ADMIN_SERVICE_CHARGE_MIN_PERCENT,
      parsedValue,
    ),
  );
}

function formatDate(value) {
  if (!value) {
    return '';
  }

  const date = new Date(value);
  const day = date.getDate().toString().padStart(2, '0');
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const year = date.getFullYear().toString();
  return `${day}/${month}/${year}`;
}

function normalizePlannedDailySchedule(plannedDailySchedule) {
  if (!Array.isArray(plannedDailySchedule)) {
    return [];
  }

  return plannedDailySchedule
    .map((entry) => {
      const parsedHours = Number(entry?.hours);

      return {
        date: entry?.date || null,
        startTime:
          typeof entry?.startTime === 'string' ? entry.startTime.trim() : '',
        endTime: typeof entry?.endTime === 'string' ? entry.endTime.trim() : '',
        hours:
          Number.isFinite(parsedHours) &&
          parsedHours > 0 &&
          parsedHours <= 10
            ? parsedHours
            : null,
      };
    })
    .filter((entry) => entry.date);
}

function paymentMethodLabel(paymentMethod) {
  return paymentMethod === PAYMENT_METHODS.CASH_ON_COMPLETION
    ? 'Cash on completion'
    : paymentMethod === PAYMENT_METHODS.STRIPE_CHECKOUT
    ? 'Online card / wallet payment'
    : 'SEPA bank transfer';
}

function invoiceNeedsCustomerProof(invoice) {
  if (!invoice) {
    return false;
  }

  return invoice.paymentMethod === PAYMENT_METHODS.SEPA_BANK_TRANSFER;
}

function invoiceNeedsOnlinePayment(invoice) {
  if (!invoice) {
    return false;
  }

  return invoice.paymentMethod === PAYMENT_METHODS.STRIPE_CHECKOUT;
}

function buildProofUploadDeadline(sentAt = new Date()) {
  return new Date(
    sentAt.getTime() + PRICING_RULES.PAYMENT_PROOF_WINDOW_HOURS * 60 * 60 * 1000,
  );
}

function isInvoiceProofUploadLocked(invoice, now = new Date()) {
  if (!invoiceNeedsCustomerProof(invoice)) {
    return false;
  }

  if (invoice?.proof || invoice?.paidAt) {
    return false;
  }

  if (invoice?.proofUploadUnlockedAt) {
    return false;
  }

  if (invoice?.proofUploadLockedAt) {
    return true;
  }

  const deadline = invoice?.proofUploadDeadlineAt
    ? new Date(invoice.proofUploadDeadlineAt)
    : null;
  if (!deadline || Number.isNaN(deadline.getTime())) {
    return false;
  }

  return now > deadline;
}

function unlockInvoiceProofUpload(
  invoice,
  { actorUserId, actorRole, at = new Date() } = {},
) {
  if (!invoice) {
    return;
  }

  invoice.proofUploadUnlockedAt = at;
  invoice.proofUploadUnlockedByRole = actorRole || null;
  invoice.proofUploadUnlockedById = actorUserId || null;
  invoice.proofUploadLockedAt = null;
}

function createInvoiceRecord({
  requestId,
  kind = REQUEST_REVIEW_KINDS.QUOTATION,
  amount,
  quotedBaseAmount,
  adminServiceChargePercent,
  dueDate,
  siteReviewDate,
  siteReviewStartTime,
  siteReviewEndTime,
  siteReviewNotes,
  plannedStartDate,
  plannedStartTime,
  plannedEndTime,
  plannedHoursPerDay,
  plannedExpectedEndDate,
  plannedDailySchedule,
  paymentMethod,
  paymentInstructions,
  note,
  actorUserId,
  actorRole,
}) {
  const sentAt = new Date();
  const proofUploadDeadlineAt = buildProofUploadDeadline(sentAt);
  const normalizedQuotedBaseAmount = roundCurrency(
    quotedBaseAmount ?? amount ?? 0,
  );
  const normalizedAdminServiceChargePercent =
    normalizeAdminServiceChargePercent(adminServiceChargePercent, { kind });
  const appServiceChargePercent =
    PRICING_RULES.APP_SERVICE_CHARGE_PERCENT;
  const appServiceChargeAmount = roundCurrency(
    normalizedQuotedBaseAmount * (appServiceChargePercent / 100),
  );
  const adminServiceChargeAmount = roundCurrency(
    normalizedQuotedBaseAmount *
      (normalizedAdminServiceChargePercent / 100),
  );
  const totalAmount = roundCurrency(
    normalizedQuotedBaseAmount +
      appServiceChargeAmount +
      adminServiceChargeAmount,
  );

  return {
    kind,
    invoiceNumber: buildInvoiceNumber(requestId),
    amount: totalAmount,
    quotedBaseAmount: normalizedQuotedBaseAmount,
    appServiceChargePercent,
    appServiceChargeAmount,
    adminServiceChargePercent: normalizedAdminServiceChargePercent,
    adminServiceChargeAmount,
    currency: 'EUR',
    dueDate: dueDate || proofUploadDeadlineAt,
    proofUploadDeadlineAt,
    proofUploadUnlockedAt: null,
    proofUploadUnlockedByRole: null,
    proofUploadUnlockedById: null,
    siteReviewDate: siteReviewDate || null,
    siteReviewStartTime: (siteReviewStartTime || '').trim(),
    siteReviewEndTime: (siteReviewEndTime || '').trim(),
    siteReviewNotes: (siteReviewNotes || '').trim(),
    plannedStartDate: plannedStartDate || null,
    plannedStartTime: (plannedStartTime || '').trim(),
    plannedEndTime: (plannedEndTime || '').trim(),
    plannedHoursPerDay:
      typeof plannedHoursPerDay === 'number' ? plannedHoursPerDay : null,
    plannedExpectedEndDate: plannedExpectedEndDate || null,
    plannedDailySchedule: normalizePlannedDailySchedule(plannedDailySchedule),
    paymentMethod,
    paymentInstructions: (paymentInstructions || '').trim(),
    note: (note || '').trim(),
    status: PAYMENT_REQUEST_STATUSES.SENT,
    sentAt,
    sentByRole: actorRole,
    sentById: actorUserId,
    reviewedAt: null,
    reviewedByRole: null,
    reviewedById: null,
    reviewNote: '',
    paymentProvider: null,
    paymentLinkUrl: null,
    providerPaymentId: null,
    paymentReference: null,
    paidAt: null,
    providerReceiptUrl: null,
    receiptNumber: null,
    receiptRelativeUrl: null,
    receiptIssuedAt: null,
    proof: null,
  };
}

function createQuoteReviewRecord({
  kind = REQUEST_REVIEW_KINDS.QUOTATION,
  quotedBaseAmount,
  selectedEstimationId,
  adminServiceChargePercent,
  dueDate,
  siteReviewDate,
  siteReviewStartTime,
  siteReviewEndTime,
  siteReviewNotes,
  plannedStartDate,
  plannedStartTime,
  plannedEndTime,
  plannedHoursPerDay,
  plannedExpectedEndDate,
  plannedDailySchedule,
  paymentMethod,
  paymentInstructions,
  note,
  actorUserId,
  actorRole,
  actorName,
}) {
  const normalizedQuotedBaseAmount = roundCurrency(quotedBaseAmount ?? 0);
  const normalizedAdminServiceChargePercent =
    normalizeAdminServiceChargePercent(adminServiceChargePercent, { kind });
  const appServiceChargePercent =
    PRICING_RULES.APP_SERVICE_CHARGE_PERCENT;
  const appServiceChargeAmount = roundCurrency(
    normalizedQuotedBaseAmount * (appServiceChargePercent / 100),
  );
  const adminServiceChargeAmount = roundCurrency(
    normalizedQuotedBaseAmount *
      (normalizedAdminServiceChargePercent / 100),
  );
  const totalAmount = roundCurrency(
    normalizedQuotedBaseAmount +
      appServiceChargeAmount +
      adminServiceChargeAmount,
  );

  return {
    kind,
    quotedBaseAmount: normalizedQuotedBaseAmount,
    appServiceChargePercent,
    appServiceChargeAmount,
    adminServiceChargePercent: normalizedAdminServiceChargePercent,
    adminServiceChargeAmount,
    totalAmount,
    currency: 'EUR',
    selectedEstimationId: selectedEstimationId || null,
    dueDate: dueDate || null,
    siteReviewDate: siteReviewDate || null,
    siteReviewStartTime: (siteReviewStartTime || '').trim(),
    siteReviewEndTime: (siteReviewEndTime || '').trim(),
    siteReviewNotes: (siteReviewNotes || '').trim(),
    plannedStartDate: plannedStartDate || null,
    plannedStartTime: (plannedStartTime || '').trim(),
    plannedEndTime: (plannedEndTime || '').trim(),
    plannedHoursPerDay:
      typeof plannedHoursPerDay === 'number' ? plannedHoursPerDay : null,
    plannedExpectedEndDate: plannedExpectedEndDate || null,
    plannedDailySchedule: normalizePlannedDailySchedule(plannedDailySchedule),
    paymentMethod,
    paymentInstructions: (paymentInstructions || '').trim(),
    note: (note || '').trim(),
    reviewedAt: new Date(),
    reviewedByRole: actorRole,
    reviewedById: actorUserId,
    reviewedByName: (actorName || '').trim(),
  };
}

function isQuoteReviewReady(review) {
  if (!review) {
    return false;
  }

  if (review.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW) {
    return Boolean(
      review.siteReviewDate &&
        String(review.siteReviewStartTime || '').trim() &&
        String(review.siteReviewEndTime || '').trim() &&
        typeof review.adminServiceChargePercent === 'number' &&
        review.adminServiceChargePercent >=
          PRICING_RULES.ADMIN_SERVICE_CHARGE_MIN_PERCENT &&
        review.adminServiceChargePercent <=
          PRICING_RULES.SITE_REVIEW_ADMIN_SERVICE_CHARGE_MAX_PERCENT &&
        String(review.paymentMethod || '').trim() &&
        String(review.paymentInstructions || '').trim(),
    );
  }

  return Boolean(
    review.plannedStartDate &&
      String(review.plannedStartTime || '').trim() &&
      String(review.plannedEndTime || '').trim() &&
      typeof review.plannedHoursPerDay === 'number' &&
      review.plannedHoursPerDay > 0 &&
      review.plannedHoursPerDay <= 10 &&
      review.plannedExpectedEndDate &&
      Array.isArray(review.plannedDailySchedule) &&
      review.plannedDailySchedule.length > 0 &&
      String(review.paymentMethod || '').trim() &&
      String(review.paymentInstructions || '').trim() &&
      typeof review.adminServiceChargePercent === 'number' &&
      review.adminServiceChargePercent >=
        PRICING_RULES.ADMIN_SERVICE_CHARGE_MIN_PERCENT &&
      review.adminServiceChargePercent <=
        PRICING_RULES.ADMIN_SERVICE_CHARGE_MAX_PERCENT,
  );
}

function buildInvoiceRequestMessage(invoice) {
  if (invoice?.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW) {
    const lines = [
      `Site review booking ${invoice.invoiceNumber} is ready.`,
      `Total service charge: EUR ${formatEuroAmount(invoice.amount)}`,
      `Payment method: ${paymentMethodLabel(invoice.paymentMethod)}`,
    ];

    if (invoice.siteReviewDate) {
      lines.push(`Review date: ${formatDate(invoice.siteReviewDate)}`);
    }
    if (invoice.siteReviewStartTime && invoice.siteReviewEndTime) {
      lines.push(
        `Review time: ${invoice.siteReviewStartTime} to ${invoice.siteReviewEndTime}`,
      );
    }
    if (invoice.proofUploadDeadlineAt) {
      lines.push(
        `Upload payment proof within ${PRICING_RULES.PAYMENT_PROOF_WINDOW_HOURS} hours or the booking will cancel automatically.`,
      );
    }
    lines.push(
      '',
      'Return to your request workspace to review the booking and upload payment proof after your transfer is sent.',
    );

    return lines.join('\n');
  }

  const lines = [
    `Quotation ${invoice.invoiceNumber} is ready.`,
    `Total service charge: EUR ${formatEuroAmount(invoice.amount)}`,
    `Payment method: ${paymentMethodLabel(invoice.paymentMethod)}`,
  ];

  if (invoice.dueDate) {
    lines.push(`Due date: ${formatDate(invoice.dueDate)}`);
  }

  lines.push(
    '',
    'Open "View quotation" to review the estimated schedule, actual work updates when they start, and payment details.',
  );

  if (invoiceNeedsOnlinePayment(invoice) && invoice.paymentLinkUrl) {
    lines.push(
      'Use the Pay online action from the quotation screen when you are ready.',
    );
  }

  if (invoiceNeedsCustomerProof(invoice)) {
    lines.push(
      'After the transfer is sent, return to the request workspace and upload your payment proof.',
    );
  }

  return lines.join('\n');
}

function attachProofToInvoice(invoice, file, note = '') {
  invoice.status = PAYMENT_REQUEST_STATUSES.PROOF_SUBMITTED;
  invoice.proofUploadLockedAt = null;
  invoice.proof = {
    originalName: file.originalName || file.originalname || 'proof',
    storedName: file.storedName || file.filename || '',
    mimeType: file.mimeType || file.mimetype || 'application/octet-stream',
    sizeBytes: file.sizeBytes || file.size || 0,
    relativeUrl: file.relativeUrl || '',
    uploadedAt: new Date(),
    note: note.trim(),
  };
  invoice.reviewedAt = null;
  invoice.reviewedByRole = null;
  invoice.reviewedById = null;
  invoice.reviewNote = '';
}

function buildProofUploadedMessage(invoice) {
  if (invoice?.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW) {
    return `Payment proof uploaded for site review booking ${invoice.invoiceNumber}. Staff can review it now.`;
  }

  return `Payment proof uploaded for quotation ${invoice.invoiceNumber}. Staff can review it now.`;
}

function applyInvoiceReview(invoice, { decision, actorUserId, actorRole, reviewNote }) {
  invoice.status = decision === 'approved'
    ? PAYMENT_REQUEST_STATUSES.APPROVED
    : PAYMENT_REQUEST_STATUSES.REJECTED;
  invoice.reviewedAt = new Date();
  invoice.reviewedByRole = actorRole;
  invoice.reviewedById = actorUserId;
  invoice.reviewNote = (reviewNote || '').trim();
}

function buildReceiptIssuedMessage(invoice) {
  if (!invoice?.receiptNumber) {
    return `Payment accepted for quotation ${invoice.invoiceNumber}.`;
  }

  return `Payment accepted for quotation ${invoice.invoiceNumber}. Receipt ${invoice.receiptNumber} is ready.`;
}

function buildProofReviewMessage(invoice, decision) {
  if (decision === 'approved') {
    if (invoice?.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW) {
      return `Payment proof approved for site review booking ${invoice.invoiceNumber}. The booking can now go ahead.`;
    }
    return `Payment proof approved for quotation ${invoice.invoiceNumber}. The request is now pending start.`;
  }

  const reason = invoice.reviewNote
    ? ` Reason: ${invoice.reviewNote}`
    : '';
  if (invoice?.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW) {
    return `Payment proof was rejected for site review booking ${invoice.invoiceNumber}. Please upload a new proof.${reason}`;
  }
  return `Payment proof was rejected for quotation ${invoice.invoiceNumber}. Please upload a new proof.${reason}`;
}

module.exports = {
  applyInvoiceReview,
  attachProofToInvoice,
  buildProofUploadDeadline,
  buildInvoiceRequestMessage,
  buildReceiptIssuedMessage,
  buildProofReviewMessage,
  buildProofUploadedMessage,
  createInvoiceRecord,
  createQuoteReviewRecord,
  invoiceNeedsCustomerProof,
  invoiceNeedsOnlinePayment,
  isInvoiceProofUploadLocked,
  isQuoteReviewReady,
  unlockInvoiceProofUpload,
  paymentMethodLabel,
};
