/**
 * WHAT: Converts MongoDB documents into safe API payloads.
 * WHY: The frontend should receive compact, predictable data instead of raw internal documents.
 * HOW: Map each entity into a plain object with only the fields required by UI flows.
 */

const {
  buildRequestScheduleSummary,
  calculateEstimatedDays,
  getCompleteFinalRequestEstimations,
  isCompleteRequestEstimation,
  resolveEstimationStage,
} = require('./request-estimation');

function resolveEstimationSubmitterStaffType(estimation) {
  return estimation?.submitterStaffType || estimation?.submittedBy?.staffType || null;
}

function resolveEstimationAssignmentType(estimation) {
  if (estimation?.assignmentType) {
    return estimation.assignmentType;
  }

  return resolveEstimationSubmitterStaffType(estimation) === 'contractor'
    ? 'external'
    : 'internal';
}

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
    staffType: user.staffType || null,
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
    attachment: serializeRequestMessageAttachment(message.attachment),
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
    actionPayload:
      message.actionPayload && typeof message.actionPayload === 'object'
        ? message.actionPayload
        : null,
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
    staffType: invite.staffType || 'technician',
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
    kind: invoice.kind || null,
    invoiceNumber: invoice.invoiceNumber || '',
    amount: typeof invoice.amount === 'number' ? invoice.amount : 0,
    quotedBaseAmount:
      typeof invoice.quotedBaseAmount === 'number'
        ? invoice.quotedBaseAmount
        : 0,
    appServiceChargePercent:
      typeof invoice.appServiceChargePercent === 'number'
        ? invoice.appServiceChargePercent
        : null,
    appServiceChargeAmount:
      typeof invoice.appServiceChargeAmount === 'number'
        ? invoice.appServiceChargeAmount
        : null,
    adminServiceChargePercent:
      typeof invoice.adminServiceChargePercent === 'number'
        ? invoice.adminServiceChargePercent
        : null,
    adminServiceChargeAmount:
      typeof invoice.adminServiceChargeAmount === 'number'
        ? invoice.adminServiceChargeAmount
        : null,
    currency: invoice.currency || 'EUR',
    dueDate: invoice.dueDate?.toISOString?.() || null,
    proofUploadDeadlineAt:
      invoice.proofUploadDeadlineAt?.toISOString?.() || null,
    proofUploadUnlockedAt:
      invoice.proofUploadUnlockedAt?.toISOString?.() || null,
    proofUploadUnlockedByRole: invoice.proofUploadUnlockedByRole || null,
    siteReviewDate: invoice.siteReviewDate?.toISOString?.() || null,
    siteReviewStartTime: invoice.siteReviewStartTime || '',
    siteReviewEndTime: invoice.siteReviewEndTime || '',
    siteReviewNotes: invoice.siteReviewNotes || '',
    plannedStartDate: invoice.plannedStartDate?.toISOString?.() || null,
    plannedStartTime: invoice.plannedStartTime || '',
    plannedEndTime: invoice.plannedEndTime || '',
    plannedHoursPerDay:
      typeof invoice.plannedHoursPerDay === 'number'
        ? invoice.plannedHoursPerDay
        : null,
    plannedExpectedEndDate:
      invoice.plannedExpectedEndDate?.toISOString?.() || null,
    plannedDailySchedule: Array.isArray(invoice.plannedDailySchedule)
      ? invoice.plannedDailySchedule.map((entry) => ({
          date: entry.date?.toISOString?.() || null,
          startTime: entry.startTime || '',
          endTime: entry.endTime || '',
          hours: typeof entry.hours === 'number' ? entry.hours : null,
        }))
      : [],
    paymentMethod: invoice.paymentMethod || '',
    paymentInstructions: invoice.paymentInstructions || '',
    note: invoice.note || '',
    status: invoice.status || null,
    sentAt: invoice.sentAt?.toISOString?.() || null,
    sentByRole: invoice.sentByRole || null,
    paymentProvider: invoice.paymentProvider || null,
    paymentLinkUrl: invoice.paymentLinkUrl || null,
    providerPaymentId: invoice.providerPaymentId || null,
    paymentReference: invoice.paymentReference || null,
    paidAt: invoice.paidAt?.toISOString?.() || null,
    providerReceiptUrl: invoice.providerReceiptUrl || null,
    receiptNumber: invoice.receiptNumber || null,
    receiptRelativeUrl: invoice.receiptRelativeUrl || null,
    receiptIssuedAt: invoice.receiptIssuedAt?.toISOString?.() || null,
    reviewedAt: invoice.reviewedAt?.toISOString?.() || null,
    reviewedByRole: invoice.reviewedByRole || null,
    reviewNote: invoice.reviewNote || '',
    proof: serializePaymentProof(invoice.proof),
  };
}

function serializeRequestAccessDetails(accessDetails) {
  if (!accessDetails) {
    return null;
  }

  return {
    accessMethod: accessDetails.accessMethod || '',
    arrivalContactName: accessDetails.arrivalContactName || '',
    arrivalContactPhone: accessDetails.arrivalContactPhone || '',
    accessNotes: accessDetails.accessNotes || '',
  };
}

function serializeRequestMediaSummary(mediaSummary) {
  if (!mediaSummary) {
    return {
      photoCount: 0,
      videoCount: 0,
      documentCount: 0,
      intakePhotoCount: 0,
      intakeVideoCount: 0,
      updatedAt: null,
    };
  }

  return {
    photoCount: typeof mediaSummary.photoCount === 'number' ? mediaSummary.photoCount : 0,
    videoCount: typeof mediaSummary.videoCount === 'number' ? mediaSummary.videoCount : 0,
    documentCount:
      typeof mediaSummary.documentCount === 'number' ? mediaSummary.documentCount : 0,
    intakePhotoCount:
      typeof mediaSummary.intakePhotoCount === 'number' ? mediaSummary.intakePhotoCount : 0,
    intakeVideoCount:
      typeof mediaSummary.intakeVideoCount === 'number' ? mediaSummary.intakeVideoCount : 0,
    updatedAt: mediaSummary.updatedAt?.toISOString?.() || null,
  };
}

function serializeQuoteReview(review) {
  if (!review) {
    return null;
  }

  return {
    kind: review.kind || null,
    quotedBaseAmount:
      typeof review.quotedBaseAmount === 'number' ? review.quotedBaseAmount : 0,
    appServiceChargePercent:
      typeof review.appServiceChargePercent === 'number'
        ? review.appServiceChargePercent
        : null,
    appServiceChargeAmount:
      typeof review.appServiceChargeAmount === 'number'
        ? review.appServiceChargeAmount
        : null,
    adminServiceChargePercent:
      typeof review.adminServiceChargePercent === 'number'
        ? review.adminServiceChargePercent
        : null,
    adminServiceChargeAmount:
      typeof review.adminServiceChargeAmount === 'number'
        ? review.adminServiceChargeAmount
        : null,
    totalAmount: typeof review.totalAmount === 'number' ? review.totalAmount : 0,
    currency: review.currency || 'EUR',
    selectedEstimationId: review.selectedEstimationId
      ? String(review.selectedEstimationId)
      : null,
    dueDate: review.dueDate?.toISOString?.() || null,
    siteReviewDate: review.siteReviewDate?.toISOString?.() || null,
    siteReviewStartTime: review.siteReviewStartTime || '',
    siteReviewEndTime: review.siteReviewEndTime || '',
    siteReviewNotes: review.siteReviewNotes || '',
    plannedStartDate: review.plannedStartDate?.toISOString?.() || null,
    plannedStartTime: review.plannedStartTime || '',
    plannedEndTime: review.plannedEndTime || '',
    plannedHoursPerDay:
      typeof review.plannedHoursPerDay === 'number' ? review.plannedHoursPerDay : null,
    plannedExpectedEndDate:
      review.plannedExpectedEndDate?.toISOString?.() || null,
    plannedDailySchedule: Array.isArray(review.plannedDailySchedule)
      ? review.plannedDailySchedule.map((entry) => ({
          date: entry.date?.toISOString?.() || null,
          startTime: entry.startTime || '',
          endTime: entry.endTime || '',
          hours: typeof entry.hours === 'number' ? entry.hours : null,
        }))
      : [],
    paymentMethod: review.paymentMethod || '',
    paymentInstructions: review.paymentInstructions || '',
    note: review.note || '',
    reviewedAt: review.reviewedAt?.toISOString?.() || null,
    reviewedByRole: review.reviewedByRole || null,
    reviewedById: review.reviewedById ? String(review.reviewedById) : null,
    reviewedByName: review.reviewedByName || '',
  };
}

function serializeEstimationSubmitter(submittedBy, submitterRole, submitterStaffType = null) {
  if (!submittedBy) {
    return null;
  }

  if (submittedBy.firstName) {
    return serializeUser(submittedBy);
  }

  return {
    id: String(submittedBy._id || submittedBy.id || submittedBy),
    firstName: '',
    lastName: '',
    fullName: '',
    email: '',
    phone: null,
    role: submitterRole || null,
    staffType: submitterStaffType || null,
    status: null,
    staffAvailability: null,
    createdAt: null,
    updatedAt: null,
  };
}

function serializeRequestEstimation(estimation, selectedEstimationId) {
  if (!estimation) {
    return null;
  }

  const estimationId = String(estimation._id || estimation.id || '');

  return {
    id: estimationId,
    submittedBy: serializeEstimationSubmitter(
      estimation.submittedBy,
      estimation.submitterRole,
      resolveEstimationSubmitterStaffType(estimation),
    ),
    submitterRole: estimation.submitterRole || null,
    submitterStaffType: resolveEstimationSubmitterStaffType(estimation),
    assignmentType: resolveEstimationAssignmentType(estimation),
    stage: resolveEstimationStage(estimation),
    estimatedStartDate: estimation.estimatedStartDate?.toISOString?.() || null,
    estimatedEndDate: estimation.estimatedEndDate?.toISOString?.() || null,
    estimatedHours:
      typeof estimation.estimatedHours === 'number'
        ? estimation.estimatedHours
        : null,
    estimatedHoursPerDay:
      typeof estimation.estimatedHoursPerDay === 'number'
        ? estimation.estimatedHoursPerDay
        : null,
    siteReviewDate: estimation.siteReviewDate?.toISOString?.() || null,
    siteReviewStartTime: estimation.siteReviewStartTime || '',
    siteReviewEndTime: estimation.siteReviewEndTime || '',
    siteReviewNotes: estimation.siteReviewNotes || '',
    siteReviewCost:
      typeof estimation.siteReviewCost === 'number'
        ? estimation.siteReviewCost
        : null,
    estimatedDays:
      typeof estimation.estimatedDays === 'number'
        ? estimation.estimatedDays
        : calculateEstimatedDays(
            estimation.estimatedStartDate,
            estimation.estimatedEndDate,
          ),
    estimatedDailySchedule: Array.isArray(estimation.estimatedDailySchedule)
      ? estimation.estimatedDailySchedule.map((entry) => ({
          date: entry.date?.toISOString?.() || null,
          startTime: entry.startTime || '',
          endTime: entry.endTime || '',
          hours: typeof entry.hours === 'number' ? entry.hours : null,
        }))
      : [],
    cost: typeof estimation.cost === 'number' ? estimation.cost : 0,
    note: estimation.note || '',
    inspectionNote: estimation.inspectionNote || '',
    submittedAt: estimation.submittedAt?.toISOString?.() || null,
    isSelected:
      Boolean(selectedEstimationId) && estimationId === String(selectedEstimationId),
    isComplete: isCompleteRequestEstimation(estimation),
  };
}

function serializeRequestWorkLog(workLog) {
  if (!workLog) {
    return null;
  }

  return {
    id: String(workLog._id || workLog.id || ''),
    actor: serializeEstimationSubmitter(workLog.actorId, workLog.actorRole),
    actorRole: workLog.actorRole || null,
    workType: workLog.workType || null,
    startedAt: workLog.startedAt?.toISOString?.() || null,
    stoppedAt: workLog.stoppedAt?.toISOString?.() || null,
    note: workLog.note || '',
    createdAt: workLog.createdAt?.toISOString?.() || null,
  };
}

function serializeLocalizedText(value) {
  if (!value) {
    return {
      en: '',
      de: '',
    };
  }

  return {
    en: value.en || '',
    de: value.de || '',
  };
}

function serializeBookServiceLabel(value) {
  const serialized = serializeLocalizedText(value);
  const english = serialized.en.trim().toLowerCase();
  const german = serialized.de.trim().toLowerCase();

  // WHY: Migrate legacy "create account" copy into the new public booking language without requiring an immediate manual DB edit.
  if (
    english === 'create customer account' ||
    german === 'kundenkonto erstellen'
  ) {
    return {
      en: 'Book a service',
      de: 'Service buchen',
    };
  }

  return serialized;
}

function serializeCompanyProfile(profile) {
  if (!profile) {
    return null;
  }

  return {
    id: String(profile._id || profile.id),
    siteKey: profile.siteKey || 'default',
    companyName: profile.companyName || '',
    legalName: profile.legalName || '',
    category: serializeLocalizedText(profile.category),
    tagline: serializeLocalizedText(profile.tagline),
    heroTitle: serializeLocalizedText(profile.heroTitle),
    heroSubtitle: serializeLocalizedText(profile.heroSubtitle),
    adminLoginLabel: serializeLocalizedText(profile.adminLoginLabel),
    createAccountLabel: serializeBookServiceLabel(profile.createAccountLabel),
    customerLoginLabel: serializeLocalizedText(profile.customerLoginLabel),
    staffLoginLabel: serializeLocalizedText(profile.staffLoginLabel),
    heroPanelTitle: serializeLocalizedText(profile.heroPanelTitle),
    heroPanelSubtitle: serializeLocalizedText(profile.heroPanelSubtitle),
    heroBullets: Array.isArray(profile.heroBullets)
      ? profile.heroBullets.map(serializeLocalizedText)
      : [],
    servicesTitle: serializeLocalizedText(profile.servicesTitle),
    serviceCardSubtitle: serializeLocalizedText(profile.serviceCardSubtitle),
    serviceLabels: Array.isArray(profile.serviceLabels)
      ? profile.serviceLabels.map((service) => {
          return {
            key: service.key || '',
            label: serializeLocalizedText(service.label),
          };
        })
      : [],
    howItWorksTitle: serializeLocalizedText(profile.howItWorksTitle),
    howItWorksSteps: Array.isArray(profile.howItWorksSteps)
      ? profile.howItWorksSteps.map((step) => {
          return {
            title: serializeLocalizedText(step.title),
            subtitle: serializeLocalizedText(step.subtitle),
          };
        })
      : [],
    contactSectionTitle: serializeLocalizedText(profile.contactSectionTitle),
    contactSectionSubtitle: serializeLocalizedText(
      profile.contactSectionSubtitle,
    ),
    serviceAreaLabel: serializeLocalizedText(profile.serviceAreaLabel),
    serviceAreaText: serializeLocalizedText(profile.serviceAreaText),
    contact: {
      addressLine1: profile.contact?.addressLine1 || '',
      city: profile.contact?.city || '',
      postalCode: profile.contact?.postalCode || '',
      country: profile.contact?.country || '',
      phone: profile.contact?.phone || '',
      secondaryPhone: profile.contact?.secondaryPhone || '',
      email: profile.contact?.email || '',
      instagramUrl: profile.contact?.instagramUrl || '',
      facebookUrl: profile.contact?.facebookUrl || '',
      hoursLabel: serializeLocalizedText(profile.contact?.hoursLabel),
    },
    primaryColorHex: profile.primaryColorHex || '#1B4D8C',
    accentColorHex: profile.accentColorHex || '#CE7B37',
    createdAt: profile.createdAt?.toISOString?.() || null,
    updatedAt: profile.updatedAt?.toISOString?.() || null,
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
  const scheduleSummary = buildRequestScheduleSummary(request);
  const selectedEstimationId = scheduleSummary.selectedEstimationId;
  const estimations = Array.isArray(request.estimations)
    ? request.estimations
        .map((estimation) =>
          serializeRequestEstimation(estimation, selectedEstimationId),
        )
        .filter(Boolean)
    : [];
  const selectedEstimation =
    estimations.find((estimation) => estimation.isSelected) || null;
  const completeFinalEstimations = getCompleteFinalRequestEstimations(request);

  return {
    id: String(request._id || request.id),
    serviceType: request.serviceType,
    status: request.status,
    source: request.source,
    message: request.message,
    preferredDate: request.preferredDate?.toISOString?.() || null,
    preferredTimeWindow: request.preferredTimeWindow || null,
    accessDetails: serializeRequestAccessDetails(request.accessDetails),
    mediaSummary: serializeRequestMediaSummary(request.mediaSummary),
    assessmentType: request.assessmentType || null,
    assessmentStatus: request.assessmentStatus || null,
    quoteReadinessStatus: request.quoteReadinessStatus || null,
    latestEstimateUpdatedAt:
      request.latestEstimateUpdatedAt?.toISOString?.() || null,
    internalReviewUpdatedAt:
      request.internalReviewUpdatedAt?.toISOString?.() || null,
    quoteReadyAt: request.quoteReadyAt?.toISOString?.() || null,
    quoteReview: serializeQuoteReview(request.quoteReview),
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
    estimations,
    selectedEstimation,
    selectedEstimationId: scheduleSummary.selectedEstimationId,
    hasCompleteEstimation: scheduleSummary.hasCompleteEstimation,
    estimationCount: scheduleSummary.estimationCount,
    completeEstimationCount: scheduleSummary.completeEstimationCount,
    completeFinalEstimationCount: completeFinalEstimations.length,
    calendarStatus: scheduleSummary.calendarStatus,
    calendarStartDate: scheduleSummary.calendarStartDate?.toISOString?.() || null,
    calendarEndDate: scheduleSummary.calendarEndDate?.toISOString?.() || null,
    calendarSource: scheduleSummary.calendarSource,
    estimatedStartDate: scheduleSummary.estimatedStartDate?.toISOString?.() || null,
    estimatedEndDate: scheduleSummary.estimatedEndDate?.toISOString?.() || null,
    estimatedHours: scheduleSummary.estimatedHours,
    estimatedHoursPerDay: scheduleSummary.estimatedHoursPerDay,
    estimatedDays: scheduleSummary.estimatedDays,
    estimatedCost: scheduleSummary.estimatedCost,
    actualStartDate: scheduleSummary.actualStartDate?.toISOString?.() || null,
    actualEndDate: scheduleSummary.actualEndDate?.toISOString?.() || null,
    totalHoursWorked: scheduleSummary.totalHoursWorked,
    totalDaysWorked: scheduleSummary.totalDaysWorked,
    aiControlEnabled: Boolean(request.aiControlEnabled),
    queueEnteredAt: request.queueEnteredAt?.toISOString?.() || null,
    attendedAt: request.attendedAt?.toISOString?.() || null,
    projectStartedAt: request.projectStartedAt?.toISOString?.() || null,
    finishedAt: request.finishedAt?.toISOString?.() || null,
    closedAt: request.closedAt?.toISOString?.() || null,
    messageCount: Array.isArray(request.messages) ? request.messages.length : 0,
    messages: Array.isArray(request.messages)
      ? request.messages.map(serializeRequestMessage).filter(Boolean)
      : [],
    workLogs: Array.isArray(request.workLogs)
      ? request.workLogs.map(serializeRequestWorkLog).filter(Boolean)
      : [],
    createdAt: request.createdAt?.toISOString?.() || null,
    updatedAt: request.updatedAt?.toISOString?.() || null,
  };
}

module.exports = {
  serializeCompanyProfile,
  serializeInternalChatMessage,
  serializeInternalChatThread,
  serializeLocalizedText,
  serializeRequestEstimation,
  serializeRequestMessage,
  serializeServiceRequest,
  serializeStaffInvite,
  serializeUser,
};
