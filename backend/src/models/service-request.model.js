/**
 * WHAT: Stores customer service requests from the form-based intake flow.
 * WHY: Request ownership, staff assignment, and dashboards all rely on a normalized request record.
 * HOW: Persist customer/contact details, location, status, source, and staff assignment metadata.
 */

const mongoose = require("mongoose");

const {
  PAYMENT_METHODS,
  PAYMENT_REQUEST_STATUSES,
  PRICING_RULES,
  REQUEST_ACCESS_METHODS,
  REQUEST_ASSESSMENT_STATUSES,
  REQUEST_ASSESSMENT_TYPES,
  REQUEST_ESTIMATION_STAGES,
  REQUEST_MESSAGE_ACTIONS,
  REQUEST_MESSAGE_SENDERS,
  REQUEST_QUOTE_READINESS_STATUSES,
  REQUEST_REVIEW_KINDS,
  REQUEST_SOURCES,
  REQUEST_STATUSES,
  REQUEST_WORK_LOG_TYPES,
  SERVICE_TYPES,
  STAFF_TYPES,
  USER_ROLES,
} = require("../constants/app.constants");

const requestMessageAttachmentSchema =
  new mongoose.Schema(
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
      enum: Object.values(
        REQUEST_MESSAGE_SENDERS,
      ),
      required: true,
    },
    senderId: {
      // WHY: Human-authored messages keep an author reference for future audit and richer participant views.
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
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
      enum: Object.values(
        REQUEST_MESSAGE_ACTIONS,
      ),
      default: null,
    },
    actionPayload: {
      // WHY: Structured workflow events let staff and customer care render quote handoff cards without parsing plain text.
      type: mongoose.Schema.Types.Mixed,
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
      default: "",
      trim: true,
    },
  },
  {
    _id: false,
    id: false,
  },
);

const plannedWorkDaySchema = new mongoose.Schema(
  {
    date: {
      type: Date,
      required: true,
    },
    startTime: {
      type: String,
      default: '',
      trim: true,
    },
    endTime: {
      type: String,
      default: '',
      trim: true,
    },
    hours: {
      type: Number,
      default: null,
      min: 0,
      max: 10,
    },
  },
  {
    _id: false,
    id: false,
  },
);

const accessDetailsSchema = new mongoose.Schema(
  {
    accessMethod: {
      type: String,
      enum: Object.values(REQUEST_ACCESS_METHODS),
      required: true,
      trim: true,
    },
    arrivalContactName: {
      type: String,
      required: true,
      trim: true,
    },
    arrivalContactPhone: {
      type: String,
      required: true,
      trim: true,
    },
    accessNotes: {
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

const requestMediaSummarySchema = new mongoose.Schema(
  {
    photoCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    videoCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    documentCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    intakePhotoCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    intakeVideoCount: {
      type: Number,
      default: 0,
      min: 0,
    },
    updatedAt: {
      type: Date,
      default: null,
    },
  },
  {
    _id: false,
    id: false,
  },
);

const requestInvoiceSchema = new mongoose.Schema(
  {
    kind: {
      type: String,
      enum: Object.values(REQUEST_REVIEW_KINDS),
      default: REQUEST_REVIEW_KINDS.QUOTATION,
    },
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
    quotedBaseAmount: {
      type: Number,
      required: true,
      min: 0,
    },
    appServiceChargePercent: {
      type: Number,
      required: true,
      min: 0,
      max: 100,
    },
    appServiceChargeAmount: {
      type: Number,
      required: true,
      min: 0,
    },
    adminServiceChargePercent: {
      type: Number,
      required: true,
      min: PRICING_RULES.ADMIN_SERVICE_CHARGE_MIN_PERCENT,
      max: PRICING_RULES.ADMIN_SERVICE_CHARGE_MAX_PERCENT,
    },
    adminServiceChargeAmount: {
      type: Number,
      required: true,
      min: 0,
    },
    currency: {
      type: String,
      default: "EUR",
      trim: true,
    },
    dueDate: {
      type: Date,
      default: null,
    },
    proofUploadDeadlineAt: {
      type: Date,
      default: null,
    },
    proofUploadUnlockedAt: {
      type: Date,
      default: null,
    },
    proofUploadUnlockedByRole: {
      type: String,
      enum: [USER_ROLES.STAFF],
      default: null,
    },
    proofUploadUnlockedById: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      default: null,
    },
    siteReviewDate: {
      type: Date,
      default: null,
    },
    siteReviewStartTime: {
      type: String,
      default: '',
      trim: true,
    },
    siteReviewEndTime: {
      type: String,
      default: '',
      trim: true,
    },
    siteReviewNotes: {
      type: String,
      default: '',
      trim: true,
    },
    plannedStartDate: {
      type: Date,
      default: null,
    },
    plannedStartTime: {
      type: String,
      default: '',
      trim: true,
    },
    plannedEndTime: {
      type: String,
      default: '',
      trim: true,
    },
    plannedHoursPerDay: {
      type: Number,
      default: null,
      min: 0,
      max: 10,
    },
    plannedExpectedEndDate: {
      type: Date,
      default: null,
    },
    plannedDailySchedule: {
      type: [plannedWorkDaySchema],
      default: [],
    },
    paymentMethod: {
      type: String,
      enum: Object.values(PAYMENT_METHODS),
      required: true,
    },
    paymentInstructions: {
      type: String,
      default: "",
      trim: true,
    },
    note: {
      type: String,
      default: "",
      trim: true,
    },
    status: {
      type: String,
      enum: Object.values(
        PAYMENT_REQUEST_STATUSES,
      ),
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
      ref: "User",
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
      ref: "User",
      default: null,
    },
    reviewNote: {
      type: String,
      default: "",
      trim: true,
    },
    paymentProvider: {
      type: String,
      default: null,
      trim: true,
    },
    paymentLinkUrl: {
      type: String,
      default: null,
      trim: true,
    },
    providerPaymentId: {
      type: String,
      default: null,
      trim: true,
    },
    paymentReference: {
      type: String,
      default: null,
      trim: true,
    },
    paidAt: {
      type: Date,
      default: null,
    },
    providerReceiptUrl: {
      type: String,
      default: null,
      trim: true,
    },
    receiptNumber: {
      type: String,
      default: null,
      trim: true,
    },
    receiptRelativeUrl: {
      type: String,
      default: null,
      trim: true,
    },
    receiptIssuedAt: {
      type: Date,
      default: null,
    },
    receiptTemplateVersion: {
      type: Number,
      default: null,
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

const quoteReviewSchema = new mongoose.Schema(
  {
    kind: {
      type: String,
      enum: Object.values(REQUEST_REVIEW_KINDS),
      default: REQUEST_REVIEW_KINDS.QUOTATION,
    },
    quotedBaseAmount: {
      type: Number,
      required: true,
      min: 0,
    },
    appServiceChargePercent: {
      type: Number,
      required: true,
      min: 0,
      max: 100,
    },
    appServiceChargeAmount: {
      type: Number,
      required: true,
      min: 0,
    },
    adminServiceChargePercent: {
      type: Number,
      required: true,
      min: PRICING_RULES.ADMIN_SERVICE_CHARGE_MIN_PERCENT,
      max: PRICING_RULES.ADMIN_SERVICE_CHARGE_MAX_PERCENT,
    },
    adminServiceChargeAmount: {
      type: Number,
      required: true,
      min: 0,
    },
    totalAmount: {
      type: Number,
      required: true,
      min: 0,
    },
    currency: {
      type: String,
      default: 'EUR',
      trim: true,
    },
    selectedEstimationId: {
      type: mongoose.Schema.Types.ObjectId,
      default: null,
    },
    dueDate: {
      type: Date,
      default: null,
    },
    siteReviewDate: {
      type: Date,
      default: null,
    },
    siteReviewStartTime: {
      type: String,
      default: '',
      trim: true,
    },
    siteReviewEndTime: {
      type: String,
      default: '',
      trim: true,
    },
    siteReviewNotes: {
      type: String,
      default: '',
      trim: true,
    },
    plannedStartDate: {
      type: Date,
      default: null,
    },
    plannedStartTime: {
      type: String,
      default: '',
      trim: true,
    },
    plannedEndTime: {
      type: String,
      default: '',
      trim: true,
    },
    plannedHoursPerDay: {
      type: Number,
      default: null,
      min: 0,
      max: 10,
    },
    plannedExpectedEndDate: {
      type: Date,
      default: null,
    },
    plannedDailySchedule: {
      type: [plannedWorkDaySchema],
      default: [],
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
    reviewedAt: {
      type: Date,
      default: Date.now,
    },
    reviewedByRole: {
      type: String,
      enum: [USER_ROLES.ADMIN],
      required: true,
    },
    reviewedById: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    reviewedByName: {
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

const requestEstimationSchema = new mongoose.Schema(
  {
    submittedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    submitterRole: {
      type: String,
      enum: [USER_ROLES.STAFF],
      default: USER_ROLES.STAFF,
    },
    submitterStaffType: {
      type: String,
      enum: Object.values(STAFF_TYPES),
      default: STAFF_TYPES.TECHNICIAN,
    },
    assignmentType: {
      type: String,
      enum: ['internal', 'external'],
      default: 'internal',
    },
    stage: {
      type: String,
      enum: Object.values(REQUEST_ESTIMATION_STAGES),
      default: REQUEST_ESTIMATION_STAGES.FINAL,
    },
    estimatedStartDate: {
      type: Date,
      default: null,
    },
    estimatedEndDate: {
      type: Date,
      default: null,
    },
    estimatedHours: {
      type: Number,
      default: null,
      min: 0,
    },
    estimatedHoursPerDay: {
      type: Number,
      default: null,
      min: 0,
      max: 10,
    },
    estimatedDays: {
      type: Number,
      default: null,
      min: 0,
    },
    estimatedDailySchedule: {
      type: [plannedWorkDaySchema],
      default: [],
    },
    cost: {
      type: Number,
      default: null,
      min: 0,
    },
    note: {
      type: String,
      default: '',
      trim: true,
    },
    inspectionNote: {
      type: String,
      default: '',
      trim: true,
    },
    siteReviewDate: {
      type: Date,
      default: null,
    },
    siteReviewStartTime: {
      type: String,
      default: '',
      trim: true,
    },
    siteReviewEndTime: {
      type: String,
      default: '',
      trim: true,
    },
    siteReviewNotes: {
      type: String,
      default: '',
      trim: true,
    },
    siteReviewCost: {
      type: Number,
      default: null,
      min: 0,
    },
    submittedAt: {
      type: Date,
      default: Date.now,
    },
  },
  {
    _id: true,
    id: false,
  },
);

const requestWorkLogSchema = new mongoose.Schema(
  {
    actorId: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    actorRole: {
      type: String,
      enum: [USER_ROLES.ADMIN, USER_ROLES.STAFF],
      required: true,
    },
    workType: {
      // WHY: Site-review attendance and main-job attendance need separate reporting in the request brief.
      type: String,
      enum: [
        REQUEST_WORK_LOG_TYPES.SITE_REVIEW,
        REQUEST_WORK_LOG_TYPES.MAIN_JOB,
      ],
      default: REQUEST_WORK_LOG_TYPES.MAIN_JOB,
    },
    startedAt: {
      type: Date,
      required: true,
    },
    stoppedAt: {
      type: Date,
      default: null,
    },
    note: {
      type: String,
      default: '',
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
      ref: "User",
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
      default: "",
      trim: true,
    },
    accessDetails: {
      type: accessDetailsSchema,
      default: null,
    },
    mediaSummary: {
      type: requestMediaSummarySchema,
      default: () => ({}),
    },
    assessmentType: {
      type: String,
      enum: Object.values(REQUEST_ASSESSMENT_TYPES),
      default: null,
    },
    assessmentStatus: {
      type: String,
      enum: Object.values(REQUEST_ASSESSMENT_STATUSES),
      default: REQUEST_ASSESSMENT_STATUSES.AWAITING_REVIEW,
    },
    quoteReadinessStatus: {
      type: String,
      enum: Object.values(REQUEST_QUOTE_READINESS_STATUSES),
      default: REQUEST_QUOTE_READINESS_STATUSES.AWAITING_ESTIMATE,
    },
    latestEstimateUpdatedAt: {
      type: Date,
      default: null,
    },
    internalReviewUpdatedAt: {
      type: Date,
      default: null,
    },
    quoteReadyAt: {
      type: Date,
      default: null,
    },
    quoteReview: {
      type: quoteReviewSchema,
      default: null,
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
        default: "",
      },
    },
    assignedStaff: {
      // WHY: Keep direct assignee lookup cheap because dashboards and staff inboxes depend on it often.
      type: mongoose.Schema.Types.ObjectId,
      ref: "User",
      default: null,
      index: true,
    },
    estimations: {
      // WHY: Scheduling, quotation validation, and the shared calendar all depend on structured estimate submissions.
      type: [requestEstimationSchema],
      default: [],
    },
    selectedEstimationId: {
      // WHY: Customer care can review multiple estimates but only one selected estimate should drive the quotation and calendar slot.
      type: mongoose.Schema.Types.ObjectId,
      default: null,
    },
    aiControlEnabled: {
      // WHY: Staff can hand the thread back to Naima temporarily without dropping the direct staff assignment.
      type: Boolean,
      default: false,
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
    workLogs: {
      // WHY: Planned-vs-actual reporting needs persisted start/stop entries rather than inferring labor from status only.
      type: [requestWorkLogSchema],
      default: [],
    },
  },
  {
    timestamps: true,
  },
);

// Inbox queries are driven by status and recency, so both should be indexed together.
serviceRequestSchema.index({
  status: 1,
  createdAt: -1,
});
serviceRequestSchema.index({
  assignedStaff: 1,
  status: 1,
  createdAt: -1,
});
serviceRequestSchema.index({
  status: 1,
  assignedStaff: 1,
  queueEnteredAt: 1,
});

const ServiceRequest = mongoose.model(
  "ServiceRequest",
  serviceRequestSchema,
);

module.exports = { ServiceRequest };
