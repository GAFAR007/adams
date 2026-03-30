/**
 * WHAT: Defines request validators for customer registration and shared auth endpoints.
 * WHY: Auth payloads must be rejected early so invalid credentials never reach the service layer.
 * HOW: Use `express-validator` chains that match the backend auth contract exactly.
 */

const { body, param } = require('express-validator');

const { USER_ROLES } = require('../constants/app.constants');
const { optionalPhoneValidator } = require('./phone.validators');

const customerRegisterValidator = [
  body('firstName').trim().notEmpty().withMessage('First name is required'),
  body('lastName').trim().notEmpty().withMessage('Last name is required'),
  body('email').trim().isEmail().withMessage('A valid email is required'),
  optionalPhoneValidator,
  body('verificationToken')
    .trim()
    .notEmpty()
    .withMessage('A verified registration token is required'),
  body('password')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters long'),
];

const customerRegistrationCodeRequestValidator = [
  body('email').trim().isEmail().withMessage('A valid email is required'),
];

const customerRegistrationCodeVerifyValidator = [
  body('email').trim().isEmail().withMessage('A valid email is required'),
  body('code')
    .trim()
    .matches(/^\d{6}$/)
    .withMessage('A valid 6-digit verification code is required'),
];

const loginValidator = [
  body('email').trim().isEmail().withMessage('A valid email is required'),
  body('password').notEmpty().withMessage('Password is required'),
];

const demoAccountsValidator = [
  param('role')
    .isIn(Object.values(USER_ROLES))
    .withMessage('A valid auth role is required'),
];

module.exports = {
  customerRegisterValidator,
  customerRegistrationCodeRequestValidator,
  customerRegistrationCodeVerifyValidator,
  demoAccountsValidator,
  loginValidator,
};
