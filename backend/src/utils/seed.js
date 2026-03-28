/**
 * WHAT: Seeds MongoDB with one admin, sample staff, sample customers, and sample service requests.
 * WHY: The first frontend and dashboard flows need predictable data for immediate testing.
 * HOW: Reset the small v1 collections, hash seed passwords from env, and create linked demo records.
 */

const bcrypt = require("bcryptjs");

const {
  connectDatabase,
} = require("../config/database");
const {
  env,
} = require("../config/env");
const {
  REQUEST_SOURCES,
  REQUEST_STATUSES,
  SERVICE_TYPES,
  STAFF_AVAILABILITIES,
  USER_ROLES,
  USER_STATUSES,
} = require("../constants/app.constants");
const {
  RefreshSession,
} = require("../models/refresh-session.model");
const {
  ServiceRequest,
} = require("../models/service-request.model");
const {
  StaffInvite,
} = require("../models/staff-invite.model");
const {
  User,
} = require("../models/user.model");
const {
  logError,
  logInfo,
} = require("./logger");
const {
  buildAiMessage,
  buildCustomerMessage,
  buildStaffMessage,
  buildSystemMessage,
} = require("./request-chat");

async function runSeed() {
  // WHY: Reuse the normal database bootstrap so seeding fails fast if the configured MongoDB is unavailable.
  await connectDatabase();

  logInfo({
    requestId: "seed",
    route: "SEED RUN",
    step: "SERVICE_START",
    layer: "script",
    operation: "SeedDatabase",
    intent:
      "Populate the local database with predictable v1 demo data",
    businessIdPresent: false,
    userRole: "system",
  });

  // WHY: Reset only the small v1 collections so the seeded relationships stay consistent for development.
  await Promise.all([
    RefreshSession.deleteMany({}),
    ServiceRequest.deleteMany({}),
    StaffInvite.deleteMany({}),
    User.deleteMany({}),
  ]);

  // WHY: Hash seed passwords once up front so every seeded user follows the real auth storage rules.
  const [
    adminPasswordHash,
    staffPasswordHash,
    customerPasswordHash,
  ] = await Promise.all([
    bcrypt.hash(
      env.seedAdminPassword,
      12,
    ),
    bcrypt.hash(
      env.seedStaffPassword,
      12,
    ),
    bcrypt.hash(
      env.seedCustomerPassword,
      12,
    ),
  ]);

  // WHY: Create the admin first so invites and seeded ownership can reference a real account id.
  const admin = await User.create({
    firstName: env.seedAdminFirstName,
    lastName: env.seedAdminLastName,
    email: "admin@adams.local",
    phone: "+491111111111",
    role: USER_ROLES.ADMIN,
    status: USER_STATUSES.ACTIVE,
    passwordHash: adminPasswordHash,
  });

  // WHY: Seed active staff accounts so assignment flows and staff dashboards are testable immediately.
  const staffMembers =
    await User.insertMany([
      {
        firstName: "Daniel",
        lastName: "Weber",
        email: "staff1@adams.local",
        phone: "+492222222222",
        role: USER_ROLES.STAFF,
        status: USER_STATUSES.ACTIVE,
        staffAvailability:
          STAFF_AVAILABILITIES.ONLINE,
        passwordHash: staffPasswordHash,
      },
      {
        firstName: "Sofia",
        lastName: "Keller",
        email: "staff2@adams.local",
        phone: "+493333333333",
        role: USER_ROLES.STAFF,
        status: USER_STATUSES.ACTIVE,
        staffAvailability:
          STAFF_AVAILABILITIES.OFFLINE,
        passwordHash: staffPasswordHash,
      },
    ]);

  // WHY: Seed customers separately so request timelines and customer auth flows have predictable owners.
  const customers =
    await User.insertMany([
      {
        firstName: "Michael",
        lastName: "Braun",
        email: "customer1@adams.local",
        phone: "+494444444444",
        role: USER_ROLES.CUSTOMER,
        status: USER_STATUSES.ACTIVE,
        passwordHash:
          customerPasswordHash,
      },
      {
        firstName: "Laura",
        lastName: "Hoffmann",
        email: "customer2@adams.local",
        phone: "+495555555555",
        role: USER_ROLES.CUSTOMER,
        status: USER_STATUSES.ACTIVE,
        passwordHash:
          customerPasswordHash,
      },
    ]);

  // WHY: Keep one pending invite in the dataset so invite-based staff registration can be tested without setup.
  await StaffInvite.create({
    inviteId: "sample-invite-id",
    firstName: "Elias",
    lastName: "Becker",
    email: "pending.staff@adams.local",
    phone: "+496666666666",
    invitedBy: admin._id,
    expiresAt: new Date(
      Date.now() +
        env.staffInviteTtlHours *
          60 *
          60 *
          1000,
    ),
  });

  // WHY: Seed requests across multiple statuses so admin, customer, and staff screens all show meaningful states.
  await ServiceRequest.insertMany([
    {
      customer: customers[0]._id,
      serviceType: SERVICE_TYPES[0],
      status:
        REQUEST_STATUSES.SUBMITTED,
      source: REQUEST_SOURCES.FORM,
      location: {
        addressLine1: "12 Clean Street",
        city: "Monchengladbach",
        postalCode: "41189",
      },
      preferredDate: new Date(
        Date.now() +
          3 * 24 * 60 * 60 * 1000,
      ),
      preferredTimeWindow: "Morning",
      message:
        "We need weekly building cleaning for our office floor.",
      contactSnapshot: {
        fullName: "Michael Braun",
        email: "customer1@adams.local",
        phone: "+494444444444",
      },
      assignedStaff: null,
      queueEnteredAt: new Date(),
      messages: [
        buildCustomerMessage({
          customerId: customers[0]._id,
          customerName:
            "Michael Braun",
          text: "We need weekly building cleaning for our office floor.",
        }),
        buildSystemMessage(
          "Your request is now in the live queue. A staff member will attend to it here.",
        ),
        buildAiMessage(
          "I captured your request details and will keep this conversation warm while you wait for staff.",
        ),
      ],
    },
    {
      customer: customers[1]._id,
      serviceType: SERVICE_TYPES[1],
      status: REQUEST_STATUSES.ASSIGNED,
      source: REQUEST_SOURCES.FORM,
      location: {
        addressLine1:
          "45 Warehouse Lane",
        city: "Dusseldorf",
        postalCode: "40210",
      },
      preferredDate: new Date(
        Date.now() +
          5 * 24 * 60 * 60 * 1000,
      ),
      preferredTimeWindow: "Afternoon",
      message:
        "Please quote for monthly warehouse floor cleaning and machine dust removal.",
      contactSnapshot: {
        fullName: "Laura Hoffmann",
        email: "customer2@adams.local",
        phone: "+495555555555",
      },
      assignedStaff:
        staffMembers[0]._id,
      queueEnteredAt: new Date(
        Date.now() -
          4 * 60 * 60 * 1000,
      ),
      attendedAt: new Date(
        Date.now() -
          3 * 60 * 60 * 1000,
      ),
      messages: [
        buildCustomerMessage({
          customerId: customers[1]._id,
          customerName:
            "Laura Hoffmann",
          text: "Please quote for monthly warehouse floor cleaning and machine dust removal.",
        }),
        buildSystemMessage(
          "Daniel Weber joined your queue and can continue the conversation here.",
        ),
        buildStaffMessage({
          staffId:
            staffMembers[0]._id,
          staffName:
            "Daniel Weber",
          text: "I am reviewing your warehouse request now and will prepare the next steps.",
        }),
      ],
    },
    {
      customer: customers[0]._id,
      serviceType: SERVICE_TYPES[2],
      status: REQUEST_STATUSES.QUOTED,
      source: REQUEST_SOURCES.FORM,
      location: {
        addressLine1: "99 Glass Road",
        city: "Cologne",
        postalCode: "50667",
      },
      preferredDate: new Date(
        Date.now() +
          7 * 24 * 60 * 60 * 1000,
      ),
      preferredTimeWindow: "Flexible",
      message:
        "Storefront window cleaning needed before next weekend.",
      contactSnapshot: {
        fullName: "Michael Braun",
        email: "customer1@adams.local",
        phone: "+494444444444",
      },
      assignedStaff:
        staffMembers[1]._id,
      queueEnteredAt: new Date(
        Date.now() -
          24 * 60 * 60 * 1000,
      ),
      attendedAt: new Date(
        Date.now() -
          23 * 60 * 60 * 1000,
      ),
      messages: [
        buildCustomerMessage({
          customerId: customers[0]._id,
          customerName:
            "Michael Braun",
          text: "Storefront window cleaning needed before next weekend.",
        }),
        buildSystemMessage(
          "Sofia Keller joined your queue and can continue the conversation here.",
        ),
        buildStaffMessage({
          staffId:
            staffMembers[1]._id,
          staffName:
            "Sofia Keller",
          text: "Quote is being prepared and I will confirm the appointment details here.",
        }),
      ],
    },
    {
      customer: customers[1]._id,
      serviceType: SERVICE_TYPES[4],
      status: REQUEST_STATUSES.CLOSED,
      source: REQUEST_SOURCES.CHAT,
      location: {
        addressLine1:
          "7 Garden Court",
        city: "Essen",
        postalCode: "45127",
      },
      preferredDate: new Date(
        Date.now() -
          2 * 24 * 60 * 60 * 1000,
      ),
      preferredTimeWindow: "Morning",
      message:
        "Caretaker follow-up needed after a completed weekend visit.",
      contactSnapshot: {
        fullName: "Laura Hoffmann",
        email: "customer2@adams.local",
        phone: "+495555555555",
      },
      assignedStaff:
        staffMembers[0]._id,
      queueEnteredAt: new Date(
        Date.now() -
          3 * 24 * 60 * 60 * 1000,
      ),
      attendedAt: new Date(
        Date.now() -
          3 * 24 * 60 * 60 * 1000 +
          2 * 60 * 60 * 1000,
      ),
      closedAt: new Date(),
      messages: [
        buildCustomerMessage({
          customerId: customers[1]._id,
          customerName:
            "Laura Hoffmann",
          text: "Caretaker follow-up needed after a completed weekend visit.",
        }),
        buildSystemMessage(
          "Daniel Weber joined your queue and can continue the conversation here.",
        ),
        buildStaffMessage({
          staffId:
            staffMembers[0]._id,
          staffName:
            "Daniel Weber",
          text: "I handled the follow-up and closed the queue for this request.",
        }),
        buildSystemMessage(
          "Request status changed to closed.",
        ),
      ],
    },
  ]);

  logInfo({
    requestId: "seed",
    route: "SEED RUN",
    step: "SERVICE_OK",
    layer: "script",
    operation: "SeedDatabase",
    intent:
      "Finish seeding demo accounts and request data successfully",
    businessIdPresent: false,
    userRole: "system",
    adminEmail: admin.email,
  });

  // WHY: Exit explicitly so the seed script does not hang on open Mongoose handles in local development.
  process.exit(0);
}

runSeed().catch((error) => {
  // WHY: Emit one safe failure log for seed problems before exiting with a non-zero status.
  logError({
    requestId: "seed",
    route: "SEED RUN",
    step: "SERVICE_FAIL",
    layer: "script",
    operation: "SeedDatabase",
    intent:
      "Report why demo data seeding could not finish",
    businessIdPresent: false,
    userRole: "system",
    classification:
      "UNKNOWN_PROVIDER_ERROR",
    error_code: "SEED_RUN_FAILED",
    resolution_hint:
      "Check MongoDB availability and the seed configuration values",
    message: error.message,
  });
  process.exit(1);
});
