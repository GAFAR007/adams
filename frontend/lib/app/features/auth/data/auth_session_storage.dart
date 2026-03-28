/// WHAT: Wraps platform-specific auth-session persistence for startup restore and logout cleanup.
/// WHY: Web refreshes destroy in-memory auth state, so the auth controller needs a single persistence boundary.
/// HOW: Serialize `AuthSession` into a string, store it via conditional imports, and restore it when still parseable.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_session.dart';
import 'auth_session_storage_io.dart'
    if (dart.library.html) 'auth_session_storage_web.dart'
    as session_storage;

final authSessionStorageProvider = Provider<AuthSessionStorage>((Ref ref) {
  return const AuthSessionStorage();
});

class AuthSessionStorage {
  const AuthSessionStorage();

  AuthSession? load() {
    final serializedSession = session_storage.loadStoredAuthSession();

    // WHY: Treat missing or corrupt local state as an empty session so startup can fall back to refresh or logged-out mode cleanly.
    if (serializedSession == null || serializedSession.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(serializedSession) as Map<String, dynamic>;
      return AuthSession.fromJson(decoded);
    } catch (_) {
      clear();
      return null;
    }
  }

  void save(AuthSession session) {
    session_storage.saveStoredAuthSession(jsonEncode(session.toJson()));
  }

  void clear() {
    session_storage.clearStoredAuthSession();
  }
}
