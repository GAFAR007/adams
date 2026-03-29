/// WHAT: Renders the public landing page from backend-driven company profile data.
/// WHY: The homepage should present real company information from MongoDB in a cleaner, more structured way.
/// HOW: Fetch the public company profile, keep only the language toggle in local UI state, and map backend data into a branded hero plus grouped accordion sections.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/public_company_profile.dart';
import '../../../theme/app_theme.dart';
import '../data/public_repository.dart';
import 'public_site_shell.dart';
import 'public_visuals.dart';

enum _PublicLanguage { english, german }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.initialLanguageCode});

  final String? initialLanguageCode;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late _PublicLanguage _language;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguageCode == 'de'
        ? _PublicLanguage.german
        : _PublicLanguage.english;
  }

  String _text(LocalizedText value) {
    return value.resolve(_language == _PublicLanguage.german ? 'de' : 'en');
  }

  _UiLabels get _labels {
    return switch (_language) {
      _PublicLanguage.english => const _UiLabels(
        addressLabel: 'Address',
        phoneLabel: 'Phone',
        secondaryPhoneLabel: 'Secondary phone',
        emailLabel: 'Email',
        hoursLabel: 'Hours',
        legalNameLabel: 'Legal name',
        categoryLabel: 'Category',
        companyPanelTitle: 'About the company',
        companyPanelSubtitle:
            'Use the grouped sections below to browse public business details without turning the page into a long wall of cards.',
        contactPanelTitle: 'Business, contact and legal info',
        contactPanelSubtitle:
            'Structured like a cleaner contact and impressum layout, with the important details tucked into dropdowns.',
        companyAccordionTitle: 'Company details',
        contactAccordionTitle: 'Direct contact',
        coverageAccordionTitle: 'Availability and coverage',
        servicesPanelSubtitle:
            'Open a service to see how requests start and where the team operates.',
        processPanelSubtitle:
            'The public request flow stays visible, but now in compact dropdown sections.',
        quickContactTitle: 'Reach us directly',
        quickContactSubtitle:
            'Phone, email, address, and opening information in one place.',
        serviceAreaLabel: 'Service area',
        footerBadge: 'Backend-driven company profile',
        footerTitle: 'Structured public info for CL Facility Management',
        footerSubtitle:
            'Company details, contact data, services, and process steps are rendered from MongoDB instead of duplicated frontend constants.',
        heroFastResponseLabel: 'Fast response',
        heroAudienceLabel: 'Homes and businesses',
        utilityQuoteLabel: 'Free quote and fast response',
        utilityAvailabilityLabel: 'Available 24 hours a day',
        homeNavLabel: 'Home',
        aboutNavLabel: 'About us',
        servicesNavLabel: 'Services',
        legalNavLabel: 'Legal',
        contactNavLabel: 'Contact',
        sectionsMenuLabel: 'Menu',
      ),
      _PublicLanguage.german => const _UiLabels(
        addressLabel: 'Adresse',
        phoneLabel: 'Telefon',
        secondaryPhoneLabel: 'Weitere Nummer',
        emailLabel: 'E-Mail',
        hoursLabel: 'Öffnungszeiten',
        legalNameLabel: 'Firmenname',
        categoryLabel: 'Kategorie',
        companyPanelTitle: 'Über das Unternehmen',
        companyPanelSubtitle:
            'Mit den gruppierten Bereichen bleiben die öffentlichen Firmendaten übersichtlich statt als lange Kartenwand dargestellt.',
        contactPanelTitle: 'Kontakt, Firmendaten und Impressum',
        contactPanelSubtitle:
            'Die wichtigsten öffentlichen Angaben sind in klaren Dropdown-Bereichen gruppiert.',
        companyAccordionTitle: 'Unternehmensdaten',
        contactAccordionTitle: 'Direkter Kontakt',
        coverageAccordionTitle: 'Erreichbarkeit und Einsatzgebiet',
        servicesPanelSubtitle:
            'Öffne eine Leistung, um Ablauf und Einsatzgebiet kompakt zu sehen.',
        processPanelSubtitle:
            'Der öffentliche Anfrageablauf bleibt sichtbar, jetzt aber in kompakten Dropdown-Bereichen.',
        quickContactTitle: 'Direkt erreichbar',
        quickContactSubtitle:
            'Telefon, E-Mail, Adresse und Öffnungszeiten an einem Ort.',
        serviceAreaLabel: 'Einsatzgebiet',
        footerBadge: 'Backend-gesteuertes Unternehmensprofil',
        footerTitle:
            'Strukturierte öffentliche Angaben für CL Facility Management',
        footerSubtitle:
            'Firmendaten, Kontakt, Leistungen und Ablauf werden aus MongoDB gerendert statt als Frontend-Konstanten dupliziert.',
        heroFastResponseLabel: 'Schnelle Antwort',
        heroAudienceLabel: 'Privat und Gewerbe',
        utilityQuoteLabel: 'Kostenlose Anfrage und schnelle Antwort',
        utilityAvailabilityLabel: '24 Stunden am Tag erreichbar',
        homeNavLabel: 'Start',
        aboutNavLabel: 'Über uns',
        servicesNavLabel: 'Leistungen',
        legalNavLabel: 'Rechtliches',
        contactNavLabel: 'Kontakt',
        sectionsMenuLabel: 'Menü',
      ),
    };
  }

  String _routeWithLanguage(String path) {
    return _language == _PublicLanguage.german ? '$path?lang=de' : path;
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(publicCompanyProfileProvider);

    return profileAsync.when(
      data: (profile) => _buildLoadedHome(context, profile),
      loading: () => const _HomeLoadingScaffold(),
      error: (error, stackTrace) => _HomeErrorScaffold(
        onRetry: () => ref.invalidate(publicCompanyProfileProvider),
      ),
    );
  }

  Widget _buildLoadedHome(
    BuildContext context,
    PublicCompanyProfileModel profile,
  ) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 980;
    final isCompact = width < 720;
    final languageCode = _language == _PublicLanguage.german ? 'de' : 'en';
    final primaryColor = _colorFromHex(
      profile.primaryColorHex,
      AppTheme.cobalt,
    );
    final accentColor = _colorFromHex(profile.accentColorHex, AppTheme.ember);
    final heroSurfaceColor = Color.lerp(primaryColor, AppTheme.ink, 0.34)!;
    final homeVisual = publicPageVisualForKey('home');

    final quickContactRows = <_InfoLineData>[
      _InfoLineData(
        label: _labels.addressLabel,
        value: _fullAddress(profile.contact),
        icon: Icons.location_on_rounded,
      ),
      _InfoLineData(
        label: _labels.phoneLabel,
        value: profile.contact.phone,
        icon: Icons.call_rounded,
      ),
      _InfoLineData(
        label: _labels.emailLabel,
        value: profile.contact.email,
        icon: Icons.mail_rounded,
      ),
      _InfoLineData(
        label: _labels.hoursLabel,
        value: _text(profile.contact.hoursLabel),
        icon: Icons.schedule_rounded,
      ),
    ];

    final businessRows = <_InfoPairData>[
      _InfoPairData(
        label: _labels.legalNameLabel,
        value: profile.legalName.isNotEmpty
            ? profile.legalName
            : profile.companyName,
      ),
      _InfoPairData(
        label: _labels.categoryLabel,
        value: _text(profile.category),
      ),
      _InfoPairData(
        label: _labels.serviceAreaLabel,
        value: _text(profile.serviceAreaText),
      ),
    ];

    final directContactRows = <_InfoPairData>[
      _InfoPairData(
        label: _labels.addressLabel,
        value: _fullAddress(profile.contact),
      ),
      _InfoPairData(label: _labels.phoneLabel, value: profile.contact.phone),
      if (profile.contact.secondaryPhone.isNotEmpty)
        _InfoPairData(
          label: _labels.secondaryPhoneLabel,
          value: profile.contact.secondaryPhone,
        ),
      _InfoPairData(label: _labels.emailLabel, value: profile.contact.email),
    ];

    final availabilityRows = <_InfoPairData>[
      _InfoPairData(
        label: _labels.hoursLabel,
        value: _text(profile.contact.hoursLabel),
      ),
      _InfoPairData(
        label: _labels.serviceAreaLabel,
        value: _text(profile.serviceAreaText),
      ),
    ];

    final serviceCards = profile.serviceLabels
        .asMap()
        .entries
        .map((entry) {
          final service = entry.value;
          final visual = publicServiceVisualForKey(service.key);

          return PublicReveal(
            delay: Duration(milliseconds: 80 + (entry.key * 90)),
            child: PublicServiceFeatureCard(
              heroTag: publicServiceHeroTag(service.key),
              imageUrl: visual.imageUrl,
              icon: visual.icon,
              eyebrow: visual.eyebrow.resolve(languageCode),
              title: _text(service.label),
              summary: visual.summary.resolve(languageCode),
              highlights: visual.highlights
                  .map((item) => item.resolve(languageCode))
                  .toList(growable: false),
              metrics: visual.metrics
                  .map((item) => item.resolve(languageCode))
                  .toList(growable: false),
              actionLabel: _language == _PublicLanguage.german
                  ? 'Leistung öffnen'
                  : 'Open service',
              onTap: () =>
                  context.go(_routeWithLanguage('/services/${service.key}')),
            ),
          );
        })
        .toList(growable: false);

    final howItWorksItems = profile.howItWorksSteps
        .map(
          (step) => _AccordionItemData(
            title: _text(step.title),
            subtitle: _text(step.subtitle),
            icon: Icons.timeline_rounded,
            rows: const <_InfoPairData>[],
          ),
        )
        .toList(growable: false);

    return Scaffold(
      backgroundColor: AppTheme.sand,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              heroSurfaceColor,
              Color.lerp(AppTheme.sand, Colors.white, 0.08)!,
              AppTheme.sand,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const <double>[0, 0.34, 1],
          ),
        ),
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: _HeroShell(
                primaryColor: primaryColor,
                accentColor: accentColor,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      24,
                      isCompact ? 24 : 28,
                      24,
                      isCompact ? 48 : 60,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        PublicReveal(
                          delay: const Duration(milliseconds: 50),
                          child: _HeroTopBar(
                            theme: theme,
                            isCompact: isCompact,
                            language: _language,
                            companyName: profile.companyName,
                            adminLoginLabel: _text(profile.adminLoginLabel),
                            utilityQuoteLabel: _labels.utilityQuoteLabel,
                            utilityAvailabilityLabel:
                                _labels.utilityAvailabilityLabel,
                            homeNavLabel: _labels.homeNavLabel,
                            aboutNavLabel: _labels.aboutNavLabel,
                            servicesNavLabel: _labels.servicesNavLabel,
                            legalNavLabel: _labels.legalNavLabel,
                            contactNavLabel: _labels.contactNavLabel,
                            sectionsMenuLabel: _labels.sectionsMenuLabel,
                            serviceItems: profile.serviceLabels,
                            homePath: _routeWithLanguage('/'),
                            aboutPath: _routeWithLanguage('/about'),
                            servicesPath: _routeWithLanguage('/services'),
                            legalPath: _routeWithLanguage('/legal'),
                            contactPath: _routeWithLanguage('/contact'),
                            routeForService: (serviceKey) =>
                                _routeWithLanguage('/services/$serviceKey'),
                            onLanguageChanged: (nextLanguage) {
                              setState(() => _language = nextLanguage);
                            },
                          ),
                        ),
                        SizedBox(height: isCompact ? 28 : 40),
                        if (isWide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                flex: 6,
                                child: PublicReveal(
                                  delay: const Duration(milliseconds: 140),
                                  beginOffset: const Offset(-0.03, 0.02),
                                  child: _HeroCopy(
                                    category: _text(profile.category),
                                    tagline: _text(profile.tagline),
                                    heroTitle: _text(profile.heroTitle),
                                    heroSubtitle: _text(profile.heroSubtitle),
                                    bookServicePath: _routeWithLanguage(
                                      '/book-service',
                                    ),
                                    createAccountLabel: _text(
                                      profile.createAccountLabel,
                                    ),
                                    customerLoginLabel: _text(
                                      profile.customerLoginLabel,
                                    ),
                                    staffLoginLabel: _text(
                                      profile.staffLoginLabel,
                                    ),
                                    fastResponseLabel:
                                        _labels.heroFastResponseLabel,
                                    audienceLabel: _labels.heroAudienceLabel,
                                    coverageLabel: _text(
                                      profile.serviceAreaText,
                                    ),
                                    theme: theme,
                                    accentColor: accentColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                flex: 4,
                                child: PublicReveal(
                                  delay: const Duration(milliseconds: 210),
                                  beginOffset: const Offset(0.03, 0.02),
                                  child: _QuickContactPanel(
                                    title: _labels.quickContactTitle,
                                    subtitle: _labels.quickContactSubtitle,
                                    rows: quickContactRows,
                                    areaLabel: _text(profile.serviceAreaLabel),
                                    areaValue: _text(profile.serviceAreaText),
                                    primaryColor: primaryColor,
                                    accentColor: accentColor,
                                    heroImageUrl: homeVisual.imageUrl,
                                    visualEyebrow: homeVisual.kicker.resolve(
                                      languageCode,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              PublicReveal(
                                delay: const Duration(milliseconds: 140),
                                child: _HeroCopy(
                                  category: _text(profile.category),
                                  tagline: _text(profile.tagline),
                                  heroTitle: _text(profile.heroTitle),
                                  heroSubtitle: _text(profile.heroSubtitle),
                                  bookServicePath: _routeWithLanguage(
                                    '/book-service',
                                  ),
                                  createAccountLabel: _text(
                                    profile.createAccountLabel,
                                  ),
                                  customerLoginLabel: _text(
                                    profile.customerLoginLabel,
                                  ),
                                  staffLoginLabel: _text(
                                    profile.staffLoginLabel,
                                  ),
                                  fastResponseLabel:
                                      _labels.heroFastResponseLabel,
                                  audienceLabel: _labels.heroAudienceLabel,
                                  coverageLabel: _text(profile.serviceAreaText),
                                  theme: theme,
                                  accentColor: accentColor,
                                ),
                              ),
                              const SizedBox(height: 20),
                              PublicReveal(
                                delay: const Duration(milliseconds: 210),
                                child: _QuickContactPanel(
                                  title: _labels.quickContactTitle,
                                  subtitle: _labels.quickContactSubtitle,
                                  rows: quickContactRows,
                                  areaLabel: _text(profile.serviceAreaLabel),
                                  areaValue: _text(profile.serviceAreaText),
                                  primaryColor: primaryColor,
                                  accentColor: accentColor,
                                  heroImageUrl: homeVisual.imageUrl,
                                  visualEyebrow: homeVisual.kicker.resolve(
                                    languageCode,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _ServiceShowcaseSection(
                        title: _text(profile.servicesTitle),
                        subtitle: _labels.servicesPanelSubtitle,
                        cards: serviceCards,
                      ),
                      const SizedBox(height: 28),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: PublicReveal(
                                delay: const Duration(milliseconds: 110),
                                child: _ContentPanel(
                                  title: _labels.companyPanelTitle,
                                  subtitle: _labels.companyPanelSubtitle,
                                  child: _StoryPanel(
                                    heroPanelTitle: _text(
                                      profile.heroPanelTitle,
                                    ),
                                    heroPanelSubtitle: _text(
                                      profile.heroPanelSubtitle,
                                    ),
                                    bullets: profile.heroBullets
                                        .map(_text)
                                        .toList(growable: false),
                                    companyName: profile.companyName,
                                    serviceArea: _text(profile.serviceAreaText),
                                    accentColor: accentColor,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: PublicReveal(
                                delay: const Duration(milliseconds: 180),
                                child: _DropdownSectionPanel(
                                  title: _labels.contactPanelTitle,
                                  subtitle: _labels.contactPanelSubtitle,
                                  accentColor: accentColor,
                                  items: <_AccordionItemData>[
                                    _AccordionItemData(
                                      title: _labels.companyAccordionTitle,
                                      subtitle: profile.legalName.isNotEmpty
                                          ? profile.legalName
                                          : profile.companyName,
                                      icon: Icons.business_center_rounded,
                                      rows: businessRows,
                                    ),
                                    _AccordionItemData(
                                      title: _labels.contactAccordionTitle,
                                      subtitle: profile.contact.phone,
                                      icon: Icons.contact_phone_rounded,
                                      rows: directContactRows,
                                    ),
                                    _AccordionItemData(
                                      title: _labels.coverageAccordionTitle,
                                      subtitle: _text(
                                        profile.contact.hoursLabel,
                                      ),
                                      icon: Icons.public_rounded,
                                      rows: availabilityRows,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      else ...<Widget>[
                        PublicReveal(
                          delay: const Duration(milliseconds: 110),
                          child: _ContentPanel(
                            title: _labels.companyPanelTitle,
                            subtitle: _labels.companyPanelSubtitle,
                            child: _StoryPanel(
                              heroPanelTitle: _text(profile.heroPanelTitle),
                              heroPanelSubtitle: _text(
                                profile.heroPanelSubtitle,
                              ),
                              bullets: profile.heroBullets
                                  .map(_text)
                                  .toList(growable: false),
                              companyName: profile.companyName,
                              serviceArea: _text(profile.serviceAreaText),
                              accentColor: accentColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        PublicReveal(
                          delay: const Duration(milliseconds: 180),
                          child: _DropdownSectionPanel(
                            title: _labels.contactPanelTitle,
                            subtitle: _labels.contactPanelSubtitle,
                            accentColor: accentColor,
                            items: <_AccordionItemData>[
                              _AccordionItemData(
                                title: _labels.companyAccordionTitle,
                                subtitle: profile.legalName.isNotEmpty
                                    ? profile.legalName
                                    : profile.companyName,
                                icon: Icons.business_center_rounded,
                                rows: businessRows,
                              ),
                              _AccordionItemData(
                                title: _labels.contactAccordionTitle,
                                subtitle: profile.contact.phone,
                                icon: Icons.contact_phone_rounded,
                                rows: directContactRows,
                              ),
                              _AccordionItemData(
                                title: _labels.coverageAccordionTitle,
                                subtitle: _text(profile.contact.hoursLabel),
                                icon: Icons.public_rounded,
                                rows: availabilityRows,
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      PublicReveal(
                        delay: const Duration(milliseconds: 240),
                        child: _DropdownSectionPanel(
                          title: _text(profile.howItWorksTitle),
                          subtitle: _labels.processPanelSubtitle,
                          accentColor: accentColor,
                          items: howItWorksItems,
                        ),
                      ),
                      const SizedBox(height: 20),
                      PublicReveal(
                        delay: const Duration(milliseconds: 300),
                        child: _FooterCallout(
                          badge: _labels.footerBadge,
                          title: _labels.footerTitle,
                          subtitle: _labels.footerSubtitle,
                          accentColor: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fullAddress(PublicContactInfo contact) {
    final parts = <String>[
      contact.addressLine1,
      '${contact.postalCode} ${contact.city}'.trim(),
      contact.country,
    ].where((part) => part.trim().isNotEmpty).toList();

    return parts.join(', ');
  }

  Color _colorFromHex(String value, Color fallback) {
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
}

class _HomeLoadingScaffold extends StatelessWidget {
  const _HomeLoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[AppTheme.ink, AppTheme.cobalt],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}

class _HomeErrorScaffold extends StatelessWidget {
  const _HomeErrorScaffold({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _ContentPanel(
            title: 'Unable to load company profile',
            subtitle:
                'The homepage needs backend company data before it can render.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(backgroundColor: AppTheme.cobalt),
                child: Text(
                  'Retry',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroShell extends StatelessWidget {
  const _HeroShell({
    required this.primaryColor,
    required this.accentColor,
    required this.child,
  });

  final Color primaryColor;
  final Color accentColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Color.lerp(primaryColor, Colors.white, 0.04)!,
            Color.lerp(primaryColor, AppTheme.ink, 0.32)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -120,
            right: -80,
            child: _GlowOrb(
              diameter: 320,
              color: accentColor.withValues(alpha: 0.16),
            ),
          ),
          Positioned(
            bottom: -180,
            left: -120,
            child: _GlowOrb(
              diameter: 380,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color,
              blurRadius: diameter * 0.4,
              spreadRadius: diameter * 0.06,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroTopBar extends StatelessWidget {
  const _HeroTopBar({
    required this.theme,
    required this.isCompact,
    required this.language,
    required this.companyName,
    required this.adminLoginLabel,
    required this.utilityQuoteLabel,
    required this.utilityAvailabilityLabel,
    required this.homeNavLabel,
    required this.aboutNavLabel,
    required this.servicesNavLabel,
    required this.legalNavLabel,
    required this.contactNavLabel,
    required this.sectionsMenuLabel,
    required this.serviceItems,
    required this.homePath,
    required this.aboutPath,
    required this.servicesPath,
    required this.legalPath,
    required this.contactPath,
    required this.routeForService,
    required this.onLanguageChanged,
  });

  final ThemeData theme;
  final bool isCompact;
  final _PublicLanguage language;
  final String companyName;
  final String adminLoginLabel;
  final String utilityQuoteLabel;
  final String utilityAvailabilityLabel;
  final String homeNavLabel;
  final String aboutNavLabel;
  final String servicesNavLabel;
  final String legalNavLabel;
  final String contactNavLabel;
  final String sectionsMenuLabel;
  final List<PublicServiceItem> serviceItems;
  final String homePath;
  final String aboutPath;
  final String servicesPath;
  final String legalPath;
  final String contactPath;
  final String Function(String serviceKey) routeForService;
  final ValueChanged<_PublicLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _HeroUtilityStrip(
          quoteLabel: utilityQuoteLabel,
          availabilityLabel: utilityAvailabilityLabel,
          selectedLanguage: language,
          onLanguageChanged: onLanguageChanged,
          isCompact: isCompact,
        ),
        const SizedBox(height: 14),
        _MainNavigationBar(
          language: language,
          companyName: companyName,
          adminLoginLabel: adminLoginLabel,
          homeNavLabel: homeNavLabel,
          aboutNavLabel: aboutNavLabel,
          servicesNavLabel: servicesNavLabel,
          legalNavLabel: legalNavLabel,
          contactNavLabel: contactNavLabel,
          sectionsMenuLabel: sectionsMenuLabel,
          serviceItems: serviceItems,
          isCompact: isCompact,
          homePath: homePath,
          aboutPath: aboutPath,
          servicesPath: servicesPath,
          legalPath: legalPath,
          contactPath: contactPath,
          routeForService: routeForService,
        ),
      ],
    );
  }
}

class _HeroUtilityStrip extends StatelessWidget {
  const _HeroUtilityStrip({
    required this.quoteLabel,
    required this.availabilityLabel,
    required this.selectedLanguage,
    required this.onLanguageChanged,
    required this.isCompact,
  });

  final String quoteLabel;
  final String availabilityLabel;
  final _PublicLanguage selectedLanguage;
  final ValueChanged<_PublicLanguage> onLanguageChanged;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final utilityItems = Wrap(
      spacing: 18,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _UtilityBadge(icon: Icons.local_offer_rounded, label: quoteLabel),
        _UtilityBadge(icon: Icons.schedule_rounded, label: availabilityLabel),
      ],
    );

    if (isCompact) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cobalt.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            utilityItems,
            const SizedBox(height: 12),
            _LanguageToggle(
              selectedLanguage: selectedLanguage,
              onChanged: onLanguageChanged,
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cobalt.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: utilityItems),
          _LanguageToggle(
            selectedLanguage: selectedLanguage,
            onChanged: onLanguageChanged,
          ),
        ],
      ),
    );
  }
}

class _UtilityBadge extends StatelessWidget {
  const _UtilityBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 15, color: Colors.white),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _MainNavigationBar extends StatelessWidget {
  const _MainNavigationBar({
    required this.language,
    required this.companyName,
    required this.adminLoginLabel,
    required this.homeNavLabel,
    required this.aboutNavLabel,
    required this.servicesNavLabel,
    required this.legalNavLabel,
    required this.contactNavLabel,
    required this.sectionsMenuLabel,
    required this.serviceItems,
    required this.isCompact,
    required this.homePath,
    required this.aboutPath,
    required this.servicesPath,
    required this.legalPath,
    required this.contactPath,
    required this.routeForService,
  });

  final _PublicLanguage language;
  final String companyName;
  final String adminLoginLabel;
  final String homeNavLabel;
  final String aboutNavLabel;
  final String servicesNavLabel;
  final String legalNavLabel;
  final String contactNavLabel;
  final String sectionsMenuLabel;
  final List<PublicServiceItem> serviceItems;
  final bool isCompact;
  final String homePath;
  final String aboutPath;
  final String servicesPath;
  final String legalPath;
  final String contactPath;
  final String Function(String serviceKey) routeForService;

  @override
  Widget build(BuildContext context) {
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF1D5EC2), Color(0xFF7BC6F4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.cleaning_services_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Text(
          companyName,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppTheme.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.18),
            blurRadius: 26,
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
                    _CompactSiteMenu(
                      language: language,
                      label: sectionsMenuLabel,
                      homeLabel: homeNavLabel,
                      companyLabel: aboutNavLabel,
                      contactLabel: contactNavLabel,
                      servicesLabel: servicesNavLabel,
                      legalLabel: legalNavLabel,
                      serviceItems: serviceItems,
                      homePath: homePath,
                      aboutPath: aboutPath,
                      servicesPath: servicesPath,
                      legalPath: legalPath,
                      contactPath: contactPath,
                      routeForService: routeForService,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: () => context.go('/admin/login'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.cobalt.withValues(alpha: 0.08),
                      foregroundColor: AppTheme.cobalt,
                    ),
                    child: Text(adminLoginLabel),
                  ),
                ),
              ],
            )
          : Row(
              children: <Widget>[
                brand,
                const Spacer(),
                _DesktopMainNav(
                  language: language,
                  homeNavLabel: homeNavLabel,
                  aboutNavLabel: aboutNavLabel,
                  servicesNavLabel: servicesNavLabel,
                  legalNavLabel: legalNavLabel,
                  contactNavLabel: contactNavLabel,
                  serviceItems: serviceItems,
                  homePath: homePath,
                  aboutPath: aboutPath,
                  servicesPath: servicesPath,
                  legalPath: legalPath,
                  contactPath: contactPath,
                  routeForService: routeForService,
                ),
                const SizedBox(width: 16),
                FilledButton.tonal(
                  onPressed: () => context.go('/admin/login'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.cobalt.withValues(alpha: 0.08),
                    foregroundColor: AppTheme.cobalt,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(adminLoginLabel),
                ),
              ],
            ),
    );
  }
}

class _DesktopMainNav extends StatelessWidget {
  const _DesktopMainNav({
    required this.language,
    required this.homeNavLabel,
    required this.aboutNavLabel,
    required this.servicesNavLabel,
    required this.legalNavLabel,
    required this.contactNavLabel,
    required this.serviceItems,
    required this.homePath,
    required this.aboutPath,
    required this.servicesPath,
    required this.legalPath,
    required this.contactPath,
    required this.routeForService,
  });

  final _PublicLanguage language;
  final String homeNavLabel;
  final String aboutNavLabel;
  final String servicesNavLabel;
  final String legalNavLabel;
  final String contactNavLabel;
  final List<PublicServiceItem> serviceItems;
  final String homePath;
  final String aboutPath;
  final String servicesPath;
  final String legalPath;
  final String contactPath;
  final String Function(String serviceKey) routeForService;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _NavLinkButton(label: homeNavLabel, onTap: () => context.go(homePath)),
        _NavLinkButton(
          label: aboutNavLabel,
          onTap: () => context.go(aboutPath),
        ),
        _ServicesNavDropdown(
          language: language,
          label: servicesNavLabel,
          servicesPath: servicesPath,
          serviceItems: serviceItems,
          routeForService: routeForService,
        ),
        _NavLinkButton(
          label: legalNavLabel,
          onTap: () => context.go(legalPath),
        ),
        _NavLinkButton(
          label: contactNavLabel,
          onTap: () => context.go(contactPath),
        ),
      ],
    );
  }
}

class _NavLinkButton extends StatelessWidget {
  const _NavLinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.ink,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AppTheme.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ServicesNavDropdown extends StatelessWidget {
  const _ServicesNavDropdown({
    required this.language,
    required this.label,
    required this.servicesPath,
    required this.serviceItems,
    required this.routeForService,
  });

  final _PublicLanguage language;
  final String label;
  final String servicesPath;
  final List<PublicServiceItem> serviceItems;
  final String Function(String serviceKey) routeForService;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _NavLinkButton(label: label, onTap: () => context.go(servicesPath)),
          PopupMenuButton<String>(
            tooltip: label,
            color: const Color(0xFFF9F5EE),
            surfaceTintColor: Colors.transparent,
            elevation: 12,
            offset: const Offset(0, 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            onSelected: (serviceKey) => context.go(routeForService(serviceKey)),
            itemBuilder: (context) => serviceItems
                .map(
                  (service) => PopupMenuItem<String>(
                    value: service.key,
                    child: Text(
                      service.label.resolve(
                        language == _PublicLanguage.german ? 'de' : 'en',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppTheme.cobalt,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSiteMenu extends StatelessWidget {
  const _CompactSiteMenu({
    required this.language,
    required this.label,
    required this.homeLabel,
    required this.companyLabel,
    required this.contactLabel,
    required this.servicesLabel,
    required this.legalLabel,
    required this.serviceItems,
    required this.homePath,
    required this.aboutPath,
    required this.servicesPath,
    required this.legalPath,
    required this.contactPath,
    required this.routeForService,
  });

  final _PublicLanguage language;
  final String label;
  final String homeLabel;
  final String companyLabel;
  final String contactLabel;
  final String servicesLabel;
  final String legalLabel;
  final List<PublicServiceItem> serviceItems;
  final String homePath;
  final String aboutPath;
  final String servicesPath;
  final String legalPath;
  final String contactPath;
  final String Function(String serviceKey) routeForService;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: label,
      color: const Color(0xFFF8F4EC),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (value) {
        if (value == 'home') {
          context.go(homePath);
          return;
        }
        if (value == 'company') {
          context.go(aboutPath);
          return;
        }
        if (value == 'contact') {
          context.go(contactPath);
          return;
        }
        if (value == 'services') {
          context.go(servicesPath);
          return;
        }
        if (value == 'legal') {
          context.go(legalPath);
          return;
        }
        if (value.startsWith('service:')) {
          final serviceKey = value.replaceFirst('service:', '');
          context.go(routeForService(serviceKey));
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: 'home', child: Text(homeLabel)),
        PopupMenuItem<String>(value: 'company', child: Text(companyLabel)),
        PopupMenuItem<String>(value: 'contact', child: Text(contactLabel)),
        PopupMenuItem<String>(
          value: 'services',
          child: Text('$servicesLabel (${serviceItems.length})'),
        ),
        ...serviceItems.map(
          (service) => PopupMenuItem<String>(
            value: 'service:${service.key}',
            child: Text(
              service.label.resolve(
                language == _PublicLanguage.german ? 'de' : 'en',
              ),
            ),
          ),
        ),
        PopupMenuItem<String>(value: 'legal', child: Text(legalLabel)),
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

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({
    required this.selectedLanguage,
    required this.onChanged,
  });

  final _PublicLanguage selectedLanguage;
  final ValueChanged<_PublicLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _LanguageChip(
              label: 'EN',
              isSelected: selectedLanguage == _PublicLanguage.english,
              onTap: () => onChanged(_PublicLanguage.english),
            ),
            const SizedBox(width: 4),
            _LanguageChip(
              label: 'DE',
              isSelected: selectedLanguage == _PublicLanguage.german,
              onTap: () => onChanged(_PublicLanguage.german),
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
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white
              : Colors.white.withValues(alpha: 0.02),
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

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.category,
    required this.tagline,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.bookServicePath,
    required this.createAccountLabel,
    required this.customerLoginLabel,
    required this.staffLoginLabel,
    required this.fastResponseLabel,
    required this.audienceLabel,
    required this.coverageLabel,
    required this.accentColor,
    this.theme,
  });

  final String category;
  final String tagline;
  final String heroTitle;
  final String heroSubtitle;
  final String bookServicePath;
  final String createAccountLabel;
  final String customerLoginLabel;
  final String staffLoginLabel;
  final String fastResponseLabel;
  final String audienceLabel;
  final String coverageLabel;
  final Color accentColor;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final resolvedTheme = theme ?? Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _HeroChip(
              text: category,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
            ),
            _HeroChip(
              text: tagline,
              backgroundColor: accentColor.withValues(alpha: 0.22),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          heroTitle,
          style: resolvedTheme.textTheme.displayMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            height: 0.98,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 128,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: <Color>[
                accentColor,
                Colors.white.withValues(alpha: 0.92),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Text(
            heroSubtitle,
            style: resolvedTheme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _HeroStatPill(icon: Icons.bolt_rounded, label: fastResponseLabel),
            _HeroStatPill(icon: Icons.apartment_rounded, label: audienceLabel),
            _HeroStatPill(icon: Icons.place_rounded, label: coverageLabel),
          ],
        ),
        const SizedBox(height: 26),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: <Widget>[
            FilledButton(
              onPressed: () => context.go(bookServicePath),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.ink,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(createAccountLabel),
            ),
            OutlinedButton(
              onPressed: () => context.go('/login'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(customerLoginLabel),
            ),
            TextButton(
              onPressed: () => context.go('/staff/login'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
              ),
              child: Text(staffLoginLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroStatPill extends StatelessWidget {
  const _HeroStatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.text, required this.backgroundColor});

  final String text;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _QuickContactPanel extends StatelessWidget {
  const _QuickContactPanel({
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.areaLabel,
    required this.areaValue,
    required this.primaryColor,
    required this.accentColor,
    required this.heroImageUrl,
    required this.visualEyebrow,
  });

  final String title;
  final String subtitle;
  final List<_InfoLineData> rows;
  final String areaLabel;
  final String areaValue;
  final Color primaryColor;
  final Color accentColor;
  final String heroImageUrl;
  final String visualEyebrow;

  @override
  Widget build(BuildContext context) {
    final cardWidth = MediaQuery.sizeOf(context).width < 900
        ? double.infinity
        : 180.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.16),
            blurRadius: 38,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PublicImageCard(
            imageUrl: heroImageUrl,
            eyebrow: visualEyebrow,
            title: title,
            subtitle: subtitle,
            footer: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                PublicTagChip(
                  text: areaLabel,
                  icon: Icons.public_rounded,
                  backgroundColor: Colors.white.withValues(alpha: 0.14),
                  foregroundColor: Colors.white,
                ),
                PublicTagChip(
                  text: areaValue,
                  icon: Icons.place_rounded,
                  backgroundColor: accentColor.withValues(alpha: 0.28),
                  foregroundColor: Colors.white,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: rows
                .map(
                  (row) => SizedBox(
                    width: cardWidth,
                    child: _InfoCallout(
                      data: row,
                      primaryColor: primaryColor,
                      accentColor: accentColor,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _ServiceShowcaseSection extends StatelessWidget {
  const _ServiceShowcaseSection({
    required this.title,
    required this.subtitle,
    required this.cards,
  });

  final String title;
  final String subtitle;
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final cardWidth = wide
                ? (constraints.maxWidth - 20) / 2
                : double.infinity;

            return Wrap(
              spacing: 20,
              runSpacing: 20,
              children: cards
                  .map((card) => SizedBox(width: cardWidth, child: card))
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _ContentPanel extends StatelessWidget {
  const _ContentPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFE8DECF)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _StoryPanel extends StatelessWidget {
  const _StoryPanel({
    required this.heroPanelTitle,
    required this.heroPanelSubtitle,
    required this.bullets,
    required this.companyName,
    required this.serviceArea,
    required this.accentColor,
  });

  final String heroPanelTitle;
  final String heroPanelSubtitle;
  final List<String> bullets;
  final String companyName;
  final String serviceArea;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          heroPanelTitle,
          style: theme.textTheme.titleLarge?.copyWith(color: AppTheme.ink),
        ),
        const SizedBox(height: 8),
        Text(
          heroPanelSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
        ),
        const SizedBox(height: 18),
        ...bullets.map(
          (bullet) => _BulletRow(text: bullet, accentColor: accentColor),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            _MetaPill(
              icon: Icons.apartment_rounded,
              text: companyName,
              backgroundColor: AppTheme.cobalt.withValues(alpha: 0.08),
              foregroundColor: AppTheme.cobalt,
            ),
            _MetaPill(
              icon: Icons.place_rounded,
              text: serviceArea,
              backgroundColor: accentColor.withValues(alpha: 0.12),
              foregroundColor: Color.lerp(accentColor, AppTheme.ink, 0.18)!,
            ),
          ],
        ),
      ],
    );
  }
}

class _DropdownSectionPanel extends StatelessWidget {
  const _DropdownSectionPanel({
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.items,
  });

  final String title;
  final String subtitle;
  final Color accentColor;
  final List<_AccordionItemData> items;

  @override
  Widget build(BuildContext context) {
    return _ContentPanel(
      title: title,
      subtitle: subtitle,
      child: Column(
        children: items
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _AccordionTile(data: item, accentColor: accentColor),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _AccordionTile extends StatelessWidget {
  const _AccordionTile({required this.data, required this.accentColor});

  final _AccordionItemData data;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F5EE),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7DCCB)),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          iconColor: AppTheme.ink.withValues(alpha: 0.8),
          collapsedIconColor: AppTheme.ink.withValues(alpha: 0.8),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              data.icon,
              color: Color.lerp(accentColor, AppTheme.ink, 0.18),
              size: 22,
            ),
          ),
          title: Text(
            data.title,
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
          ),
          subtitle: data.subtitle.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    data.subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
          children: <Widget>[
            if (data.rows.isNotEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.76),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE6D8C5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: data.rows
                        .asMap()
                        .entries
                        .map(
                          (entry) => _DefinitionRow(
                            pair: entry.value,
                            isLast: entry.key == data.rows.length - 1,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FooterCallout extends StatelessWidget {
  const _FooterCallout({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });

  final String badge;
  final String title;
  final String subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            AppTheme.ink,
            Color.lerp(AppTheme.ink, accentColor, 0.18)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.16),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _MetaPill(
            icon: Icons.data_object_rounded,
            text: badge,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCallout extends StatelessWidget {
  const _InfoCallout({
    required this.data,
    required this.primaryColor,
    required this.accentColor,
  });

  final _InfoLineData data;
  final Color primaryColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = Color.lerp(Colors.white, AppTheme.sand, 0.68)!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4D8C9)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Color.lerp(primaryColor, Colors.white, 0.86),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              data.icon,
              size: 20,
              color: Color.lerp(primaryColor, accentColor, 0.26),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  data.label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppTheme.cobalt,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data.value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.ink,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.text, required this.accentColor});

  final String text;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: Color.lerp(accentColor, AppTheme.pine, 0.24),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _DefinitionRow extends StatelessWidget {
  const _DefinitionRow({required this.pair, required this.isLast});

  final _InfoPairData pair;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: isLast
                ? BorderSide.none
                : BorderSide(color: AppTheme.clay.withValues(alpha: 0.52)),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                pair.label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppTheme.cobalt,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                pair.value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.ink,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.text,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String text;
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
            Icon(icon, size: 16, color: foregroundColor),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.max(120, MediaQuery.sizeOf(context).width * 0.5),
              ),
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
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

class _InfoLineData {
  const _InfoLineData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _InfoPairData {
  const _InfoPairData({required this.label, required this.value});

  final String label;
  final String value;
}

class _AccordionItemData {
  const _AccordionItemData({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.rows = const <_InfoPairData>[],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<_InfoPairData> rows;
}

class _UiLabels {
  const _UiLabels({
    required this.addressLabel,
    required this.phoneLabel,
    required this.secondaryPhoneLabel,
    required this.emailLabel,
    required this.hoursLabel,
    required this.legalNameLabel,
    required this.categoryLabel,
    required this.companyPanelTitle,
    required this.companyPanelSubtitle,
    required this.contactPanelTitle,
    required this.contactPanelSubtitle,
    required this.companyAccordionTitle,
    required this.contactAccordionTitle,
    required this.coverageAccordionTitle,
    required this.servicesPanelSubtitle,
    required this.processPanelSubtitle,
    required this.quickContactTitle,
    required this.quickContactSubtitle,
    required this.serviceAreaLabel,
    required this.footerBadge,
    required this.footerTitle,
    required this.footerSubtitle,
    required this.heroFastResponseLabel,
    required this.heroAudienceLabel,
    required this.utilityQuoteLabel,
    required this.utilityAvailabilityLabel,
    required this.homeNavLabel,
    required this.aboutNavLabel,
    required this.servicesNavLabel,
    required this.legalNavLabel,
    required this.contactNavLabel,
    required this.sectionsMenuLabel,
  });

  final String addressLabel;
  final String phoneLabel;
  final String secondaryPhoneLabel;
  final String emailLabel;
  final String hoursLabel;
  final String legalNameLabel;
  final String categoryLabel;
  final String companyPanelTitle;
  final String companyPanelSubtitle;
  final String contactPanelTitle;
  final String contactPanelSubtitle;
  final String companyAccordionTitle;
  final String contactAccordionTitle;
  final String coverageAccordionTitle;
  final String servicesPanelSubtitle;
  final String processPanelSubtitle;
  final String quickContactTitle;
  final String quickContactSubtitle;
  final String serviceAreaLabel;
  final String footerBadge;
  final String footerTitle;
  final String footerSubtitle;
  final String heroFastResponseLabel;
  final String heroAudienceLabel;
  final String utilityQuoteLabel;
  final String utilityAvailabilityLabel;
  final String homeNavLabel;
  final String aboutNavLabel;
  final String servicesNavLabel;
  final String legalNavLabel;
  final String contactNavLabel;
  final String sectionsMenuLabel;
}
