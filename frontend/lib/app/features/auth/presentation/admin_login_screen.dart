/// WHAT: Renders the admin login using the shared role-aware login experience.
/// WHY: Admin access should keep the same polished structure as other roles while still routing into operations tools.
/// HOW: Configure the shared role login screen with the admin role contract and dashboard route.
library;

import 'package:flutter/material.dart';

import 'role_login_screen.dart';

class AdminLoginScreen extends StatelessWidget {
  const AdminLoginScreen({super.key, this.initialLanguageCode});

  final String? initialLanguageCode;

  @override
  Widget build(BuildContext context) {
    return RoleLoginScreen(
      role: 'admin',
      copy: const RoleLoginCopy(
        pageTitle: 'Admin Login',
        pageTitleDe: 'Admin-Login',
        eyebrow: 'Operations access',
        eyebrowDe: 'Operations-Zugang',
        headerTitle: 'Sign in to your operations space',
        headerTitleDe: 'Melden Sie sich in Ihrem Operations-Bereich an',
        headerSubtitle:
            'Manage the request queue, staff load, invites, and handoff performance.',
        headerSubtitleDe:
            'Steuern Sie Queue, Team-Auslastung, Einladungen und Übergaben an einem Ort.',
        emailLabel: 'Admin email',
        emailLabelDe: 'Admin-E-Mail',
        submitLabel: 'Enter Dashboard',
        submitLabelDe: 'Zum Dashboard',
        failureMessage: 'Use an admin account for this dashboard.',
        failureMessageDe:
            'Bitte verwenden Sie für dieses Dashboard ein Admin-Konto.',
        heroVisualKey: 'legal',
      ),
      successRoute: '/admin',
      icon: Icons.admin_panel_settings_rounded,
      initialLanguageCode: initialLanguageCode,
    );
  }
}
