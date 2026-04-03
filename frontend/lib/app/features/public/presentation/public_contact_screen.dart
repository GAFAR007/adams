library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_language.dart';
import '../../../theme/app_theme.dart';
import '../data/public_repository.dart';
import 'public_site_shell.dart';
import 'public_visuals.dart';

class PublicContactScreen extends ConsumerStatefulWidget {
  const PublicContactScreen({super.key, this.initialLanguageCode});

  final String? initialLanguageCode;

  @override
  ConsumerState<PublicContactScreen> createState() =>
      _PublicContactScreenState();
}

class _PublicContactScreenState extends ConsumerState<PublicContactScreen> {
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
        final title = isGerman ? 'Kontakt' : 'Contact';
        final subtitle = isGerman
            ? 'Alle öffentlichen Kontakt- und Erreichbarkeitsdaten an einem Ort.'
            : 'All public contact and availability details in one place.';
        final pageVisual = publicPageVisualForKey('contact');
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
            ref.read(appLanguageProvider.notifier).setLanguage(language);
          },
          activeItem: PublicNavItem.contact,
          eyebrow: resolvePublicText(profile.contactSectionTitle, _language),
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
                  text: profile.contact.phone,
                  icon: Icons.call_rounded,
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
              final directCard = PublicSurfaceCard(
                title: isGerman ? 'Direkter Kontakt' : 'Direct contact',
                subtitle: isGerman
                    ? 'Telefon und E-Mail für neue Anfragen und Rückfragen.'
                    : 'Phone and email for new requests and follow-up questions.',
                child: PublicInfoList(
                  rows: <PublicInfoRowData>[
                    PublicInfoRowData(
                      label: isGerman ? 'Telefon' : 'Phone',
                      value: profile.contact.phone,
                      icon: Icons.call_rounded,
                    ),
                    if (profile.contact.secondaryPhone.isNotEmpty)
                      PublicInfoRowData(
                        label: isGerman ? 'Weitere Nummer' : 'Secondary phone',
                        value: profile.contact.secondaryPhone,
                        icon: Icons.phone_android_rounded,
                      ),
                    PublicInfoRowData(
                      label: isGerman ? 'E-Mail' : 'Email',
                      value: profile.contact.email,
                      icon: Icons.mail_rounded,
                    ),
                  ],
                ),
              );
              final businessCard = PublicSurfaceCard(
                title: isGerman
                    ? 'Standort und Erreichbarkeit'
                    : 'Location and availability',
                subtitle: isGerman
                    ? 'Adresse, Einsatzgebiet und Öffnungszeiten.'
                    : 'Address, service area, and operating hours.',
                child: PublicInfoList(
                  rows: <PublicInfoRowData>[
                    PublicInfoRowData(
                      label: isGerman ? 'Adresse' : 'Address',
                      value: address,
                      icon: Icons.location_on_rounded,
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
              final requestCard = PublicSurfaceCard(
                title: isGerman ? 'Anfragen' : 'Requests',
                subtitle: isGerman
                    ? 'Kunden können strukturierte Anfragen digital senden.'
                    : 'Customers can send structured requests digitally.',
                child: PublicBulletList(
                  items: <String>[
                    resolvePublicText(profile.heroSubtitle, _language),
                    resolvePublicText(profile.serviceCardSubtitle, _language),
                    resolvePublicText(
                      profile.howItWorksSteps.first.subtitle,
                      _language,
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
                        Expanded(child: directCard),
                        const SizedBox(width: 20),
                        Expanded(child: businessCard),
                      ],
                    ),
                    const SizedBox(height: 20),
                    requestCard,
                  ],
                );
              }

              return Column(
                children: <Widget>[
                  directCard,
                  const SizedBox(height: 20),
                  businessCard,
                  const SizedBox(height: 20),
                  requestCard,
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
