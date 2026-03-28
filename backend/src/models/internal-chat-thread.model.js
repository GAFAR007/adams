/**
 * WHAT: Stores internal direct and group chat threads between admin and staff users.
 * WHY: Internal coordination needs persistent one-to-one and multi-person chat history instead of seeded frontend-only data.
 * HOW: Save thread type, optional direct-thread key, participant read markers, and a compact embedded message log.
 */

const mongoose = require('mongoose');

const { USER_ROLES } = require('../constants/app.constants');

const internalChatMessageSchema = new mongoose.Schema(
  {
    sender: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    senderName: {
      type: String,
      required: true,
      trim: true,
    },
    senderRole: {
      type: String,
      enum: [USER_ROLES.ADMIN, USER_ROLES.STAFF],
      required: true,
    },
    text: {
      type: String,
      required: true,
      trim: true,
    },
    createdAt: {
      type: Date,
      default: Date.now,
    },
  },
  {
    _id: true,
    id: false,
  },
);

const internalChatParticipantSchema = new mongoose.Schema(
  {
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    lastReadAt: {
      type: Date,
      default: null,
    },
  },
  {
    _id: false,
    id: false,
  },
);

const internalChatThreadSchema = new mongoose.Schema(
  {
    threadType: {
      type: String,
      enum: ['direct', 'group'],
      default: 'direct',
      required: true,
      index: true,
    },
    title: {
      type: String,
      trim: true,
      default: null,
    },
    participantKey: {
      type: String,
      trim: true,
      default: null,
    },
    participants: {
      type: [internalChatParticipantSchema],
      validate: {
        validator(value) {
          return Array.isArray(value) && value.length >= 2;
        },
        message: 'Internal chat threads must have at least two participants',
      },
      required: true,
    },
    createdBy: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
    },
    lastMessageAt: {
      type: Date,
      default: Date.now,
      index: true,
    },
    messages: {
      type: [internalChatMessageSchema],
      default: [],
    },
  },
  {
    timestamps: true,
  },
);

internalChatThreadSchema.index(
  { participantKey: 1 },
  {
    unique: true,
    partialFilterExpression: { participantKey: { $type: 'string' } },
  },
);
internalChatThreadSchema.index({ 'participants.user': 1, lastMessageAt: -1 });

const InternalChatThread = mongoose.model(
  'InternalChatThread',
  internalChatThreadSchema,
);

module.exports = { InternalChatThread };
