/**
 * WHAT: Seeds MongoDB with the public company profile, one admin, sample staff, sample customers, and sample service requests.
 * WHY: The first frontend, homepage, and dashboard flows need predictable data for immediate testing.
 * HOW: Reset the small v1 collections, seed the company profile, hash seed passwords from env, and create linked demo records.
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
  STAFF_AVAILABILITIES,
  USER_ROLES,
  USER_STATUSES,
} = require("../constants/app.constants");
const {
  CompanyProfile,
} = require("../models/company-profile.model");
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
const {
  buildQueueCreatedAiText,
} = require("./request-queue-ai");

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
    CompanyProfile.deleteMany({}),
    RefreshSession.deleteMany({}),
    ServiceRequest.deleteMany({}),
    StaffInvite.deleteMany({}),
    User.deleteMany({}),
  ]);

  await CompanyProfile.create({
    siteKey: "default",
    companyName: "CL Facility Management",
    legalName: "CL Logistic and Facility Management UG",
    category: {
      en: "Cleaning service",
      de: "Reinigungsservice",
    },
    tagline: {
      en: "Move, clean and fix.",
      de: "Umzug, Reinigung und Instandhaltung.",
    },
    heroTitle: {
      en: "Specialist cleaning and facility support for homes, workplaces, and properties in Mönchengladbach.",
      de: "Spezialreinigung und Facility-Service für Wohnungen, Arbeitsplätze und Objekte in Mönchengladbach.",
    },
    heroSubtitle: {
      en: "CL Logistic and Facility Management UG provides direct local support for specialist clean-ups, infection control, and dependable day-to-day cleaning from one place.",
      de: "CL Logistic and Facility Management UG bietet direkten lokalen Support für Spezialreinigungen, Infektionsschutz und verlässliche Alltagsreinigung an einem Ort.",
    },
    adminLoginLabel: {
      en: "Admin Login",
      de: "Admin-Anmeldung",
    },
    createAccountLabel: {
      en: "Book a service",
      de: "Service buchen",
    },
    customerLoginLabel: {
      en: "Customer Login",
      de: "Kunden-Login",
    },
    staffLoginLabel: {
      en: "Staff Login",
      de: "Mitarbeiter-Login",
    },
    heroPanelTitle: {
      en: "Specialist response and dependable everyday support",
      de: "Spezialeinsätze und verlässliche Unterstützung im Alltag",
    },
    heroPanelSubtitle: {
      en: "From trauma, fire, hoarding, and infection-control cleaning to regular building, office, and home support, CL Facility Management helps properties return to a safe, presentable standard.",
      de: "Von Trauma-, Brand-, Messie- und Infektionsschutzreinigung bis zur regelmäßigen Betreuung von Gebäuden, Büros und Wohnungen hilft CL Facility Management dabei, Objekte wieder in einen sicheren und gepflegten Zustand zu bringen.",
    },
    heroBullets: [
      {
        en: "Specialist cleaning for fire damage, trauma, hoarding situations, sharps, and hygiene-critical environments.",
        de: "Spezialreinigung für Brandschäden, Trauma-Situationen, Messie-Fälle, Sharps-Funde und hygienekritische Umgebungen.",
      },
      {
        en: "Discreet, practical support when properties need resetting after difficult incidents or unsafe conditions.",
        de: "Diskrete und praktische Unterstützung, wenn Objekte nach belastenden Vorfällen oder unsicheren Zuständen wiederhergestellt werden müssen.",
      },
      {
        en: "Regular support across Mönchengladbach for buildings, offices, homes, windows, and shared spaces.",
        de: "Regelmäßige Unterstützung in Mönchengladbach für Gebäude, Büros, Wohnungen, Fenster und Gemeinschaftsflächen.",
      },
      {
        en: "Direct contact for quotes, scheduling, urgent specialist clean-ups, and practical service questions.",
        de: "Direkter Kontakt für Angebote, Terminabstimmung, dringende Spezialreinigungen und praktische Servicefragen.",
      },
    ],
    servicesTitle: {
      en: "Services",
      de: "Leistungen",
    },
    serviceCardSubtitle: {
      en: "Choose the specialist or everyday cleaning service you need and the team can review it through the request queue.",
      de: "Wählen Sie die gewünschte Spezial- oder Alltagsreinigung, dann prüft das Team die Anfrage über die Queue.",
    },
    serviceLabels: [
      {
        key: "fire_damage_cleaning",
        label: {
          en: "Fire Damage Cleaning",
          de: "Brandschadenreinigung",
        },
      },
      {
        key: "needle_sweeps_sharps_cleanups",
        label: {
          en: "Needle Sweeps & Sharps Clean-Ups",
          de: "Nadelsuche & Sharps-Beseitigung",
        },
      },
      {
        key: "hoarding_cleanups",
        label: {
          en: "Hoarding Clean-Ups",
          de: "Hoarding- und Messie-Reinigung",
        },
      },
      {
        key: "trauma_decomposition_cleanups",
        label: {
          en: "Trauma & Decomposition Clean-Ups",
          de: "Trauma- und Leichenfundortreinigung",
        },
      },
      {
        key: "infection_control_cleaning",
        label: {
          en: "Infection Control Cleaning",
          de: "Infektionsschutzreinigung",
        },
      },
      {
        key: "building_cleaning",
        label: {
          en: "Building Cleaning",
          de: "Gebäudereinigung",
        },
      },
      {
        key: "window_cleaning",
        label: {
          en: "Window Cleaning",
          de: "Fensterreinigung",
        },
      },
      {
        key: "office_cleaning",
        label: {
          en: "Office Cleaning",
          de: "Büroreinigung",
        },
      },
      {
        key: "house_cleaning",
        label: {
          en: "House Cleaning",
          de: "Hausreinigung",
        },
      },
    ],
    howItWorksTitle: {
      en: "How it works",
      de: "So funktioniert es",
    },
    howItWorksSteps: [
      {
        title: {
          en: "1. Send your request",
          de: "1. Anfrage senden",
        },
        subtitle: {
          en: "Customers can send a structured request with service type, address, timing, and job notes.",
          de: "Kunden senden eine strukturierte Anfrage mit Leistungsart, Adresse, Zeitpunkt und Notizen zum Auftrag.",
        },
      },
      {
        title: {
          en: "2. Review and clarify",
          de: "2. Prüfen und abstimmen",
        },
        subtitle: {
          en: "Admin and staff can review the request, ask follow-up questions, and confirm the next step.",
          de: "Admin und Mitarbeitende prüfen die Anfrage, stellen Rückfragen und bestätigen den nächsten Schritt.",
        },
      },
      {
        title: {
          en: "3. Complete the work",
          de: "3. Arbeit abschließen",
        },
        subtitle: {
          en: "The assigned team member can move the request through quote, confirmation, start, and completion.",
          de: "Das zugewiesene Teammitglied führt die Anfrage durch Angebot, Bestätigung, Start und Abschluss.",
        },
      },
    ],
    contactSectionTitle: {
      en: "Contact and business info",
      de: "Kontakt- und Unternehmensdaten",
    },
    contactSectionSubtitle: {
      en: "These details come from the shared company profile so the homepage stays backend-driven.",
      de: "Diese Angaben kommen aus dem hinterlegten Unternehmensprofil, damit die Startseite backend-gesteuert bleibt.",
    },
    serviceAreaLabel: {
      en: "Service area",
      de: "Einsatzgebiet",
    },
    serviceAreaText: {
      en: "Mönchengladbach, Germany",
      de: "Mönchengladbach, Deutschland",
    },
    contact: {
      addressLine1: "Kunkel Str. 44",
      city: "Mönchengladbach",
      postalCode: "41063",
      country: "Germany",
      phone: "+49 2166 6377345",
      secondaryPhone: "",
      email: "cl.facility.management@gmx.de",
      instagramUrl: "https://www.instagram.com/",
      facebookUrl: "https://www.facebook.com/profile.php?id=61575728904144",
      hoursLabel: {
        en: "Always open",
        de: "Immer geöffnet",
      },
    },
    primaryColorHex: "#1B4D8C",
    accentColorHex: "#CE7B37",
  });

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
      serviceType: "building_cleaning",
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
          buildQueueCreatedAiText({
            request: {
              serviceType: "building_cleaning",
              preferredTimeWindow: "Morning",
              location: {
                city: "Monchengladbach",
              },
              messages: [],
            },
            companyProfile: {
              companyName: "CL Facility Management",
            },
          }),
        ),
      ],
    },
    {
      customer: customers[1]._id,
      serviceType: "warehouse_hall_cleaning",
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
      serviceType: "window_glass_cleaning",
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
      serviceType: "caretaker_service",
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
