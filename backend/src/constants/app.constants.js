/**
 * WHAT: Stores shared backend constants for roles, statuses, classifications, and service options.
 * WHY: Central constants prevent drift across validators, models, services, and frontend-facing payloads.
 * HOW: Export immutable enum-like objects and arrays that every backend layer can reference.
 *
 * flutter run -d chrome
 */

const USER_ROLES = Object.freeze({
  ADMIN: "admin",
  STAFF: "staff",
  CUSTOMER: "customer",
});

const USER_STATUSES = Object.freeze({
  ACTIVE: "active",
  INVITED: "invited",
  DISABLED: "disabled",
});

const STAFF_AVAILABILITIES = Object.freeze({
  ONLINE: "online",
  OFFLINE: "offline",
});

const STAFF_TYPES = Object.freeze({
  CUSTOMER_CARE: "customer_care",
  TECHNICIAN: "technician",
  CONTRACTOR: "contractor",
});

const REQUEST_STATUSES = Object.freeze({
  SUBMITTED: "submitted",
  UNDER_REVIEW: "under_review",
  ASSIGNED: "assigned",
  QUOTED: "quoted",
  APPOINTMENT_CONFIRMED: "appointment_confirmed",
  PENDING_START: "pending_start",
  PROJECT_STARTED: "project_started",
  WORK_DONE: "work_done",
  CLOSED: "closed",
});

const REQUEST_MESSAGE_SENDERS = Object.freeze({
  CUSTOMER: "customer",
  STAFF: "staff",
  ADMIN: "admin",
  SYSTEM: "system",
  AI: "ai",
});

const REQUEST_MESSAGE_ACTIONS = Object.freeze({
  CUSTOMER_UPDATE_REQUEST:
    "customer_update_request",
  CUSTOMER_UPDATE_REQUEST_CLEARED:
    "customer_update_request_cleared",
  CUSTOMER_UPLOAD_PAYMENT_PROOF:
    "customer_upload_payment_proof",
  ESTIMATE_UPDATED: "estimate_updated",
  // WHY: Booking a site review is a distinct customer-visible workflow event and should be addressable in thread consumers.
  SITE_REVIEW_BOOKED: "site_review_booked",
  SITE_REVIEW_READY_FOR_INTERNAL_REVIEW:
    "site_review_ready_for_internal_review",
  QUOTE_READY_FOR_INTERNAL_REVIEW:
    "quote_ready_for_internal_review",
  INTERNAL_REVIEW_UPDATED:
    "internal_review_updated",
  SITE_REVIEW_READY_FOR_CUSTOMER_CARE:
    "site_review_ready_for_customer_care",
  QUOTATION_READY_FOR_CUSTOMER_CARE:
    "quotation_ready_for_customer_care",
  QUOTATION_INVALIDATED: "quotation_invalidated",
  SITE_REVIEW_SENT: "site_review_sent",
  QUOTATION_SENT: "quotation_sent",
  PAYMENT_PROOF_UPLOAD_UNLOCKED:
    "payment_proof_upload_unlocked",
});

const REQUEST_ASSESSMENT_TYPES = Object.freeze({
  REMOTE_REVIEW: "remote_review",
  SITE_REVIEW_REQUIRED: "site_review_required",
});

const REQUEST_ASSESSMENT_STATUSES = Object.freeze(
  {
    AWAITING_REVIEW: "awaiting_review",
    AWAITING_CUSTOMER_MEDIA:
      "awaiting_customer_media",
    SITE_VISIT_REQUIRED: "site_visit_required",
    SITE_VISIT_SCHEDULED: "site_visit_scheduled",
    SITE_VISIT_COMPLETED: "site_visit_completed",
  },
);

const REQUEST_QUOTE_READINESS_STATUSES =
  Object.freeze({
    AWAITING_ESTIMATE: "awaiting_estimate",
    SITE_REVIEW_READY_FOR_INTERNAL_REVIEW:
      "site_review_ready_for_internal_review",
    SITE_REVIEW_READY_FOR_CUSTOMER_CARE:
      "site_review_ready_for_customer_care",
    QUOTE_READY_FOR_INTERNAL_REVIEW:
      "quote_ready_for_internal_review",
    QUOTE_READY_FOR_CUSTOMER_CARE:
      "quote_ready_for_customer_care",
    QUOTED: "quoted",
  });

const REQUEST_ESTIMATION_STAGES = Object.freeze({
  DRAFT: "draft",
  FINAL: "final",
});

const REQUEST_ACCESS_METHODS = Object.freeze({
  MEET_ON_SITE: "meet_on_site",
  RECEPTION_OR_CONCIERGE:
    "reception_or_concierge",
  KEY_SAFE: "key_safe",
  OPEN_ACCESS: "open_access",
  OTHER: "other",
});

const PAYMENT_METHODS = Object.freeze({
  SEPA_BANK_TRANSFER: "sepa_bank_transfer",
  CASH_ON_COMPLETION: "cash_on_completion",
  STRIPE_CHECKOUT: "stripe_checkout",
});

const PAYMENT_REQUEST_STATUSES = Object.freeze({
  SENT: "sent",
  PROOF_SUBMITTED: "proof_submitted",
  APPROVED: "approved",
  REJECTED: "rejected",
});

const PRICING_RULES = Object.freeze({
  APP_SERVICE_CHARGE_PERCENT: 5,
  ADMIN_SERVICE_CHARGE_MIN_PERCENT: 5,
  ADMIN_SERVICE_CHARGE_MAX_PERCENT: 50,
  ADMIN_SERVICE_CHARGE_DEFAULT_PERCENT: 5,
  SITE_REVIEW_ADMIN_SERVICE_CHARGE_MAX_PERCENT: 20,
  PAYMENT_PROOF_WINDOW_HOURS: 24,
});

const REQUEST_REVIEW_KINDS = Object.freeze({
  QUOTATION: "quotation",
  SITE_REVIEW: "site_review",
});

const REQUEST_WORK_LOG_TYPES = Object.freeze({
  SITE_REVIEW: "site_review",
  MAIN_JOB: "main_job",
});

const REQUEST_SOURCES = Object.freeze({
  FORM: "form",
  CHAT: "chat",
});

const SERVICE_TYPES = Object.freeze([
  "fire_damage_cleaning",
  "needle_sweeps_sharps_cleanups",
  "hoarding_cleanups",
  "trauma_decomposition_cleanups",
  "infection_control_cleaning",
  "building_cleaning",
  "window_cleaning",
  "office_cleaning",
  "house_cleaning",
  "warehouse_hall_cleaning",
  "window_glass_cleaning",
  "winter_service",
  "caretaker_service",
  "garden_care",
  "post_construction_cleaning",
]);

const ERROR_CLASSIFICATIONS = Object.freeze({
  INVALID_INPUT: "INVALID_INPUT",
  MISSING_REQUIRED_FIELD:
    "MISSING_REQUIRED_FIELD",
  COUNTRY_UNSUPPORTED: "COUNTRY_UNSUPPORTED",
  POSTAL_CODE_MISMATCH: "POSTAL_CODE_MISMATCH",
  PROVIDER_REJECTED_FORMAT:
    "PROVIDER_REJECTED_FORMAT",
  AUTHENTICATION_ERROR: "AUTHENTICATION_ERROR",
  RATE_LIMITED: "RATE_LIMITED",
  PROVIDER_OUTAGE: "PROVIDER_OUTAGE",
  UNKNOWN_PROVIDER_ERROR:
    "UNKNOWN_PROVIDER_ERROR",
});

const LOG_STEPS = Object.freeze({
  ROUTE_IN: "ROUTE_IN",
  AUTH_OK: "AUTH_OK",
  AUTH_FAIL: "AUTH_FAIL",
  VALIDATION_OK: "VALIDATION_OK",
  VALIDATION_FAIL: "VALIDATION_FAIL",
  SERVICE_START: "SERVICE_START",
  DB_QUERY_START: "DB_QUERY_START",
  DB_QUERY_OK: "DB_QUERY_OK",
  DB_QUERY_FAIL: "DB_QUERY_FAIL",
  PROVIDER_CALL_START: "PROVIDER_CALL_START",
  PROVIDER_CALL_OK: "PROVIDER_CALL_OK",
  PROVIDER_CALL_FAIL: "PROVIDER_CALL_FAIL",
  SERVICE_OK: "SERVICE_OK",
  SERVICE_FAIL: "SERVICE_FAIL",
  CONTROLLER_RESPONSE_OK:
    "CONTROLLER_RESPONSE_OK",
  CONTROLLER_RESPONSE_FAIL:
    "CONTROLLER_RESPONSE_FAIL",
});

module.exports = {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  REQUEST_ACCESS_METHODS,
  REQUEST_ASSESSMENT_STATUSES,
  REQUEST_ASSESSMENT_TYPES,
  REQUEST_ESTIMATION_STAGES,
  REQUEST_SOURCES,
  REQUEST_QUOTE_READINESS_STATUSES,
  REQUEST_REVIEW_KINDS,
  REQUEST_WORK_LOG_TYPES,
  REQUEST_STATUSES,
  REQUEST_MESSAGE_SENDERS,
  REQUEST_MESSAGE_ACTIONS,
  PAYMENT_METHODS,
  PAYMENT_REQUEST_STATUSES,
  PRICING_RULES,
  SERVICE_TYPES,
  STAFF_AVAILABILITIES,
  STAFF_TYPES,
  USER_ROLES,
  USER_STATUSES,
};
