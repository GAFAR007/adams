/**
 * WHAT: Wraps hosted online-payment provider calls for request invoices.
 * WHY: Staff and customer flows need one place to create checkout links and confirm paid sessions.
 * HOW: Use env-backed Stripe Checkout requests over fetch and return normalized payment-session data.
 */

const { env } = require('../config/env');
const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  PAYMENT_METHODS,
} = require('../constants/app.constants');
const { AppError } = require('./app-error');

function toMinorUnits(amount) {
  return Math.round(Number(amount || 0) * 100);
}

async function stripeRequest(path, body = null, { method = 'POST' } = {}) {
  if (!env.stripeSecretKey) {
    throw new AppError({
      message: 'Stripe is not configured yet',
      statusCode: 503,
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      errorCode: 'STRIPE_NOT_CONFIGURED',
      resolutionHint: 'Add STRIPE_SECRET_KEY to the backend environment and try again',
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
    });
  }

  const response = await fetch(`https://api.stripe.com/v1${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${env.stripeSecretKey}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body,
  });
  const payload = await response.json();

  if (!response.ok) {
    throw new AppError({
      message:
        payload?.error?.message ||
        'Stripe payment session could not be created',
      statusCode: 502,
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      errorCode: 'STRIPE_REQUEST_FAILED',
      resolutionHint:
        'Check the Stripe configuration and retry the quotation send',
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
    });
  }

  return payload;
}

async function createHostedPaymentSession({ invoice, request }) {
  if (invoice.paymentMethod !== PAYMENT_METHODS.STRIPE_CHECKOUT) {
    return null;
  }

  const params = new URLSearchParams();
  params.set('mode', 'payment');
  params.set('success_url', env.stripeSuccessUrl);
  params.set('cancel_url', env.stripeCancelUrl);
  params.set('customer_email', request.contactSnapshot?.email || '');
  params.set(
    'line_items[0][price_data][currency]',
    (invoice.currency || 'EUR').toLowerCase(),
  );
  params.set(
    'line_items[0][price_data][unit_amount]',
    String(toMinorUnits(invoice.amount)),
  );
  params.set(
    'line_items[0][price_data][product_data][name]',
    `Quotation ${invoice.invoiceNumber}`,
  );
  params.set(
    'line_items[0][price_data][product_data][description]',
    `${request.serviceType || 'service_request'} · ${request.location?.city || 'service request'}`,
  );
  params.set('line_items[0][quantity]', '1');
  params.set('metadata[requestId]', String(request._id || request.id || ''));
  params.set('metadata[invoiceNumber]', invoice.invoiceNumber);
  params.set(
    'payment_intent_data[description]',
    `Quotation ${invoice.invoiceNumber}`,
  );
  params.set(
    'payment_intent_data[metadata][requestId]',
    String(request._id || request.id || ''),
  );
  params.set(
    'payment_intent_data[metadata][invoiceNumber]',
    invoice.invoiceNumber,
  );

  const session = await stripeRequest('/checkout/sessions', params);
  return {
    paymentProvider: 'stripe',
    paymentLinkUrl: session.url || null,
    providerPaymentId: session.id || null,
  };
}

async function syncHostedPaymentSession(invoice) {
  if (
    !invoice ||
    invoice.paymentMethod !== PAYMENT_METHODS.STRIPE_CHECKOUT ||
    !invoice.providerPaymentId
  ) {
    return null;
  }

  const session = await stripeRequest(
    `/checkout/sessions/${encodeURIComponent(invoice.providerPaymentId)}?expand[]=payment_intent.latest_charge`,
    null,
    { method: 'GET' },
  );

  const paymentIntent =
    session.payment_intent && typeof session.payment_intent === 'object'
      ? session.payment_intent
      : null;
  const latestCharge =
    paymentIntent?.latest_charge && typeof paymentIntent.latest_charge === 'object'
      ? paymentIntent.latest_charge
      : null;

  return {
    isPaid: session.payment_status === 'paid',
    paymentReference: paymentIntent?.id || session.id || null,
    paidAt: latestCharge?.created
      ? new Date(Number(latestCharge.created) * 1000)
      : session.created
      ? new Date(Number(session.created) * 1000)
      : new Date(),
    providerReceiptUrl: latestCharge?.receipt_url || null,
  };
}

module.exports = {
  createHostedPaymentSession,
  syncHostedPaymentSession,
};
