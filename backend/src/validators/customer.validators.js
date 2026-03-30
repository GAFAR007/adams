/**
 * WHAT: Defines validators for customer-owned service request actions.
 * WHY: Customer request payloads need a strict shape before they become operational work items.
 * HOW: Validate service type, location fields, and free-text request context at the controller boundary.
 */

const { body, param, query } = require('express-validator');

const customerRequestFieldsValidator = [
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

const customerCreateRequestValidator = [...customerRequestFieldsValidator];

const customerVerifyAddressValidator = [
  body('addressLine1')
    .trim()
    .isLength({ min: 5, max: 240 })
    .withMessage('Address line must be between 5 and 240 characters'),
  body('placeId')
    .optional()
    .trim()
    .isLength({ min: 1, max: 255 })
    .withMessage('Place ID must be between 1 and 255 characters'),
];

const customerAutocompleteAddressValidator = [
  query('input')
    .trim()
    .isLength({ min: 3, max: 240 })
    .withMessage('Address search input must be between 3 and 240 characters'),
];

const customerUpdateRequestValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  ...customerRequestFieldsValidator,
];

const customerPostRequestMessageValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('message')
    .trim()
    .isLength({ min: 1, max: 2000 })
    .withMessage('Message must be between 1 and 2000 characters'),
];

const customerUploadPaymentProofValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('note')
    .optional()
    .trim()
    .isLength({ max: 500 })
    .withMessage('Proof note must be 500 characters or fewer'),
];

const customerUploadRequestAttachmentValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('caption')
    .optional()
    .trim()
    .isLength({ max: 500 })
    .withMessage('Attachment caption must be 500 characters or fewer'),
];

const customerReplaceRequestAttachmentValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  param('messageId').isMongoId().withMessage('Message ID must be valid'),
];

module.exports = {
  customerAutocompleteAddressValidator,
  customerCreateRequestValidator,
  customerPostRequestMessageValidator,
  customerReplaceRequestAttachmentValidator,
  customerUploadPaymentProofValidator,
  customerUploadRequestAttachmentValidator,
  customerUpdateRequestValidator,
  customerVerifyAddressValidator,
};
