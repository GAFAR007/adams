/**
 * WHAT: Stores customer service requests from the form-based intake flow.
 * WHY: Request ownership, staff assignment, and dashboards all rely on a normalized request record.
 * HOW: Persist customer/contact details, location, status, source, and staff assignment metadata.
 */

const mongoose = require('mongoose');

const {
  PAYMENT_METHODS,
  PAYMENT_REQUEST_STATUSES,
  REQUEST_MESSAGE_ACTIONS,
  REQUEST_MESSAGE_SENDERS,
  REQUEST_SOURCES,
  REQUEST_STATUSES,
  SERVICE_TYPES,
  USER_ROLES,
} = require('../constants/app.constants');

const requestMessageAttachmentSchema = new mongoose.Schema(
  {
    originalName: {
      type: String,
      required: true,
      trim: true,
    },
    storedName: {
      type: String,
      required: true,
      trim: true,
    },
    mimeType: {
      type: String,
      required: true,
      trim: true,
    },
    sizeBytes: {
      type: Number,
      required: true,
      min: 1,
    },
    relativeUrl: {
      type: String,
      required: true,
      trim: true,
    },
  },
  {
    _id: false,
    id: false,
  },
);

const requestMessageSchema = new mongoose.Schema(
  {
    senderType: {
      // WHY: The frontend needs to distinguish customer, staff, AI, and system messages when rendering the thread.
      type: String,
      enum: Object.values(REQUEST_MESSAGE_SENDERS),
      required: true,
    },
    senderId: {
      // WHY: Human-authored messages keep an author reference for future audit and richer participant views.
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    senderName: {
      type: String,
      required: true,
      trim: true,
    },
    actionType: {
      // WHY: Structured message actions let the frontend render real affordances like request-update buttons in chat.
      type: String,
      enum: Object.values(REQUEST_MESSAGE_ACTIONS),
      default: null,
    },
    text: {
      type: String,
      required: true,
      trim: true,
    },
    attachment: {
      // WHY: Customers may need to drop images or documents straight into the live thread for staff review.
      type: requestMessageAttachmentSchema,
      default: null,
    },
    createdAt: {
      type: Date,
      default: Date.now,
    },
  },
  {
    _id: true,
    id: false,
  },
);

const paymentProofSchema = new mongoose.Schema(
  {
    originalName: {
      type: String,
      required: true,
      trim: true,
    },
    storedName: {
      type: String,
      required: true,
      trim: true,
    },
    mimeType: {
      type: String,
      required: true,
      trim: true,
    },
    sizeBytes: {
      type: Number,
      required: true,
      min: 1,
    },
    relativeUrl: {
      type: String,
      required: true,
      trim: true,
    },
    uploadedAt: {
      type: Date,
      default: Date.now,
    },
    note: {
      type: String,
      default: '',
      trim: true,
    },
  },
  {
    _id: false,
    id: false,
  },
);

const requestInvoiceSchema = new mongoose.Schema(
  {
    invoiceNumber: {
      type: String,
      required: true,
      trim: true,
    },
    amount: {
      type: Number,
      required: true,
      min: 0,
    },
    currency: {
      type: String,
      default: 'EUR',
      trim: true,
    },
    dueDate: {
      type: Date,
      default: null,
    },
    paymentMethod: {
      type: String,
      enum: Object.values(PAYMENT_METHODS),
      required: true,
    },
    paymentInstructions: {
      type: String,
      default: '',
      trim: true,
    },
    note: {
      type: String,
      default: '',
      trim: true,
    },
    status: {
      type: String,
      enum: Object.values(PAYMENT_REQUEST_STATUSES),
      default: PAYMENT_REQUEST_STATUSES.SENT,
    },
    sentAt: {
      type: Date,
      default: Date.now,
    },
    sentByRole: {
      type: String,
      enum: [USER_ROLES.ADMIN, USER_ROLES.STAFF],
      required: true,
    },
    sentById: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    reviewedAt: {
      type: Date,
      default: null,
    },
    reviewedByRole: {
      type: String,
      enum: [USER_ROLES.ADMIN, USER_ROLES.STAFF],
      default: null,
    },
    reviewedById: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    reviewNote: {
      type: String,
      default: '',
      trim: true,
    },
    proof: {
      type: paymentProofSchema,
      default: null,
    },
  },
  {
    _id: false,
    id: false,
  },
);

const serviceRequestSchema = new mongoose.Schema(
  {
    customer: {
      // WHY: Keep a stable customer reference so request ownership can always be enforced from the DB.
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    serviceType: {
      type: String,
      enum: SERVICE_TYPES,
      required: true,
    },
    status: {
      // WHY: Persist workflow status centrally so admin, customer, and staff views stay in sync.
      type: String,
      enum: Object.values(REQUEST_STATUSES),
      default: REQUEST_STATUSES.SUBMITTED,
      index: true,
    },
    source: {
      // WHY: Record intake source now so the model can support future AI/chat flows without shape changes.
      type: String,
      enum: Object.values(REQUEST_SOURCES),
      default: REQUEST_SOURCES.FORM,
    },
    location: {
      addressLine1: {
        type: String,
        required: true,
        trim: true,
      },
      city: {
        type: String,
        required: true,
        trim: true,
      },
      postalCode: {
        type: String,
        required: true,
        trim: true,
      },
    },
    preferredDate: {
      type: Date,
      default: null,
    },
    preferredTimeWindow: {
      type: String,
      default: '',
      trim: true,
    },
    invoice: {
      // WHY: Persist the latest invoice/payment-proof state directly on the request so chat and delivery status stay aligned.
      type: requestInvoiceSchema,
      default: null,
    },
    detailsUpdatedAt: {
      // WHY: Track the last customer details edit so update-request prompts can clear once the customer has actually edited the request.
      type: Date,
      default: Date.now,
    },
    message: {
      type: String,
      required: true,
      trim: true,
    },
    contactSnapshot: {
      // WHY: Snapshot submission-time contact details so later profile edits do not rewrite past requests.
      fullName: {
        type: String,
        required: true,
      },
      email: {
        type: String,
        required: true,
      },
      phone: {
        type: String,
        default: '',
      },
    },
    assignedStaff: {
      // WHY: Keep direct assignee lookup cheap because dashboards and staff inboxes depend on it often.
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
      index: true,
    },
    queueEnteredAt: {
      // WHY: Queue views and queue-clearing metrics need the original waiting timestamp preserved independently of updates.
      type: Date,
      default: Date.now,
    },
    attendedAt: {
      // WHY: Record the first staff pickup time so the system can distinguish waiting work from attended work.
      type: Date,
      default: null,
    },
    projectStartedAt: {
      // WHY: Capture when on-site work actually started so the workflow can show the live project timeline.
      type: Date,
      default: null,
    },
    finishedAt: {
      // WHY: Capture when the work was marked done, even if final closure happens later.
      type: Date,
      default: null,
    },
    closedAt: {
      // WHY: Store the closure timestamp explicitly so daily queue-clearing metrics do not rely on generic updatedAt writes.
      type: Date,
      default: null,
    },
    messages: {
      // WHY: Keep queue conversation history directly on the request so customer, staff, and admin surfaces share one thread.
      type: [requestMessageSchema],
      default: [],
    },
  },
  {
    timestamps: true,
  },
);

// Inbox queries are driven by status and recency, so both should be indexed together.
serviceRequestSchema.index({ status: 1, createdAt: -1 });
serviceRequestSchema.index({ assignedStaff: 1, status: 1, createdAt: -1 });
serviceRequestSchema.index({ status: 1, assignedStaff: 1, queueEnteredAt: 1 });

const ServiceRequest = mongoose.model('ServiceRequest', serviceRequestSchema);

module.exports = { ServiceRequest };
