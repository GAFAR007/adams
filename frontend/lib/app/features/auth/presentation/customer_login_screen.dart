/// WHAT: Renders the customer login using the shared role-aware login experience.
/// WHY: Customers should get the same polished login structure while still routing into their request inbox only.
/// HOW: Configure the shared role login screen with customer-specific copy, routing, and the register action.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'role_login_screen.dart';

class CustomerLoginScreen extends StatelessWidget {
  const CustomerLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleLoginScreen(
      role: 'customer',
      pageTitle: 'Customer Login',
      headerTitle: 'Sign in to your service space',
      headerSubtitle:
          'Track your requests, see who picked up your queue, and continue the conversation in one place.',
      emailLabel: 'Email',
      submitLabel: 'Enter Request Inbox',
      failureMessage: 'Use the customer login for customer accounts only.',
      successRoute: '/app/requests',
      icon: Icons.home_work_rounded,
      footer: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => context.go('/book-service'),
          child: const Text('Need a first booking? Start service chat'),
        ),
      ),
    );
  }
}
