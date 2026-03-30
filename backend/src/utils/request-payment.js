/**
 * WHAT: Builds and updates invoice/payment-proof payloads that live on service requests.
 * WHY: Staff, admin, and customer flows all touch the same billing state and should not duplicate that shape logic.
 * HOW: Expose small helpers for invoice creation, proof attachment, review decisions, and human-readable copy.
 */

const {
  PAYMENT_METHODS,
  PAYMENT_REQUEST_STATUSES,
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

function createInvoiceRecord({
  requestId,
  amount,
  dueDate,
  paymentMethod,
  paymentInstructions,
  note,
  actorUserId,
  actorRole,
}) {
  const sentAt = new Date();

  return {
    invoiceNumber: buildInvoiceNumber(requestId),
    amount: Number(amount),
    currency: 'EUR',
    dueDate: dueDate || null,
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

function buildInvoiceRequestMessage(invoice) {
  const segments = [
    `Quotation ${invoice.invoiceNumber} for EUR ${formatEuroAmount(invoice.amount)} is ready.`,
    `Payment option: ${paymentMethodLabel(invoice.paymentMethod)}.`,
  ];

  if (invoice.dueDate) {
    segments.push(`Due date: ${formatDate(invoice.dueDate)}.`);
  }

  if (invoice.note) {
    segments.push(invoice.note);
  }

  if (invoice.paymentInstructions) {
    segments.push(`Payment details: ${invoice.paymentInstructions}`);
  }

  if (invoiceNeedsOnlinePayment(invoice) && invoice.paymentLinkUrl) {
    segments.push(
      'Use the online payment button on the payment card to complete checkout securely and receive your receipt.',
    );
  }

  if (invoiceNeedsCustomerProof(invoice)) {
    segments.push(
      'Upload your payment proof from the payment card near the composer once the transfer is complete.',
    );
  }

  return segments.join(' ');
}

function attachProofToInvoice(invoice, file, note = '') {
  invoice.status = PAYMENT_REQUEST_STATUSES.PROOF_SUBMITTED;
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
    return `Payment proof approved for quotation ${invoice.invoiceNumber}. The request is now pending start.`;
  }

  const reason = invoice.reviewNote
    ? ` Reason: ${invoice.reviewNote}`
    : '';
  return `Payment proof was rejected for quotation ${invoice.invoiceNumber}. Please upload a new proof.${reason}`;
}

module.exports = {
  applyInvoiceReview,
  attachProofToInvoice,
  buildInvoiceRequestMessage,
  buildReceiptIssuedMessage,
  buildProofReviewMessage,
  buildProofUploadedMessage,
  createInvoiceRecord,
  invoiceNeedsCustomerProof,
  invoiceNeedsOnlinePayment,
  paymentMethodLabel,
};
