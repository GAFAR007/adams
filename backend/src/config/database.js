/**
 * WHAT: Manages the MongoDB connection for the backend.
 * WHY: Database startup logic should live in one place so failures are observable and easy to change.
 * HOW: Configure Mongoose once, open the connection, and emit structured startup logs.
 */

const mongoose = require('mongoose');

const { env } = require('./env');
const { logError, logInfo } = require('../utils/logger');

async function connectDatabase() {
  // WHY: Keep Mongoose query behavior predictable so filters do not silently accept unknown keys.
  mongoose.set('strictQuery', true);

  logInfo({
    requestId: 'system',
    route: 'SYSTEM DB',
    step: 'DB_QUERY_START',
    layer: 'config',
    operation: 'DatabaseConnect',
    intent: 'Connect MongoDB before serving requests',
    businessIdPresent: false,
    userRole: 'system',
  });

  try {
    // WHY: Use the single validated URI from config so all environments connect consistently.
    await mongoose.connect(env.mongoDbUri);

    logInfo({
      requestId: 'system',
      route: 'SYSTEM DB',
      step: 'DB_QUERY_OK',
      layer: 'config',
      operation: 'DatabaseConnect',
      intent: 'Confirm MongoDB availability for the API',
      businessIdPresent: false,
      userRole: 'system',
    });
  } catch (error) {
    // WHY: Log the precise startup failure once here before handing the fatal error back to boot logic.
    logError({
      requestId: 'system',
      route: 'SYSTEM DB',
      step: 'DB_QUERY_FAIL',
      layer: 'config',
      operation: 'DatabaseConnect',
      intent: 'Fail startup when MongoDB cannot be reached',
      businessIdPresent: false,
      userRole: 'system',
      classification: 'PROVIDER_OUTAGE',
      error_code: 'MONGODB_CONNECT_FAILED',
      resolution_hint: 'Start MongoDB locally or update MONGODB_URI',
      message: error.message,
    });

    throw error;
  }
}

module.exports = { connectDatabase };
