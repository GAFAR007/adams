library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/public_company_profile.dart';
import '../../../theme/app_theme.dart';
import '../data/public_repository.dart';
import 'public_site_shell.dart';
import 'public_visuals.dart';

class PublicServiceDetailScreen extends ConsumerStatefulWidget {
  const PublicServiceDetailScreen({
    super.key,
    required this.serviceKey,
    this.initialLanguageCode,
  });

  final String serviceKey;
  final String? initialLanguageCode;

  @override
  ConsumerState<PublicServiceDetailScreen> createState() =>
      _PublicServiceDetailScreenState();
}

class _PublicServiceDetailScreenState
    extends ConsumerState<PublicServiceDetailScreen> {
  late PublicSiteLanguage _language;

  @override
  void initState() {
    super.initState();
    _language = publicSiteLanguageFromCode(widget.initialLanguageCode);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(publicCompanyProfileProvider);

    return profileAsync.when(
      data: (profile) {
        PublicServiceItem? service;
        for (final item in profile.serviceLabels) {
          if (item.key == widget.serviceKey) {
            service = item;
            break;
          }
        }

        if (service == null) {
          return const _PublicPageErrorScaffold(message: 'Service not found');
        }

        final isGerman = _language == PublicSiteLanguage.german;
        final languageCode = publicSiteLanguageCode(_language);
        final serviceName = resolvePublicText(service.label, _language);
        final visual = publicServiceVisualForKey(service.key);
        final title = serviceName;
        final subtitle = visual.summary.resolve(languageCode);
        final servicesPath = languageCode == 'de'
            ? '/services?lang=de'
            : '/services';
        final bookingPath = languageCode == 'de'
            ? '/book-service?lang=de&service=${service.key}'
            : '/book-service?service=${service.key}';

        return PublicSiteShell(
          profile: profile,
          language: _language,
          onLanguageChanged: (language) {
            setState(() => _language = language);
          },
          activeItem: PublicNavItem.services,
          eyebrow: resolvePublicText(profile.category, _language),
          pageTitle: title,
          pageSubtitle: subtitle,
          heroVisual: PublicImageCard(
            heroTag: publicServiceHeroTag(service.key),
            imageUrl: visual.imageUrl,
            eyebrow: visual.eyebrow.resolve(languageCode),
            title: serviceName,
            subtitle: subtitle,
            footer: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: visual.metrics
                  .map(
                    (metric) => PublicTagChip(
                      text: metric.resolve(languageCode),
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      foregroundColor: Colors.white,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final overviewCard = PublicSurfaceCard(
                title: isGerman ? 'Leistungsüberblick' : 'Service overview',
                subtitle: resolvePublicText(
                  profile.serviceCardSubtitle,
                  _language,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    PublicBulletList(
                      items: visual.highlights
                          .map((item) => item.resolve(languageCode))
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: visual.metrics
                          .map(
                            (metric) => PublicTagChip(
                              text: metric.resolve(languageCode),
                              icon: Icons.check_circle_outline_rounded,
                              backgroundColor: AppTheme.cobalt.withValues(
                                alpha: 0.08,
                              ),
                              foregroundColor: AppTheme.cobalt,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              );

              final factsCard = PublicSurfaceCard(
                title: isGerman ? 'Rahmendaten' : 'Service facts',
                subtitle: isGerman
                    ? 'Die wichtigsten öffentlichen Informationen für diese Leistung.'
                    : 'The key public information for this service.',
                child: PublicInfoList(
                  rows: <PublicInfoRowData>[
                    PublicInfoRowData(
                      label: isGerman ? 'Leistung' : 'Service',
                      value: serviceName,
                      icon: Icons.cleaning_services_rounded,
                    ),
                    PublicInfoRowData(
                      label: isGerman ? 'Einsatzgebiet' : 'Service area',
                      value: resolvePublicText(
                        profile.serviceAreaText,
                        _language,
                      ),
                      icon: Icons.public_rounded,
                    ),
                    PublicInfoRowData(
                      label: isGerman ? 'Erreichbarkeit' : 'Availability',
                      value: resolvePublicText(
                        profile.contact.hoursLabel,
                        _language,
                      ),
                      icon: Icons.schedule_rounded,
                    ),
                    PublicInfoRowData(
                      label: isGerman ? 'Kontakt' : 'Contact',
                      value: profile.contact.phone,
                      icon: Icons.call_rounded,
                    ),
                  ],
                ),
              );

              final processCard = PublicSurfaceCard(
                title: resolvePublicText(profile.howItWorksTitle, _language),
                subtitle: isGerman
                    ? 'Der Ablauf bleibt einfach und für alle Leistungen konsistent.'
                    : 'The workflow stays simple and consistent across services.',
                child: PublicInfoList(
                  rows: profile.howItWorksSteps
                      .map(
                        (step) => PublicInfoRowData(
                          label: resolvePublicText(step.title, _language),
                          value: resolvePublicText(step.subtitle, _language),
                          icon: Icons.timeline_rounded,
                        ),
                      )
                      .toList(growable: false),
                ),
              );

              final actionCard = PublicSurfaceCard(
                title: isGerman ? 'Nächster Schritt' : 'Next step',
                subtitle: isGerman
                    ? 'Zur Leistungsübersicht zurück oder direkt eine Kundenanfrage starten.'
                    : 'Return to the services overview or start a customer request directly.',
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    FilledButton(
                      onPressed: () => context.go(servicesPath),
                      child: Text(
                        isGerman ? 'Alle Leistungen' : 'All services',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => context.go(bookingPath),
                      child: Text(
                        resolvePublicText(
                          profile.createAccountLabel,
                          _language,
                        ),
                      ),
                    ),
                  ],
                ),
              );

              if (wide) {
                return Column(
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: PublicReveal(
                            delay: const Duration(milliseconds: 80),
                            child: overviewCard,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: PublicReveal(
                            delay: const Duration(milliseconds: 150),
                            child: factsCard,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    PublicReveal(
                      delay: const Duration(milliseconds: 220),
                      child: processCard,
                    ),
                    const SizedBox(height: 20),
                    PublicReveal(
                      delay: const Duration(milliseconds: 290),
                      child: actionCard,
                    ),
                  ],
                );
              }

              return Column(
                children: <Widget>[
                  PublicReveal(
                    delay: const Duration(milliseconds: 80),
                    child: overviewCard,
                  ),
                  const SizedBox(height: 20),
                  PublicReveal(
                    delay: const Duration(milliseconds: 150),
                    child: factsCard,
                  ),
                  const SizedBox(height: 20),
                  PublicReveal(
                    delay: const Duration(milliseconds: 220),
                    child: processCard,
                  ),
                  const SizedBox(height: 20),
                  PublicReveal(
                    delay: const Duration(milliseconds: 290),
                    child: actionCard,
                  ),
                ],
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
  const _PublicPageErrorScaffold({this.message = 'Unable to load page'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(message)));
  }
}
