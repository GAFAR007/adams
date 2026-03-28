/// WHAT: Defines the mutable authentication state consumed by routing and protected screens.
/// WHY: The app needs one source of truth for bootstrap progress, active user, and session token.
/// HOW: Store bootstrapping, submission, and authenticated session fields in an immutable value object.
library;

import '../../../core/models/auth_user.dart';

class AuthState {
  const AuthState({
    this.isBootstrapping = true,
    this.hasBootstrapped = false,
    this.isSubmitting = false,
    this.user,
    this.accessToken,
    this.errorMessage,
  });

  final bool isBootstrapping;
  final bool hasBootstrapped;
  final bool isSubmitting;
  final AuthUser? user;
  final String? accessToken;
  final String? errorMessage;

  bool get isAuthenticated => user != null && accessToken != null && accessToken!.isNotEmpty;
  String get role => user?.role ?? '';

  AuthState copyWith({
    bool? isBootstrapping,
    bool? hasBootstrapped,
    bool? isSubmitting,
    AuthUser? user,
    String? accessToken,
    String? errorMessage,
    bool clearSession = false,
    bool clearError = false,
  }) {
    return AuthState(
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      hasBootstrapped: hasBootstrapped ?? this.hasBootstrapped,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      user: clearSession ? null : user ?? this.user,
      accessToken: clearSession ? null : accessToken ?? this.accessToken,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
