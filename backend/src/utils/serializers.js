/**
 * WHAT: Converts MongoDB documents into safe API payloads.
 * WHY: The frontend should receive compact, predictable data instead of raw internal documents.
 * HOW: Map each entity into a plain object with only the fields required by UI flows.
 */

function serializeUser(user) {
  // WHY: Keep null handling centralized so callers do not need to guard every serializer call.
  if (!user) {
    return null;
  }

  return {
    // WHY: Always expose a string id so frontend code does not depend on MongoDB object internals.
    id: String(user._id || user.id),
    firstName: user.firstName,
    lastName: user.lastName,
    fullName: `${user.firstName} ${user.lastName}`.trim(),
    email: user.email,
    phone: user.phone || null,
    role: user.role,
    status: user.status,
    staffAvailability: user.staffAvailability || null,
    createdAt: user.createdAt?.toISOString?.() || null,
    updatedAt: user.updatedAt?.toISOString?.() || null,
  };
}

function serializeRequestMessage(message) {
  if (!message) {
    return null;
  }

  return {
    id: String(message._id || message.id || ''),
    senderType: message.senderType,
    senderId: message.senderId ? String(message.senderId) : null,
    senderName: message.senderName || '',
    text: message.text || '',
    createdAt: message.createdAt?.toISOString?.() || null,
  };
}

function serializeStaffInvite(invite, inviteLink = null) {
  if (!invite) {
    return null;
  }

  return {
    id: String(invite._id || invite.id),
    inviteId: invite.inviteId,
    firstName: invite.firstName || '',
    lastName: invite.lastName || '',
    email: invite.email,
    phone: invite.phone || null,
    expiresAt: invite.expiresAt?.toISOString?.() || null,
    acceptedAt: invite.acceptedAt?.toISOString?.() || null,
    revokedAt: invite.revokedAt?.toISOString?.() || null,
    inviteLink,
    createdAt: invite.createdAt?.toISOString?.() || null,
  };
}

function serializeServiceRequest(request) {
  if (!request) {
    return null;
  }

  // WHY: Only serialize populated relations when the data is actually present to avoid fake partial users.
  const customer = request.customer && request.customer.firstName ? serializeUser(request.customer) : null;
  const assignedStaff =
    request.assignedStaff && request.assignedStaff.firstName ? serializeUser(request.assignedStaff) : null;

  return {
    id: String(request._id || request.id),
    serviceType: request.serviceType,
    status: request.status,
    source: request.source,
    message: request.message,
    preferredDate: request.preferredDate?.toISOString?.() || null,
    preferredTimeWindow: request.preferredTimeWindow || null,
    location: {
      addressLine1: request.location?.addressLine1 || '',
      city: request.location?.city || '',
      postalCode: request.location?.postalCode || '',
    },
    contactSnapshot: {
      fullName: request.contactSnapshot?.fullName || '',
      email: request.contactSnapshot?.email || '',
      phone: request.contactSnapshot?.phone || '',
    },
    customer,
    assignedStaff,
    queueEnteredAt: request.queueEnteredAt?.toISOString?.() || null,
    attendedAt: request.attendedAt?.toISOString?.() || null,
    closedAt: request.closedAt?.toISOString?.() || null,
    messageCount: Array.isArray(request.messages) ? request.messages.length : 0,
    messages: Array.isArray(request.messages)
      ? request.messages.map(serializeRequestMessage).filter(Boolean)
      : [],
    createdAt: request.createdAt?.toISOString?.() || null,
    updatedAt: request.updatedAt?.toISOString?.() || null,
  };
}

module.exports = {
  serializeRequestMessage,
  serializeServiceRequest,
  serializeStaffInvite,
  serializeUser,
};
