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
const { CompanyProfile } = require('../models/company-profile.model');

const receiptDirectory = path.resolve(__dirname, '../../uploads/receipts');
const CURRENT_RECEIPT_TEMPLATE_VERSION = 6;

fs.mkdirSync(receiptDirectory, { recursive: true });

function firstNonEmpty(...values) {
  return values.find((value) => String(value || '').trim().length > 0) || '';
}

function normalizeHexColor(value, fallback) {
  const normalized = String(value || '').trim();
  if (/^#[0-9a-fA-F]{6}$/.test(normalized)) {
    return normalized;
  }

  if (/^[0-9a-fA-F]{6}$/.test(normalized)) {
    return `#${normalized}`;
  }

  return fallback;
}

function formatDateTime(value, { dateOnly = false } = {}) {
  if (!value) {
    return '';
  }

  const date = new Date(value);
  const day = String(date.getDate()).padStart(2, '0');
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const year = String(date.getFullYear());

  if (dateOnly) {
    return `${day}/${month}/${year}`;
  }

  const hour = String(date.getHours()).padStart(2, '0');
  const minute = String(date.getMinutes()).padStart(2, '0');
  return `${day}/${month}/${year} ${hour}:${minute}`;
}

function formatAmount(amount, currency = 'EUR') {
  return new Intl.NumberFormat('en-IE', {
    style: 'currency',
    currency: currency || 'EUR',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(Number(amount || 0));
}

function paymentMethodLabel(paymentMethod) {
  return paymentMethod === PAYMENT_METHODS.CASH_ON_COMPLETION
    ? 'Cash on completion'
    : paymentMethod === PAYMENT_METHODS.STRIPE_CHECKOUT
    ? 'Online card or wallet payment'
    : 'SEPA bank transfer';
}

function serviceLabel(serviceType, companyProfile) {
  const profileMatch = Array.isArray(companyProfile?.serviceLabels)
    ? companyProfile.serviceLabels.find((entry) => entry?.key === serviceType)
    : null;
  const localizedLabel = firstNonEmpty(
    profileMatch?.label?.en,
    profileMatch?.label?.de,
  );

  if (localizedLabel) {
    return localizedLabel;
  }

  return String(serviceType || '')
    .split('_')
    .filter(Boolean)
    .map((segment) => segment.charAt(0).toUpperCase() + segment.slice(1))
    .join(' ');
}

function formatAddress(parts) {
  return parts
    .map((part) => String(part || '').trim())
    .filter(Boolean)
    .join(', ');
}

function clampText(value, maxLength = 220) {
  const normalized = String(value || '').replace(/\s+/g, ' ').trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }

  return `${normalized.slice(0, maxLength - 1).trim()}...`;
}

function receiptFilePath(relativeUrl) {
  const storedName = path.basename(String(relativeUrl || '').trim());
  if (!storedName || storedName === '.' || storedName === '/') {
    return null;
  }

  return path.join(receiptDirectory, storedName);
}

function localReceiptExists(relativeUrl) {
  const localPath = receiptFilePath(relativeUrl);
  return Boolean(localPath && fs.existsSync(localPath));
}

function removeLocalReceipt(relativeUrl) {
  const localPath = receiptFilePath(relativeUrl);
  if (!localPath || !fs.existsSync(localPath)) {
    return;
  }

  try {
    fs.unlinkSync(localPath);
  } catch (error) {
    // WHY: Receipt cleanup should never block a new receipt from being generated.
  }
}

async function loadCompanyProfile() {
  return CompanyProfile.findOne({ siteKey: 'default' }).lean();
}

function buildTheme(companyProfile) {
  return {
    brand: normalizeHexColor(companyProfile?.primaryColorHex, '#193B63'),
    accent: normalizeHexColor(companyProfile?.accentColorHex, '#B8772E'),
    text: '#14202B',
    muted: '#53616F',
    soft: '#7A8692',
    line: '#D6DEE6',
    lineStrong: '#BFCBDA',
    panel: '#F8FAFC',
    panelStrong: '#EEF3F8',
    paper: '#FFFFFF',
    success: '#1C7A47',
    successSurface: '#E8F6EE',
  };
}

function drawRoundedPanel(document, options) {
  const {
    x,
    y,
    width,
    height,
    fillColor,
    strokeColor,
    radius = 18,
  } = options;

  document.save();
  document.lineWidth(1);
  document.roundedRect(x, y, width, height, radius);
  if (fillColor) {
    document.fillColor(fillColor);
  }
  if (strokeColor) {
    document.strokeColor(strokeColor);
  }
  document.fillAndStroke(fillColor || '#FFFFFF', strokeColor || '#FFFFFF');
  document.restore();
}

function drawRule(document, { x, y, width, color }) {
  document.save();
  document.lineWidth(1);
  document.strokeColor(color);
  document.moveTo(x, y).lineTo(x + width, y).stroke();
  document.restore();
}

function drawStatusPill(document, { x, y, label, theme, width = 72 }) {
  const height = 24;

  drawRoundedPanel(document, {
    x,
    y,
    width,
    height,
    radius: 999,
    fillColor: theme.successSurface,
    strokeColor: theme.successSurface,
  });

  document
    .font('Helvetica-Bold')
    .fontSize(9)
    .fillColor(theme.success)
    .text(label, x, y + 7, {
      width,
      align: 'center',
    });
}

function drawDocumentWatermark(document, options) {
  const {
    theme,
    receiptNumber,
  } = options;
  const centerX = document.page.width / 2;
  const centerY = document.page.height / 2;

  document.save();
  document.rotate(-31, {
    origin: [centerX, centerY],
  });
  document.opacity(0.055);
  document.fillColor(theme.brand);
  document.font('Helvetica-Bold').fontSize(58).text(
    'ADAMS VERIFIED',
    centerX - 240,
    centerY - 40,
    {
      width: 480,
      align: 'center',
    },
  );
  document.opacity(0.08);
  document.fillColor(theme.accent);
  document.font('Helvetica-Bold').fontSize(16).text(
    `RECEIPT ${receiptNumber}`,
    centerX - 220,
    centerY + 22,
    {
      width: 440,
      align: 'center',
    },
  );
  document.restore();
}

function estimateKeyValueRowsHeight(document, options) {
  const {
    rows,
    width,
    rowGap = 18,
    labelSize = 8.5,
    valueSize = 11,
    labelSpacing = 3,
  } = options;

  let totalHeight = 0;
  rows.forEach((row) => {
    const label = String(row.label || '').trim();
    const value = String(row.value || '').trim();
    if (!label || !value) {
      return;
    }

    document.fontSize(labelSize);
    totalHeight += document.heightOfString(label.toUpperCase(), { width });
    totalHeight += labelSpacing;
    document.fontSize(valueSize);
    totalHeight += document.heightOfString(value, { width });
    totalHeight += rowGap;
  });

  return totalHeight > 0 ? totalHeight - rowGap : 0;
}

function drawKeyValueRows(document, options) {
  const {
    rows,
    x,
    y,
    width,
    rowGap = 18,
    labelSize = 8.5,
    valueSize = 11,
    labelSpacing = 3,
    labelColor = '#68757E',
    valueColor = '#17242B',
  } = options;

  let currentY = y;
  rows.forEach((row) => {
    const label = String(row.label || '').trim();
    const value = String(row.value || '').trim();
    if (!label || !value) {
      return;
    }

    document.fontSize(labelSize).fillColor(labelColor).text(
      label.toUpperCase(),
      x,
      currentY,
      { width },
    );
    currentY += document.heightOfString(label.toUpperCase(), { width });
    currentY += labelSpacing;

    document.fontSize(valueSize);
    const valueHeight = document.heightOfString(value, { width });
    document.fillColor(valueColor).text(value, x, currentY, { width });
    currentY += valueHeight + rowGap;
  });

  return currentY;
}

function drawLabeledCard(document, options) {
  const {
    x,
    y,
    width,
    title,
    rows,
    theme,
    height,
  } = options;
  const horizontalPadding = 16;
  const topPadding = 14;
  const innerWidth = width - horizontalPadding * 2;
  const titleHeight = document
    .font('Helvetica-Bold')
    .fontSize(8.5)
    .heightOfString(title.toUpperCase(), {
      width: innerWidth,
    });
  const contentHeight =
    height ||
    topPadding +
      titleHeight +
      10 +
      estimateKeyValueRowsHeight(document, {
        rows,
        width: innerWidth,
        rowGap: 8,
        valueSize: 10.8,
      }) +
      16;

  drawRoundedPanel(document, {
    x,
    y,
    width,
    height: contentHeight,
    radius: 12,
    fillColor: theme.paper,
    strokeColor: theme.line,
  });

  document.save();
  document.lineWidth(3);
  document.strokeColor(theme.brand);
  document.moveTo(x, y).lineTo(x + width, y).stroke();
  document.restore();

  document
    .font('Helvetica-Bold')
    .fontSize(8.5)
    .fillColor(theme.soft)
    .text(title.toUpperCase(), x + horizontalPadding, y + topPadding, {
      width: innerWidth,
    });

  drawKeyValueRows(document, {
    rows,
    x: x + horizontalPadding,
    y: y + topPadding + titleHeight + 10,
    width: innerWidth,
    rowGap: 8,
    valueSize: 10.8,
    labelColor: theme.soft,
    valueColor: theme.text,
  });

  return contentHeight;
}

function drawMetaCells(document, options) {
  const {
    cells,
    x,
    y,
    width,
    theme,
  } = options;
  const gap = 10;
  const cellWidth = (width - gap * (cells.length - 1)) / cells.length;
  let cellHeight = 0;

  cells.forEach((cell) => {
    document.fontSize(8.5);
    const labelHeight = document.heightOfString(
      String(cell.label || '').toUpperCase(),
      { width: cellWidth - 22 },
    );
    document.fontSize(10.8);
    const valueHeight = document.heightOfString(String(cell.value || ''), {
      width: cellWidth - 22,
    });
    cellHeight = Math.max(
      cellHeight,
      10 + labelHeight + 4 + valueHeight + 10,
    );
  });

  cells.forEach((cell, index) => {
    const cellX = x + index * (cellWidth + gap);

    drawRoundedPanel(document, {
      x: cellX,
      y,
      width: cellWidth,
      height: cellHeight,
      radius: 10,
      fillColor: theme.paper,
      strokeColor: theme.line,
    });

    document
      .font('Helvetica-Bold')
      .fontSize(8.2)
      .fillColor(theme.soft)
      .text(String(cell.label || '').toUpperCase(), cellX + 11, y + 10, {
        width: cellWidth - 22,
      });
    document
      .font('Helvetica')
      .fontSize(10.8)
      .fillColor(theme.text)
      .text(String(cell.value || ''), cellX + 11, y + 24, {
        width: cellWidth - 22,
      });
  });

  return cellHeight;
}

function drawLineItemTable(document, options) {
  const {
    x,
    y,
    width,
    theme,
    description,
    quantity,
    unitPrice,
    totalPrice,
    subtotal,
    totalLabel,
  } = options;
  const descriptionWidth = width * 0.58;
  const quantityWidth = width * 0.1;
  const unitPriceWidth = width * 0.15;
  const amountWidth = width - descriptionWidth - quantityWidth - unitPriceWidth;
  const headerHeight = 28;
  const totalsHeight = 56;
  const rowDescriptionWidth = descriptionWidth - 24;
  document.fontSize(11);
  const descriptionHeight = document.heightOfString(description, {
    width: rowDescriptionWidth,
  });
  const rowHeight = Math.max(46, descriptionHeight + 18);
  const height = headerHeight + rowHeight + totalsHeight;
  const quantityX = x + descriptionWidth;
  const unitPriceX = quantityX + quantityWidth;
  const amountX = unitPriceX + unitPriceWidth;
  const rowY = y + headerHeight + 12;
  const totalsY = y + headerHeight + rowHeight;

  drawRoundedPanel(document, {
    x,
    y,
    width,
    height,
    radius: 10,
    fillColor: theme.paper,
    strokeColor: theme.line,
  });

  document.save();
  document.rect(x, y, width, headerHeight).fill(theme.panelStrong);
  document.restore();

  document.save();
  document.lineWidth(1);
  document.strokeColor(theme.line);
  [quantityX, unitPriceX, amountX].forEach((lineX) => {
    document.moveTo(lineX, y).lineTo(lineX, y + headerHeight + rowHeight).stroke();
  });
  document.restore();

  document
    .font('Helvetica-Bold')
    .fontSize(8.4)
    .fillColor(theme.soft)
    .text('DESCRIPTION', x + 12, y + 10, {
      width: descriptionWidth - 24,
    });
  document
    .font('Helvetica-Bold')
    .fontSize(8.4)
    .fillColor(theme.soft)
    .text('QTY', quantityX + 12, y + 10, {
      width: quantityWidth - 24,
      align: 'center',
    });
  document
    .font('Helvetica-Bold')
    .fontSize(8.4)
    .fillColor(theme.soft)
    .text('UNIT PRICE', unitPriceX + 12, y + 10, {
      width: unitPriceWidth - 24,
      align: 'right',
    });
  document
    .font('Helvetica-Bold')
    .fontSize(8.4)
    .fillColor(theme.soft)
    .text('AMOUNT', amountX + 12, y + 10, {
      width: amountWidth - 24,
      align: 'right',
    });

  document.font('Helvetica').fontSize(10.7).fillColor(theme.text).text(
    description,
    x + 12,
    rowY,
    {
      width: descriptionWidth - 24,
    },
  );
  document.font('Helvetica').fontSize(10.7).fillColor(theme.text).text(
    String(quantity),
    quantityX + 12,
    rowY,
    {
      width: quantityWidth - 24,
      align: 'center',
    },
  );
  document.font('Helvetica').fontSize(10.7).fillColor(theme.text).text(
    unitPrice,
    unitPriceX + 12,
    rowY,
    {
      width: unitPriceWidth - 24,
      align: 'right',
    },
  );
  document.font('Helvetica-Bold').fontSize(10.7).fillColor(theme.text).text(
    totalPrice,
    amountX + 12,
    rowY,
    {
      width: amountWidth - 24,
      align: 'right',
    },
  );

  drawRule(document, {
    x,
    y: totalsY,
    width,
    color: theme.line,
  });

  document.font('Helvetica').fontSize(9.2).fillColor(theme.muted).text(
    'Subtotal',
    unitPriceX + 12,
    totalsY + 12,
    {
      width: unitPriceWidth - 24,
    },
  );
  document.font('Helvetica').fontSize(10).fillColor(theme.text).text(
    subtotal,
    amountX + 12,
    totalsY + 10,
    {
      width: amountWidth - 24,
      align: 'right',
    },
  );
  document.font('Helvetica-Bold').fontSize(9.7).fillColor(theme.text).text(
    totalLabel,
    unitPriceX + 12,
    totalsY + 31,
    {
      width: unitPriceWidth - 24,
    },
  );
  document.font('Helvetica-Bold').fontSize(14).fillColor(theme.brand).text(
    totalPrice,
    amountX + 12,
    totalsY + 26,
    {
      width: amountWidth - 24,
      align: 'right',
    },
  );

  return height;
}

function drawAmountCallout(document, options) {
  const {
    x,
    y,
    width,
    amount,
    paidAt,
    theme,
  } = options;
  const height = 74;

  drawRoundedPanel(document, {
    x,
    y,
    width,
    height,
    radius: 12,
    fillColor: theme.panel,
    strokeColor: theme.lineStrong,
  });

  drawStatusPill(document, {
    x: x + width - 84,
    y: y + 12,
    label: 'PAID',
    theme,
    width: 60,
  });

  document
    .font('Helvetica-Bold')
    .fontSize(8.4)
    .fillColor(theme.soft)
    .text('AMOUNT RECEIVED', x + 16, y + 16, { width: width - 112 });
  document
    .font('Helvetica-Bold')
    .fontSize(22)
    .fillColor(theme.text)
    .text(amount, x + 16, y + 28, { width: width - 32 });
  document
    .font('Helvetica')
    .fontSize(9.1)
    .fillColor(theme.muted)
    .text(`Recorded ${paidAt}`, x + 16, y + 53, { width: width - 32 });

  return height;
}

function buildReceiptSummary({ invoice, request, companyProfile }) {
  const issuedByDisplayName = firstNonEmpty(
    companyProfile?.companyName,
    companyProfile?.legalName,
    'Adams Service Ops',
  );
  const issuedByLegalName = firstNonEmpty(
    companyProfile?.legalName,
    companyProfile?.companyName,
  );
  const issuedByAddress = formatAddress([
    companyProfile?.contact?.addressLine1,
    [
      companyProfile?.contact?.postalCode,
      companyProfile?.contact?.city,
    ].filter(Boolean).join(' '),
    companyProfile?.contact?.country,
  ]);
  const paidByName = firstNonEmpty(request?.contactSnapshot?.fullName, 'Customer');
  const paidByAddress = formatAddress([
    request?.location?.addressLine1,
    [
      request?.location?.postalCode,
      request?.location?.city,
    ].filter(Boolean).join(' '),
  ]);
  const paymentReference = firstNonEmpty(
    invoice?.paymentReference,
    invoice?.invoiceNumber,
    '-',
  );
  const requestNote = clampText(
    firstNonEmpty(request?.message, invoice?.note),
    110,
  );
  const supportLine = [
    firstNonEmpty(companyProfile?.contact?.email, ''),
    firstNonEmpty(companyProfile?.contact?.phone, ''),
  ].filter(Boolean).join(' | ');

  return {
    issuedByDisplayName,
    issuedByLegalName,
    issuedByAddress,
    paidByName,
    paidByAddress,
    companyEmail: firstNonEmpty(companyProfile?.contact?.email, '-'),
    companyPhone: firstNonEmpty(companyProfile?.contact?.phone, '-'),
    customerEmail: firstNonEmpty(request?.contactSnapshot?.email, '-'),
    customerPhone: firstNonEmpty(request?.contactSnapshot?.phone, '-'),
    serviceName: firstNonEmpty(
      serviceLabel(request?.serviceType, companyProfile),
      'Service request',
    ),
    serviceAddress: paidByAddress,
    requestNote,
    preferredVisit: formatDateTime(request?.preferredDate, { dateOnly: true }),
    preferredTimeWindow: firstNonEmpty(request?.preferredTimeWindow, '-'),
    paymentReference,
    dueDate: formatDateTime(invoice?.dueDate, { dateOnly: true }) || '-',
    paymentStatus: 'Paid in full',
    paymentProvider: firstNonEmpty(invoice?.paymentProvider, 'Manual confirmation'),
    supportLine,
  };
}

function renderReceiptDocument(document, options) {
  const {
    invoice,
    request,
    companyProfile,
    receiptNumber,
    issuedAt,
    theme,
  } = options;
  const margin = 48;
  const pageWidth = document.page.width - margin * 2;
  const summary = buildReceiptSummary({ invoice, request, companyProfile });
  const amountPaid = formatAmount(invoice?.amount, invoice?.currency);
  const invoiceNumber = firstNonEmpty(invoice?.invoiceNumber, '-');
  const paidAt = firstNonEmpty(
    formatDateTime(invoice?.paidAt),
    formatDateTime(issuedAt),
  );
  const topBandHeight = 8;
  const headerY = 34;
  const sectionGap = 16;
  const panelGap = 16;
  const halfWidth = (pageWidth - panelGap) / 2;
  const headerTextWidth = pageWidth - 198 - panelGap;
  const companyDisplayName = summary.issuedByDisplayName;
  const requestId = firstNonEmpty(request?._id, request?.id, '-');

  document.rect(0, 0, document.page.width, topBandHeight).fill(theme.brand);

  document
    .font('Helvetica-Bold')
    .fontSize(8.6)
    .fillColor(theme.soft)
    .text('OFFICIAL PAYMENT RECEIPT', margin, headerY, {
      width: headerTextWidth,
    });
  document
    .font('Helvetica-Bold')
    .fontSize(27)
    .fillColor(theme.text)
    .text('Receipt', margin, headerY + 14, {
      width: headerTextWidth,
    });
  document
    .font('Helvetica')
    .fontSize(10.5)
    .fillColor(theme.muted)
    .text(
      `This document confirms that payment has been received and matched to quotation ${invoiceNumber}.`,
      margin,
      headerY + 49,
      {
        width: headerTextWidth,
      },
    );
  document
    .font('Helvetica-Bold')
    .fontSize(10.4)
    .fillColor(theme.text)
    .text(companyDisplayName, margin, headerY + 84, {
      width: headerTextWidth,
    });
  document
    .font('Helvetica')
    .fontSize(9.4)
    .fillColor(theme.muted)
    .text(summary.issuedByAddress, margin, headerY + 100, {
      width: headerTextWidth,
    });

  drawAmountCallout(document, {
    x: margin + headerTextWidth + panelGap,
    y: headerY,
    width: 198,
    amount: amountPaid,
    paidAt,
    theme,
  });

  let currentY = headerY + 118;

  const metaHeight = drawMetaCells(document, {
    cells: [
      { label: 'Receipt no.', value: receiptNumber },
      { label: 'Quotation no.', value: invoiceNumber },
      { label: 'Issued', value: formatDateTime(issuedAt) },
      { label: 'Paid', value: paidAt },
    ],
    x: margin,
    y: currentY,
    width: pageWidth,
    theme,
  });
  currentY += metaHeight + sectionGap;

  const issuedByRows = [
    {
      label: 'Business',
      value:
        summary.issuedByLegalName &&
        summary.issuedByLegalName !== summary.issuedByDisplayName
          ? `${summary.issuedByDisplayName}\n${summary.issuedByLegalName}`
          : summary.issuedByDisplayName,
    },
    { label: 'Address', value: summary.issuedByAddress },
    {
      label: 'Contact',
      value: [summary.companyEmail, summary.companyPhone].filter(Boolean).join('\n'),
    },
  ];
  const paidByRows = [
    { label: 'Customer', value: summary.paidByName },
    {
      label: 'Contact',
      value: [summary.customerEmail, summary.customerPhone].filter(Boolean).join('\n'),
    },
    { label: 'Service address', value: summary.paidByAddress },
  ];
  const issuedByHeight = drawLabeledCard(document, {
    x: margin,
    y: currentY,
    width: halfWidth,
    title: 'Issued by',
    rows: issuedByRows,
    theme,
  });
  const paidByHeight = drawLabeledCard(document, {
    x: margin + halfWidth + panelGap,
    y: currentY,
    width: halfWidth,
    title: 'Paid by',
    rows: paidByRows,
    theme,
  });
  currentY += Math.max(issuedByHeight, paidByHeight) + sectionGap;

  const serviceRows = [
    { label: 'Service', value: summary.serviceName },
    {
      label: 'Schedule',
      value: [summary.preferredVisit || '-', summary.preferredTimeWindow]
        .filter(Boolean)
        .join(' | '),
    },
    {
      label: 'Reference',
      value: requestId,
    },
  ];
  const paymentRows = [
    { label: 'Status', value: summary.paymentStatus },
    {
      label: 'Settlement',
      value: `${paymentMethodLabel(invoice?.paymentMethod)}\n${paidAt}`,
    },
    { label: 'Reference', value: summary.paymentReference },
    { label: 'Due date', value: summary.dueDate },
  ];
  const serviceHeight = drawLabeledCard(document, {
    x: margin,
    y: currentY,
    width: halfWidth,
    title: 'Service details',
    rows: serviceRows,
    theme,
  });
  const paymentHeight = drawLabeledCard(document, {
    x: margin + halfWidth + panelGap,
    y: currentY,
    width: halfWidth,
    title: 'Payment details',
    rows: paymentRows,
    theme,
  });
  currentY += Math.max(serviceHeight, paymentHeight) + sectionGap;

  const lineItemDescription = [
    `Approved quotation settlement for ${summary.serviceName}`,
    `Service location: ${summary.serviceAddress}`,
  ].join('\n');
  const tableHeight = drawLineItemTable(document, {
    x: margin,
    y: currentY,
    width: pageWidth,
    theme,
    description: lineItemDescription,
    quantity: 1,
    unitPrice: amountPaid,
    totalPrice: amountPaid,
    subtotal: amountPaid,
    totalLabel: 'Total received',
  });
  currentY += tableHeight + sectionGap;

  const noteText = firstNonEmpty(
    summary.requestNote,
    invoice?.paymentInstructions,
    'Payment received and reconciled against the approved quotation. Keep this receipt for your records.',
  );
  const footerNote = noteText
    ? `Note: ${noteText}`
    : 'Payment received and reconciled against the approved quotation.';
  const footerY = Math.min(currentY, document.page.height - 72);

  drawRule(document, {
    x: margin,
    y: footerY,
    width: pageWidth,
    color: theme.lineStrong,
  });
  document
    .font('Helvetica')
    .fontSize(9.2)
    .fillColor(theme.muted)
    .text(
      'This receipt is generated from the Adams service request system as confirmation of payment received.',
      margin,
      footerY + 10,
      {
        width: pageWidth,
      },
    );
  document
    .font('Helvetica')
    .fontSize(9.2)
    .fillColor(theme.muted)
    .text(
      footerNote,
      margin,
      footerY + 24,
      {
        width: pageWidth,
      },
    );
  document
    .font('Helvetica')
    .fontSize(9.2)
    .fillColor(theme.muted)
    .text(
      `${companyDisplayName} | ${summary.companyEmail} | ${summary.companyPhone}`,
      margin,
      footerY + 38,
      {
        width: pageWidth,
      },
    );

  drawDocumentWatermark(document, {
    theme,
    receiptNumber,
  });
}

async function issuePaymentReceipt({ invoice, request }) {
  const companyProfile = await loadCompanyProfile();
  const receiptNumber =
    invoice.receiptNumber ||
    `REC-${new Date().getFullYear()}-${String(randomUUID()).slice(0, 8).toUpperCase()}`;
  const fileName = `${receiptNumber.toLowerCase()}-${Date.now()}.pdf`;
  const outputPath = path.join(receiptDirectory, fileName);
  const relativeUrl = `/uploads/receipts/${fileName}`;
  const issuedAt = new Date();
  const theme = buildTheme(companyProfile);
  const previousRelativeUrl = String(invoice?.receiptRelativeUrl || '').trim();

  await new Promise((resolve, reject) => {
    const document = new PDFDocument({
      margin: 0,
      size: 'A4',
      info: {
        Title: `Receipt ${receiptNumber}`,
        Author: firstNonEmpty(
          companyProfile?.legalName,
          companyProfile?.companyName,
          'Adams Service Ops',
        ),
        Subject: `Payment receipt for ${invoice?.invoiceNumber || 'quotation'}`,
      },
    });
    const stream = fs.createWriteStream(outputPath);
    document.pipe(stream);

    renderReceiptDocument(document, {
      invoice,
      request,
      companyProfile,
      receiptNumber,
      issuedAt,
      theme,
    });

    document.end();
    stream.on('finish', resolve);
    stream.on('error', reject);
  });

  if (previousRelativeUrl && previousRelativeUrl !== relativeUrl) {
    removeLocalReceipt(previousRelativeUrl);
  }

  return {
    receiptNumber,
    receiptRelativeUrl: relativeUrl,
    receiptIssuedAt: issuedAt,
    receiptTemplateVersion: CURRENT_RECEIPT_TEMPLATE_VERSION,
  };
}

module.exports = {
  CURRENT_RECEIPT_TEMPLATE_VERSION,
  issuePaymentReceipt,
  localReceiptExists,
};
