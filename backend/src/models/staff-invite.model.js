/**
 * WHAT: Tracks admin-issued staff invitation records.
 * WHY: Invite-only staff onboarding requires an auditable record before account creation happens.
 * HOW: Store invite identity, target contact details, expiry, and acceptance state.
 */

const mongoose = require('mongoose');

const staffInviteSchema = new mongoose.Schema(
  {
    inviteId: {
      type: String,
      required: true,
      unique: true,
    },
    firstName: {
      type: String,
      default: '',
      trim: true,
    },
    lastName: {
      type: String,
      default: '',
      trim: true,
    },
    email: {
      type: String,
      required: true,
      lowercase: true,
      trim: true,
      index: true,
    },
    phone: {
      type: String,
      default: '',
      trim: true,
    },
    invitedBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    expiresAt: {
      type: Date,
      required: true,
    },
    acceptedAt: {
      type: Date,
      default: null,
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

staffInviteSchema.index({ email: 1, acceptedAt: 1, revokedAt: 1 });

const StaffInvite = mongoose.model('StaffInvite', staffInviteSchema);

module.exports = { StaffInvite };
