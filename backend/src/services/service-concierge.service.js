/**
 * WHAT: Generates public booking-assistant replies for the unauthenticated service-intake chat.
 * WHY: The public site should feel like customer care while still collecting account details in a guided flow.
 * HOW: Load company context, optionally call the Groq/OpenAI-compatible model for tone, and fall back safely when AI is unavailable.
 */

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
} = require('../constants/app.constants');
const { env } = require('../config/env');
const { CompanyProfile } = require('../models/company-profile.model');
const { AppError } = require('../utils/app-error');
const { logError, logInfo } = require('../utils/logger');

const ASSISTANT_NAME = 'Naima';
const BOOKING_STEP_SEQUENCE = Object.freeze([
  'service',
  'firstName',
  'lastName',
  'email',
  'phone',
  'password',
]);

function normalizeText(value) {
  return String(value || '').trim();
}

function resolveLocalizedText(value, languageCode) {
  if (!value) {
    return '';
  }

  if (languageCode === 'de') {
    return value.de || value.en || '';
  }

  return value.en || value.de || '';
}

function normalizeLanguageCode(value) {
  return value === 'de' ? 'de' : 'en';
}

function resolveServiceName(profile, serviceKey, languageCode) {
  const normalizedKey = normalizeText(serviceKey);
  if (!normalizedKey) {
    return '';
  }

  const service = (Array.isArray(profile?.serviceLabels)
    ? profile.serviceLabels
    : []
  ).find((item) => item?.key === normalizedKey);

  return resolveLocalizedText(service?.label, languageCode);
}

function resolveNextStep(payload) {
  if (!normalizeText(payload.serviceKey) && !normalizeText(payload.serviceName)) {
    return 'service';
  }

  if (!normalizeText(payload.firstName)) {
    return 'firstName';
  }

  if (!normalizeText(payload.lastName)) {
    return 'lastName';
  }

  if (!normalizeText(payload.email)) {
    return 'email';
  }

  if (!normalizeText(payload.phone)) {
    return 'phone';
  }

  if (!payload.passwordCaptured) {
    return 'password';
  }

  return 'done';
}

function buildStepPrompt(step, languageCode) {
  const labels = {
    en: {
      service:
        'Which service would you like to book first? You can choose a service chip or type it here.',
      firstName: 'What is your first name?',
      lastName: 'And your last name?',
      email: 'What email address should we use for your booking access?',
      phone: 'What phone number should the team use if they need to reach you quickly?',
      password:
        'Please create a password with at least 8 characters for your customer access.',
      done:
        'Everything is ready. Confirm below and I will create your secure customer access so you can continue the booking.',
    },
    de: {
      service:
        'Welche Leistung möchten Sie zuerst buchen? Sie können eine Leistungs-Kachel wählen oder sie hier eingeben.',
      firstName: 'Wie lautet Ihr Vorname?',
      lastName: 'Und Ihr Nachname?',
      email:
        'Welche E-Mail-Adresse sollen wir für Ihren Buchungszugang verwenden?',
      phone:
        'Unter welcher Telefonnummer kann das Team Sie bei Rückfragen schnell erreichen?',
      password:
        'Bitte erstellen Sie ein Passwort mit mindestens 8 Zeichen für Ihren Kundenzugang.',
      done:
        'Alles ist bereit. Bestätigen Sie unten, dann erstelle ich Ihren sicheren Kundenzugang und Sie können mit der Buchung weitermachen.',
    },
  };

  return labels[languageCode][step] || labels[languageCode].firstName;
}

function buildFallbackReply({
  languageCode,
  firstName,
  serviceName,
  justCapturedStep,
  nextStep,
}) {
  const safeFirstName = normalizeText(firstName);
  const safeServiceName = normalizeText(serviceName);
  const greeting = safeFirstName
    ? languageCode === 'de'
      ? `Danke, ${safeFirstName}.`
      : `Thanks, ${safeFirstName}.`
    : languageCode === 'de'
      ? 'Perfekt.'
      : 'Perfect.';

  if (nextStep === 'done') {
    return languageCode === 'de'
      ? `Ich habe jetzt alles für ${safeServiceName || 'Ihre Anfrage'}. Unten können Sie Ihren sicheren Kundenzugang anlegen und danach direkt mit der Serviceanfrage weitermachen.`
      : `I have everything I need for ${safeServiceName || 'your request'}. Use the button below to create your secure customer access and continue straight into the service request.`;
  }

  if (justCapturedStep === 'service' && safeServiceName) {
    return languageCode === 'de'
      ? `Alles klar, ${safeServiceName} ist notiert. ${buildStepPrompt(nextStep, languageCode)}`
      : `Great, I have ${safeServiceName} noted. ${buildStepPrompt(nextStep, languageCode)}`;
  }

  return `${greeting} ${buildStepPrompt(nextStep, languageCode)}`.trim();
}

async function requestAiReply({
  companyName,
  languageCode,
  serviceName,
  firstName,
  justCapturedStep,
  nextStep,
  logContext,
}) {
  if (!env.aiApiKey) {
    return null;
  }

  const languageLabel = languageCode === 'de' ? 'German' : 'English';
  const prompt = [
    `You are ${ASSISTANT_NAME}, the calm customer-care concierge for ${companyName}.`,
    `Reply in ${languageLabel}.`,
    'Keep the tone seamless, warm, concise, and premium.',
    'Ask only one next question at a time.',
    'Do not mention AI, models, providers, JSON, or internal systems.',
    'Do not ask for information that is already collected.',
    `The visitor has just completed this step: ${justCapturedStep}.`,
    `The next missing step is: ${nextStep}.`,
    serviceName ? `Selected service: ${serviceName}.` : 'No service selected yet.',
    firstName ? `Use the first name ${firstName} naturally if it helps.` : 'Do not invent a first name.',
    nextStep === 'done'
      ? 'Invite the visitor to press the final button to create secure customer access and continue.'
      : `Ask for this next step clearly: ${nextStep}.`,
    'Return valid JSON only with this shape: {"reply":"..."}',
  ].join('\n');

  logInfo({
    ...logContext,
    step: LOG_STEPS.PROVIDER_CALL_START,
    layer: 'service',
    operation: 'PublicServiceConciergeReply',
    intent: 'Generate the public service-concierge reply through the configured AI provider',
    provider: env.aiProvider,
    model: env.aiModelDefault,
  });

  try {
    const response = await fetch(`${env.aiBaseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.aiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: env.aiModelDefault,
        temperature: 0.55,
        response_format: {
          type: 'json_object',
        },
        messages: [
          {
            role: 'system',
            content: prompt,
          },
        ],
      }),
    });

    if (!response.ok) {
      const responseBody = await response.text();
      logError({
        ...logContext,
        step: LOG_STEPS.PROVIDER_CALL_FAIL,
        layer: 'service',
        operation: 'PublicServiceConciergeReply',
        intent: 'Capture the AI provider failure before the flow falls back to a deterministic reply',
        classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
        error_code: 'PUBLIC_SERVICE_CONCIERGE_PROVIDER_REJECTED',
        resolution_hint: 'Check the configured AI provider credentials and try again',
        message: responseBody || `Provider returned HTTP ${response.status}`,
      });
      return null;
    }

    const data = await response.json();
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== 'string' || !content.trim()) {
      return null;
    }

    const parsed = JSON.parse(content);
    const reply = normalizeText(parsed?.reply);
    if (!reply) {
      return null;
    }

    logInfo({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_OK,
      layer: 'service',
      operation: 'PublicServiceConciergeReply',
      intent: 'Confirm the AI provider returned a usable concierge reply',
      provider: env.aiProvider,
      model: env.aiModelDefault,
    });

    return reply;
  } catch (error) {
    logError({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
      layer: 'service',
      operation: 'PublicServiceConciergeReply',
      intent: 'Capture unexpected AI provider errors before the flow falls back safely',
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      error_code: 'PUBLIC_SERVICE_CONCIERGE_PROVIDER_FAILED',
      resolution_hint: 'Check the configured AI provider and network reachability',
      message: error.message,
    });
    return null;
  }
}

async function generatePublicServiceConciergeReply(payload, logContext) {
  const languageCode = normalizeLanguageCode(payload.languageCode);

  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'PublicServiceConciergeReply',
    intent: 'Generate a public booking-assistant reply for the service-intake chat',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'PublicServiceConciergeReply',
    intent: 'Load the public company profile so the concierge reply uses live business context',
  });

  const profile = await CompanyProfile.findOne({ siteKey: 'default' });
  if (!profile) {
    throw new AppError({
      message: 'Company profile not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'PUBLIC_COMPANY_PROFILE_NOT_FOUND',
      resolutionHint: 'Seed the company profile before using the public booking assistant',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'PublicServiceConciergeReply',
    intent: 'Confirm the public company profile is available for concierge context',
  });

  const justCapturedStep = normalizeText(payload.justCapturedStep) || 'service';
  const firstName = normalizeText(payload.firstName);
  const serviceKey = normalizeText(payload.serviceKey);
  const serviceName =
    normalizeText(payload.serviceName) ||
    resolveServiceName(profile, serviceKey, languageCode);
  const nextStep =
    normalizeText(payload.nextStep) ||
    resolveNextStep({
      serviceKey,
      serviceName,
      firstName,
      lastName: normalizeText(payload.lastName),
      email: normalizeText(payload.email),
      phone: normalizeText(payload.phone),
      passwordCaptured: Boolean(payload.passwordCaptured),
    });

  const aiReply = await requestAiReply({
    companyName: profile.companyName,
    languageCode,
    serviceName,
    firstName,
    justCapturedStep,
    nextStep,
    logContext,
  });

  const reply =
    aiReply ||
    buildFallbackReply({
      languageCode,
      firstName,
      serviceName,
      justCapturedStep,
      nextStep,
    });

  return {
    message: 'Public service concierge reply generated successfully',
    assistant: {
      name: ASSISTANT_NAME,
      reply,
      nextStep,
      readyForRegistration: nextStep === 'done',
    },
  };
}

module.exports = {
  generatePublicServiceConciergeReply,
};
