library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_language.dart';
import '../../../theme/app_theme.dart';
import '../data/public_repository.dart';
import 'public_site_shell.dart';
import 'public_visuals.dart';

class PublicServicesScreen extends ConsumerStatefulWidget {
  const PublicServicesScreen({super.key, this.initialLanguageCode});

  final String? initialLanguageCode;

  @override
  ConsumerState<PublicServicesScreen> createState() =>
      _PublicServicesScreenState();
}

class _PublicServicesScreenState extends ConsumerState<PublicServicesScreen> {
  late PublicSiteLanguage _language;

  @override
  void initState() {
    super.initState();
    final initialCode = widget.initialLanguageCode;
    _language = initialCode == null || initialCode.trim().isEmpty
        ? ref.read(appLanguageProvider)
        : publicSiteLanguageFromCode(initialCode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(appLanguageProvider.notifier).setLanguage(_language);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(publicCompanyProfileProvider);

    return profileAsync.when(
      data: (profile) {
        final isGerman = _language == PublicSiteLanguage.german;
        final title = resolvePublicText(profile.servicesTitle, _language);
        final subtitle = isGerman
            ? 'Jede Leistung hat jetzt ihre eigene Seite mit klarerem Fokus.'
            : 'Each service now has its own page with a clearer focus.';
        final languageCode = publicSiteLanguageCode(_language);
        final pageVisual = publicPageVisualForKey('services');

        return PublicSiteShell(
          profile: profile,
          language: _language,
          onLanguageChanged: (language) {
            setState(() => _language = language);
            ref.read(appLanguageProvider.notifier).setLanguage(language);
          },
          activeItem: PublicNavItem.services,
          eyebrow: resolvePublicText(profile.category, _language),
          pageTitle: title,
          pageSubtitle: subtitle,
          heroVisual: PublicImageCard(
            imageUrl: pageVisual.imageUrl,
            eyebrow: resolvePublicText(pageVisual.kicker, _language),
            title: title,
            subtitle: resolvePublicText(pageVisual.supportingLine, _language),
            footer: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                PublicTagChip(
                  text: resolvePublicText(profile.serviceAreaText, _language),
                  icon: Icons.place_rounded,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  foregroundColor: Colors.white,
                ),
                PublicTagChip(
                  text: resolvePublicText(
                    profile.contact.hoursLabel,
                    _language,
                  ),
                  icon: Icons.schedule_rounded,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  foregroundColor: Colors.white,
                ),
              ],
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final cardWidth = wide
                  ? (constraints.maxWidth - 20) / 2
                  : double.infinity;

              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: profile.serviceLabels
                    .asMap()
                    .entries
                    .map((entry) {
                      final service = entry.value;
                      final visual = publicServiceVisualForKey(service.key);

                      return PublicReveal(
                        delay: Duration(milliseconds: 60 + (entry.key * 80)),
                        child: SizedBox(
                          width: cardWidth,
                          child: PublicServiceFeatureCard(
                            heroTag: publicServiceHeroTag(service.key),
                            imageUrl: visual.imageUrl,
                            icon: visual.icon,
                            eyebrow: visual.eyebrow.resolve(languageCode),
                            title: resolvePublicText(service.label, _language),
                            summary: visual.summary.resolve(languageCode),
                            highlights: visual.highlights
                                .map((item) => item.resolve(languageCode))
                                .toList(growable: false),
                            metrics: visual.metrics
                                .map((item) => item.resolve(languageCode))
                                .toList(growable: false),
                            actionLabel: isGerman
                                ? 'Leistung ansehen'
                                : 'View service',
                            onTap: () {
                              final path = languageCode == 'de'
                                  ? '/services/${service.key}?lang=de'
                                  : '/services/${service.key}';
                              context.go(path);
                            },
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              );
            },
          ),
        );
      },
      loading: () => const _PublicPageLoadingScaffold(),
      error: (error, stackTrace) => const _PublicPageErrorScaffold(),
    );
  }
}

class _PublicPageLoadingScaffold extends StatelessWidget {
  const _PublicPageLoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.ink,
      body: Center(child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

class _PublicPageErrorScaffold extends StatelessWidget {
  const _PublicPageErrorScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Unable to load page')));
  }
}
