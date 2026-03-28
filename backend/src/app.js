/**
 * WHAT: Builds the configured Express application for the backend API.
 * WHY: Keeping app creation separate from server startup makes the API testable and composable.
 * HOW: Register security, parsing, request context, routing, and terminal error handlers in order.
 */

const cookieParser = require('cookie-parser');
const cors = require('cors');
const express = require('express');
const helmet = require('helmet');

const { env } = require('./config/env');
const { notFoundMiddleware } = require('./middleware/not-found.middleware');
const { errorMiddleware } = require('./middleware/error.middleware');
const { requestContextMiddleware } = require('./middleware/request-context.middleware');
const { createApiRouter } = require('./routes');

function isLocalDevelopmentOrigin(origin) {
  // WHY: Local development uses random tooling ports, so allow browser origins broadly there to unblock iteration.
  return env.nodeEnv === 'development' && Boolean(origin);
}

function isAllowedCorsOrigin(origin) {
  if (!origin) {
    return true;
  }

  // WHY: In development, prefer iteration speed and let frontend tools connect from any local browser origin.
  if (isLocalDevelopmentOrigin(origin)) {
    return true;
  }

  // WHY: Prefer the explicit allowlist first so production-style deployments stay intentionally configured.
  if (env.corsOrigins.includes(origin)) {
    return true;
  }

  return false;
}

function buildCorsOptions() {
  return {
    origin(origin, callback) {
      // WHY: Non-browser tools may omit Origin, but browser clients still need an explicit CORS decision.
      if (isAllowedCorsOrigin(origin)) {
        callback(null, true);
        return;
      }

      // WHY: Reject unknown browser origins before cookies or protected routes are exposed cross-site.
      callback(new Error(`Origin ${origin} is not allowed by CORS`));
    },
    // WHY: Spell out supported methods so browser preflights do not have to infer the API contract.
    methods: ['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'OPTIONS'],
    // WHY: Reflect the headers our frontend actually sends during auth and dashboard requests.
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    // WHY: Expose the browser to the safe CORS response shape needed for cookie-backed auth flows.
    credentials: true,
    preflightContinue: false,
    optionsSuccessStatus: 204,
  };
}

function buildApp() {
  const app = express();
  const corsMiddleware = cors(buildCorsOptions());

  // WHY: Keep core security headers, but do not mark API responses as same-origin-only because the frontend is a separate origin in development.
  app.use(helmet({
    crossOriginResourcePolicy: false,
  }));
  // WHY: Log request entry before CORS so failed preflight and origin-rejection cases still appear in the terminal.
  app.use(requestContextMiddleware);
  // WHY: CORS needs to run before routes so browser clients fail early on disallowed origins.
  app.use(corsMiddleware);
  // WHY: Respond to browser preflight checks explicitly so cross-origin POST and PATCH calls can proceed.
  app.options(/.*/, corsMiddleware);
  // WHY: JSON parsing happens once globally so controllers receive a normalized body shape.
  app.use(express.json({ limit: '1mb' }));
  // WHY: Auth refresh relies on cookies, so parsing them must happen before auth controllers run.
  app.use(cookieParser());

  app.get('/health', (req, res) => {
    // WHY: Keep health checks dependency-light so infra can verify the process quickly.
    res.status(200).json({ message: 'Backend is healthy' });
  });

  // WHY: Mount all versioned API routes together so future versions can coexist cleanly.
  app.use('/api/v1', createApiRouter());
  // WHY: Missing-route handling must run after all known routes have had a chance to match.
  app.use(notFoundMiddleware);
  // WHY: The error middleware stays last so it can normalize failures from every earlier layer.
  app.use(errorMiddleware);

  return app;
}

module.exports = { buildApp };
