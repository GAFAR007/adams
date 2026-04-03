/**
 * WHAT: Handles unauthenticated homepage-content requests.
 * WHY: The public site needs a thin HTTP boundary separate from admin, staff, and customer flows.
 * HOW: Build request log context, delegate to the public service, and return safe serialized content.
 */

const {
  LOG_STEPS,
} = require("../constants/app.constants");
const {
  asyncHandler,
} = require("../utils/async-handler");
const {
  buildRequestLog,
  logInfo,
} = require("../utils/logger");
const publicService = require("../services/public.service");
const serviceConciergeService = require("../services/service-concierge.service");

const publicCompanyProfileController =
  asyncHandler(async (req, res) => {
    const logContext = buildRequestLog(req, {
      layer: "controller",
      operation: "PublicGetCompanyProfile",
      intent:
        "Return the public company profile for the landing page",
    });

    const result =
      await publicService.getCompanyProfile(
        logContext,
      );
    res.status(200).json(result);

    logInfo({
      ...logContext,
      step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
    });
  });

const publicServiceConciergeReplyController =
  asyncHandler(async (req, res) => {
    const logContext = buildRequestLog(req, {
      layer: "controller",
      operation: "PublicServiceConciergeReply",
      intent:
        "Return the next customer-care reply for the public booking chat",
    });

    const result =
      await serviceConciergeService.generatePublicServiceConciergeReply(
        req.body,
        logContext,
      );
    res.status(200).json(result);

    logInfo({
      ...logContext,
      step: LOG_STEPS.CONTROLLER_RESPONSE_OK,
    });
  });

module.exports = {
  publicCompanyProfileController,
  publicServiceConciergeReplyController,
};
