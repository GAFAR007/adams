/**
 * WHAT: Defines request validators for admin request assignment and staff invite endpoints.
 * WHY: Admin actions change workflow ownership, so their inputs must be strict and explicit.
 * HOW: Validate IDs, invite target details, and optional filters before admin controllers run.
 */

const { body, param, query } = require('express-validator');
const {
  PAYMENT_METHODS,
  PRICING_RULES,
  REQUEST_MESSAGE_ACTIONS,
  REQUEST_REVIEW_KINDS,
  STAFF_TYPES,
} = require('../constants/app.constants');
const { optionalPhoneValidator } = require('./phone.validators');

const adminRequestFiltersValidator = [
  query('status').optional().trim().isString().withMessage('Status filter must be a string'),
  query('assignedStaffId').optional().isMongoId().withMessage('Assigned staff filter must be a valid ID'),
  query('search').optional().trim().isString().withMessage('Search must be text'),
];

const adminCalendarFiltersValidator = [
  query('start')
    .optional()
    .isISO8601()
    .withMessage('Calendar start must be a valid ISO date'),
  query('end')
    .optional()
    .isISO8601()
    .withMessage('Calendar end must be a valid ISO date'),
];

const adminAssignRequestValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('staffId').isMongoId().withMessage('Staff ID is required'),
];

const adminSelectRequestEstimationValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('estimationId').isMongoId().withMessage('Estimation ID is required'),
];

const adminDeleteStaffInviteValidator = [
  param('inviteId').isMongoId().withMessage('Invite ID must be valid'),
];

const adminCreateStaffInviteValidator = [
  body('firstName').trim().notEmpty().withMessage('First name is required'),
  body('lastName').trim().notEmpty().withMessage('Last name is required'),
  body('email').trim().isEmail().withMessage('A valid email is required'),
  body('staffType')
    .trim()
    .isIn(Object.values(STAFF_TYPES))
    .withMessage('Staff type must be customer care, technician, or contractor'),
  optionalPhoneValidator,
];

const adminCreateRequestInvoiceValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('amount')
    .optional({ nullable: true })
    .isFloat({ gt: 0 })
    .withMessage('Invoice amount must be greater than zero'),
  body('adminServiceChargePercent')
    .optional({ nullable: true })
    .custom((value, { req }) => {
      const numericValue = Number(value);
      const reviewKind =
        req.body.reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
          ? REQUEST_REVIEW_KINDS.SITE_REVIEW
          : REQUEST_REVIEW_KINDS.QUOTATION;
      const maximumPercent =
        reviewKind === REQUEST_REVIEW_KINDS.SITE_REVIEW
          ? PRICING_RULES.SITE_REVIEW_ADMIN_SERVICE_CHARGE_MAX_PERCENT
          : PRICING_RULES.ADMIN_SERVICE_CHARGE_MAX_PERCENT;

      return (
        Number.isFinite(numericValue) &&
        numericValue >= PRICING_RULES.ADMIN_SERVICE_CHARGE_MIN_PERCENT &&
        numericValue <= maximumPercent
      );
    })
    .withMessage('Admin service charge is outside the allowed range'),
  body('dueDate')
    .optional({ nullable: true })
    .isISO8601()
    .withMessage('Due date must be a valid ISO date'),
  body('reviewKind')
    .optional({ nullable: true })
    .trim()
    .isIn(Object.values(REQUEST_REVIEW_KINDS))
    .withMessage('Review kind is invalid'),
  body('siteReviewDate')
    .optional({ nullable: true })
    .isISO8601()
    .withMessage('Site review date must be a valid ISO date'),
  body('siteReviewStartTime')
    .optional({ nullable: true })
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/)
    .withMessage('Site review start time must use HH:mm format'),
  body('siteReviewEndTime')
    .optional({ nullable: true })
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/)
    .withMessage('Site review end time must use HH:mm format'),
  body('siteReviewNotes')
    .optional()
    .trim()
    .isLength({ max: 2000 })
    .withMessage('Site review notes must be 2000 characters or fewer'),
  body('plannedStartDate')
    .optional({ nullable: true })
    .isISO8601()
    .withMessage('Planned start date must be a valid ISO date'),
  body('plannedStartTime')
    .optional({ nullable: true })
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/)
    .withMessage('Planned start time must use HH:mm format'),
  body('plannedEndTime')
    .optional({ nullable: true })
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/)
    .withMessage('Planned end time must use HH:mm format'),
  body('plannedHoursPerDay')
    .optional({ nullable: true })
    .isFloat({ gt: 0, lte: 10 })
    .withMessage('Planned hours per day must be between 1 and 10'),
  body('plannedExpectedEndDate')
    .optional({ nullable: true })
    .isISO8601()
    .withMessage('Planned expected end date must be a valid ISO date'),
  body('plannedDailySchedule')
    .optional({ nullable: true })
    .isArray()
    .withMessage('Planned daily schedule must be an array'),
  body('plannedDailySchedule.*.date')
    .optional({ nullable: true })
    .isISO8601()
    .withMessage('Planned workday date must be a valid ISO date'),
  body('plannedDailySchedule.*.startTime')
    .optional({ nullable: true })
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/)
    .withMessage('Planned workday start time must use HH:mm format'),
  body('plannedDailySchedule.*.endTime')
    .optional({ nullable: true })
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/)
    .withMessage('Planned workday end time must use HH:mm format'),
  body('plannedDailySchedule.*.hours')
    .optional({ nullable: true })
    .isFloat({ gt: 0, lte: 10 })
    .withMessage('Planned workday hours must be between 1 and 10'),
  body('paymentMethod')
    .trim()
    .isIn(Object.values(PAYMENT_METHODS))
    .withMessage('Payment method is invalid'),
  body('paymentInstructions')
    .trim()
    .isLength({ min: 4, max: 2000 })
    .withMessage('Payment instructions must be between 4 and 2000 characters'),
  body('note')
    .optional()
    .trim()
    .isLength({ max: 2000 })
    .withMessage('Invoice note must be 2000 characters or fewer'),
];

const adminPostRequestMessageValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('message')
    .trim()
    .isLength({ min: 1, max: 2000 })
    .withMessage('Message must be between 1 and 2000 characters'),
  body('actionType')
    .optional({ nullable: true })
    .isIn(Object.values(REQUEST_MESSAGE_ACTIONS))
    .withMessage('Action type is invalid'),
];

const adminUploadRequestAttachmentValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('caption')
    .optional()
    .trim()
    .isLength({ max: 500 })
    .withMessage('Attachment caption must be 500 characters or fewer'),
];

const adminReviewPaymentProofValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('decision')
    .trim()
    .isIn(['approved', 'rejected'])
    .withMessage('Decision must be approved or rejected'),
  body('reviewNote')
    .optional()
    .trim()
    .isLength({ max: 500 })
    .withMessage('Review note must be 500 characters or fewer'),
];

module.exports = {
  adminAssignRequestValidator,
  adminCalendarFiltersValidator,
  adminCreateRequestInvoiceValidator,
  adminCreateStaffInviteValidator,
  adminDeleteStaffInviteValidator,
  adminPostRequestMessageValidator,
  adminRequestFiltersValidator,
  adminReviewPaymentProofValidator,
  adminSelectRequestEstimationValidator,
  adminUploadRequestAttachmentValidator,
};
