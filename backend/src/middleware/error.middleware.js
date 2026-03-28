/**
 * WHAT: Converts thrown backend errors into the safe API error contract.
 * WHY: Frontend flows need predictable error responses without stack traces or internal leakage.
 * HOW: Detect AppError instances, log the failure with context, and emit the normalized JSON payload.
 */

const { LOG_STEPS } = require('../constants/app.constants');
const { AppError } = require('../utils/app-error');
const { logError } = require('../utils/logger');

function errorMiddleware(error, req, res, next) {
  void next;

  // WHY: Normalize unknown exceptions so the client never receives raw stacks or internal object shapes.
  const safeError =
    error instanceof AppError
      ? error
      : new AppError({
          message: 'Something went wrong',
          statusCode: 500,
          classification: 'UNKNOWN_PROVIDER_ERROR',
          errorCode: 'UNEXPECTED_SERVER_ERROR',
          resolutionHint: 'Try again later or contact support',
          step: LOG_STEPS.CONTROLLER_RESPONSE_FAIL,
        });

  // WHY: Log the normalized failure payload once so operational traces and client responses stay aligned.
  logError({
    requestId: req.requestId || 'unknown-request',
    route: `${req.method} ${req.originalUrl}`,
    step: safeError.step || LOG_STEPS.CONTROLLER_RESPONSE_FAIL,
    layer: 'middleware',
    operation: 'ErrorResponse',
    intent: 'Return a safe error payload to the client',
    businessIdPresent: false,
    userRole: req.authUser?.role || 'anonymous',
    classification: safeError.classification,
    error_code: safeError.errorCode,
    resolution_hint: safeError.resolutionHint,
    message: safeError.message,
  });

  // WHY: Return the shared safe error contract instead of leaking framework or provider details.
  res.status(safeError.statusCode).json({
    message: safeError.message,
    classification: safeError.classification,
    error_code: safeError.errorCode,
    requestId: req.requestId || 'unknown-request',
    resolution_hint: safeError.resolutionHint,
  });
}

module.exports = { errorMiddleware };
