/**
 * WHAT: Generates subtle queue-assistant copy for customer requests that are still waiting for staff pickup.
 * WHY: The waiting thread should feel useful and on-brand instead of repeating one generic reassurance line.
 * HOW: Build small, service-aware replies from request data and optional company-profile context.
 */

const DEFAULT_COMPANY_NAME = 'CL Facility Management';

const DEFAULT_SERVICE_LABELS = Object.freeze({
  fire_damage_cleaning: 'Fire Damage Cleaning',
  needle_sweeps_sharps_cleanups: 'Needle Sweeps & Sharps Clean-Ups',
  hoarding_cleanups: 'Hoarding Clean-Ups',
  trauma_decomposition_cleanups: 'Trauma & Decomposition Clean-Ups',
  infection_control_cleaning: 'Infection Control Cleaning',
  building_cleaning: 'Building Cleaning',
  window_cleaning: 'Window Cleaning',
  office_cleaning: 'Office Cleaning',
  house_cleaning: 'House Cleaning',
  warehouse_hall_cleaning: 'Warehouse & Hall Cleaning',
  window_glass_cleaning: 'Window & Glass Cleaning',
  winter_service: 'Winter Service',
  caretaker_service: 'Caretaker Service',
  garden_care: 'Garden Care',
  post_construction_cleaning: 'Post-Construction Cleaning',
});

const SERVICE_TALKING_POINTS = Object.freeze({
  fire_damage_cleaning:
    'fire damage cleanup, soot removal, and post-incident property recovery',
  needle_sweeps_sharps_cleanups:
    'needle sweeps, sharps collection, and safer access around affected areas',
  hoarding_cleanups:
    'hoarding clear-outs, waste removal, and practical property resets',
  trauma_decomposition_cleanups:
    'specialist trauma cleanup, decomposition remediation, and sensitive recovery work',
  infection_control_cleaning:
    'infection-control cleaning, high-touch disinfection, and hygiene-led resets',
  building_cleaning:
    'offices, shared areas, and routine building upkeep',
  window_cleaning:
    'glass, frames, and clearer day-to-day presentation',
  office_cleaning:
    'desks, meeting rooms, shared kitchens, and day-to-day office upkeep',
  house_cleaning:
    'occupied homes, reset work, and recurring domestic support',
  warehouse_hall_cleaning:
    'warehouse floors, dust control, and operational spaces',
  window_glass_cleaning:
    'storefront glass, frames, and first-impression presentation',
  winter_service:
    'snow clearance, gritting, and safer site access',
  caretaker_service:
    'day-to-day site checks, small fixes, and ongoing property support',
  garden_care:
    'grounds presentation, seasonal upkeep, and outdoor maintenance',
  post_construction_cleaning:
    'handover cleans, dust removal, and ready-to-use finishes',
});

function normalizeText(value) {
  return String(value || '').trim();
}

function resolveCompanyName(companyProfile) {
  return normalizeText(companyProfile?.companyName) || DEFAULT_COMPANY_NAME;
}

function resolveServiceLabel(companyProfile, serviceType) {
  const normalizedServiceType = normalizeText(serviceType);
  const localizedLabel = Array.isArray(companyProfile?.serviceLabels)
    ? companyProfile.serviceLabels.find((entry) => {
        return normalizeText(entry?.key) === normalizedServiceType;
      })
    : null;

  return (
    normalizeText(localizedLabel?.label?.en) ||
    normalizeText(localizedLabel?.label?.de) ||
    DEFAULT_SERVICE_LABELS[normalizedServiceType] ||
    'Service Support'
  );
}

function resolveServiceTalkingPoint(serviceType) {
  return (
    SERVICE_TALKING_POINTS[normalizeText(serviceType)] ||
    'homes, offices, and managed properties'
  );
}

function resolveFirstName(request) {
  const fullName = normalizeText(request?.contactSnapshot?.fullName);
  return fullName ? fullName.split(/\s+/)[0] : '';
}

function resolveAssignedStaffName(request) {
  const fullName = normalizeText(request?.assignedStaff?.fullName);
  if (fullName) {
    return fullName;
  }

  return [request?.assignedStaff?.firstName, request?.assignedStaff?.lastName]
    .map(normalizeText)
    .filter(Boolean)
    .join(' ')
    .trim();
}

function assignedStaffIsOffline(request) {
  return normalizeLookupText(request?.assignedStaff?.staffAvailability) === 'offline';
}

function resolveLocationFragment(request) {
  const city = normalizeText(request?.location?.city);
  return city ? ` in ${city}` : '';
}

function resolveTimeWindowSentence(request) {
  const preferredTimeWindow = normalizeText(request?.preferredTimeWindow);
  return preferredTimeWindow
    ? ` I still have your ${preferredTimeWindow.toLowerCase()} preference noted.`
    : '';
}

function resolveHoursLabel(companyProfile) {
  return (
    normalizeText(companyProfile?.contact?.hoursLabel?.en) ||
    normalizeText(companyProfile?.contact?.hoursLabel?.de) ||
    'business hours'
  );
}

function resolveServiceArea(companyProfile) {
  return (
    normalizeText(companyProfile?.serviceAreaText?.en) ||
    normalizeText(companyProfile?.serviceAreaText?.de) ||
    'Monchengladbach and nearby areas'
  );
}

function normalizeLookupText(value) {
  return normalizeText(value).toLowerCase();
}

function containsAny(value, patterns) {
  const text = normalizeLookupText(value);
  return patterns.some((pattern) => text.includes(pattern));
}

function buildGreeting(request) {
  const firstName = resolveFirstName(request);
  return firstName ? `Hi ${firstName},` : 'Hi,';
}

function buildAssistantCoverageSentence(request) {
  const staffName = resolveAssignedStaffName(request);

  if (!staffName) {
    return 'I’m here while the team reviews your request.';
  }

  if (assignedStaffIsOffline(request)) {
    return `${staffName} is offline right now, so I’m covering the chat until they are back.`;
  }

  if (request?.aiControlEnabled) {
    return `${staffName} asked me to keep the chat moving for now.`;
  }

  return 'I’m here to keep the conversation tidy for the team.';
}

function buildQueueCreatedAiText({ request, companyProfile }) {
  const companyName = resolveCompanyName(companyProfile);
  const serviceLabel = resolveServiceLabel(companyProfile, request?.serviceType);
  const locationFragment = resolveLocationFragment(request);
  const timeWindowSentence = resolveTimeWindowSentence(request);

  return `${buildGreeting(request)} I’m Naima from ${companyName}. Your ${serviceLabel} request is safely in the live queue${locationFragment}. While the team reviews it, I’m here to answer quick questions about our company, services, and next steps, or to keep any extra notes and photos organised for staff.${timeWindowSentence}`;
}

function buildQueueFollowUpAiText({ request, companyProfile, customerText }) {
  const companyName = resolveCompanyName(companyProfile);
  const serviceLabel = resolveServiceLabel(companyProfile, request?.serviceType);
  const talkingPoint = resolveServiceTalkingPoint(request?.serviceType);
  const serviceArea = resolveServiceArea(companyProfile);
  const hoursLabel = resolveHoursLabel(companyProfile);
  const timeWindowSentence = resolveTimeWindowSentence(request);
  const coverageSentence = buildAssistantCoverageSentence(request);
  const phone = normalizeText(companyProfile?.contact?.phone);
  const email = normalizeText(companyProfile?.contact?.email);
  const lookupText = normalizeLookupText(customerText);

  if (
    containsAny(lookupText, [
      'how long',
      'queue',
      'wait',
      'reply',
      'respond',
      'response',
      'staff join',
      'pick up',
      'pickup',
      'when will',
    ])
  ) {
    return `${buildGreeting(request)} I cannot promise the exact reply time, but ${coverageSentence} Your ${serviceLabel} request stays active in this chat, and the team can pick up from the latest notes here. While you wait, I’m happy to answer questions about ${companyName}, our services, or what happens next.`;
  }

  if (
    containsAny(lookupText, [
      'what do you do',
      'what services',
      'about the company',
      'about your company',
      'who are you',
      'tell me about',
      'company',
    ])
  ) {
    return `${buildGreeting(request)} I’m Naima from ${companyName}. ${coverageSentence} We support ${talkingPoint} and broader facility work across ${serviceArea}. We focus on clear communication, steady handoff to staff, and keeping each request organised in one place so customers always know what is happening.`;
  }

  if (
    containsAny(lookupText, [
      'price',
      'quote',
      'cost',
      'how much',
      'rate',
      'rates',
    ])
  ) {
    return `${buildGreeting(request)} ${coverageSentence} Final pricing is confirmed after the team reviews the scope, access, timing, and frequency of the work. For ${serviceLabel}, extra detail about surfaces, size, and access points helps the quote come back more accurately.${timeWindowSentence}`;
  }

  if (
    containsAny(lookupText, [
      'phone',
      'email',
      'contact',
      'call',
      'reach you',
      'opening hours',
      'hours',
      'open',
      'number',
    ])
  ) {
    const contactLine = [phone, email].filter(Boolean).join(' or ');
    return `${buildGreeting(request)} you can reach ${companyName}${contactLine ? ` on ${contactLine}` : ''}. Our listed hours are ${hoursLabel}. ${coverageSentence} I’m still here in the thread if you want help with the request itself.`;
  }

  if (
    containsAny(lookupText, [
      'service area',
      'cover',
      'where do you work',
      'which area',
      'location',
    ])
  ) {
    return `${buildGreeting(request)} we currently present our service area as ${serviceArea}. ${coverageSentence} If your address is already in this request, the team will review it from there and continue in this same chat.`;
  }

  if (
    containsAny(lookupText, [
      'what happens next',
      'next step',
      'what next',
      'appointment',
      'when do you come',
      'visit',
    ])
  ) {
    return `${buildGreeting(request)} the next step is to keep this thread current so the team can continue cleanly from here. ${coverageSentence} After that, they can confirm the brief, answer practical questions, and agree timing or quoting details with you.${timeWindowSentence}`;
  }

  if (
    containsAny(lookupText, [
      'photo',
      'picture',
      'image',
      'file',
      'attachment',
    ])
  ) {
    return `${buildGreeting(request)} yes, photos and files are useful here. ${coverageSentence} They help the team review access points, surfaces, and any tricky areas before they reply, especially for ${serviceLabel} work.`;
  }

  if (
    containsAny(lookupText, [
      'hi',
      'hello',
      'hey',
      'thanks',
      'thank you',
    ]) && lookupText.length < 40
  ) {
    return `${buildGreeting(request)} ${coverageSentence} I can answer questions about ${companyName}, our services, contact details, or the next steps, and I can also keep extra notes tidy for staff.`;
  }

  return `${buildGreeting(request)} I’ve added that to your ${serviceLabel} request. ${coverageSentence} I can help with questions about ${companyName}, what we do, the service area, contact details, or what happens next.${timeWindowSentence}`;
}

function buildQueueAttachmentAiText({
  request,
  companyProfile,
  attachmentName,
}) {
  const companyName = resolveCompanyName(companyProfile);
  const serviceLabel = resolveServiceLabel(companyProfile, request?.serviceType);
  const fileLead = normalizeText(attachmentName)
    ? `${normalizeText(attachmentName)} is now in the thread.`
    : 'Your file is now in the thread.';
  return `${buildGreeting(request)} ${fileLead} That helps the ${companyName} team review your ${serviceLabel} request more clearly before they join the thread. If there is one area you want them to notice first, send a quick note and I will keep it attached to the brief.`;
}

function buildQueueDetailsUpdatedAiText({ request, companyProfile }) {
  const companyName = resolveCompanyName(companyProfile);
  const serviceLabel = resolveServiceLabel(companyProfile, request?.serviceType);
  const timeWindowSentence = resolveTimeWindowSentence(request);

  return `${buildGreeting(request)} your ${serviceLabel} details are updated and the latest brief is now clean and ready for the team. If you want, I can still help with questions about ${companyName} or the next steps while you wait.${timeWindowSentence}`;
}

function buildAiControlEnabledText({ request, companyProfile }) {
  const companyName = resolveCompanyName(companyProfile);
  const staffName = resolveAssignedStaffName(request) || 'your staff contact';
  const serviceLabel = resolveServiceLabel(companyProfile, request?.serviceType);

  return `${buildGreeting(request)} I’m back in the chat while ${staffName} steps away. I can help with questions about ${companyName}, our ${serviceLabel} service, contact details, or what happens next, and I’ll keep any new notes tidy for ${staffName} to resume later.`;
}

module.exports = {
  buildAiControlEnabledText,
  buildQueueAttachmentAiText,
  buildQueueCreatedAiText,
  buildQueueDetailsUpdatedAiText,
  buildQueueFollowUpAiText,
};
