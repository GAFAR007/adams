/**
 * WHAT: Defines validators for customer-owned service request actions.
 * WHY: Customer request payloads need a strict shape before they become operational work items.
 * HOW: Validate service type, location fields, and free-text request context at the controller boundary.
 */

const { body, param, query } = require('express-validator');
const { REQUEST_ACCESS_METHODS } = require('../constants/app.constants');

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

const requiredAccessDetailsValidator = [
  body('accessMethod')
    .trim()
    .isIn(Object.values(REQUEST_ACCESS_METHODS))
    .withMessage('Access method is required'),
  body('arrivalContactName')
    .trim()
    .isLength({ min: 2, max: 120 })
    .withMessage('Arrival contact name is required'),
  body('arrivalContactPhone')
    .trim()
    .isLength({ min: 5, max: 40 })
    .withMessage('Arrival contact phone is required'),
  body('accessNotes')
    .trim()
    .isLength({ min: 5, max: 1000 })
    .withMessage('Access notes are required'),
];

const optionalAccessDetailsValidator = [
  body('accessMethod')
    .optional({ nullable: true })
    .trim()
    .isIn(Object.values(REQUEST_ACCESS_METHODS))
    .withMessage('Access method is invalid'),
  body('arrivalContactName')
    .optional({ nullable: true })
    .trim()
    .isLength({ min: 2, max: 120 })
    .withMessage('Arrival contact name must be between 2 and 120 characters'),
  body('arrivalContactPhone')
    .optional({ nullable: true })
    .trim()
    .isLength({ min: 5, max: 40 })
    .withMessage('Arrival contact phone must be between 5 and 40 characters'),
  body('accessNotes')
    .optional({ nullable: true })
    .trim()
    .isLength({ min: 5, max: 1000 })
    .withMessage('Access notes must be between 5 and 1000 characters'),
];

const customerCreateRequestValidator = [
  ...customerRequestFieldsValidator,
  ...requiredAccessDetailsValidator,
];

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
  ...optionalAccessDetailsValidator,
];

const customerPostRequestMessageValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('message')
    .trim()
    .isLength({ min: 1, max: 2000 })
    .withMessage('Message must be between 1 and 2000 characters'),
];

const customerSuggestRequestReplyValidator = [
  param('requestId').isMongoId().withMessage('Request ID must be valid'),
  body('draft')
    .optional({ nullable: true })
    .isString()
    .withMessage('Draft must be text')
    .isLength({ max: 2000 })
    .withMessage('Draft must be 2000 characters or fewer'),
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
  customerSuggestRequestReplyValidator,
  customerReplaceRequestAttachmentValidator,
  customerUploadPaymentProofValidator,
  customerUploadRequestAttachmentValidator,
  customerUpdateRequestValidator,
  customerVerifyAddressValidator,
};
