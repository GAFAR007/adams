/**
 * WHAT: Verifies request addresses and returns live Germany-only predictions through Google Maps APIs.
 * WHY: Customer intake should suggest likely addresses while typing, then confirm city and postal code from a real match before the request is sent.
 * HOW: Call Google Places Autocomplete for predictions and Google Geocoding for normalized verification through one provider-aware service.
 */

const { env } = require("../config/env");
const {
  ERROR_CLASSIFICATIONS,
  LOG_STEPS,
} = require("../constants/app.constants");
const {
  logError,
  logInfo,
} = require("../utils/logger");

function getAddressValidationStatus() {
  return {
    provider: env.googleAddressApiKey
      ? "google-maps"
      : "disabled",
    configured: Boolean(env.googleAddressApiKey),
  };
}

function logAddressValidationStatus() {
  const status = getAddressValidationStatus();

  logInfo({
    requestId: "address",
    route: "ADDRESS VERIFICATION",
    step: LOG_STEPS.SERVICE_OK,
    layer: "service",
    operation: "AddressValidationStatus",
    intent:
      "Report the active address-verification provider at backend startup",
    provider: status.provider,
    configured: status.configured,
  });
}

function normalizeText(value) {
  return String(value || "").trim();
}

function buildUnavailableVerification(
  addressLine1,
) {
  return {
    status: "unavailable",
    provider: "google-maps",
    addressLine1,
    city: "",
    postalCode: "",
    formattedAddress: "",
    countryCode: "",
    resolutionHint:
      "Continue with manual city and postal code entry",
  };
}

function buildNotFoundVerification(addressLine1) {
  return {
    status: "not_found",
    provider: "google-maps",
    addressLine1,
    city: "",
    postalCode: "",
    formattedAddress: "",
    countryCode: "",
    resolutionHint:
      "Retype the full street address so the city and postal code can be confirmed automatically",
  };
}

function findAddressComponent(
  result,
  type,
  valueKey = "long_name",
) {
  const components = Array.isArray(
    result?.address_components,
  )
    ? result.address_components
    : [];

  const component = components.find(
    (item) =>
      Array.isArray(item?.types) &&
      item.types.includes(type),
  );

  return normalizeText(component?.[valueKey]);
}

function resolveCity(result) {
  const preferredTypes = [
    "locality",
    "postal_town",
    "administrative_area_level_3",
    "administrative_area_level_2",
    "sublocality",
  ];

  for (const type of preferredTypes) {
    const value = findAddressComponent(
      result,
      type,
    );
    if (value) {
      return value;
    }
  }

  return "";
}

function resolveAddressLine1(
  result,
  fallbackAddress,
) {
  const streetNumber = findAddressComponent(
    result,
    "street_number",
  );
  const route = findAddressComponent(
    result,
    "route",
  );
  const premise = findAddressComponent(
    result,
    "premise",
  );

  const streetLine = [route, streetNumber]
    .filter(Boolean)
    .join(" ")
    .trim();
  if (streetLine) {
    return streetLine;
  }

  if (premise) {
    return premise;
  }

  return normalizeText(fallbackAddress);
}

function buildVerifiedResponse(
  result,
  originalAddress,
) {
  const city = resolveCity(result);
  const postalCode = findAddressComponent(
    result,
    "postal_code",
  );
  const addressLine1 = resolveAddressLine1(
    result,
    originalAddress,
  );
  const countryCode = findAddressComponent(
    result,
    "country",
    "short_name",
  );

  if (
    countryCode &&
    countryCode.toUpperCase() !== "DE"
  ) {
    return buildNotFoundVerification(
      addressLine1,
    );
  }

  if (!city || !postalCode) {
    return {
      status: "not_found",
      provider: "google-maps",
      addressLine1,
      city,
      postalCode,
      formattedAddress: normalizeText(
        result?.formatted_address,
      ),
      countryCode,
      resolutionHint:
        "Retype the full street address so the city and postal code can be confirmed automatically",
    };
  }

  return {
    status: "verified",
    provider: "google-maps",
    addressLine1,
    city,
    postalCode,
    formattedAddress:
      normalizeText(result?.formatted_address) ||
      [addressLine1, postalCode, city]
        .filter(Boolean)
        .join(", "),
    countryCode,
    resolutionHint: "",
  };
}

function buildGeocodeSearchParams({
  addressLine1,
  placeId,
}) {
  const params = new URLSearchParams({
    key: env.googleAddressApiKey,
    region: "de",
    language: "de",
  });

  if (normalizeText(placeId)) {
    params.set(
      "place_id",
      normalizeText(placeId),
    );
  } else {
    params.set(
      "address",
      normalizeText(addressLine1),
    );
  }

  return params;
}

async function autocompleteAddress(
  input,
  logContext,
) {
  const normalizedInput = normalizeText(input);

  if (
    !env.googleAddressApiKey ||
    normalizedInput.length < 3
  ) {
    return [];
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.PROVIDER_CALL_START,
    layer: "service",
    operation: "CustomerAddressAutocomplete",
    intent:
      "Load live Germany-only address suggestions while the customer types the request location",
    provider: "google-maps",
  });

  try {
    const searchParams = new URLSearchParams({
      input: normalizedInput,
      key: env.googleAddressApiKey,
      components: "country:de",
      language: "de",
      types: "address",
    });
    const response = await fetch(
      `https://maps.googleapis.com/maps/api/place/autocomplete/json?${searchParams.toString()}`,
    );

    if (!response.ok) {
      const providerResponse =
        await response.text();

      logError({
        ...logContext,
        step: LOG_STEPS.PROVIDER_CALL_FAIL,
        layer: "service",
        operation: "CustomerAddressAutocomplete",
        intent:
          "Capture the failed Google Places autocomplete response before the chat falls back to manual address entry",
        classification:
          ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
        error_code:
          "GOOGLE_ADDRESS_AUTOCOMPLETE_FAILED",
        resolution_hint:
          "Check the Google Maps Places API key and enabled APIs, then try again",
        message:
          providerResponse ||
          `Provider returned HTTP ${response.status}`,
      });

      return [];
    }

    const payload = await response.json();
    const providerStatus = normalizeText(
      payload?.status,
    );
    const predictions = Array.isArray(
      payload?.predictions,
    )
      ? payload.predictions
      : [];

    if (
      providerStatus === "ZERO_RESULTS" ||
      predictions.length === 0
    ) {
      logInfo({
        ...logContext,
        step: LOG_STEPS.PROVIDER_CALL_OK,
        layer: "service",
        operation: "CustomerAddressAutocomplete",
        intent:
          "Record that no Germany-only address predictions matched the current input",
        provider: "google-maps",
        outcome: "no_results",
      });

      return [];
    }

    if (providerStatus !== "OK") {
      logError({
        ...logContext,
        step: LOG_STEPS.PROVIDER_CALL_FAIL,
        layer: "service",
        operation: "CustomerAddressAutocomplete",
        intent:
          "Capture the rejected Google Places autocomplete response before the chat falls back to manual address entry",
        classification:
          ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
        error_code:
          "GOOGLE_ADDRESS_AUTOCOMPLETE_REJECTED",
        resolution_hint:
          "Check the Google Maps Places API key and enabled APIs, then try again",
        message:
          payload?.error_message ||
          providerStatus ||
          "Google address autocomplete failed",
      });

      return [];
    }

    const items = predictions
      .map((prediction) => ({
        placeId: normalizeText(
          prediction?.place_id,
        ),
        description: normalizeText(
          prediction?.description,
        ),
        primaryText: normalizeText(
          prediction?.structured_formatting
            ?.main_text,
        ),
        secondaryText: normalizeText(
          prediction?.structured_formatting
            ?.secondary_text,
        ),
      }))
      .filter(
        (item) =>
          item.placeId && item.description,
      )
      .slice(0, 5);

    logInfo({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_OK,
      layer: "service",
      operation: "CustomerAddressAutocomplete",
      intent:
        "Confirm Google Places returned Germany-only address predictions for the request intake chat",
      provider: "google-maps",
      outcome: "predictions_ready",
      count: items.length,
    });

    return items;
  } catch (error) {
    logError({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
      layer: "service",
      operation: "CustomerAddressAutocomplete",
      intent:
        "Capture the Google Places autocomplete exception before the chat falls back to manual address entry",
      classification:
        ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      error_code:
        "GOOGLE_ADDRESS_AUTOCOMPLETE_UNAVAILABLE",
      resolution_hint:
        "Check the Google Maps Places API key, network access, and enabled APIs, then try again",
      message: error.message,
    });

    return [];
  }
}

async function verifyAddress(
  addressLine1,
  logContext,
  placeId = "",
) {
  const normalizedAddress =
    normalizeText(addressLine1);

  if (!env.googleAddressApiKey) {
    return {
      ...buildUnavailableVerification(
        normalizedAddress,
      ),
      provider: "disabled",
    };
  }

  logInfo({
    ...logContext,
    step: LOG_STEPS.PROVIDER_CALL_START,
    layer: "service",
    operation: "CustomerAddressVerification",
    intent:
      "Verify the typed service address and derive city plus postal code before request submission",
    provider: "google-maps",
  });

  try {
    const searchParams = buildGeocodeSearchParams(
      {
        addressLine1: normalizedAddress,
        placeId,
      },
    );
    const response = await fetch(
      `https://maps.googleapis.com/maps/api/geocode/json?${searchParams.toString()}`,
    );

    if (!response.ok) {
      const providerResponse =
        await response.text();

      logError({
        ...logContext,
        step: LOG_STEPS.PROVIDER_CALL_FAIL,
        layer: "service",
        operation: "CustomerAddressVerification",
        intent:
          "Capture the failed Google address verification response before the flow falls back to manual entry",
        classification:
          ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
        error_code:
          "GOOGLE_ADDRESS_VERIFICATION_FAILED",
        resolution_hint:
          "Check the Google Address API key and Maps API access, then try again",
        message:
          providerResponse ||
          `Provider returned HTTP ${response.status}`,
      });

      return buildUnavailableVerification(
        normalizedAddress,
      );
    }

    const payload = await response.json();
    const providerStatus = normalizeText(
      payload?.status,
    );
    const results = Array.isArray(
      payload?.results,
    )
      ? payload.results
      : [];

    if (
      providerStatus === "ZERO_RESULTS" ||
      results.length === 0
    ) {
      logInfo({
        ...logContext,
        step: LOG_STEPS.PROVIDER_CALL_OK,
        layer: "service",
        operation: "CustomerAddressVerification",
        intent:
          "Record that Google could not match the typed address strongly enough to confirm city and postal code",
        provider: "google-maps",
        outcome: "not_found",
      });

      return buildNotFoundVerification(
        normalizedAddress,
      );
    }

    if (providerStatus !== "OK") {
      logError({
        ...logContext,
        step: LOG_STEPS.PROVIDER_CALL_FAIL,
        layer: "service",
        operation: "CustomerAddressVerification",
        intent:
          "Capture the rejected Google geocoding response before the flow falls back to manual address entry",
        classification:
          ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
        error_code:
          "GOOGLE_ADDRESS_VERIFICATION_REJECTED",
        resolution_hint:
          "Check the Google Address API key and enabled APIs, then try again",
        message:
          payload?.error_message ||
          providerStatus ||
          "Google address verification failed",
      });

      return buildUnavailableVerification(
        normalizedAddress,
      );
    }

    const verifiedResult = buildVerifiedResponse(
      results[0],
      normalizedAddress,
    );

    logInfo({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_OK,
      layer: "service",
      operation: "CustomerAddressVerification",
      intent:
        "Confirm the address-verification provider returned a normalized location for request intake",
      provider: "google-maps",
      outcome: verifiedResult.status,
      city: verifiedResult.city || "-",
      postalCode:
        verifiedResult.postalCode || "-",
    });

    return verifiedResult;
  } catch (error) {
    logError({
      ...logContext,
      step: LOG_STEPS.PROVIDER_CALL_FAIL,
      layer: "service",
      operation: "CustomerAddressVerification",
      intent:
        "Capture the address-verification provider exception before the flow falls back to manual location entry",
      classification:
        ERROR_CLASSIFICATIONS.PROVIDER_OUTAGE,
      error_code:
        "GOOGLE_ADDRESS_VERIFICATION_UNAVAILABLE",
      resolution_hint:
        "Check the Google Address API key, network access, and enabled APIs, then try again",
      message: error.message,
    });

    return buildUnavailableVerification(
      normalizedAddress,
    );
  }
}

module.exports = {
  autocompleteAddress,
  getAddressValidationStatus,
  logAddressValidationStatus,
  verifyAddress,
};
