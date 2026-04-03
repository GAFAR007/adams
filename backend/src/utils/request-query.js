/**
 * WHAT: Shares the standard request population shape across services.
 * WHY: Admin, staff, and customer payloads should expose the same related request data.
 * HOW: Apply the common user population paths to any request query before execution.
 */

const REQUEST_USER_SELECT =
  'firstName lastName email phone role staffType status staffAvailability createdAt updatedAt';

function populateServiceRequestRelations(query) {
  return query
    .populate('customer', REQUEST_USER_SELECT)
    .populate('assignedStaff', REQUEST_USER_SELECT)
    .populate('estimations.submittedBy', REQUEST_USER_SELECT)
    .populate('workLogs.actorId', REQUEST_USER_SELECT);
}

module.exports = {
  populateServiceRequestRelations,
};
