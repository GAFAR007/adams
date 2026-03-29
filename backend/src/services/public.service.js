/**
 * WHAT: Implements the public landing-page content lookup.
 * WHY: The homepage should read company information from MongoDB instead of frontend constants.
 * HOW: Load the seeded company profile and serialize it into a safe public payload.
 */

const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
} = require('../constants/app.constants');
const {
  CompanyProfile,
} = require('../models/company-profile.model');
const {
  AppError,
} = require('../utils/app-error');
const {
  logInfo,
} = require('../utils/logger');
const {
  serializeCompanyProfile,
} = require('../utils/serializers');

async function getCompanyProfile(logContext) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation: 'PublicGetCompanyProfile',
    intent: 'Load the public company profile for the landing page',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'PublicGetCompanyProfile',
    intent: 'Fetch the seeded public company profile from MongoDB',
  });

  const profile = await CompanyProfile.findOne({
    siteKey: 'default',
  });

  if (!profile) {
    throw new AppError({
      message: 'Company profile not found',
      statusCode: 404,
      classification: ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode: 'PUBLIC_COMPANY_PROFILE_NOT_FOUND',
      resolutionHint: 'Seed the database or create a company profile document',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'PublicGetCompanyProfile',
    intent: 'Confirm the homepage company profile is ready for response shaping',
  });

  return {
    message: 'Company profile fetched successfully',
    companyProfile: serializeCompanyProfile(profile),
  };
}

module.exports = {
  getCompanyProfile,
};
