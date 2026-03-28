/**
 * WHAT: Defines the backend's structured application error type.
 * WHY: A shared error shape keeps controller responses safe and predictable for the frontend.
 * HOW: Capture HTTP status and the safe metadata needed by the error middleware.
 */

class AppError extends Error {
  constructor({
    message,
    statusCode = 500,
    classification = 'UNKNOWN_PROVIDER_ERROR',
    errorCode = 'UNEXPECTED_ERROR',
    resolutionHint = 'Try again later or contact support',
    step = 'SERVICE_FAIL',
  }) {
    // WHY: Preserve the standard Error behavior so stack traces still work in development.
    super(message);
    // WHY: Keep every extra property on the instance so middleware can emit a stable safe error contract.
    this.name = 'AppError';
    this.statusCode = statusCode;
    this.classification = classification;
    this.errorCode = errorCode;
    this.resolutionHint = resolutionHint;
    this.step = step;
  }
}

module.exports = { AppError };
