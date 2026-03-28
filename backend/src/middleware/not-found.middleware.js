/**
 * WHAT: Handles unmatched routes with the shared error contract.
 * WHY: A controlled 404 response keeps missing-route failures consistent with the rest of the API.
 * HOW: Convert unknown routes into an AppError and pass it into the main error middleware.
 */

const { AppError } = require('../utils/app-error');

function notFoundMiddleware(req, res, next) {
  void res;

  // WHY: Convert unknown routes into the shared AppError shape so 404s follow the same API contract.
  next(
    new AppError({
      message: 'Route not found',
      statusCode: 404,
      classification: 'INVALID_INPUT',
      errorCode: 'ROUTE_NOT_FOUND',
      resolutionHint: 'Check the API path and HTTP method',
      step: 'CONTROLLER_RESPONSE_FAIL',
    }),
  );
}

module.exports = { notFoundMiddleware };
