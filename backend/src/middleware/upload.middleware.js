/**
 * WHAT: Handles multipart uploads for customer payment-proof and chat-attachment files.
 * WHY: Uploads need file-size and file-type limits before they reach service logic.
 * HOW: Use Multer memory storage with narrow allowlists and convert upload failures into the shared API error shape.
 */

const multer = require('multer');
const path = require('path');

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
} = require('../constants/app.constants');
const { AppError } = require('../utils/app-error');

const paymentProofMimeTypes = new Set([
  'application/pdf',
  'image/jpeg',
  'image/png',
]);
const requestAttachmentMimeTypes = new Set([
  'application/msword',
  'application/pdf',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'image/jpeg',
  'image/png',
  'image/webp',
  'text/plain',
]);

function createUpload({
  allowedMimeTypes,
  allowedExtensions = null,
  invalidTypeMessage,
  invalidTypeErrorCode,
  invalidTypeResolutionHint,
  fileSizeBytes,
}) {
  return multer({
    storage: multer.memoryStorage(),
    limits: {
      fileSize: fileSizeBytes,
    },
    fileFilter: (_req, file, callback) => {
      const normalizedMimeType = String(file.mimetype || '').toLowerCase();
      const normalizedExtension = path.extname(file.originalname || '').toLowerCase();

      if (
        allowedMimeTypes.has(normalizedMimeType) ||
        (allowedExtensions?.has(normalizedExtension) ?? false)
      ) {
        callback(null, true);
        return;
      }

      callback(
        new AppError({
          message: invalidTypeMessage,
          statusCode: 400,
          classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
          errorCode: invalidTypeErrorCode,
          resolutionHint: invalidTypeResolutionHint,
          step: LOG_STEPS.VALIDATION_FAIL,
        }),
      );
    },
  });
}

function buildUploadMiddleware({
  upload,
  fieldName,
  tooLargeMessage,
  tooLargeErrorCode,
  tooLargeResolutionHint,
  uploadFailedMessage,
  uploadFailedErrorCode,
  uploadFailedResolutionHint,
}) {
  return (req, res, next) => {
    upload.single(fieldName)(req, res, (error) => {
      if (!error) {
        next();
        return;
      }

      if (error instanceof AppError) {
        next(error);
        return;
      }

      if (
        error instanceof multer.MulterError &&
        error.code === 'LIMIT_FILE_SIZE'
      ) {
        next(
          new AppError({
            message: tooLargeMessage,
            statusCode: 400,
            classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
            errorCode: tooLargeErrorCode,
            resolutionHint: tooLargeResolutionHint,
            step: LOG_STEPS.VALIDATION_FAIL,
          }),
        );
        return;
      }

      next(
        new AppError({
          message: uploadFailedMessage,
          statusCode: 400,
          classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
          errorCode: uploadFailedErrorCode,
          resolutionHint: uploadFailedResolutionHint,
          step: LOG_STEPS.VALIDATION_FAIL,
        }),
      );
    });
  };
}

const paymentProofUpload = createUpload({
  allowedMimeTypes: paymentProofMimeTypes,
  allowedExtensions: new Set(['.pdf', '.jpg', '.jpeg', '.png']),
  invalidTypeMessage: 'Only PNG, JPG, or PDF payment proof files are allowed',
  invalidTypeErrorCode: 'PAYMENT_PROOF_FILE_TYPE_INVALID',
  invalidTypeResolutionHint: 'Upload a PNG, JPG, or PDF file and try again',
  fileSizeBytes: 8 * 1024 * 1024,
});

const requestAttachmentUpload = createUpload({
  allowedMimeTypes: requestAttachmentMimeTypes,
  allowedExtensions: new Set([
    '.doc',
    '.docx',
    '.jpg',
    '.jpeg',
    '.pdf',
    '.png',
    '.txt',
    '.webp',
  ]),
  invalidTypeMessage:
    'Only PNG, JPG, WEBP, PDF, TXT, DOC, or DOCX chat attachments are allowed',
  invalidTypeErrorCode: 'REQUEST_ATTACHMENT_FILE_TYPE_INVALID',
  invalidTypeResolutionHint:
    'Upload a supported image or document file and try again',
  fileSizeBytes: 12 * 1024 * 1024,
});

const paymentProofUploadMiddleware = buildUploadMiddleware({
  upload: paymentProofUpload,
  fieldName: 'proof',
  tooLargeMessage: 'Payment proof files must be 8MB or smaller',
  tooLargeErrorCode: 'PAYMENT_PROOF_FILE_TOO_LARGE',
  tooLargeResolutionHint: 'Choose a smaller file and try again',
  uploadFailedMessage: 'Payment proof upload failed',
  uploadFailedErrorCode: 'PAYMENT_PROOF_UPLOAD_FAILED',
  uploadFailedResolutionHint: 'Retry the upload with a supported proof file',
});

const requestAttachmentUploadMiddleware = buildUploadMiddleware({
  upload: requestAttachmentUpload,
  fieldName: 'attachment',
  tooLargeMessage: 'Chat attachments must be 12MB or smaller',
  tooLargeErrorCode: 'REQUEST_ATTACHMENT_FILE_TOO_LARGE',
  tooLargeResolutionHint: 'Choose a smaller file and try again',
  uploadFailedMessage: 'Chat attachment upload failed',
  uploadFailedErrorCode: 'REQUEST_ATTACHMENT_UPLOAD_FAILED',
  uploadFailedResolutionHint:
    'Retry the upload with a supported attachment file',
});

module.exports = {
  paymentProofUploadMiddleware,
  requestAttachmentUploadMiddleware,
};
