/// WHAT: Renders the staff login using the shared role-aware login experience.
/// WHY: Staff should get the same clean login structure while still routing only into staff-owned queue work.
/// HOW: Configure the shared role login screen with staff-specific copy and the staff dashboard route.
library;

import 'package:flutter/material.dart';

import 'role_login_screen.dart';

class StaffLoginScreen extends StatelessWidget {
  const StaffLoginScreen({
    super.key,
    this.initialLanguageCode,
    this.initialEmail,
  });

  final String? initialLanguageCode;
  final String? initialEmail;

  @override
  Widget build(BuildContext context) {
    return RoleLoginScreen(
      role: 'staff',
      copy: const RoleLoginCopy(
        pageTitle: 'Staff Login',
        pageTitleDe: 'Mitarbeiter-Login',
        eyebrow: 'Team access',
        eyebrowDe: 'Teamzugang',
        headerTitle: 'Sign in to your staff workspace',
        headerTitleDe: 'Melden Sie sich in Ihrem Team-Bereich an',
        headerSubtitle:
            'Pick up waiting customers, reply in live threads, and clear assigned work quickly.',
        headerSubtitleDe:
            'Übernehmen Sie wartende Kunden, antworten Sie live im Thread und erledigen Sie zugewiesene Arbeit direkt.',
        emailLabel: 'Staff email',
        emailLabelDe: 'Mitarbeiter-E-Mail',
        submitLabel: 'Open Queue Workspace',
        submitLabelDe: 'Queue-Arbeitsbereich öffnen',
        failureMessage: 'Use the staff login only with a staff account.',
        failureMessageDe:
            'Bitte verwenden Sie den Mitarbeiter-Login nur mit einem Staff-Konto.',
        heroVisualKey: 'about',
      ),
      successRoute: '/staff',
      icon: Icons.support_agent_rounded,
      initialLanguageCode: initialLanguageCode,
      initialEmail: initialEmail,
    );
  }
}
