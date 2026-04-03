/**
 * WHAT: Implements customer registration, shared login, logout, refresh, and session bootstrap.
 * WHY: Authentication should stay in one service so every role follows the same security rules.
 * HOW: Validate account state, hash/check passwords, issue tokens, and return safe user payloads.
 */

const crypto = require('crypto');

const bcrypt = require("bcryptjs");
const jwt = require('jsonwebtoken');

const { env } = require('../config/env');
const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
  USER_ROLES,
  USER_STATUSES,
} = require("../constants/app.constants");
const {
  CustomerRegistrationVerification,
} = require('../models/customer-registration-verification.model');
const {
  User,
} = require("../models/user.model");
const {
  sendCustomerRegistrationCodeEmail,
} = require('./email.service');
const {
  AppError,
} = require("../utils/app-error");
const { hashValue } = require('../utils/security');
const {
  logError,
  logInfo,
} = require("../utils/logger");
const {
  serializeUser,
} = require("../utils/serializers");
const {
  issueSessionTokens,
  revokeRefreshSession,
  rotateRefreshSession,
} = require("./token.service");

const CUSTOMER_REGISTRATION_PURPOSE =
  'customer_register';

function normalizeEmail(email) {
  return String(email || '')
    .trim()
    .toLowerCase();
}

function createRegistrationCode() {
  return crypto
    .randomInt(0, 1000000)
    .toString()
    .padStart(6, '0');
}

function createCustomerRegistrationVerificationToken(
  verification,
) {
  return jwt.sign(
    {
      email: verification.email,
      purpose: verification.purpose,
      verificationId: String(
        verification._id,
      ),
      tokenType:
        'customer_registration_verification',
    },
    env.jwtCustomerRegistrationSecret,
    {
      expiresIn:
        env.customerRegistrationVerificationTokenTtl,
    },
  );
}

function verifyCustomerRegistrationVerificationToken(
  verificationToken,
) {
  try {
    return jwt.verify(
      verificationToken,
      env.jwtCustomerRegistrationSecret,
    );
  } catch (error) {
    throw new AppError({
      message:
        'Your email verification has expired',
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        'CUSTOMER_REGISTER_VERIFICATION_INVALID',
      resolutionHint:
        'Request a new verification code and try again',
      step: LOG_STEPS.AUTH_FAIL,
    });
  }
}

async function ensureCustomerEmailAvailable(
  email,
) {
  const existingUser =
    await User.findOne({ email });

  if (existingUser) {
    throw new AppError({
      message:
        'This email already has an account. Please log in instead.',
      statusCode: 409,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode:
        'CUSTOMER_REGISTER_EMAIL_TAKEN',
      resolutionHint:
        'Log in instead or reset the password for the existing account',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }
}

async function requestCustomerRegistrationCode(
  payload,
  logContext,
) {
  const normalizedEmail =
    normalizeEmail(payload.email);

  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation:
      'RequestCustomerRegistrationCode',
    intent:
      'Send a one-time email code before customer account creation',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation:
      'RequestCustomerRegistrationCode',
    intent:
      'Check whether the customer email already belongs to an existing account',
  });

  await ensureCustomerEmailAvailable(
    normalizedEmail,
  );

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation:
      'RequestCustomerRegistrationCode',
    intent:
      'Confirm the customer email is available for a new account',
  });

  const code =
    createRegistrationCode();
  const expiresAt =
    new Date(
      Date.now() +
        env.customerRegistrationCodeTtlMinutes *
          60 *
          1000,
    );

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation:
      'RequestCustomerRegistrationCode',
    intent:
      'Store the latest hashed verification code for the customer email',
  });

  await CustomerRegistrationVerification.findOneAndUpdate(
    {
      email: normalizedEmail,
      purpose:
        CUSTOMER_REGISTRATION_PURPOSE,
    },
    {
      email: normalizedEmail,
      purpose:
        CUSTOMER_REGISTRATION_PURPOSE,
      codeHash: hashValue(code),
      expiresAt,
      lastSentAt: new Date(),
      verifiedAt: null,
    },
    {
      upsert: true,
      returnDocument: 'after',
      setDefaultsOnInsert: true,
    },
  );

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation:
      'RequestCustomerRegistrationCode',
    intent:
      'Confirm the new verification code record is ready before sending email',
  });

  await sendCustomerRegistrationCodeEmail(
    {
      email: normalizedEmail,
      firstName: payload.firstName || '',
      code,
      expiresInMinutes:
        env.customerRegistrationCodeTtlMinutes,
    },
    logContext,
  );

  return {
    message:
      'Verification code sent successfully',
  };
}

async function verifyCustomerRegistrationCode(
  payload,
  logContext,
) {
  const normalizedEmail =
    normalizeEmail(payload.email);

  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: 'service',
    operation:
      'VerifyCustomerRegistrationCode',
    intent:
      'Validate the customer email code before allowing account creation',
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation:
      'VerifyCustomerRegistrationCode',
    intent:
      'Confirm the verification request still belongs to an available email',
  });

  await ensureCustomerEmailAvailable(
    normalizedEmail,
  );

  const verification =
    await CustomerRegistrationVerification.findOne(
      {
        email: normalizedEmail,
        purpose:
          CUSTOMER_REGISTRATION_PURPOSE,
      },
    );

  if (
    !verification ||
    verification.expiresAt <=
      new Date()
  ) {
    throw new AppError({
      message:
        'This verification code has expired',
      statusCode: 400,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode:
        'CUSTOMER_REGISTER_CODE_EXPIRED',
      resolutionHint:
        'Request a new verification code and try again',
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  if (
    verification.codeHash !==
    hashValue(payload.code)
  ) {
    throw new AppError({
      message:
        'The verification code is not correct',
      statusCode: 400,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode:
        'CUSTOMER_REGISTER_CODE_INVALID',
      resolutionHint:
        'Check the latest code from your email and try again',
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  verification.verifiedAt =
    new Date();
  await verification.save();

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation:
      'VerifyCustomerRegistrationCode',
    intent:
      'Confirm the customer email is verified for the upcoming account creation',
  });

  return {
    message:
      'Email verified successfully',
    verificationToken:
      createCustomerRegistrationVerificationToken(
        verification,
      ),
  };
}

async function loadVerifiedCustomerRegistration(
  email,
  verificationToken,
) {
  const verificationPayload =
    verifyCustomerRegistrationVerificationToken(
      verificationToken,
    );

  if (
    verificationPayload.tokenType !==
      'customer_registration_verification' ||
    verificationPayload.purpose !==
      CUSTOMER_REGISTRATION_PURPOSE ||
    normalizeEmail(
      verificationPayload.email,
    ) !== email
  ) {
    throw new AppError({
      message:
        'Your email verification is not valid for this registration',
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        'CUSTOMER_REGISTER_VERIFICATION_MISMATCH',
      resolutionHint:
        'Verify this email address again and try once more',
      step: LOG_STEPS.AUTH_FAIL,
    });
  }

  const verification =
    await CustomerRegistrationVerification.findOne(
      {
        _id: verificationPayload.verificationId,
        email,
        purpose:
          CUSTOMER_REGISTRATION_PURPOSE,
      },
    );

  if (
    !verification ||
    !verification.verifiedAt ||
    verification.expiresAt <=
      new Date()
  ) {
    throw new AppError({
      message:
        'Your email verification has expired',
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        'CUSTOMER_REGISTER_VERIFICATION_EXPIRED',
      resolutionHint:
        'Request a new verification code and try again',
      step: LOG_STEPS.AUTH_FAIL,
    });
  }

  return verification;
}

async function registerCustomer(
  payload,
  meta,
  logContext,
) {
  const normalizedEmail =
    normalizeEmail(payload.email);

  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "RegisterCustomer",
    intent:
      "Create the customer account before the first service request is submitted",
  });

  // WHY: Check email ownership first so registration never creates duplicate customer accounts.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "RegisterCustomer",
    intent:
      "Check whether the requested customer email is already in use",
  });

  const existingUser =
    await User.findOne({
      email: normalizedEmail,
    });

  // WHY: Stop here so the UI gets a clear account-exists answer before any password work happens.
  if (existingUser) {
    throw new AppError({
      message:
        "This email already has an account. Please log in instead.",
      statusCode: 409,
      classification:
        ERROR_CLASSIFICATIONS.INVALID_INPUT,
      errorCode:
        "CUSTOMER_REGISTER_EMAIL_TAKEN",
      resolutionHint:
        "Log in instead or reset the password for the existing account",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "RegisterCustomer",
    intent:
      "Confirm the new customer email is available",
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: 'service',
    operation: 'RegisterCustomer',
    intent:
      'Load the verified registration record before creating the customer account',
  });

  const verification =
    await loadVerifiedCustomerRegistration(
      normalizedEmail,
      payload.verificationToken,
    );

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: 'service',
    operation: 'RegisterCustomer',
    intent:
      'Confirm the customer email was verified before account creation',
  });

  // WHY: Hash the password only after uniqueness passes so rejected sign-ups do not waste crypto work.
  const passwordHash =
    await bcrypt.hash(
      payload.password,
      12,
    );

  // WHY: Persist the account in one place so later request flows can trust a real customer record exists.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "RegisterCustomer",
    intent:
      "Persist the new customer account in MongoDB",
  });

  const user = await User.create({
    firstName: payload.firstName,
    lastName: payload.lastName,
    email: normalizedEmail,
    phone: payload.phone || "",
    role: USER_ROLES.CUSTOMER,
    status: USER_STATUSES.ACTIVE,
    passwordHash,
  });

  await CustomerRegistrationVerification.deleteOne(
    { _id: verification._id },
  );

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "RegisterCustomer",
    intent:
      "Confirm the customer account was saved successfully",
  });

  // WHY: Start a session immediately so the new customer can continue without a second login step.
  const tokens =
    await issueSessionTokens(
      user,
      meta,
      logContext,
    );

  return {
    message:
      "Customer registered successfully",
    user: serializeUser(user),
    ...tokens,
  };
}

async function loginUser(
  payload,
  meta,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "LoginUser",
    intent:
      "Authenticate any active admin, staff, or customer user",
  });

  // WHY: Load the hidden password hash explicitly because normal queries never expose credential material.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "LoginUser",
    intent:
      "Load the matching account with its password hash for credential verification",
  });

  const user = await User.findOne({
    email: payload.email.toLowerCase(),
  }).select("+passwordHash");

  // WHY: Keep the failure generic so callers cannot discover which emails exist in the system.
  if (!user || !user.passwordHash) {
    throw new AppError({
      message:
        "Invalid email or password",
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_LOGIN_INVALID_CREDENTIALS",
      resolutionHint:
        "Check your email and password and try again",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "LoginUser",
    intent:
      "Confirm the account record is available for password comparison",
  });

  // WHY: Compare the submitted password only after the trusted account record is loaded.
  const passwordMatches =
    await bcrypt.compare(
      payload.password,
      user.passwordHash,
    );

  // WHY: Reuse the same safe message for a bad password so account discovery remains difficult.
  if (!passwordMatches) {
    throw new AppError({
      message:
        "Invalid email or password",
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_LOGIN_INVALID_CREDENTIALS",
      resolutionHint:
        "Check your email and password and try again",
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  // WHY: Block inactive accounts even if the credentials are valid so invite and disable states are respected.
  if (
    user.status !== USER_STATUSES.ACTIVE
  ) {
    throw new AppError({
      message:
        "Your account is not active",
      statusCode: 403,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_LOGIN_USER_INACTIVE",
      resolutionHint:
        "Complete your invite flow or contact an administrator",
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  // WHY: Keep token issuance centralized so login and refresh follow the same session rules.
  const tokens =
    await issueSessionTokens(
      user,
      meta,
      logContext,
    );

  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_OK,
    layer: "service",
    operation: "LoginUser",
    intent:
      "Return an authenticated session for the verified account",
  });

  return {
    message: "Login successful",
    user: serializeUser(user),
    ...tokens,
  };
}

async function refreshAuth(
  refreshToken,
  meta,
  logContext,
) {
  // WHY: Rotate the refresh session first so replayed refresh cookies stop working immediately.
  const tokens =
    await rotateRefreshSession(
      refreshToken,
      meta,
      logContext,
    );

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "RefreshAuth",
    intent:
      "Load the current user record after refresh-token rotation",
  });

  // WHY: Re-read the user from MongoDB so the client gets the latest persisted profile and role state.
  const decoded = await User.findById(
    jwtSafeSubject(tokens.accessToken),
  );
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "RefreshAuth",
    intent:
      "Confirm the refreshed session still maps to a valid user",
  });

  return {
    message:
      "Session refreshed successfully",
    user: serializeUser(decoded),
    ...tokens,
  };
}

function jwtSafeSubject(accessToken) {
  const tokenParts =
    accessToken.split(".");

  // WHY: Guard malformed access tokens before attempting to decode the payload segment.
  if (tokenParts.length < 2) {
    throw new AppError({
      message:
        "Unable to refresh this session",
      statusCode: 401,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_REFRESH_ACCESS_DECODE_FAILED",
      resolutionHint:
        "Log in again to continue",
      step: LOG_STEPS.SERVICE_FAIL,
    });
  }

  // WHY: Extract the signed subject so refresh uses the same identity encoded in the issued access token.
  const payload = JSON.parse(
    Buffer.from(
      tokenParts[1],
      "base64url",
    ).toString("utf8"),
  );
  return payload.sub;
}

async function logoutUser(
  refreshToken,
  logContext,
) {
  // WHY: Reuse refresh-session revocation so logout and token invalidation follow one path.
  await revokeRefreshSession(
    refreshToken,
    logContext,
  );

  return {
    message: "Logout successful",
  };
}

async function getCurrentUser(
  userId,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "GetCurrentUser",
    intent:
      "Bootstrap the frontend session with the current authenticated user",
  });

  // WHY: Resolve the user from MongoDB so deleted accounts are caught before the frontend trusts the session.
  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "GetCurrentUser",
    intent:
      "Load the authenticated user record for session bootstrap",
  });

  const user =
    await User.findById(userId);

  // WHY: Convert stale-token lookups into a controlled auth error before any client bootstrap continues.
  if (!user) {
    logError({
      ...logContext,
      step: LOG_STEPS.DB_QUERY_FAIL,
      layer: "service",
      operation: "GetCurrentUser",
      intent:
        "Reject stale access tokens that reference a missing account",
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      error_code:
        "AUTH_ME_USER_NOT_FOUND",
      resolution_hint:
        "Log in again to continue",
      message:
        "Authenticated user was not found",
    });

    throw new AppError({
      message:
        "Authenticated user not found",
      statusCode: 404,
      classification:
        ERROR_CLASSIFICATIONS.AUTHENTICATION_ERROR,
      errorCode:
        "AUTH_ME_USER_NOT_FOUND",
      resolutionHint:
        "Log in again to continue",
      step: LOG_STEPS.DB_QUERY_FAIL,
    });
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "GetCurrentUser",
    intent:
      "Confirm the frontend can bootstrap from a valid user record",
  });

  // WHY: Return the serialized user shape so the frontend never depends on raw Mongoose documents.
  return {
    message:
      "Authenticated user fetched successfully",
    user: serializeUser(user),
  };
}

async function getDemoAccounts(
  role,
  logContext,
) {
  logInfo({
    ...logContext,
    step: LOG_STEPS.SERVICE_START,
    layer: "service",
    operation: "GetDemoAccounts",
    intent:
      "Return backend-backed quick-fill login accounts for the requested role",
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_START,
    layer: "service",
    operation: "GetDemoAccounts",
    intent:
      "Load active users for the requested auth role before shaping quick-fill accounts",
  });

  const users = await User.find({
    role,
    status: USER_STATUSES.ACTIVE,
  }).sort({
    createdAt: 1,
    firstName: 1,
    lastName: 1,
  });

  logInfo({
    ...logContext,
    step: LOG_STEPS.DB_QUERY_OK,
    layer: "service",
    operation: "GetDemoAccounts",
    intent:
      "Confirm the role-specific users are ready for quick-fill response shaping",
  });

  // WHY: Public login shortcuts should stay in sync with real active accounts across environments, but the user must always type the password manually.
  const accounts = users.map((user) => ({
    id: String(user._id),
    fullName:
      `${user.firstName} ${user.lastName}`.trim(),
    email: user.email,
    role: user.role,
    staffType:
      user.staffType || null,
    quickFillPassword: null,
  }));

  return {
    message:
      "Demo accounts fetched successfully",
    role,
    passwordAutofillEnabled:
      false,
    accounts,
  };
}

module.exports = {
  getDemoAccounts,
  getCurrentUser,
  loginUser,
  logoutUser,
  refreshAuth,
  registerCustomer,
  requestCustomerRegistrationCode,
  verifyCustomerRegistrationCode,
};
