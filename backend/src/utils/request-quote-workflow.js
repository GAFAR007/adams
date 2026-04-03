/**
 * WHAT: Builds structured quote-workflow chat events for staff-facing request threads.
 * WHY: Estimate updates, admin review, and customer-care handoff should render as cards instead of opaque paragraphs.
 * HOW: Return compact action payloads and helper text summaries for the request message builders.
 */

const {
  REQUEST_ESTIMATION_STAGES,
  REQUEST_MESSAGE_ACTIONS,
  REQUEST_QUOTE_READINESS_STATUSES,
  REQUEST_REVIEW_KINDS,
  STAFF_TYPES,
} = require('../constants/app.constants');

function formatDateValue(value) {
  if (!value) {
    return null;
  }

  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date.toISOString();
}

function resolveStaffTypeLabel(staffType) {
  switch (staffType) {
    case STAFF_TYPES.CUSTOMER_CARE:
      return 'Customer Care';
    case STAFF_TYPES.CONTRACTOR:
      return 'Contractor';
    default:
      return 'Technician';
  }
}

function buildEstimateUpdatedWorkflowEvent({ request, estimation }) {
  const submitterName =
    estimation?.submittedBy?.fullName ||
    [
      estimation?.submittedBy?.firstName,
      estimation?.submittedBy?.lastName,
    ].filter(Boolean).join(' ') ||
    'Staff';
  const stage = estimation?.stage || REQUEST_ESTIMATION_STAGES.FINAL;
  const readinessStatus =
    request?.quoteReadinessStatus ||
    REQUEST_QUOTE_READINESS_STATUSES.AWAITING_ESTIMATE;
  const readyForReview =
    readinessStatus ===
    REQUEST_QUOTE_READINESS_STATUSES.QUOTE_READY_FOR_INTERNAL_REVIEW;
  const siteReviewReadyForReview =
    readinessStatus ===
    REQUEST_QUOTE_READINESS_STATUSES.SITE_REVIEW_READY_FOR_INTERNAL_REVIEW;

  return {
    actionType: REQUEST_MESSAGE_ACTIONS.ESTIMATE_UPDATED,
    text: `Estimate updated by ${submitterName}.`,
    actionPayload: {
      title: 'Estimate updated',
      summary: siteReviewReadyForReview
        ? 'Site review booking is ready for internal review.'
        : readyForReview
        ? 'Ready for internal review.'
        : stage === REQUEST_ESTIMATION_STAGES.DRAFT
        ? 'Saved as draft.'
        : 'Estimate is still incomplete.',
      submitterName,
      submitterStaffType: estimation?.submitterStaffType || null,
      submitterStaffTypeLabel: resolveStaffTypeLabel(
        estimation?.submitterStaffType,
      ),
      estimationId: estimation?._id ? String(estimation._id) : null,
      stage,
      readinessStatus,
      estimatedStartDate: formatDateValue(estimation?.estimatedStartDate),
      estimatedEndDate: formatDateValue(estimation?.estimatedEndDate),
      estimatedHoursPerDay:
        typeof estimation?.estimatedHoursPerDay === 'number'
          ? estimation.estimatedHoursPerDay
          : null,
      estimatedCost:
        typeof estimation?.cost === 'number' ? estimation.cost : null,
    },
  };
}

function buildInternalReviewWorkflowEvent({ review, estimation, adminName }) {
  const isSiteReview = review?.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW;
  return {
    actionType: REQUEST_MESSAGE_ACTIONS.INTERNAL_REVIEW_UPDATED,
    text: 'Internal review updated.',
    actionPayload: {
      title: isSiteReview
        ? 'Site review internal review updated'
        : 'Internal review updated',
      summary: isSiteReview
        ? 'Site review booking package reviewed and refreshed for customer care.'
        : 'Quote package reviewed and refreshed for customer care.',
      reviewedByName: adminName || 'Admin Team',
      reviewKind: review?.kind || REQUEST_REVIEW_KINDS.QUOTATION,
      totalAmount:
        typeof review?.totalAmount === 'number' ? review.totalAmount : null,
      currency: review?.currency || 'EUR',
      siteReviewDate: formatDateValue(review?.siteReviewDate),
      siteReviewStartTime: review?.siteReviewStartTime || '',
      siteReviewEndTime: review?.siteReviewEndTime || '',
      plannedStartDate: formatDateValue(review?.plannedStartDate),
      plannedExpectedEndDate: formatDateValue(review?.plannedExpectedEndDate),
      sourceEstimateOwnerName:
        estimation?.submittedBy?.fullName ||
        [
          estimation?.submittedBy?.firstName,
          estimation?.submittedBy?.lastName,
        ].filter(Boolean).join(' ') ||
        '',
      sourceEstimateOwnerStaffType: estimation?.submitterStaffType || null,
      sourceEstimateOwnerStaffTypeLabel: resolveStaffTypeLabel(
        estimation?.submitterStaffType,
      ),
    },
  };
}

function buildSiteReviewReadyForInternalReviewWorkflowEvent({ estimation }) {
  return {
    actionType: REQUEST_MESSAGE_ACTIONS.SITE_REVIEW_READY_FOR_INTERNAL_REVIEW,
    text: 'Site review booking ready for internal review.',
    actionPayload: {
      title: 'Site review ready for internal review',
      summary:
        'A priced site review booking is available for admin review before customer care sends it.',
      sourceEstimateOwnerName:
        estimation?.submittedBy?.fullName ||
        [
          estimation?.submittedBy?.firstName,
          estimation?.submittedBy?.lastName,
        ].filter(Boolean).join(' ') ||
        '',
      sourceEstimateOwnerStaffType: estimation?.submitterStaffType || null,
      sourceEstimateOwnerStaffTypeLabel: resolveStaffTypeLabel(
        estimation?.submitterStaffType,
      ),
      siteReviewDate: formatDateValue(estimation?.siteReviewDate),
      siteReviewStartTime: estimation?.siteReviewStartTime || '',
      siteReviewEndTime: estimation?.siteReviewEndTime || '',
    },
  };
}

function buildQuoteReadyForInternalReviewWorkflowEvent({ estimation }) {
  return {
    actionType: REQUEST_MESSAGE_ACTIONS.QUOTE_READY_FOR_INTERNAL_REVIEW,
    text: 'Ready for internal review.',
    actionPayload: {
      title: 'Ready for internal review',
      summary:
        'At least one complete final estimate is available for admin review.',
      sourceEstimateOwnerName:
        estimation?.submittedBy?.fullName ||
        [
          estimation?.submittedBy?.firstName,
          estimation?.submittedBy?.lastName,
        ].filter(Boolean).join(' ') ||
        '',
      sourceEstimateOwnerStaffType: estimation?.submitterStaffType || null,
      sourceEstimateOwnerStaffTypeLabel: resolveStaffTypeLabel(
        estimation?.submitterStaffType,
      ),
    },
  };
}

function buildQuoteReadyForCustomerCareWorkflowEvent({ review, estimation }) {
  return {
    actionType: REQUEST_MESSAGE_ACTIONS.QUOTATION_READY_FOR_CUSTOMER_CARE,
    text: 'Quotation ready for customer care.',
    actionPayload: {
      title: 'Quotation ready to send',
      summary: 'Customer care can now send the quotation to the customer.',
      totalAmount:
        typeof review?.totalAmount === 'number' ? review.totalAmount : null,
      currency: review?.currency || 'EUR',
      plannedStartDate: formatDateValue(review?.plannedStartDate),
      plannedExpectedEndDate: formatDateValue(review?.plannedExpectedEndDate),
      sourceEstimateOwnerName:
        estimation?.submittedBy?.fullName ||
        [
          estimation?.submittedBy?.firstName,
          estimation?.submittedBy?.lastName,
        ].filter(Boolean).join(' ') ||
        '',
      sourceEstimateOwnerStaffType: estimation?.submitterStaffType || null,
      sourceEstimateOwnerStaffTypeLabel: resolveStaffTypeLabel(
        estimation?.submitterStaffType,
      ),
    },
  };
}

function buildSiteReviewReadyForCustomerCareWorkflowEvent({ review, estimation }) {
  return {
    actionType: REQUEST_MESSAGE_ACTIONS.SITE_REVIEW_READY_FOR_CUSTOMER_CARE,
    text: 'Site review booking ready for customer care.',
    actionPayload: {
      title: 'Site review ready to send',
      summary: 'Customer care can now send the site review booking to the customer.',
      reviewKind: REQUEST_REVIEW_KINDS.SITE_REVIEW,
      totalAmount:
        typeof review?.totalAmount === 'number' ? review.totalAmount : null,
      currency: review?.currency || 'EUR',
      siteReviewDate: formatDateValue(review?.siteReviewDate),
      siteReviewStartTime: review?.siteReviewStartTime || '',
      siteReviewEndTime: review?.siteReviewEndTime || '',
      sourceEstimateOwnerName:
        estimation?.submittedBy?.fullName ||
        [
          estimation?.submittedBy?.firstName,
          estimation?.submittedBy?.lastName,
        ].filter(Boolean).join(' ') ||
        '',
      sourceEstimateOwnerStaffType: estimation?.submitterStaffType || null,
      sourceEstimateOwnerStaffTypeLabel: resolveStaffTypeLabel(
        estimation?.submitterStaffType,
      ),
    },
  };
}

function buildQuoteInvalidatedWorkflowEvent() {
  return {
    actionType: REQUEST_MESSAGE_ACTIONS.QUOTATION_INVALIDATED,
    text: 'Estimate changed, review required again.',
    actionPayload: {
      title: 'Review required again',
      summary:
        'A staff estimate changed after internal review. Customer care send is paused until review is refreshed.',
    },
  };
}

function buildQuotationSentWorkflowEvent({ invoice, estimation, senderName }) {
  if (invoice?.kind === REQUEST_REVIEW_KINDS.SITE_REVIEW) {
    return {
      actionType: REQUEST_MESSAGE_ACTIONS.SITE_REVIEW_SENT,
      text: 'Site review booking sent to customer.',
      actionPayload: {
        title: 'Site review booking sent',
        summary: 'Customer care sent the paid site review booking to the customer.',
        reviewKind: REQUEST_REVIEW_KINDS.SITE_REVIEW,
        invoiceNumber: invoice?.invoiceNumber || '',
        totalAmount:
          typeof invoice?.amount === 'number' ? invoice.amount : null,
        currency: invoice?.currency || 'EUR',
        siteReviewDate: formatDateValue(invoice?.siteReviewDate),
        siteReviewStartTime: invoice?.siteReviewStartTime || '',
        siteReviewEndTime: invoice?.siteReviewEndTime || '',
        senderName: senderName || 'Customer Care',
        sourceEstimateOwnerName:
          estimation?.submittedBy?.fullName ||
          [
            estimation?.submittedBy?.firstName,
            estimation?.submittedBy?.lastName,
          ].filter(Boolean).join(' ') ||
          '',
        sourceEstimateOwnerStaffType: estimation?.submitterStaffType || null,
        sourceEstimateOwnerStaffTypeLabel: resolveStaffTypeLabel(
          estimation?.submitterStaffType,
        ),
      },
    };
  }

  return {
    actionType: REQUEST_MESSAGE_ACTIONS.QUOTATION_SENT,
    text: 'Quotation sent to customer.',
    actionPayload: {
      title: 'Quotation sent',
      summary: 'Customer care sent the quotation to the customer.',
      invoiceNumber: invoice?.invoiceNumber || '',
      totalAmount:
        typeof invoice?.amount === 'number' ? invoice.amount : null,
      currency: invoice?.currency || 'EUR',
      plannedStartDate: formatDateValue(invoice?.plannedStartDate),
      plannedExpectedEndDate: formatDateValue(invoice?.plannedExpectedEndDate),
      senderName: senderName || 'Customer Care',
      sourceEstimateOwnerName:
        estimation?.submittedBy?.fullName ||
        [
          estimation?.submittedBy?.firstName,
          estimation?.submittedBy?.lastName,
        ].filter(Boolean).join(' ') ||
        '',
      sourceEstimateOwnerStaffType: estimation?.submitterStaffType || null,
      sourceEstimateOwnerStaffTypeLabel: resolveStaffTypeLabel(
        estimation?.submitterStaffType,
      ),
    },
  };
}

module.exports = {
  buildEstimateUpdatedWorkflowEvent,
  buildInternalReviewWorkflowEvent,
  buildQuoteInvalidatedWorkflowEvent,
  buildSiteReviewReadyForCustomerCareWorkflowEvent,
  buildSiteReviewReadyForInternalReviewWorkflowEvent,
  buildQuoteReadyForInternalReviewWorkflowEvent,
  buildQuoteReadyForCustomerCareWorkflowEvent,
  buildQuotationSentWorkflowEvent,
  resolveStaffTypeLabel,
};
