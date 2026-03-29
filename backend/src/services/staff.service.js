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
  REQUEST_MESSAGE_ACTIONS,
  REQUEST_STATUSES,
  STAFF_AVAILABILITIES,
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
  buildAiMessage,
  buildStaffMessage,
  buildSystemMessage,
} = require('../utils/request-chat');
const { buildAiControlEnabledText } = require('../utils/request-queue-ai');
const {
  applyInvoiceReview,
  buildInvoiceRequestMessage,
  buildProofReviewMessage,
  createInvoiceRecord,
  invoiceNeedsCustomerProof,
} = require('../utils/request-payment');
const {
  finalizeApprovedInvoice,
  syncOnlineInvoicePaymentIfNeeded,
} = require('../utils/request-payment-status');
const { serializeServiceRequest, serializeUser } = require('../utils/serializers');
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

function startOfToday() {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  return date;
}

async function loadQueueCompanyProfile() {
  return CompanyProfile.findOne({ siteKey: 'default' }).lean();
}

async function loadActiveStaffUser(staffUserId) {
  // WHY: Staff-only actions should always resolve identity from MongoDB so queue and reply permissions stay trustworthy.
  return User.findOne({
    _id: staffUserId,
    role: USER_ROLES.STAFF,
    status: USER_STATUSES.ACTIVE,
  });
}

async function loadAssignedRequest(requestId, staffUserId) {
  // WHY: Assignment ownership is enforced at the query layer so staff can never update another teammate's request.
  const request = await ServiceRequest.findOne({
    _id: requestId,
    assignedStaff: staffUserId,
  })
    .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt');

  if (request && await syncOnlineInvoicePaymentIfNeeded(request)) {
    await request.save();
  }

  return request;
}

async function syncRequestCollectionInvoices(requests) {
  await Promise.all(
    requests.map(async (request) => {
      if (await syncOnlineInvoicePaymentIfNeeded(request)) {
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

  const [
    staff,
    waitingQueueCount,
    assignedCount,
    quotedCount,
    confirmedCount,
    pendingStartCount,
    clearedTodayCount,
    queueRequests,
    recentRequests,
  ] = await Promise.all([
    loadActiveStaffUser(staffUserId),
    ServiceRequest.countDocuments({
      status: REQUEST_STATUSES.SUBMITTED,
      assignedStaff: null,
    }),
    ServiceRequest.countDocuments({
      assignedStaff: staffUserId,
      status: { $in: STAFF_OPEN_STATUSES },
    }),
    ServiceRequest.countDocuments({
      assignedStaff: staffUserId,
      status: REQUEST_STATUSES.QUOTED,
    }),
    ServiceRequest.countDocuments({
      assignedStaff: staffUserId,
      status: REQUEST_STATUSES.APPOINTMENT_CONFIRMED,
    }),
    ServiceRequest.countDocuments({
      assignedStaff: staffUserId,
      status: REQUEST_STATUSES.PENDING_START,
    }),
    ServiceRequest.countDocuments({
      assignedStaff: staffUserId,
      status: REQUEST_STATUSES.CLOSED,
      closedAt: { $gte: todayStart },
    }),
    ServiceRequest.find({
      status: REQUEST_STATUSES.SUBMITTED,
      assignedStaff: null,
    })
      .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
      .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
      .sort({ queueEnteredAt: 1, createdAt: 1 })
      .limit(10),
    ServiceRequest.find({ assignedStaff: staffUserId })
      .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
      .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
      .sort({ updatedAt: -1, createdAt: -1 })
      .limit(10),
  ]);

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

  const query = { assignedStaff: staffUserId };

  if (filters.status) {
    // WHY: Let staff narrow their own inbox without ever escaping their assignment scope.
    query.status = filters.status;
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'StaffListRequests',
    intent: 'Load the assigned request rows and their related customer summaries',
  });

  const requests = await ServiceRequest.find(query)
    .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .sort({ updatedAt: -1, createdAt: -1 });

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

  const attendAt = new Date();

  // WHY: Claim the queue atomically so two staff members cannot pick up the same waiting request at the same time.
  let request = await ServiceRequest.findOneAndUpdate(
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
  )
    .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt');

  if (!request) {
    // WHY: Re-read the request when the atomic claim misses so the UI gets a precise reason instead of a silent generic failure.
    request = await ServiceRequest.findById(requestId)
      .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
      .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt');

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

  const [staff, request] = await Promise.all([
    loadActiveStaffUser(staffUserId),
    loadAssignedRequest(requestId, staffUserId),
  ]);

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

  const [staff, request] = await Promise.all([
    loadActiveStaffUser(staffUserId),
    loadAssignedRequest(requestId, staffUserId),
  ]);

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

  const [staff, request] = await Promise.all([
    loadActiveStaffUser(staffUserId),
    loadAssignedRequest(requestId, staffUserId),
  ]);

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
      message: 'Assigned request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_INVOICE_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your dashboard and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot receive new invoices',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'STAFF_INVOICE_REQUEST_CLOSED',
      resolutionHint: 'Reopen the workflow before billing again',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  request.invoice = createInvoiceRecord({
    requestId: request.id,
    amount: payload.amount,
    dueDate: payload.dueDate || null,
    paymentMethod: payload.paymentMethod,
    paymentInstructions: payload.paymentInstructions,
    note: payload.note,
    actorUserId: staffUserId,
    actorRole: USER_ROLES.STAFF,
  });
  const hostedPaymentSession = await createHostedPaymentSession({
    invoice: request.invoice,
    request,
  });
  if (hostedPaymentSession) {
    request.invoice.paymentProvider = hostedPaymentSession.paymentProvider;
    request.invoice.paymentLinkUrl = hostedPaymentSession.paymentLinkUrl;
    request.invoice.providerPaymentId = hostedPaymentSession.providerPaymentId;
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
  request.attendedAt = request.attendedAt || new Date();
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'StaffCreateRequestInvoice',
    intent: 'Confirm the invoice was attached to the assigned request and sent into the chat',
  });

  return {
    message: 'Invoice sent successfully',
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

  const request = await loadAssignedRequest(requestId, staffUserId);

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

  const request = await loadAssignedRequest(requestId, staffUserId);

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
  createAssignedRequestInvoice,
  getDashboard,
  listAssignedRequests,
  postAssignedRequestMessage,
  registerFromInvite,
  reviewAssignedRequestPaymentProof,
  updateAssignedRequestAiControl,
  updateAssignedRequestStatus,
  updateAvailability,
};
