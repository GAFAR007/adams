/**
 * WHAT: Implements internal direct and group chat for admin and staff users.
 * WHY: Internal coordination needs persistent one-to-one and multi-person chat threads instead of seeded frontend-only placeholders.
 * HOW: Resolve active participants from MongoDB, maintain one direct thread per user pair, create named group threads, and compute unread state per viewer.
 */

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  USER_ROLES,
  USER_STATUSES,
} = require("../constants/app.constants");
const { env } = require("../config/env");
const {
  InternalChatThread,
} = require("../models/internal-chat-thread.model");
const { User } = require("../models/user.model");
const {
  storeInternalChatAttachmentFile,
} = require("./file-storage.service");
const {
  AppError,
} = require("../utils/app-error");
const {
  logError,
  logInfo,
} = require("../utils/logger");
const {
  buildRequestMessageAttachment,
} = require("../utils/request-chat");
const {
  serializeInternalChatThread,
  serializeUser,
} = require("../utils/serializers");

const INTERNAL_CHAT_ALLOWED_ROLES = [
  USER_ROLES.ADMIN,
  USER_ROLES.STAFF,
];
const USER_PUBLIC_FIELDS =
  "firstName lastName email phone role staffType status staffAvailability createdAt updatedAt";
const INTERNAL_CHAT_ATTACHMENT_PLACEHOLDER =
  "Shared an attachment";
const INTERNAL_CHAT_AI_ASSISTANT_NAME =
  "Naima AI";
const INTERNAL_CHAT_HOSTILE_LANGUAGE_PATTERN =
  /\b(mother\s*fucker|motherfucker|mfer|fucker|fuck|fucking|wtf|shit|bullshit|asshole|bitch|idiot|stupid|useless|dumb|bastard|nigga|nigger|niga+)\b/i;
const INTERNAL_CHAT_UNPROFESSIONAL_TONE_PATTERN =
  /\b(sup|wassup|what'?s up|yo|bro|bruh|fam|homie)\b/i;
const INTERNAL_CHAT_SHORT_GREETING_PATTERN =
  /^(hi|hello|hey|yo|sup|wassup|good morning|good afternoon|good evening|hi there|hello there)[!,. ]*$/i;
const INTERNAL_CHAT_REPLY_DELAY_PATTERN =
  /\b(reply|respond|response|get back|hear back|busy|available|free|there)\b/i;

function buildParticipantKey(userIdA, userIdB) {
  return [String(userIdA), String(userIdB)]
    .sort()
    .join(":");
}

function buildFullName(user) {
  return `${user.firstName || ""} ${user.lastName || ""}`.trim();
}

function normalizeUniqueParticipantIds(
  participantIds = [],
  currentUserId,
) {
  return [
    ...new Set(
      (Array.isArray(participantIds)
        ? participantIds
        : []
      ).map(String),
    ),
  ].filter(
    (id) => id && id !== String(currentUserId),
  );
}

async function loadActiveChatUser(userId) {
  return User.findOne({
    _id: userId,
    role: { $in: INTERNAL_CHAT_ALLOWED_ROLES },
    status: USER_STATUSES.ACTIVE,
  });
}

async function loadActiveChatUsers(userIds) {
  return User.find({
    _id: { $in: userIds },
    role: { $in: INTERNAL_CHAT_ALLOWED_ROLES },
    status: USER_STATUSES.ACTIVE,
  }).select(USER_PUBLIC_FIELDS);
}

async function populateInternalChatThread(
  threadId,
) {
  return InternalChatThread.findById(threadId)
    .populate(
      "participants.user",
      USER_PUBLIC_FIELDS,
    )
    .populate(
      "messages.sender",
      USER_PUBLIC_FIELDS,
    );
}

async function loadAccessibleThread(
  threadId,
  currentUserId,
) {
  return InternalChatThread.findOne({
    _id: threadId,
    "participants.user": currentUserId,
  })
    .populate(
      "participants.user",
      USER_PUBLIC_FIELDS,
    )
    .populate(
      "messages.sender",
      USER_PUBLIC_FIELDS,
    );
}

function touchParticipantReadState(
  thread,
  userId,
  timestamp,
) {
  const participant = thread.participants.find(
    (item) => {
      return (
        String(item.user?._id || item.user) ===
        String(userId)
      );
    },
  );

  if (participant) {
    participant.lastReadAt = timestamp;
  }
}

function appendThreadMessage(
  thread,
  sender,
  message,
  timestamp,
) {
  thread.messages.push({
    sender: sender._id,
    senderName: buildFullName(sender),
    senderRole: sender.role,
    text: message.text,
    attachment: message.attachment || null,
    createdAt: timestamp,
  });
  thread.lastMessageAt = timestamp;
  touchParticipantReadState(
    thread,
    sender._id,
    timestamp,
  );
}

function buildInternalChatMessagePayload({
  text,
  attachment = null,
}) {
  const normalizedText = String(
    text || "",
  ).trim();

  return {
    text:
      normalizedText ||
      INTERNAL_CHAT_ATTACHMENT_PLACEHOLDER,
    attachment,
  };
}

function buildInternalChatTranscriptLine(
  message,
  currentUserId,
) {
  const senderId = String(
    message?.sender?._id ||
      message?.sender ||
      message?.senderId ||
      "",
  );
  const senderLabel =
    senderId === String(currentUserId)
      ? "You"
      : message?.senderName || "Other operator";
  const senderRole = String(
    message?.senderRole ||
      message?.sender?.role ||
      "user",
  );
  const createdAt = message?.createdAt
    ? new Date(message.createdAt).toISOString()
    : "unknown-time";
  const messageText =
    String(message?.text || "").trim() ||
    "[no text]";
  const attachmentNote = message?.attachment
    ?.originalName
    ? ` [Attachment: ${message.attachment.originalName}]`
    : "";

  return `[${createdAt}] ${senderLabel} (${senderRole}): ${messageText}${attachmentNote}`;
}

function extractInternalChatMessageSenderId(
  message,
) {
  return String(
    message?.sender?._id ||
      message?.sender ||
      message?.senderId ||
      "",
  );
}

function normalizeInternalChatDraft(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeInternalChatDraftForComparison(
  value,
) {
  return normalizeInternalChatDraft(value)
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function capitalizeWord(value) {
  if (!value) {
    return "";
  }

  return (
    value.charAt(0).toUpperCase() +
    value.slice(1).toLowerCase()
  );
}

function containsInternalChatHostileLanguage(
  value,
) {
  return INTERNAL_CHAT_HOSTILE_LANGUAGE_PATTERN.test(
    normalizeInternalChatDraft(value),
  );
}

function containsInternalChatUnprofessionalTone(
  value,
) {
  return INTERNAL_CHAT_UNPROFESSIONAL_TONE_PATTERN.test(
    normalizeInternalChatDraft(value),
  );
}

function isShortInternalChatGreeting(value) {
  return INTERNAL_CHAT_SHORT_GREETING_PATTERN.test(
    normalizeInternalChatDraft(value),
  );
}

function isWaitingForInternalChatReply(
  thread,
  currentUserId,
) {
  const messages = Array.isArray(thread?.messages)
    ? thread.messages
    : [];
  if (!messages.length) {
    return false;
  }

  const latestMessage =
    messages[messages.length - 1];
  return (
    extractInternalChatMessageSenderId(
      latestMessage,
    ) === String(currentUserId)
  );
}

function buildInternalChatCounterpartGreeting(
  thread,
  currentUserId,
) {
  const latestIncomingMessage = [
    ...(thread?.messages || []),
  ]
    .reverse()
    .find((message) => {
      return (
        extractInternalChatMessageSenderId(
          message,
        ) !== String(currentUserId)
      );
    });

  const incomingName = String(
    latestIncomingMessage?.senderName || "",
  ).trim();
  const counterpartName =
    incomingName ||
    buildFullName(
      (Array.isArray(thread?.participants)
        ? thread.participants
        : []
      ).find((participant) => {
        const participantId = String(
          participant?.user?._id ||
            participant?.user ||
            "",
        );
        return (
          participantId &&
          participantId !== String(currentUserId)
        );
      })?.user || {},
    );
  const firstName = String(counterpartName || "")
    .trim()
    .split(/\s+/)
    .find(Boolean);

  if (!firstName) {
    return "Hello,";
  }

  return `Hello ${capitalizeWord(firstName)},`;
}

function cleanInternalChatDraftBody(draft) {
  return normalizeInternalChatDraft(draft)
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

function buildProfessionalInternalChatRewrite(
  thread,
  draft,
  currentUserId,
) {
  const normalizedDraft =
    normalizeInternalChatDraft(draft);
  if (!normalizedDraft) {
    return "";
  }

  const greeting =
    buildInternalChatCounterpartGreeting(
      thread,
      currentUserId,
    );
  if (
    isShortInternalChatGreeting(normalizedDraft)
  ) {
    return `${greeting} I hope you are well.`;
  }

  const looksLikeFollowUp =
    isWaitingForInternalChatReply(
      thread,
      currentUserId,
    ) ||
    containsInternalChatHostileLanguage(
      normalizedDraft,
    ) ||
    INTERNAL_CHAT_REPLY_DELAY_PATTERN.test(
      normalizedDraft,
    );

  if (looksLikeFollowUp) {
    return `${greeting} sorry to follow up. Are you currently busy? I have not received a reply from you yet.`;
  }

  const cleanedBody = cleanInternalChatDraftBody(
    normalizedDraft,
  );
  if (!cleanedBody) {
    return `${greeting} I hope you are well.`;
  }

  const polishedBody = polishInternalChatDraft(
    cleanedBody,
  ).replace(/^[A-Z][a-z]+,\s+/, "");
  if (!polishedBody) {
    return `${greeting} I hope you are well.`;
  }

  return `${greeting} ${polishedBody}`;
}

function shouldForceProfessionalRewrite(
  draft,
  suggestion,
) {
  const normalizedDraft =
    normalizeInternalChatDraft(draft);
  if (!normalizedDraft) {
    return false;
  }

  const normalizedSuggestion =
    normalizeInternalChatDraft(suggestion);
  return (
    isShortInternalChatGreeting(
      normalizedDraft,
    ) ||
    containsInternalChatHostileLanguage(
      normalizedDraft,
    ) ||
    containsInternalChatUnprofessionalTone(
      normalizedDraft,
    ) ||
    normalizeInternalChatDraftForComparison(
      normalizedSuggestion,
    ) ===
      normalizeInternalChatDraftForComparison(
        normalizedDraft,
      )
  );
}

function polishInternalChatDraft(draft) {
  let text = normalizeInternalChatDraft(draft);
  if (!text) {
    return "";
  }

  text = text
    .replace(/\bmy\s+nanes\b/gi, "my name is")
    .replace(/\bmy\s+nane\b/gi, "my name is")
    .replace(/\bmy\s+names\b/gi, "my name is")
    .replace(/\bim\b/gi, "I'm")
    .replace(/\bdont\b/gi, "don't")
    .replace(/\bcant\b/gi, "can't")
    .replace(/\bwont\b/gi, "won't")
    .replace(/\bi\b/g, "I");

  text = text.replace(
    /\b(my name is\s+)([a-z][a-z'-]*)\b/gi,
    (_match, prefix, name) =>
      `${prefix}${capitalizeWord(name)}`,
  );

  text = text.replace(
    /^(my name is\s+[A-Z][A-Za-z'-]*)(\s+)(?=(the|we|i|you|he|she|they|it|tomorrow|today|yesterday)\b)/i,
    (_match, intro) => `${intro}. `,
  );

  text = text.replace(
    /([.!?])(?=[A-Za-z])/g,
    "$1 ",
  );
  text = text.replace(/\s+/g, " ").trim();

  text = text.replace(
    /(^|[.!?]\s+)([a-z])/g,
    (_match, prefix, letter) => {
      return `${prefix}${letter.toUpperCase()}`;
    },
  );

  if (!/[.!?]$/.test(text)) {
    text = `${text}.`;
  }

  return text;
}

function buildInternalChatFallbackSuggestion(
  thread,
  draft,
  currentUserId,
) {
  const normalizedDraft =
    normalizeInternalChatDraft(draft);
  if (normalizedDraft) {
    return buildProfessionalInternalChatRewrite(
      thread,
      normalizedDraft,
      currentUserId,
    );
  }

  const latestIncomingMessage = [
    ...(thread?.messages || []),
  ]
    .reverse()
    .find((message) => {
      const senderId = String(
        message?.sender?._id ||
          message?.sender ||
          message?.senderId ||
          "",
      );
      return (
        senderId &&
        senderId !== String(currentUserId)
      );
    });

  if (latestIncomingMessage?.senderName) {
    return `Thanks ${latestIncomingMessage.senderName}. I have reviewed the thread and will follow up on the next step shortly.`;
  }

  return "Thanks for the update. I have reviewed the thread and will follow up shortly.";
}

async function requestInternalChatAiSuggestion({
  thread,
  sender,
  draft,
  logContext,
}) {
  const normalizedDraft =
    normalizeInternalChatDraft(draft);
  const deterministicFallback =
    buildInternalChatFallbackSuggestion(
      thread,
      normalizedDraft,
      sender?._id,
    );
  if (
    !env.aiApiKey ||
    !env.aiBaseUrl ||
    !env.aiModelReasoning
  ) {
    return deterministicFallback;
  }

  const transcript = (
    Array.isArray(thread?.messages)
      ? thread.messages
      : []
  )
    .slice(-18)
    .map((message) =>
      buildInternalChatTranscriptLine(
        message,
        sender?._id,
      ),
    )
    .join("\n");
  const participantSummary = (
    Array.isArray(thread?.participants)
      ? thread.participants
      : []
  )
    .map((participant) =>
      buildFullName(participant?.user || {}),
    )
    .filter(Boolean)
    .join(", ");
  const prompt = [
    `You are ${INTERNAL_CHAT_AI_ASSISTANT_NAME}, an internal reply assistant for Adams Service Ops.`,
    `Write the best possible next message for ${buildFullName(sender)} (${sender.role}) to send in this internal ${thread.threadType} chat.`,
    "This is a workplace operations chat between staff and admin users.",
    "Read the conversation carefully before writing.",
    "If a draft is provided, always rewrite it into a polished professional workplace message without changing the factual meaning.",
    "Never return the draft unchanged when a draft is provided.",
    "Address the other participant by first name when possible; otherwise use their role.",
    "Even a short greeting like hi should become a fuller professional greeting.",
    "If the draft contains profanity, insults, hostility, or impatient wording, rewrite it into calm, respectful, workplace-safe language.",
    "Never keep profanity, abuse, or aggressive phrasing in the final suggestion.",
    "If the sender appears to be following up on a missing reply, turn that into a polite follow-up asking whether the other person is currently busy or available.",
    "Prefer a courteous professional rewrite over a literal paraphrase when the original tone is inappropriate for work.",
    "If the draft is empty, compose the best next reply from the conversation alone.",
    "Do not invent facts, dates, promises, or decisions that are not in the thread.",
    "Keep names, references, addresses, and numbers exact when they already exist.",
    "Match the language used in the draft when present; otherwise mirror the latest relevant human message.",
    "Keep the message concise, professional, and operationally useful.",
    "Do not mention AI, assistants, models, prompts, or analysis.",
    'Return valid JSON only with this shape: {"suggestion":"..."}',
    `Thread title: ${thread.title || thread.threadType}`,
    `Participants: ${participantSummary || "Unknown participants"}`,
    normalizedDraft
      ? `Current draft from ${buildFullName(sender)}: ${normalizedDraft}`
      : "Current draft: [empty]",
    "Recent conversation:",
    transcript || "[no prior messages]",
  ].join("\n");

  logInfo({
    ...logContext,
    step: LOG_STEPS.PROVIDER_CALL_START,
    layer: "service",
    operation: "InternalChatSuggestReply",
    intent:
      "Generate an AI-refined internal chat reply from the live thread context",
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
          response_format: {
            type: "json_object",
          },
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
        operation: "InternalChatSuggestReply",
        intent:
          "Capture the AI provider failure before falling back to a deterministic internal-chat suggestion",
        classification:
          ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
        error_code:
          "INTERNAL_CHAT_AI_PROVIDER_REJECTED",
        resolution_hint:
          "Check the configured AI provider credentials and try again",
        message:
          responseBody ||
          `Provider returned HTTP ${response.status}`,
      });
      return buildInternalChatFallbackSuggestion(
        thread,
        normalizedDraft,
        sender?._id,
      );
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

    const professionalDraftRewrite =
      buildProfessionalInternalChatRewrite(
        thread,
        normalizedDraft,
        sender?._id,
      );
    const normalizedSuggestion =
      normalizeInternalChatDraft(suggestion);
    const shouldUseDeterministicRewrite =
      Boolean(professionalDraftRewrite) &&
      shouldForceProfessionalRewrite(
        normalizedDraft,
        normalizedSuggestion,
      );
    const resolvedSuggestion =
      shouldUseDeterministicRewrite
        ? professionalDraftRewrite
        : normalizedSuggestion;
    if (!resolvedSuggestion) {
      return deterministicFallback;
    }

    if (
      normalizeInternalChatDraftForComparison(
        resolvedSuggestion,
      ) ===
      normalizeInternalChatDraftForComparison(
        normalizedDraft,
      )
    ) {
      return deterministicFallback;
    }

    logInfo({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_OK,
      layer: "service",
      operation: "InternalChatSuggestReply",
      intent:
        "Confirm the AI provider returned a usable internal-chat draft suggestion",
      provider: env.aiProvider,
      model: env.aiModelReasoning,
    });

    return resolvedSuggestion;
  } catch (error) {
    logError({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
      layer: "service",
      operation: "InternalChatSuggestReply",
      intent:
        "Capture unexpected AI provider errors before falling back to a deterministic internal-chat suggestion",
      classification:
        ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      error_code:
        "INTERNAL_CHAT_AI_PROVIDER_FAILED",
      resolution_hint:
        "Check the configured AI provider and network reachability",
      message: error.message,
    });
    return deterministicFallback;
  }
}

async function listInternalChats(
  authUser,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "InternalChatList",
    intent:
      "Load real internal direct and group chat threads plus the active operator directory",
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "InternalChatList",
    intent:
      "Fetch accessible internal chat threads and active admin/staff directory rows together",
  });

  const [currentUser, threads, directoryUsers] =
    await Promise.all([
      loadActiveChatUser(authUser.id),
      InternalChatThread.find({
        "participants.user": authUser.id,
      })
        .populate(
          "participants.user",
          USER_PUBLIC_FIELDS,
        )
        .populate(
          "messages.sender",
          USER_PUBLIC_FIELDS,
        )
        .sort({
          lastMessageAt: -1,
          updatedAt: -1,
        }),
      User.find({
        _id: { $ne: authUser.id },
        role: {
          $in: INTERNAL_CHAT_ALLOWED_ROLES,
        },
        status: USER_STATUSES.ACTIVE,
      }).select(USER_PUBLIC_FIELDS),
    ]);

  if (!currentUser) {
    throw new AppError({
      message: "Operator account not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: "INTERNAL_CHAT_USER_NOT_FOUND",
      resolutionHint:
        "Log in again and try once more",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "InternalChatList",
    intent:
      "Confirm internal chat threads and directory rows are ready for response shaping",
  });

  const sortedDirectory = [
    ...directoryUsers,
  ].sort((left, right) => {
    const leftOnline =
      left.staffAvailability === "online" ? 0 : 1;
    const rightOnline =
      right.staffAvailability === "online"
        ? 0
        : 1;
    if (leftOnline !== rightOnline) {
      return leftOnline - rightOnline;
    }

    if (left.role !== right.role) {
      return left.role === USER_ROLES.ADMIN
        ? -1
        : 1;
    }

    return buildFullName(left).localeCompare(
      buildFullName(right),
    );
  });

  return {
    message:
      "Internal chats fetched successfully",
    threads: threads
      .map((thread) =>
        serializeInternalChatThread(
          thread,
          authUser.id,
        ),
      )
      .filter(Boolean),
    directory: sortedDirectory
      .map(serializeUser)
      .filter(Boolean),
  };
}

async function createDirectThreadAndSendMessage(
  authUser,
  participantId,
  message,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "InternalChatCreateDirectThread",
    intent:
      "Start or reuse a real direct internal chat thread and persist the first message",
  });

  if (
    String(authUser.id) === String(participantId)
  ) {
    throw new AppError({
      message:
        "Choose another person to start a chat",
      statusCode: 400,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: "INTERNAL_CHAT_SELF_RECIPIENT",
      resolutionHint:
        "Pick a different staff or admin account",
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "InternalChatCreateDirectThread",
    intent:
      "Validate both chat participants and load any existing direct thread before writing a message",
  });

  const [sender, recipient] = await Promise.all([
    loadActiveChatUser(authUser.id),
    loadActiveChatUser(participantId),
  ]);

  if (!sender) {
    throw new AppError({
      message: "Operator account not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: "INTERNAL_CHAT_SENDER_NOT_FOUND",
      resolutionHint:
        "Log in again and try once more",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!recipient) {
    throw new AppError({
      message: "Recipient not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode:
        "INTERNAL_CHAT_RECIPIENT_NOT_FOUND",
      resolutionHint:
        "Refresh the team list and choose an active account",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const participantKey = buildParticipantKey(
    sender._id,
    recipient._id,
  );
  let thread = await InternalChatThread.findOne({
    participantKey,
  });
  const messageTimestamp = new Date();

  if (!thread) {
    thread = await InternalChatThread.create({
      threadType: "direct",
      participantKey,
      participants: [
        {
          user: sender._id,
          lastReadAt: messageTimestamp,
        },
        { user: recipient._id, lastReadAt: null },
      ],
      createdBy: sender._id,
      lastMessageAt: messageTimestamp,
      messages: [],
    });
  }

  appendThreadMessage(
    thread,
    sender,
    buildInternalChatMessagePayload({
      text: message,
    }),
    messageTimestamp,
  );
  await thread.save();

  const populatedThread =
    await populateInternalChatThread(thread._id);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "InternalChatCreateDirectThread",
    intent:
      "Confirm the direct chat thread exists and the first message was persisted",
  });

  return {
    message: "Internal message sent successfully",
    thread: serializeInternalChatThread(
      populatedThread,
      authUser.id,
    ),
  };
}

async function createGroupThreadAndSendMessage(
  authUser,
  title,
  participantIds,
  message,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "InternalChatCreateGroupThread",
    intent:
      "Create a real internal group chat thread and persist the first message",
  });

  const normalizedParticipantIds =
    normalizeUniqueParticipantIds(
      participantIds,
      authUser.id,
    );

  if (normalizedParticipantIds.length < 2) {
    throw new AppError({
      message:
        "Choose at least two other people for a group chat",
      statusCode: 400,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: "INTERNAL_CHAT_GROUP_TOO_SMALL",
      resolutionHint:
        "Pick at least two active admin or staff accounts",
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "InternalChatCreateGroupThread",
    intent:
      "Validate the group creator and all requested participants before creating the thread",
  });

  const [sender, recipients] = await Promise.all([
    loadActiveChatUser(authUser.id),
    loadActiveChatUsers(normalizedParticipantIds),
  ]);

  if (!sender) {
    throw new AppError({
      message: "Operator account not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: "INTERNAL_CHAT_SENDER_NOT_FOUND",
      resolutionHint:
        "Log in again and try once more",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (
    recipients.length !==
    normalizedParticipantIds.length
  ) {
    throw new AppError({
      message:
        "One or more selected people are no longer available",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode:
        "INTERNAL_CHAT_GROUP_RECIPIENT_NOT_FOUND",
      resolutionHint:
        "Refresh the team list and choose only active accounts",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const messageTimestamp = new Date();
  const thread = await InternalChatThread.create({
    threadType: "group",
    title: String(title || "").trim(),
    participantKey: null,
    participants: [
      {
        user: sender._id,
        lastReadAt: messageTimestamp,
      },
      ...recipients.map((user) => ({
        user: user._id,
        lastReadAt: null,
      })),
    ],
    createdBy: sender._id,
    lastMessageAt: messageTimestamp,
    messages: [],
  });

  appendThreadMessage(
    thread,
    sender,
    buildInternalChatMessagePayload({
      text: message,
    }),
    messageTimestamp,
  );
  await thread.save();

  const populatedThread =
    await populateInternalChatThread(thread._id);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "InternalChatCreateGroupThread",
    intent:
      "Confirm the group chat thread exists and the first message was persisted",
  });

  return {
    message:
      "Internal group created successfully",
    thread: serializeInternalChatThread(
      populatedThread,
      authUser.id,
    ),
  };
}

async function postInternalChatMessage(
  authUser,
  threadId,
  message,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "InternalChatPostMessage",
    intent:
      "Append a new message onto an existing internal chat thread",
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "InternalChatPostMessage",
    intent:
      "Load the thread and sender identity before persisting the new internal message",
  });

  const [sender, thread] = await Promise.all([
    loadActiveChatUser(authUser.id),
    loadAccessibleThread(threadId, authUser.id),
  ]);

  if (!sender) {
    throw new AppError({
      message: "Operator account not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: "INTERNAL_CHAT_SENDER_NOT_FOUND",
      resolutionHint:
        "Log in again and try once more",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!thread) {
    throw new AppError({
      message: "Chat thread not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: "INTERNAL_CHAT_THREAD_NOT_FOUND",
      resolutionHint:
        "Refresh the chat list and open a valid thread",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const messageTimestamp = new Date();
  appendThreadMessage(
    thread,
    sender,
    buildInternalChatMessagePayload({
      text: message,
    }),
    messageTimestamp,
  );
  await thread.save();

  const populatedThread =
    await populateInternalChatThread(thread._id);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "InternalChatPostMessage",
    intent:
      "Confirm the internal chat message was saved on the accessible thread",
  });

  return {
    message: "Internal message sent successfully",
    thread: serializeInternalChatThread(
      populatedThread,
      authUser.id,
    ),
  };
}

async function uploadInternalChatAttachment(
  authUser,
  threadId,
  file,
  caption,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "InternalChatUploadAttachment",
    intent:
      "Store an internal chat attachment and append it to the accessible thread",
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "InternalChatUploadAttachment",
    intent:
      "Load the sender and accessible thread before saving the uploaded internal chat attachment",
  });

  const [sender, thread] = await Promise.all([
    loadActiveChatUser(authUser.id),
    loadAccessibleThread(threadId, authUser.id),
  ]);

  if (!sender) {
    throw new AppError({
      message: "Operator account not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: "INTERNAL_CHAT_SENDER_NOT_FOUND",
      resolutionHint:
        "Log in again and try once more",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!thread) {
    throw new AppError({
      message: "Chat thread not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: "INTERNAL_CHAT_THREAD_NOT_FOUND",
      resolutionHint:
        "Refresh the chat list and open a valid thread",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const storedFile =
    await storeInternalChatAttachmentFile(file, {
      ...logContext,
      operation: "InternalChatUploadAttachment",
    });
  const attachment =
    buildRequestMessageAttachment(storedFile);
  const messageTimestamp = new Date();

  appendThreadMessage(
    thread,
    sender,
    buildInternalChatMessagePayload({
      text: caption,
      attachment,
    }),
    messageTimestamp,
  );
  await thread.save();

  const populatedThread =
    await populateInternalChatThread(thread._id);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "InternalChatUploadAttachment",
    intent:
      "Confirm the attachment-backed internal chat message was saved on the thread",
  });

  return {
    message:
      "Internal attachment sent successfully",
    thread: serializeInternalChatThread(
      populatedThread,
      authUser.id,
    ),
  };
}

async function markInternalChatRead(
  authUser,
  threadId,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "InternalChatMarkRead",
    intent:
      "Mark an internal thread as read for the current operator",
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "InternalChatMarkRead",
    intent:
      "Load the accessible thread before updating the participant read marker",
  });

  const thread = await loadAccessibleThread(
    threadId,
    authUser.id,
  );

  if (!thread) {
    throw new AppError({
      message: "Chat thread not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: "INTERNAL_CHAT_THREAD_NOT_FOUND",
      resolutionHint:
        "Refresh the chat list and open a valid thread",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const timestamp = new Date();
  touchParticipantReadState(
    thread,
    authUser.id,
    timestamp,
  );
  await thread.save();

  const populatedThread =
    await populateInternalChatThread(thread._id);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "InternalChatMarkRead",
    intent:
      "Confirm the current operator read marker was saved on the thread",
  });

  return {
    message: "Internal chat marked as read",
    thread: serializeInternalChatThread(
      populatedThread,
      authUser.id,
    ),
  };
}

async function suggestInternalChatReply(
  authUser,
  threadId,
  draft,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "InternalChatSuggestReply",
    intent:
      "Generate an AI-assisted internal chat reply suggestion from the current thread context",
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "InternalChatSuggestReply",
    intent:
      "Load the sender and accessible thread before generating the internal chat suggestion",
  });

  const [sender, thread] = await Promise.all([
    loadActiveChatUser(authUser.id),
    loadAccessibleThread(threadId, authUser.id),
  ]);

  if (!sender) {
    throw new AppError({
      message: "Operator account not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: "INTERNAL_CHAT_SENDER_NOT_FOUND",
      resolutionHint:
        "Log in again and try once more",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!thread) {
    throw new AppError({
      message: "Chat thread not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: "INTERNAL_CHAT_THREAD_NOT_FOUND",
      resolutionHint:
        "Refresh the chat list and open a valid thread",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const suggestion =
    await requestInternalChatAiSuggestion({
      thread,
      sender,
      draft,
      logContext,
    });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "InternalChatSuggestReply",
    intent:
      "Confirm the internal chat suggestion is ready for the composer",
  });

  return {
    message:
      "Internal chat suggestion generated successfully",
    assistant: {
      name: INTERNAL_CHAT_AI_ASSISTANT_NAME,
      suggestion,
    },
  };
}

module.exports = {
  createDirectThreadAndSendMessage,
  createGroupThreadAndSendMessage,
  listInternalChats,
  markInternalChatRead,
  postInternalChatMessage,
  suggestInternalChatReply,
  uploadInternalChatAttachment,
};
