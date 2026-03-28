/**
 * WHAT: Defines validators for customer-owned service request actions.
 * WHY: Customer request payloads need a strict shape before they become operational work items.
 * HOW: Validate service type, location fields, and free-text request context at the controller boundary.
 */

const { body, param } = require('express-validator');

const customerCreateRequestValidator = [
  body('serviceType').trim().notEmpty().withMessage('Service type is required'),
  body('addressLine1').trim().notEmpty().withMessage('Address line is required'),
  body('city').trim().notEmpty().withMessage('City is required'),
  body('postalCode').trim().notEmpty().withMessage('Postal code is required'),
  body('preferredDate').optional().isISO8601().withMessage('Preferred date must be a valid ISO date'),
  body('preferredTimeWindow').optional().trim().isString().withMessage('Preferred time window must be text'),
  body('message')
    .trim()
    .isLength({ min: 10 })
    .withMessage('Message must be at least 10 characters long'),
];

const customerPostRequestMessageValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('message')
    .trim()
    .isLength({ min: 1, max: 2000 })
    .withMessage('Message must be between 1 and 2000 characters'),
];

module.exports = {
  customerCreateRequestValidator,
  customerPostRequestMessageValidator,
};
