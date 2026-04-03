/// WHAT: Renders a compact online/offline presence indicator for chats and workspace headers.
/// WHY: Customer and staff chat surfaces need one consistent way to show live availability.
/// HOW: Pair a colored status dot with a rounded label and light/dark surface variants.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class PresenceChip extends StatelessWidget {
  const PresenceChip({
    super.key,
    required this.label,
    required this.isOnline,
    this.dark = false,
    this.compact = false,
  });

  final String label;
  final bool isOnline;
  final bool dark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = dark
        ? AppTheme.darkSurfaceMuted
        : isOnline
        ? AppTheme.successSurface
        : AppTheme.shellMuted;
    final borderColor = dark
        ? AppTheme.darkBorder
        : isOnline
        ? AppTheme.pine.withValues(alpha: 0.34)
        : AppTheme.border.withValues(alpha: 0.74);
    final foregroundColor = dark ? AppTheme.darkText : AppTheme.ink;
    final dotColor = isOnline
        ? AppTheme.pine
        : dark
        ? AppTheme.darkTextSoft
        : AppTheme.textMuted;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
              child: SizedBox(width: compact ? 6 : 8, height: compact ? 6 : 8),
            ),
            SizedBox(width: compact ? 6 : 8),
            Text(
              label,
              style:
                  (compact
                          ? Theme.of(context).textTheme.labelSmall
                          : Theme.of(context).textTheme.labelMedium)
                      ?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w700,
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
