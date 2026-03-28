/**
 * WHAT: Defines validators for invite-based staff registration and staff request updates.
 * WHY: Staff flows depend on trusted invite tokens and bounded status updates.
 * HOW: Validate tokens, passwords, request IDs, and the allowed status payload shape.
 */

const { body, param, query } = require('express-validator');

const staffRegisterValidator = [
  body('inviteToken').trim().notEmpty().withMessage('Invite token is required'),
  body('firstName').trim().notEmpty().withMessage('First name is required'),
  body('lastName').trim().notEmpty().withMessage('Last name is required'),
  body('phone').optional().trim().isLength({ min: 7 }).withMessage('Phone number must be at least 7 characters'),
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
];

module.exports = {
  staffAttendQueueRequestValidator,
  staffPostRequestMessageValidator,
  staffRegisterValidator,
  staffRequestFiltersValidator,
  staffUpdateAvailabilityValidator,
  staffUpdateRequestStatusValidator,
};
