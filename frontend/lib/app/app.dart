/// WHAT: Builds the top-level Flutter application and triggers session bootstrap.
/// WHY: The router depends on auth state, so the app must initialize auth before user flows begin.
/// HOW: Start session bootstrap once, read the router provider, and render `MaterialApp.router`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/application/auth_controller.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class AdamsApp extends ConsumerStatefulWidget {
  const AdamsApp({super.key});

  @override
  ConsumerState<AdamsApp> createState() => _AdamsAppState();
}

class _AdamsAppState extends ConsumerState<AdamsApp> {
  @override
  void initState() {
    super.initState();

    // Bootstrapping once here keeps routing decisions consistent across refreshes and deep links.
    Future<void>.microtask(() => ref.read(authControllerProvider.notifier).bootstrapSession());
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('AdamsApp.build: rebuilding the root application');

    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Adams Service Ops',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildTheme(),
      routerConfig: router,
    );
  }
}
