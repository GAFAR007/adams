// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

/// WHAT: Persists the authenticated session in browser local storage for refresh-safe web auth.
/// WHY: Reloading the Flutter web app clears in-memory state, so a small persisted session avoids forced re-login on every refresh.
/// HOW: Store the serialized auth session under one stable local-storage key and expose load/save/clear helpers.
library;

import 'dart:html' as html;

const String _authSessionStorageKey = 'adams.auth.session';

String? loadStoredAuthSession() {
  return html.window.localStorage[_authSessionStorageKey];
}

void saveStoredAuthSession(String serializedSession) {
  html.window.localStorage[_authSessionStorageKey] = serializedSession;
}

void clearStoredAuthSession() {
  html.window.localStorage.remove(_authSessionStorageKey);
}
