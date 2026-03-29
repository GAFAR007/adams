library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/public_company_profile.dart';
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
  Timer? _sceneTimer;
  int _sceneIndex = 0;

  @override
  void initState() {
    super.initState();
    _language = publicSiteLanguageFromCode(widget.initialLanguageCode);
    _sceneTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _sceneIndex += 1);
    });
  }

  @override
  void dispose() {
    _sceneTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(publicCompanyProfileProvider);

    return profileAsync.when(
      data: (profile) {
        final isGerman = _language == PublicSiteLanguage.german;
        final primaryColor = publicColorFromHex(
          profile.primaryColorHex,
          AppTheme.cobalt,
        );
        final accentColor = publicColorFromHex(
          profile.accentColorHex,
          AppTheme.ember,
        );
        final serviceArea = _resolveLocalizedText(
          profile.serviceAreaText,
          _language,
        );
        final hoursText = _resolveLocalizedText(
          profile.contact.hoursLabel,
          _language,
        );
        final addressText = _formatAddress(profile.contact);
        final aboutTitle = isGerman ? 'Über uns' : 'About us';
        final aboutSubtitle = isGerman
            ? 'Lokale Reinigungsunterstützung für Wohnungen, Büros, Fenster und Gemeinschaftsflächen in $serviceArea.'
            : 'Local cleaning support for homes, offices, windows, and shared spaces in $serviceArea.';
        final bookServicePath = _routeWithLanguage('/book-service', _language);
        final scenes = _buildAboutScenes(
          profile: profile,
          language: _language,
          serviceArea: serviceArea,
          hoursText: hoursText,
          primaryColor: primaryColor,
          accentColor: accentColor,
        );
        final activeScene = scenes[_sceneIndex % scenes.length];
        final detailRows = <PublicInfoRowData>[
          PublicInfoRowData(
            label: isGerman ? 'Standort' : 'Based in',
            value: addressText,
            icon: Icons.location_on_rounded,
          ),
          PublicInfoRowData(
            label: isGerman ? 'Telefon' : 'Phone',
            value: profile.contact.phone,
            icon: Icons.phone_in_talk_rounded,
          ),
          PublicInfoRowData(
            label: isGerman ? 'E-Mail' : 'Email',
            value: profile.contact.email,
            icon: Icons.mail_rounded,
          ),
          PublicInfoRowData(
            label: isGerman ? 'Erreichbarkeit' : 'Hours',
            value: hoursText,
            icon: Icons.schedule_rounded,
          ),
        ];
        final serviceTags = profile.serviceLabels
            .map((item) => _resolveLocalizedText(item.label, _language))
            .where((label) => label.trim().isNotEmpty)
            .toList(growable: false);

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
          heroActions: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: <Widget>[
              FilledButton.icon(
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
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(
                  resolvePublicText(profile.createAccountLabel, _language),
                ),
              ),
            ],
          ),
          heroVisual: _AnimatedAboutHeroCard(
            scene: activeScene,
            sceneIndex: _sceneIndex % scenes.length,
            sceneCount: scenes.length,
          ),
          body: Column(
            children: <Widget>[
              _AboutShowcasePanel(
                companyName: profile.companyName,
                serviceArea: serviceArea,
                hoursText: hoursText,
                scene: activeScene,
                sceneIndex: _sceneIndex % scenes.length,
                sceneCount: scenes.length,
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final detailsCard = PublicSurfaceCard(
                    title: isGerman
                        ? 'Kontakt und Einsatzgebiet'
                        : 'Contact and coverage',
                    subtitle: isGerman
                        ? 'Die wichtigsten Angaben für direkten Kontakt und eine schnelle Einordnung.'
                        : 'The key details for direct contact and a quick overview.',
                    child: PublicInfoList(rows: detailRows),
                  );
                  final focusCard = _AboutFocusCard(
                    language: _language,
                    scene: activeScene,
                    serviceTags: serviceTags,
                  );

                  if (wide) {
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(child: detailsCard),
                          const SizedBox(width: 20),
                          Expanded(child: focusCard),
                        ],
                      ),
                    );
                  }

                  return Column(
                    children: <Widget>[
                      detailsCard,
                      const SizedBox(height: 20),
                      focusCard,
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
      loading: () => const _PublicPageLoadingScaffold(),
      error: (error, stackTrace) => const _PublicPageErrorScaffold(),
    );
  }
}

class _AboutSceneData {
  const _AboutSceneData({
    required this.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.bullets,
    required this.metrics,
    required this.imageUrl,
    required this.imageAlignment,
    required this.primaryColor,
    required this.secondaryColor,
  });

  final String key;
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<String> bullets;
  final List<String> metrics;
  final String imageUrl;
  final Alignment imageAlignment;
  final Color primaryColor;
  final Color secondaryColor;
}

class _AnimatedAboutHeroCard extends StatelessWidget {
  const _AnimatedAboutHeroCard({
    required this.scene,
    required this.sceneIndex,
    required this.sceneCount,
  });

  final _AboutSceneData scene;
  final int sceneIndex;
  final int sceneCount;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: scene.primaryColor.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 900),
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
                begin: const Offset(0.04, 0.02),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _AboutHeroFrame(
          key: ValueKey<String>('about-hero-${scene.key}'),
          scene: scene,
          sceneIndex: sceneIndex,
          sceneCount: sceneCount,
        ),
      ),
    );
  }
}

class _AboutHeroFrame extends StatelessWidget {
  const _AboutHeroFrame({
    super.key,
    required this.scene,
    required this.sceneIndex,
    required this.sceneCount,
  });

  final _AboutSceneData scene;
  final int sceneIndex;
  final int sceneCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: AspectRatio(
        aspectRatio: 16 / 11.2,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.network(
              scene.imageUrl,
              fit: BoxFit.cover,
              alignment: scene.imageAlignment,
              errorBuilder: (context, error, stackTrace) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[scene.primaryColor, scene.secondaryColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                );
              },
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    AppTheme.ink.withValues(alpha: 0.78),
                    scene.primaryColor.withValues(alpha: 0.36),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                  stops: const <double>[0, 0.62, 1],
                ),
              ),
            ),
            Positioned(
              top: 18,
              left: 18,
              child: PublicTagChip(
                text: scene.eyebrow,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                foregroundColor: Colors.white,
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
                    color: Colors.white.withValues(alpha: 0.14),
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
                    scene.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    scene.subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.84),
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutShowcasePanel extends StatelessWidget {
  const _AboutShowcasePanel({
    required this.companyName,
    required this.serviceArea,
    required this.hoursText,
    required this.scene,
    required this.sceneIndex,
    required this.sceneCount,
  });

  final String companyName;
  final String serviceArea;
  final String hoursText;
  final _AboutSceneData scene;
  final int sceneIndex;
  final int sceneCount;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            scene.primaryColor.withValues(alpha: 0.12),
            scene.secondaryColor.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.94),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: scene.primaryColor.withValues(alpha: 0.12)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final copy = AnimatedSwitcher(
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
                    begin: const Offset(0.04, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<String>('about-copy-${scene.key}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      PublicTagChip(
                        text: scene.eyebrow,
                        backgroundColor: scene.primaryColor.withValues(
                          alpha: 0.12,
                        ),
                        foregroundColor: scene.primaryColor,
                      ),
                      Text(
                        '${(sceneIndex + 1).toString().padLeft(2, '0')} / ${sceneCount.toString().padLeft(2, '0')}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppTheme.ink.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    scene.title,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(color: AppTheme.ink),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: wide ? 580 : constraints.maxWidth,
                    ),
                    child: Text(
                      scene.subtitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.ink.withValues(alpha: 0.78),
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: scene.bullets
                        .map(
                          (bullet) => _AboutBulletRow(
                            text: bullet,
                            accentColor: scene.primaryColor,
                          ),
                        )
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <String>[companyName, serviceArea, hoursText]
                        .where((value) => value.trim().isNotEmpty)
                        .map(
                          (chip) => PublicTagChip(
                            text: chip,
                            icon: _chipIconForValue(chip),
                            backgroundColor: const Color(0xFFF0E7D8),
                            foregroundColor: AppTheme.ink,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          );
          final visualRail = AnimatedSwitcher(
            duration: const Duration(milliseconds: 820),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) {
              return currentChild ?? const SizedBox.shrink();
            },
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1.03, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<String>('about-visual-${scene.key}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _AboutMiniVisualCard(
                    scene: scene,
                    sceneIndex: sceneIndex,
                    sceneCount: sceneCount,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: scene.metrics
                        .map(
                          (metric) => PublicTagChip(
                            text: metric,
                            backgroundColor: scene.primaryColor.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: scene.primaryColor,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 11, child: copy),
                const SizedBox(width: 24),
                Expanded(flex: 7, child: visualRail),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[copy, const SizedBox(height: 20), visualRail],
          );
        },
      ),
    );
  }
}

class _AboutMiniVisualCard extends StatelessWidget {
  const _AboutMiniVisualCard({
    required this.scene,
    required this.sceneIndex,
    required this.sceneCount,
  });

  final _AboutSceneData scene;
  final int sceneIndex;
  final int sceneCount;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 240,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.network(
              scene.imageUrl,
              fit: BoxFit.cover,
              alignment: scene.imageAlignment,
              errorBuilder: (context, error, stackTrace) {
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[scene.primaryColor, scene.secondaryColor],
                    ),
                  ),
                );
              },
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    AppTheme.ink.withValues(alpha: 0.8),
                    scene.primaryColor.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: PublicTagChip(
                text: scene.eyebrow,
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                foregroundColor: Colors.white,
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Text(
                '${(sceneIndex + 1).toString().padLeft(2, '0')} / ${sceneCount.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Text(
                scene.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutFocusCard extends StatelessWidget {
  const _AboutFocusCard({
    required this.language,
    required this.scene,
    required this.serviceTags,
  });

  final PublicSiteLanguage language;
  final _AboutSceneData scene;
  final List<String> serviceTags;

  @override
  Widget build(BuildContext context) {
    final isGerman = language == PublicSiteLanguage.german;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: scene.primaryColor.withValues(alpha: 0.12)),
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
          Text(
            isGerman ? 'Womit Sie rechnen können' : 'What to expect',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            isGerman
                ? 'Ein sauberer Ablauf, klare Kommunikation und Leistungen, die zum Objekt passen.'
                : 'A cleaner routine, clear communication, and support that matches the property.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
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
                    begin: const Offset(0.03, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Column(
              key: ValueKey<String>('focus-${scene.key}'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ...scene.bullets
                    .take(3)
                    .toList(growable: false)
                    .asMap()
                    .entries
                    .map(
                      (entry) => Padding(
                        padding: EdgeInsets.only(
                          bottom: entry.key == 2 ? 0 : 12,
                        ),
                        child: _AboutFocusTile(
                          text: entry.value,
                          icon: _focusIconForIndex(entry.key),
                          accentColor: scene.primaryColor,
                        ),
                      ),
                    ),
                if (scene.metrics.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: scene.metrics
                        .map(
                          (metric) => PublicTagChip(
                            text: metric,
                            backgroundColor: scene.secondaryColor.withValues(
                              alpha: 0.12,
                            ),
                            foregroundColor: Color.lerp(
                              scene.secondaryColor,
                              AppTheme.ink,
                              0.2,
                            )!,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                if (serviceTags.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: serviceTags
                        .take(4)
                        .map(
                          (label) => PublicTagChip(
                            text: label,
                            backgroundColor: AppTheme.cobalt.withValues(
                              alpha: 0.08,
                            ),
                            foregroundColor: AppTheme.cobalt,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutBulletRow extends StatelessWidget {
  const _AboutBulletRow({required this.text, required this.accentColor});

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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.55,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutFocusTile extends StatelessWidget {
  const _AboutFocusTile({
    required this.text,
    required this.icon,
    required this.accentColor,
  });

  final String text;
  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.ink,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
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

String _resolveLocalizedText(LocalizedText text, PublicSiteLanguage language) {
  return resolvePublicText(text, language);
}

String _routeWithLanguage(String path, PublicSiteLanguage language) {
  return publicSiteLanguageCode(language) == 'de' ? '$path?lang=de' : path;
}

String _formatAddress(PublicContactInfo contact) {
  return <String>[
    contact.addressLine1,
    <String>[
      contact.postalCode,
      contact.city,
    ].where((part) => part.trim().isNotEmpty).join(' '),
    contact.country,
  ].where((part) => part.trim().isNotEmpty).join(', ');
}

List<_AboutSceneData> _buildAboutScenes({
  required PublicCompanyProfileModel profile,
  required PublicSiteLanguage language,
  required String serviceArea,
  required String hoursText,
  required Color primaryColor,
  required Color accentColor,
}) {
  final pageVisual = publicPageVisualForKey('about');
  final officeVisual = publicServiceVisualForKey('office_cleaning');
  final buildingVisual = publicServiceVisualForKey('building_cleaning');
  final windowVisual = publicServiceVisualForKey('window_cleaning');
  final isGerman = language == PublicSiteLanguage.german;

  return <_AboutSceneData>[
    _AboutSceneData(
      key: 'welcome',
      eyebrow: resolvePublicText(pageVisual.kicker, language),
      title: isGerman
          ? 'Saubere Räume, klare Kommunikation, verlässliche Unterstützung'
          : 'Clean spaces, clear communication, reliable support',
      subtitle: isGerman
          ? '${profile.companyName} unterstützt Wohnungen, Büros und Gemeinschaftsflächen in $serviceArea dabei, sauber, gepflegt und im Alltag einsatzbereit zu bleiben.'
          : '${profile.companyName} helps homes, offices, and shared buildings in $serviceArea stay clean, presentable, and ready for everyday use.',
      bullets: <String>[
        isGerman
            ? 'Regelmäßige und einmalige Reinigungen, abgestimmt auf Objekt, Zeitplan und den Alltag vor Ort.'
            : 'Regular and one-off cleaning arranged around your property, schedule, and day-to-day needs.',
        isGerman
            ? 'Direkter Kontakt für Angebote, Terminabstimmung und praktische Servicefragen, wenn Sie Unterstützung brauchen.'
            : 'Direct contact for quotes, scheduling, and practical service questions when you need them.',
        isGerman
            ? 'Lokale Unterstützung in $serviceArea für Wohnungen, Büros, Fenster und Gemeinschaftsflächen.'
            : 'Local support across $serviceArea for homes, offices, windows, and shared spaces.',
      ],
      metrics: <String>[
        profile.companyName,
        serviceArea,
        hoursText,
      ].where((value) => value.trim().isNotEmpty).toList(growable: false),
      imageUrl: pageVisual.imageUrl,
      imageAlignment: Alignment.centerLeft,
      primaryColor: primaryColor,
      secondaryColor: accentColor,
    ),
    _AboutSceneData(
      key: 'office',
      eyebrow: resolvePublicText(officeVisual.eyebrow, language),
      title: isGerman
          ? 'Gezielte Unterstützung für ruhige, produktive Arbeitsplätze'
          : 'Focused support for calm, productive workplaces',
      subtitle: resolvePublicText(officeVisual.summary, language),
      bullets: officeVisual.highlights
          .map((item) => resolvePublicText(item, language))
          .toList(growable: false),
      metrics: officeVisual.metrics
          .map((item) => resolvePublicText(item, language))
          .toList(growable: false),
      imageUrl: officeVisual.imageUrl,
      imageAlignment: Alignment.centerRight,
      primaryColor: Color.lerp(primaryColor, AppTheme.pine, 0.22)!,
      secondaryColor: Color.lerp(accentColor, AppTheme.ink, 0.18)!,
    ),
    _AboutSceneData(
      key: 'building',
      eyebrow: resolvePublicText(buildingVisual.eyebrow, language),
      title: isGerman
          ? 'Gemeinschaftsflächen, die gepflegt und einladend bleiben'
          : 'Shared spaces that stay welcoming and well looked after',
      subtitle: resolvePublicText(buildingVisual.summary, language),
      bullets: buildingVisual.highlights
          .map((item) => resolvePublicText(item, language))
          .toList(growable: false),
      metrics: buildingVisual.metrics
          .map((item) => resolvePublicText(item, language))
          .toList(growable: false),
      imageUrl: buildingVisual.imageUrl,
      imageAlignment: Alignment.center,
      primaryColor: accentColor,
      secondaryColor: Color.lerp(accentColor, AppTheme.ink, 0.2)!,
    ),
    _AboutSceneData(
      key: 'window',
      eyebrow: resolvePublicText(windowVisual.eyebrow, language),
      title: isGerman
          ? 'Sauberes Glas, hellere Räume und ein stärkerer erster Eindruck'
          : 'Sharper glass, brighter spaces, and a stronger first impression',
      subtitle: resolvePublicText(windowVisual.summary, language),
      bullets: windowVisual.highlights
          .map((item) => resolvePublicText(item, language))
          .toList(growable: false),
      metrics: windowVisual.metrics
          .map((item) => resolvePublicText(item, language))
          .toList(growable: false),
      imageUrl: windowVisual.imageUrl,
      imageAlignment: Alignment.centerRight,
      primaryColor: Color.lerp(primaryColor, AppTheme.ink, 0.08)!,
      secondaryColor: AppTheme.pine,
    ),
  ];
}

IconData _chipIconForValue(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.contains('open') || normalized.contains('geöffnet')) {
    return Icons.schedule_rounded;
  }
  if (normalized.contains('germany') ||
      normalized.contains('deutschland') ||
      normalized.contains('mönchengladbach')) {
    return Icons.location_on_rounded;
  }
  return Icons.business_rounded;
}

IconData _focusIconForIndex(int index) {
  switch (index) {
    case 0:
      return Icons.task_alt_rounded;
    case 1:
      return Icons.forum_rounded;
    default:
      return Icons.event_available_rounded;
  }
}
