/// WHAT: Renders the customer login form and starts the authenticated customer session.
/// WHY: Customers need a direct path into their request area before creating or tracking requests.
/// HOW: Collect credentials, call the auth controller, and route successful logins into `/app/requests`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_controller.dart';
import '../../../shared/presentation/auth_scaffold.dart';

class CustomerLoginScreen extends ConsumerStatefulWidget {
  const CustomerLoginScreen({super.key});

  @override
  ConsumerState<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends ConsumerState<CustomerLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    debugPrint('CustomerLoginScreen._submit: customer login submitted');

    try {
      await ref.read(authControllerProvider.notifier).loginAsRole(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            expectedRole: 'customer',
            failureMessage: 'Use the customer login for customer accounts only.',
          );
    } catch (_) {
      return;
    }

    if (!mounted) {
      return;
    }

    context.go('/app/requests');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return AuthScaffold(
      title: 'Customer Login',
      subtitle: 'Sign in to submit and track your service requests.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
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
              child: Text(authState.isSubmitting ? 'Signing in...' : 'Login'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/register'),
            child: const Text('Need an account? Register here'),
          ),
        ],
      ),
    );
  }
}
