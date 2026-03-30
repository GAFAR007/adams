/// WHAT: Owns auth state transitions for bootstrap, login, registration, and logout.
/// WHY: Route guards and protected features need one orchestrator for session lifecycle changes.
/// HOW: Delegate HTTP work to repositories, keep the API client token in sync, and expose simple methods to UI.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/auth_repository.dart';
import '../data/auth_session_storage.dart';
import '../domain/auth_session.dart';
import '../domain/auth_state.dart';
import '../../staff/data/staff_repository.dart';

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    return const AuthState();
  }

  AuthRepository get _authRepository => ref.read(authRepositoryProvider);
  AuthSessionStorage get _sessionStorage =>
      ref.read(authSessionStorageProvider);
  StaffRepository get _staffRepository => ref.read(staffRepositoryProvider);
  ApiClient get _client => ref.read(apiClientProvider);

  Future<void> bootstrapSession() async {
    if (state.hasBootstrapped ||
        state.isBootstrapping == false && state.isAuthenticated) {
      return;
    }

    state = state.copyWith(isBootstrapping: true, clearError: true);
    debugPrint(
      'AuthController.bootstrapSession: attempting refresh-based bootstrap',
    );

    final persistedSession = _sessionStorage.load();

    // WHY: Restore a still-valid access token immediately so a simple page refresh does not force a fresh login round-trip.
    if (persistedSession != null &&
        !_isAccessTokenExpired(persistedSession.accessToken)) {
      _applySession(persistedSession);
      unawaited(_refreshSessionInBackground());
      return;
    }

    try {
      final session = await _authRepository.refresh();
      _applySession(session);
    } catch (_) {
      // A failed refresh at startup should land the app in a clean logged-out state.
      _sessionStorage.clear();
      _client.setAccessToken(null);
      state = state.copyWith(
        isBootstrapping: false,
        hasBootstrapped: true,
        clearSession: true,
        clearError: true,
      );
    }
  }

  Future<void> registerCustomer({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String verificationToken,
  }) async {
    await _runAuthAction(() async {
      final session = await _authRepository.registerCustomer(
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
        password: password,
        verificationToken: verificationToken,
      );
      _ensureRole(
        session,
        expectedRole: 'customer',
        failureMessage: 'Use the customer registration flow only.',
      );
      _applySession(session);
    });
  }

  Future<void> loginAsRole({
    required String email,
    required String password,
    required String expectedRole,
    required String failureMessage,
  }) async {
    await _runAuthAction(() async {
      final session = await _authRepository.login(
        email: email,
        password: password,
      );
      _ensureRole(
        session,
        expectedRole: expectedRole,
        failureMessage: failureMessage,
      );
      _applySession(session);
    });
  }

  Future<void> registerStaff({
    required String inviteToken,
    required String firstName,
    required String lastName,
    required String phone,
    required String password,
  }) async {
    await _runAuthAction(() async {
      final session = await _staffRepository.registerFromInvite(
        inviteToken: inviteToken,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        password: password,
      );
      _ensureRole(
        session,
        expectedRole: 'staff',
        failureMessage: 'This invite does not create a staff account.',
      );
      _applySession(session);
    });
  }

  Future<void> logout() async {
    debugPrint('AuthController.logout: logging out current session');

    try {
      await _authRepository.logout();
    } finally {
      _sessionStorage.clear();
      _client.setAccessToken(null);
      state = state.copyWith(
        isBootstrapping: false,
        hasBootstrapped: true,
        isSubmitting: false,
        clearSession: true,
        clearError: true,
      );
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    state = state.copyWith(
      isSubmitting: true,
      clearError: true,
      hasBootstrapped: true,
      isBootstrapping: false,
    );

    try {
      await action();
    } catch (error) {
      _sessionStorage.clear();
      _client.setAccessToken(null);
      state = state.copyWith(
        isSubmitting: false,
        hasBootstrapped: true,
        isBootstrapping: false,
        errorMessage: error.toString().replaceFirst('Exception: ', ''),
        clearSession: true,
      );
      rethrow;
    }
  }

  void _applySession(AuthSession session) {
    _sessionStorage.save(session);
    _client.setAccessToken(session.accessToken);
    state = state.copyWith(
      user: session.user,
      accessToken: session.accessToken,
      isSubmitting: false,
      isBootstrapping: false,
      hasBootstrapped: true,
      clearError: true,
    );
  }

  Future<void> _refreshSessionInBackground() async {
    try {
      final refreshedSession = await _authRepository.refresh();
      _applySession(refreshedSession);
    } catch (_) {
      // WHY: Keep the restored local session active when silent refresh fails so the user does not get logged out on every reload.
    }
  }

  bool _isAccessTokenExpired(String token) {
    try {
      final tokenParts = token.split('.');
      if (tokenParts.length < 2) {
        return true;
      }

      final normalizedPayload = base64Url.normalize(tokenParts[1]);
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(normalizedPayload)))
              as Map<String, dynamic>;
      final expiry = payload['exp'];
      if (expiry is! num) {
        return true;
      }

      final expiryTime = DateTime.fromMillisecondsSinceEpoch(
        expiry.toInt() * 1000,
      );

      // WHY: Expire locally a little early so requests do not race the backend with a token that is about to die.
      return DateTime.now().isAfter(
        expiryTime.subtract(const Duration(seconds: 30)),
      );
    } catch (_) {
      return true;
    }
  }

  void _ensureRole(
    AuthSession session, {
    required String expectedRole,
    required String failureMessage,
  }) {
    if (session.user.role != expectedRole) {
      throw ApiException(failureMessage);
    }
  }
}
