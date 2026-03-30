/// WHAT: Defines the full route map and role guards for the Flutter application.
/// WHY: Public, customer, admin, and staff flows all live in one app and need centralized navigation rules.
/// HOW: Watch auth state, redirect by role, and mount the screen tree under `GoRouter`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_dashboard_screen.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/admin_login_screen.dart';
import '../features/auth/presentation/customer_login_screen.dart';
import '../features/auth/presentation/staff_login_screen.dart';
import '../features/auth/presentation/staff_register_screen.dart';
import '../features/customer/presentation/customer_create_request_screen.dart';
import '../features/customer/presentation/customer_requests_screen.dart';
import '../features/public/presentation/home_screen.dart';
import '../features/public/presentation/public_about_screen.dart';
import '../features/public/presentation/public_booking_chat_screen.dart';
import '../features/public/presentation/public_contact_screen.dart';
import '../features/public/presentation/public_legal_screen.dart';
import '../features/public/presentation/public_service_detail_screen.dart';
import '../features/public/presentation/public_services_screen.dart';
import '../features/staff/presentation/staff_dashboard_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (BuildContext context, GoRouterState state) {
      final location = state.matchedLocation;
      final isAdminProtected = location == '/admin';
      final isStaffProtected = location == '/staff';
      final isCustomerProtected =
          location == '/app/requests' ||
          location == '/app/requests/new' ||
          location.startsWith('/app/requests/');
      final isPublicAuthRoute =
          location == '/login' ||
          location == '/book-service' ||
          location == '/register' ||
          location == '/admin/login' ||
          location == '/staff/login' ||
          location.startsWith('/staff/register/');

      if (!authState.hasBootstrapped || authState.isBootstrapping) {
        return location == '/splash' ? null : '/splash';
      }

      if (location == '/splash') {
        return _homeForRole(authState.role);
      }

      if (isPublicAuthRoute && authState.isAuthenticated) {
        if ((location == '/book-service' || location == '/register') &&
            authState.role == 'customer') {
          final selectedService = state.uri.queryParameters['service'];
          if (selectedService != null && selectedService.isNotEmpty) {
            return '/app/requests/new?service=$selectedService';
          }

          return '/app/requests/new';
        }

        return _homeForRole(authState.role);
      }

      if (isAdminProtected) {
        if (!authState.isAuthenticated) {
          return '/admin/login';
        }

        if (authState.role != 'admin') {
          return _homeForRole(authState.role);
        }
      }

      if (isStaffProtected) {
        if (!authState.isAuthenticated) {
          return '/staff/login';
        }

        if (authState.role != 'staff') {
          return _homeForRole(authState.role);
        }
      }

      if (isCustomerProtected) {
        if (!authState.isAuthenticated) {
          return '/login';
        }

        if (authState.role != 'customer') {
          return _homeForRole(authState.role);
        }
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        builder: (BuildContext context, GoRouterState state) =>
            const _StartupScreen(),
      ),
      GoRoute(
        path: '/',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _buildPublicTransitionPage(
              state,
              HomeScreen(
                initialLanguageCode: state.uri.queryParameters['lang'],
              ),
            ),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _buildPublicTransitionPage(
              state,
              PublicAboutScreen(
                initialLanguageCode: state.uri.queryParameters['lang'],
              ),
            ),
      ),
      GoRoute(
        path: '/contact',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _buildPublicTransitionPage(
              state,
              PublicContactScreen(
                initialLanguageCode: state.uri.queryParameters['lang'],
              ),
            ),
      ),
      GoRoute(
        path: '/legal',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _buildPublicTransitionPage(
              state,
              PublicLegalScreen(
                initialLanguageCode: state.uri.queryParameters['lang'],
              ),
            ),
      ),
      GoRoute(
        path: '/services',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _buildPublicTransitionPage(
              state,
              PublicServicesScreen(
                initialLanguageCode: state.uri.queryParameters['lang'],
              ),
            ),
      ),
      GoRoute(
        path: '/services/:serviceKey',
        pageBuilder: (BuildContext context, GoRouterState state) =>
            _buildPublicTransitionPage(
              state,
              PublicServiceDetailScreen(
                serviceKey: state.pathParameters['serviceKey'] ?? '',
                initialLanguageCode: state.uri.queryParameters['lang'],
              ),
            ),
      ),
      GoRoute(
        path: '/book-service',
        builder: (BuildContext context, GoRouterState state) =>
            PublicBookingChatScreen(
              initialLanguageCode: state.uri.queryParameters['lang'],
              initialServiceKey: state.uri.queryParameters['service'],
            ),
      ),
      GoRoute(
        path: '/login',
        builder: (BuildContext context, GoRouterState state) =>
            CustomerLoginScreen(
              initialLanguageCode: state.uri.queryParameters['lang'],
            ),
      ),
      GoRoute(
        path: '/register',
        builder: (BuildContext context, GoRouterState state) =>
            PublicBookingChatScreen(
              initialLanguageCode: state.uri.queryParameters['lang'],
              initialServiceKey: state.uri.queryParameters['service'],
            ),
      ),
      GoRoute(
        path: '/admin/login',
        builder: (BuildContext context, GoRouterState state) =>
            AdminLoginScreen(
              initialLanguageCode: state.uri.queryParameters['lang'],
            ),
      ),
      GoRoute(
        path: '/staff/login',
        builder: (BuildContext context, GoRouterState state) =>
            StaffLoginScreen(
              initialLanguageCode: state.uri.queryParameters['lang'],
            ),
      ),
      GoRoute(
        path: '/staff/register/:token',
        builder: (BuildContext context, GoRouterState state) =>
            StaffRegisterScreen(
              inviteToken: state.pathParameters['token'] ?? '',
            ),
      ),
      GoRoute(
        path: '/app/requests',
        builder: (BuildContext context, GoRouterState state) =>
            const CustomerRequestsScreen(),
      ),
      GoRoute(
        path: '/app/requests/new',
        builder: (BuildContext context, GoRouterState state) =>
            CustomerCreateRequestScreen(
              initialServiceType: state.uri.queryParameters['service'],
            ),
      ),
      GoRoute(
        path: '/app/requests/:requestId/edit',
        builder: (BuildContext context, GoRouterState state) =>
            CustomerCreateRequestScreen(
              requestId: state.pathParameters['requestId'],
            ),
      ),
      GoRoute(
        path: '/admin',
        builder: (BuildContext context, GoRouterState state) =>
            const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/staff',
        builder: (BuildContext context, GoRouterState state) =>
            const StaffDashboardScreen(),
      ),
    ],
  );
});

String _homeForRole(String role) {
  return switch (role) {
    'admin' => '/admin',
    'staff' => '/staff',
    'customer' => '/app/requests',
    _ => '/',
  };
}

CustomTransitionPage<void> _buildPublicTransitionPage(
  GoRouterState state,
  Widget child,
) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final offset = Tween<Offset>(
        begin: const Offset(0.02, 0.015),
        end: Offset.zero,
      ).animate(curved);

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: offset, child: child),
      );
    },
  );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
