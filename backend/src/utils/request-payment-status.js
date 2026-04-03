/**
 * WHAT: Applies payment-provider confirmations and receipt issuance to request invoices.
 * WHY: Staff, admin, and customer surfaces all need the same approved-payment side effects.
 * HOW: Sync hosted payments, generate receipts once, and append one system note when payment becomes approved.
 */

const {
  PAYMENT_REQUEST_STATUSES,
  REQUEST_REVIEW_KINDS,
  REQUEST_STATUSES,
} = require('../constants/app.constants');
const { syncHostedPaymentSession } = require('./payment-provider');
const {
  CURRENT_RECEIPT_TEMPLATE_VERSION,
  issuePaymentReceipt,
  localReceiptExists,
} = require('./payment-receipt');
const {
  buildReceiptIssuedMessage,
  invoiceNeedsOnlinePayment,
} = require('./request-payment');
const { buildSystemMessage } = require('./request-chat');

async function issueReceiptIfMissing(request) {
  const invoice = request?.invoice;
  if (!invoice) {
    return {
      changed: false,
      newlyIssued: false,
    };
  }

  const hasStoredReceipt =
    invoice.receiptNumber &&
    invoice.receiptRelativeUrl &&
    invoice.receiptIssuedAt;
  const hasCurrentTemplate =
    Number(invoice.receiptTemplateVersion || 0) >=
    CURRENT_RECEIPT_TEMPLATE_VERSION;
  const localFileAvailable =
    !invoice.receiptRelativeUrl || localReceiptExists(invoice.receiptRelativeUrl);

  if (hasStoredReceipt && hasCurrentTemplate && localFileAvailable) {
    return {
      changed: false,
      newlyIssued: false,
    };
  }

  const issuedReceipt = await issuePaymentReceipt({
    invoice,
    request,
  });
  invoice.receiptNumber = issuedReceipt.receiptNumber;
  invoice.receiptRelativeUrl = issuedReceipt.receiptRelativeUrl;
  invoice.receiptIssuedAt = issuedReceipt.receiptIssuedAt;
  invoice.receiptTemplateVersion = issuedReceipt.receiptTemplateVersion;
  return {
    changed: true,
    newlyIssued: !hasStoredReceipt,
  };
}

async function finalizeApprovedInvoice(request, { appendMessage = true } = {}) {
  const invoice = request?.invoice;
  if (!invoice) {
    return false;
  }

  let changed = false;
  if (invoice.status !== PAYMENT_REQUEST_STATUSES.APPROVED) {
    invoice.status = PAYMENT_REQUEST_STATUSES.APPROVED;
    changed = true;
  }

  if (
    invoice.kind === REQUEST_REVIEW_KINDS.QUOTATION &&
    request.status !== REQUEST_STATUSES.CLOSED
  ) {
    if (request.status !== REQUEST_STATUSES.PENDING_START) {
      request.status = REQUEST_STATUSES.PENDING_START;
      changed = true;
    }
  }

  const receiptSync = await issueReceiptIfMissing(request);
  if (receiptSync.changed) {
    changed = true;
  }

  if (changed && appendMessage && receiptSync.newlyIssued) {
    request.messages.push(buildSystemMessage(buildReceiptIssuedMessage(invoice)));
  }

  return changed;
}

async function syncApprovedInvoiceReceiptIfNeeded(request) {
  const invoice = request?.invoice;
  if (!invoice || invoice.status !== PAYMENT_REQUEST_STATUSES.APPROVED) {
    return false;
  }

  const receiptSync = await issueReceiptIfMissing(request);
  return receiptSync.changed;
}

async function syncOnlineInvoicePaymentIfNeeded(
  request,
  { appendMessage = true } = {},
) {
  const invoice = request?.invoice;
  if (!invoice || !invoiceNeedsOnlinePayment(invoice)) {
    return false;
  }

  if (!invoice.providerPaymentId) {
    return false;
  }

  if (
    invoice.status === PAYMENT_REQUEST_STATUSES.APPROVED &&
    invoice.receiptRelativeUrl
  ) {
    return false;
  }

  const paymentSession = await syncHostedPaymentSession(invoice);
  if (!paymentSession?.isPaid) {
    return false;
  }

  if (!invoice.paidAt) {
    invoice.paidAt = paymentSession.paidAt || new Date();
  }

  if (!invoice.paymentReference && paymentSession.paymentReference) {
    invoice.paymentReference = paymentSession.paymentReference;
  }

  if (!invoice.providerReceiptUrl && paymentSession.providerReceiptUrl) {
    invoice.providerReceiptUrl = paymentSession.providerReceiptUrl;
  }

  return finalizeApprovedInvoice(request, { appendMessage });
}

module.exports = {
  finalizeApprovedInvoice,
  issueReceiptIfMissing,
  syncApprovedInvoiceReceiptIfNeeded,
  syncOnlineInvoicePaymentIfNeeded,
};
