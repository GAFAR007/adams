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
    try {
      final response = await _client.getJson('/auth/demo-accounts/$role');
      final bundle = DemoLoginBundle.fromJson(response);
      if (bundle.accounts.isNotEmpty) {
        return bundle;
      }
    } on ApiException {
      // WHY: Email-only seeded shortcuts should stay available even when the backend quick-fill endpoint is disabled or temporarily unavailable.
    }

    return _fallbackDemoAccounts(role);
  }

  DemoLoginBundle _fallbackDemoAccounts(String role) {
    switch (role) {
      case 'admin':
        return const DemoLoginBundle(
          role: 'admin',
          passwordAutofillEnabled: false,
          accounts: <DemoLoginAccount>[
            DemoLoginAccount(
              id: 'fallback-admin-1',
              fullName: 'Adams Gafar',
              email: 'admin@adams.local',
              role: 'admin',
              staffType: null,
              quickFillPassword: null,
            ),
          ],
        );
      case 'customer':
        return const DemoLoginBundle(
          role: 'customer',
          passwordAutofillEnabled: false,
          accounts: <DemoLoginAccount>[
            DemoLoginAccount(
              id: 'fallback-customer-1',
              fullName: 'Fatima Kaya',
              email: 'customer1@adams.local',
              role: 'customer',
              staffType: null,
              quickFillPassword: null,
            ),
          ],
        );
      case 'staff':
        return const DemoLoginBundle(
          role: 'staff',
          passwordAutofillEnabled: false,
          accounts: <DemoLoginAccount>[
            DemoLoginAccount(
              id: 'fallback-staff-care-1',
              fullName: 'Amina Yilmaz',
              email: 'care1@adams.local',
              role: 'staff',
              staffType: 'customer_care',
              quickFillPassword: null,
            ),
            DemoLoginAccount(
              id: 'fallback-staff-1',
              fullName: 'Daniel Weber',
              email: 'staff1@adams.local',
              role: 'staff',
              staffType: 'technician',
              quickFillPassword: null,
            ),
            DemoLoginAccount(
              id: 'fallback-staff-2',
              fullName: 'Sofia Keller',
              email: 'staff2@adams.local',
              role: 'staff',
              staffType: 'contractor',
              quickFillPassword: null,
            ),
            DemoLoginAccount(
              id: 'fallback-staff-3',
              fullName: 'Jonas Hartmann',
              email: 'staff3@adams.local',
              role: 'staff',
              staffType: 'technician',
              quickFillPassword: null,
            ),
            DemoLoginAccount(
              id: 'fallback-staff-4',
              fullName: 'Leonie Brandt',
              email: 'staff4@adams.local',
              role: 'staff',
              staffType: 'technician',
              quickFillPassword: null,
            ),
            DemoLoginAccount(
              id: 'fallback-staff-5',
              fullName: 'Marek Nowak',
              email: 'staff5@adams.local',
              role: 'staff',
              staffType: 'contractor',
              quickFillPassword: null,
            ),
          ],
        );
      default:
        return DemoLoginBundle(
          role: role,
          passwordAutofillEnabled: false,
          accounts: const <DemoLoginAccount>[],
        );
    }
  }
}
