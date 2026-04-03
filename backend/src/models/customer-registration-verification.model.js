/**
 * WHAT: Stores temporary customer registration email-code verification records.
 * WHY: First-time customer sign-up must verify email ownership before an account is created.
 * HOW: Persist a hashed code per email with expiry and verification state.
 */

const mongoose = require('mongoose');

const customerRegistrationVerificationSchema = new mongoose.Schema(
  {
    email: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
      index: true,
    },
    purpose: {
      type: String,
      required: true,
      default: 'customer_register',
    },
    codeHash: {
      type: String,
      required: true,
    },
    expiresAt: {
      type: Date,
      required: true,
      index: true,
    },
    lastSentAt: {
      type: Date,
      default: Date.now,
    },
    verifiedAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  },
);

customerRegistrationVerificationSchema.index(
  { email: 1, purpose: 1 },
  { unique: true },
);

const CustomerRegistrationVerification = mongoose.model(
  'CustomerRegistrationVerification',
  customerRegistrationVerificationSchema,
);

module.exports = { CustomerRegistrationVerification };
