library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/public_company_profile.dart';
import '../../../theme/app_theme.dart';

enum PublicSiteLanguage { english, german }

enum PublicNavItem { home, about, services, legal, contact }

PublicSiteLanguage publicSiteLanguageFromCode(String? code) {
  return code == 'de' ? PublicSiteLanguage.german : PublicSiteLanguage.english;
}

String publicSiteLanguageCode(PublicSiteLanguage language) {
  return language == PublicSiteLanguage.german ? 'de' : 'en';
}

String resolvePublicText(LocalizedText value, PublicSiteLanguage language) {
  return value.resolve(publicSiteLanguageCode(language));
}

Color publicColorFromHex(String value, Color fallback) {
  final normalized = value.trim().replaceFirst('#', '');
  if (normalized.isEmpty) {
    return fallback;
  }

  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) {
    return fallback;
  }

  return Color(parsed);
}

class PublicSiteShell extends StatelessWidget {
  const PublicSiteShell({
    super.key,
    required this.profile,
    required this.language,
    required this.onLanguageChanged,
    required this.activeItem,
    required this.pageTitle,
    required this.pageSubtitle,
    required this.body,
    this.eyebrow,
    this.heroVisual,
    this.heroActions,
    this.heroDetails,
  });

  final PublicCompanyProfileModel profile;
  final PublicSiteLanguage language;
  final ValueChanged<PublicSiteLanguage> onLanguageChanged;
  final PublicNavItem activeItem;
  final String pageTitle;
  final String pageSubtitle;
  final String? eyebrow;
  final Widget body;
  final Widget? heroVisual;
  final Widget? heroActions;
  final Widget? heroDetails;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 800;
    final primaryColor = publicColorFromHex(
      profile.primaryColorHex,
      AppTheme.cobalt,
    );
    final accentColor = publicColorFromHex(
      profile.accentColorHex,
      AppTheme.ember,
    );
    final copy = _PublicSiteCopy(language);

    return Scaffold(
      backgroundColor: AppTheme.sand,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color.lerp(primaryColor, AppTheme.ink, 0.32)!,
              Color.lerp(AppTheme.sand, Colors.white, 0.06)!,
              AppTheme.sand,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const <double>[0, 0.38, 1],
          ),
        ),
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 24, 24, isCompact ? 40 : 52),
                  child: Column(
                    children: <Widget>[
                      PublicReveal(
                        delay: const Duration(milliseconds: 40),
                        child: _PublicUtilityBar(
                          quoteLabel: copy.utilityQuoteLabel,
                          availabilityLabel: copy.utilityAvailabilityLabel,
                          language: language,
                          onLanguageChanged: onLanguageChanged,
                          isCompact: isCompact,
                        ),
                      ),
                      const SizedBox(height: 14),
                      PublicReveal(
                        delay: const Duration(milliseconds: 110),
                        child: _PublicMainNav(
                          profile: profile,
                          language: language,
                          activeItem: activeItem,
                          copy: copy,
                          isCompact: isCompact,
                        ),
                      ),
                      const SizedBox(height: 26),
                      PublicReveal(
                        delay: const Duration(milliseconds: 180),
                        child: _PublicPageHero(
                          eyebrow: eyebrow,
                          title: pageTitle,
                          subtitle: pageSubtitle,
                          primaryColor: primaryColor,
                          accentColor: accentColor,
                          isCompact: isCompact,
                          heroVisual: heroVisual,
                          heroActions: heroActions,
                          heroDetails: heroDetails,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -18),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: PublicReveal(
                    delay: const Duration(milliseconds: 240),
                    beginOffset: const Offset(0, 0.04),
                    child: body,
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

class _PublicUtilityBar extends StatelessWidget {
  const _PublicUtilityBar({
    required this.quoteLabel,
    required this.availabilityLabel,
    required this.language,
    required this.onLanguageChanged,
    required this.isCompact,
  });

  final String quoteLabel;
  final String availabilityLabel;
  final PublicSiteLanguage language;
  final ValueChanged<PublicSiteLanguage> onLanguageChanged;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final items = Wrap(
      spacing: 18,
      runSpacing: 10,
      children: <Widget>[
        _UtilityItem(icon: Icons.local_offer_rounded, text: quoteLabel),
        _UtilityItem(icon: Icons.schedule_rounded, text: availabilityLabel),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 18,
        vertical: isCompact ? 14 : 12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.cobalt.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                items,
                const SizedBox(height: 12),
                _PublicLanguageToggle(
                  language: language,
                  onChanged: onLanguageChanged,
                ),
              ],
            )
          : Row(
              children: <Widget>[
                Expanded(child: items),
                _PublicLanguageToggle(
                  language: language,
                  onChanged: onLanguageChanged,
                ),
              ],
            ),
    );
  }
}

class _UtilityItem extends StatelessWidget {
  const _UtilityItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: Colors.white),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PublicLanguageToggle extends StatelessWidget {
  const _PublicLanguageToggle({
    required this.language,
    required this.onChanged,
  });

  final PublicSiteLanguage language;
  final ValueChanged<PublicSiteLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _PublicLanguageChip(
              label: 'EN',
              isSelected: language == PublicSiteLanguage.english,
              onTap: () => onChanged(PublicSiteLanguage.english),
            ),
            const SizedBox(width: 4),
            _PublicLanguageChip(
              label: 'DE',
              isSelected: language == PublicSiteLanguage.german,
              onTap: () => onChanged(PublicSiteLanguage.german),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublicLanguageChip extends StatelessWidget {
  const _PublicLanguageChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: isSelected ? AppTheme.ink : Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PublicMainNav extends StatelessWidget {
  const _PublicMainNav({
    required this.profile,
    required this.language,
    required this.activeItem,
    required this.copy,
    required this.isCompact,
  });

  final PublicCompanyProfileModel profile;
  final PublicSiteLanguage language;
  final PublicNavItem activeItem;
  final _PublicSiteCopy copy;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: isCompact ? 52 : 56,
          height: isCompact ? 52 : 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Color.lerp(AppTheme.cobalt, AppTheme.ink, 0.12)!,
                Color.lerp(AppTheme.cobalt, Colors.white, 0.28)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppTheme.cobalt.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.cleaning_services_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            profile.companyName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w700,
              fontSize: isCompact ? 18 : 20,
              letterSpacing: -0.4,
            ),
          ),
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 18,
        vertical: isCompact ? 14 : 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: brand),
                    const SizedBox(width: 12),
                    _PublicCompactMenu(
                      copy: copy,
                      language: language,
                      profile: profile,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _PublicAdminEntryButton(
                    label: resolvePublicText(profile.adminLoginLabel, language),
                    onPressed: () => context.go('/admin/login'),
                  ),
                ),
              ],
            )
          : Row(
              children: <Widget>[
                Flexible(
                  flex: 5,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: brand,
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  flex: 7,
                  child: Center(
                    child: _DesktopPublicNavGroup(
                      profile: profile,
                      language: language,
                      activeItem: activeItem,
                      copy: copy,
                    ),
                  ),
                ),
                const SizedBox(width: 22),
                _PublicAdminEntryButton(
                  label: resolvePublicText(profile.adminLoginLabel, language),
                  onPressed: () => context.go('/admin/login'),
                ),
              ],
            ),
    );
  }
}

class _DesktopPublicNavGroup extends StatelessWidget {
  const _DesktopPublicNavGroup({
    required this.profile,
    required this.language,
    required this.activeItem,
    required this.copy,
  });

  final PublicCompanyProfileModel profile;
  final PublicSiteLanguage language;
  final PublicNavItem activeItem;
  final _PublicSiteCopy copy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Color.lerp(Colors.white, AppTheme.sand, 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8DECF)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: <Widget>[
          _PublicNavButton(
            label: copy.homeLabel,
            isActive: activeItem == PublicNavItem.home,
            onTap: () => _go(context, '/', language),
          ),
          _PublicNavButton(
            label: copy.aboutLabel,
            isActive: activeItem == PublicNavItem.about,
            onTap: () => _go(context, '/about', language),
          ),
          _PublicServicesDropdown(
            label: copy.servicesLabel,
            profile: profile,
            language: language,
            isActive: activeItem == PublicNavItem.services,
          ),
          _PublicNavButton(
            label: copy.legalLabel,
            isActive: activeItem == PublicNavItem.legal,
            onTap: () => _go(context, '/legal', language),
          ),
          _PublicNavButton(
            label: copy.contactLabel,
            isActive: activeItem == PublicNavItem.contact,
            onTap: () => _go(context, '/contact', language),
          ),
        ],
      ),
    );
  }
}

class _PublicCompactMenu extends StatelessWidget {
  const _PublicCompactMenu({
    required this.copy,
    required this.language,
    required this.profile,
  });

  final _PublicSiteCopy copy;
  final PublicSiteLanguage language;
  final PublicCompanyProfileModel profile;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: copy.menuLabel,
      color: const Color(0xFFF8F4EC),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (value) {
        if (value == 'home') {
          _go(context, '/', language);
          return;
        }

        if (value == 'about') {
          _go(context, '/about', language);
          return;
        }

        if (value == 'services') {
          _go(context, '/services', language);
          return;
        }

        if (value == 'legal') {
          _go(context, '/legal', language);
          return;
        }

        if (value == 'contact') {
          _go(context, '/contact', language);
          return;
        }

        if (value.startsWith('service:')) {
          final serviceKey = value.replaceFirst('service:', '');
          _go(context, '/services/$serviceKey', language);
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'home', child: Text(copy.homeLabel)),
        PopupMenuItem<String>(value: 'about', child: Text(copy.aboutLabel)),
        PopupMenuItem<String>(
          value: 'services',
          child: Text(copy.servicesLabel),
        ),
        ...profile.serviceLabels.map(
          (service) => PopupMenuItem<String>(
            value: 'service:${service.key}',
            child: Text(resolvePublicText(service.label, language)),
          ),
        ),
        PopupMenuItem<String>(value: 'legal', child: Text(copy.legalLabel)),
        PopupMenuItem<String>(value: 'contact', child: Text(copy.contactLabel)),
      ],
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.ink,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.menu_rounded, color: Colors.white),
      ),
    );
  }
}

class _PublicNavButton extends StatelessWidget {
  const _PublicNavButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isActive
                ? <BoxShadow>[
                    BoxShadow(
                      color: AppTheme.cobalt.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: isActive ? AppTheme.cobalt : AppTheme.ink,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PublicServicesDropdown extends StatelessWidget {
  const _PublicServicesDropdown({
    required this.label,
    required this.profile,
    required this.language,
    required this.isActive,
  });

  final String label;
  final PublicCompanyProfileModel profile;
  final PublicSiteLanguage language;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isActive
            ? <BoxShadow>[
                BoxShadow(
                  color: AppTheme.cobalt.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _go(context, '/services', language),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isActive ? AppTheme.cobalt : AppTheme.ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: label,
            color: const Color(0xFFF8F4EC),
            surfaceTintColor: Colors.transparent,
            elevation: 14,
            offset: const Offset(0, 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            onSelected: (serviceKey) =>
                _go(context, '/services/$serviceKey', language),
            itemBuilder: (context) => profile.serviceLabels
                .map(
                  (service) => PopupMenuItem<String>(
                    value: service.key,
                    child: Text(resolvePublicText(service.label, language)),
                  ),
                )
                .toList(growable: false),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 14, 12),
              child: AnimatedRotation(
                turns: isActive ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: isActive ? AppTheme.cobalt : AppTheme.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicAdminEntryButton extends StatelessWidget {
  const _PublicAdminEntryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Color.lerp(Colors.white, AppTheme.cobalt, 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.cobalt.withValues(alpha: 0.08)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 16,
                  color: AppTheme.cobalt,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppTheme.cobalt,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppTheme.cobalt,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicPageHero extends StatelessWidget {
  const _PublicPageHero({
    required this.title,
    required this.subtitle,
    required this.primaryColor,
    required this.accentColor,
    required this.isCompact,
    this.eyebrow,
    this.heroVisual,
    this.heroActions,
    this.heroDetails,
  });

  final String? eyebrow;
  final String title;
  final String subtitle;
  final Color primaryColor;
  final Color accentColor;
  final bool isCompact;
  final Widget? heroVisual;
  final Widget? heroActions;
  final Widget? heroDetails;

  @override
  Widget build(BuildContext context) {
    final textContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (eyebrow != null && eyebrow!.trim().isNotEmpty) ...<Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              eyebrow!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          title,
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          width: 120,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: <Color>[accentColor, Colors.white.withValues(alpha: 0.9)],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.84),
              height: 1.55,
            ),
          ),
        ),
        if (heroActions != null) ...<Widget>[
          const SizedBox(height: 24),
          heroActions!,
        ],
        if (heroDetails != null) ...<Widget>[
          const SizedBox(height: 24),
          heroDetails!,
        ],
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 24 : 34),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Color.lerp(primaryColor, AppTheme.ink, 0.18)!,
            Color.lerp(primaryColor, accentColor, 0.16)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(36),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: heroVisual == null
          ? textContent
          : isCompact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                textContent,
                const SizedBox(height: 22),
                heroVisual!,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 11, child: textContent),
                const SizedBox(width: 24),
                Expanded(flex: 8, child: heroVisual!),
              ],
            ),
    );
  }
}

class PublicReveal extends StatefulWidget {
  const PublicReveal({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.beginOffset = const Offset(0, 0.03),
  });

  final Widget child;
  final Duration delay;
  final Offset beginOffset;

  @override
  State<PublicReveal> createState() => _PublicRevealState();
}

class _PublicRevealState extends State<PublicReveal> {
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.delay, () {
      if (!mounted) {
        return;
      }

      setState(() => _isVisible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      opacity: _isVisible ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        offset: _isVisible ? Offset.zero : widget.beginOffset,
        child: widget.child,
      ),
    );
  }
}

class PublicSurfaceCard extends StatelessWidget {
  const PublicSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.title,
    this.subtitle,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: const Color(0xFFE8DECF)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Text(title!, style: Theme.of(context).textTheme.headlineMedium),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ],
            const SizedBox(height: 18),
          ],
          child,
        ],
      ),
    );
  }
}

class PublicTagChip extends StatelessWidget {
  const PublicTagChip({
    super.key,
    required this.text,
    this.icon,
    this.backgroundColor = const Color(0xFFF0E7D8),
    this.foregroundColor = AppTheme.ink,
  });

  final String text;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: foregroundColor),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PublicImageCard extends StatelessWidget {
  const PublicImageCard({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.eyebrow,
    this.title,
    this.subtitle,
    this.footer,
    this.aspectRatio = 16 / 10,
    this.alignment = Alignment.center,
    this.borderRadius = 28,
  });

  final String imageUrl;
  final String? heroTag;
  final String? eyebrow;
  final String? title;
  final String? subtitle;
  final Widget? footer;
  final double aspectRatio;
  final Alignment alignment;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(AppTheme.cobalt, AppTheme.ink, 0.3),
              ),
              child: Image.network(
                imageUrl,
                fit: BoxFit.cover,
                alignment: alignment,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }

                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          AppTheme.cobalt,
                          Color.lerp(AppTheme.cobalt, AppTheme.ink, 0.44)!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.cleaning_services_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      AppTheme.ink.withValues(alpha: 0.06),
                      AppTheme.ink.withValues(alpha: 0.22),
                      AppTheme.ink.withValues(alpha: 0.84),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const <double>[0, 0.45, 1],
                  ),
                ),
              ),
            ),
            if (eyebrow != null ||
                title != null ||
                subtitle != null ||
                footer != null)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      if (eyebrow != null && eyebrow!.isNotEmpty) ...<Widget>[
                        PublicTagChip(
                          text: eyebrow!,
                          backgroundColor: Colors.white.withValues(alpha: 0.14),
                          foregroundColor: Colors.white,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (title != null) ...<Widget>[
                        Text(
                          title!,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (subtitle != null) const SizedBox(height: 8),
                      ],
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                                height: 1.5,
                              ),
                        ),
                      if (footer != null) ...<Widget>[
                        const SizedBox(height: 14),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    if (heroTag == null) {
      return card;
    }

    return Hero(tag: heroTag!, child: card);
  }
}

class PublicServiceFeatureCard extends StatelessWidget {
  const PublicServiceFeatureCard({
    super.key,
    required this.heroTag,
    required this.imageUrl,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.summary,
    required this.highlights,
    required this.metrics,
    required this.actionLabel,
    required this.onTap,
  });

  final String heroTag;
  final String imageUrl;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String summary;
  final List<String> highlights;
  final List<String> metrics;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final isCompact = constraints.maxWidth < 420;
        final imageAspectRatio = isCompact ? 16 / 8.8 : 16 / 10;
        final iconBoxSize = isCompact ? 40.0 : 44.0;
        final iconRadius = isCompact ? 14.0 : 16.0;
        final horizontalGap = isCompact ? 10.0 : 12.0;
        final topGap = isCompact ? 14.0 : 18.0;
        final contentGap = isCompact ? 14.0 : 16.0;
        final chipGap = isCompact ? 8.0 : 10.0;
        final buttonGap = isCompact ? 14.0 : 18.0;
        final summaryStyle =
            (isCompact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)
                ?.copyWith(
                  color: AppTheme.ink,
                  height: isCompact ? 1.48 : 1.55,
                );

        Widget buildMetricChip(String metric) {
          if (!isCompact) {
            return PublicTagChip(
              text: metric,
              backgroundColor: AppTheme.cobalt.withValues(alpha: 0.08),
              foregroundColor: AppTheme.cobalt,
            );
          }

          return DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.cobalt.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Text(
                metric,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppTheme.cobalt,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }

        return PublicSurfaceCard(
          padding: EdgeInsets.all(isCompact ? 20 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PublicImageCard(
                heroTag: heroTag,
                imageUrl: imageUrl,
                aspectRatio: imageAspectRatio,
                eyebrow: eyebrow,
                title: title,
              ),
              SizedBox(height: topGap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: iconBoxSize,
                    height: iconBoxSize,
                    decoration: BoxDecoration(
                      color: AppTheme.cobalt.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(iconRadius),
                    ),
                    child: Icon(
                      icon,
                      size: isCompact ? 20 : 24,
                      color: AppTheme.cobalt,
                    ),
                  ),
                  SizedBox(width: horizontalGap),
                  Expanded(child: Text(summary, style: summaryStyle)),
                ],
              ),
              SizedBox(height: contentGap),
              PublicBulletList(items: highlights),
              SizedBox(height: isCompact ? 4 : 6),
              Wrap(
                spacing: chipGap,
                runSpacing: chipGap,
                children: metrics.map(buildMetricChip).toList(growable: false),
              ),
              SizedBox(height: buttonGap),
              SizedBox(
                width: isCompact ? double.infinity : null,
                child: FilledButton.icon(
                  onPressed: onTap,
                  style: isCompact
                      ? FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        )
                      : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(actionLabel),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class PublicInfoRowData {
  const PublicInfoRowData({
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;
}

class PublicInfoList extends StatelessWidget {
  const PublicInfoList({super.key, required this.rows});

  final List<PublicInfoRowData> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: rows
          .asMap()
          .entries
          .map(
            (entry) => Padding(
              padding: EdgeInsets.only(
                bottom: entry.key == rows.length - 1 ? 0 : 14,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F5EE),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE8DDCE)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (entry.value.icon != null) ...<Widget>[
                        Icon(
                          entry.value.icon,
                          size: 18,
                          color: AppTheme.cobalt,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              entry.value.label,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: AppTheme.cobalt,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              entry.value.value,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppTheme.ink,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class PublicBulletList extends StatelessWidget {
  const PublicBulletList({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: AppTheme.pine,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.55,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

void _go(BuildContext context, String path, PublicSiteLanguage language) {
  final code = publicSiteLanguageCode(language);
  final destination = code == 'de' ? '$path?lang=de' : path;
  context.go(destination);
}

class _PublicSiteCopy {
  const _PublicSiteCopy(this.language);

  final PublicSiteLanguage language;

  String get utilityQuoteLabel => language == PublicSiteLanguage.german
      ? 'Kostenlose Anfrage und schnelle Antwort'
      : 'Free quote and fast response';

  String get utilityAvailabilityLabel => language == PublicSiteLanguage.german
      ? '24 Stunden am Tag erreichbar'
      : 'Available 24 hours a day';

  String get homeLabel =>
      language == PublicSiteLanguage.german ? 'Start' : 'Home';

  String get aboutLabel =>
      language == PublicSiteLanguage.german ? 'Über uns' : 'About us';

  String get servicesLabel =>
      language == PublicSiteLanguage.german ? 'Leistungen' : 'Services';

  String get legalLabel =>
      language == PublicSiteLanguage.german ? 'Rechtliches' : 'Legal';

  String get contactLabel =>
      language == PublicSiteLanguage.german ? 'Kontakt' : 'Contact';

  String get menuLabel =>
      language == PublicSiteLanguage.german ? 'Menü' : 'Menu';
}
