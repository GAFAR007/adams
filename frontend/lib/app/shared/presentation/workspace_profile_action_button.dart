library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class WorkspaceCircularActionButton extends StatelessWidget {
  const WorkspaceCircularActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.dark = false,
    this.diameter = 28,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;
  final bool dark;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = dark
        ? AppTheme.darkSurfaceMuted
        : AppTheme.accentSoft;
    final borderColor = dark
        ? AppTheme.darkBorder
        : AppTheme.border.withValues(alpha: 0.84);

    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: diameter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onPressed,
            tooltip: tooltip,
            icon: child,
          ),
        ),
      ),
    );
  }
}

class WorkspaceProfileActionButton extends StatelessWidget {
  const WorkspaceProfileActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.displayName,
    this.dark = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final String displayName;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = dark ? AppTheme.darkAccent : theme.colorScheme.primary;
    final initials = getInitials(displayName);

    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 28,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
          tooltip: tooltip,
          icon: CircleAvatar(
            radius: 14,
            backgroundColor: primaryColor.withValues(alpha: 0.15),
            child: Text(
              initials,
              style: theme.textTheme.labelSmall?.copyWith(
                color: primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WorkspaceIconActionButton extends StatelessWidget {
  const WorkspaceIconActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.dark = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = dark ? AppTheme.darkText : AppTheme.ink;

    return WorkspaceCircularActionButton(
      tooltip: tooltip,
      onPressed: onPressed,
      dark: dark,
      child: Icon(icon, size: 18, color: foregroundColor),
    );
  }
}

class WorkspaceCalendarActionButton extends StatelessWidget {
  const WorkspaceCalendarActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.dark = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return WorkspaceIconActionButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icons.calendar_month_rounded,
      dark: dark,
    );
  }
}

class WorkspaceLogoutActionButton extends StatelessWidget {
  const WorkspaceLogoutActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    this.dark = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return WorkspaceIconActionButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icons.logout_rounded,
      dark: dark,
    );
  }
}

String getInitials(String name) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    return 'U';
  }

  final parts = trimmedName.split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return parts.first[0].toUpperCase();
  }

  return (parts.first[0] + parts.last[0]).toUpperCase();
}
