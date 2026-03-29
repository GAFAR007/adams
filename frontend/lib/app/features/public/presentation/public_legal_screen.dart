library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../data/public_repository.dart';
import 'public_site_shell.dart';
import 'public_visuals.dart';

class PublicLegalScreen extends ConsumerStatefulWidget {
  const PublicLegalScreen({super.key, this.initialLanguageCode});

  final String? initialLanguageCode;

  @override
  ConsumerState<PublicLegalScreen> createState() => _PublicLegalScreenState();
}

class _PublicLegalScreenState extends ConsumerState<PublicLegalScreen> {
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
        final title = isGerman ? 'Rechtliches' : 'Legal';
        final subtitle = isGerman
            ? 'Öffentliche Unternehmens- und Kontaktangaben für die Website.'
            : 'Public business and contact details for the website.';
        final pageVisual = publicPageVisualForKey('legal');
        final address = [
          profile.contact.addressLine1,
          '${profile.contact.postalCode} ${profile.contact.city}'.trim(),
          profile.contact.country,
        ].where((part) => part.trim().isNotEmpty).join(', ');

        return PublicSiteShell(
          profile: profile,
          language: _language,
          onLanguageChanged: (language) {
            setState(() => _language = language);
          },
          activeItem: PublicNavItem.legal,
          eyebrow: title,
          pageTitle: title,
          pageSubtitle: subtitle,
          heroVisual: PublicImageCard(
            imageUrl: pageVisual.imageUrl,
            eyebrow: resolvePublicText(pageVisual.kicker, _language),
            title: title,
            subtitle: resolvePublicText(pageVisual.supportingLine, _language),
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 980;
              final legalCard = PublicSurfaceCard(
                title: isGerman ? 'Unternehmensangaben' : 'Business details',
                subtitle: isGerman
                    ? 'Die wichtigsten Angaben, die aktuell aus dem Backend-Profil geladen werden.'
                    : 'The main details currently loaded from the backend profile.',
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
                      label: isGerman ? 'Standort' : 'Address',
                      value: address,
                      icon: Icons.location_on_rounded,
                    ),
                  ],
                ),
              );
              final contactCard = PublicSurfaceCard(
                title: isGerman ? 'Kontakt für Rechtliches' : 'Legal contact',
                subtitle: isGerman
                    ? 'Diese öffentlichen Kontaktwege stehen für Rückfragen zur Verfügung.'
                    : 'These public contact channels are available for follow-up questions.',
                child: PublicInfoList(
                  rows: <PublicInfoRowData>[
                    PublicInfoRowData(
                      label: isGerman ? 'Telefon' : 'Phone',
                      value: profile.contact.phone,
                      icon: Icons.call_rounded,
                    ),
                    PublicInfoRowData(
                      label: isGerman ? 'E-Mail' : 'Email',
                      value: profile.contact.email,
                      icon: Icons.mail_rounded,
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
              final noteCard = PublicSurfaceCard(
                title: isGerman ? 'Hinweis' : 'Note',
                subtitle: isGerman
                    ? 'Weitere formale Website-Angaben können später über das gleiche Firmenprofil oder ein separates CMS-Feld ergänzt werden.'
                    : 'Additional formal website disclosures can later be added through the same company profile or a dedicated CMS field.',
                child: PublicBulletList(
                  items: <String>[
                    isGerman
                        ? 'Die Seite verwendet aktuell die hinterlegten Firmenstammdaten aus MongoDB.'
                        : 'The page currently uses the stored company master data from MongoDB.',
                    isGerman
                        ? 'Kontakt, Standort, Einsatzgebiet und Öffnungszeiten bleiben dadurch konsistent.'
                        : 'That keeps contact, location, coverage, and hours consistent.',
                    isGerman
                        ? 'Wenn du vollständige Impressum- oder Datenschutztexte willst, sollten wir dafür eigene Backend-Felder ergänzen.'
                        : 'If you want full legal notice or privacy copy, we should add dedicated backend fields for that next.',
                  ],
                ),
              );

              if (wide) {
                return Column(
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: legalCard),
                        const SizedBox(width: 20),
                        Expanded(child: contactCard),
                      ],
                    ),
                    const SizedBox(height: 20),
                    noteCard,
                  ],
                );
              }

              return Column(
                children: <Widget>[
                  legalCard,
                  const SizedBox(height: 20),
                  contactCard,
                  const SizedBox(height: 20),
                  noteCard,
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
