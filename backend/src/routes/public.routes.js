/**
 * WHAT: Registers unauthenticated public-content routes.
 * WHY: The landing page should be able to fetch company content without requiring login.
 * HOW: Mount a small public router that exposes only safe read-only site data.
 */

const express = require('express');

const {
  publicCompanyProfileController,
  publicServiceConciergeReplyController,
} = require('../controllers/public.controller');
const { validateRequest } = require('../middleware/validate.middleware');
const {
  publicServiceConciergeReplyValidator,
} = require('../validators/public.validators');

function createPublicRouter() {
  const router = express.Router();

  router.get(
    '/company-profile',
    publicCompanyProfileController,
  );
  router.post(
    '/service-concierge/reply',
    publicServiceConciergeReplyValidator,
    validateRequest,
    publicServiceConciergeReplyController,
  );

  return router;
}

module.exports = { createPublicRouter };
