/**
 * WHAT: Centralizes request estimation, calendar, and work-log derivations.
 * WHY: Admin, staff, and customer payloads should all interpret scheduling data the same way.
 * HOW: Expose helpers for completeness checks, selected estimation lookup, calendar ranges, and work totals.
 */

const {
  REQUEST_ASSESSMENT_STATUSES,
  REQUEST_ESTIMATION_STAGES,
  REQUEST_STATUSES,
} = require('../constants/app.constants');

function normalizeDateValue(value) {
  if (!value) {
    return null;
  }

  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function toRoundedNumber(value, decimals = 2) {
  const multiplier = 10 ** decimals;
  return Math.round(Number(value || 0) * multiplier) / multiplier;
}

function calculateEstimatedDays(startDate, endDate) {
  const start = normalizeDateValue(startDate);
  const end = normalizeDateValue(endDate);
  if (!start || !end || end < start) {
    return null;
  }

  const startDay = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  const endDay = new Date(end.getFullYear(), end.getMonth(), end.getDate());
  const diff = endDay.getTime() - startDay.getTime();
  return Math.floor(diff / 86400000) + 1;
}

function normalizeEstimatedDailySchedule(estimatedDailySchedule) {
  if (!Array.isArray(estimatedDailySchedule)) {
    return [];
  }

  return estimatedDailySchedule
    .map((entry) => {
      const date = normalizeDateValue(entry?.date);
      const parsedHours = Number(entry?.hours);

      return {
        date,
        startTime:
          typeof entry?.startTime === 'string' ? entry.startTime.trim() : '',
        endTime: typeof entry?.endTime === 'string' ? entry.endTime.trim() : '',
        hours:
          Number.isFinite(parsedHours) &&
          parsedHours > 0 &&
          parsedHours <= 10
            ? toRoundedNumber(parsedHours)
            : null,
      };
    })
    .filter((entry) => entry.date);
}

function calculateEstimatedHoursFromDailySchedule(estimatedDailySchedule) {
  const normalizedSchedule = normalizeEstimatedDailySchedule(estimatedDailySchedule);
  if (!normalizedSchedule.length) {
    return null;
  }

  const totalHours = normalizedSchedule.reduce((sum, entry) => {
    return sum + (typeof entry.hours === 'number' ? entry.hours : 0);
  }, 0);

  return totalHours > 0 ? toRoundedNumber(totalHours) : null;
}

function isCompleteRequestEstimation(estimation) {
  if (!estimation) {
    return false;
  }

  const start = normalizeDateValue(estimation.estimatedStartDate);
  const end = normalizeDateValue(estimation.estimatedEndDate);
  const cost = typeof estimation.cost === 'number'
    ? estimation.cost
    : Number(estimation.cost);
  const hoursPerDay =
    typeof estimation.estimatedHoursPerDay === 'number'
      ? estimation.estimatedHoursPerDay
      : Number(estimation.estimatedHoursPerDay);
  const normalizedSchedule = normalizeEstimatedDailySchedule(
    estimation.estimatedDailySchedule,
  );

  return Boolean(
    start &&
    end &&
    end >= start &&
    Number.isFinite(hoursPerDay) &&
      hoursPerDay > 0 &&
      hoursPerDay <= 10 &&
    normalizedSchedule.length > 0 &&
    normalizedSchedule.every((entry) => typeof entry.hours === 'number') &&
    Number.isFinite(cost) &&
    cost > 0,
  );
}

function isSiteReviewBookingReady(estimation) {
  if (!estimation) {
    return false;
  }

  const siteReviewDate = normalizeDateValue(estimation.siteReviewDate);
  const siteReviewCost =
    typeof estimation.siteReviewCost === 'number'
      ? estimation.siteReviewCost
      : Number(estimation.siteReviewCost);

  return Boolean(
    siteReviewDate &&
      String(estimation.siteReviewStartTime || '').trim() &&
      String(estimation.siteReviewEndTime || '').trim() &&
      Number.isFinite(siteReviewCost) &&
      siteReviewCost > 0,
  );
}

function resolveEstimationStage(estimation) {
  return estimation?.stage || REQUEST_ESTIMATION_STAGES.FINAL;
}

function isFinalRequestEstimation(estimation) {
  return resolveEstimationStage(estimation) === REQUEST_ESTIMATION_STAGES.FINAL;
}

function isCompleteFinalRequestEstimation(estimation) {
  return isFinalRequestEstimation(estimation) && isCompleteRequestEstimation(estimation);
}

function sortEstimationsBySubmittedAt(estimations) {
  return [...estimations].sort((left, right) => {
    const leftDate = normalizeDateValue(left.submittedAt)?.getTime() || 0;
    const rightDate = normalizeDateValue(right.submittedAt)?.getTime() || 0;
    return leftDate - rightDate;
  });
}

function getCompleteRequestEstimations(request) {
  return sortEstimationsBySubmittedAt(
    (Array.isArray(request?.estimations) ? request.estimations : []).filter(
      isCompleteRequestEstimation,
    ),
  );
}

function getCompleteFinalRequestEstimations(request) {
  return sortEstimationsBySubmittedAt(
    (Array.isArray(request?.estimations) ? request.estimations : []).filter(
      isCompleteFinalRequestEstimation,
    ),
  );
}

function getReadySiteReviewEstimations(request) {
  return sortEstimationsBySubmittedAt(
    (Array.isArray(request?.estimations) ? request.estimations : []).filter(
      isSiteReviewBookingReady,
    ),
  );
}

function getSelectedRequestEstimation(request) {
  const allEstimations = Array.isArray(request?.estimations)
    ? request.estimations
    : [];
  const selectedId = request?.selectedEstimationId
    ? String(request.selectedEstimationId)
    : '';

  if (selectedId) {
    const selected = allEstimations.find((estimation) => {
      return String(estimation?._id || estimation?.id || '') === selectedId;
    });

    if (isCompleteFinalRequestEstimation(selected)) {
      return selected;
    }
  }

  const completeEstimations = getCompleteFinalRequestEstimations(request);
  return completeEstimations.length > 0
    ? completeEstimations[completeEstimations.length - 1]
    : null;
}

function getSelectedReadySiteReviewEstimation(request) {
  const readyEstimations = getReadySiteReviewEstimations(request);
  const selectedId = request?.selectedEstimationId
    ? String(request.selectedEstimationId)
    : '';

  if (selectedId) {
    const selected = readyEstimations.find((estimation) => {
      return String(estimation?._id || estimation?.id || '') === selectedId;
    });

    if (selected) {
      return selected;
    }
  }

  return readyEstimations.length > 0
    ? readyEstimations[readyEstimations.length - 1]
    : null;
}

function buildRequestCalendarWindow(request) {
  const selectedEstimation = getSelectedRequestEstimation(request);
  if (selectedEstimation) {
    return {
      startDate: normalizeDateValue(selectedEstimation.estimatedStartDate),
      endDate: normalizeDateValue(selectedEstimation.estimatedEndDate),
      source: request?.selectedEstimationId ? 'selected_estimation' : 'latest_estimation',
    };
  }

  const selectedSiteReviewEstimation = getSelectedReadySiteReviewEstimation(request);
  if (selectedSiteReviewEstimation) {
    const siteReviewDate = normalizeDateValue(selectedSiteReviewEstimation.siteReviewDate);
    if (siteReviewDate) {
      return {
        startDate: siteReviewDate,
        endDate: siteReviewDate,
        source: request?.selectedEstimationId
          ? 'selected_site_review'
          : 'latest_site_review',
      };
    }
  }

  const fallbackDate =
    normalizeDateValue(request?.preferredDate) ||
    normalizeDateValue(request?.attendedAt) ||
    normalizeDateValue(request?.queueEnteredAt) ||
    normalizeDateValue(request?.createdAt);

  return {
    startDate: fallbackDate,
    endDate: fallbackDate,
    source: request?.preferredDate ? 'preferred_date' : 'request_created',
  };
}

function buildRequestCalendarStatus(request) {
  const hasCompleteEstimation =
    getCompleteFinalRequestEstimations(request).length > 0;

  if (
    request?.assessmentStatus === REQUEST_ASSESSMENT_STATUSES.SITE_VISIT_SCHEDULED
  ) {
    return 'scheduled';
  }

  switch (request?.status) {
    case REQUEST_STATUSES.CLOSED:
      return 'completed';
    case REQUEST_STATUSES.WORK_DONE:
      return 'finished';
    case REQUEST_STATUSES.PROJECT_STARTED:
      return 'started';
    case REQUEST_STATUSES.PENDING_START:
      return 'pending_start';
    case REQUEST_STATUSES.APPOINTMENT_CONFIRMED:
      return 'scheduled';
    case REQUEST_STATUSES.QUOTED:
      return 'quoted';
    case REQUEST_STATUSES.ASSIGNED:
      return hasCompleteEstimation ? 'assigned' : 'pending_estimation';
    case REQUEST_STATUSES.UNDER_REVIEW:
      return hasCompleteEstimation ? 'estimated' : 'pending_estimation';
    case REQUEST_STATUSES.SUBMITTED:
    default:
      return hasCompleteEstimation ? 'estimated' : 'pending_estimation';
  }
}

function summarizeRequestWorkLogs(request) {
  const workLogs = Array.isArray(request?.workLogs) ? request.workLogs : [];
  const dayKeys = new Set();
  let totalMinutes = 0;
  let actualStartDate = normalizeDateValue(request?.projectStartedAt);
  let actualEndDate = normalizeDateValue(request?.finishedAt);

  for (const workLog of workLogs) {
    const startedAt = normalizeDateValue(workLog?.startedAt);
    const stoppedAt = normalizeDateValue(workLog?.stoppedAt);

    if (startedAt) {
      dayKeys.add(startedAt.toISOString().slice(0, 10));
      if (!actualStartDate || startedAt < actualStartDate) {
        actualStartDate = startedAt;
      }
    }

    if (stoppedAt && (!actualEndDate || stoppedAt > actualEndDate)) {
      actualEndDate = stoppedAt;
    }

    if (startedAt && stoppedAt && stoppedAt > startedAt) {
      totalMinutes += Math.round((stoppedAt.getTime() - startedAt.getTime()) / 60000);
    }
  }

  return {
    actualStartDate,
    actualEndDate,
    totalHoursWorked: toRoundedNumber(totalMinutes / 60),
    totalDaysWorked: dayKeys.size,
  };
}

function buildRequestScheduleSummary(request) {
  const selectedEstimation = getSelectedRequestEstimation(request);
  const calendarWindow = buildRequestCalendarWindow(request);
  const workSummary = summarizeRequestWorkLogs(request);
  const completeEstimations = getCompleteFinalRequestEstimations(request);

  return {
    estimationCount: Array.isArray(request?.estimations) ? request.estimations.length : 0,
    completeEstimationCount: completeEstimations.length,
    hasCompleteEstimation: completeEstimations.length > 0,
    selectedEstimationId: selectedEstimation
      ? String(selectedEstimation._id || selectedEstimation.id || '')
      : null,
    calendarStatus: buildRequestCalendarStatus(request),
    calendarStartDate: calendarWindow.startDate,
    calendarEndDate: calendarWindow.endDate,
    calendarSource: calendarWindow.source,
    estimatedStartDate: normalizeDateValue(selectedEstimation?.estimatedStartDate),
    estimatedEndDate: normalizeDateValue(selectedEstimation?.estimatedEndDate),
    estimatedHours: selectedEstimation?.estimatedHours || null,
    estimatedHoursPerDay: selectedEstimation?.estimatedHoursPerDay || null,
    estimatedDays:
      selectedEstimation?.estimatedDays ||
      calculateEstimatedDays(
        selectedEstimation?.estimatedStartDate,
        selectedEstimation?.estimatedEndDate,
      ),
    estimatedCost:
      typeof selectedEstimation?.cost === 'number' ? selectedEstimation.cost : null,
    actualStartDate: workSummary.actualStartDate,
    actualEndDate: workSummary.actualEndDate,
    totalHoursWorked: workSummary.totalHoursWorked,
    totalDaysWorked: workSummary.totalDaysWorked,
  };
}

function requestOverlapsCalendarRange(request, rangeStart, rangeEnd) {
  const start = normalizeDateValue(rangeStart);
  const end = normalizeDateValue(rangeEnd);
  if (!start || !end) {
    return true;
  }

  const calendarWindow = buildRequestCalendarWindow(request);
  const itemStart = normalizeDateValue(calendarWindow.startDate);
  const itemEnd = normalizeDateValue(calendarWindow.endDate) || itemStart;
  if (!itemStart || !itemEnd) {
    return false;
  }

  return itemStart <= end && itemEnd >= start;
}

module.exports = {
  buildRequestCalendarStatus,
  buildRequestCalendarWindow,
  buildRequestScheduleSummary,
  calculateEstimatedHoursFromDailySchedule,
  calculateEstimatedDays,
  getCompleteFinalRequestEstimations,
  getCompleteRequestEstimations,
  getReadySiteReviewEstimations,
  getSelectedRequestEstimation,
  isCompleteFinalRequestEstimation,
  isCompleteRequestEstimation,
  isFinalRequestEstimation,
  isSiteReviewBookingReady,
  normalizeDateValue,
  normalizeEstimatedDailySchedule,
  requestOverlapsCalendarRange,
  resolveEstimationStage,
  summarizeRequestWorkLogs,
};
