/**
 * WHAT: Applies a simple in-memory rate limit to authentication-sensitive endpoints.
 * WHY: Login and token routes need a first-line defense against brute-force abuse in v1.
 * HOW: Track request timestamps by IP and route, then reject callers that exceed the configured window.
 */

const { ERROR_CLASSIFICATIONS, LOG_STEPS } = require('../constants/app.constants');
const { env } = require('../config/env');
const { AppError } = require('../utils/app-error');

const bucketStore = new Map();

function createAuthRateLimitMiddleware() {
  return function authRateLimitMiddleware(req, res, next) {
    void res;

    const now = Date.now();
    // WHY: Rate-limit by caller IP and route so one noisy auth path does not block unrelated endpoints.
    const key = `${req.ip}:${req.baseUrl}${req.path}`;
    const bucket = bucketStore.get(key) || [];
    // WHY: Drop expired timestamps on every request to keep the in-memory bucket aligned to the active window.
    const validEntries = bucket.filter((timestamp) => now - timestamp < env.authRateLimitWindowMs);

    if (validEntries.length >= env.authRateLimitMaxAttempts) {
      throw new AppError({
        message: 'Too many authentication attempts',
        statusCode: 429,
        classification: ERROR_CLASSIFICATIONS.RATE_LIMITED,
        errorCode: 'AUTH_RATE_LIMIT_EXCEEDED',
        resolutionHint: 'Wait briefly before trying again',
        step: LOG_STEPS.AUTH_FAIL,
      });
    }

    // WHY: Record the accepted attempt after the guard so future requests see the updated count.
    validEntries.push(now);
    bucketStore.set(key, validEntries);

    next();
  };
}

module.exports = { createAuthRateLimitMiddleware };
