/**
 * WHAT: Stores refresh-token sessions for authenticated users.
 * WHY: Server-side session tracking makes logout and refresh-token revocation enforceable.
 * HOW: Persist a hashed token per session together with expiry, revocation, and client metadata.
 */

const mongoose = require('mongoose');

const refreshSessionSchema = new mongoose.Schema(
  {
    sessionId: {
      type: String,
      required: true,
      unique: true,
    },
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      index: true,
    },
    tokenHash: {
      type: String,
      required: true,
    },
    ipAddress: {
      type: String,
      default: '',
    },
    userAgent: {
      type: String,
      default: '',
    },
    expiresAt: {
      type: Date,
      required: true,
      index: true,
    },
    revokedAt: {
      type: Date,
      default: null,
    },
  },
  {
    timestamps: true,
  },
);

// The compound user/revocation index keeps refresh-session validation and cleanup queries efficient.
refreshSessionSchema.index({ user: 1, revokedAt: 1 });

const RefreshSession = mongoose.model('RefreshSession', refreshSessionSchema);

module.exports = { RefreshSession };
