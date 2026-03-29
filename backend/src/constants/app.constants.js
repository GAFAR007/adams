/**
 * WHAT: Stores shared backend constants for roles, statuses, classifications, and service options.
 * WHY: Central constants prevent drift across validators, models, services, and frontend-facing payloads.
 * HOW: Export immutable enum-like objects and arrays that every backend layer can reference.
 */

const USER_ROLES = Object.freeze({
  ADMIN: 'admin',
  STAFF: 'staff',
  CUSTOMER: 'customer',
});

const USER_STATUSES = Object.freeze({
  ACTIVE: 'active',
  INVITED: 'invited',
  DISABLED: 'disabled',
});

const STAFF_AVAILABILITIES = Object.freeze({
  ONLINE: 'online',
  OFFLINE: 'offline',
});

const REQUEST_STATUSES = Object.freeze({
  SUBMITTED: 'submitted',
  UNDER_REVIEW: 'under_review',
  ASSIGNED: 'assigned',
  QUOTED: 'quoted',
  APPOINTMENT_CONFIRMED: 'appointment_confirmed',
  PENDING_START: 'pending_start',
  PROJECT_STARTED: 'project_started',
  WORK_DONE: 'work_done',
  CLOSED: 'closed',
});

const REQUEST_MESSAGE_SENDERS = Object.freeze({
  CUSTOMER: 'customer',
  STAFF: 'staff',
  ADMIN: 'admin',
  SYSTEM: 'system',
  AI: 'ai',
});

const REQUEST_MESSAGE_ACTIONS = Object.freeze({
  CUSTOMER_UPDATE_REQUEST: 'customer_update_request',
  CUSTOMER_UPLOAD_PAYMENT_PROOF: 'customer_upload_payment_proof',
});

const PAYMENT_METHODS = Object.freeze({
  SEPA_BANK_TRANSFER: 'sepa_bank_transfer',
  CASH_ON_COMPLETION: 'cash_on_completion',
  STRIPE_CHECKOUT: 'stripe_checkout',
});

const PAYMENT_REQUEST_STATUSES = Object.freeze({
  SENT: 'sent',
  PROOF_SUBMITTED: 'proof_submitted',
  APPROVED: 'approved',
  REJECTED: 'rejected',
});

const REQUEST_SOURCES = Object.freeze({
  FORM: 'form',
  CHAT: 'chat',
});

const SERVICE_TYPES = Object.freeze([
  'building_cleaning',
  'warehouse_hall_cleaning',
  'window_glass_cleaning',
  'winter_service',
  'caretaker_service',
  'garden_care',
  'post_construction_cleaning',
]);

const ERROR_CLASSIFICATIONS = Object.freeze({
  INVALID_INPUT: 'INVALID_INPUT',
  MISSING_REQUIRED_FIELD: 'MISSING_REQUIRED_FIELD',
  COUNTRY_UNSUPPORTED: 'COUNTRY_UNSUPPORTED',
  POSTAL_CODE_MISMATCH: 'POSTAL_CODE_MISMATCH',
  PROVIDER_REJECTED_FORMAT: 'PROVIDER_REJECTED_FORMAT',
  AUTHENTICATION_ERROR: 'AUTHENTICATION_ERROR',
  RATE_LIMITED: 'RATE_LIMITED',
  PROVIDER_OUTAGE: 'PROVIDER_OUTAGE',
  UNKNOWN_PROVIDER_ERROR: 'UNKNOWN_PROVIDER_ERROR',
});

const LOG_STEPS = Object.freeze({
  ROUTE_IN: 'ROUTE_IN',
  AUTH_OK: 'AUTH_OK',
  AUTH_FAIL: 'AUTH_FAIL',
  VALIDATION_OK: 'VALIDATION_OK',
  VALIDATION_FAIL: 'VALIDATION_FAIL',
  SERVICE_START: 'SERVICE_START',
  DB_QUERY_START: 'DB_QUERY_START',
  DB_QUERY_OK: 'DB_QUERY_OK',
  DB_QUERY_FAIL: 'DB_QUERY_FAIL',
  PROVIDER_CALL_START: 'PROVIDER_CALL_START',
  PROVIDER_CALL_OK: 'PROVIDER_CALL_OK',
  PROVIDER_CALL_FAIL: 'PROVIDER_CALL_FAIL',
  SERVICE_OK: 'SERVICE_OK',
  SERVICE_FAIL: 'SERVICE_FAIL',
  CONTROLLER_RESPONSE_OK: 'CONTROLLER_RESPONSE_OK',
  CONTROLLER_RESPONSE_FAIL: 'CONTROLLER_RESPONSE_FAIL',
});

module.exports = {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  REQUEST_SOURCES,
  REQUEST_STATUSES,
  REQUEST_MESSAGE_SENDERS,
  REQUEST_MESSAGE_ACTIONS,
  PAYMENT_METHODS,
  PAYMENT_REQUEST_STATUSES,
  SERVICE_TYPES,
  STAFF_AVAILABILITIES,
  USER_ROLES,
  USER_STATUSES,
};
