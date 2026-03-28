/// WHAT: Defines the auth payload returned from the backend for login, register, and refresh flows.
/// WHY: Auth repositories should parse the response contract once before controller logic consumes it.
/// HOW: Map the backend payload into a user model plus access token.
library;

import '../../../core/models/auth_user.dart';

class AuthSession {
  const AuthSession({
    required this.message,
    required this.user,
    required this.accessToken,
  });

  final String message;
  final AuthUser user;
  final String accessToken;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'message': message,
      'user': user.toJson(),
      'accessToken': accessToken,
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      message: json['message'] as String? ?? '',
      user: AuthUser.fromJson(
        json['user'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      accessToken: json['accessToken'] as String? ?? '',
    );
  }
}
