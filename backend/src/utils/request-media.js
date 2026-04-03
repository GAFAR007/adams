/**
 * WHAT: Derives request media summary counts from attachment messages.
 * WHY: Intake rules and review flows need stable photo/video counts without duplicating MIME checks in every service.
 * HOW: Count attached message media by type and persist the totals back onto the request document.
 */

function isImageMimeType(value) {
  return String(value || '').toLowerCase().startsWith('image/');
}

function isVideoMimeType(value) {
  return String(value || '').toLowerCase().startsWith('video/');
}

function buildRequestMediaSummary(messages, existingSummary = {}, overrides = {}) {
  const summary = {
    photoCount: 0,
    videoCount: 0,
    documentCount: 0,
    intakePhotoCount:
      typeof existingSummary?.intakePhotoCount === 'number'
        ? existingSummary.intakePhotoCount
        : 0,
    intakeVideoCount:
      typeof existingSummary?.intakeVideoCount === 'number'
        ? existingSummary.intakeVideoCount
        : 0,
    updatedAt: new Date(),
  };

  const items = Array.isArray(messages) ? messages : [];
  for (const message of items) {
    const mimeType = message?.attachment?.mimeType;
    if (!mimeType) {
      continue;
    }

    if (isImageMimeType(mimeType)) {
      summary.photoCount += 1;
      continue;
    }

    if (isVideoMimeType(mimeType)) {
      summary.videoCount += 1;
      continue;
    }

    summary.documentCount += 1;
  }

  if (typeof overrides.intakePhotoCount === 'number') {
    summary.intakePhotoCount = overrides.intakePhotoCount;
  }

  if (typeof overrides.intakeVideoCount === 'number') {
    summary.intakeVideoCount = overrides.intakeVideoCount;
  }

  return summary;
}

function refreshRequestMediaSummary(request, overrides = {}) {
  if (!request) {
    return null;
  }

  request.mediaSummary = buildRequestMediaSummary(
    request.messages,
    request.mediaSummary,
    overrides,
  );

  return request.mediaSummary;
}

module.exports = {
  buildRequestMediaSummary,
  isImageMimeType,
  isVideoMimeType,
  refreshRequestMediaSummary,
};
