/**
 * WHAT: Implements authenticated customer request creation, request history, and request-thread messaging.
 * WHY: Customer queue access must stay isolated from admin and staff behavior while preserving one shared request thread.
 * HOW: Load the signed-in customer, persist queue-ready requests, and append customer/AI messages onto owned requests only.
 */

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  REQUEST_SOURCES,
  REQUEST_STATUSES,
  USER_ROLES,
  USER_STATUSES,
} = require('../constants/app.constants');
const { ServiceRequest } = require('../models/service-request.model');
const { User } = require('../models/user.model');
const { AppError } = require('../utils/app-error');
const { logInfo } = require('../utils/logger');
const {
  buildAiMessage,
  buildCustomerMessage,
  buildSystemMessage,
} = require('../utils/request-chat');
const { serializeServiceRequest } = require('../utils/serializers');

function buildWaitingAiText() {
  // WHY: Keep the placeholder AI copy in one helper so queue-waiting guidance stays consistent across message flows.
  return 'Thanks. I added your update to the queue and will keep this conversation warm while a staff member joins.';
}

async function loadActiveCustomer(customerUserId) {
  // WHY: Customer-owned actions should always resolve identity from the trusted user record instead of form data.
  return User.findOne({
    _id: customerUserId,
    role: USER_ROLES.CUSTOMER,
    status: USER_STATUSES.ACTIVE,
  });
}

async function loadOwnedRequest(customerUserId, requestId) {
  // WHY: Scope request lookups by the signed-in customer id so customers can never post into someone else's thread.
  return ServiceRequest.findOne({
    _id: requestId,
    customer: customerUserId,
  })
    .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt');
}

async function createRequest(customerUserId, payload, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'CustomerCreateRequest',
    intent: 'Create a new form-based service request and place it into the live waiting queue',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'CustomerCreateRequest',
    intent: 'Load the authenticated customer to build a trusted contact snapshot and first queue message',
  });

  const customer = await loadActiveCustomer(customerUserId);

  // WHY: Reject stale or invalid customer sessions before creating a service request.
  if (!customer) {
    throw new AppError({
      message: 'Customer account not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode: 'CUSTOMER_REQUEST_USER_NOT_FOUND',
      resolutionHint: 'Log in again and try once more',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  // WHY: Seed the thread immediately so the customer lands in a queue with visible conversation context instead of silence.
  const request = await ServiceRequest.create({
    customer: customer._id,
    serviceType: payload.serviceType,
    status: REQUEST_STATUSES.SUBMITTED,
    source: REQUEST_SOURCES.FORM,
    location: {
      addressLine1: payload.addressLine1,
      city: payload.city,
      postalCode: payload.postalCode,
    },
    preferredDate: payload.preferredDate || null,
    preferredTimeWindow: payload.preferredTimeWindow || '',
    message: payload.message,
    contactSnapshot: {
      fullName: `${customer.firstName} ${customer.lastName}`.trim(),
      email: customer.email,
      phone: customer.phone || '',
    },
    queueEnteredAt: new Date(),
    messages: [
      buildCustomerMessage({
        customerId: customer._id,
        customerName: `${customer.firstName} ${customer.lastName}`.trim(),
        text: payload.message,
      }),
      buildSystemMessage('Your request is now in the live queue. A staff member will attend to it here.'),
      buildAiMessage('I captured your request details and will keep you company here while you wait for staff.'),
    ],
  });

  // WHY: Re-read the request with populated relations so create and list endpoints return one stable payload shape.
  const populatedRequest = await ServiceRequest.findById(request._id)
    .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt');

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'CustomerCreateRequest',
    intent: 'Confirm the new queue-backed service request was saved for the customer timeline',
  });

  return {
    message: 'Service request created successfully and added to the queue',
    request: serializeServiceRequest(populatedRequest),
  };
}

async function listRequests(customerUserId, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'CustomerListRequests',
    intent: 'Return only the service requests and request threads owned by the authenticated customer',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'CustomerListRequests',
    intent: 'Load the customer request timeline with assignment and thread details when available',
  });

  const requests = await ServiceRequest.find({ customer: customerUserId })
    .populate('customer', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .populate('assignedStaff', 'firstName lastName email phone role status staffAvailability createdAt updatedAt')
    .sort({ createdAt: -1 });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'CustomerListRequests',
    intent: 'Confirm customer-owned request history is ready for the frontend',
  });

  return {
    message: 'Customer requests fetched successfully',
    requests: requests.map(serializeServiceRequest),
  };
}

async function postRequestMessage(customerUserId, requestId, text, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'CustomerPostRequestMessage',
    intent: 'Append a customer message to an owned queue thread and keep the waiting customer informed',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'CustomerPostRequestMessage',
    intent: 'Load the owned request thread before appending a new customer message',
  });

  const request = await loadOwnedRequest(customerUserId, requestId);

  // WHY: Keep ownership enforcement at the query boundary so customers cannot post into another request thread.
  if (!request) {
    throw new AppError({
      message: 'Request thread not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_MESSAGE_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  request.messages.push(
    buildCustomerMessage({
      customerId: customerUserId,
      customerName: request.contactSnapshot.fullName,
      text,
    }),
  );

  // WHY: While no staff member is attached, a lightweight AI placeholder should reassure the customer that the queue is still active.
  if (!request.assignedStaff) {
    request.messages.push(buildAiMessage(buildWaitingAiText()));
  }

  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'CustomerPostRequestMessage',
    intent: 'Confirm the customer message was appended to the owned queue thread',
  });

  return {
    message: request.assignedStaff
      ? 'Message sent to the assigned staff thread'
      : 'Message added to the queue while you wait for staff',
    request: serializeServiceRequest(request),
  };
}

module.exports = {
  createRequest,
  listRequests,
  postRequestMessage,
};
