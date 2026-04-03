/**
 * WHAT: Manages the MongoDB connection for the backend.
 * WHY: Database startup logic should live in one place so failures are observable and easy to change.
 * HOW: Configure Mongoose once, open the connection, and emit structured startup logs.
 */

const mongoose = require('mongoose');

const { env } = require('./env');
const { logError, logInfo } = require('../utils/logger');

function classifyMongoConnectionFailure(error) {
  const message = String(error?.message || '');
  const isSrvUri = String(
    env.mongoDbUri || '',
  ).startsWith('mongodb+srv://');

  if (
    isSrvUri &&
    /query(?:Srv|Txt)\s+ETIMEOUT/i.test(
      message,
    )
  ) {
    return {
      classification:
        'NETWORK_DNS_FAILURE',
      errorCode:
        'MONGODB_ATLAS_DNS_TIMEOUT',
      resolutionHint:
        'Atlas DNS SRV/TXT lookup timed out. Check DNS/VPN/network access, or replace MONGODB_URI with the non-SRV mongodb:// connection string from Atlas Drivers.',
    };
  }

  if (
    isSrvUri &&
    /query(?:Srv|Txt)\s+(?:ENOTFOUND|EAI_AGAIN)/i.test(
      message,
    )
  ) {
    return {
      classification:
        'NETWORK_DNS_FAILURE',
      errorCode:
        'MONGODB_ATLAS_DNS_LOOKUP_FAILED',
      resolutionHint:
        'Atlas DNS SRV/TXT lookup failed. Check DNS resolution on this machine, or replace MONGODB_URI with the non-SRV mongodb:// connection string from Atlas Drivers.',
    };
  }

  if (/ECONNREFUSED/i.test(message)) {
    return {
      classification:
        'PROVIDER_OUTAGE',
      errorCode:
        'MONGODB_CONNECT_REFUSED',
      resolutionHint:
        'MongoDB refused the connection. Start MongoDB locally or verify the target host and port in MONGODB_URI.',
    };
  }

  return {
    classification:
      'PROVIDER_OUTAGE',
    errorCode:
      'MONGODB_CONNECT_FAILED',
    resolutionHint:
      'Start MongoDB locally or update MONGODB_URI',
  };
}

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
    const failure = classifyMongoConnectionFailure(
      error,
    );

    error.adamsClassification =
      failure.classification;
    error.adamsErrorCode =
      failure.errorCode;
    error.adamsResolutionHint =
      failure.resolutionHint;

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
      classification:
        failure.classification,
      error_code: failure.errorCode,
      resolution_hint:
        failure.resolutionHint,
      message: error.message,
    });

    throw error;
  }
}

module.exports = { connectDatabase };
