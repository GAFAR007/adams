const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  REQUEST_MESSAGE_SENDERS,
  USER_ROLES,
} = require("../constants/app.constants");
const { env } = require("../config/env");
const {
  logError,
  logInfo,
} = require("../utils/logger");

const REQUEST_REPLY_ASSISTANT_NAME = "Naima AI";
const REQUEST_HOSTILE_LANGUAGE_PATTERN =
  /\b(mother\s*fucker|motherfucker|mfer|fucker|fuck|fucking|wtf|shit|bullshit|asshole|bitch|idiot|stupid|useless|dumb|bastard|nigga|nigger|niga+)\b/i;
const REQUEST_UNPROFESSIONAL_TONE_PATTERN =
  /\b(sup|wassup|what'?s up|yo|bro|bruh|fam|homie)\b/i;
const REQUEST_SHORT_GREETING_PATTERN =
  /^(hi|hello|hey|yo|sup|wassup|good morning|good afternoon|good evening|hi there|hello there)[!,. ]*$/i;
const REQUEST_REPLY_DELAY_PATTERN =
  /\b(reply|respond|response|get back|hear back|busy|available|free|there|follow up|following up)\b/i;

function normalizeRequestDraft(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeRequestDraftForComparison(value) {
  return normalizeRequestDraft(value)
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function capitalizeWord(value) {
  if (!value) {
    return "";
  }

  return value.charAt(0).toUpperCase() + value.slice(1).toLowerCase();
}

function firstNameFromFullName(value) {
  return String(value || "")
    .trim()
    .split(/\s+/)
    .find(Boolean) || "";
}

function containsRequestHostileLanguage(value) {
  return REQUEST_HOSTILE_LANGUAGE_PATTERN.test(
    normalizeRequestDraft(value),
  );
}

function containsRequestUnprofessionalTone(value) {
  return REQUEST_UNPROFESSIONAL_TONE_PATTERN.test(
    normalizeRequestDraft(value),
  );
}

function isShortRequestGreeting(value) {
  return REQUEST_SHORT_GREETING_PATTERN.test(
    normalizeRequestDraft(value),
  );
}

function requestViewerOwnSenderType(viewerRole) {
  if (viewerRole === USER_ROLES.STAFF) {
    return REQUEST_MESSAGE_SENDERS.STAFF;
  }

  if (viewerRole === USER_ROLES.ADMIN) {
    return REQUEST_MESSAGE_SENDERS.ADMIN;
  }

  return REQUEST_MESSAGE_SENDERS.CUSTOMER;
}

function isWaitingForRequestReply(request, viewerRole) {
  const messages = Array.isArray(request?.messages)
    ? request.messages
    : [];
  if (!messages.length) {
    return false;
  }

  const latestMessage = messages[messages.length - 1];
  return String(latestMessage?.senderType || "") === requestViewerOwnSenderType(viewerRole);
}

function counterpartNameForRequest(request, viewerRole) {
  if (viewerRole === USER_ROLES.CUSTOMER) {
    const staffName = String(
      request?.assignedStaff?.firstName ||
        request?.assignedStaff?.fullName ||
        "",
    ).trim();
    if (staffName) {
      return firstNameFromFullName(
        request.assignedStaff.fullName ||
          `${request.assignedStaff.firstName || ""} ${request.assignedStaff.lastName || ""}`,
      );
    }

    return "Naima";
  }

  const customerName = String(
    request?.customer?.firstName ||
      request?.contactSnapshot?.fullName ||
      "",
  ).trim();
  return firstNameFromFullName(customerName);
}

function buildRequestCounterpartGreeting(request, viewerRole) {
  const firstName = counterpartNameForRequest(
    request,
    viewerRole,
  );

  if (!firstName) {
    return "Hello,";
  }

  return `Hello ${capitalizeWord(firstName)},`;
}

function cleanRequestDraftBody(draft) {
  return normalizeRequestDraft(draft)
    .replace(
      /\b(mother\s*fucker|motherfucker|mfer|fucker|fuck|fucking|wtf|shit|bullshit|asshole|bitch|idiot|stupid|useless|dumb|bastard|nigga|nigger|niga+)\b/gi,
      "",
    )
    .replace(
      /^(hi|hello|hey|yo|sup|wassup|what'?s up|hi there|hello there)\b[\s,!.:-]*/i,
      "",
    )
    .replace(/\b(bro|bruh|fam|homie)\b/gi, "")
    .replace(/\s+/g, " ")
    .trim();
}

function polishRequestDraft(draft) {
  let text = normalizeRequestDraft(draft);
  if (!text) {
    return "";
  }

  text = text
    .replace(/\bim\b/gi, "I'm")
    .replace(/\bdont\b/gi, "don't")
    .replace(/\bcant\b/gi, "can't")
    .replace(/\bwont\b/gi, "won't")
    .replace(/\bi\b/g, "I");

  text = text.replace(/([.!?])(?=[A-Za-z])/g, "$1 ");
  text = text.replace(/\s+/g, " ").trim();
  text = text.replace(/(^|[.!?]\s+)([a-z])/g, (_match, prefix, letter) => {
    return `${prefix}${letter.toUpperCase()}`;
  });

  if (!/[.!?]$/.test(text)) {
    text = `${text}.`;
  }

  return text;
}

function buildProfessionalRequestReply(request, viewerRole, draft) {
  const normalizedDraft = normalizeRequestDraft(draft);
  const greeting = buildRequestCounterpartGreeting(
    request,
    viewerRole,
  );

  if (!normalizedDraft) {
    return `${greeting} I hope you are well.`;
  }

  if (isShortRequestGreeting(normalizedDraft)) {
    return `${greeting} I hope you are well.`;
  }

  const looksLikeFollowUp =
    isWaitingForRequestReply(request, viewerRole) ||
    containsRequestHostileLanguage(normalizedDraft) ||
    REQUEST_REPLY_DELAY_PATTERN.test(normalizedDraft);

  if (looksLikeFollowUp) {
    return `${greeting} sorry to follow up. Are you currently available? I have not received a reply from you yet.`;
  }

  const cleanedBody = cleanRequestDraftBody(
    normalizedDraft,
  );
  if (!cleanedBody) {
    return `${greeting} I hope you are well.`;
  }

  const polishedBody = polishRequestDraft(cleanedBody)
    .replace(/^(hello|hi|hey)[,!.\s]+/i, "")
    .trim();
  if (!polishedBody) {
    return `${greeting} I hope you are well.`;
  }

  return `${greeting} ${polishedBody}`.replace(/\s+/g, " ").trim();
}

function shouldForceProfessionalRequestRewrite(draft, suggestion) {
  const normalizedDraft = normalizeRequestDraft(draft);
  if (!normalizedDraft) {
    return false;
  }

  const normalizedSuggestion = normalizeRequestDraft(
    suggestion,
  );
  return (
    isShortRequestGreeting(normalizedDraft) ||
    containsRequestHostileLanguage(normalizedDraft) ||
    containsRequestUnprofessionalTone(normalizedDraft) ||
    normalizeRequestDraftForComparison(
      normalizedSuggestion,
    ) === normalizeRequestDraftForComparison(normalizedDraft)
  );
}

function buildRequestTranscriptLine(message, viewerRole) {
  const senderType = String(message?.senderType || "system");
  const senderLabel =
    senderType === requestViewerOwnSenderType(viewerRole)
      ? "You"
      : String(message?.senderName || "Other participant").trim() || "Other participant";
  const createdAt = message?.createdAt
    ? new Date(message.createdAt).toISOString()
    : "unknown-time";
  const messageText =
    normalizeRequestDraft(message?.text) || "[no text]";
  const attachmentNote = message?.attachment?.originalName
    ? ` [Attachment: ${message.attachment.originalName}]`
    : "";

  return `[${createdAt}] ${senderLabel} (${senderType}): ${messageText}${attachmentNote}`;
}

async function suggestRequestThreadReply({
  request,
  viewerRole,
  senderName,
  draft,
  logContext,
}) {
  const normalizedDraft = normalizeRequestDraft(draft);
  const deterministicFallback =
    buildProfessionalRequestReply(
      request,
      viewerRole,
      normalizedDraft,
    );

  if (
    !env.aiApiKey ||
    !env.aiBaseUrl ||
    !env.aiModelReasoning
  ) {
    return deterministicFallback;
  }

  const transcript = (
    Array.isArray(request?.messages)
      ? request.messages
      : []
  )
    .slice(-20)
    .map((message) =>
      buildRequestTranscriptLine(message, viewerRole),
    )
    .join("\n");
  const counterpartGreeting =
    buildRequestCounterpartGreeting(
      request,
      viewerRole,
    );
  const prompt = [
    `You are ${REQUEST_REPLY_ASSISTANT_NAME}, a reply assistant for Adams Service Ops request threads.`,
    `Write the best possible next message for ${senderName} (${viewerRole}) to send in this live request conversation.`,
    "This is a workplace or customer-service chat. Keep the tone professional, calm, and respectful.",
    "If a draft is provided, always rewrite it into a polished professional message without changing the factual meaning.",
    "Never return the draft unchanged when a draft is provided.",
    `Use a named greeting when appropriate, for example: ${counterpartGreeting}`,
    "Even a short greeting like hi should become a fuller professional greeting.",
    "If the draft contains profanity, insults, slurs, hostility, or slang, rewrite it into workplace-safe language.",
    "If the sender appears to be following up on a missing reply, turn that into a polite follow-up asking whether the other person is currently available.",
    "Do not invent facts, promises, times, or status updates that are not in the thread.",
    "Keep names, numbers, references, and service details exact when they already exist.",
    "Return valid JSON only with this shape: {\"suggestion\":\"...\"}",
    `Request service: ${String(request?.serviceType || "service_request").replace(/_/g, " ")}`,
    `Request location: ${request?.addressSummary || request?.contactSnapshot?.city || "Unknown location"}`,
    normalizedDraft
      ? `Current draft from ${senderName}: ${normalizedDraft}`
      : "Current draft: [empty]",
    "Recent conversation:",
    transcript || "[no prior messages]",
  ].join("\n");

  logInfo({
    ...logContext,
    step: LOG_STEPS.PROVIDER_CALL_START,
    layer: "service",
    operation: "RequestReplySuggest",
    intent:
      "Generate an AI-refined request-thread reply from the live conversation context",
    provider: env.aiProvider,
    model: env.aiModelReasoning,
  });

  try {
    const response = await fetch(
      `${env.aiBaseUrl}/chat/completions`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.aiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: env.aiModelReasoning,
          temperature: 0.35,
          response_format: { type: "json_object" },
          messages: [
            {
              role: "system",
              content: prompt,
            },
          ],
        }),
      },
    );

    if (!response.ok) {
      const responseBody = await response.text();
      logError({
        ...logContext,
        step: LOG_STEPS.PROVIDER_CALL_FAIL,
        layer: "service",
        operation: "RequestReplySuggest",
        intent:
          "Capture the AI provider failure before falling back to a deterministic request-thread suggestion",
        classification:
          ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
        error_code:
          "REQUEST_REPLY_AI_PROVIDER_REJECTED",
        resolution_hint:
          "Check the configured AI provider credentials and try again",
        message:
          responseBody ||
          `Provider returned HTTP ${response.status}`,
      });
      return deterministicFallback;
    }

    const data = await response.json();
    const content =
      data?.choices?.[0]?.message?.content;
    if (
      typeof content !== "string" ||
      !content.trim()
    ) {
      return deterministicFallback;
    }

    const parsed = JSON.parse(content);
    const suggestion = String(
      parsed?.suggestion || "",
    ).trim();
    if (!suggestion) {
      return deterministicFallback;
    }

    const normalizedSuggestion =
      normalizeRequestDraft(suggestion);
    const resolvedSuggestion =
      shouldForceProfessionalRequestRewrite(
        normalizedDraft,
        normalizedSuggestion,
      )
        ? deterministicFallback
        : normalizedSuggestion;

    if (!resolvedSuggestion) {
      return deterministicFallback;
    }

    if (
      normalizeRequestDraftForComparison(
        resolvedSuggestion,
      ) ===
      normalizeRequestDraftForComparison(
        normalizedDraft,
      )
    ) {
      return deterministicFallback;
    }

    logInfo({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_OK,
      layer: "service",
      operation: "RequestReplySuggest",
      intent:
        "Confirm the AI provider returned a usable request-thread suggestion",
      provider: env.aiProvider,
      model: env.aiModelReasoning,
    });

    return resolvedSuggestion;
  } catch (error) {
    logError({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
      layer: "service",
      operation: "RequestReplySuggest",
      intent:
        "Capture unexpected AI provider errors before falling back to a deterministic request-thread suggestion",
      classification:
        ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      error_code: "REQUEST_REPLY_AI_PROVIDER_FAILED",
      resolution_hint:
        "Check the configured AI provider and network reachability",
      message: error.message,
    });
    return deterministicFallback;
  }
}

module.exports = {
  REQUEST_REPLY_ASSISTANT_NAME,
  suggestRequestThreadReply,
};
