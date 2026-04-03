/**
 * WHAT: Defines the user schema for admin, staff, and customer accounts.
 * WHY: Role-based access and customer request ownership both depend on a shared account model.
 * HOW: Store identity, role, status, and password hash with indexes tuned for auth and dashboard lookups.
 */

const mongoose = require('mongoose');

const {
  STAFF_AVAILABILITIES,
  STAFF_TYPES,
  USER_ROLES,
  USER_STATUSES,
} = require('../constants/app.constants');

const userSchema = new mongoose.Schema(
  {
    firstName: {
      // WHY: Names stay first-class fields so dashboards and greetings do not parse them from a single string.
      type: String,
      required: true,
      trim: true,
    },
    lastName: {
      type: String,
      required: true,
      trim: true,
    },
    email: {
      // WHY: Normalize email at the model layer so auth and invite lookups compare one canonical value.
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
    },
    phone: {
      type: String,
      default: '',
      trim: true,
    },
    role: {
      // WHY: Role drives authorization across the whole backend, so only known enum values are allowed.
      type: String,
      enum: Object.values(USER_ROLES),
      required: true,
    },
    status: {
      type: String,
      enum: Object.values(USER_STATUSES),
      default: USER_STATUSES.ACTIVE,
    },
    staffAvailability: {
      // WHY: Queue operations need a simple online/offline flag so staff can opt in and out of live queue handling.
      type: String,
      enum: Object.values(STAFF_AVAILABILITIES),
      default: STAFF_AVAILABILITIES.OFFLINE,
    },
    staffType: {
      // WHY: The workflow distinguishes customer care, technicians, and contractors even when auth still groups them under shared roles.
      type: String,
      enum: Object.values(STAFF_TYPES),
      default: null,
    },
    passwordHash: {
      // WHY: Keep hashes hidden from normal queries so serializers and controllers cannot leak them by accident.
      type: String,
      select: false,
    },
  },
  {
    timestamps: true,
  },
);

// The compound role/status index supports dashboard and permission-oriented staff lookups.
userSchema.index({ role: 1, status: 1 });
userSchema.index({ role: 1, staffType: 1, status: 1 });

const User = mongoose.model('User', userSchema);

module.exports = { User };
