/**
 * WHAT: Defines the public company-profile document that powers the landing page.
 * WHY: Homepage business content should come from MongoDB instead of being duplicated in the frontend.
 * HOW: Store one seeded site profile with localized copy, services, and contact details.
 */

const mongoose = require('mongoose');

const localizedTextSchema = new mongoose.Schema(
  {
    en: {
      type: String,
      required: true,
      trim: true,
    },
    de: {
      type: String,
      required: true,
      trim: true,
    },
  },
  {
    _id: false,
  },
);

const serviceLabelSchema = new mongoose.Schema(
  {
    key: {
      type: String,
      required: true,
      trim: true,
    },
    label: {
      type: localizedTextSchema,
      required: true,
    },
  },
  {
    _id: false,
  },
);

const localizedStepSchema = new mongoose.Schema(
  {
    title: {
      type: localizedTextSchema,
      required: true,
    },
    subtitle: {
      type: localizedTextSchema,
      required: true,
    },
  },
  {
    _id: false,
  },
);

const companyContactSchema = new mongoose.Schema(
  {
    addressLine1: {
      type: String,
      required: true,
      trim: true,
    },
    city: {
      type: String,
      required: true,
      trim: true,
    },
    postalCode: {
      type: String,
      required: true,
      trim: true,
    },
    country: {
      type: String,
      required: true,
      trim: true,
    },
    phone: {
      type: String,
      required: true,
      trim: true,
    },
    secondaryPhone: {
      type: String,
      default: '',
      trim: true,
    },
    email: {
      type: String,
      required: true,
      trim: true,
      lowercase: true,
    },
    instagramUrl: {
      type: String,
      default: '',
      trim: true,
    },
    facebookUrl: {
      type: String,
      default: '',
      trim: true,
    },
    hoursLabel: {
      type: localizedTextSchema,
      required: true,
    },
  },
  {
    _id: false,
  },
);

const companyProfileSchema = new mongoose.Schema(
  {
    siteKey: {
      type: String,
      required: true,
      unique: true,
      trim: true,
      default: 'default',
    },
    companyName: {
      type: String,
      required: true,
      trim: true,
    },
    legalName: {
      type: String,
      default: '',
      trim: true,
    },
    category: {
      type: localizedTextSchema,
      required: true,
    },
    tagline: {
      type: localizedTextSchema,
      required: true,
    },
    heroTitle: {
      type: localizedTextSchema,
      required: true,
    },
    heroSubtitle: {
      type: localizedTextSchema,
      required: true,
    },
    adminLoginLabel: {
      type: localizedTextSchema,
      required: true,
    },
    createAccountLabel: {
      type: localizedTextSchema,
      required: true,
    },
    customerLoginLabel: {
      type: localizedTextSchema,
      required: true,
    },
    staffLoginLabel: {
      type: localizedTextSchema,
      required: true,
    },
    heroPanelTitle: {
      type: localizedTextSchema,
      required: true,
    },
    heroPanelSubtitle: {
      type: localizedTextSchema,
      required: true,
    },
    heroBullets: {
      type: [localizedTextSchema],
      default: [],
    },
    servicesTitle: {
      type: localizedTextSchema,
      required: true,
    },
    serviceCardSubtitle: {
      type: localizedTextSchema,
      required: true,
    },
    serviceLabels: {
      type: [serviceLabelSchema],
      default: [],
    },
    howItWorksTitle: {
      type: localizedTextSchema,
      required: true,
    },
    howItWorksSteps: {
      type: [localizedStepSchema],
      default: [],
    },
    contactSectionTitle: {
      type: localizedTextSchema,
      required: true,
    },
    contactSectionSubtitle: {
      type: localizedTextSchema,
      required: true,
    },
    serviceAreaLabel: {
      type: localizedTextSchema,
      required: true,
    },
    serviceAreaText: {
      type: localizedTextSchema,
      required: true,
    },
    contact: {
      type: companyContactSchema,
      required: true,
    },
    primaryColorHex: {
      type: String,
      default: '#1B4D8C',
      trim: true,
    },
    accentColorHex: {
      type: String,
      default: '#CE7B37',
      trim: true,
    },
  },
  {
    timestamps: true,
  },
);

const CompanyProfile = mongoose.model('CompanyProfile', companyProfileSchema);

module.exports = { CompanyProfile };
