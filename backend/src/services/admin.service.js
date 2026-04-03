/**
 * WHAT: Implements admin dashboard, request management, and invite/staff management flows.
 * WHY: Admin operations need a dedicated service boundary to keep controllers thin and auditable.
 * HOW: Query MongoDB for aggregate summaries, manage invite records, and assign requests to staff.
 */

const { randomUUID } = require('crypto');

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  PAYMENT_REQUEST_STATUSES,
  REQUEST_ASSESSMENT_STATUSES,
  REQUEST_ASSESSMENT_TYPES,
  REQUEST_MESSAGE_ACTIONS,
  REQUEST_QUOTE_READINESS_STATUSES,
  REQUEST_REVIEW_KINDS,
  REQUEST_STATUSES,
  STAFF_AVAILABILITIES,
  STAFF_TYPES,
  USER_ROLES,
  USER_STATUSES,
} = require('../constants/app.constants');
const { env } = require('../config/env');
const { ServiceRequest } = require('../models/service-request.model');
const { StaffInvite } = require('../models/staff-invite.model');
const { User } = require('../models/user.model');
const { AppError } = require('../utils/app-error');
const { logInfo } = require('../utils/logger');
const {
  buildAttachmentActionPayload,
  buildAdminMessage,
  buildRequestMessageAttachment,
  buildSystemMessage,
  resolveWorkflowAttachmentCategory,
} = require('../utils/request-chat');
const {
  applyInvoiceReview,
  buildInvoiceRequestMessage,
  buildProofReviewMessage,
  createQuoteReviewRecord,
  invoiceNeedsCustomerProof,
  isQuoteReviewReady,
} = require('../utils/request-payment');
const {
  buildInternalReviewWorkflowEvent,
  buildQuoteReadyForCustomerCareWorkflowEvent,
  buildSiteReviewReadyForCustomerCareWorkflowEvent,
} = require('../utils/request-quote-workflow');
const {
  finalizeApprovedInvoice,
  syncApprovedInvoiceReceiptIfNeeded,
  syncOnlineInvoicePaymentIfNeeded,
} = require('../utils/request-payment-status');
const {
  getReadySiteReviewEstimations,
  getSelectedRequestEstimation,
  isCompleteRequestEstimation,
  normalizeDateValue,
  requestOverlapsCalendarRange,
} = require('../utils/request-estimation');
const { populateServiceRequestRelations } = require('../utils/request-query');
const { serializeServiceRequest, serializeStaffInvite, serializeUser } = require('../utils/serializers');
const { refreshRequestMediaSummary } = require('../utils/request-media');
const { storeRequestAttachmentFile } = require('./file-storage.service');
const { buildStaffInviteLink } = require('./token.service');

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

function isSiteReviewStillPending(request) {
  return (
    request?.assessmentType === REQUEST_ASSESSMENT_TYPES.SITE_REVIEW_REQUIRED &&
    request?.assessmentStatus !==
      REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_COMPLETED
  );
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

async function getDashboard(logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminGetDashboard',
    intent: 'Provide a compact operational overview for the admin dashboard',
  });

  // WHY: Build totals from the shared enum so dashboard cards stay aligned with the canonical workflow states.
  const statuses = Object.values(REQUEST_STATUSES);
  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminGetDashboard',
    intent: 'Load headline counts and recent request data for admin overview cards',
  });

  const [
    totalRequests,
    statusCounts,
    staffCount,
    pendingInvitesCount,
    waitingQueueCount,
    activeQueueCount,
    clearedTodayCount,
    staffOnlineCount,
    recentRequests,
  ] = await Promise.all([
    ServiceRequest.countDocuments(),
    Promise.all(statuses.map((status) => ServiceRequest.countDocuments({ status }))),
    User.countDocuments({ role: USER_ROLES.STAFF, status: USER_STATUSES.ACTIVE }),
    StaffInvite.countDocuments({
      acceptedAt: null,
      revokedAt: null,
      expiresAt: { $gt: new Date() },
    }),
    ServiceRequest.countDocuments({
      status: REQUEST_STATUSES.SUBMITTED,
      assignedStaff: null,
    }),
    ServiceRequest.countDocuments({
      status: {
        $in: [
          REQUEST_STATUSES.ASSIGNED,
          REQUEST_STATUSES.UNDER_REVIEW,
          REQUEST_STATUSES.QUOTED,
          REQUEST_STATUSES.APPOINTMENT_CONFIRMED,
          REQUEST_STATUSES.PENDING_START,
          REQUEST_STATUSES.PROJECT_STARTED,
          REQUEST_STATUSES.WORK_DONE,
        ],
      },
    }),
    ServiceRequest.countDocuments({
      status: REQUEST_STATUSES.CLOSED,
      closedAt: { $gte: todayStart },
    }),
    User.countDocuments({
      role: USER_ROLES.STAFF,
      status: USER_STATUSES.ACTIVE,
      staffAvailability: STAFF_AVAILABILITIES.ONLINE,
    }),
    populateServiceRequestRelations(
      ServiceRequest.find()
        .sort({ updatedAt: -1, createdAt: -1 })
        .limit(5),
    ),
  ]);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminGetDashboard',
    intent: 'Confirm admin summary data is ready for response shaping',
  });

  await syncRequestCollectionInvoices(recentRequests);

  const countsByStatus = statuses.reduce((accumulator, status, index) => {
    // WHY: Convert the positional count array into a keyed map so the frontend does not rely on ordering.
    accumulator[status] = statusCounts[index];
    return accumulator;
  }, {});

  return {
    message: 'Admin dashboard fetched successfully',
    kpis: {
      totalRequests,
      countsByStatus,
      staffCount,
      staffOnlineCount,
      pendingInvitesCount,
      waitingQueueCount,
      activeQueueCount,
      clearedTodayCount,
    },
    recentRequests: recentRequests.map(serializeServiceRequest),
  };
}

async function listRequests(filters, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminListRequests',
    intent: 'Return request inbox data for admin review and assignment',
  });

  // WHY: Build the query incrementally so each optional filter affects only the intended slice.
  const query = {};

  if (filters.status) {
    query.status = filters.status;
  }

  if (filters.assignedStaffId) {
    query.assignedStaff = filters.assignedStaffId;
  }

  if (filters.search) {
    // WHY: Search across the main contact and location fields admins actually use to find requests quickly.
    const safeRegex = new RegExp(filters.search, 'i');
    query.$or = [
      { 'contactSnapshot.fullName': safeRegex },
      { 'contactSnapshot.email': safeRegex },
      { 'location.addressLine1': safeRegex },
      { 'location.city': safeRegex },
      { 'location.postalCode': safeRegex },
    ];
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminListRequests',
    intent: 'Load request rows with the related customer and assigned staff summaries',
  });

  const requests = await populateServiceRequestRelations(
    ServiceRequest.find(query)
      .sort({ updatedAt: -1, createdAt: -1 })
      .limit(50),
  );

  await syncRequestCollectionInvoices(requests);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminListRequests',
    intent: 'Confirm request inbox data is available for the admin UI',
  });

  return {
    message: 'Requests fetched successfully',
    requests: requests.map(serializeServiceRequest),
  };
}

function parseCalendarDateFilters(filters = {}) {
  const start = normalizeDateValue(filters.start);
  const end = normalizeDateValue(filters.end);

  return {
    start,
    end,
  };
}

async function listCalendarRequests(filters, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminListCalendarRequests',
    intent: 'Return shared calendar jobs with estimation-backed schedule windows for admin planning',
  });

  const { start, end } = parseCalendarDateFilters(filters);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminListCalendarRequests',
    intent: 'Load requests that can appear on the shared admin calendar',
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
    operation: 'AdminListCalendarRequests',
    intent: 'Confirm calendar-ready request data is available for admin scheduling views',
  });

  return {
    message: 'Calendar jobs fetched successfully',
    requests: calendarRequests.map(serializeServiceRequest),
  };
}

async function assignRequest(requestId, staffId, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminAssignRequest',
    intent: 'Assign a customer request to a staff member who can continue the workflow',
  });

  // WHY: Confirm the assignee first so request assignment cannot point to a missing or inactive staff account.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminAssignRequest',
    intent: 'Validate that the selected staff member exists and can receive assignments',
  });

  const staff = await User.findOne({
    _id: staffId,
    role: USER_ROLES.STAFF,
    status: USER_STATUSES.ACTIVE,
  });

  // WHY: Stop before updating the request if the selected staff member is not assignable.
  if (!staff) {
    throw new AppError({
      message: 'Staff member not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_ASSIGN_STAFF_NOT_FOUND',
      resolutionHint: 'Select an active staff account and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (staff.staffType === STAFF_TYPES.CUSTOMER_CARE) {
    throw new AppError({
      message: 'Customer care cannot be assigned as field staff',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_ASSIGN_CUSTOMER_CARE_FORBIDDEN',
      resolutionHint: 'Assign a technician or contractor to handle planning and execution',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  // WHY: Update the assignee and workflow status together so ownership and stage never drift apart.
  const request = await populateServiceRequestRelations(
    ServiceRequest.findByIdAndUpdate(
      requestId,
      {
        assignedStaff: staff._id,
        status: REQUEST_STATUSES.ASSIGNED,
        $push: {
          messages: buildSystemMessage(
            `${staff.firstName} ${staff.lastName}`.trim() +
              ' was assigned to your request and can continue the conversation here.',
          ),
        },
      },
      { new: true },
    ),
  );

  // WHY: Report a missing request after staff validation so the admin gets the most accurate failure reason.
  if (!request) {
    throw new AppError({
      message: 'Service request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_ASSIGN_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh the request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminAssignRequest',
    intent: 'Confirm the service request is now assigned to the selected staff member',
  });

  return {
    message: 'Request assigned successfully',
    request: serializeServiceRequest(request),
  };
}

async function loadAdminVisibleRequest(requestId) {
  return populateServiceRequestRelations(ServiceRequest.findById(requestId));
}

async function postRequestMessage(adminUser, requestId, text, actionType, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminPostRequestMessage',
    intent: 'Append an admin reply onto a customer request thread',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminPostRequestMessage',
    intent: 'Load the request before appending an admin chat reply',
  });

  const request = await loadAdminVisibleRequest(requestId);

  if (!request) {
    throw new AppError({
      message: 'Service request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_MESSAGE_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh the request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot accept new replies',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_MESSAGE_REQUEST_CLOSED',
      resolutionHint: 'Open another active request thread instead',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  request.messages.push(
    buildAdminMessage({
      adminId: adminUser.id,
      adminName: 'Admin Team',
      actionType,
      text,
    }),
  );
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminPostRequestMessage',
    intent: 'Confirm the admin reply was appended to the request thread',
  });

  return {
    message: 'Reply sent successfully',
    request: serializeServiceRequest(request),
  };
}

async function uploadRequestAttachment(adminUser, requestId, file, caption, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminUploadRequestAttachment',
    intent: 'Append an admin attachment onto a request thread',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminUploadRequestAttachment',
    intent: 'Load the request before appending an admin attachment message',
  });

  const request = await loadAdminVisibleRequest(requestId);

  if (!request) {
    throw new AppError({
      message: 'Service request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_ATTACHMENT_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh the request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot accept new chat attachments',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_ATTACHMENT_REQUEST_CLOSED',
      resolutionHint: 'Open another active request thread instead',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (!file) {
    throw new AppError({
      message: 'Attachment file is required',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.MISSING_REQUIRED_FIELD,
      errorCode: 'ADMIN_ATTACHMENT_FILE_REQUIRED',
      resolutionHint: 'Choose a file and try again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  const trimmedCaption = typeof caption === 'string' ? caption.trim() : '';
  const storedAttachment = await storeRequestAttachmentFile(file, logContext);
  request.messages.push(
    buildAdminMessage({
      adminId: adminUser.id,
      adminName: 'Admin Team',
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
  refreshRequestMediaSummary(request);
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminUploadRequestAttachment',
    intent: 'Confirm the admin attachment was appended to the request thread',
  });

  return {
    message: 'Attachment sent successfully',
    request: serializeServiceRequest(request),
  };
}

async function createRequestInvoice(adminUser, requestId, payload, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminCreateRequestInvoice',
    intent: 'Create and send an invoice from the admin request workspace',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminCreateRequestInvoice',
    intent: 'Load the target request before attaching a new invoice',
  });

  const request = await loadAdminVisibleRequest(requestId);

  if (!request) {
    throw new AppError({
      message: 'Service request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_INVOICE_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh the request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot receive internal review updates',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_INTERNAL_REVIEW_REQUEST_CLOSED',
      resolutionHint: 'Continue internal review from an open request only',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const reviewKind = isSiteReviewStillPending(request)
    ? REQUEST_REVIEW_KINDS.SITE_REVIEW
    : REQUEST_REVIEW_KINDS.QUOTATION;
  const hasBlockingInvoice =
    Boolean(request.invoice) &&
    // WHY: The site-review payment invoice should not block the later
    // post-review quotation review once the technician submits a final estimate.
    !(
      request.invoice.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW &&
      reviewKind === REQUEST_REVIEW_KINDS.QUOTATION
    );

  if (
    hasBlockingInvoice ||
    request.status === REQUEST_STATUSES.QUOTED ||
    request.status === REQUEST_STATUSES.APPOINTMENT_CONFIRMED ||
    request.status === REQUEST_STATUSES.PENDING_START ||
    request.status === REQUEST_STATUSES.PROJECT_STARTED ||
    request.status === REQUEST_STATUSES.WORK_DONE
  ) {
    throw new AppError({
      message: 'Internal review is locked after the quotation has been sent',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_INTERNAL_REVIEW_LOCKED_AFTER_QUOTED',
      resolutionHint:
        'Review must be completed before customer care sends the quotation',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }
  const quoteEstimation =
    reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
      ? getSelectedReadySiteReviewEstimation(request)
      : getSelectedRequestEstimation(request);
  if (!quoteEstimation) {
    throw new AppError({
      message:
        reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
          ? 'A booked and priced site review is required before internal review'
          : 'Estimation required from staff or contractor',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode:
        reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
          ? 'ADMIN_SITE_REVIEW_ESTIMATION_REQUIRED'
          : 'ADMIN_INVOICE_ESTIMATION_REQUIRED',
      resolutionHint:
        reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
          ? 'Ask staff to book the site review date, time, and review charge before internal review'
          : 'Ask staff to submit a final complete estimate with dates, hours per day, daily work plan, and cost before internal review',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (
    reviewKind !== REQUEST_REVIEW_KINDS.SITE_REVIEW &&
    !isCompleteRequestEstimation(quoteEstimation)
  ) {
    throw new AppError({
      message: 'A final complete estimate is required before internal review',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_INTERNAL_REVIEW_FINAL_ESTIMATE_REQUIRED',
      resolutionHint:
        'Wait for staff to complete the final estimate before updating internal review',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const selectedSubmitterId =
    quoteEstimation.submittedBy?._id || quoteEstimation.submittedBy || null;
  if (!request.selectedEstimationId && quoteEstimation._id) {
    request.selectedEstimationId = quoteEstimation._id;
  }
  if (selectedSubmitterId) {
    request.assignedStaff = selectedSubmitterId;
  }

  request.quoteReview = createQuoteReviewRecord({
    kind: reviewKind,
    quotedBaseAmount:
      reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
        ? quoteEstimation.siteReviewCost
        : quoteEstimation.cost,
    selectedEstimationId: quoteEstimation._id || quoteEstimation.id || null,
    adminServiceChargePercent: payload.adminServiceChargePercent,
    dueDate: payload.dueDate || null,
    siteReviewDate:
      payload.siteReviewDate || quoteEstimation.siteReviewDate || null,
    siteReviewStartTime:
      payload.siteReviewStartTime || quoteEstimation.siteReviewStartTime || '',
    siteReviewEndTime:
      payload.siteReviewEndTime || quoteEstimation.siteReviewEndTime || '',
    siteReviewNotes:
      payload.siteReviewNotes || quoteEstimation.siteReviewNotes || '',
    plannedStartDate: payload.plannedStartDate || null,
    plannedStartTime: payload.plannedStartTime || '',
    plannedEndTime: payload.plannedEndTime || '',
    plannedHoursPerDay:
      typeof payload.plannedHoursPerDay === 'number'
        ? payload.plannedHoursPerDay
        : null,
    plannedExpectedEndDate: payload.plannedExpectedEndDate || null,
    plannedDailySchedule: Array.isArray(payload.plannedDailySchedule)
      ? payload.plannedDailySchedule
      : [],
    paymentMethod: payload.paymentMethod,
    paymentInstructions: payload.paymentInstructions,
    note: payload.note,
    actorUserId: adminUser.id,
    actorRole: USER_ROLES.ADMIN,
    actorName: 'Admin Team',
  });
  request.internalReviewUpdatedAt = request.quoteReview.reviewedAt;
  request.quoteReadyAt = null;
  request.quoteReadinessStatus =
    reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
      ? REQUEST_QUOTE_READINESS_STATUSES.SITE_REVIEW_READY_FOR_INTERNAL_REVIEW
      : REQUEST_QUOTE_READINESS_STATUSES.QUOTE_READY_FOR_INTERNAL_REVIEW;

  const internalReviewEvent = buildInternalReviewWorkflowEvent({
    review: request.quoteReview,
    estimation: quoteEstimation,
    adminName: 'Admin Team',
  });
  request.messages.push(
    buildSystemMessage(internalReviewEvent.text, {
      actionType: internalReviewEvent.actionType,
      actionPayload: internalReviewEvent.actionPayload,
    }),
  );

  if (isQuoteReviewReady(request.quoteReview)) {
    request.quoteReadinessStatus =
      reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
        ? REQUEST_QUOTE_READINESS_STATUSES.SITE_REVIEW_READY_FOR_CUSTOMER_CARE
        : REQUEST_QUOTE_READINESS_STATUSES.QUOTE_READY_FOR_CUSTOMER_CARE;
    request.quoteReadyAt = new Date();
    const quoteReadyEvent =
      reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
        ? buildSiteReviewReadyForCustomerCareWorkflowEvent({
            review: request.quoteReview,
            estimation: quoteEstimation,
          })
        : buildQuoteReadyForCustomerCareWorkflowEvent({
            review: request.quoteReview,
            estimation: quoteEstimation,
          });
    request.messages.push(
      buildSystemMessage(quoteReadyEvent.text, {
        actionType: quoteReadyEvent.actionType,
        actionPayload: quoteReadyEvent.actionPayload,
      }),
    );
  }

  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminCreateRequestInvoice',
    intent: 'Confirm the internal review was saved and staff chat handoff notifications were appended',
  });

  return {
    message: 'Internal review updated successfully',
    request: serializeServiceRequest(request),
  };
}

async function selectRequestEstimation(adminUser, requestId, estimationId, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminSelectRequestEstimation',
    intent: 'Select the estimate that should drive quotation and calendar assignment',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminSelectRequestEstimation',
    intent: 'Load the request and target estimate before reserving the planned slot',
  });

  const request = await loadAdminVisibleRequest(requestId);
  if (!request) {
    throw new AppError({
      message: 'Service request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_SELECT_ESTIMATION_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh the request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const targetEstimation = (Array.isArray(request.estimations) ? request.estimations : []).find(
    (estimation) => String(estimation?._id || estimation?.id || '') === String(estimationId),
  );
  if (!targetEstimation || !isCompleteRequestEstimation(targetEstimation)) {
    throw new AppError({
      message: 'Estimation required from staff or contractor',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_SELECT_ESTIMATION_INVALID',
      resolutionHint:
        'Choose a complete estimate with start date, end date, and cost before assigning the job',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  request.selectedEstimationId = targetEstimation._id;
  const estimationStaffId =
    targetEstimation.submittedBy?._id || targetEstimation.submittedBy || null;
  const submitterStaffType =
    targetEstimation.submitterStaffType || targetEstimation.submittedBy?.staffType || null;
  const submitterTypeLabel =
    submitterStaffType === 'contractor'
      ? 'contractor'
      : submitterStaffType === 'customer_care'
        ? 'customer care'
        : 'technician';
  if (estimationStaffId) {
    request.assignedStaff = estimationStaffId;
  }
  if (
    request.status === REQUEST_STATUSES.SUBMITTED ||
    request.status === REQUEST_STATUSES.UNDER_REVIEW
  ) {
    request.status = REQUEST_STATUSES.ASSIGNED;
  }
  request.quoteReview = null;
  request.internalReviewUpdatedAt = null;
  request.quoteReadyAt = null;
  request.quoteReadinessStatus =
    REQUEST_QUOTE_READINESS_STATUSES.QUOTE_READY_FOR_INTERNAL_REVIEW;

  const submitterName = targetEstimation.submittedBy?.firstName
    ? `${targetEstimation.submittedBy.firstName} ${targetEstimation.submittedBy.lastName}`.trim()
    : 'the selected staff member';
  request.messages.push(
    buildAdminMessage({
      adminId: adminUser.id,
      adminName: 'Admin Team',
      text:
        `Selected ${submitterTypeLabel} estimation from ${submitterName}. ` +
        `Planned window: ${targetEstimation.estimatedStartDate.toISOString().slice(0, 10)} to ${targetEstimation.estimatedEndDate.toISOString().slice(0, 10)}. ` +
        `Quoted cost basis: EUR ${Number(targetEstimation.cost || 0).toFixed(2)}.`,
    }),
  );
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminSelectRequestEstimation',
    intent: 'Confirm the selected estimate now drives the request assignment and calendar slot',
  });

  return {
    message: 'Estimation selected successfully',
    request: serializeServiceRequest(request),
  };
}

async function reviewPaymentProof(adminUser, requestId, decision, reviewNote, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminReviewPaymentProof',
    intent: 'Approve or reject a customer payment proof from the admin workspace',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminReviewPaymentProof',
    intent: 'Load the request invoice before applying the payment-proof review decision',
  });

  const request = await loadAdminVisibleRequest(requestId);

  if (!request) {
    throw new AppError({
      message: 'Service request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_REVIEW_PAYMENT_PROOF_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh the request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!request.invoice) {
    throw new AppError({
      message: 'No invoice exists on this request yet',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_REVIEW_PAYMENT_PROOF_INVOICE_MISSING',
      resolutionHint: 'Send an invoice before reviewing payment proof',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (request.invoice.status !== PAYMENT_REQUEST_STATUSES.PROOF_SUBMITTED) {
    throw new AppError({
      message: 'There is no payment proof waiting for review on this request',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_REVIEW_PAYMENT_PROOF_STATUS_INVALID',
      resolutionHint: 'Refresh the request and check the latest invoice status',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  applyInvoiceReview(request.invoice, {
    decision,
    actorUserId: adminUser.id,
    actorRole: USER_ROLES.ADMIN,
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
    operation: 'AdminReviewPaymentProof',
    intent: 'Confirm the admin payment-proof review decision was saved',
  });

  return {
    message: decision === 'approved'
      ? 'Payment proof approved'
      : 'Payment proof rejected',
    request: serializeServiceRequest(request),
  };
}

async function listStaff(logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminListStaff',
    intent: 'Return active staff accounts for the admin management panel',
  });

  // WHY: Load identity rows and workload counts separately so the admin can see both people and open assignments.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminListStaff',
    intent: 'Load active staff accounts and their current assignment counts',
  });

  const staffMembers = await User.find({
    role: USER_ROLES.STAFF,
    status: USER_STATUSES.ACTIVE,
  }).sort({ createdAt: -1 });

  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);

  const assignmentCounts = await ServiceRequest.aggregate([
    {
      $match: {
        assignedStaff: { $ne: null },
        // WHY: Admin workload cards should count every still-open staff request, including under-review work in progress.
        status: {
          $in: [
            REQUEST_STATUSES.ASSIGNED,
            REQUEST_STATUSES.UNDER_REVIEW,
            REQUEST_STATUSES.QUOTED,
            REQUEST_STATUSES.APPOINTMENT_CONFIRMED,
            REQUEST_STATUSES.PENDING_START,
            REQUEST_STATUSES.PROJECT_STARTED,
            REQUEST_STATUSES.WORK_DONE,
          ],
        },
      },
    },
    {
      $group: {
        _id: '$assignedStaff',
        count: { $sum: 1 },
      },
    },
  ]);

  const clearedTodayCounts = await ServiceRequest.aggregate([
    {
      $match: {
        assignedStaff: { $ne: null },
        status: REQUEST_STATUSES.CLOSED,
        closedAt: { $gte: todayStart },
      },
    },
    {
      $group: {
        _id: '$assignedStaff',
        count: { $sum: 1 },
      },
    },
  ]);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminListStaff',
    intent: 'Confirm staff management rows are ready for response shaping',
  });

  const countsByStaffId = assignmentCounts.reduce((accumulator, item) => {
    // WHY: Normalize aggregate output into a lookup map before merging counts into serialized staff rows.
    accumulator[String(item._id)] = item.count;
    return accumulator;
  }, {});

  const clearedTodayByStaffId = clearedTodayCounts.reduce((accumulator, item) => {
    // WHY: Merge queue-clearing throughput into each staff row so admins can see who is actively closing work today.
    accumulator[String(item._id)] = item.count;
    return accumulator;
  }, {});

  return {
    message: 'Staff fetched successfully',
    staff: staffMembers.map((staff) => ({
      ...serializeUser(staff),
      assignedOpenRequestCount: countsByStaffId[String(staff._id)] || 0,
      clearedTodayCount: clearedTodayByStaffId[String(staff._id)] || 0,
    })),
  };
}

async function createStaffInvite(payload, adminUser, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminCreateStaffInvite',
    intent: 'Create an invite-only onboarding link for a future staff account',
  });

  // WHY: Block invite creation if a real account already owns the target email address.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminCreateStaffInvite',
    intent: 'Ensure the target email is not already attached to an existing user',
  });

  const existingUser = await User.findOne({ email: payload.email.toLowerCase() });

  if (existingUser) {
    throw new AppError({
      message: 'A user with this email already exists',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_CREATE_INVITE_EMAIL_TAKEN',
      resolutionHint: 'Use a different email address for the invite',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  // WHY: Revoke older open invites for the same email so only the newest onboarding link stays valid.
  await StaffInvite.updateMany(
    {
      email: payload.email.toLowerCase(),
      acceptedAt: null,
      revokedAt: null,
      expiresAt: { $gt: new Date() },
    },
    { revokedAt: new Date() },
  );

  // WHY: Store the invite recipient details now so onboarding stays auditable and prefilled later.
  const invite = await StaffInvite.create({
    inviteId: randomUUID(),
    firstName: payload.firstName,
    lastName: payload.lastName,
    email: payload.email.toLowerCase(),
    phone: payload.phone || '',
    staffType: payload.staffType,
    invitedBy: adminUser.id,
    expiresAt: new Date(Date.now() + env.staffInviteTtlHours * 60 * 60 * 1000),
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminCreateStaffInvite',
    intent: 'Confirm the staff invite record exists before generating the copyable link',
  });

  return {
    message: 'Staff invite created successfully',
    invite: serializeStaffInvite(invite, buildStaffInviteLink(invite)),
  };
}

async function deleteStaffInvite(inviteId, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminDeleteStaffInvite',
    intent: 'Let the admin remove invite links while preserving already-created staff accounts',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminDeleteStaffInvite',
    intent: 'Load the invite record before deciding whether to cancel or delete it',
  });

  const invite = await StaffInvite.findById(inviteId);

  // WHY: Return a precise not-found error so the admin can refresh stale dashboard data cleanly.
  if (!invite) {
    throw new AppError({
      message: 'Staff invite not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'ADMIN_DELETE_INVITE_NOT_FOUND',
      resolutionHint: 'Refresh the invite list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (!invite.acceptedAt) {
    // WHY: Pending invites should be canceled, not destroyed, so the system can still remember they were revoked.
    invite.revokedAt = new Date();
    await invite.save();

    logInfo({
      ...logContext,
      step: LOG_STEPS.DB_QUERY_OK,
      layer: 'service',
      operation: 'AdminDeleteStaffInvite',
      intent: 'Confirm the pending invite was revoked and removed from active invite management',
    });

    return {
      message: 'Pending invite canceled and link removed',
      inviteId,
    };
  }

  // WHY: Once an invite has already produced a staff account, deleting the link record must not interfere with the account itself.
  await StaffInvite.deleteOne({ _id: invite._id });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminDeleteStaffInvite',
    intent: 'Confirm the processed invite link record was removed without affecting the accepted staff account',
  });

  return {
    message: 'Processed invite link removed',
    inviteId,
  };
}

async function listStaffInvites(logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'AdminListStaffInvites',
    intent: 'Return active staff invites so admins can copy or review onboarding links',
  });

  // WHY: Filter out accepted and expired invites so the admin UI only shows usable links.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'AdminListStaffInvites',
    intent: 'Load pending, unexpired staff invites for the admin panel',
  });

  const invites = await StaffInvite.find({
    acceptedAt: null,
    revokedAt: null,
    expiresAt: { $gt: new Date() },
  }).sort({ createdAt: -1 });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminListStaffInvites',
    intent: 'Confirm pending invite data is ready for response shaping',
  });

  return {
    message: 'Staff invites fetched successfully',
    invites: invites.map((invite) => serializeStaffInvite(invite, buildStaffInviteLink(invite))),
  };
}

module.exports = {
  assignRequest,
  selectRequestEstimation,
  createRequestInvoice,
  createStaffInvite,
  deleteStaffInvite,
  getDashboard,
  listCalendarRequests,
  listRequests,
  listStaff,
  listStaffInvites,
  postRequestMessage,
  reviewPaymentProof,
  uploadRequestAttachment,
};
