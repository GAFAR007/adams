/**
 * WHAT: Defines request validators for admin request assignment and staff invite endpoints.
 * WHY: Admin actions change workflow ownership, so their inputs must be strict and explicit.
 * HOW: Validate IDs, invite target details, and optional filters before admin controllers run.
 */

const { body, param, query } = require('express-validator');

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

module.exports = {
  adminAssignRequestValidator,
  adminCreateStaffInviteValidator,
  adminDeleteStaffInviteValidator,
  adminRequestFiltersValidator,
};
