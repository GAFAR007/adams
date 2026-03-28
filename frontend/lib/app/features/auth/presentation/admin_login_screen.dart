/// WHAT: Renders the dedicated admin login form for operational access.
/// WHY: Admin access should be visually and behaviorally distinct from customer-facing auth flows.
/// HOW: Submit shared login credentials and enforce the returned role before routing to `/admin`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_controller.dart';
import '../../../shared/presentation/auth_scaffold.dart';

class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    debugPrint('AdminLoginScreen._submit: admin login submitted');

    try {
      await ref.read(authControllerProvider.notifier).loginAsRole(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            expectedRole: 'admin',
            failureMessage: 'Use an admin account for this dashboard.',
          );
    } catch (_) {
      return;
    }

    if (!mounted) {
      return;
    }

    context.go('/admin');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return AuthScaffold(
      title: 'Admin Login',
      subtitle: 'Access the request queue, staff list, and invite management tools.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Admin email'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          if (authState.errorMessage != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(authState.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: authState.isSubmitting ? null : _submit,
              child: Text(authState.isSubmitting ? 'Signing in...' : 'Enter Admin Dashboard'),
            ),
          ),
        ],
      ),
    );
  }
}
