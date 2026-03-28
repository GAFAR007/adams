/**
 * WHAT: Converts `express-validator` results into the shared API error format.
 * WHY: Controllers should only run after request payloads meet the route contract.
 * HOW: Inspect validation results, classify the first issue, and short-circuit on invalid input.
 */

const { validationResult } = require('express-validator');

const { ERROR_CLASSIFICATIONS, LOG_STEPS } = require('../constants/app.constants');
const { AppError } = require('../utils/app-error');
const { buildRequestLog, logInfo } = require('../utils/logger');

function validateRequest(req, res, next) {
  void res;

  // WHY: Collect all validator results once so every controller gets the same input gate behavior.
  const errors = validationResult(req);

  if (!errors.isEmpty()) {
    // WHY: Report the first actionable issue to keep error messages focused for the UI.
    const [firstError] = errors.array();
    const message = firstError.msg || 'Invalid request payload';
    // WHY: Distinguish missing fields from generic invalid input so the frontend can respond more clearly.
    const classification = message.toLowerCase().includes('required')
      ? ERROR_CLASSIFICATIONS.MISSING_REQUIRED_FIELD
      : ERROR_CLASSIFICATIONS.INVALID_INPUT;

    throw new AppError({
      message,
      statusCode: 400,
      classification,
      errorCode: 'REQUEST_VALIDATION_FAILED',
      resolutionHint: 'Review the submitted fields and try again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  // WHY: Emit validation success here once so controllers do not repeat the same checkpoint manually.
  logInfo(
    buildRequestLog(req, {
      step: LOG_STEPS.VALIDATION_OK,
      layer: 'middleware',
      operation: 'ValidateRequest',
      intent: 'Confirm the request payload matches the route contract',
    }),
  );

  // WHY: Only continue when the request already matches the route contract.
  next();
}

module.exports = { validateRequest };
