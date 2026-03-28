/**
 * WHAT: Defines request validators for customer registration and shared auth endpoints.
 * WHY: Auth payloads must be rejected early so invalid credentials never reach the service layer.
 * HOW: Use `express-validator` chains that match the backend auth contract exactly.
 */

const { body } = require('express-validator');

const customerRegisterValidator = [
  body('firstName').trim().notEmpty().withMessage('First name is required'),
  body('lastName').trim().notEmpty().withMessage('Last name is required'),
  body('email').trim().isEmail().withMessage('A valid email is required'),
  body('phone').optional().trim().isLength({ min: 7 }).withMessage('Phone number must be at least 7 characters'),
  body('password')
    .isLength({ min: 8 })
    .withMessage('Password must be at least 8 characters long'),
];

const loginValidator = [
  body('email').trim().isEmail().withMessage('A valid email is required'),
  body('password').notEmpty().withMessage('Password is required'),
];

module.exports = {
  customerRegisterValidator,
  loginValidator,
};
