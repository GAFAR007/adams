/**
 * WHAT: Defines validators for unauthenticated public-site interactions.
 * WHY: The public booking assistant should reject malformed payloads before any AI call runs.
 * HOW: Validate the service-concierge request shape with `express-validator`.
 */

const { body } = require('express-validator');

const BOOKING_STEPS = Object.freeze([
  'service',
  'firstName',
  'lastName',
  'email',
  'phone',
  'password',
  'done',
]);

const publicServiceConciergeReplyValidator = [
  body('languageCode')
    .optional()
    .isIn(['en', 'de'])
    .withMessage('Language code must be en or de'),
  body('serviceKey')
    .optional()
    .trim()
    .isLength({ min: 1, max: 120 })
    .withMessage('Service key must be between 1 and 120 characters'),
  body('serviceName')
    .optional()
    .trim()
    .isLength({ min: 1, max: 160 })
    .withMessage('Service name must be between 1 and 160 characters'),
  body('firstName')
    .optional()
    .trim()
    .isLength({ min: 1, max: 120 })
    .withMessage('First name must be between 1 and 120 characters'),
  body('justCapturedStep')
    .isIn(BOOKING_STEPS)
    .withMessage('A valid captured step is required'),
  body('nextStep')
    .optional()
    .isIn(BOOKING_STEPS)
    .withMessage('Next step must be a valid booking step'),
  body('completedSteps')
    .optional()
    .isArray()
    .withMessage('Completed steps must be an array'),
  body('completedSteps.*')
    .optional()
    .isIn(BOOKING_STEPS)
    .withMessage('Completed steps contain an invalid value'),
];

module.exports = {
  BOOKING_STEPS,
  publicServiceConciergeReplyValidator,
};
