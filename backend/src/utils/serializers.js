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

function serializeInternalChatMessage(
  message,
  currentUserId,
  otherParticipants = [],
) {
  if (!message) {
    return null;
  }

  const senderId = String(
    message.sender?._id || message.sender || message.senderId || '',
  );
  const createdAt =
    message.createdAt?.toISOString?.() ||
    (message.createdAt ? new Date(message.createdAt).toISOString() : null);
  const isOwn = senderId === String(currentUserId);

  let receiptStatus = null;
  if (isOwn) {
    const createdAtDate = createdAt ? new Date(createdAt) : null;
    const participantReadDates = otherParticipants
      .map((participant) =>
        participant?.lastReadAt ? new Date(participant.lastReadAt) : null,
      )
      .filter(Boolean);
    const allRead =
      createdAtDate &&
      otherParticipants.length > 0 &&
      otherParticipants.every((participant) => {
        return (
          participant?.lastReadAt &&
          new Date(participant.lastReadAt) >= createdAtDate
        );
      });

    if (!createdAtDate || otherParticipants.length === 0) {
      receiptStatus = 'sent';
    } else if (allRead) {
      receiptStatus = 'read';
    } else if (participantReadDates.length > 0) {
      receiptStatus = 'delivered';
    } else {
      receiptStatus = 'sent';
    }
  }

  return {
    id: String(message._id || message.id || ''),
    senderId,
    senderName: message.senderName || '',
    senderRole: message.senderRole || message.sender?.role || null,
    text: message.text || '',
    createdAt,
    isOwn,
    receiptStatus,
  };
}

function serializeInternalChatThread(thread, currentUserId) {
  if (!thread) {
    return null;
  }

  const participantStates = Array.isArray(thread.participants)
    ? thread.participants
    : [];
  const currentParticipant = participantStates.find((participant) => {
    return (
      String(participant.user?._id || participant.user) === String(currentUserId)
    );
  });
  const otherParticipants = participantStates.filter((participant) => {
    return (
      String(participant.user?._id || participant.user) !== String(currentUserId)
    );
  });
  const threadType = thread.threadType || 'direct';
  const serializedParticipants = otherParticipants
    .map((participant) => serializeUser(participant.user))
    .filter(Boolean);
  const counterpart =
    threadType === 'direct' && serializedParticipants.length > 0
      ? serializedParticipants[0]
      : null;

  if (threadType === 'direct' && !counterpart) {
    return null;
  }

  const unreadCount = (Array.isArray(thread.messages) ? thread.messages : []).reduce(
    (count, message) => {
      const senderId = String(
        message.sender?._id || message.sender || message.senderId || '',
      );
      if (senderId === String(currentUserId)) {
        return count;
      }

      const createdAt = message.createdAt ? new Date(message.createdAt) : null;
      const lastReadAt = currentParticipant?.lastReadAt
        ? new Date(currentParticipant.lastReadAt)
        : null;

      if (!createdAt || !lastReadAt || createdAt > lastReadAt) {
        return count + 1;
      }

      return count;
    },
    0,
  );

  return {
    id: String(thread._id || thread.id || ''),
    threadType,
    title: thread.title || null,
    counterpart,
    participants: serializedParticipants,
    participantCount: participantStates.length,
    onlineParticipantCount: serializedParticipants.reduce((count, participant) => {
      return participant.staffAvailability === 'online' ? count + 1 : count;
    }, 0),
    unreadCount,
    messageCount: Array.isArray(thread.messages) ? thread.messages.length : 0,
    lastMessageAt: thread.lastMessageAt?.toISOString?.() || null,
    createdAt: thread.createdAt?.toISOString?.() || null,
    updatedAt: thread.updatedAt?.toISOString?.() || null,
    messages: Array.isArray(thread.messages)
      ? thread.messages
          .map((message) =>
            serializeInternalChatMessage(
              message,
              currentUserId,
              otherParticipants,
            ),
          )
          .filter(Boolean)
      : [],
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
    actionType: message.actionType || null,
    text: message.text || '',
    attachment: serializeRequestMessageAttachment(message.attachment),
    createdAt: message.createdAt?.toISOString?.() || null,
  };
}

function serializeRequestMessageAttachment(attachment) {
  if (!attachment) {
    return null;
  }

  return {
    originalName: attachment.originalName || '',
    storedName: attachment.storedName || '',
    mimeType: attachment.mimeType || '',
    sizeBytes: attachment.sizeBytes || 0,
    relativeUrl: attachment.relativeUrl || '',
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

function serializePaymentProof(proof) {
  if (!proof) {
    return null;
  }

  return {
    originalName: proof.originalName || '',
    storedName: proof.storedName || '',
    mimeType: proof.mimeType || '',
    sizeBytes: proof.sizeBytes || 0,
    relativeUrl: proof.relativeUrl || '',
    uploadedAt: proof.uploadedAt?.toISOString?.() || null,
    note: proof.note || '',
  };
}

function serializeRequestInvoice(invoice) {
  if (!invoice) {
    return null;
  }

  return {
    invoiceNumber: invoice.invoiceNumber || '',
    amount: typeof invoice.amount === 'number' ? invoice.amount : 0,
    currency: invoice.currency || 'EUR',
    dueDate: invoice.dueDate?.toISOString?.() || null,
    paymentMethod: invoice.paymentMethod || '',
    paymentInstructions: invoice.paymentInstructions || '',
    note: invoice.note || '',
    status: invoice.status || null,
    sentAt: invoice.sentAt?.toISOString?.() || null,
    sentByRole: invoice.sentByRole || null,
    reviewedAt: invoice.reviewedAt?.toISOString?.() || null,
    reviewedByRole: invoice.reviewedByRole || null,
    reviewNote: invoice.reviewNote || '',
    proof: serializePaymentProof(invoice.proof),
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
    invoice: serializeRequestInvoice(request.invoice),
    detailsUpdatedAt: request.detailsUpdatedAt?.toISOString?.() || null,
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
    projectStartedAt: request.projectStartedAt?.toISOString?.() || null,
    finishedAt: request.finishedAt?.toISOString?.() || null,
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
  serializeInternalChatMessage,
  serializeInternalChatThread,
  serializeRequestMessage,
  serializeServiceRequest,
  serializeStaffInvite,
  serializeUser,
};
