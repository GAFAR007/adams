/// WHAT: Defines the backend-fetched quick-fill login accounts used by role-specific auth screens.
/// WHY: Login screens should parse backend auth shortcuts once instead of reading raw JSON in the UI.
/// HOW: Shape each demo account and the role-level autofill flag into typed immutable Dart models.
library;

class DemoLoginAccount {
  const DemoLoginAccount({
    required this.id,
    required this.fullName,
    required this.email,
    required this.quickFillPassword,
  });

  final String id;
  final String fullName;
  final String email;
  final String? quickFillPassword;

  factory DemoLoginAccount.fromJson(Map<String, dynamic> json) {
    return DemoLoginAccount(
      id: json['id'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      quickFillPassword: json['quickFillPassword'] as String?,
    );
  }
}

class DemoLoginBundle {
  const DemoLoginBundle({
    required this.role,
    required this.passwordAutofillEnabled,
    required this.accounts,
  });

  final String role;
  final bool passwordAutofillEnabled;
  final List<DemoLoginAccount> accounts;

  factory DemoLoginBundle.fromJson(Map<String, dynamic> json) {
    final rawAccounts = json['accounts'] as List<dynamic>? ?? const <dynamic>[];

    return DemoLoginBundle(
      role: json['role'] as String? ?? '',
      passwordAutofillEnabled:
          json['passwordAutofillEnabled'] as bool? ?? false,
      accounts: rawAccounts
          .whereType<Map<String, dynamic>>()
          .map(DemoLoginAccount.fromJson)
          .toList(),
    );
  }
}
