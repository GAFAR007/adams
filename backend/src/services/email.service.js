/**
 * WHAT: Sends transactional emails through the configured provider.
 * WHY: Registration verification codes must leave the backend through one provider-aware path.
 * HOW: Validate config, call Brevo's transactional email API, and surface safe app errors.
 */

const { env } = require('../config/env');
const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
} = require('../constants/app.constants');
const { AppError } = require('../utils/app-error');
const { logError, logInfo } = require('../utils/logger');

function getEmailProviderStatus() {
  const resolvedProvider =
    env.emailProvider ||
    (env.brevoApiKey && env.emailFrom ? 'brevo' : '');

  if (resolvedProvider === 'brevo') {
    return {
      provider: 'brevo',
      configured: Boolean(env.brevoApiKey && env.emailFrom),
      sender: env.emailFrom || null,
    };
  }

  return {
    provider: 'disabled',
    configured: false,
    sender: null,
  };
}

function logEmailProviderStatus() {
  const status = getEmailProviderStatus();

  logInfo({
    requestId: 'email',
    route: 'EMAIL',
    step: LOG_STEPS.SERVICE_OK,
    layer: 'service',
    operation: 'EmailProviderStatus',
    intent: 'Report the active transactional email provider at backend startup',
    provider: status.provider,
    configured: status.configured,
    sender: status.sender || '-',
  });
}

function parseBrevoProviderError(providerResponse) {
  try {
    return JSON.parse(providerResponse);
  } catch (error) {
    return null;
  }
}

function buildBrevoAppError(providerResponse) {
  const parsedError = parseBrevoProviderError(providerResponse);
  const providerMessage = String(parsedError?.message || providerResponse || '');
  const providerCode = String(parsedError?.code || '').toLowerCase();
  const ipMatch = providerMessage.match(/\b\d{1,3}(?:\.\d{1,3}){3}\b/);
  const blockedIp = ipMatch?.[0] || '';

  if (
    providerCode === 'unauthorized' &&
    providerMessage.toLowerCase().includes('unrecognised ip address')
  ) {
    return new AppError({
      message: blockedIp.isNotEmpty
          ? `Brevo blocked this server IP (${blockedIp}) from sending email`
          : 'Brevo blocked this server IP from sending email',
      statusCode: 503,
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      errorCode: 'BREVO_IP_NOT_AUTHORIZED',
      resolutionHint: blockedIp.isNotEmpty
          ? `Authorize ${blockedIp} in Brevo Security -> Authorised IPs, then try again`
          : 'Authorize the current server IP in Brevo Security -> Authorised IPs, then try again',
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
    });
  }

  return new AppError({
    message: 'We could not send the verification email',
    statusCode: 503,
    classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
    errorCode: 'BREVO_SEND_EMAIL_FAILED',
    resolutionHint:
      'Try again in a moment or contact support if the issue continues',
    step: LOG_STEPS.PROVIDER_CALL_FAIL,
  });
}

async function sendBrevoEmail(payload, logContext) {
  if (!env.brevoApiKey || !env.emailFrom) {
    throw new AppError({
      message: 'Email delivery is not configured yet',
      statusCode: 503,
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      errorCode: 'EMAIL_PROVIDER_NOT_CONFIGURED',
      resolutionHint:
        'Add the Brevo API key and sender details to the backend environment',
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.PROVIDER_CALL_START,
    layer: 'service',
    operation: 'SendBrevoEmail',
    intent: 'Send a transactional email through Brevo',
  });

  const response = await fetch('https://api.brevo.com/v3/smtp/email', {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      'api-key': env.brevoApiKey,
    },
    body: JSON.stringify({
      sender: {
        email: env.emailFrom,
        name: env.emailFromName || env.emailFrom,
      },
      to: [
        {
          email: payload.to.email,
          name: payload.to.name || payload.to.email,
        },
      ],
      subject: payload.subject,
      htmlContent: payload.htmlContent,
      textContent: payload.textContent,
      tags: payload.tags || [],
    }),
  });

  if (!response.ok) {
    const providerResponse = await response.text();
    const appError = buildBrevoAppError(providerResponse);

    logError({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
      layer: 'service',
      operation: 'SendBrevoEmail',
      intent:
        'Capture the failed Brevo transactional email response for debugging',
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      error_code: appError.errorCode,
      resolution_hint: appError.resolutionHint,
      message: providerResponse,
    });

    throw appError;
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.PROVIDER_CALL_OK,
    layer: 'service',
    operation: 'SendBrevoEmail',
    intent: 'Confirm the verification email was accepted by Brevo',
  });
}

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

async function sendCustomerRegistrationCodeEmail(
  { email, firstName, code, expiresInMinutes },
  logContext,
) {
  const resolvedProvider =
    env.emailProvider ||
    (env.brevoApiKey && env.emailFrom ? 'brevo' : '');

  if (resolvedProvider !== 'brevo') {
    throw new AppError({
      message: 'Email delivery is not available for registration right now',
      statusCode: 503,
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      errorCode: 'EMAIL_PROVIDER_UNSUPPORTED',
      resolutionHint: 'Set EMAIL_PROVIDER=brevo and try again',
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
    });
  }

  const safeName = escapeHtml(firstName || 'there');
  const safeCode = escapeHtml(code);

  await sendBrevoEmail(
    {
      to: {
        email,
        name: firstName || email,
      },
      subject: 'Your registration code',
      textContent:
        `Hello ${firstName || 'there'},\n\n` +
        `Use this 6-digit code to continue creating your customer account: ${code}\n\n` +
        `This code expires in ${expiresInMinutes} minutes.\n\n` +
        'If you already have an account, log in instead.\n\n' +
        'GafarExpress',
      htmlContent:
        '<html><body style="font-family:Arial,sans-serif;background:#f5f8fd;color:#172033;">' +
        '<div style="max-width:560px;margin:0 auto;padding:32px 24px;">' +
        '<div style="background:#ffffff;border-radius:20px;padding:28px;border:1px solid #d8e2f1;">' +
        `<p style="margin:0 0 16px;">Hello ${safeName},</p>` +
        '<p style="margin:0 0 16px;">Use the verification code below to continue creating your customer account.</p>' +
        `<div style="margin:24px 0;padding:18px 20px;background:#244e8f;border-radius:16px;color:#ffffff;font-size:32px;font-weight:700;letter-spacing:8px;text-align:center;">${safeCode}</div>` +
        `<p style="margin:0 0 12px;">This code expires in ${expiresInMinutes} minutes.</p>` +
        '<p style="margin:0;color:#5b6576;">If you already have an account, log in instead.</p>' +
        '</div></div></body></html>',
      tags: ['customer-registration', 'verification-code'],
    },
    logContext,
  );
}

module.exports = {
  getEmailProviderStatus,
  logEmailProviderStatus,
  sendCustomerRegistrationCodeEmail,
};
