/**
 * WHAT: Loads and normalizes backend environment configuration.
 * WHY: Centralized config prevents scattered environment parsing and inconsistent defaults.
 * HOW: Load `.env` once, coerce shared settings, and export a single immutable config object.
 */

const path = require("path");

const dotenv = require("dotenv");

dotenv.config({
  // WHY: Resolve the backend `.env` explicitly so scripts and app startup read the same file.
  path: path.resolve(__dirname, "../../.env"),
  quiet: true,
});

function toNumber(value, fallback) {
  // WHY: Centralize number coercion so invalid env values degrade safely to known defaults.
  const parsed = Number(value);
  return Number.isFinite(parsed)
    ? parsed
    : fallback;
}

function splitOrigins(value) {
  // WHY: Normalize the CORS allowlist once so middleware does not repeat parsing logic.
  return String(value || "")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean);
}

function normalizeText(value) {
  return String(value || "").trim();
}

const env = Object.freeze({
  // WHY: Freeze config so runtime code cannot mutate shared environment values by accident.
  nodeEnv: process.env.NODE_ENV || "development",
  port: toNumber(process.env.PORT, 4000),
  host: process.env.HOST || "127.0.0.1",
  mongoDbUri:
    process.env.MONGODB_URI ||
    "mongodb://127.0.0.1:27017/adams",
  jwtAccessSecret:
    process.env.JWT_ACCESS_SECRET ||
    "change-this-access-secret",
  jwtRefreshSecret:
    process.env.JWT_REFRESH_SECRET ||
    "change-this-refresh-secret",
  jwtInviteSecret:
    process.env.JWT_INVITE_SECRET ||
    process.env.JWT_REFRESH_SECRET ||
    "change-this-invite-secret",
  jwtCustomerRegistrationSecret:
    process.env
      .JWT_CUSTOMER_REGISTRATION_SECRET ||
    process.env.JWT_ACCESS_SECRET ||
    "change-this-customer-registration-secret",
  jwtAccessTtl:
    process.env.JWT_ACCESS_TTL || "15m",
  jwtRefreshTtl:
    process.env.JWT_REFRESH_TTL || "7d",
  customerRegistrationCodeTtlMinutes: toNumber(
    process.env
      .CUSTOMER_REGISTRATION_CODE_TTL_MINUTES,
    15,
  ),
  customerRegistrationVerificationTokenTtl:
    process.env
      .CUSTOMER_REGISTRATION_VERIFICATION_TOKEN_TTL ||
    "30m",
  authCookieName: "refreshToken",
  staffInviteTtlHours: toNumber(
    process.env.STAFF_INVITE_TTL_HOURS,
    72,
  ),
  corsOrigins: splitOrigins(
    process.env.CORS_ORIGIN ||
      "http://localhost:5173,http://localhost:8080,http://localhost:3000",
  ),
  frontendAppUrl:
    process.env.FRONTEND_APP_URL ||
    "http://localhost:5173",
  authRateLimitMaxAttempts: toNumber(
    process.env.AUTH_RATE_LIMIT_MAX_ATTEMPTS,
    10,
  ),
  authRateLimitWindowMs: toNumber(
    process.env.AUTH_RATE_LIMIT_WINDOW_MS,
    60000,
  ),
  seedAdminFirstName:
    process.env.SEED_ADMIN_FIRST_NAME || "Adams",
  seedAdminLastName:
    process.env.SEED_ADMIN_LAST_NAME || "Gafar",
  seedAdminPassword:
    process.env.SEED_ADMIN_PASSWORD ||
    "AdminPass123!",
  seedStaffPassword:
    process.env.SEED_STAFF_PASSWORD ||
    "StaffPass123!",
  seedCustomerPassword:
    process.env.SEED_CUSTOMER_PASSWORD ||
    "CustomerPass123!",
  emailProvider: normalizeText(
    process.env.EMAIL_PROVIDER,
  ).toLowerCase(),
  brevoApiKey: normalizeText(
    process.env.BREVO_API_KEY,
  ),
  emailFrom: normalizeText(
    process.env.EMAIL_FROM,
  ),
  emailFromName: normalizeText(
    process.env.EMAIL_FROM_NAME,
  ),
  cloudinaryCloudName: normalizeText(
    process.env.CLOUDINARY_CLOUD_NAME,
  ),
  cloudinaryApiKey: normalizeText(
    process.env.CLOUDINARY_API_KEY,
  ),
  cloudinaryApiSecret: normalizeText(
    process.env.CLOUDINARY_API_SECRET,
  ),
  googleAddressApiKey: normalizeText(
    process.env.GOOGLE_ADDRESS_API_KEY,
  ),
  aiProvider: process.env.AI_PROVIDER || "groq",
  aiApiKey:
    process.env.AI_API_KEY ||
    process.env.XAI_API_KEY ||
    "",
  aiBaseUrl:
    process.env.AI_BASE_URL ||
    "https://api.groq.com/openai/v1",
  aiModelDefault:
    process.env.AI_MODEL_DEFAULT ||
    "llama-3.1-8b-instant",
  aiModelReasoning:
    process.env.AI_MODEL_REASONING ||
    "llama-3.1-70b-versatile",
  stripeSecretKey:
    process.env.STRIPE_SECRET_KEY || "",
  stripeSuccessUrl:
    process.env.STRIPE_SUCCESS_URL ||
    `${process.env.FRONTEND_APP_URL || "http://localhost:5173"}/#/app/requests`,
  stripeCancelUrl:
    process.env.STRIPE_CANCEL_URL ||
    `${process.env.FRONTEND_APP_URL || "http://localhost:5173"}/#/app/requests`,
});

module.exports = { env };
