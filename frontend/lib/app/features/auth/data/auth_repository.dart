/// WHAT: Talks to backend auth endpoints for registration, login, refresh, logout, and current-user fetches.
/// WHY: Auth HTTP behavior should stay isolated from controllers and presentation logic.
/// HOW: Call the versioned backend endpoints through `ApiClient` and parse the shared auth contract.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/auth_user.dart';
import '../../../core/network/api_client.dart';
import '../domain/demo_login_bundle.dart';
import '../domain/auth_session.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(apiClientProvider));
});

final authDemoAccountsProvider = FutureProvider.autoDispose
    .family<DemoLoginBundle, String>((ref, role) async {
      // WHY: Login shortcuts can change after new registrations, so the list should refetch when the screen is reopened.
      return ref.watch(authRepositoryProvider).fetchDemoAccounts(role: role);
    });

class AuthRepository {
  const AuthRepository(this._client);

  final ApiClient _client;

  Future<AuthSession> registerCustomer({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String verificationToken,
  }) async {
    final response = await _client.postJson(
      '/auth/customer/register',
      data: <String, dynamic>{
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'password': password,
        'verificationToken': verificationToken,
      },
    );

    return AuthSession.fromJson(response);
  }

  Future<void> requestCustomerRegistrationCode({required String email}) async {
    await _client.postJson(
      '/auth/customer/register/request-code',
      data: <String, dynamic>{'email': email},
    );
  }

  Future<String> verifyCustomerRegistrationCode({
    required String email,
    required String code,
  }) async {
    final response = await _client.postJson(
      '/auth/customer/register/verify-code',
      data: <String, dynamic>{'email': email, 'code': code},
    );

    final verificationToken = response['verificationToken'];
    if (verificationToken is String && verificationToken.isNotEmpty) {
      return verificationToken;
    }

    throw const ApiException('Email verification token was missing');
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.postJson(
      '/auth/login',
      data: <String, dynamic>{'email': email, 'password': password},
    );

    return AuthSession.fromJson(response);
  }

  Future<AuthSession> refresh() async {
    final response = await _client.postJson('/auth/refresh');
    return AuthSession.fromJson(response);
  }

  Future<void> logout() async {
    await _client.postJson('/auth/logout');
  }

  Future<AuthUser> me() async {
    final response = await _client.getJson('/auth/me');
    return AuthUser.fromJson(
      response['user'] as Map<String, dynamic>? ?? const <String, dynamic>{},
    );
  }

  Future<DemoLoginBundle> fetchDemoAccounts({required String role}) async {
    final response = await _client.getJson('/auth/demo-accounts/$role');
    return DemoLoginBundle.fromJson(response);
  }
}
