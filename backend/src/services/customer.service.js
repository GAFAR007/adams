/**
 * WHAT: Implements authenticated customer request creation, request history, and request-thread messaging.
 * WHY: Customer queue access must stay isolated from admin and staff behavior while preserving one shared request thread.
 * HOW: Load the signed-in customer, persist queue-ready requests, and append customer/AI messages onto owned requests only.
 */

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  PAYMENT_METHODS,
  PAYMENT_REQUEST_STATUSES,
  REQUEST_MESSAGE_ACTIONS,
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
  buildRequestMessageAttachment,
  buildSystemMessage,
} = require('../utils/request-chat');
const {
  attachProofToInvoice,
  buildProofUploadedMessage,
} = require('../utils/request-payment');
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

  const detailsUpdatedAt = new Date();
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
    detailsUpdatedAt,
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

async function updateRequest(customerUserId, requestId, payload, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'CustomerUpdateRequest',
    intent: 'Persist edited request details for a customer-owned service request',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'CustomerUpdateRequest',
    intent: 'Load the owned request before applying edited service details',
  });

  const request = await loadOwnedRequest(customerUserId, requestId);

  if (!request) {
    throw new AppError({
      message: 'Request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_UPDATE_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot be edited',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_UPDATE_REQUEST_CLOSED',
      resolutionHint: 'Open a new request or continue the thread for reference only',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  request.serviceType = payload.serviceType;
  request.location.addressLine1 = payload.addressLine1;
  request.location.city = payload.city;
  request.location.postalCode = payload.postalCode;
  request.preferredDate = payload.preferredDate || null;
  request.preferredTimeWindow = payload.preferredTimeWindow || '';
  request.message = payload.message;
  request.detailsUpdatedAt = new Date();
  request.messages.push(
    buildSystemMessage(
      'Customer updated the request details. Review the latest request brief for the new address, timing, and work scope.',
    ),
  );

  const lastMessage = request.messages[request.messages.length - 2];
  const shouldClearPendingUpdateAction =
    lastMessage?.actionType === REQUEST_MESSAGE_ACTIONS.CUSTOMER_UPDATE_REQUEST;

  if (!request.assignedStaff && shouldClearPendingUpdateAction) {
    request.messages.push(
      buildAiMessage(
        'Your request details were updated successfully. I kept the queue thread aligned with the latest information.',
      ),
    );
  }

  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'CustomerUpdateRequest',
    intent: 'Confirm the owned request details were updated successfully',
  });

  return {
    message: 'Request updated successfully',
    request: serializeServiceRequest(request),
  };
}

async function uploadPaymentProof(customerUserId, requestId, file, note, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'CustomerUploadPaymentProof',
    intent: 'Attach customer payment proof to the latest invoice on an owned request',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'CustomerUploadPaymentProof',
    intent: 'Load the owned request and its invoice before accepting a proof file',
  });

  const request = await loadOwnedRequest(customerUserId, requestId);

  if (!request) {
    throw new AppError({
      message: 'Request not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_PAYMENT_PROOF_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot accept new payment proof uploads',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_PAYMENT_PROOF_REQUEST_CLOSED',
      resolutionHint: 'Open a new request if you need to continue with another job',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (!file) {
    throw new AppError({
      message: 'Payment proof file is required',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.MISSING_REQUIRED_FIELD,
      errorCode: 'CUSTOMER_PAYMENT_PROOF_FILE_REQUIRED',
      resolutionHint: 'Choose a PNG, JPG, or PDF file and try again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  if (!request.invoice) {
    throw new AppError({
      message: 'No invoice is waiting for payment proof on this request',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_PAYMENT_PROOF_INVOICE_MISSING',
      resolutionHint: 'Wait for staff or admin to send an invoice first',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (request.invoice.paymentMethod !== PAYMENT_METHODS.SEPA_BANK_TRANSFER) {
    throw new AppError({
      message: 'This invoice does not require an uploaded payment proof',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_PAYMENT_PROOF_NOT_REQUIRED',
      resolutionHint: 'Follow the payment option shown on the invoice details',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (
    request.invoice.status !== PAYMENT_REQUEST_STATUSES.SENT &&
    request.invoice.status !== PAYMENT_REQUEST_STATUSES.REJECTED
  ) {
    throw new AppError({
      message: 'This invoice is not waiting for a new payment proof upload',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_PAYMENT_PROOF_STATUS_INVALID',
      resolutionHint: 'Refresh the chat to check the latest payment status',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  attachProofToInvoice(request.invoice, file, note);
  request.messages.push(buildSystemMessage(buildProofUploadedMessage(request.invoice)));
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'CustomerUploadPaymentProof',
    intent: 'Confirm the payment proof was attached to the owned request invoice',
  });

  return {
    message: 'Payment proof uploaded successfully',
    request: serializeServiceRequest(request),
  };
}

async function uploadRequestAttachment(
  customerUserId,
  requestId,
  file,
  caption,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'CustomerUploadRequestAttachment',
    intent: 'Attach a customer document or image directly to an owned request thread',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'CustomerUploadRequestAttachment',
    intent: 'Load the owned request thread before adding a file attachment message',
  });

  const request = await loadOwnedRequest(customerUserId, requestId);

  if (!request) {
    throw new AppError({
      message: 'Request thread not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_ATTACHMENT_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (request.status === REQUEST_STATUSES.CLOSED) {
    throw new AppError({
      message: 'Closed requests cannot accept new chat attachments',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_ATTACHMENT_REQUEST_CLOSED',
      resolutionHint: 'Open a new request if you need to continue with another job',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (!file) {
    throw new AppError({
      message: 'Attachment file is required',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.MISSING_REQUIRED_FIELD,
      errorCode: 'CUSTOMER_ATTACHMENT_FILE_REQUIRED',
      resolutionHint: 'Choose a file and try again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  const trimmedCaption = typeof caption === 'string' ? caption.trim() : '';
  const relativeUrl = `/uploads/request-attachments/${file.filename}`;
  request.messages.push(
    buildCustomerMessage({
      customerId: customerUserId,
      customerName: request.contactSnapshot.fullName,
      text:
        trimmedCaption.length === 0
          ? `Shared a file: ${file.originalname || 'attachment'}`
          : trimmedCaption,
      attachment: buildRequestMessageAttachment(file, relativeUrl),
    }),
  );

  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'CustomerUploadRequestAttachment',
    intent: 'Confirm the customer file was appended to the owned request thread',
  });

  return {
    message: request.assignedStaff
      ? 'Attachment sent to the assigned staff thread'
      : 'Attachment added to the queue while you wait for staff',
    request: serializeServiceRequest(request),
  };
}

module.exports = {
  createRequest,
  listRequests,
  postRequestMessage,
  uploadRequestAttachment,
  uploadPaymentProof,
  updateRequest,
};
