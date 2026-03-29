/**
 * WHAT: Applies payment-provider confirmations and receipt issuance to request invoices.
 * WHY: Staff, admin, and customer surfaces all need the same approved-payment side effects.
 * HOW: Sync hosted payments, generate receipts once, and append one system note when payment becomes approved.
 */

const {
  PAYMENT_REQUEST_STATUSES,
  REQUEST_STATUSES,
} = require('../constants/app.constants');
const { syncHostedPaymentSession } = require('./payment-provider');
const { issuePaymentReceipt } = require('./payment-receipt');
const {
  buildReceiptIssuedMessage,
  invoiceNeedsOnlinePayment,
} = require('./request-payment');
const { buildSystemMessage } = require('./request-chat');

async function issueReceiptIfMissing(request) {
  const invoice = request?.invoice;
  if (!invoice) {
    return false;
  }

  if (
    invoice.receiptNumber &&
    invoice.receiptRelativeUrl &&
    invoice.receiptIssuedAt
  ) {
    return false;
  }

  const issuedReceipt = await issuePaymentReceipt({
    invoice,
    request,
  });
  invoice.receiptNumber = issuedReceipt.receiptNumber;
  invoice.receiptRelativeUrl = issuedReceipt.receiptRelativeUrl;
  invoice.receiptIssuedAt = issuedReceipt.receiptIssuedAt;
  return true;
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

  if (request.status !== REQUEST_STATUSES.CLOSED) {
    if (request.status !== REQUEST_STATUSES.PENDING_START) {
      request.status = REQUEST_STATUSES.PENDING_START;
      changed = true;
    }
  }

  if (await issueReceiptIfMissing(request)) {
    changed = true;
  }

  if (changed && appendMessage) {
    request.messages.push(buildSystemMessage(buildReceiptIssuedMessage(invoice)));
  }

  return changed;
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
  syncOnlineInvoicePaymentIfNeeded,
};
