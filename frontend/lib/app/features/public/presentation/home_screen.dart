/// WHAT: Renders the public landing page from backend-driven company profile data.
/// WHY: The homepage should present real company information from MongoDB in a cleaner, more structured way.
/// HOW: Fetch the public company profile, keep only the language toggle in local UI state, and map backend data into a branded hero plus grouped accordion sections.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/public_company_profile.dart';
import '../../../shared/utils/external_url_opener.dart';
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
  final ValueNotifier<_StoryMotionState> _storyMotion = ValueNotifier(
    const _StoryMotionState(),
  );
  double _lastScrollPixels = 0;

  @override
  void initState() {
    super.initState();
    _language = widget.initialLanguageCode == 'de'
        ? _PublicLanguage.german
        : _PublicLanguage.english;
  }

  @override
  void dispose() {
    _storyMotion.dispose();
    super.dispose();
  }

  String _text(LocalizedText value) {
    return value.resolve(_language == _PublicLanguage.german ? 'de' : 'en');
  }

  Future<void> _copyText(String text, String successMessage) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openUri(Uri uri, {bool sameTab = false}) async {
    final launched = await openExternalUrl(uri.toString(), sameTab: sameTab);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_labels.linkOpenFailedMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Uri _buildPhoneUri(String phone) {
    return Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'\s+'), ''));
  }

  Uri _buildMailUri(String email) {
    return Uri(scheme: 'mailto', path: email);
  }

  Uri _buildMapsUri(PublicContactInfo contact) {
    final query = _fullAddress(contact);
    return Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
  }

  Uri _buildSocialUri(String value, String fallback) {
    final normalized = value.trim();
    return Uri.parse(normalized.isNotEmpty ? normalized : fallback);
  }

  _UiLabels get _labels {
    return switch (_language) {
      _PublicLanguage.english => const _UiLabels(
        addressLabel: 'Address',
        phoneLabel: 'Phone',
        emailLabel: 'Email',
        hoursLabel: 'Hours',
        companyPanelTitle: 'About us',
        companyPanelSubtitle: '',
        servicesPanelSubtitle:
            'Open a service to see how requests start and where the team operates.',
        quickContactTitle: 'Reach us directly',
        quickContactSubtitle:
            'Phone, email, address, and opening information in one place.',
        serviceAreaLabel: 'Service area',
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
        copyActionLabel: 'Copy',
        callActionLabel: 'Call',
        mapActionLabel: 'Open map',
        emailActionLabel: 'Send email',
        instagramActionLabel: 'Instagram',
        facebookActionLabel: 'Facebook',
        phoneCopiedMessage: 'Phone number copied',
        emailCopiedMessage: 'Email copied',
        addressCopiedMessage: 'Address copied',
        linkOpenFailedMessage: 'Could not open the link on this device.',
      ),
      _PublicLanguage.german => const _UiLabels(
        addressLabel: 'Adresse',
        phoneLabel: 'Telefon',
        emailLabel: 'E-Mail',
        hoursLabel: 'Öffnungszeiten',
        companyPanelTitle: 'Über uns',
        companyPanelSubtitle: '',
        servicesPanelSubtitle:
            'Öffne eine Leistung, um Ablauf und Einsatzgebiet kompakt zu sehen.',
        quickContactTitle: 'Direkt erreichbar',
        quickContactSubtitle:
            'Telefon, E-Mail, Adresse und Öffnungszeiten an einem Ort.',
        serviceAreaLabel: 'Einsatzgebiet',
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
        copyActionLabel: 'Kopieren',
        callActionLabel: 'Anrufen',
        mapActionLabel: 'Karte öffnen',
        emailActionLabel: 'E-Mail senden',
        instagramActionLabel: 'Instagram',
        facebookActionLabel: 'Facebook',
        phoneCopiedMessage: 'Telefonnummer kopiert',
        emailCopiedMessage: 'E-Mail kopiert',
        addressCopiedMessage: 'Adresse kopiert',
        linkOpenFailedMessage:
            'Der Link konnte auf diesem Gerät nicht geöffnet werden.',
      ),
    };
  }

  String _routeWithLanguage(String path) {
    return _language == _PublicLanguage.german ? '$path?lang=de' : path;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final pixels = notification.metrics.pixels;
    final delta = pixels - _lastScrollPixels;
    _lastScrollPixels = pixels;

    var direction = _storyMotion.value.direction;
    var momentum = _storyMotion.value.momentum;

    if (notification is ScrollUpdateNotification) {
      if (delta > 0.35) {
        direction = _StoryScrollDirection.down;
      } else if (delta < -0.35) {
        direction = _StoryScrollDirection.up;
      }
      momentum = (delta.abs() / 36).clamp(0.0, 1.0);
    } else if (notification is ScrollEndNotification) {
      direction = _StoryScrollDirection.idle;
      momentum = 0;
    }

    final progress = (pixels / 420).clamp(0.0, 1.4);
    final current = _storyMotion.value;
    if ((current.progress - progress).abs() < 0.01 &&
        (current.momentum - momentum).abs() < 0.02 &&
        current.direction == direction) {
      return false;
    }

    _storyMotion.value = _StoryMotionState(
      progress: progress,
      momentum: momentum,
      direction: direction,
    );
    return false;
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
    final fullAddress = _fullAddress(profile.contact);
    final mapsUri = _buildMapsUri(profile.contact);
    final phoneUri = _buildPhoneUri(profile.contact.phone);
    final emailUri = _buildMailUri(profile.contact.email);
    final instagramUri = _buildSocialUri(
      profile.contact.instagramUrl,
      'https://www.instagram.com/',
    );
    final facebookUri = _buildSocialUri(
      profile.contact.facebookUrl,
      'https://www.facebook.com/',
    );

    final quickContactRows = <_InfoLineData>[
      _InfoLineData(
        label: _labels.addressLabel,
        value: fullAddress,
        icon: Icons.location_on_rounded,
        compact: false,
        allowWrap: true,
        onTap: () {
          _openUri(mapsUri);
        },
        actions: <_InfoLineAction>[
          _InfoLineAction(
            icon: Icons.copy_rounded,
            tooltip: _labels.copyActionLabel,
            onTap: () {
              _copyText(fullAddress, _labels.addressCopiedMessage);
            },
          ),
          _InfoLineAction(
            icon: Icons.map_outlined,
            tooltip: _labels.mapActionLabel,
            onTap: () {
              _openUri(mapsUri);
            },
          ),
        ],
      ),
      _InfoLineData(
        label: _labels.phoneLabel,
        value: profile.contact.phone,
        icon: Icons.call_rounded,
        compact: true,
        allowWrap: true,
        onTap: () {
          _openUri(phoneUri, sameTab: true);
        },
        actions: <_InfoLineAction>[
          _InfoLineAction(
            icon: Icons.copy_rounded,
            tooltip: _labels.copyActionLabel,
            onTap: () {
              _copyText(profile.contact.phone, _labels.phoneCopiedMessage);
            },
          ),
          _InfoLineAction(
            icon: Icons.call_outlined,
            tooltip: _labels.callActionLabel,
            onTap: () {
              _openUri(phoneUri, sameTab: true);
            },
          ),
        ],
      ),
      _InfoLineData(
        label: _labels.emailLabel,
        value: profile.contact.email,
        icon: Icons.mail_rounded,
        compact: false,
        allowWrap: true,
        onTap: () {
          _openUri(emailUri, sameTab: true);
        },
        actions: <_InfoLineAction>[
          _InfoLineAction(
            icon: Icons.copy_rounded,
            tooltip: _labels.copyActionLabel,
            onTap: () {
              _copyText(profile.contact.email, _labels.emailCopiedMessage);
            },
          ),
          _InfoLineAction(
            icon: Icons.send_outlined,
            tooltip: _labels.emailActionLabel,
            onTap: () {
              _openUri(emailUri, sameTab: true);
            },
          ),
        ],
      ),
      _InfoLineData(
        label: _labels.hoursLabel,
        value: _text(profile.contact.hoursLabel),
        icon: Icons.schedule_rounded,
        compact: true,
        allowWrap: false,
      ),
    ];
    final socialLinks = <_SocialLinkData>[
      _SocialLinkData(
        icon: Icons.facebook_rounded,
        tooltip: _labels.facebookActionLabel,
        backgroundColor: const Color(0xFFDCE8FB),
        foregroundColor: const Color(0xFF1877F2),
        onTap: () {
          _openUri(facebookUri);
        },
      ),
      _SocialLinkData(
        icon: Icons.camera_alt_outlined,
        tooltip: _labels.instagramActionLabel,
        backgroundColor: const Color(0xFFE5ECF8),
        foregroundColor: AppTheme.cobalt,
        onTap: () {
          _openUri(instagramUri);
        },
      ),
    ];

    final serviceCardBuilders = profile.serviceLabels
        .asMap()
        .entries
        .map((entry) {
          final service = entry.value;
          final visual = publicServiceVisualForKey(service.key);
          final route = _routeWithLanguage('/services/${service.key}');

          return (BuildContext cardContext) => PublicReveal(
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
              onTap: () => cardContext.go(route),
            ),
          );
        })
        .toList(growable: false);
    final storyTitle = LocalizedText(
      en: 'Reliable support for clean, welcoming spaces',
      de: 'Verlässliche Unterstützung für saubere, einladende Räume',
    );
    final storySubtitle = LocalizedText(
      en: '${profile.companyName} helps homes, offices, and shared buildings in ${profile.serviceAreaText.en.isNotEmpty ? profile.serviceAreaText.en : profile.serviceAreaText.de} stay clean, presentable, and ready for everyday use.',
      de: '${profile.companyName} unterstützt Wohnungen, Büros und Gemeinschaftsflächen in ${profile.serviceAreaText.de.isNotEmpty ? profile.serviceAreaText.de : profile.serviceAreaText.en} dabei, sauber, gepflegt und im Alltag einsatzbereit zu bleiben.',
    );
    final storyBullets = <LocalizedText>[
      LocalizedText(
        en: 'Regular and one-off cleaning arranged around your property, schedule, and day-to-day needs.',
        de: 'Regelmäßige und einmalige Reinigungen, abgestimmt auf Objekt, Zeitplan und den Alltag vor Ort.',
      ),
      LocalizedText(
        en: 'Direct contact for quotes, scheduling, and practical service questions when you need them.',
        de: 'Direkter Kontakt für Angebote, Terminabstimmung und praktische Servicefragen, wenn Sie Unterstützung brauchen.',
      ),
      LocalizedText(
        en: 'Local support across ${profile.serviceAreaText.en.isNotEmpty ? profile.serviceAreaText.en : profile.serviceAreaText.de} for homes, offices, windows, and shared spaces.',
        de: 'Lokale Unterstützung in ${profile.serviceAreaText.de.isNotEmpty ? profile.serviceAreaText.de : profile.serviceAreaText.en} für Wohnungen, Büros, Fenster und Gemeinschaftsflächen.',
      ),
    ];

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
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
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
                                      socialLinks: socialLinks,
                                      areaLabel: _text(
                                        profile.serviceAreaLabel,
                                      ),
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
                                    coverageLabel: _text(
                                      profile.serviceAreaText,
                                    ),
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
                                    socialLinks: socialLinks,
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
                          cardBuilders: serviceCardBuilders,
                        ),
                        const SizedBox(height: 28),
                        PublicReveal(
                          delay: const Duration(milliseconds: 110),
                          child: _ContentPanel(
                            title: _labels.companyPanelTitle,
                            subtitle: _labels.companyPanelSubtitle,
                            child: _StoryPanel(
                              heroPanelTitle: storyTitle,
                              heroPanelSubtitle: storySubtitle,
                              bullets: storyBullets,
                              companyName: profile.companyName,
                              serviceArea: profile.serviceAreaText,
                              primaryColor: primaryColor,
                              accentColor: accentColor,
                              motionListenable: _storyMotion,
                            ),
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
    final currentPath = GoRouterState.of(context).uri.path;
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
            companyName,
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
                  child: _AdminEntryButton(
                    label: adminLoginLabel,
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
                    child: _DesktopMainNav(
                      language: language,
                      currentPath: currentPath,
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
                  ),
                ),
                const SizedBox(width: 22),
                _AdminEntryButton(
                  label: adminLoginLabel,
                  onPressed: () => context.go('/admin/login'),
                ),
              ],
            ),
    );
  }
}

class _DesktopMainNav extends StatelessWidget {
  const _DesktopMainNav({
    required this.language,
    required this.currentPath,
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
  final String currentPath;
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
    final normalizedHomePath = Uri.parse(homePath).path;
    final normalizedAboutPath = Uri.parse(aboutPath).path;
    final normalizedServicesPath = Uri.parse(servicesPath).path;
    final normalizedLegalPath = Uri.parse(legalPath).path;
    final normalizedContactPath = Uri.parse(contactPath).path;

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
          _NavLinkButton(
            label: homeNavLabel,
            isActive: currentPath == normalizedHomePath,
            onTap: () => context.go(homePath),
          ),
          _NavLinkButton(
            label: aboutNavLabel,
            isActive: currentPath == normalizedAboutPath,
            onTap: () => context.go(aboutPath),
          ),
          _ServicesNavDropdown(
            language: language,
            label: servicesNavLabel,
            servicesPath: servicesPath,
            isActive:
                currentPath == normalizedServicesPath ||
                currentPath.startsWith('$normalizedServicesPath/'),
            serviceItems: serviceItems,
            routeForService: routeForService,
          ),
          _NavLinkButton(
            label: legalNavLabel,
            isActive: currentPath == normalizedLegalPath,
            onTap: () => context.go(legalPath),
          ),
          _NavLinkButton(
            label: contactNavLabel,
            isActive: currentPath == normalizedContactPath,
            onTap: () => context.go(contactPath),
          ),
        ],
      ),
    );
  }
}

class _NavLinkButton extends StatelessWidget {
  const _NavLinkButton({
    required this.label,
    required this.onTap,
    this.isActive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: isActive ? AppTheme.cobalt : AppTheme.ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.1,
    );

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
          child: Text(label, style: textStyle),
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
    required this.isActive,
    required this.serviceItems,
    required this.routeForService,
  });

  final _PublicLanguage language;
  final String label;
  final String servicesPath;
  final bool isActive;
  final List<PublicServiceItem> serviceItems;
  final String Function(String serviceKey) routeForService;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      color: isActive ? AppTheme.cobalt : AppTheme.ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.1,
    );

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
              onTap: () => context.go(servicesPath),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                child: Text(label, style: textStyle),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: label,
            color: const Color(0xFFF9F5EE),
            surfaceTintColor: Colors.transparent,
            elevation: 14,
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

class _AdminEntryButton extends StatelessWidget {
  const _AdminEntryButton({required this.label, required this.onPressed});

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
    required this.socialLinks,
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
  final List<_SocialLinkData> socialLinks;
  final String areaLabel;
  final String areaValue;
  final Color primaryColor;
  final Color accentColor;
  final String heroImageUrl;
  final String visualEyebrow;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final useTwoColumns = panelWidth >= 680;
        final imageAspectRatio = panelWidth < 480
            ? 16 / 11.8
            : panelWidth < 680
            ? 16 / 10.8
            : 16 / 8.8;
        final primaryRows = rows
            .where((row) => !row.compact)
            .toList(growable: false);
        final compactRows = rows
            .where((row) => row.compact)
            .toList(growable: false);

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(30),
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
                aspectRatio: imageAspectRatio,
                borderRadius: 24,
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
              const SizedBox(height: 14),
              _QuickContactDirectory(
                primaryRows: primaryRows,
                compactRows: compactRows,
                useTwoColumns: useTwoColumns,
                primaryColor: primaryColor,
                accentColor: accentColor,
              ),
              if (socialLinks.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: socialLinks
                      .map((item) => _SocialLinkButton(data: item))
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _QuickContactDirectory extends StatelessWidget {
  const _QuickContactDirectory({
    required this.primaryRows,
    required this.compactRows,
    required this.useTwoColumns,
    required this.primaryColor,
    required this.accentColor,
  });

  final List<_InfoLineData> primaryRows;
  final List<_InfoLineData> compactRows;
  final bool useTwoColumns;
  final Color primaryColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Color.lerp(primaryColor, Colors.white, 0.9)!;
    final secondarySurface = Color.lerp(surfaceColor, AppTheme.sand, 0.4)!;
    final strokeColor = primaryColor.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[surfaceColor, secondarySurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: strokeColor),
      ),
      child: useTwoColumns
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 8,
                    child: _QuickContactColumn(
                      rows: primaryRows,
                      primaryColor: primaryColor,
                      accentColor: accentColor,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: strokeColor,
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: _QuickContactColumn(
                      rows: compactRows,
                      primaryColor: primaryColor,
                      accentColor: accentColor,
                    ),
                  ),
                ],
              ),
            )
          : _QuickContactColumn(
              rows: <_InfoLineData>[...primaryRows, ...compactRows],
              primaryColor: primaryColor,
              accentColor: accentColor,
            ),
    );
  }
}

class _QuickContactColumn extends StatelessWidget {
  const _QuickContactColumn({
    required this.rows,
    required this.primaryColor,
    required this.accentColor,
  });

  final List<_InfoLineData> rows;
  final Color primaryColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: rows
          .asMap()
          .entries
          .map(
            (entry) => _QuickContactLine(
              data: entry.value,
              isLast: entry.key == rows.length - 1,
              primaryColor: primaryColor,
              accentColor: accentColor,
            ),
          )
          .toList(growable: false),
    );
  }
}

class _QuickContactLine extends StatelessWidget {
  const _QuickContactLine({
    required this.data,
    required this.isLast,
    required this.primaryColor,
    required this.accentColor,
  });

  final _InfoLineData data;
  final bool isLast;
  final Color primaryColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconSurface = Color.lerp(primaryColor, Colors.white, 0.82)!;
    final accentIconColor = Color.lerp(primaryColor, accentColor, 0.18)!;
    final labelColor = Color.lerp(primaryColor, AppTheme.ink, 0.18)!;
    final labelWidth = data.compact ? 46.0 : 66.0;
    final content = Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: data.allowWrap
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, size: 16, color: accentIconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: data.compact
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: labelWidth,
                            child: Text(
                              data.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: labelColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              data.value,
                              maxLines: data.allowWrap ? 2 : 1,
                              softWrap: data.allowWrap,
                              overflow: data.allowWrap
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.ink.withValues(alpha: 0.88),
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            data.label,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: labelColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data.value,
                            maxLines: data.allowWrap ? 2 : 1,
                            softWrap: true,
                            overflow: data.allowWrap
                                ? TextOverflow.ellipsis
                                : TextOverflow.visible,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.ink.withValues(alpha: 0.88),
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
              ),
              if (data.actions.isNotEmpty) ...<Widget>[
                const SizedBox(width: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: data.actions
                      .map((action) => _InfoActionButton(data: action))
                      .toList(growable: false),
                ),
              ],
            ],
          ),
          if (!isLast) ...<Widget>[
            const SizedBox(height: 10),
            Divider(
              height: 1,
              thickness: 1,
              color: primaryColor.withValues(alpha: 0.1),
            ),
          ],
        ],
      ),
    );

    if (data.onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: data.onTap,
        child: content,
      ),
    );
  }
}

class _InfoActionButton extends StatelessWidget {
  const _InfoActionButton({required this.data});

  final _InfoLineAction data;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: data.tooltip,
      child: InkResponse(
        radius: 18,
        onTap: data.onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppTheme.cobalt.withValues(alpha: 0.08)),
          ),
          child: Icon(
            data.icon,
            size: 15,
            color: AppTheme.cobalt.withValues(alpha: 0.86),
          ),
        ),
      ),
    );
  }
}

class _SocialLinkButton extends StatelessWidget {
  const _SocialLinkButton({required this.data});

  final _SocialLinkData data;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: data.tooltip,
      child: InkResponse(
        radius: 28,
        onTap: data.onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: data.backgroundColor,
            shape: BoxShape.circle,
          ),
          child: Icon(data.icon, size: 28, color: data.foregroundColor),
        ),
      ),
    );
  }
}

class _ServiceShowcaseSection extends StatefulWidget {
  const _ServiceShowcaseSection({
    required this.title,
    required this.subtitle,
    required this.cardBuilders,
  });

  final String title;
  final String subtitle;
  final List<WidgetBuilder> cardBuilders;

  @override
  State<_ServiceShowcaseSection> createState() =>
      _ServiceShowcaseSectionState();
}

class _ServiceShowcaseSectionState extends State<_ServiceShowcaseSection> {
  PageController? _pageController;
  double? _viewportFraction;
  int? _cardCount;

  static int _loopStartPage(int itemCount, {int seedIndex = 0}) {
    if (itemCount <= 0) {
      return 0;
    }

    const seedPage = 10000;
    final basePage = seedPage - (seedPage % itemCount);
    return basePage + (seedIndex % itemCount);
  }

  void _ensurePageController({
    required int itemCount,
    required double viewportFraction,
  }) {
    final needsNewController =
        _pageController == null ||
        _cardCount != itemCount ||
        _viewportFraction == null ||
        (_viewportFraction! - viewportFraction).abs() > 0.001;

    if (!needsNewController) {
      return;
    }

    final logicalIndex = itemCount <= 0
        ? 0
        : ((_pageController?.hasClients ?? false)
                  ? (_pageController!.page?.round() ??
                        _pageController!.initialPage)
                  : (_pageController?.initialPage ?? 0)) %
              itemCount;

    _pageController?.dispose();
    _cardCount = itemCount;
    _viewportFraction = viewportFraction;
    _pageController = PageController(
      initialPage: _loopStartPage(itemCount, seedIndex: logicalIndex),
      viewportFraction: viewportFraction,
    );
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardBuilders = widget.cardBuilders;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(widget.title, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Text(
            widget.subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ),
        const SizedBox(height: 18),
        if (cardBuilders.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              if (cardBuilders.length == 1) {
                return cardBuilders.first(context);
              }

              final layout = _ServiceCarouselLayout.forWidth(
                constraints.maxWidth,
              );
              _ensurePageController(
                itemCount: cardBuilders.length,
                viewportFraction: layout.viewportFraction,
              );

              return SizedBox(
                height: layout.heightFor(constraints.maxWidth),
                child: ScrollConfiguration(
                  behavior: const MaterialScrollBehavior().copyWith(
                    dragDevices: <PointerDeviceKind>{
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.invertedStylus,
                      PointerDeviceKind.unknown,
                    },
                  ),
                  child: PageView.builder(
                    controller: _pageController!,
                    clipBehavior: Clip.none,
                    padEnds: false,
                    itemBuilder: (context, index) {
                      final logicalIndex = index % cardBuilders.length;
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: layout.cardSpacing / 2,
                        ),
                        child: cardBuilders[logicalIndex](context),
                      );
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _ServiceCarouselLayout {
  const _ServiceCarouselLayout({
    required this.viewportFraction,
    required this.cardSpacing,
    required this.minimumHeight,
    required this.contentHeight,
  });

  final double viewportFraction;
  final double cardSpacing;
  final double minimumHeight;
  final double contentHeight;

  factory _ServiceCarouselLayout.forWidth(double width) {
    if (width >= 1240) {
      return const _ServiceCarouselLayout(
        viewportFraction: 0.5,
        cardSpacing: 20,
        minimumHeight: 690,
        contentHeight: 338,
      );
    }
    if (width >= 920) {
      return const _ServiceCarouselLayout(
        viewportFraction: 0.64,
        cardSpacing: 18,
        minimumHeight: 700,
        contentHeight: 340,
      );
    }
    if (width >= 680) {
      return const _ServiceCarouselLayout(
        viewportFraction: 0.8,
        cardSpacing: 16,
        minimumHeight: 660,
        contentHeight: 332,
      );
    }
    if (width >= 480) {
      return const _ServiceCarouselLayout(
        viewportFraction: 0.92,
        cardSpacing: 14,
        minimumHeight: 660,
        contentHeight: 344,
      );
    }
    return const _ServiceCarouselLayout(
      viewportFraction: 0.94,
      cardSpacing: 12,
      minimumHeight: 700,
      contentHeight: 362,
    );
  }

  double heightFor(double availableWidth) {
    final cardWidth = math.max(
      0,
      (availableWidth * viewportFraction) - cardSpacing,
    );
    final estimatedHeight = (cardWidth * (10 / 16)) + contentHeight;
    return math.max(minimumHeight, estimatedHeight);
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
          if (subtitle.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: 18),
          ] else
            const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _StoryPanel extends StatefulWidget {
  const _StoryPanel({
    required this.heroPanelTitle,
    required this.heroPanelSubtitle,
    required this.bullets,
    required this.companyName,
    required this.serviceArea,
    required this.primaryColor,
    required this.accentColor,
    required this.motionListenable,
  });

  final LocalizedText heroPanelTitle;
  final LocalizedText heroPanelSubtitle;
  final List<LocalizedText> bullets;
  final String companyName;
  final LocalizedText serviceArea;
  final Color primaryColor;
  final Color accentColor;
  final ValueListenable<_StoryMotionState> motionListenable;

  @override
  State<_StoryPanel> createState() => _StoryPanelState();
}

class _StoryPanelState extends State<_StoryPanel> {
  Timer? _sceneTimer;
  int _sceneIndex = 0;

  @override
  void initState() {
    super.initState();
    _sceneTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sceneIndex = (_sceneIndex + 1) % 3;
      });
    });
  }

  @override
  void dispose() {
    _sceneTimer?.cancel();
    super.dispose();
  }

  String _localizedValue(LocalizedText text, String languageCode) {
    final value = text.resolve(languageCode).trim();
    if (value.isNotEmpty) {
      return value;
    }
    return text.resolve(languageCode == 'de' ? 'en' : 'de').trim();
  }

  List<String> _rotatedBullets(String languageCode, int start) {
    if (widget.bullets.isEmpty) {
      return <String>[_localizedValue(widget.heroPanelSubtitle, languageCode)];
    }

    final targetLength = math.min(3, widget.bullets.length);
    return List<String>.generate(targetLength, (index) {
      return _localizedValue(
        widget.bullets[(start + index) % widget.bullets.length],
        languageCode,
      );
    });
  }

  List<_StorySceneData> _buildScenes() {
    final aboutVisual = publicPageVisualForKey('about');
    final buildingVisual = publicServiceVisualForKey('building_cleaning');
    final officeVisual = publicServiceVisualForKey('office_cleaning');
    final windowVisual = publicServiceVisualForKey('window_cleaning');

    return <_StorySceneData>[
      _StorySceneData(
        key: 'about-en',
        localeCode: 'en',
        localeLabel: 'English',
        eyebrow: aboutVisual.kicker.resolve('en'),
        title: _localizedValue(widget.heroPanelTitle, 'en'),
        subtitle: _localizedValue(widget.heroPanelSubtitle, 'en'),
        bullets: _rotatedBullets('en', 0),
        imageUrl: aboutVisual.imageUrl,
        imageAlignment: Alignment.centerLeft,
        primaryColor: widget.primaryColor,
        secondaryColor: widget.accentColor,
      ),
      _StorySceneData(
        key: 'building-de',
        localeCode: 'de',
        localeLabel: 'Deutsch',
        eyebrow: buildingVisual.eyebrow.resolve('de'),
        title: _localizedValue(widget.heroPanelTitle, 'de'),
        subtitle: _localizedValue(widget.heroPanelSubtitle, 'de'),
        bullets: _rotatedBullets('de', 1),
        imageUrl: buildingVisual.imageUrl,
        imageAlignment: Alignment.center,
        primaryColor: widget.accentColor,
        secondaryColor: Color.lerp(widget.accentColor, AppTheme.ink, 0.22)!,
      ),
      _StorySceneData(
        key: 'office-en',
        localeCode: 'en',
        localeLabel: 'English',
        eyebrow: officeVisual.eyebrow.resolve('en'),
        title: _localizedValue(widget.heroPanelTitle, 'en'),
        subtitle: officeVisual.summary.resolve('en'),
        bullets: _rotatedBullets('en', 2),
        imageUrl: officeVisual.imageUrl,
        imageAlignment: Alignment.centerRight,
        primaryColor: AppTheme.pine,
        secondaryColor: widget.primaryColor,
      ),
      _StorySceneData(
        key: 'window-de',
        localeCode: 'de',
        localeLabel: 'Deutsch',
        eyebrow: windowVisual.eyebrow.resolve('de'),
        title: _localizedValue(widget.heroPanelTitle, 'de'),
        subtitle: windowVisual.summary.resolve('de'),
        bullets: _rotatedBullets('de', 0),
        imageUrl: windowVisual.imageUrl,
        imageAlignment: Alignment.centerRight,
        primaryColor: widget.primaryColor,
        secondaryColor: AppTheme.pine,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scenes = _buildScenes();
    final scene = scenes[_sceneIndex % scenes.length];

    return ValueListenableBuilder<_StoryMotionState>(
      valueListenable: widget.motionListenable,
      builder: (context, motion, _) {
        final directionSign = switch (motion.direction) {
          _StoryScrollDirection.down => 1.0,
          _StoryScrollDirection.up => -1.0,
          _StoryScrollDirection.idle => 0.0,
        };
        final imageOffset = Offset(
          directionSign * (8 + (motion.momentum * 12)),
          (-directionSign * 8) - (motion.progress * 6),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 920;
            final content = AnimatedSlide(
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              offset: Offset(directionSign * 0.02, 0),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 820),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (currentChild, previousChildren) {
                  return currentChild ?? const SizedBox.shrink();
                },
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.04, 0.03),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<String>('copy-${scene.key}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          _StoryLocalePill(
                            label: scene.localeLabel,
                            foregroundColor: scene.primaryColor,
                            backgroundColor: scene.primaryColor.withValues(
                              alpha: 0.12,
                            ),
                          ),
                          Text(
                            scene.eyebrow,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scene.primaryColor,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                          Text(
                            '${(_sceneIndex + 1).toString().padLeft(2, '0')} / ${scenes.length.toString().padLeft(2, '0')}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: AppTheme.ink.withValues(alpha: 0.45),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        scene.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: AppTheme.ink,
                          fontSize: isCompact ? 26 : 30,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isCompact ? constraints.maxWidth : 540,
                        ),
                        child: Text(
                          scene.subtitle,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: AppTheme.ink.withValues(alpha: 0.76),
                            height: 1.55,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 760),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (currentChild, previousChildren) {
                          return currentChild ?? const SizedBox.shrink();
                        },
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SizeTransition(
                              sizeFactor: animation,
                              axisAlignment: -1,
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          key: ValueKey<String>('bullets-${scene.key}'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: scene.bullets
                              .map(
                                (bullet) => _BulletRow(
                                  text: bullet,
                                  accentColor: scene.primaryColor,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          _MetaPill(
                            icon: Icons.apartment_rounded,
                            text: widget.companyName,
                            backgroundColor: scene.primaryColor.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: scene.primaryColor,
                          ),
                          _MetaPill(
                            icon: Icons.place_rounded,
                            text: _localizedValue(
                              widget.serviceArea,
                              scene.localeCode,
                            ),
                            backgroundColor: scene.secondaryColor.withValues(
                              alpha: 0.12,
                            ),
                            foregroundColor: Color.lerp(
                              scene.secondaryColor,
                              AppTheme.ink,
                              0.18,
                            )!,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );

            final imageCard = AnimatedSwitcher(
              duration: const Duration(milliseconds: 900),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) {
                return currentChild ?? const SizedBox.shrink();
              },
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 1.04,
                      end: 1,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _StoryImageCard(
                key: ValueKey<String>('image-${scene.key}'),
                scene: scene,
                sceneIndex: _sceneIndex,
                sceneCount: scenes.length,
                compact: isCompact,
                imageOffset: imageOffset,
                imageScale: 1.02 + (motion.momentum * 0.03),
              ),
            );

            return ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeInOutCubic,
                padding: EdgeInsets.all(isCompact ? 18 : 22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      scene.primaryColor.withValues(alpha: 0.12),
                      scene.secondaryColor.withValues(alpha: 0.1),
                      Colors.white.withValues(alpha: 0.94),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: scene.primaryColor.withValues(alpha: 0.12),
                  ),
                ),
                child: isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          imageCard,
                          const SizedBox(height: 18),
                          content,
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(flex: 6, child: content),
                          const SizedBox(width: 22),
                          Expanded(flex: 5, child: imageCard),
                        ],
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _StoryImageCard extends StatelessWidget {
  const _StoryImageCard({
    super.key,
    required this.scene,
    required this.sceneIndex,
    required this.sceneCount,
    required this.compact,
    required this.imageOffset,
    required this.imageScale,
  });

  final _StorySceneData scene;
  final int sceneIndex;
  final int sceneCount;
  final bool compact;
  final Offset imageOffset;
  final double imageScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: scene.primaryColor.withValues(alpha: 0.12),
            blurRadius: 26,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          height: compact ? 240 : 360,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Transform.translate(
                offset: imageOffset,
                child: Transform.scale(
                  scale: imageScale,
                  child: Image.network(
                    scene.imageUrl,
                    fit: BoxFit.cover,
                    alignment: scene.imageAlignment,
                    errorBuilder: (context, error, stackTrace) {
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              scene.primaryColor.withValues(alpha: 0.78),
                              scene.secondaryColor.withValues(alpha: 0.72),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      AppTheme.ink.withValues(alpha: 0.76),
                      scene.primaryColor.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    stops: const <double>[0, 0.55, 1],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      scene.secondaryColor.withValues(alpha: 0.12),
                      Colors.transparent,
                      scene.primaryColor.withValues(alpha: 0.18),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              Positioned(
                top: 18,
                left: 18,
                child: _StoryLocalePill(
                  label: scene.localeLabel,
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                ),
              ),
              Positioned(
                top: 18,
                right: 18,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    '${(sceneIndex + 1).toString().padLeft(2, '0')} / ${sceneCount.toString().padLeft(2, '0')}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      scene.eyebrow,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      scene.title,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontSize: compact ? 28 : 34,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryLocalePill extends StatelessWidget {
  const _StoryLocalePill({
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final String label;
  final Color foregroundColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: foregroundColor,
            fontWeight: FontWeight.w700,
          ),
        ),
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
    required this.compact,
    required this.allowWrap,
    this.onTap,
    this.actions = const <_InfoLineAction>[],
  });

  final String label;
  final String value;
  final IconData icon;
  final bool compact;
  final bool allowWrap;
  final VoidCallback? onTap;
  final List<_InfoLineAction> actions;
}

class _InfoLineAction {
  const _InfoLineAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
}

class _SocialLinkData {
  const _SocialLinkData({
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;
}

enum _StoryScrollDirection { idle, up, down }

class _StoryMotionState {
  const _StoryMotionState({
    this.progress = 0,
    this.momentum = 0,
    this.direction = _StoryScrollDirection.idle,
  });

  final double progress;
  final double momentum;
  final _StoryScrollDirection direction;
}

class _StorySceneData {
  const _StorySceneData({
    required this.key,
    required this.localeCode,
    required this.localeLabel,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.imageUrl,
    required this.imageAlignment,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final String key;
  final String localeCode;
  final String localeLabel;
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final String imageUrl;
  final Alignment imageAlignment;
  final Color primaryColor;
  final Color secondaryColor;
}

class _UiLabels {
  const _UiLabels({
    required this.addressLabel,
    required this.phoneLabel,
    required this.emailLabel,
    required this.hoursLabel,
    required this.companyPanelTitle,
    required this.companyPanelSubtitle,
    required this.servicesPanelSubtitle,
    required this.quickContactTitle,
    required this.quickContactSubtitle,
    required this.serviceAreaLabel,
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
    required this.copyActionLabel,
    required this.callActionLabel,
    required this.mapActionLabel,
    required this.emailActionLabel,
    required this.instagramActionLabel,
    required this.facebookActionLabel,
    required this.phoneCopiedMessage,
    required this.emailCopiedMessage,
    required this.addressCopiedMessage,
    required this.linkOpenFailedMessage,
  });

  final String addressLabel;
  final String phoneLabel;
  final String emailLabel;
  final String hoursLabel;
  final String companyPanelTitle;
  final String companyPanelSubtitle;
  final String servicesPanelSubtitle;
  final String quickContactTitle;
  final String quickContactSubtitle;
  final String serviceAreaLabel;
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
  final String copyActionLabel;
  final String callActionLabel;
  final String mapActionLabel;
  final String emailActionLabel;
  final String instagramActionLabel;
  final String facebookActionLabel;
  final String phoneCopiedMessage;
  final String emailCopiedMessage;
  final String addressCopiedMessage;
  final String linkOpenFailedMessage;
}
