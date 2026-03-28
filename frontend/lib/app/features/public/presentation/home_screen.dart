/// WHAT: Renders the public landing page with bilingual hero copy, core services, and auth CTAs.
/// WHY: Visitors should be able to understand the product quickly in either English or German before entering the app.
/// HOW: Keep lightweight home-page language state in Riverpod and map all public landing copy through localized data objects.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/panel_card.dart';
import '../../../theme/app_theme.dart';

enum _PublicLanguage { english, german }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _PublicLanguage _language = _PublicLanguage.english;

  @override
  Widget build(BuildContext context) {
    debugPrint('HomeScreen.build: rendering landing page');

    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
    final isCompact = width < 640;
    final copy = _copyFor(_language);

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[AppTheme.ink, AppTheme.cobalt],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _HeroTopBar(
                      theme: theme,
                      isCompact: isCompact,
                      language: _language,
                      adminLoginLabel: copy.adminLoginLabel,
                      onLanguageChanged: (nextLanguage) {
                        setState(() => _language = nextLanguage);
                      },
                    ),
                    const SizedBox(height: 40),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            flex: 5,
                            child: _HeroCopy(copy: copy, theme: theme),
                          ),
                          const SizedBox(width: 28),
                          Expanded(flex: 4, child: _HeroPanel(copy: copy)),
                        ],
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _HeroCopy(copy: copy),
                          const SizedBox(height: 28),
                          _HeroPanel(copy: copy),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList.list(
              children: <Widget>[
                Text(copy.servicesTitle, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: copy.serviceLabels
                      .map(
                        (String label) => SizedBox(
                          width: isWide ? 250 : double.infinity,
                          child: PanelCard(
                            title: label,
                            subtitle: copy.serviceCardSubtitle,
                            child: const SizedBox.shrink(),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 28),
                Text(
                  copy.howItWorksTitle,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: copy.howItWorksSteps
                      .map(
                        (_InfoCardCopy step) => SizedBox(
                          width: 280,
                          child: PanelCard(
                            title: step.title,
                            subtitle: step.subtitle,
                            child: const SizedBox.shrink(),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTopBar extends StatelessWidget {
  const _HeroTopBar({
    required this.theme,
    required this.isCompact,
    required this.language,
    required this.adminLoginLabel,
    required this.onLanguageChanged,
  });

  final ThemeData theme;
  final bool isCompact;
  final _PublicLanguage language;
  final String adminLoginLabel;
  final ValueChanged<_PublicLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(
            Icons.cleaning_services_rounded,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 14),
        Text(
          'Adams Service Ops',
          style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
        ),
      ],
    );

    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _LanguageToggle(
          selectedLanguage: language,
          onChanged: onLanguageChanged,
        ),
        TextButton(
          onPressed: () => context.go('/admin/login'),
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: Text(adminLoginLabel),
        ),
      ],
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[brand, const SizedBox(height: 16), actions],
      );
    }

    return Row(children: <Widget>[brand, const Spacer(), actions]);
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

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.copy, this.theme});

  final _HomeCopy copy;
  final ThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final resolvedTheme = theme ?? Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          copy.heroTitle,
          style: resolvedTheme.textTheme.displayMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          copy.heroSubtitle,
          style: resolvedTheme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: <Widget>[
            FilledButton(
              onPressed: () => context.go('/register'),
              child: Text(copy.createAccountLabel),
            ),
            OutlinedButton(
              onPressed: () => context.go('/login'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              child: Text(copy.customerLoginLabel),
            ),
            TextButton(
              onPressed: () => context.go('/staff/login'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(copy.staffLoginLabel),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.copy});

  final _HomeCopy copy;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      title: copy.heroPanelTitle,
      subtitle: copy.heroPanelSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: copy.heroBullets
            .map((String bullet) => _Bullet(text: bullet))
            .toList(),
      ),
    );
  }
}

class _HomeCopy {
  const _HomeCopy({
    required this.adminLoginLabel,
    required this.heroTitle,
    required this.heroSubtitle,
    required this.createAccountLabel,
    required this.customerLoginLabel,
    required this.staffLoginLabel,
    required this.heroPanelTitle,
    required this.heroPanelSubtitle,
    required this.heroBullets,
    required this.servicesTitle,
    required this.serviceCardSubtitle,
    required this.serviceLabels,
    required this.howItWorksTitle,
    required this.howItWorksSteps,
  });

  final String adminLoginLabel;
  final String heroTitle;
  final String heroSubtitle;
  final String createAccountLabel;
  final String customerLoginLabel;
  final String staffLoginLabel;
  final String heroPanelTitle;
  final String heroPanelSubtitle;
  final List<String> heroBullets;
  final String servicesTitle;
  final String serviceCardSubtitle;
  final List<String> serviceLabels;
  final String howItWorksTitle;
  final List<_InfoCardCopy> howItWorksSteps;
}

class _InfoCardCopy {
  const _InfoCardCopy({required this.title, required this.subtitle});

  final String title;
  final String subtitle;
}

const _HomeCopy _englishCopy = _HomeCopy(
  adminLoginLabel: 'Admin Login',
  heroTitle: 'Cleaner service requests, clearer operations, faster handoff.',
  heroSubtitle:
      'Customers create structured requests, admins manage the queue, and staff work only on the jobs assigned to them.',
  createAccountLabel: 'Create Customer Account',
  customerLoginLabel: 'Customer Login',
  staffLoginLabel: 'Staff Login',
  heroPanelTitle: 'What the first version does',
  heroPanelSubtitle:
      'Focused, operational, and ready for real request handling.',
  heroBullets: <String>[
    'Customer registration and structured request submission',
    'Admin dashboard for requests, staff, and invite links',
    'Staff dashboard for assigned requests and workflow updates',
    'Future-ready request structure for later AI intake',
  ],
  servicesTitle: 'Services',
  serviceCardSubtitle:
      'Structured request capture keeps the intake clean before staff take over.',
  serviceLabels: <String>[
    'Building Cleaning',
    'Warehouse & Hall Cleaning',
    'Window & Glass Cleaning',
    'Winter Service',
    'Caretaker Service',
    'Garden Care',
    'Post-Construction Cleaning',
  ],
  howItWorksTitle: 'How it works',
  howItWorksSteps: <_InfoCardCopy>[
    _InfoCardCopy(
      title: '1. Customer sends request',
      subtitle:
          'The request form captures service type, location, preferred timing, and job notes.',
    ),
    _InfoCardCopy(
      title: '2. Admin reviews queue',
      subtitle:
          'Admins see basic stats, pending invites, and a live request list for assignment.',
    ),
    _InfoCardCopy(
      title: '3. Staff moves the work',
      subtitle:
          'Assigned staff can quote, confirm appointments, and close work from their own dashboard.',
    ),
  ],
);

const _HomeCopy _germanCopy = _HomeCopy(
  adminLoginLabel: 'Admin-Anmeldung',
  heroTitle:
      'Sauberere Serviceanfragen, klarere Abläufe, schnellere Übergaben.',
  heroSubtitle:
      'Kundinnen und Kunden senden strukturierte Anfragen, Admins steuern die Queue und Mitarbeitende arbeiten nur an zugewiesenen Aufträgen.',
  createAccountLabel: 'Kundenkonto erstellen',
  customerLoginLabel: 'Kunden-Login',
  staffLoginLabel: 'Mitarbeiter-Login',
  heroPanelTitle: 'Was die erste Version kann',
  heroPanelSubtitle:
      'Fokussiert, operativ und bereit für echte Anfragen im Tagesgeschäft.',
  heroBullets: <String>[
    'Kundenregistrierung und strukturierte Anfrageerfassung',
    'Admin-Dashboard für Anfragen, Mitarbeitende und Einladungslinks',
    'Mitarbeiter-Dashboard für zugewiesene Aufträge und Statuswechsel',
    'Zukunftsfähige Struktur für spätere KI-gestützte Intake-Prozesse',
  ],
  servicesTitle: 'Leistungen',
  serviceCardSubtitle:
      'Die strukturierte Anfrageerfassung hält den Intake sauber, bevor das Team übernimmt.',
  serviceLabels: <String>[
    'Gebäudereinigung',
    'Lager- & Hallenreinigung',
    'Fenster- & Glasreinigung',
    'Winterdienst',
    'Hausmeisterservice',
    'Gartenpflege',
    'Bauendreinigung',
  ],
  howItWorksTitle: 'So funktioniert es',
  howItWorksSteps: <_InfoCardCopy>[
    _InfoCardCopy(
      title: '1. Kunde sendet Anfrage',
      subtitle:
          'Das Anfrageformular erfasst Leistungsart, Ort, Wunschzeit und wichtige Arbeitsnotizen.',
    ),
    _InfoCardCopy(
      title: '2. Admin prüft die Queue',
      subtitle:
          'Admins sehen Kennzahlen, offene Einladungen und die Live-Anfragenliste zur Zuweisung.',
    ),
    _InfoCardCopy(
      title: '3. Team bearbeitet den Auftrag',
      subtitle:
          'Zugewiesene Mitarbeitende können Angebote senden, Termine bestätigen und Arbeiten im eigenen Dashboard abschließen.',
    ),
  ],
);

_HomeCopy _copyFor(_PublicLanguage language) {
  return switch (language) {
    _PublicLanguage.english => _englishCopy,
    _PublicLanguage.german => _germanCopy,
  };
}
