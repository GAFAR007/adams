/**
 * WHAT: Validates admin/staff internal chat payloads.
 * WHY: Internal chat routes should only accept valid thread ids, recipients, titles, and bounded message text.
 * HOW: Reuse express-validator to guard direct-thread creation, group creation, replies, and read-state updates.
 */

const { body, param } = require('express-validator');

const createDirectInternalChatValidator = [
  body('participantId').isMongoId().withMessage('Participant ID must be valid'),
  body('message')
    .trim()
    .isLength({ min: 1, max: 2000 })
    .withMessage('Message must be between 1 and 2000 characters'),
];

const createGroupInternalChatValidator = [
  body('title')
    .trim()
    .isLength({ min: 2, max: 80 })
    .withMessage('Group title must be between 2 and 80 characters'),
  body('participantIds')
    .isArray({ min: 2 })
    .withMessage('Choose at least two people for a group chat'),
  body('participantIds.*')
    .isMongoId()
    .withMessage('Each participant ID must be valid'),
  body('message')
    .trim()
    .isLength({ min: 1, max: 2000 })
    .withMessage('Message must be between 1 and 2000 characters'),
];

const postInternalChatMessageValidator = [
  param('threadId').isMongoId().withMessage('Thread ID must be valid'),
  body('message')
    .trim()
    .isLength({ min: 1, max: 2000 })
    .withMessage('Message must be between 1 and 2000 characters'),
];

const markInternalChatReadValidator = [
  param('threadId').isMongoId().withMessage('Thread ID must be valid'),
];

module.exports = {
  createDirectInternalChatValidator,
  createGroupInternalChatValidator,
  markInternalChatReadValidator,
  postInternalChatMessageValidator,
};
