/**
 * WHAT: Defines validators for invite-based staff registration and staff request updates.
 * WHY: Staff flows depend on trusted invite tokens and bounded status updates.
 * HOW: Validate tokens, passwords, request IDs, and the allowed status payload shape.
 */

const { body, param, query } = require('express-validator');
const {
  PAYMENT_METHODS,
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

const staffUpdateRequestAiControlValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('enabled').isBoolean().withMessage('Enabled must be true or false'),
];

const staffCreateRequestInvoiceValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('amount')
    .isFloat({ gt: 0 })
    .withMessage('Invoice amount must be greater than zero'),
  body('dueDate')
    .optional({ nullable: true })
    .isISO8601()
    .withMessage('Due date must be a valid ISO date'),
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

module.exports = {
  staffAttendQueueRequestValidator,
  staffCreateRequestInvoiceValidator,
  staffPostRequestMessageValidator,
  staffRegisterValidator,
  staffRequestFiltersValidator,
  staffReviewPaymentProofValidator,
  staffUpdateAvailabilityValidator,
  staffUpdateRequestAiControlValidator,
  staffUpdateRequestStatusValidator,
};
