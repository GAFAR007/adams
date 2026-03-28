/// WHAT: Provides a non-web no-op session persistence implementation.
/// WHY: Local browser storage is only available on web, but shared auth code still needs one interface.
/// HOW: Return null for loads and ignore save/clear calls on non-web targets.
library;

String? loadStoredAuthSession() {
  return null;
}

void saveStoredAuthSession(String serializedSession) {
  final _ = serializedSession;
}

void clearStoredAuthSession() {}
