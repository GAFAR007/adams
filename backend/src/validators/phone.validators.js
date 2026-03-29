/**
 * WHAT: Shared phone-field validator for request payloads.
 * WHY: Customer and staff flows should reject junk text while still allowing
 * common international phone formatting characters.
 * HOW: Allow only phone-like punctuation, then require at least 7 digits.
 */

const { body } = require('express-validator');

const PHONE_ALLOWED_CHARACTERS = /^[0-9+().\-\s]+$/;
const PHONE_MIN_DIGITS = 7;
const PHONE_ERROR_MESSAGE =
  'Phone number must be a valid phone number with at least 7 digits';

function looksLikePhoneNumber(value) {
  const normalized = String(value || '').trim();
  if (!normalized) {
    return false;
  }

  if (!PHONE_ALLOWED_CHARACTERS.test(normalized)) {
    return false;
  }

  const digitsOnly = normalized.replace(/\D/g, '');
  return digitsOnly.length >= PHONE_MIN_DIGITS;
}

const optionalPhoneValidator = body('phone')
  .optional({ checkFalsy: true })
  .trim()
  .custom((value) => {
    if (!looksLikePhoneNumber(value)) {
      throw new Error(PHONE_ERROR_MESSAGE);
    }

    return true;
  });

module.exports = {
  looksLikePhoneNumber,
  optionalPhoneValidator,
  PHONE_ERROR_MESSAGE,
};
