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
import '../features/auth/presentation/customer_register_screen.dart';
import '../features/auth/presentation/staff_login_screen.dart';
import '../features/auth/presentation/staff_register_screen.dart';
import '../features/customer/presentation/customer_create_request_screen.dart';
import '../features/customer/presentation/customer_requests_screen.dart';
import '../features/public/presentation/home_screen.dart';
import '../features/staff/presentation/staff_dashboard_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authControllerProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (BuildContext context, GoRouterState state) {
      final location = state.matchedLocation;
      final isAdminProtected = location == '/admin';
      final isStaffProtected = location == '/staff';
      final isCustomerProtected = location == '/app/requests' || location == '/app/requests/new';
      final isPublicAuthRoute = location == '/login' ||
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
        builder: (BuildContext context, GoRouterState state) => const _StartupScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (BuildContext context, GoRouterState state) => const CustomerLoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (BuildContext context, GoRouterState state) => const CustomerRegisterScreen(),
      ),
      GoRoute(
        path: '/admin/login',
        builder: (BuildContext context, GoRouterState state) => const AdminLoginScreen(),
      ),
      GoRoute(
        path: '/staff/login',
        builder: (BuildContext context, GoRouterState state) => const StaffLoginScreen(),
      ),
      GoRoute(
        path: '/staff/register/:token',
        builder: (BuildContext context, GoRouterState state) => StaffRegisterScreen(
          inviteToken: state.pathParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: '/app/requests',
        builder: (BuildContext context, GoRouterState state) => const CustomerRequestsScreen(),
      ),
      GoRoute(
        path: '/app/requests/new',
        builder: (BuildContext context, GoRouterState state) => const CustomerCreateRequestScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (BuildContext context, GoRouterState state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/staff',
        builder: (BuildContext context, GoRouterState state) => const StaffDashboardScreen(),
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

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
