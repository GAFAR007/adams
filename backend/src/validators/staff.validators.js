/**
 * WHAT: Defines validators for invite-based staff registration and staff request updates.
 * WHY: Staff flows depend on trusted invite tokens and bounded status updates.
 * HOW: Validate tokens, passwords, request IDs, and the allowed status payload shape.
 */

const { body, param, query } = require('express-validator');
const {
  REQUEST_ASSESSMENT_STATUSES,
  REQUEST_ASSESSMENT_TYPES,
  REQUEST_ESTIMATION_STAGES,
  REQUEST_MESSAGE_ACTIONS,
} = require('../constants/app.constants');
const { optionalPhoneValidator } = require('./phone.validators');

const staffRegisterValidator = [
  body('inviteToken').trim().notEmpty().withMessage('Invite token is required'),
  body('firstName').trim().notEmpty().withMessage('First name is required'),
  body('lastName').trim().notEmpty().withMessage('Last name is required'),
  optionalPhoneValidator,
  body('password')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters long'),
];

const staffRequestFiltersValidator = [
  query('status').optional().trim().isString().withMessage('Status filter must be a string'),
];

const staffCalendarFiltersValidator = [
  query('start')
    .optional()
    .isISO8601()
    .withMessage('Calendar start must be a valid ISO date'),
  query('end')
    .optional()
    .isISO8601()
    .withMessage('Calendar end must be a valid ISO date'),
];

const staffUpdateAvailabilityValidator = [
  body('availability')
    .trim()
    .isIn(['online', 'offline'])
    .withMessage('Availability must be online or offline'),
];

const staffAttendQueueRequestValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
];

const staffUpdateRequestStatusValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('status').trim().notEmpty().withMessage('Status is required'),
  body('password')
    .optional()
    .trim()
    .isLength({ max: 200 })
    .withMessage('Password must be 200 characters or fewer'),
];

const staffSubmitRequestEstimationValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('assessmentType')
    .optional({ nullable: true })
    .trim()
    .isIn(Object.values(REQUEST_ASSESSMENT_TYPES))
    .withMessage('Assessment type must be remote review or site review required'),
  body('assessmentStatus')
    .optional({ nullable: true })
    .trim()
    .isIn(Object.values(REQUEST_ASSESSMENT_STATUSES))
    .withMessage('Assessment status is invalid'),
  body('stage')
    .optional({ nullable: true })
    .trim()
    .isIn(Object.values(REQUEST_ESTIMATION_STAGES))
    .withMessage('Estimate stage must be draft or final'),
  body('estimatedStartDate')
    .optional({ nullable: true })
    .isISO8601()
    .withMessage('Estimated start date must be a valid ISO date'),
  body('estimatedEndDate')
    .optional({ nullable: true })
    .isISO8601()
    .withMessage('Estimated end date must be a valid ISO date'),
  body('cost')
    .optional({ nullable: true })
    .isFloat({ gt: 0 })
    .withMessage('Estimated cost must be greater than zero'),
  body('estimatedHours')
    .optional({ nullable: true })
    .isFloat({ gt: 0 })
    .withMessage('Estimated hours must be greater than zero'),
  body('estimatedHoursPerDay')
    .optional({ nullable: true })
    .isFloat({ gt: 0, lte: 10 })
    .withMessage('Estimated hours per day must be between 1 and 10'),
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
  body('siteReviewCost')
    .optional({ nullable: true })
    .isFloat({ gt: 0 })
    .withMessage('Site review cost must be greater than zero'),
  body('estimatedDays')
    .optional({ nullable: true })
    .isInt({ gt: 0 })
    .withMessage('Estimated days must be greater than zero'),
  body('estimatedDailySchedule')
    .optional({ nullable: true })
    .isArray()
    .withMessage('Estimated daily schedule must be an array'),
  body('estimatedDailySchedule.*.date')
    .optional({ nullable: true })
    .isISO8601()
    .withMessage('Estimated workday date must be a valid ISO date'),
  body('estimatedDailySchedule.*.startTime')
    .optional({ nullable: true })
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/)
    .withMessage('Estimated workday start time must use HH:mm format'),
  body('estimatedDailySchedule.*.endTime')
    .optional({ nullable: true })
    .matches(/^([01]\d|2[0-3]):[0-5]\d$/)
    .withMessage('Estimated workday end time must use HH:mm format'),
  body('estimatedDailySchedule.*.hours')
    .optional({ nullable: true })
    .isFloat({ gt: 0, lte: 10 })
    .withMessage('Estimated workday hours must be between 1 and 10'),
  body('note')
    .optional()
    .trim()
    .isLength({ max: 2000 })
    .withMessage('Estimation note must be 2000 characters or fewer'),
  body('inspectionNote')
    .optional()
    .trim()
    .isLength({ max: 2000 })
    .withMessage('Inspection note must be 2000 characters or fewer'),
  body('siteReviewNotes')
    .optional()
    .trim()
    .isLength({ max: 2000 })
    .withMessage('Site review notes must be 2000 characters or fewer'),
];

const staffPostRequestMessageValidator = [
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

const staffSuggestRequestReplyValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('draft')
    .optional({ nullable: true })
    .isString()
    .withMessage('Draft must be text')
    .isLength({ max: 2000 })
    .withMessage('Draft must be 2000 characters or fewer'),
];

const staffUpdateRequestAiControlValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('enabled').isBoolean().withMessage('Enabled must be true or false'),
];

const staffClockRequestWorkValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('action')
    .trim()
    .isIn(['clock_in', 'clock_out'])
    .withMessage('Action must be clock_in or clock_out'),
  body('note')
    .optional()
    .trim()
    .isLength({ max: 500 })
    .withMessage('Clock note must be 500 characters or fewer'),
];

const staffUploadRequestAttachmentValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('caption')
    .optional()
    .trim()
    .isLength({ max: 500 })
    .withMessage('Attachment caption must be 500 characters or fewer'),
];

const staffCreateRequestInvoiceValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
];

const staffReviewPaymentProofValidator = [
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

const staffUnlockPaymentProofValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
];

module.exports = {
  staffAttendQueueRequestValidator,
  staffCalendarFiltersValidator,
  staffClockRequestWorkValidator,
  staffCreateRequestInvoiceValidator,
  staffPostRequestMessageValidator,
  staffSuggestRequestReplyValidator,
  staffRegisterValidator,
  staffRequestFiltersValidator,
  staffReviewPaymentProofValidator,
  staffUnlockPaymentProofValidator,
  staffSubmitRequestEstimationValidator,
  staffUpdateAvailabilityValidator,
  staffUploadRequestAttachmentValidator,
  staffUpdateRequestAiControlValidator,
  staffUpdateRequestStatusValidator,
};
