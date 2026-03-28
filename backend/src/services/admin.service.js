/**
 * WHAT: Implements admin dashboard, request management, and invite/staff management flows.
 * WHY: Admin operations need a dedicated service boundary to keep controllers thin and auditable.
 * HOW: Query MongoDB for aggregate summaries, manage invite records, and assign requests to staff.
 */

const { randomUUID } = require('crypto');

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  REQUEST_STATUSES,
  STAFF_AVAILABILITIES,
  USER_ROLES,
  USER_STATUSES,
} = require('../constants/app.constants');
const { env } = require('../config/env');
const { ServiceRequest } = require('../models/service-request.model');
const { StaffInvite } = require('../models/staff-invite.model');
const { User } = require('../models/user.model');
const { AppError } = require('../utils/app-error');
const { logInfo } = require('../utils/logger');
const { buildSystemMessage } = require('../utils/request-chat');
const { serializeServiceRequest, serializeStaffInvite, serializeUser } = require('../utils/serializers');
const { buildStaffInviteLink } = require('./token.service');

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
    ServiceRequest.find()
      .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
      .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
      .sort({ updatedAt: -1, createdAt: -1 })
      .limit(5),
  ]);

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'AdminGetDashboard',
    intent: 'Confirm admin summary data is ready for response shaping',
  });

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

  const requests = await ServiceRequest.find(query)
    .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .sort({ updatedAt: -1, createdAt: -1 })
    .limit(50);

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

  // WHY: Update the assignee and workflow status together so ownership and stage never drift apart.
  const request = await ServiceRequest.findByIdAndUpdate(
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
  )
    .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt');

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
  createStaffInvite,
  deleteStaffInvite,
  getDashboard,
  listRequests,
  listStaff,
  listStaffInvites,
};
