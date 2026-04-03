library;

import 'package:flutter/material.dart';

import '../../core/i18n/app_language.dart';
import '../../theme/app_theme.dart';

class AppLanguageToggle extends StatelessWidget {
  const AppLanguageToggle({
    super.key,
    required this.language,
    required this.onChanged,
    this.dark = false,
    this.compact = false,
  });

  final AppLanguage language;
  final ValueChanged<AppLanguage> onChanged;
  final bool dark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final shellColor = dark ? AppTheme.darkSurfaceMuted : AppTheme.accentSoft;
    final borderColor = dark
        ? AppTheme.darkBorder
        : AppTheme.border.withValues(alpha: 0.84);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: shellColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 4,
          vertical: compact ? 1 : 4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _LanguageChip(
              label: 'EN',
              isSelected: language == AppLanguage.english,
              dark: dark,
              compact: compact,
              onTap: () => onChanged(AppLanguage.english),
            ),
            SizedBox(width: compact ? 2 : 4),
            _LanguageChip(
              label: 'DE',
              isSelected: language == AppLanguage.german,
              dark: dark,
              compact: compact,
              onTap: () => onChanged(AppLanguage.german),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.label,
    required this.isSelected,
    required this.dark,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool dark;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedForeground = dark ? AppTheme.darkAccent : AppTheme.ink;
    final unselectedForeground = dark
        ? AppTheme.darkTextMuted
        : AppTheme.textMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? (dark ? AppTheme.darkSurface : AppTheme.shell)
              : Colors.transparent,
          border: isSelected
              ? Border.all(
                  color: dark
                      ? AppTheme.darkBorderStrong
                      : AppTheme.border.withValues(alpha: 0.92),
                )
              : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: compact ? 12 : null,
            color: isSelected ? selectedForeground : unselectedForeground,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
