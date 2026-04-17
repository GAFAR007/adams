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
  REQUEST_ASSESSMENT_STATUSES,
  REQUEST_MESSAGE_ACTIONS,
  REQUEST_MESSAGE_SENDERS,
  REQUEST_QUOTE_READINESS_STATUSES,
  REQUEST_SOURCES,
  REQUEST_STATUSES,
  STAFF_AVAILABILITIES,
  USER_ROLES,
  USER_STATUSES,
} = require('../constants/app.constants');
const { CompanyProfile } = require('../models/company-profile.model');
const { ServiceRequest } = require('../models/service-request.model');
const { User } = require('../models/user.model');
const { AppError } = require('../utils/app-error');
const { logInfo } = require('../utils/logger');
const {
  buildQueueAttachmentAiText,
  buildQueueCreatedAiText,
  buildQueueDetailsUpdatedAiText,
  buildQueueFollowUpAiText,
} = require('../utils/request-queue-ai');
const {
  REQUEST_ATTACHMENT_CATEGORIES,
  buildAttachmentActionPayload,
  buildAiMessage,
  buildCustomerMessage,
  buildRequestMessageAttachment,
  buildSystemMessage,
  resolveWorkflowAttachmentCategory,
} = require('../utils/request-chat');
const {
  REQUEST_REPLY_ASSISTANT_NAME,
  suggestRequestThreadReply,
} = require('../utils/request-reply-assistant');
const {
  attachProofToInvoice,
  isInvoiceProofUploadLocked,
} = require('../utils/request-payment');
const {
  syncApprovedInvoiceReceiptIfNeeded,
  syncOnlineInvoicePaymentIfNeeded,
} = require('../utils/request-payment-status');
const { serializeServiceRequest } = require('../utils/serializers');
const {
  isImageMimeType,
  isVideoMimeType,
  refreshRequestMediaSummary,
} = require('../utils/request-media');
const {
  storePaymentProofFile,
  storeRequestAttachmentFile,
} = require('./file-storage.service');
const { populateServiceRequestRelations } = require('../utils/request-query');

const MAX_REQUEST_INTAKE_PHOTOS = 12;
const MAX_REQUEST_INTAKE_VIDEOS = 2;

async function loadQueueCompanyProfile() {
  // WHY: Queue-assistant copy should reuse the live company profile when it exists, but request handling must still work without it.
  return CompanyProfile.findOne({ siteKey: 'default' }).lean();
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
  const populatedRequest = await populateServiceRequestRelations(
    ServiceRequest.findOne({
      _id: requestId,
      customer: customerUserId,
    }),
  );

  if (
    populatedRequest &&
    (
      await syncOnlineInvoicePaymentIfNeeded(populatedRequest) ||
      await syncApprovedInvoiceReceiptIfNeeded(populatedRequest)
    )
  ) {
    await populatedRequest.save();
  }

  return populatedRequest;
}

function shouldAssistantHandleCustomerThread(request) {
  if (!request?.assignedStaff) {
    return true;
  }

  return (
    Boolean(request.aiControlEnabled) ||
    request.assignedStaff.staffAvailability !== STAFF_AVAILABILITIES.ONLINE
  );
}

function buildCustomerThreadResponseMessage(request, itemLabel) {
  if (!request?.assignedStaff) {
    return `${itemLabel} added to the queue`;
  }

  if (shouldAssistantHandleCustomerThread(request)) {
    return `${itemLabel} added while Naima covers the chat`;
  }

  return `${itemLabel} sent to the assigned staff thread`;
}

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

async function createRequest(customerUserId, payload, files, logContext) {
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

  const intakeFiles = Array.isArray(files) ? files : [];
  const intakePhotoFiles = intakeFiles.filter((file) =>
    isImageMimeType(file?.mimetype),
  );
  const intakeVideoFiles = intakeFiles.filter((file) =>
    isVideoMimeType(file?.mimetype),
  );

  if (intakePhotoFiles.length > MAX_REQUEST_INTAKE_PHOTOS) {
    throw new AppError({
      message: 'No more than 12 request photos can be submitted at once',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_REQUEST_PHOTO_LIMIT_EXCEEDED',
      resolutionHint: 'Remove some photos and try again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  if (intakeVideoFiles.length > MAX_REQUEST_INTAKE_VIDEOS) {
    throw new AppError({
      message: 'No more than 2 request videos can be submitted at once',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_REQUEST_VIDEO_LIMIT_EXCEEDED',
      resolutionHint: 'Remove some videos and try again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  const storedIntakeAttachments = await Promise.all(
    intakeFiles.map((file) => storeRequestAttachmentFile(file, logContext)),
  );

  const detailsUpdatedAt = new Date();
  const companyProfile = await loadQueueCompanyProfile();
  const customerName = `${customer.firstName} ${customer.lastName}`.trim();
  const intakeMessages = storedIntakeAttachments.map((storedAttachment, index) =>
    buildCustomerMessage({
      customerId: customer._id,
      customerName,
      actionPayload: buildAttachmentActionPayload({
        attachmentCategory: REQUEST_ATTACHMENT_CATEGORIES.REQUEST_UPLOAD,
        mimeType: storedAttachment.mimeType,
        sequence: index + 1,
      }),
      text: isVideoMimeType(storedAttachment.mimeType)
        ? `Shared intake video ${index + 1}`
        : `Shared intake photo ${index + 1}`,
      attachment: buildRequestMessageAttachment(storedAttachment),
    }),
  );

  // WHY: Seed the thread immediately so the customer lands in a queue with visible conversation context instead of silence.
  const request = await ServiceRequest.create({
    customer: customer._id,
    serviceType: payload.serviceType,
    status: REQUEST_STATUSES.SUBMITTED,
    source: REQUEST_SOURCES.FORM,
    assessmentStatus: REQUEST_ASSESSMENT_STATUSES.AWAITING_REVIEW,
    quoteReadinessStatus:
      REQUEST_QUOTE_READINESS_STATUSES.AWAITING_ESTIMATE,
    location: {
      addressLine1: payload.addressLine1,
      city: payload.city,
      postalCode: payload.postalCode,
    },
    accessDetails: {
      accessMethod: payload.accessMethod,
      arrivalContactName: payload.arrivalContactName,
      arrivalContactPhone: payload.arrivalContactPhone,
      accessNotes: payload.accessNotes,
    },
    preferredDate: payload.preferredDate || null,
    preferredTimeWindow: payload.preferredTimeWindow || '',
    detailsUpdatedAt,
    message: payload.message,
    contactSnapshot: {
      fullName: customerName,
      email: customer.email,
      phone: customer.phone || '',
    },
    queueEnteredAt: new Date(),
    messages: [
      buildCustomerMessage({
        customerId: customer._id,
        customerName,
        text: payload.message,
      }),
      ...intakeMessages,
      buildSystemMessage('Your request is now in the live queue. A staff member will attend to it here.'),
      buildAiMessage(
        buildQueueCreatedAiText({
          request: {
            serviceType: payload.serviceType,
            preferredTimeWindow: payload.preferredTimeWindow || '',
            location: {
              city: payload.city,
            },
            messages: [],
          },
          companyProfile,
        }),
      ),
    ],
  });
  refreshRequestMediaSummary(request, {
    intakePhotoCount: intakePhotoFiles.length,
    intakeVideoCount: intakeVideoFiles.length,
  });
  await request.save();

  // WHY: Re-read the request with populated relations so create and list endpoints return one stable payload shape.
  const populatedRequest = await populateServiceRequestRelations(
    ServiceRequest.findById(request._id),
  );

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

  const requests = await populateServiceRequestRelations(
    ServiceRequest.find({ customer: customerUserId }).sort({ createdAt: -1 }),
  );

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
  if (shouldAssistantHandleCustomerThread(request)) {
    const companyProfile = await loadQueueCompanyProfile();
    request.messages.push(
      buildAiMessage(
        buildQueueFollowUpAiText({
          request,
          companyProfile,
          customerText: text,
        }),
      ),
    );
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
    message: buildCustomerThreadResponseMessage(request, 'Message'),
    request: serializeServiceRequest(request),
  };
}

async function suggestRequestReply(customerUserId, requestId, draft, logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'CustomerSuggestRequestReply',
    intent: 'Generate a professional customer reply suggestion from the owned request thread context',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'CustomerSuggestRequestReply',
    intent: 'Load the owned request thread before generating the customer reply suggestion',
  });

  const request = await loadOwnedRequest(customerUserId, requestId);

  if (!request) {
    throw new AppError({
      message: 'Request thread not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_REPLY_SUGGEST_REQUEST_NOT_FOUND',
      resolutionHint: 'Refresh your request list and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  const suggestion = await suggestRequestThreadReply({
    request,
    viewerRole: USER_ROLES.CUSTOMER,
    senderName: request.contactSnapshot.fullName,
    draft,
    logContext,
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'CustomerSuggestRequestReply',
    intent: 'Confirm the customer reply suggestion is ready for the composer',
  });

  return {
    message: 'Customer reply suggestion generated successfully',
    assistant: {
      name: REQUEST_REPLY_ASSISTANT_NAME,
      suggestion,
    },
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

  if (isCustomerEditLocked(request)) {
    throw new AppError({
      message: 'Requests cannot be edited after the quotation has been sent',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_UPDATE_REQUEST_QUOTED_LOCKED',
      resolutionHint: 'Continue the thread with staff if you need clarification on the quoted work plan',
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
  const nextAccessDetails = {
    accessMethod:
      payload.accessMethod || request.accessDetails?.accessMethod || '',
    arrivalContactName:
      payload.arrivalContactName ||
      request.accessDetails?.arrivalContactName ||
      '',
    arrivalContactPhone:
      payload.arrivalContactPhone ||
      request.accessDetails?.arrivalContactPhone ||
      '',
    accessNotes: payload.accessNotes || request.accessDetails?.accessNotes || '',
  };
  if (
    nextAccessDetails.accessMethod &&
    nextAccessDetails.arrivalContactName &&
    nextAccessDetails.arrivalContactPhone &&
    nextAccessDetails.accessNotes
  ) {
    request.accessDetails = nextAccessDetails;
  }
  request.detailsUpdatedAt = new Date();
  request.messages.push(
    buildSystemMessage(
      'Customer updated the request details. Review the latest request brief for the new address, timing, and work scope.',
    ),
  );

  const lastMessage = request.messages[request.messages.length - 2];
  const shouldRespondToPendingUpdateRequest =
    lastMessage?.actionType === REQUEST_MESSAGE_ACTIONS.CUSTOMER_UPDATE_REQUEST;

  if (
    shouldAssistantHandleCustomerThread(request) &&
    shouldRespondToPendingUpdateRequest
  ) {
    const companyProfile = await loadQueueCompanyProfile();
    request.messages.push(
      buildAiMessage(
        buildQueueDetailsUpdatedAiText({
          request,
          companyProfile,
        }),
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

  if (isInvoiceProofUploadLocked(request.invoice)) {
    throw new AppError({
      message:
        request.invoice.kind === 'site_review'
          ? 'Payment proof can no longer be uploaded for this site review booking'
          : 'Payment proof can no longer be uploaded for this quotation',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_PAYMENT_PROOF_UPLOAD_WINDOW_EXPIRED',
      resolutionHint:
        'Ask customer care to reopen payment-proof upload if the transfer was completed late',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const storedProof = await storePaymentProofFile(file, logContext);
  attachProofToInvoice(request.invoice, storedProof, note);
  const proofAttachment = buildRequestMessageAttachment(
    storedProof,
    request.invoice.proof?.relativeUrl,
  );
  const trimmedNote = typeof note === 'string' ? note.trim() : '';
  request.messages.push(
    buildCustomerMessage({
      customerId: customerUserId,
      customerName: request.contactSnapshot.fullName,
      actionType: REQUEST_MESSAGE_ACTIONS.CUSTOMER_UPLOAD_PAYMENT_PROOF,
      actionPayload: buildAttachmentActionPayload({
        attachmentCategory:
          request.invoice.kind === 'site_review'
            ? REQUEST_ATTACHMENT_CATEGORIES.SITE_REVIEW_PROOF_UPLOAD
            : REQUEST_ATTACHMENT_CATEGORIES.INVOICE_PROOF_UPLOAD,
        mimeType: storedProof.mimeType,
        invoiceKind: request.invoice.kind,
      }),
      text: trimmedNote.length === 0
          ? request.invoice.kind === 'site_review'
                ? `Uploaded payment proof for site review booking ${request.invoice.invoiceNumber}.`
                : `Uploaded payment proof for quotation ${request.invoice.invoiceNumber}.`
          : request.invoice.kind === 'site_review'
          ? `Uploaded payment proof for site review booking ${request.invoice.invoiceNumber}. Note: ${trimmedNote}`
          : `Uploaded payment proof for quotation ${request.invoice.invoiceNumber}. Note: ${trimmedNote}`,
      attachment: proofAttachment,
    }),
  );
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
  const storedAttachment = await storeRequestAttachmentFile(file, logContext);
  request.messages.push(
    buildCustomerMessage({
      customerId: customerUserId,
      customerName: request.contactSnapshot.fullName,
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

  if (shouldAssistantHandleCustomerThread(request)) {
    const companyProfile = await loadQueueCompanyProfile();
    request.messages.push(
      buildAiMessage(
        buildQueueAttachmentAiText({
          request,
          companyProfile,
          attachmentName: storedAttachment.originalName,
        }),
      ),
    );
  }

  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'CustomerUploadRequestAttachment',
    intent: 'Confirm the customer file was appended to the owned request thread',
  });

  return {
    message: buildCustomerThreadResponseMessage(request, 'Attachment'),
    request: serializeServiceRequest(request),
  };
}

async function replaceRequestAttachment(
  customerUserId,
  requestId,
  messageId,
  file,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'CustomerReplaceRequestAttachment',
    intent: 'Replace an existing customer-owned chat attachment on an owned request thread',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'CustomerReplaceRequestAttachment',
    intent: 'Load the owned request thread before replacing a customer attachment message',
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
      message: 'Closed requests cannot accept attachment updates',
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

  const message = request.messages.id(messageId);

  if (!message) {
    throw new AppError({
      message: 'Attachment message not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_ATTACHMENT_MESSAGE_NOT_FOUND',
      resolutionHint: 'Refresh the thread and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (
    message.senderType !== REQUEST_MESSAGE_SENDERS.CUSTOMER
  ) {
    throw new AppError({
      message: 'Only customer attachment messages can be updated',
      statusCode: 403,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_ATTACHMENT_MESSAGE_FORBIDDEN',
      resolutionHint: 'Choose one of your own attachment messages and try again',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (String(message.senderId || '') !== String(customerUserId)) {
    throw new AppError({
      message: 'Only your own attachment messages can be updated',
      statusCode: 403,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_ATTACHMENT_MESSAGE_FORBIDDEN',
      resolutionHint: 'Choose one of your own attachment messages and try again',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (!message.attachment) {
    throw new AppError({
      message: 'This message does not contain a replaceable attachment',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_ATTACHMENT_MESSAGE_EMPTY',
      resolutionHint: 'Choose a message that already contains an uploaded file',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  if (message.actionType === REQUEST_MESSAGE_ACTIONS.CUSTOMER_UPLOAD_PAYMENT_PROOF) {
    throw new AppError({
      message: 'Payment proof files should be updated from the quotation card',
      statusCode: 409,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'CUSTOMER_ATTACHMENT_PAYMENT_PROOF_MANAGED_SEPARATELY',
      resolutionHint: 'Use the quotation card to upload a new payment proof',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  const storedAttachment = await storeRequestAttachmentFile(file, logContext);
  message.attachment = buildRequestMessageAttachment(storedAttachment);

  if (String(message.text || '').trim().startsWith('Shared a file:')) {
    message.text = `Shared a file: ${storedAttachment.originalName || 'attachment'}`;
  }

  request.markModified('messages');
  refreshRequestMediaSummary(request);
  await request.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'CustomerReplaceRequestAttachment',
    intent: 'Confirm the customer attachment message now points to the replacement file',
  });

  return {
    message: 'Attachment updated successfully',
    request: serializeServiceRequest(request),
  };
}

module.exports = {
  createRequest,
  listRequests,
  postRequestMessage,
  suggestRequestReply,
  replaceRequestAttachment,
  uploadRequestAttachment,
  uploadPaymentProof,
  updateRequest,
};
