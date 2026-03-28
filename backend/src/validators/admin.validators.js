/**
 * WHAT: Defines request validators for admin request assignment and staff invite endpoints.
 * WHY: Admin actions change workflow ownership, so their inputs must be strict and explicit.
 * HOW: Validate IDs, invite target details, and optional filters before admin controllers run.
 */

const { body, param, query } = require('express-validator');
const { PAYMENT_METHODS } = require('../constants/app.constants');

const adminRequestFiltersValidator = [
  query('status').optional().trim().isString().withMessage('Status filter must be a string'),
  query('assignedStaffId').optional().isMongoId().withMessage('Assigned staff filter must be a valid ID'),
  query('search').optional().trim().isString().withMessage('Search must be text'),
];

const adminAssignRequestValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('staffId').isMongoId().withMessage('Staff ID is required'),
];

const adminDeleteStaffInviteValidator = [
  param('inviteId').isMongoId().withMessage('Invite ID must be valid'),
];

const adminCreateStaffInviteValidator = [
  body('firstName').trim().notEmpty().withMessage('First name is required'),
  body('lastName').trim().notEmpty().withMessage('Last name is required'),
  body('email').trim().isEmail().withMessage('A valid email is required'),
  body('phone').optional().trim().isLength({ min: 7 }).withMessage('Phone number must be at least 7 characters'),
];

const adminCreateRequestInvoiceValidator = [
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
  adminCreateRequestInvoiceValidator,
  adminCreateStaffInviteValidator,
  adminDeleteStaffInviteValidator,
  adminRequestFiltersValidator,
  adminReviewPaymentProofValidator,
};
