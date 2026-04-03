/// WHAT: Renders a small, role-agnostic badge for request statuses.
/// WHY: Status labels appear in multiple dashboards and should stay visually consistent.
/// HOW: Map known backend statuses to accessible colors and display them inside a chip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/app_language.dart';
import '../../core/models/service_request_model.dart';
import '../../theme/app_theme.dart';

class StatusChip extends ConsumerWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.compact = false,
    this.labelOverride,
  });

  final String status;
  final bool compact;
  final String? labelOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final tone = AppTheme.statusTone(status);

    return Chip(
      label: Text(
        labelOverride ?? requestStatusLabelFor(status, language: language),
      ),
      backgroundColor: tone.background,
      side: BorderSide(
        color: (tone.border ?? tone.background).withValues(alpha: 0.96),
      ),
      labelStyle:
          (compact
                  ? Theme.of(context).textTheme.labelSmall
                  : Theme.of(context).textTheme.bodySmall)
              ?.copyWith(color: tone.foreground, fontWeight: FontWeight.w700),
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
