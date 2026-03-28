/// WHAT: Renders a small, role-agnostic badge for request statuses.
/// WHY: Status labels appear in multiple dashboards and should stay visually consistent.
/// HOW: Map known backend statuses to accessible colors and display them inside a chip.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
  });

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = switch (status) {
      'submitted' => (background: AppTheme.clay, foreground: AppTheme.ink),
      'under_review' => (background: const Color(0xFFFFF0C9), foreground: AppTheme.ink),
      'assigned' => (background: const Color(0xFFD7E7FF), foreground: AppTheme.cobalt),
      'quoted' => (background: const Color(0xFFFFE2C8), foreground: AppTheme.ember),
      'appointment_confirmed' => (background: const Color(0xFFD8F2E8), foreground: AppTheme.pine),
      'closed' => (background: const Color(0xFFE7E7E7), foreground: AppTheme.ink),
      _ => (background: AppTheme.clay, foreground: AppTheme.ink),
    };

    return Chip(
      label: Text(status.replaceAll('_', ' ')),
      backgroundColor: colors.background,
      labelStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w700,
          ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}
