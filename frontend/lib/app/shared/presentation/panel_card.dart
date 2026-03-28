/// WHAT: Provides a reusable elevated content panel for cards, forms, and dashboard sections.
/// WHY: Shared card structure keeps the app consistent across public, customer, admin, and staff surfaces.
/// HOW: Wrap arbitrary child content in a padded Material card with optional heading copy.
library;

import 'package:flutter/material.dart';

class PanelCard extends StatelessWidget {
  const PanelCard({super.key, required this.child, this.title, this.subtitle});

  final Widget child;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final cardPadding = isCompact ? 18.0 : 24.0;
    final sectionSpacing = isCompact ? 16.0 : 20.0;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null) ...<Widget>[
              Text(title!, style: theme.textTheme.titleLarge),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(subtitle!, style: theme.textTheme.bodyMedium),
              ],
              SizedBox(height: sectionSpacing),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
