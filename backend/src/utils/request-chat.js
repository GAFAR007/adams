/**
 * WHAT: Builds normalized request-chat message payloads for customer, staff, system, and AI events.
 * WHY: Queue and chat flows need one consistent message shape so services do not duplicate sender metadata rules.
 * HOW: Expose small helper builders that return message objects ready to append onto `ServiceRequest.messages`.
 */

const { REQUEST_MESSAGE_SENDERS } = require('../constants/app.constants');

function buildBaseMessage({ senderType, senderId = null, senderName, text }) {
  // WHY: Trim message text once here so every caller stores the same clean payload shape.
  return {
    senderType,
    senderId,
    senderName,
    text: text.trim(),
    createdAt: new Date(),
  };
}

function buildCustomerMessage({ customerId, customerName, text }) {
  // WHY: Customer messages should always carry the account owner id so later audit or threading work can trace authorship.
  return buildBaseMessage({
    senderType: REQUEST_MESSAGE_SENDERS.CUSTOMER,
    senderId: customerId,
    senderName: customerName,
    text,
  });
}

function buildStaffMessage({ staffId, staffName, text }) {
  // WHY: Staff replies need the responder identity so customers know exactly who joined the thread.
  return buildBaseMessage({
    senderType: REQUEST_MESSAGE_SENDERS.STAFF,
    senderId: staffId,
    senderName: staffName,
    text,
  });
}

function buildSystemMessage(text) {
  // WHY: System notices describe workflow changes without pretending to be a human participant.
  return buildBaseMessage({
    senderType: REQUEST_MESSAGE_SENDERS.SYSTEM,
    senderName: 'System',
    text,
  });
}

function buildAiMessage(text) {
  // WHY: AI placeholder messages should be clearly labeled so customers can tell they are not from staff.
  return buildBaseMessage({
    senderType: REQUEST_MESSAGE_SENDERS.AI,
    senderName: 'AI Assistant',
    text,
  });
}

module.exports = {
  buildAiMessage,
  buildCustomerMessage,
  buildStaffMessage,
  buildSystemMessage,
};
