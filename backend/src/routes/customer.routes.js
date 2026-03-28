/**
 * WHAT: Registers customer-only endpoints for service-request creation and listing.
 * WHY: Customer request ownership must be protected from other roles and anonymous traffic.
 * HOW: Apply customer auth guards, validate request payloads, and delegate to customer controllers.
 */

const express = require("express");

const {
  customerCreateRequestController,
  customerListRequestsController,
  customerPostRequestMessageController,
} = require("../controllers/customer.controller");
const {
  USER_ROLES,
} = require("../constants/app.constants");
const {
  requireAuth,
  requireRoles,
} = require("../middleware/auth.middleware");
const {
  validateRequest,
} = require("../middleware/validate.middleware");
const {
  customerCreateRequestValidator,
  customerPostRequestMessageValidator,
} = require("../validators/customer.validators");

function createCustomerRouter() {
  const router = express.Router();

  router.use(
    requireAuth,
    requireRoles([USER_ROLES.CUSTOMER]),
  );

  router.post(
    "/requests",
    customerCreateRequestValidator,
    validateRequest,
    customerCreateRequestController,
  );
  router.get(
    "/requests",
    customerListRequestsController,
  );
  router.post(
    "/requests/:requestId/messages",
    customerPostRequestMessageValidator,
    validateRequest,
    customerPostRequestMessageController,
  );

  return router;
}

module.exports = {
  createCustomerRouter,
};
