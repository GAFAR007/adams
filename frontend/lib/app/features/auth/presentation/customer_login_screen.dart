/// WHAT: Renders the customer login using the shared role-aware login experience.
/// WHY: Customers should get the same polished login structure while still routing into their request inbox only.
/// HOW: Configure the shared role login screen with customer-specific copy, routing, and the register action.
library;

import 'package:flutter/material.dart';

import 'role_login_screen.dart';

class CustomerLoginScreen extends StatelessWidget {
  const CustomerLoginScreen({super.key, this.initialLanguageCode});

  final String? initialLanguageCode;

  @override
  Widget build(BuildContext context) {
    return RoleLoginScreen(
      role: 'customer',
      copy: const RoleLoginCopy(
        pageTitle: 'Customer Login',
        pageTitleDe: 'Kunden-Login',
        eyebrow: 'Customer access',
        eyebrowDe: 'Kundenzugang',
        headerTitle: 'Sign in to your service space',
        headerTitleDe: 'Melden Sie sich in Ihrem Servicebereich an',
        headerSubtitle:
            'Track your requests, see who picked up your queue, and continue the conversation in one place.',
        headerSubtitleDe:
            'Verfolgen Sie Ihre Anfragen, sehen Sie die Übernahme durch das Team und führen Sie die Unterhaltung an einem Ort weiter.',
        emailLabel: 'Email',
        emailLabelDe: 'E-Mail',
        submitLabel: 'Enter Request Inbox',
        submitLabelDe: 'Zum Anfrage-Postfach',
        failureMessage: 'Use the customer login for customer accounts only.',
        failureMessageDe:
            'Bitte verwenden Sie den Kunden-Login nur mit einem Kundenkonto.',
        heroVisualKey: 'services',
        footerLabel: 'Need a first booking? Start service chat',
        footerLabelDe: 'Noch keine Buchung? Service-Chat starten',
        footerRoute: '/book-service',
      ),
      successRoute: '/app/requests',
      icon: Icons.home_work_rounded,
      initialLanguageCode: initialLanguageCode,
    );
  }
}
