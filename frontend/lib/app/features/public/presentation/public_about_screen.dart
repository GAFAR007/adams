library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../data/public_repository.dart';
import 'public_site_shell.dart';
import 'public_visuals.dart';

class PublicAboutScreen extends ConsumerStatefulWidget {
  const PublicAboutScreen({super.key, this.initialLanguageCode});

  final String? initialLanguageCode;

  @override
  ConsumerState<PublicAboutScreen> createState() => _PublicAboutScreenState();
}

class _PublicAboutScreenState extends ConsumerState<PublicAboutScreen> {
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
        final isGerman = _language == PublicSiteLanguage.german;
        final aboutTitle = isGerman ? 'Über uns' : 'About us';
        final aboutSubtitle = isGerman
            ? 'Lerne das Unternehmen, den Einsatzbereich und die Arbeitsweise von ${profile.companyName} kennen.'
            : 'Get to know ${profile.companyName}, the service area, and how the team works.';
        final pageVisual = publicPageVisualForKey('about');

        return PublicSiteShell(
          profile: profile,
          language: _language,
          onLanguageChanged: (language) {
            setState(() => _language = language);
          },
          activeItem: PublicNavItem.about,
          eyebrow: resolvePublicText(profile.category, _language),
          pageTitle: aboutTitle,
          pageSubtitle: aboutSubtitle,
          heroVisual: PublicImageCard(
            imageUrl: pageVisual.imageUrl,
            eyebrow: resolvePublicText(pageVisual.kicker, _language),
            title: profile.companyName,
            subtitle: resolvePublicText(pageVisual.supportingLine, _language),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final storyCard = PublicSurfaceCard(
                title: resolvePublicText(profile.heroPanelTitle, _language),
                subtitle: resolvePublicText(
                  profile.heroPanelSubtitle,
                  _language,
                ),
                child: PublicBulletList(
                  items: profile.heroBullets
                      .map((item) => resolvePublicText(item, _language))
                      .toList(growable: false),
                ),
              );
              final detailsCard = PublicSurfaceCard(
                title: isGerman ? 'Unternehmensprofil' : 'Company profile',
                subtitle: isGerman
                    ? 'Öffentliche Basisdaten direkt aus dem hinterlegten Firmenprofil.'
                    : 'Public baseline details pulled directly from the stored company profile.',
                child: PublicInfoList(
                  rows: <PublicInfoRowData>[
                    PublicInfoRowData(
                      label: isGerman ? 'Firmenname' : 'Legal name',
                      value: profile.legalName.isNotEmpty
                          ? profile.legalName
                          : profile.companyName,
                      icon: Icons.business_center_rounded,
                    ),
                    PublicInfoRowData(
                      label: isGerman ? 'Kategorie' : 'Category',
                      value: resolvePublicText(profile.category, _language),
                      icon: Icons.category_rounded,
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
                      label: isGerman ? 'Öffnungszeiten' : 'Hours',
                      value: resolvePublicText(
                        profile.contact.hoursLabel,
                        _language,
                      ),
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                ),
              );
              final workflowCard = PublicSurfaceCard(
                title: resolvePublicText(profile.howItWorksTitle, _language),
                subtitle: isGerman
                    ? 'Der gleiche Ablauf, kompakter dargestellt.'
                    : 'The same workflow, presented as a cleaner overview.',
                child: PublicInfoList(
                  rows: profile.howItWorksSteps
                      .map(
                        (step) => PublicInfoRowData(
                          label: resolvePublicText(step.title, _language),
                          value: resolvePublicText(step.subtitle, _language),
                          icon: Icons.checklist_rounded,
                        ),
                      )
                      .toList(growable: false),
                ),
              );

              if (wide) {
                return Column(
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: storyCard),
                        const SizedBox(width: 20),
                        Expanded(child: detailsCard),
                      ],
                    ),
                    const SizedBox(height: 20),
                    workflowCard,
                  ],
                );
              }

              return Column(
                children: <Widget>[
                  storyCard,
                  const SizedBox(height: 20),
                  detailsCard,
                  const SizedBox(height: 20),
                  workflowCard,
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
  const _PublicPageErrorScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Unable to load page')));
  }
}
