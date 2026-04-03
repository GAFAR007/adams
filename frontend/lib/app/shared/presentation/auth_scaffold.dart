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
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              AppTheme.darkPage,
              AppTheme.darkSurfaceRaised,
              AppTheme.sand,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: <double>[0, 0.52, 1],
          ),
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -120,
              left: -80,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.darkAccent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 260, height: 260),
              ),
            ),
            Positioned(
              right: -80,
              bottom: -90,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.mist.withValues(alpha: 0.42),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 240, height: 240),
              ),
            ),
            SafeArea(
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
          ],
        ),
      ),
    );
  }
}
