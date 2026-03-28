/**
 * WHAT: Stores customer service requests from the form-based intake flow.
 * WHY: Request ownership, staff assignment, and dashboards all rely on a normalized request record.
 * HOW: Persist customer/contact details, location, status, source, and staff assignment metadata.
 */

const mongoose = require('mongoose');

const {
  REQUEST_MESSAGE_SENDERS,
  REQUEST_SOURCES,
  REQUEST_STATUSES,
  SERVICE_TYPES,
} = require('../constants/app.constants');

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
    text: {
      type: String,
      required: true,
      trim: true,
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
