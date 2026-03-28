/// WHAT: Renders the staff login using the shared role-aware login experience.
/// WHY: Staff should get the same clean login structure while still routing only into staff-owned queue work.
/// HOW: Configure the shared role login screen with staff-specific copy and the staff dashboard route.
library;

import 'package:flutter/material.dart';

import 'role_login_screen.dart';

class StaffLoginScreen extends StatelessWidget {
  const StaffLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RoleLoginScreen(
      role: 'staff',
      pageTitle: 'Staff Login',
      headerTitle: 'Sign in to your space',
      headerSubtitle:
          'Pick up waiting customers, reply in live threads, and clear assigned work quickly.',
      emailLabel: 'Staff email',
      submitLabel: 'Open Queue Workspace',
      failureMessage: 'Use the staff login only with a staff account.',
      successRoute: '/staff',
      icon: Icons.support_agent_rounded,
    );
  }
}
