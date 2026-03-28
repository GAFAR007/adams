/// WHAT: Provides a centered, reusable auth layout for login and registration screens.
/// WHY: Customer, admin, and staff auth flows should share a consistent framing without repeated scaffolding.
/// HOW: Place the given child inside a responsive card with title, subtitle, and a clean background.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'panel_card.dart';

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[AppTheme.ink, AppTheme.cobalt, AppTheme.sand],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: PanelCard(
                  title: title,
                  subtitle: subtitle,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
