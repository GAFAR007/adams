/**
 * WHAT: Builds the versioned API router tree for the backend.
 * WHY: A single assembly point keeps route registration predictable as the API grows.
 * HOW: Mount domain routers under `/api/v1` with a lightweight version root response.
 */

const express = require("express");

const {
  createAdminRouter,
} = require("./admin.routes");
const {
  createAuthRouter,
} = require("./auth.routes");
const {
  createCustomerRouter,
} = require("./customer.routes");
const {
  createPublicRouter,
} = require("./public.routes");
const {
  createStaffRouter,
} = require("./staff.routes");

function createApiRouter() {
  const router = express.Router();

  router.get("/", (req, res) => {
    // A tiny version root helps local debugging confirm the mounted API prefix quickly.
    res
      .status(200)
      .json({
        message: "API v1 is running",
      });
  });

  router.use(
    "/public",
    createPublicRouter(),
  );
  router.use(
    "/auth",
    createAuthRouter(),
  );
  router.use(
    "/admin",
    createAdminRouter(),
  );
  router.use(
    "/staff",
    createStaffRouter(),
  );
  router.use(
    "/customer",
    createCustomerRouter(),
  );

  return router;
}

module.exports = { createApiRouter };
