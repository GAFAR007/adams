/**
 * WHAT: Bootstraps the Express server and MongoDB connection for the backend API.
 * WHY: The backend needs a single startup entry that wires infrastructure before serving requests.
 * HOW: Load validated environment settings, connect MongoDB, create the app, and start listening.
 */

const http = require('http');

const {
  buildApp,
} = require("./src/app");
const {
  connectDatabase,
} = require("./src/config/database");
const {
  env,
} = require("./src/config/env");
const {
  logError,
  logInfo,
} = require("./src/utils/logger");
const {
  logFileStorageStatus,
} = require('./src/services/file-storage.service');
const {
  logEmailProviderStatus,
} = require('./src/services/email.service');
const {
  logAiProviderStatus,
} = require('./src/services/service-concierge.service');
const {
  logAddressValidationStatus,
} = require('./src/services/address-validation.service');
const {
  attachSocketServer,
} = require('./src/realtime/socket');

async function startServer() {
  // WHY: Refuse to accept traffic until the database is reachable.
  await connectDatabase();

  // WHY: Build the Express app only after core infrastructure is ready.
  const app = buildApp();
  const server = http.createServer(app);
  attachSocketServer(server);
  logFileStorageStatus();
  logEmailProviderStatus();
  logAiProviderStatus();
  logAddressValidationStatus();

  return server.listen(env.port, env.host, () => {
    // WHY: Emit the final startup checkpoint only when the process is actually listening.
    logInfo({
      requestId: "system",
      route: "SYSTEM START",
      step: "SERVICE_OK",
      layer: "system",
      operation: "ServerStart",
      intent:
        "Expose the API after infrastructure is ready",
      businessIdPresent: false,
      userRole: "system",
      host: env.host,
      port: env.port,
    });
  });
}

if (require.main === module) {
  startServer().catch((error) => {
    // WHY: Fail fast on startup so broken infra never leaves a half-booted API process running.
    logError({
      requestId: "system",
      route: "SYSTEM START",
      step: "SERVICE_FAIL",
      layer: "system",
      operation: "ServerStart",
      intent:
        "Fail fast when startup dependencies are unavailable",
      businessIdPresent: false,
      userRole: "system",
      classification:
        error.adamsClassification ||
        "UNKNOWN_PROVIDER_ERROR",
      error_code:
        error.adamsErrorCode ||
        "SERVER_START_FAILED",
      resolution_hint:
        error.adamsResolutionHint ||
        "Check environment variables and MongoDB availability",
      message: error.message,
    });
    process.exit(1);
  });
}

module.exports = { startServer };
