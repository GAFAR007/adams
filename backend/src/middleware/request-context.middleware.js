/**
 * WHAT: Attaches per-request context like request IDs and initial route logs.
 * WHY: Every later log entry needs a shared request identifier and request metadata.
 * HOW: Generate the ID early, store it on the request, and emit the ROUTE_IN checkpoint immediately.
 */

const { randomUUID } = require('crypto');

const { LOG_STEPS } = require('../constants/app.constants');
const { logInfo } = require('../utils/logger');

function requestContextMiddleware(req, res, next) {
  // WHY: Reuse caller-provided request IDs when present so upstream tools can trace the same request.
  req.requestId = req.headers['x-request-id'] || randomUUID();

  // WHY: Emit the first checkpoint immediately so every later log can be tied back to request entry.
  logInfo({
    requestId: req.requestId,
    route: `${req.method} ${req.originalUrl}`,
    step: LOG_STEPS.ROUTE_IN,
    layer: 'middleware',
    operation: 'RequestEntry',
    intent: 'Accept and trace the inbound API request',
    businessIdPresent: false,
    userRole: 'anonymous',
  });

  next();
}

module.exports = { requestContextMiddleware };
