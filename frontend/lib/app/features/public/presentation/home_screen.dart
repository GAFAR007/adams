/// WHAT: Renders the public landing page with core services, trust messaging, and auth CTAs.
/// WHY: The first user touchpoint should explain the service clearly before pushing visitors into auth flows.
/// HOW: Use a responsive hero, service grid, and process section with navigation CTAs to role-specific routes.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../shared/presentation/panel_card.dart';
import '../../../theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    debugPrint('HomeScreen.build: rendering landing page');

    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 900;

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
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(Icons.cleaning_services_rounded, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Adams Service Ops',
                          style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => context.go('/admin/login'),
                          child: const Text('Admin Login'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            flex: 5,
                            child: _HeroCopy(theme: theme),
                          ),
                          const SizedBox(width: 28),
                          const Expanded(
                            flex: 4,
                            child: _HeroPanel(),
                          ),
                        ],
                      )
                    else
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _HeroCopy(),
                          SizedBox(height: 28),
                          _HeroPanel(),
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
                Text('Services', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: AppConfig.serviceLabels.values
                      .map(
                        (String label) => SizedBox(
                          width: isWide ? 250 : double.infinity,
                          child: PanelCard(
                            title: label,
                            subtitle: 'Structured request capture keeps the intake clean before staff take over.',
                            child: const SizedBox.shrink(),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 28),
                Text('How it works', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: const <Widget>[
                    SizedBox(
                      width: 280,
                      child: PanelCard(
                        title: '1. Customer sends request',
                        subtitle: 'The request form captures service type, location, preferred timing, and job notes.',
                        child: SizedBox.shrink(),
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: PanelCard(
                        title: '2. Admin reviews queue',
                        subtitle: 'Admins see basic stats, pending invites, and a live request list for assignment.',
                        child: SizedBox.shrink(),
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: PanelCard(
                        title: '3. Staff moves the work',
                        subtitle: 'Assigned staff can quote, confirm appointments, and close work from their own dashboard.',
                        child: SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
            child: Icon(Icons.check_circle_rounded, size: 18, color: AppTheme.pine),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({this.theme});

  final ThemeData? theme;

  @override
  Widget build(BuildContext context) {
    final resolvedTheme = theme ?? Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Cleaner service requests, clearer operations, faster handoff.',
          style: resolvedTheme.textTheme.displayMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Customers create structured requests, admins manage the queue, and staff work only on the jobs assigned to them.',
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
              child: const Text('Create Customer Account'),
            ),
            OutlinedButton(
              onPressed: () => context.go('/login'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
              child: const Text('Customer Login'),
            ),
            TextButton(
              onPressed: () => context.go('/staff/login'),
              child: const Text('Staff Login'),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel();

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      title: 'What the first version does',
      subtitle: 'Focused, operational, and ready for real request handling.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          _Bullet(text: 'Customer registration and structured request submission'),
          _Bullet(text: 'Admin dashboard for requests, staff, and invite links'),
          _Bullet(text: 'Staff dashboard for assigned requests and workflow updates'),
          _Bullet(text: 'Future-ready request structure for later AI intake'),
        ],
      ),
    );
  }
}
