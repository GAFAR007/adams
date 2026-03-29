/**
 * WHAT: Generates lightweight PDF receipts for approved request payments.
 * WHY: Customers and staff need a stable receipt artifact even when payment started as a proof upload.
 * HOW: Render a small PDF into the uploads directory and return receipt metadata for the invoice record.
 */

const { randomUUID } = require('crypto');
const fs = require('fs');
const path = require('path');

const PDFDocument = require('pdfkit');

const { PAYMENT_METHODS } = require('../constants/app.constants');

const receiptDirectory = path.resolve(__dirname, '../../uploads/receipts');
fs.mkdirSync(receiptDirectory, { recursive: true });

function formatDateTime(value) {
  if (!value) {
    return '';
  }

  const date = new Date(value);
  const day = String(date.getDate()).padStart(2, '0');
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const year = String(date.getFullYear());
  const hour = String(date.getHours()).padStart(2, '0');
  const minute = String(date.getMinutes()).padStart(2, '0');
  return `${day}/${month}/${year} ${hour}:${minute}`;
}

function formatAmount(amount) {
  return `EUR ${Number(amount || 0).toFixed(2)}`;
}

function paymentMethodLabel(paymentMethod) {
  return paymentMethod === PAYMENT_METHODS.CASH_ON_COMPLETION
    ? 'Cash on completion'
    : paymentMethod === PAYMENT_METHODS.STRIPE_CHECKOUT
    ? 'Online payment'
    : 'SEPA bank transfer';
}

function serviceLabel(serviceType) {
  return String(serviceType || '')
    .split('_')
    .filter(Boolean)
    .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
    .join(' ');
}

async function issuePaymentReceipt({ invoice, request }) {
  const receiptNumber =
    invoice.receiptNumber ||
    `REC-${new Date().getFullYear()}-${String(randomUUID()).slice(0, 8).toUpperCase()}`;
  const fileName = `${receiptNumber.toLowerCase()}-${Date.now()}.pdf`;
  const outputPath = path.join(receiptDirectory, fileName);
  const relativeUrl = `/uploads/receipts/${fileName}`;

  await new Promise((resolve, reject) => {
    const document = new PDFDocument({ margin: 48, size: 'A4' });
    const stream = fs.createWriteStream(outputPath);
    document.pipe(stream);

    document.fontSize(22).fillColor('#11243B').text('Payment Receipt');
    document.moveDown(0.8);
    document.fontSize(11).fillColor('#4B5563').text(`Receipt number: ${receiptNumber}`);
    document.text(`Quotation number: ${invoice.invoiceNumber}`);
    document.text(`Issued: ${formatDateTime(invoice.receiptIssuedAt || new Date())}`);

    document.moveDown(1.2);
    document.fontSize(14).fillColor('#11243B').text('Customer');
    document.fontSize(11).fillColor('#111827');
    document.text(request.contactSnapshot?.fullName || 'Customer');
    document.text(request.contactSnapshot?.email || '');
    if (request.contactSnapshot?.phone) {
      document.text(request.contactSnapshot.phone);
    }

    document.moveDown(1.1);
    document.fontSize(14).fillColor('#11243B').text('Service');
    document.fontSize(11).fillColor('#111827');
    document.text(serviceLabel(request.serviceType) || 'Service request');
    document.text(
      [request.location?.addressLine1, request.location?.city, request.location?.postalCode]
        .filter(Boolean)
        .join(', '),
    );

    document.moveDown(1.1);
    document.fontSize(14).fillColor('#11243B').text('Payment');
    document.fontSize(11).fillColor('#111827');
    document.text(`Amount: ${formatAmount(invoice.amount)}`);
    document.text(`Method: ${paymentMethodLabel(invoice.paymentMethod)}`);
    if (invoice.paymentReference) {
      document.text(`Reference: ${invoice.paymentReference}`);
    }
    if (invoice.paidAt) {
      document.text(`Paid at: ${formatDateTime(invoice.paidAt)}`);
    }

    document.moveDown(1.2);
    document.fontSize(10).fillColor('#4B5563').text(
      'This receipt confirms that the quotation payment was accepted and recorded in the service request thread.',
    );

    document.end();
    stream.on('finish', resolve);
    stream.on('error', reject);
  });

  return {
    receiptNumber,
    receiptRelativeUrl: relativeUrl,
    receiptIssuedAt: new Date(),
  };
}

module.exports = {
  issuePaymentReceipt,
};
