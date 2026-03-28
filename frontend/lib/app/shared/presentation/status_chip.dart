/// WHAT: Renders a small, role-agnostic badge for request statuses.
/// WHY: Status labels appear in multiple dashboards and should stay visually consistent.
/// HOW: Map known backend statuses to accessible colors and display them inside a chip.
library;

import 'package:flutter/material.dart';

import '../../core/models/service_request_model.dart';
import '../../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = switch (status) {
      'submitted' => (background: AppTheme.clay, foreground: AppTheme.ink),
      'under_review' => (
        background: const Color(0xFFFFF0C9),
        foreground: AppTheme.ink,
      ),
      'assigned' => (
        background: const Color(0xFFD7E7FF),
        foreground: AppTheme.cobalt,
      ),
      'quoted' => (
        background: const Color(0xFFFFE2C8),
        foreground: AppTheme.ember,
      ),
      'appointment_confirmed' => (
        background: const Color(0xFFD8F2E8),
        foreground: AppTheme.pine,
      ),
      'pending_start' => (
        background: const Color(0xFFE9E1FF),
        foreground: const Color(0xFF5E41A8),
      ),
      'project_started' => (
        background: const Color(0xFFD9F4FF),
        foreground: const Color(0xFF15607A),
      ),
      'work_done' => (
        background: const Color(0xFFDDF7E4),
        foreground: const Color(0xFF2F7C3E),
      ),
      'closed' => (
        background: const Color(0xFFE7E7E7),
        foreground: AppTheme.ink,
      ),
      _ => (background: AppTheme.clay, foreground: AppTheme.ink),
    };

    return Chip(
      label: Text(requestStatusLabelFor(status)),
      backgroundColor: colors.background,
      labelStyle:
          (compact
                  ? Theme.of(context).textTheme.labelSmall
                  : Theme.of(context).textTheme.bodySmall)
              ?.copyWith(color: colors.foreground, fontWeight: FontWeight.w700),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 8,
        vertical: compact ? 0 : 2,
      ),
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      materialTapTargetSize: compact
          ? MaterialTapTargetSize.shrinkWrap
          : MaterialTapTargetSize.padded,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}
