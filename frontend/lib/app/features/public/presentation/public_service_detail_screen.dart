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
        final bookServiceLabel = resolvePublicText(
          profile.createAccountLabel,
          _language,
        );

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
          heroActions: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => context.go(bookingPath),
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
                label: Text(bookServiceLabel),
              ),
              OutlinedButton(
                onPressed: () => context.go(servicesPath),
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
                child: Text(isGerman ? 'Alle Leistungen' : 'All services'),
              ),
            ],
          ),
          heroDetails: _ServiceHeroDetails(
            title: isGerman
                ? 'Was diese Leistung umfasst'
                : 'What this service includes',
            items: visual.highlights
                .map((item) => item.resolve(languageCode))
                .toList(growable: false),
          ),
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
          body: const SizedBox.shrink(),
        );
      },
      loading: () => const _PublicPageLoadingScaffold(),
      error: (error, stackTrace) => const _PublicPageErrorScaffold(),
    );
  }
}

class _ServiceHeroDetails extends StatelessWidget {
  const _ServiceHeroDetails({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 720),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
  const _PublicPageErrorScaffold({this.message = 'Unable to load page'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(message)));
  }
}
