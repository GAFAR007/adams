/**
 * WHAT: Provides readable structured logging helpers for the backend.
 * WHY: Developers need logs that are easy to scan in the terminal while still carrying precise trace data.
 * HOW: Render pretty multiline logs in development and keep a JSON fallback for production-style environments.
 */

const PRETTY_MODE =
  process.env.LOG_FORMAT !== "json" &&
  process.env.NODE_ENV !== "production";

function formatPrimitive(value) {
  if (
    value === null ||
    value === undefined
  ) {
    // WHY: Render missing values consistently so logs stay easy to scan.
    return "-";
  }

  if (typeof value === "boolean") {
    // WHY: Use yes/no wording because it is faster to read in terminal output than true/false.
    return value ? "yes" : "no";
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  if (Array.isArray(value)) {
    // WHY: Collapse arrays into one readable line so debug output does not become noisy by default.
    return value.length ?
        value.join(", ")
      : "-";
  }

  if (typeof value === "object") {
    // WHY: Fallback to JSON only for values that still need a compact single-line representation.
    return JSON.stringify(value);
  }

  return String(value);
}

function formatClock(isoTimestamp) {
  return new Date(
    isoTimestamp,
  ).toLocaleTimeString("en-GB", {
    hour12: false,
  });
}

function humanizeOperation(operation) {
  // WHY: Keep a readable fallback for operation names that do not have an explicit friendly label yet.
  return String(
    operation || "operation",
  )
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/^./, (value) =>
      value.toUpperCase(),
    );
}

const OPERATION_LABELS = {
  RegisterCustomer: "Customer sign-up",
  LoginUser: "Login",
  RefreshAuth: "Session refresh",
  LogoutUser: "Logout",
  GetCurrentUser: "Current user",
  IssueSessionTokens: "Session",
  RotateRefreshSession:
    "Session refresh",
  RevokeRefreshSession:
    "Session cleanup",
  AdminGetDashboard: "Admin dashboard",
  AdminListRequests: "Admin requests",
  AdminAssignRequest:
    "Request assignment",
  AdminListStaff: "Staff list",
  AdminCreateStaffInvite:
    "Staff invite",
  AdminListStaffInvites:
    "Staff invites",
  CustomerCreateRequest:
    "Customer request",
  CustomerListRequests:
    "Customer requests",
  StaffRegister: "Staff sign-up",
  StaffGetDashboard: "Staff dashboard",
  StaffListRequests:
    "Assigned requests",
  StaffUpdateRequestStatus:
    "Request status",
};

function buildStageMessage(entry) {
  const summaryKey = `${entry.operation}:${entry.step}`;

  // WHY: Prefer explicit stage labels for common flows so local logs read like plain English.
  const summaryMap = {
    "DatabaseConnect:DB_QUERY_START":
      "MongoDB connecting",
    "DatabaseConnect:DB_QUERY_OK":
      "MongoDB connected",
    "DatabaseConnect:DB_QUERY_FAIL":
      "MongoDB connection failed",
    "ServerStart:SERVICE_OK": `Server ready on ${formatPrimitive(entry.host) || "127.0.0.1"}:${formatPrimitive(entry.port)}`,
    "ServerStart:SERVICE_FAIL":
      "Server failed to start",
    "SeedDatabase:SERVICE_START":
      "Database seeding started",
    "SeedDatabase:SERVICE_OK":
      "Database seeded",
    "SeedDatabase:SERVICE_FAIL":
      "Database seeding failed",
    "RequestEntry:ROUTE_IN": `${formatPrimitive(entry.route)} received`,
    "RequireAuth:AUTH_OK": `${formatPrimitive(entry.route)} authenticated`,
    "RequireAuth:AUTH_FAIL": `${formatPrimitive(entry.route)} authentication failed`,
    "ValidateRequest:VALIDATION_OK": `${formatPrimitive(entry.route)} validated`,
    "ValidateRequest:VALIDATION_FAIL": `${formatPrimitive(entry.route)} validation failed`,
    "ErrorResponse:CONTROLLER_RESPONSE_FAIL": `${formatPrimitive(entry.route)} failed`,
    "RegisterCustomer:SERVICE_START":
      "Customer sign-up started",
    "RegisterCustomer:SERVICE_OK":
      "Customer registered",
    "RegisterCustomer:SERVICE_FAIL":
      "Customer sign-up failed",
    "RegisterCustomer:DB_QUERY_START":
      "Checking customer details",
    "RegisterCustomer:DB_QUERY_OK":
      "Customer details ready",
    "LoginUser:SERVICE_START":
      "Login started",
    "LoginUser:SERVICE_OK":
      "Login successful",
    "LoginUser:SERVICE_FAIL":
      "Login failed",
    "LoginUser:DB_QUERY_START":
      "Checking account",
    "LoginUser:DB_QUERY_OK":
      "Account found",
    "RefreshAuth:SERVICE_START":
      "Session refresh started",
    "RefreshAuth:SERVICE_OK":
      "Session refreshed",
    "RefreshAuth:SERVICE_FAIL":
      "Session refresh failed",
    "RefreshAuth:DB_QUERY_START":
      "Loading refreshed user",
    "RefreshAuth:DB_QUERY_OK":
      "Refreshed user ready",
    "LogoutUser:SERVICE_OK":
      "Logged out",
    "LogoutUser:CONTROLLER_RESPONSE_OK":
      "Logout complete",
    "GetCurrentUser:SERVICE_START":
      "Loading current user",
    "GetCurrentUser:SERVICE_OK":
      "Current user loaded",
    "GetCurrentUser:SERVICE_FAIL":
      "Current user load failed",
    "GetCurrentUser:DB_QUERY_START":
      "Checking current user",
    "GetCurrentUser:DB_QUERY_OK":
      "Current user ready",
    "IssueSessionTokens:SERVICE_START":
      "Creating session",
    "IssueSessionTokens:SERVICE_OK":
      "Session created",
    "IssueSessionTokens:SERVICE_FAIL":
      "Session creation failed",
    "IssueSessionTokens:DB_QUERY_START":
      "Saving session",
    "IssueSessionTokens:DB_QUERY_OK":
      "Session saved",
    "RotateRefreshSession:SERVICE_START":
      "Checking session refresh",
    "RotateRefreshSession:SERVICE_OK":
      "Session rotated",
    "RotateRefreshSession:SERVICE_FAIL":
      "Session refresh failed",
    "RotateRefreshSession:DB_QUERY_START":
      "Checking existing session",
    "RotateRefreshSession:DB_QUERY_OK":
      "Existing session valid",
    "RevokeRefreshSession:SERVICE_OK":
      "Session already closed",
    "RevokeRefreshSession:DB_QUERY_START":
      "Ending session",
    "RevokeRefreshSession:DB_QUERY_OK":
      "Session ended",
    "AdminGetDashboard:SERVICE_START":
      "Admin dashboard loading",
    "AdminGetDashboard:SERVICE_OK":
      "Admin dashboard ready",
    "AdminGetDashboard:DB_QUERY_START":
      "Loading admin dashboard",
    "AdminGetDashboard:DB_QUERY_OK":
      "Admin dashboard ready",
    "AdminListRequests:SERVICE_START":
      "Loading admin requests",
    "AdminListRequests:SERVICE_OK":
      "Admin requests ready",
    "AdminListRequests:DB_QUERY_START":
      "Loading admin requests",
    "AdminListRequests:DB_QUERY_OK":
      "Admin requests ready",
    "AdminAssignRequest:SERVICE_START":
      "Request assignment started",
    "AdminAssignRequest:SERVICE_OK":
      "Request assigned",
    "AdminAssignRequest:SERVICE_FAIL":
      "Request assignment failed",
    "AdminAssignRequest:DB_QUERY_START":
      "Checking assignment details",
    "AdminAssignRequest:DB_QUERY_OK":
      "Request assigned",
    "AdminListStaff:SERVICE_START":
      "Loading staff list",
    "AdminListStaff:SERVICE_OK":
      "Staff list ready",
    "AdminListStaff:DB_QUERY_START":
      "Loading staff list",
    "AdminListStaff:DB_QUERY_OK":
      "Staff list ready",
    "AdminCreateStaffInvite:SERVICE_START":
      "Creating staff invite",
    "AdminCreateStaffInvite:SERVICE_OK":
      "Staff invite created",
    "AdminCreateStaffInvite:SERVICE_FAIL":
      "Staff invite creation failed",
    "AdminCreateStaffInvite:DB_QUERY_START":
      "Checking staff invite data",
    "AdminCreateStaffInvite:DB_QUERY_OK":
      "Staff invite created",
    "AdminListStaffInvites:SERVICE_START":
      "Loading staff invites",
    "AdminListStaffInvites:SERVICE_OK":
      "Staff invites ready",
    "AdminListStaffInvites:DB_QUERY_START":
      "Loading staff invites",
    "AdminListStaffInvites:DB_QUERY_OK":
      "Staff invites ready",
    "CustomerCreateRequest:SERVICE_START":
      "Customer request started",
    "CustomerCreateRequest:SERVICE_OK":
      "Customer request created",
    "CustomerCreateRequest:SERVICE_FAIL":
      "Customer request failed",
    "CustomerCreateRequest:DB_QUERY_START":
      "Checking customer request details",
    "CustomerCreateRequest:DB_QUERY_OK":
      "Customer request created",
    "CustomerListRequests:SERVICE_START":
      "Loading customer requests",
    "CustomerListRequests:SERVICE_OK":
      "Customer requests ready",
    "CustomerListRequests:DB_QUERY_START":
      "Loading customer requests",
    "CustomerListRequests:DB_QUERY_OK":
      "Customer requests ready",
    "StaffRegister:SERVICE_START":
      "Staff sign-up started",
    "StaffRegister:SERVICE_OK":
      "Staff account created",
    "StaffRegister:SERVICE_FAIL":
      "Staff sign-up failed",
    "StaffRegister:DB_QUERY_START":
      "Checking staff invite",
    "StaffRegister:DB_QUERY_OK":
      "Staff account created",
    "StaffGetDashboard:SERVICE_START":
      "Loading staff dashboard",
    "StaffGetDashboard:SERVICE_OK":
      "Staff dashboard ready",
    "StaffGetDashboard:DB_QUERY_START":
      "Loading staff dashboard",
    "StaffGetDashboard:DB_QUERY_OK":
      "Staff dashboard ready",
    "StaffListRequests:SERVICE_START":
      "Loading assigned requests",
    "StaffListRequests:SERVICE_OK":
      "Assigned requests ready",
    "StaffListRequests:DB_QUERY_START":
      "Loading assigned requests",
    "StaffListRequests:DB_QUERY_OK":
      "Assigned requests ready",
    "StaffUpdateRequestStatus:SERVICE_START":
      "Request status update started",
    "StaffUpdateRequestStatus:SERVICE_OK":
      "Request status updated",
    "StaffUpdateRequestStatus:SERVICE_FAIL":
      "Request status update failed",
    "StaffUpdateRequestStatus:DB_QUERY_START":
      "Checking request status update",
    "StaffUpdateRequestStatus:DB_QUERY_OK":
      "Request status updated",
  };

  if (summaryMap[summaryKey]) {
    return summaryMap[summaryKey];
  }

  // WHY: Keep a generic fallback for less common steps without dropping the log entirely.
  const fallbackVerbMap = {
    ROUTE_IN: "received",
    AUTH_OK: "access granted",
    AUTH_FAIL: "access denied",
    VALIDATION_OK: "validated",
    VALIDATION_FAIL:
      "validation failed",
    SERVICE_START: "started",
    SERVICE_OK: "completed",
    SERVICE_FAIL: "failed",
    DB_QUERY_START: "checking data",
    DB_QUERY_OK: "data ready",
    DB_QUERY_FAIL: "data check failed",
    PROVIDER_CALL_START:
      "contacting provider",
    PROVIDER_CALL_OK:
      "provider response received",
    PROVIDER_CALL_FAIL:
      "provider request failed",
    CONTROLLER_RESPONSE_OK:
      "response sent",
    CONTROLLER_RESPONSE_FAIL:
      "response failed",
  };

  const operationLabel =
    OPERATION_LABELS[entry.operation] ||
    humanizeOperation(entry.operation);

  const fallbackMessage =
    fallbackVerbMap[entry.step] ||
    "updated";

  if (
    String(fallbackMessage).includes(
      ":",
    )
  ) {
    return `${operationLabel}${fallbackMessage}`;
  }

  if (
    entry.step === "DB_QUERY_START" ||
    entry.step === "DB_QUERY_OK" ||
    entry.step === "DB_QUERY_FAIL" ||
    entry.step ===
      "PROVIDER_CALL_START" ||
    entry.step === "PROVIDER_CALL_OK" ||
    entry.step === "PROVIDER_CALL_FAIL"
  ) {
    // WHY: Add punctuation for mid-flow stages so "checking data" style messages read naturally.
    return `${operationLabel}: ${fallbackMessage}`;
  }

  return `${operationLabel} ${fallbackMessage}`;
}

function buildPrettyLines(entry) {
  const headline = `[${formatClock(entry.timestamp)}] ${entry.level.toUpperCase().padEnd(5)} ${buildStageMessage(entry)}`;
  const lines = [headline];

  if (entry.level === "error") {
    lines.push(
      `         reason=${formatPrimitive(entry.message)} | code=${formatPrimitive(entry.error_code)} | next=${formatPrimitive(entry.resolution_hint)}`,
    );
  }

  return lines;
}

function write(level, payload) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    ...payload,
  };

  if (PRETTY_MODE) {
    // WHY: Use human-friendly terminal output locally because it is faster to debug than raw JSON blocks.
    const rendered =
      buildPrettyLines(entry).join(
        "\n",
      );

    if (level === "error") {
      console.error(rendered);
      return;
    }

    console.log(rendered);
    return;
  }

  // WHY: Keep JSON output available for production-style transports and machine parsing.
  const serialized =
    JSON.stringify(entry);

  if (level === "error") {
    console.error(serialized);
    return;
  }

  console.log(serialized);
}

function logInfo(payload) {
  write("info", payload);
}

function logError(payload) {
  write("error", payload);
}

function buildRequestLog(
  req,
  overrides = {},
) {
  return {
    requestId:
      req.requestId ||
      "unknown-request",
    route: `${req.method} ${req.baseUrl || ""}${req.path}`,
    businessIdPresent: false,
    userRole:
      req.authUser?.role || "anonymous",
    ...overrides,
  };
}

module.exports = {
  buildRequestLog,
  logError,
  logInfo,
};
