/// WHAT: Renders the admin login using the shared role-aware login experience.
/// WHY: Admin access should keep the same polished structure as other roles while still routing into operations tools.
/// HOW: Configure the shared role login screen with the admin role contract and dashboard route.
library;

import 'package:flutter/material.dart';

import 'role_login_screen.dart';

class AdminLoginScreen extends StatelessWidget {
  const AdminLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleLoginScreen(
      role: 'admin',
      pageTitle: 'Admin Login',
      headerTitle: 'Sign in to your operations space',
      headerSubtitle:
          'Manage the request queue, staff load, invites, and handoff performance.',
      emailLabel: 'Admin email',
      submitLabel: 'Enter Dashboard',
      failureMessage: 'Use an admin account for this dashboard.',
      successRoute: '/admin',
      icon: Icons.admin_panel_settings_rounded,
    );
  }
}
