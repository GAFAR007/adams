/**
 * WHAT: Stores request-thread attachments and payment-proof files in Cloudinary or local fallback storage.
 * WHY: Customer, staff, and admin uploads should share one storage path instead of duplicating disk-only assumptions.
 * HOW: Accept Multer memory files, upload to Cloudinary when configured, and return one normalized stored-file shape.
 */

const { createHash, randomUUID } = require('crypto');
const fs = require('fs/promises');
const path = require('path');

const { env } = require('../config/env');
const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
} = require('../constants/app.constants');
const { AppError } = require('../utils/app-error');
const { logError, logInfo } = require('../utils/logger');

const uploadsRootDirectory = path.resolve(__dirname, '../../uploads');

const STORAGE_TARGETS = Object.freeze({
  PAYMENT_PROOFS: {
    cloudinaryFolder: 'adams/payment-proofs',
    localDirectory: 'payment-proofs',
    operation: 'StorePaymentProofFile',
  },
  REQUEST_ATTACHMENTS: {
    cloudinaryFolder: 'adams/request-attachments',
    localDirectory: 'request-attachments',
    operation: 'StoreRequestAttachmentFile',
  },
});

function cloudinaryEnabled() {
  return Boolean(
    env.cloudinaryCloudName &&
      env.cloudinaryApiKey &&
      env.cloudinaryApiSecret,
  );
}

function getFileStorageStatus() {
  if (cloudinaryEnabled()) {
    return {
      mode: 'cloudinary',
      cloudName: env.cloudinaryCloudName,
    };
  }

  return {
    mode: 'local',
    cloudName: null,
  };
}

function logFileStorageStatus() {
  const status = getFileStorageStatus();

  logInfo({
    requestId: 'storage',
    route: 'FILE STORAGE',
    step: LOG_STEPS.SERVICE_OK,
    layer: 'service',
    operation: 'FileStorageStatus',
    intent: 'Report which storage backend is active for chat attachments and payment proofs',
    storageMode: status.mode,
    cloudName: status.cloudName || '-',
  });
}

function detectResourceType(mimeType) {
  return String(mimeType || '')
    .toLowerCase()
    .startsWith('image/')
    ? 'image'
    : 'raw';
}

function normalizedExtension(fileName) {
  return path.extname(String(fileName || '')).toLowerCase();
}

function buildStoredFilePayload(file, storedName, relativeUrl) {
  const originalName = String(
    file?.originalName || file?.originalname || 'attachment',
  );
  const mimeType = String(
    file?.mimeType || file?.mimetype || 'application/octet-stream',
  );
  const sizeBytes = Number(file?.sizeBytes ?? file?.size ?? 0);

  return {
    originalName,
    originalname: originalName,
    storedName,
    filename: storedName,
    mimeType,
    mimetype: mimeType,
    sizeBytes,
    size: sizeBytes,
    relativeUrl,
  };
}

function buildCloudinarySignature(params) {
  const serializedParams = Object.entries(params)
    .filter(([, value]) => value !== undefined && value !== null && `${value}` !== '')
    .sort(([leftKey], [rightKey]) => leftKey.localeCompare(rightKey))
    .map(([key, value]) => `${key}=${value}`)
    .join('&');

  return createHash('sha1')
    .update(`${serializedParams}${env.cloudinaryApiSecret}`)
    .digest('hex');
}

async function uploadToCloudinary(file, target, logContext) {
  const extension = normalizedExtension(file.originalname);
  const resourceType = detectResourceType(file.mimetype);
  const timestamp = Math.floor(Date.now() / 1000);
  const uniqueName = `${Date.now()}-${randomUUID()}`;
  const publicId = resourceType === 'raw' && extension
    ? `${uniqueName}${extension}`
    : uniqueName;
  const signatureParams = {
    folder: target.cloudinaryFolder,
    public_id: publicId,
    timestamp,
  };
  const signature = buildCloudinarySignature(signatureParams);
  const fileBlob = new Blob([file.buffer], {
    type: file.mimetype || 'application/octet-stream',
  });
  const formData = new FormData();
  formData.set('file', fileBlob, file.originalname || publicId);
  formData.set('api_key', env.cloudinaryApiKey);
  formData.set('folder', target.cloudinaryFolder);
  formData.set('public_id', publicId);
  formData.set('signature', signature);
  formData.set('timestamp', String(timestamp));

  logInfo({
    ...logContext,
    step: LOG_STEPS.PROVIDER_CALL_START,
    layer: 'service',
    operation: target.operation,
    intent: `Upload ${target.localDirectory} to Cloudinary storage`,
  });

  const response = await fetch(
    `https://api.cloudinary.com/v1_1/${env.cloudinaryCloudName}/${resourceType}/upload`,
    {
      method: 'POST',
      body: formData,
    },
  );
  const responseText = await response.text();

  if (!response.ok) {
    let providerError = responseText;

    try {
      providerError = JSON.parse(responseText);
    } catch (error) {
      // WHY: Keep the raw provider body when Cloudinary does not return valid JSON.
    }

    logError({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
      layer: 'service',
      operation: target.operation,
      intent: `Capture the failed Cloudinary response while storing ${target.localDirectory}`,
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      error_code: 'CLOUDINARY_UPLOAD_FAILED',
      resolution_hint:
        'Check the Cloudinary credentials, cloud name, and account upload permissions',
      message: providerError,
    });

    throw new AppError({
      message: 'File upload storage failed',
      statusCode: 503,
      classification: ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      errorCode: 'CLOUDINARY_UPLOAD_FAILED',
      resolutionHint:
        'Check the Cloudinary storage settings and try the upload again',
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
    });
  }

  const payload = JSON.parse(responseText);

  logInfo({
    ...logContext,
    step: LOG_STEPS.PROVIDER_CALL_OK,
    layer: 'service',
    operation: target.operation,
    intent: `Confirm Cloudinary accepted the ${target.localDirectory} upload`,
  });

  const baseStoredName = String(payload.public_id || publicId);
  const storedName =
    payload.format &&
        !baseStoredName.toLowerCase().endsWith(`.${payload.format}`.toLowerCase())
      ? `${baseStoredName}.${payload.format}`
      : baseStoredName;

  return buildStoredFilePayload(
    file,
    storedName,
    payload.secure_url || '',
  );
}

async function storeLocally(file, target) {
  const extension = normalizedExtension(file.originalname);
  const storedName = `${Date.now()}-${randomUUID()}${extension}`;
  const targetDirectory = path.join(uploadsRootDirectory, target.localDirectory);
  const targetPath = path.join(targetDirectory, storedName);

  await fs.mkdir(targetDirectory, { recursive: true });
  await fs.writeFile(targetPath, file.buffer);

  return buildStoredFilePayload(
    file,
    storedName,
    `/uploads/${target.localDirectory}/${storedName}`,
  );
}

async function storeFile(file, target, logContext) {
  if (!file || !Buffer.isBuffer(file.buffer)) {
    throw new AppError({
      message: 'Upload file payload is missing',
      statusCode: 400,
      classification: ERROR_CLASSIFICATIONS.MISSING_REQUIRED_FIELD,
      errorCode: 'UPLOAD_FILE_PAYLOAD_MISSING',
      resolutionHint: 'Choose a file and try the upload again',
      step: LOG_STEPS.VALIDATION_FAIL,
    });
  }

  if (cloudinaryEnabled()) {
    return uploadToCloudinary(file, target, logContext);
  }

  return storeLocally(file, target);
}

async function storePaymentProofFile(file, logContext) {
  return storeFile(file, STORAGE_TARGETS.PAYMENT_PROOFS, logContext);
}

async function storeRequestAttachmentFile(file, logContext) {
  return storeFile(file, STORAGE_TARGETS.REQUEST_ATTACHMENTS, logContext);
}

module.exports = {
  getFileStorageStatus,
  logFileStorageStatus,
  storePaymentProofFile,
  storeRequestAttachmentFile,
};
