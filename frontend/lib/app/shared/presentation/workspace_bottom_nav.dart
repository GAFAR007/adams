/// WHAT: Renders a compact workspace bottom navigation bar for role-specific dashboards.
/// WHY: Admin and staff screens need a clearer, chat-app-style way to move between major sections without stacking everything at once.
/// HOW: Accept typed nav items, highlight the active section, and optionally show small count badges inside a rounded floating bar.
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class WorkspaceBottomNavItem {
  const WorkspaceBottomNavItem({
    required this.label,
    required this.icon,
    this.badgeText,
    this.badgeBackgroundColor,
    this.badgeForegroundColor,
  });

  final String label;
  final IconData icon;
  final String? badgeText;
  final Color? badgeBackgroundColor;
  final Color? badgeForegroundColor;
}

class WorkspaceBottomNav extends StatelessWidget {
  const WorkspaceBottomNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onTap,
    this.dark = false,
    this.compact = false,
  });

  final List<WorkspaceBottomNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final bool dark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 16,
          0,
          compact ? 10 : 16,
          compact ? 10 : 16,
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final isCompact = compact || constraints.maxWidth < 460;
            final surfaceColor = dark ? AppTheme.darkSurface : AppTheme.shell;
            final borderColor = dark
                ? AppTheme.darkBorder
                : AppTheme.border.withValues(alpha: 0.78);

            final navDecoration = BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(isCompact ? 24 : 28),
              border: Border.all(color: borderColor),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: dark
                      ? Colors.black.withValues(alpha: 0.24)
                      : AppTheme.ink.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            );

            return DecoratedBox(
              decoration: navDecoration,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 5 : 10,
                  vertical: isCompact ? 5 : 10,
                ),
                child: Row(
                  children: List<Widget>.generate(items.length, (int index) {
                    final item = items[index];
                    final isSelected = index == selectedIndex;
                    final badgeText = item.badgeText;
                    final showBadge =
                        badgeText != null &&
                        badgeText.isNotEmpty &&
                        badgeText != '0';
                    final badgeBackgroundColor = item.badgeBackgroundColor;
                    final badgeForegroundColor = item.badgeForegroundColor;
                    final foregroundColor = isSelected
                        ? (dark ? AppTheme.darkAccent : Colors.white)
                        : dark
                        ? AppTheme.darkTextMuted
                        : AppTheme.textMuted;

                    return Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(
                          isCompact ? 18 : 20,
                        ),
                        onTap: () => onTap(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: EdgeInsets.symmetric(
                            horizontal: isCompact ? 6 : 10,
                            vertical: isCompact ? 7 : 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (dark
                                      ? AppTheme.darkAccentSurface
                                      : AppTheme.cobalt)
                                : Colors.transparent,
                            border: isSelected && dark
                                ? Border.all(color: AppTheme.darkBorderStrong)
                                : null,
                            borderRadius: BorderRadius.circular(
                              isCompact ? 18 : 20,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Stack(
                                clipBehavior: Clip.none,
                                children: <Widget>[
                                  Icon(
                                    item.icon,
                                    size: isCompact ? 19 : 23,
                                    color: foregroundColor,
                                  ),
                                  if (showBadge)
                                    Positioned(
                                      top: -5,
                                      right: -12,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color:
                                              badgeBackgroundColor ??
                                              (isSelected
                                                  ? (dark
                                                        ? AppTheme.darkAccent
                                                              .withValues(
                                                                alpha: 0.18,
                                                              )
                                                        : Colors.white
                                                              .withValues(
                                                                alpha: 0.2,
                                                              ))
                                                  : dark
                                                  ? AppTheme.darkSurfaceMuted
                                                  : AppTheme.shellMuted),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1,
                                          ),
                                          child: Text(
                                            badgeText,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color:
                                                      badgeForegroundColor ??
                                                      (isSelected
                                                          ? (dark
                                                                ? AppTheme
                                                                      .darkAccent
                                                                : Colors.white)
                                                          : dark
                                                          ? AppTheme.darkText
                                                          : AppTheme.ink),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              SizedBox(height: isCompact ? 4 : 6),
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      fontSize: isCompact ? 11 : null,
                                      color: foregroundColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
