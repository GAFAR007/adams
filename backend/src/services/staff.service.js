/**
 * WHAT: Implements invite-based staff registration plus queue, availability, and request-thread workflows.
 * WHY: Staff need one service boundary for onboarding, queue pickup, multi-request handling, and customer replies.
 * HOW: Verify invites, toggle staff availability, atomically claim queue items, and append staff/system updates to request threads.
 */

const bcrypt = require('bcryptjs');

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  PAYMENT_REQUEST_STATUSES,
  REQUEST_ASSESSMENT_STATUSES,
  REQUEST_ASSESSMENT_TYPES,
  REQUEST_ESTIMATION_STAGES,
  REQUEST_MESSAGE_ACTIONS,
  REQUEST_QUOTE_READINESS_STATUSES,
  REQUEST_REVIEW_KINDS,
  REQUEST_STATUSES,
  REQUEST_WORK_LOG_TYPES,
  STAFF_AVAILABILITIES,
  STAFF_TYPES,
  USER_ROLES,
  USER_STATUSES,
} = require('../constants/app.constants');
const { CompanyProfile } = require('../models/company-profile.model');
const { ServiceRequest } = require('../models/service-request.model');
const { StaffInvite } = require('../models/staff-invite.model');
const { User } = require('../models/user.model');
const { AppError } = require('../utils/app-error');
const { logInfo } = require('../utils/logger');
const {
  createHostedPaymentSession,
} = require('../utils/payment-provider');
const {
  buildAttachmentActionPayload,
  buildAiMessage,
  buildRequestMessageAttachment,
  buildStaffMessage,
  buildSystemMessage,
  resolveWorkflowAttachmentCategory,
} = require('../utils/request-chat');
const {
  REQUEST_REPLY_ASSISTANT_NAME,
  suggestRequestThreadReply,
} = require('../utils/request-reply-assistant');
const { buildAiControlEnabledText } = require('../utils/request-queue-ai');
const {
  applyInvoiceReview,
  buildInvoiceRequestMessage,
  buildProofReviewMessage,
  createInvoiceRecord,
  isInvoiceProofUploadLocked,
  isQuoteReviewReady,
  invoiceNeedsCustomerProof,
  unlockInvoiceProofUpload,
} = require('../utils/request-payment');
const {
  buildEstimateUpdatedWorkflowEvent,
  buildQuoteInvalidatedWorkflowEvent,
  buildQuoteReadyForCustomerCareWorkflowEvent,
  buildQuoteReadyForInternalReviewWorkflowEvent,
  buildQuotationSentWorkflowEvent,
  buildSiteReviewReadyForCustomerCareWorkflowEvent,
  buildSiteReviewReadyForInternalReviewWorkflowEvent,
} = require('../utils/request-quote-workflow');
const {
  finalizeApprovedInvoice,
  syncApprovedInvoiceReceiptIfNeeded,
  syncOnlineInvoicePaymentIfNeeded,
} = require('../utils/request-payment-status');
const {
  calculateEstimatedHoursFromDailySchedule,
  calculateEstimatedDays,
  buildRequestCalendarWindow,
  getSelectedRequestEstimation,
  isCompleteFinalRequestEstimation,
  isSiteReviewBookingReady,
  getReadySiteReviewEstimations,
  normalizeDateValue,
  normalizeEstimatedDailySchedule,
  requestOverlapsCalendarRange,
  resolveEstimationStage,
} = require('../utils/request-estimation');
const { populateServiceRequestRelations } = require('../utils/request-query');
const { serializeServiceRequest, serializeUser } = require('../utils/serializers');
const { refreshRequestMediaSummary } = require('../utils/request-media');
const { storeRequestAttachmentFile } = require('./file-storage.service');
const { issueSessionTokens, verifyStaffInviteToken } = require('./token.service');

const STAFF_MANAGEABLE_STATUSES = [
  REQUEST_STATUSES.UNDER_REVIEW,
  REQUEST_STATUSES.QUOTED,
  REQUEST_STATUSES.APPOINTMENT_CONFIRMED,
  REQUEST_STATUSES.PENDING_START,
  REQUEST_STATUSES.PROJECT_STARTED,
  REQUEST_STATUSES.WORK_DONE,
  REQUEST_STATUSES.CLOSED,
];

const STAFF_OPEN_STATUSES = [
  REQUEST_STATUSES.ASSIGNED,
  REQUEST_STATUSES.UNDER_REVIEW,
  REQUEST_STATUSES.QUOTED,
  REQUEST_STATUSES.APPOINTMENT_CONFIRMED,
  REQUEST_STATUSES.PENDING_START,
  REQUEST_STATUSES.PROJECT_STARTED,
  REQUEST_STATUSES.WORK_DONE,
];

function isCustomerEditLocked(request) {
  if (!request) {
    return false;
  }

  return (
    Boolean(request.invoice) ||
    request.status === REQUEST_STATUSES.QUOTED ||
    request.status === REQUEST_STATUSES.APPOINTMENT_CONFIRMED ||
    request.status === REQUEST_STATUSES.PENDING_START ||
    request.status === REQUEST_STATUSES.PROJECT_STARTED ||
    request.status === REQUEST_STATUSES.WORK_DONE ||
    request.status === REQUEST_STATUSES.CLOSED
  );
}

function formatThreadDate(value) {
  const parsed = normalizeDateValue(value);
  if (!parsed) {
    return '';
  }

  const day = String(parsed.getUTCDate()).padStart(2, '0');
  const month = String(parsed.getUTCMonth() + 1).padStart(2, '0');
  const year = String(parsed.getUTCFullYear());
  return `${day}/${month}/${year}`;
}

function startOfToday() {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  return date;
}

function endOfToday() {
  const date = new Date();
  date.setHours(23, 59, 59, 999);
  return date;
}

async function loadQueueCompanyProfile() {
  return CompanyProfile.findOne({ siteKey: 'default' }).lean();
}

function resolveStaffOperationalType(staffUser) {
  if (staffUser?.staffType === STAFF_TYPES.CONTRACTOR) {
    return STAFF_TYPES.CONTRACTOR;
  }

  if (staffUser?.staffType === STAFF_TYPES.CUSTOMER_CARE) {
    return STAFF_TYPES.CUSTOMER_CARE;
  }

  return STAFF_TYPES.TECHNICIAN;
}

function resolveEstimationAssignmentType(staffUser) {
  return resolveStaffOperationalType(staffUser) === STAFF_TYPES.CONTRACTOR
    ? 'external'
    : 'internal';
}

function isCustomerCareStaff(staffUser) {
  return resolveStaffOperationalType(staffUser) === STAFF_TYPES.CUSTOMER_CARE;
}

function isSiteReviewStillPending(assessmentType, assessmentStatus) {
  return (
    assessmentType === REQUEST_ASSESSMENT_TYPES.SITE_REVIEW_REQUIRED &&
    assessmentStatus !== REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_COMPLETED
  );
}

function hasActiveSiteReviewInvoice(request) {
  return request?.invoice?.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW;
}

function getSelectedReadySiteReviewEstimation(request) {
  const readyEstimations = getReadySiteReviewEstimations(request);
  const selectedId = request?.selectedEstimationId
    ? String(request.selectedEstimationId)
    : '';

  if (selectedId) {
    const selected = readyEstimations.find((estimation) => {
      return String(estimation?._id || estimation?.id || '') === selectedId;
    });
    if (selected) {
      return selected;
    }
  }

  return readyEstimations.length > 0
    ? readyEstimations[readyEstimations.length - 1]
    : null;
}

function buildStaffVisibleRequestQuery(requestId, staffUser) {
  if (isCustomerCareStaff(staffUser)) {
    return { _id: requestId };
  }

  return {
    _id: requestId,
    assignedStaff: staffUser?._id || staffUser?.id || null,
  };
}

function buildStaffRequestListQuery(staffUser, filters = {}) {
  const query = {};

  if (!isCustomerCareStaff(staffUser)) {
    query.assignedStaff = staffUser?._id || staffUser?.id || null;
  }

  if (filters.status) {
    query.status = filters.status;
  }

  return query;
}

async function loadActiveStaffUser(staffUserId) {
  // WHY: Staff-only actions should always resolve identity from MongoDB so queue and reply permissions stay trustworthy.
  return User.findOne({
    _id: staffUserId,
    role: USER_ROLES.STAFF,
    status: USER_STATUSES.ACTIVE,
  });
}

async function loadStaffVisibleRequest(requestId, staffUser) {
  // WHY: Customer care must see every request for handoff, while technicians and contractors remain scoped to assigned work.
  const request = await populateServiceRequestRelations(
    ServiceRequest.findOne({
      ...buildStaffVisibleRequestQuery(requestId, staffUser),
    }),
  );

  if (
    request &&
    (
      await syncOnlineInvoicePaymentIfNeeded(request) ||
      await syncApprovedInvoiceReceiptIfNeeded(request)
    )
  ) {
    await request.save();
  }

  return request;
}

function parseCalendarDateFilters(filters = {}) {
  return {
    start: normalizeDateValue(filters.start),
    end: normalizeDateValue(filters.end),
  };
}

async function syncRequestCollectionInvoices(requests) {
  await Promise.all(
    requests.map(async (request) => {
      if (
        await syncOnlineInvoicePaymentIfNeeded(request) ||
        await syncApprovedInvoiceReceiptIfNeeded(request)
      ) {
        await request.save();
      }
    }),
  );
}

async function registerFromInvite(payload, meta, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffRegister',
    intent: 'Create a staff account only after a valid invite has been presented',
  });

  // WHY: Verify the signed invite token before hitting MongoDB so fake links fail early.
  const invitePayload = verifyStaffInviteToken(payload.inviteToken);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffRegister',
    intent: 'Load the invite record and confirm it is still eligible for registration',
  });

  const invite = await StaffInvite.findOne({
    inviteId: invitePayload.inviteId,
    email: invitePayload.email.toLowerCase(),
  });

  // WHY: Reject used, revoked, or expired invites before creating a staff account.
  if (!invite || invite.acceptedAt || invite.revokedAt || invite.expiresAt <= new Date()) {
    throw new AppError({
      message: 'This staff invite is no longer available',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_REGISTER_INVITE_UNAVAILABLE',
      resolutionHint: 'Ask an admin to create a new invite link',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  // WHY: Block duplicate accounts when the invite email already belongs to an existing user.
  const existingUser = await User.findOne({ email: invite.email.toLowerCase() });

  if (existingUser) {
    throw new AppError({
      message: 'A user with this invite email already exists',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_REGISTER_EMAIL_TAKEN',
      resolutionHint: 'Use the existing account or ask an admin for help',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  // WHY: Hash the password before persistence so the invite flow never stores raw credentials.
  const passwordHash = await bcrypt.hash(payload.password, 12);

  // WHY: Build the staff account from the invite email so registration cannot change the invited identity.
  const user = await User.create({
    firstName: payload.firstName,
    lastName: payload.lastName,
    email: invite.email.toLowerCase(),
    phone: payload.phone || invite.phone || '',
    role: USER_ROLES.STAFF,
    staffType: invite.staffType || STAFF_TYPES.TECHNICIAN,
    status: USER_STATUSES.ACTIVE,
    staffAvailability: STAFF_AVAILABILITIES.OFFLINE,
    passwordHash,
  });

  // WHY: Mark the invite as consumed immediately so the same link cannot create another account later.
  invite.acceptedAt = new Date();
  await invite.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffRegister',
    intent: 'Confirm the invite was consumed and the staff account was created',
  });

  const tokens = await issueSessionTokens(user, meta, logContext);

  return {
    message: 'Staff account created successfully',
    user: serializeUser(user),
    ...tokens,
  };
}

async function getDashboard(staffUserId, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffGetDashboard',
    intent: 'Provide availability, queue, and assigned-work data for the staff dashboard',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffGetDashboard',
    intent: 'Load the staff profile, waiting queue, assigned work, and queue-clearing counts together',
  });

  const todayStart = startOfToday();

  const staff = await loadActiveStaffUser(staffUserId);

  // WHY: Stop here if the staff session no longer maps to an active staff account so queue controls do not run on stale sessions.
  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_DASHBOARD_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const visibleScope = buildStaffRequestListQuery(staff);

  const [
    waitingQueueCount,
    assignedCount,
    quotedCount,
    confirmedCount,
    pendingStartCount,
    clearedTodayCount,
    queueRequests,
    recentRequests,
  ] = await Promise.all([
    ServiceRequest.countDocuments({
      status: REQUEST_STATUSES.SUBMITTED,
      assignedStaff: null,
    }),
    ServiceRequest.countDocuments({
      ...visibleScope,
      status: { $in: STAFF_OPEN_STATUSES },
    }),
    ServiceRequest.countDocuments({
      ...visibleScope,
      status: REQUEST_STATUSES.QUOTED,
    }),
    ServiceRequest.countDocuments({
      ...visibleScope,
      status: REQUEST_STATUSES.APPOINTMENT_CONFIRMED,
    }),
    ServiceRequest.countDocuments({
      ...visibleScope,
      status: REQUEST_STATUSES.PENDING_START,
    }),
    ServiceRequest.countDocuments({
      ...visibleScope,
      status: REQUEST_STATUSES.CLOSED,
      closedAt: { $gte: todayStart },
    }),
    populateServiceRequestRelations(
      ServiceRequest.find({
        status: REQUEST_STATUSES.SUBMITTED,
        assignedStaff: null,
      })
        .sort({ queueEnteredAt: 1, createdAt: 1 })
        .limit(10),
    ),
    populateServiceRequestRelations(
      ServiceRequest.find(visibleScope)
        .sort({ updatedAt: -1, createdAt: -1 })
        .limit(10),
    ),
  ]);

  await syncRequestCollectionInvoices(queueRequests);
  await syncRequestCollectionInvoices(recentRequests);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffGetDashboard',
    intent: 'Confirm the staff queue and assignment snapshot is ready',
  });

  return {
    message: 'Staff dashboard fetched successfully',
    currentAvailability: staff.staffAvailability,
    kpis: {
      waitingQueueCount,
      assignedCount,
      quotedCount,
      confirmedCount,
      pendingStartCount,
      clearedTodayCount,
    },
    queueRequests: queueRequests.map(serializeServiceRequest),
    assignedRequests: recentRequests.map(serializeServiceRequest),
  };
}

async function listAssignedRequests(staffUserId, filters, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffListRequests',
    intent: 'Return only the requests assigned to the authenticated staff member',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_LIST_REQUESTS_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const query = buildStaffRequestListQuery(staff, filters);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffListRequests',
    intent: 'Load the assigned request rows and their related customer summaries',
  });

  const requests = await populateServiceRequestRelations(
    ServiceRequest.find(query).sort({ updatedAt: -1, createdAt: -1 }),
  );

  await syncRequestCollectionInvoices(requests);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffListRequests',
    intent: 'Confirm assigned request data is ready for the staff UI',
  });

  return {
    message: 'Assigned requests fetched successfully',
    requests: requests.map(serializeServiceRequest),
  };
}

async function listCalendarRequests(staffUserId, filters, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffListCalendarRequests',
    intent: 'Return shared calendar jobs so staff can review available and scheduled work',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_CALENDAR_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const { start, end } = parseCalendarDateFilters(filters);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffListCalendarRequests',
    intent: 'Load queue and assigned requests that can appear on the shared staff calendar',
  });

  const requests = await populateServiceRequestRelations(
    ServiceRequest.find()
      .sort({ updatedAt: -1, createdAt: -1 })
      .limit(250),
  );

  await syncRequestCollectionInvoices(requests);

  const calendarRequests = requests.filter((request) => {
    return requestOverlapsCalendarRange(request, start, end);
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffListCalendarRequests',
    intent: 'Confirm shared calendar request data is ready for staff planning and pickup',
  });

  return {
    message: 'Calendar jobs fetched successfully',
    requests: calendarRequests.map(serializeServiceRequest),
  };
}

async function clockAssignedRequestWork(
  staffUserId,
  requestId,
  action,
  note,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffClockRequestWork',
    intent: 'Persist a technician or contractor clock-in or clock-out entry on a scheduled request',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_CLOCK_WORK_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (isCustomerCareStaff(staff)) {
    throw new AppError({
      message: 'Customer care cannot clock on-site work',
      statusCode: 403,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_CLOCK_WORK_CUSTOMER_CARE_FORBIDDEN',
      resolutionHint: 'Use a technician or contractor account for work-day clock actions',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const request = await loadStaffVisibleRequest(requestId, staff);
  if (!request) {
    throw new AppError({
      message: 'Assigned request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_CLOCK_WORK_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!requestOverlapsCalendarRange(request, startOfToday(), endOfToday())) {
    throw new AppError({
      message: 'Clock actions are only available on the scheduled event day',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_CLOCK_WORK_OUTSIDE_EVENT_DAY',
      resolutionHint: 'Open this action on the day the review or job is scheduled',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const actorId = String(staff._id || staff.id || '');
  const workLogs = Array.isArray(request.workLogs) ? request.workLogs : [];
  const activeWorkLog = workLogs.find((workLog) => {
    const workLogActorId = String(workLog?.actorId?._id || workLog?.actorId || '');
    return workLogActorId === actorId && !workLog?.stoppedAt;
  });
  const now = new Date();
  const trimmedNote = typeof note === 'string' ? note.trim() : '';
  const isSiteReviewClock =
    request.assessmentStatus ===
    REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_SCHEDULED;
  const workType = isSiteReviewClock
    ? REQUEST_WORK_LOG_TYPES.SITE_REVIEW
    : REQUEST_WORK_LOG_TYPES.MAIN_JOB;
  const actionLabel = isSiteReviewClock
    ? 'site review'
    : 'scheduled work';
  const calendarWindow = buildRequestCalendarWindow(request);
  const scheduledEndDate = normalizeDateValue(calendarWindow?.endDate);
  const isLastScheduledJobDay =
    !scheduledEndDate || scheduledEndDate <= endOfToday();

  if (action === 'clock_in') {
    if (activeWorkLog) {
      throw new AppError({
        message: 'You are already clocked in for this request',
        statusCode: 409,
        classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
        errorCode: 'STAFF_CLOCK_WORK_ALREADY_STARTED',
        resolutionHint: 'Clock out the active session before starting a new one',
        step: LOG_STEPS.SERVICE_FAIL,
      });
    }

    request.attendedAt = request.attendedAt || now;
    if (!isSiteReviewClock) {
      // WHY: Main-job clock-in should move the request into live work-in-progress state automatically.
      request.status = REQUEST_STATUSES.PROJECT_STARTED;
      request.projectStartedAt = request.projectStartedAt || now;
    }
    request.workLogs.push({
      actorId: staff._id,
      actorRole: USER_ROLES.STAFF,
      workType,
      startedAt: now,
      note: trimmedNote,
    });
    request.messages.push(
      buildSystemMessage(
        `${staff.firstName} ${staff.lastName}`.trim()
          ? `${`${staff.firstName} ${staff.lastName}`.trim()} clocked in for ${actionLabel}.`
          : `Clocked in for ${actionLabel}.`,
      ),
    );
  } else {
    if (!activeWorkLog) {
      throw new AppError({
        message: 'No active clock-in was found for this request',
        statusCode: 409,
        classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
        errorCode: 'STAFF_CLOCK_WORK_NOT_STARTED',
        resolutionHint: 'Clock in first, then return here to clock out',
        step: LOG_STEPS.SERVICE_FAIL,
      });
    }

    activeWorkLog.stoppedAt = now;
    if (trimmedNote) {
      activeWorkLog.note = trimmedNote;
    }
    if (!isSiteReviewClock && isLastScheduledJobDay) {
      // WHY: On the final scheduled work day, clock-out should close the execution phase and mark the job as completed.
      request.status = REQUEST_STATUSES.WORK_DONE;
      request.finishedAt = request.finishedAt || now;
    }
    request.messages.push(
      buildSystemMessage(
        `${staff.firstName} ${staff.lastName}`.trim()
          ? `${`${staff.firstName} ${staff.lastName}`.trim()} clocked out from ${actionLabel}.`
          : `Clocked out from ${actionLabel}.`,
      ),
    );
  }

  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffClockRequestWork',
    intent: 'Confirm the work-log entry was saved on the assigned request',
  });

  return {
    message: action === 'clock_in'
      ? 'Clocked in successfully'
      : 'Clocked out successfully',
    request: serializeServiceRequest(request),
  };
}

async function updateAvailability(staffUserId, availability, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffUpdateAvailability',
    intent: 'Let staff opt into or out of handling live queue items',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffUpdateAvailability',
    intent: 'Persist the staff online/offline state on the staff account record',
  });

  const staff = await User.findOneAndUpdate(
    {
      _id: staffUserId,
      role: USER_ROLES.STAFF,
      status: USER_STATUSES.ACTIVE,
    },
    {
      staffAvailability: availability,
    },
    {
      new: true,
    },
  );

  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_AVAILABILITY_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffUpdateAvailability',
    intent: 'Confirm the staff availability flag was updated successfully',
  });

  return {
    message:
      availability === STAFF_AVAILABILITIES.ONLINE
        ? 'You are now online for queue handling'
        : 'You are now offline for queue handling',
    user: serializeUser(staff),
  };
}

async function attendQueueRequest(staffUserId, requestId, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffAttendQueueRequest',
    intent: 'Allow an online staff member to pick up a waiting customer queue thread',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffAttendQueueRequest',
    intent: 'Load the staff account and confirm it is online before claiming queue work',
  });

  const staff = await loadActiveStaffUser(staffUserId);

  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_ATTEND_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (staff.staffAvailability !== STAFF_AVAILABILITIES.ONLINE) {
    throw new AppError({
      message: 'Go online before attending a customer queue',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_ATTEND_REQUIRES_ONLINE_STATUS',
      resolutionHint: 'Switch your status to online and try again',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (resolveStaffOperationalType(staff) === STAFF_TYPES.CUSTOMER_CARE) {
    throw new AppError({
      message: 'Customer care cannot claim jobs from the shared queue',
      statusCode: 403,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_ATTEND_CUSTOMER_CARE_FORBIDDEN',
      resolutionHint: 'Use a technician or contractor account to claim and execute jobs',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const attendAt = new Date();

  // WHY: Claim the queue atomically so two staff members cannot pick up the same waiting request at the same time.
  let request = await populateServiceRequestRelations(
    ServiceRequest.findOneAndUpdate(
      {
        _id: requestId,
        status: REQUEST_STATUSES.SUBMITTED,
        assignedStaff: null,
      },
      {
        assignedStaff: staff._id,
        status: REQUEST_STATUSES.ASSIGNED,
        attendedAt: attendAt,
        $push: {
          messages: buildSystemMessage(
            `${staff.firstName} ${staff.lastName}`.trim() +
              ' joined your queue and can continue the conversation here.',
          ),
        },
      },
      {
        new: true,
      },
    ),
  );

  if (!request) {
    // WHY: Re-read the request when the atomic claim misses so the UI gets a precise reason instead of a silent generic failure.
    request = await populateServiceRequestRelations(
      ServiceRequest.findById(requestId),
    );

    if (!request) {
      throw new AppError({
        message: 'Queue request not found',
        statusCode: 404,
        classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
        errorCode: 'STAFF_ATTEND_REQUEST_NOT_FOUND',
        resolutionHint: 'Refresh the queue and try again',
        step: LOG_STEPS.DB_QUERY_FAIL,
      });
    }

    if (String(request.assignedStaff?._id || request.assignedStaff?.id || '') === String(staffUserId)) {
      return {
        message: 'You are already attending this queue',
        request: serializeServiceRequest(request),
      };
    }

    throw new AppError({
      message: 'Another staff member already picked up this queue',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_ATTEND_QUEUE_ALREADY_CLAIMED',
      resolutionHint: 'Refresh the queue and choose another waiting request',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffAttendQueueRequest',
    intent: 'Confirm the waiting queue item is now assigned to the staff member',
  });

  return {
    message: 'Queue picked up successfully',
    request: serializeServiceRequest(request),
  };
}

async function postAssignedRequestMessage(
  staffUserId,
  requestId,
  text,
  actionType,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffPostRequestMessage',
    intent: 'Append a staff reply onto an assigned customer thread',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffPostRequestMessage',
    intent: 'Load the staff account and assigned request before sending a reply',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  const request = staff
    ? await loadStaffVisibleRequest(requestId, staff)
    : null;

  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_MESSAGE_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!request) {
    throw new AppError({
      message: 'Assigned request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_MESSAGE_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (
    actionType === REQUEST_MESSAGE_ACTIONS.CUSTOMER_UPDATE_REQUEST &&
    isCustomerEditLocked(request)
  ) {
    throw new AppError({
      message: 'Customer updates are locked after the quotation has been sent',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_CUSTOMER_UPDATE_REQUEST_LOCKED',
      resolutionHint: 'Use the quoted work plan as the active reference from this point onward',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  request.messages.push(
    buildStaffMessage({
      staffId: staffUserId,
      staffName: `${staff.firstName} ${staff.lastName}`.trim(),
      actionType,
      text,
    }),
  );

  // WHY: A staff reply means the request is actively being worked, so keep the first-attended marker filled in.
  request.attendedAt = request.attendedAt || new Date();
  request.aiControlEnabled = false;
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffPostRequestMessage',
    intent: 'Confirm the staff reply was appended to the assigned request thread',
  });

  return {
    message: 'Reply sent successfully',
    request: serializeServiceRequest(request),
  };
}

async function suggestAssignedRequestReply(
  staffUserId,
  requestId,
  draft,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffSuggestRequestReply',
    intent: 'Generate a professional staff reply suggestion from the assigned request thread context',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffSuggestRequestReply',
    intent: 'Load the staff account and assigned request before generating the request reply suggestion',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  const request = staff
    ? await loadStaffVisibleRequest(requestId, staff)
    : null;

  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_REPLY_SUGGEST_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!request) {
    throw new AppError({
      message: 'Assigned request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_REPLY_SUGGEST_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const suggestion = await suggestRequestThreadReply({
    request,
    viewerRole: USER_ROLES.STAFF,
    senderName: `${staff.firstName} ${staff.lastName}`.trim(),
    draft,
    logContext,
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffSuggestRequestReply',
    intent: 'Confirm the staff request reply suggestion is ready for the composer',
  });

  return {
    message: 'Staff reply suggestion generated successfully',
    assistant: {
      name: REQUEST_REPLY_ASSISTANT_NAME,
      suggestion,
    },
  };
}

async function uploadAssignedRequestAttachment(
  staffUserId,
  requestId,
  file,
  caption,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffUploadRequestAttachment',
    intent: 'Append a staff attachment onto an assigned customer thread',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffUploadRequestAttachment',
    intent: 'Load the staff account and assigned request before uploading an attachment reply',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  const request = staff
    ? await loadStaffVisibleRequest(requestId, staff)
    : null;

  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_ATTACHMENT_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!request) {
    throw new AppError({
      message: 'Assigned request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_ATTACHMENT_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot accept new chat attachments',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_ATTACHMENT_REQUEST_CLOSED',
      resolutionHint: 'Open another active request thread instead',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (!file) {
    throw new AppError({
      message: 'Attachment file is required',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.MISSING_REQUIRED_FIELD,
      errorCode: 'STAFF_ATTACHMENT_FILE_REQUIRED',
      resolutionHint: 'Choose a file and try again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  const trimmedCaption = typeof caption === 'string' ? caption.trim() : '';
  const storedAttachment = await storeRequestAttachmentFile(file, logContext);
  request.messages.push(
    buildStaffMessage({
      staffId: staffUserId,
      staffName: `${staff.firstName} ${staff.lastName}`.trim(),
      actionPayload: buildAttachmentActionPayload({
        attachmentCategory: resolveWorkflowAttachmentCategory(request),
        mimeType: storedAttachment.mimeType,
      }),
      text:
        trimmedCaption.length === 0
          ? `Shared a file: ${storedAttachment.originalName || 'attachment'}`
          : trimmedCaption,
      attachment: buildRequestMessageAttachment(storedAttachment),
    }),
  );
  request.attendedAt = request.attendedAt || new Date();
  request.aiControlEnabled = false;
  refreshRequestMediaSummary(request);
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffUploadRequestAttachment',
    intent: 'Confirm the staff attachment was appended to the assigned request thread',
  });

  return {
    message: 'Attachment sent successfully',
    request: serializeServiceRequest(request),
  };
}

async function submitAssignedRequestEstimation(
  staffUserId,
  requestId,
  payload,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffSubmitAssignedRequestEstimation',
    intent: 'Let assigned staff submit planned dates and cost for quotation review',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffSubmitAssignedRequestEstimation',
    intent: 'Load the staff account and assigned request before storing the estimate',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  const request = staff
    ? await loadStaffVisibleRequest(requestId, staff)
    : null;

  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_ESTIMATION_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!request) {
    throw new AppError({
      message: 'Assigned request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_ESTIMATION_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot receive new estimations',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_ESTIMATION_REQUEST_CLOSED',
      resolutionHint: 'Open an active request before submitting an estimate',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (
    request.status === REQUEST_STATUSES.QUOTED ||
    request.status === REQUEST_STATUSES.APPOINTMENT_CONFIRMED ||
    request.status === REQUEST_STATUSES.PENDING_START ||
    request.status === REQUEST_STATUSES.PROJECT_STARTED ||
    request.status === REQUEST_STATUSES.WORK_DONE
  ) {
    throw new AppError({
      message: 'Estimation is locked after customer care sends the quotation',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_ESTIMATION_LOCKED_AFTER_QUOTED',
      resolutionHint:
        'Update the estimate before customer care marks the request quoted',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const submitterStaffType = resolveStaffOperationalType(staff);
  if (submitterStaffType === STAFF_TYPES.CUSTOMER_CARE) {
    throw new AppError({
      message: 'Customer care cannot submit estimations',
      statusCode: 403,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_ESTIMATION_ROLE_FORBIDDEN',
      resolutionHint:
        'Use a technician or contractor account to submit the planned dates and cost',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const requestedAssessmentType =
    payload.assessmentType ||
    request.assessmentType ||
    REQUEST_ASSESSMENT_TYPES.REMOTE_REVIEW;
  const requestedAssessmentStatus =
    payload.assessmentStatus ||
    request.assessmentStatus ||
    REQUEST_ASSESSMENT_STATUSES.AWAITING_REVIEW;
  const requestedStage = resolveEstimationStage(payload.stage);
  const assessmentType = requestedAssessmentType;

  if (!Object.values(REQUEST_ASSESSMENT_TYPES).includes(assessmentType)) {
    throw new AppError({
      message: 'Assessment type is invalid',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_ESTIMATION_ASSESSMENT_TYPE_INVALID',
      resolutionHint: 'Choose remote review or site review required',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  if (
    !Object.values(REQUEST_ASSESSMENT_STATUSES).includes(
      requestedAssessmentStatus,
    )
  ) {
    throw new AppError({
      message: 'Assessment status is invalid',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_ESTIMATION_ASSESSMENT_STATUS_INVALID',
      resolutionHint: 'Choose a valid assessment status and try again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  const existingEstimation = Array.isArray(request.estimations)
    ? request.estimations.find((estimation) => {
        return (
          String(estimation?.submittedBy?._id || estimation?.submittedBy || '') ===
          String(staff._id)
        );
      })
    : null;
  // WHY: The booking confirmation message should fire only when the persisted review booking is newly created or meaningfully changed.
  const previousSiteReviewBooking = existingEstimation
    ? {
        siteReviewDate: normalizeDateValue(existingEstimation.siteReviewDate),
        siteReviewStartTime: String(existingEstimation.siteReviewStartTime || '').trim(),
        siteReviewEndTime: String(existingEstimation.siteReviewEndTime || '').trim(),
        siteReviewCost:
          typeof existingEstimation.siteReviewCost === 'number'
            ? existingEstimation.siteReviewCost
            : Number(existingEstimation.siteReviewCost),
      }
    : null;
  const hadReadySiteReviewBooking = isSiteReviewBookingReady(previousSiteReviewBooking);

  const siteReviewDate =
    normalizeDateValue(payload.siteReviewDate) ||
    normalizeDateValue(existingEstimation?.siteReviewDate);
  const siteReviewStartTime =
    typeof payload.siteReviewStartTime === 'string'
      ? payload.siteReviewStartTime.trim()
      : existingEstimation?.siteReviewStartTime || '';
  const siteReviewEndTime =
    typeof payload.siteReviewEndTime === 'string'
      ? payload.siteReviewEndTime.trim()
      : existingEstimation?.siteReviewEndTime || '';
  const parsedSiteReviewCost =
    payload.siteReviewCost === null || payload.siteReviewCost === undefined
      ? Number(existingEstimation?.siteReviewCost)
      : Number(payload.siteReviewCost);
  const siteReviewCost =
    Number.isFinite(parsedSiteReviewCost) && parsedSiteReviewCost > 0
      ? Number(parsedSiteReviewCost.toFixed(2))
      : null;
  const siteReviewNotes =
    typeof payload.siteReviewNotes === 'string'
      ? payload.siteReviewNotes.trim()
      : existingEstimation?.siteReviewNotes || '';

  if (
    siteReviewDate &&
    siteReviewStartTime &&
    siteReviewEndTime &&
    siteReviewEndTime <= siteReviewStartTime
  ) {
    throw new AppError({
      message: 'Site review end time must be after the site review start time',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_SITE_REVIEW_TIME_RANGE_INVALID',
      resolutionHint: 'Choose a valid site review time window and try again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  const estimatedStartDate = normalizeDateValue(payload.estimatedStartDate);
  const estimatedEndDate = normalizeDateValue(payload.estimatedEndDate);
  if (
    estimatedStartDate &&
    estimatedEndDate &&
    estimatedEndDate < estimatedStartDate
  ) {
    throw new AppError({
      message: 'Estimated end date must be on or after the estimated start date',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_ESTIMATION_DATE_RANGE_INVALID',
      resolutionHint: 'Choose a valid planned window and try again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  const parsedEstimatedDays =
    typeof payload.estimatedDays === 'number'
      ? payload.estimatedDays
      : Number(payload.estimatedDays);
  const estimatedDays =
    Number.isInteger(parsedEstimatedDays) && parsedEstimatedDays > 0
      ? parsedEstimatedDays
      : calculateEstimatedDays(estimatedStartDate, estimatedEndDate);

  const parsedEstimatedHoursPerDay =
    typeof payload.estimatedHoursPerDay === 'number'
      ? payload.estimatedHoursPerDay
      : Number(payload.estimatedHoursPerDay);
  const estimatedHoursPerDay =
    Number.isFinite(parsedEstimatedHoursPerDay) &&
    parsedEstimatedHoursPerDay > 0 &&
    parsedEstimatedHoursPerDay <= 10
      ? Number(parsedEstimatedHoursPerDay.toFixed(2))
      : null;

  const estimatedDailySchedule = normalizeEstimatedDailySchedule(
    payload.estimatedDailySchedule,
  );
  const estimatedHoursFromDailySchedule =
    calculateEstimatedHoursFromDailySchedule(estimatedDailySchedule);
  const parsedEstimatedHours =
    typeof payload.estimatedHours === 'number'
      ? payload.estimatedHours
      : Number(payload.estimatedHours);
  const estimatedHours =
    Number.isFinite(parsedEstimatedHours) && parsedEstimatedHours > 0
      ? Number(parsedEstimatedHours.toFixed(2))
      : estimatedHoursFromDailySchedule
        ? estimatedHoursFromDailySchedule
        : estimatedDays && estimatedHoursPerDay
          ? Number((estimatedDays * estimatedHoursPerDay).toFixed(2))
          : null;
  const parsedCost = Number(payload.cost);
  const cost =
    Number.isFinite(parsedCost) && parsedCost > 0
      ? Number(parsedCost.toFixed(2))
      : null;
  const hasFinalEstimatePayload = Boolean(
    estimatedStartDate ||
      estimatedEndDate ||
      estimatedHoursPerDay ||
      estimatedHours ||
      estimatedDays ||
      estimatedDailySchedule.length > 0 ||
      cost,
  );
  const hasCompleteSiteReviewBookingPayload = Boolean(
    siteReviewDate &&
      siteReviewStartTime &&
      siteReviewEndTime &&
      siteReviewCost,
  );
  // WHY: Booking mode should not depend on the client sending a perfectly synchronized status field.
  const isSchedulingSiteReview =
    assessmentType === REQUEST_ASSESSMENT_TYPES.SITE_REVIEW_REQUIRED &&
    (
      requestedAssessmentStatus ===
        REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_SCHEDULED ||
      (
        requestedAssessmentStatus !==
          REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_COMPLETED &&
        hasCompleteSiteReviewBookingPayload &&
        !hasFinalEstimatePayload
      )
    );
  const assessmentStatus = isSchedulingSiteReview
    ? REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_SCHEDULED
    : requestedAssessmentStatus;
  // WHY: A site-review booking should always persist as a draft workflow step, even if stale final-stage state leaks in.
  const stage = isSchedulingSiteReview
    ? REQUEST_ESTIMATION_STAGES.DRAFT
    : requestedStage;
  const isSiteReviewPending = isSiteReviewStillPending(
    assessmentType,
    assessmentStatus,
  );

  if (hasActiveSiteReviewInvoice(request) && isSiteReviewPending) {
    throw new AppError({
      message:
        'Site review booking is locked until the booked review has been completed',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_SITE_REVIEW_LOCKED_UNTIL_COMPLETED',
      resolutionHint:
        'Complete the site review first, then return here to set the final job estimate',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (
    !isSchedulingSiteReview &&
    isSiteReviewPending &&
    stage === REQUEST_ESTIMATION_STAGES.FINAL
  ) {
    throw new AppError({
      message:
        'Final job pricing unlocks only after the site review has been completed',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_FINAL_ESTIMATE_LOCKED_UNTIL_SITE_REVIEW_DONE',
      resolutionHint:
        'Save the site review booking first, then switch to final after the review is completed',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (!isSchedulingSiteReview && isSiteReviewPending && hasFinalEstimatePayload) {
    throw new AppError({
      message:
        'Job estimate dates, daily work plan, and final cost stay locked until the site review is completed',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_FINAL_PRICING_LOCKED_DURING_SITE_REVIEW',
      resolutionHint:
        'Book the site review now, then return after the visit to add the final work estimate',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (
    assessmentStatus === REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_SCHEDULED &&
    !(siteReviewDate && siteReviewStartTime && siteReviewEndTime)
  ) {
    throw new AppError({
      message:
        'A site review date and time are required before the visit can be marked scheduled',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.MISSING_REQUIRED_FIELD,
      errorCode: 'STAFF_SITE_REVIEW_BOOKING_FIELDS_REQUIRED',
      resolutionHint: 'Add the review date and time, then save again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  const estimationPayload = {
    submittedBy: staff._id,
    submitterRole: USER_ROLES.STAFF,
    submitterStaffType,
    assignmentType: resolveEstimationAssignmentType(staff),
    stage,
    estimatedStartDate: isSiteReviewPending ? null : estimatedStartDate || null,
    estimatedEndDate: isSiteReviewPending ? null : estimatedEndDate || null,
    estimatedHours: isSiteReviewPending ? null : estimatedHours,
    estimatedHoursPerDay: isSiteReviewPending ? null : estimatedHoursPerDay,
    estimatedDays: isSiteReviewPending ? null : estimatedDays,
    estimatedDailySchedule: isSiteReviewPending ? [] : estimatedDailySchedule,
    cost: isSiteReviewPending ? null : cost,
    siteReviewDate: siteReviewDate || null,
    siteReviewStartTime,
    siteReviewEndTime,
    siteReviewNotes,
    siteReviewCost,
    note: (payload.note || '').trim(),
    inspectionNote: (payload.inspectionNote || '').trim(),
    submittedAt: new Date(),
  };

  if (existingEstimation) {
    Object.assign(existingEstimation, estimationPayload);
  } else {
    request.estimations.push(estimationPayload);
  }

  const savedEstimation = existingEstimation || request.estimations.at(-1);
  const eventEstimation = {
    ...(savedEstimation?.toObject?.() || savedEstimation || {}),
    submittedBy: {
      firstName: staff.firstName,
      lastName: staff.lastName,
      fullName: `${staff.firstName} ${staff.lastName}`.trim(),
    },
    submitterStaffType,
    stage,
    siteReviewDate,
    siteReviewStartTime,
    siteReviewEndTime,
    siteReviewNotes,
    siteReviewCost,
  };
  const estimationUpdatedAt = estimationPayload.submittedAt;
  const hadInternalReview = Boolean(
    request.quoteReview || request.internalReviewUpdatedAt,
  );
  const isCompleteFinalEstimate = isCompleteFinalRequestEstimation({
    ...(savedEstimation?.toObject?.() || savedEstimation || {}),
    stage,
  });
  const isSiteReviewReady = isSiteReviewBookingReady({
    ...(savedEstimation?.toObject?.() || savedEstimation || {}),
    stage,
    siteReviewDate,
    siteReviewStartTime,
    siteReviewEndTime,
    siteReviewCost,
  });
  const didSiteReviewBookingChange =
    !hadReadySiteReviewBooking ||
    previousSiteReviewBooking?.siteReviewDate?.getTime?.() !== siteReviewDate?.getTime?.() ||
    previousSiteReviewBooking?.siteReviewStartTime !== siteReviewStartTime ||
    previousSiteReviewBooking?.siteReviewEndTime !== siteReviewEndTime ||
    Number(previousSiteReviewBooking?.siteReviewCost || 0) !== Number(siteReviewCost || 0);

  request.attendedAt = request.attendedAt || new Date();
  request.assessmentType = assessmentType;
  request.assessmentStatus = assessmentStatus;
  request.latestEstimateUpdatedAt = estimationUpdatedAt;
  request.quoteReadyAt = null;

  if (hadInternalReview) {
    request.quoteReview = null;
    request.internalReviewUpdatedAt = null;
    const invalidatedEvent = buildQuoteInvalidatedWorkflowEvent();
    request.messages.push(
      buildSystemMessage(invalidatedEvent.text, {
        actionType: invalidatedEvent.actionType,
        actionPayload: invalidatedEvent.actionPayload,
      }),
    );
  }

  request.quoteReadinessStatus = isSiteReviewPending
    ? isSiteReviewReady
      ? REQUEST_QUOTE_READINESS_STATUSES.SITE_REVIEW_READY_FOR_INTERNAL_REVIEW
      : REQUEST_QUOTE_READINESS_STATUSES.AWAITING_ESTIMATE
    : isCompleteFinalEstimate
      ? REQUEST_QUOTE_READINESS_STATUSES.QUOTE_READY_FOR_INTERNAL_REVIEW
      : REQUEST_QUOTE_READINESS_STATUSES.AWAITING_ESTIMATE;
  if (
    request.status === REQUEST_STATUSES.SUBMITTED ||
    request.status === REQUEST_STATUSES.ASSIGNED
  ) {
    request.status = REQUEST_STATUSES.UNDER_REVIEW;
  }

  const estimateUpdatedEvent = buildEstimateUpdatedWorkflowEvent({
    request,
    estimation: eventEstimation,
  });
  request.messages.push(
    buildSystemMessage(estimateUpdatedEvent.text, {
      actionType: estimateUpdatedEvent.actionType,
      actionPayload: estimateUpdatedEvent.actionPayload,
    }),
  );

  if (isSiteReviewPending && isSiteReviewReady) {
    if (didSiteReviewBookingChange && siteReviewDate) {
      request.messages.push(
        buildSystemMessage(
          `Review booked for ${formatThreadDate(siteReviewDate)}. Review charge pending.`,
          {
            actionType: REQUEST_MESSAGE_ACTIONS.SITE_REVIEW_BOOKED,
            actionPayload: {
              // WHY: Thread consumers can reuse the structured payload later without parsing the message body text.
              title: 'Review booked',
              summary: 'Review charge pending.',
              siteReviewDate: formatThreadDate(siteReviewDate),
              siteReviewStartTime,
              siteReviewEndTime,
              siteReviewCost,
            },
          },
        ),
      );
    }

    const readyForReviewEvent =
      buildSiteReviewReadyForInternalReviewWorkflowEvent({
        estimation: eventEstimation,
      });
    request.messages.push(
      buildSystemMessage(readyForReviewEvent.text, {
        actionType: readyForReviewEvent.actionType,
        actionPayload: readyForReviewEvent.actionPayload,
      }),
    );
  } else if (isCompleteFinalEstimate) {
    const readyForReviewEvent = buildQuoteReadyForInternalReviewWorkflowEvent({
      estimation: eventEstimation,
    });
    request.messages.push(
      buildSystemMessage(readyForReviewEvent.text, {
        actionType: readyForReviewEvent.actionType,
        actionPayload: readyForReviewEvent.actionPayload,
      }),
    );
  }

  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffSubmitAssignedRequestEstimation',
    intent: 'Confirm the estimation is saved for front-office quotation review',
  });

  return {
    message: existingEstimation
      ? 'Estimation updated successfully'
      : 'Estimation submitted successfully',
    request: serializeServiceRequest(request),
  };
}

async function updateAssignedRequestAiControl(
  staffUserId,
  requestId,
  enabled,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffUpdateRequestAiControl',
    intent: 'Let assigned staff hand the chat to Naima temporarily without losing ownership of the request',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffUpdateRequestAiControl',
    intent: 'Load the staff account and assigned request before changing who is covering the live chat',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  const request = staff
    ? await loadStaffVisibleRequest(requestId, staff)
    : null;

  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_AI_CONTROL_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!request) {
    throw new AppError({
      message: 'Assigned request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_AI_CONTROL_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot change AI coverage',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_AI_CONTROL_REQUEST_CLOSED',
      resolutionHint: 'Open another active request thread instead',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const staffName = `${staff.firstName} ${staff.lastName}`.trim();
  request.aiControlEnabled = enabled;

  if (enabled) {
    const companyProfile = await loadQueueCompanyProfile();
    request.messages.push(
      buildSystemMessage(`${staffName} handed the chat back to Naima for interim cover.`),
    );
    request.messages.push(
      buildAiMessage(
        buildAiControlEnabledText({
          request,
          companyProfile,
        }),
      ),
    );
  } else {
    request.messages.push(
      buildSystemMessage(
        staff.staffAvailability === STAFF_AVAILABILITIES.ONLINE
          ? `${staffName} resumed direct chat control here.`
          : `${staffName} cleared the manual Naima cover. Naima will still stay active while staff is offline.`,
      ),
    );
  }

  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffUpdateRequestAiControl',
    intent: 'Confirm the Naima handoff state was saved on the assigned request',
  });

  return {
    message: enabled
      ? 'Naima is now covering this chat'
      : staff.staffAvailability === STAFF_AVAILABILITIES.ONLINE
      ? 'Direct staff chat resumed'
      : 'Manual Naima cover cleared, but Naima stays active while staff is offline',
    request: serializeServiceRequest(request),
  };
}

async function createAssignedRequestInvoice(staffUserId, requestId, payload, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffCreateRequestInvoice',
    intent: 'Create and send an invoice from the assigned request conversation',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffCreateRequestInvoice',
    intent: 'Load the assigned request and current staff member before creating an invoice',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  const request = staff
    ? await loadStaffVisibleRequest(requestId, staff)
    : null;

  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_INVOICE_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!request) {
    throw new AppError({
      message: 'Visible request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_INVOICE_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!isCustomerCareStaff(staff)) {
    throw new AppError({
      message: 'Only customer care can send the quotation',
      statusCode: 403,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_QUOTATION_SEND_ROLE_FORBIDDEN',
      resolutionHint:
        'Use a customer care account to send the quotation from the request chat page',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot receive quotations',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_QUOTATION_REQUEST_CLOSED',
      resolutionHint: 'Reopen the workflow before sending a quotation',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const reviewKind =
    request.quoteReview?.kind || REQUEST_REVIEW_KINDS.QUOTATION;
  const readyStatusRequired =
    reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
      ? REQUEST_QUOTE_READINESS_STATUSES.SITE_REVIEW_READY_FOR_CUSTOMER_CARE
      : REQUEST_QUOTE_READINESS_STATUSES.QUOTE_READY_FOR_CUSTOMER_CARE;
  const canReplaceApprovedSiteReviewInvoice =
    request.invoice?.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW &&
    request.invoice?.status === PAYMENT_REQUEST_STATUSES.APPROVED &&
    reviewKind === REQUEST_REVIEW_KINDS.QUOTATION;

  if (
    (!canReplaceApprovedSiteReviewInvoice && request.invoice) ||
    request.status === REQUEST_STATUSES.QUOTED ||
    request.status === REQUEST_STATUSES.APPOINTMENT_CONFIRMED ||
    request.status === REQUEST_STATUSES.PENDING_START ||
    request.status === REQUEST_STATUSES.PROJECT_STARTED ||
    request.status === REQUEST_STATUSES.WORK_DONE
  ) {
    throw new AppError({
      message:
        reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
          ? 'A site review booking has already been sent for this request'
          : 'Quotation has already been sent for this request',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode:
        reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
          ? 'STAFF_SITE_REVIEW_ALREADY_SENT'
          : 'STAFF_QUOTATION_ALREADY_SENT',
      resolutionHint: 'Open the existing quotation instead of sending a new one',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const quoteEstimation =
    reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
      ? getSelectedReadySiteReviewEstimation(request)
      : getSelectedRequestEstimation(request);
  if (
    reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW &&
    !quoteEstimation
  ) {
    throw new AppError({
      message:
        'A booked and priced site review is required before customer care can send the review invoice',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_SITE_REVIEW_BOOKING_REQUIRED',
      resolutionHint:
        'Wait for a technician or contractor to book the review before customer care sends it',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (
    reviewKind !== REQUEST_REVIEW_KINDS.SITE_REVIEW &&
    (!quoteEstimation || !isCompleteFinalRequestEstimation(quoteEstimation))
  ) {
    throw new AppError({
      message: 'A final complete estimate is required before sending quotation',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_QUOTATION_FINAL_ESTIMATE_REQUIRED',
      resolutionHint:
        'Wait for a technician or contractor to finish the estimate before customer care sends the quotation',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (!request.quoteReview || !isQuoteReviewReady(request.quoteReview)) {
    throw new AppError({
      message: 'Internal review must be completed before sending quotation',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_QUOTATION_INTERNAL_REVIEW_REQUIRED',
      resolutionHint:
        'Ask admin to finish internal review before customer care sends the quotation',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (
    !request.internalReviewUpdatedAt ||
    !request.latestEstimateUpdatedAt ||
    request.internalReviewUpdatedAt < request.latestEstimateUpdatedAt ||
    request.quoteReadinessStatus !== readyStatusRequired
  ) {
    throw new AppError({
      message:
        reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
          ? 'Site review booking changed, review required again'
          : 'Estimate changed, review required again',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode:
        reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
          ? 'STAFF_SITE_REVIEW_REVIEW_STALE'
          : 'STAFF_QUOTATION_REVIEW_STALE',
      resolutionHint:
        'Ask admin to refresh internal review before customer care sends the quotation',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  request.invoice = createInvoiceRecord({
    requestId: request._id || request.id || requestId,
    kind: reviewKind,
    quotedBaseAmount: request.quoteReview.quotedBaseAmount,
    adminServiceChargePercent: request.quoteReview.adminServiceChargePercent,
    dueDate: request.quoteReview.dueDate || null,
    siteReviewDate: request.quoteReview.siteReviewDate || null,
    siteReviewStartTime: request.quoteReview.siteReviewStartTime || '',
    siteReviewEndTime: request.quoteReview.siteReviewEndTime || '',
    siteReviewNotes: request.quoteReview.siteReviewNotes || '',
    plannedStartDate: request.quoteReview.plannedStartDate || null,
    plannedStartTime: request.quoteReview.plannedStartTime || '',
    plannedEndTime: request.quoteReview.plannedEndTime || '',
    plannedHoursPerDay:
      typeof request.quoteReview.plannedHoursPerDay === 'number'
        ? request.quoteReview.plannedHoursPerDay
        : null,
    plannedExpectedEndDate:
      request.quoteReview.plannedExpectedEndDate || null,
    plannedDailySchedule: Array.isArray(request.quoteReview.plannedDailySchedule)
      ? request.quoteReview.plannedDailySchedule
      : [],
    paymentMethod: request.quoteReview.paymentMethod,
    paymentInstructions: request.quoteReview.paymentInstructions,
    note: request.quoteReview.note,
    actorUserId: staffUserId,
    actorRole: USER_ROLES.STAFF,
  });

  const paymentSession = await createHostedPaymentSession({
    invoice: request.invoice,
    request,
  });
  if (paymentSession) {
    Object.assign(request.invoice, paymentSession);
  }

  if (reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW) {
    request.quoteReadinessStatus =
      REQUEST_QUOTE_READINESS_STATUSES.AWAITING_ESTIMATE;
    request.quoteReadyAt = null;
    if (
      request.status === REQUEST_STATUSES.SUBMITTED ||
      request.status === REQUEST_STATUSES.ASSIGNED
    ) {
      request.status = REQUEST_STATUSES.UNDER_REVIEW;
    }
  } else {
    request.status = REQUEST_STATUSES.QUOTED;
    request.quoteReadinessStatus = REQUEST_QUOTE_READINESS_STATUSES.QUOTED;
    request.quoteReadyAt = request.invoice.sentAt || new Date();
  }
  request.messages.push(
    buildStaffMessage({
      staffId: staffUserId,
      staffName: `${staff.firstName} ${staff.lastName}`.trim(),
      actionType: invoiceNeedsCustomerProof(request.invoice)
        ? REQUEST_MESSAGE_ACTIONS.CUSTOMER_UPLOAD_PAYMENT_PROOF
        : null,
      text: buildInvoiceRequestMessage(request.invoice),
    }),
  );

  const quotationSentEvent = buildQuotationSentWorkflowEvent({
    invoice: request.invoice,
    estimation: quoteEstimation,
    senderName: `${staff.firstName} ${staff.lastName}`.trim(),
  });
  request.messages.push(
    buildSystemMessage(quotationSentEvent.text, {
      actionType: quotationSentEvent.actionType,
      actionPayload: quotationSentEvent.actionPayload,
    }),
  );

  await request.save();

  return {
    message:
      reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
        ? 'Site review booking sent successfully'
        : 'Quotation sent successfully',
    request: serializeServiceRequest(request),
  };
}

async function reviewAssignedRequestPaymentProof(
  staffUserId,
  requestId,
  decision,
  reviewNote,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffReviewPaymentProof',
    intent: 'Approve or reject a customer payment proof for an assigned request',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffReviewPaymentProof',
    intent: 'Load the assigned request before changing invoice proof status',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  const request = staff
    ? await loadStaffVisibleRequest(requestId, staff)
    : null;

  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_REVIEW_PAYMENT_PROOF_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!request) {
    throw new AppError({
      message: 'Assigned request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_REVIEW_PAYMENT_PROOF_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!request.invoice) {
    throw new AppError({
      message: 'No invoice exists on this request yet',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_REVIEW_PAYMENT_PROOF_INVOICE_MISSING',
      resolutionHint: 'Send an invoice before reviewing payment proof',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (request.invoice.status !== PAYMENT_REQUEST_STATUSES.PROOF_SUBMITTED) {
    throw new AppError({
      message: 'There is no payment proof waiting for review on this request',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_REVIEW_PAYMENT_PROOF_STATUS_INVALID',
      resolutionHint: 'Refresh the request and check the latest invoice status',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  applyInvoiceReview(request.invoice, {
    decision,
    actorUserId: staffUserId,
    actorRole: USER_ROLES.STAFF,
    reviewNote,
  });
  request.messages.push(
    buildSystemMessage(buildProofReviewMessage(request.invoice, decision)),
  );
  if (decision === 'approved') {
    await finalizeApprovedInvoice(request);
  }
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffReviewPaymentProof',
    intent: 'Confirm the invoice proof review decision was saved for the assigned request',
  });

  return {
    message: decision === 'approved'
      ? 'Payment proof approved'
      : 'Payment proof rejected',
    request: serializeServiceRequest(request),
  };
}

async function unlockAssignedRequestInvoiceProofUpload(
  staffUserId,
  requestId,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffUnlockInvoiceProofUpload',
    intent:
      'Allow customer care to reopen payment-proof upload on the active request invoice',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffUnlockInvoiceProofUpload',
    intent: 'Load the request invoice before reopening proof upload',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  const request = staff
    ? await loadStaffVisibleRequest(requestId, staff)
    : null;

  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_UNLOCK_PROOF_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!isCustomerCareStaff(staff)) {
    throw new AppError({
      message: 'Only customer care can unlock proof upload',
      statusCode: 403,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_UNLOCK_PROOF_ROLE_FORBIDDEN',
      resolutionHint:
        'Use a customer care account to reopen the payment-proof window',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (!request) {
    throw new AppError({
      message: 'Visible request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_UNLOCK_PROOF_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!request.invoice || !invoiceNeedsCustomerProof(request.invoice)) {
    throw new AppError({
      message: 'There is no proof-based invoice on this request',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_UNLOCK_PROOF_INVOICE_INVALID',
      resolutionHint:
        'Send a SEPA invoice first before reopening proof upload',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (request.invoice.proof || request.invoice.paidAt) {
    throw new AppError({
      message: 'Proof upload is already complete for this invoice',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_UNLOCK_PROOF_ALREADY_COMPLETE',
      resolutionHint:
        'Use proof review or payment status actions instead of reopening upload',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (!isInvoiceProofUploadLocked(request.invoice)) {
    throw new AppError({
      message: 'Proof upload is not locked on this invoice',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_UNLOCK_PROOF_NOT_LOCKED',
      resolutionHint:
        'Wait until the proof window has expired before reopening it',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  unlockInvoiceProofUpload(request.invoice, {
    actorUserId: staffUserId,
    actorRole: USER_ROLES.STAFF,
  });
  request.messages.push(
    buildSystemMessage('Customer care reopened payment proof upload for this request.', {
      actionType: REQUEST_MESSAGE_ACTIONS.PAYMENT_PROOF_UPLOAD_UNLOCKED,
      actionPayload: {
        title: 'Payment proof upload reopened',
        summary:
          'Customer care reopened the proof upload window for the customer.',
        invoiceNumber: request.invoice.invoiceNumber || '',
        invoiceKind: request.invoice.kind || REQUEST_REVIEW_KINDS.QUOTATION,
      },
    }),
  );
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffUnlockInvoiceProofUpload',
    intent: 'Confirm the proof upload window was reopened',
  });

  return {
    message: 'Payment proof upload unlocked',
    request: serializeServiceRequest(request),
  };
}

async function updateAssignedRequestStatus(staffUserId, requestId, status, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'StaffUpdateRequestStatus',
    intent: 'Allow assigned staff to move their request through the next approved workflow state',
  });

  // WHY: Keep staff transitions inside a controlled subset so only approved workflow moves are allowed.
  if (!STAFF_MANAGEABLE_STATUSES.includes(status)) {
    throw new AppError({
      message: 'This status cannot be set by staff',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_UPDATE_STATUS_NOT_ALLOWED',
      resolutionHint: 'Use one of the allowed workflow statuses for staff',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffUpdateRequestStatus',
    intent: 'Load the request and confirm it belongs to the authenticated staff user',
  });

  const staff = await loadActiveStaffUser(staffUserId);
  if (!staff) {
    throw new AppError({
      message: 'Staff account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_UPDATE_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (resolveStaffOperationalType(staff) === STAFF_TYPES.CUSTOMER_CARE) {
    throw new AppError({
      message: 'Customer care cannot update execution statuses',
      statusCode: 403,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'STAFF_UPDATE_STATUS_CUSTOMER_CARE_FORBIDDEN',
      resolutionHint: 'Use a technician or contractor account to update on-site job progress',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const request = await loadStaffVisibleRequest(requestId, staff);

  if (!request) {
    throw new AppError({
      message: 'Assigned request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_UPDATE_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  request.status = status;
  request.attendedAt = request.attendedAt || new Date();
  if (status === REQUEST_STATUSES.PROJECT_STARTED) {
    request.projectStartedAt = request.projectStartedAt || new Date();
  }
  if (
    status === REQUEST_STATUSES.WORK_DONE ||
    status === REQUEST_STATUSES.CLOSED
  ) {
    request.finishedAt = request.finishedAt || new Date();
  }
  request.closedAt = status === REQUEST_STATUSES.CLOSED ? new Date() : null;
  request.messages.push(
    buildSystemMessage(`Request status changed to ${status.replace(/_/g, ' ')}.`),
  );
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffUpdateRequestStatus',
    intent: 'Confirm the assigned request status change was persisted',
  });

  return {
    message: 'Request status updated successfully',
    request: serializeServiceRequest(request),
  };
}

module.exports = {
  attendQueueRequest,
  clockAssignedRequestWork,
  createAssignedRequestInvoice,
  getDashboard,
  listCalendarRequests,
  listAssignedRequests,
  unlockAssignedRequestInvoiceProofUpload,
  postAssignedRequestMessage,
  suggestAssignedRequestReply,
  submitAssignedRequestEstimation,
  uploadAssignedRequestAttachment,
  registerFromInvite,
  reviewAssignedRequestPaymentProof,
  updateAssignedRequestAiControl,
  updateAssignedRequestStatus,
  updateAvailability,
};
