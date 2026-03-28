/*
 * WHAT: Renders the staff login form for assigned-work access.
 * WHY: Staff members need a dedicated entry point that routes only into staff-owned work.
 * HOW: Submit shared login credentials, verify the staff role, and let the central router handle success routing.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';
import '../../../shared/presentation/auth_scaffold.dart';

class StaffLoginScreen extends ConsumerStatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  ConsumerState<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends ConsumerState<StaffLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    debugPrint('StaffLoginScreen._submit: staff login submitted');

    try {
      await ref
          .read(authControllerProvider.notifier)
          .loginAsRole(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            expectedRole: 'staff',
            failureMessage: 'Use the staff login only with a staff account.',
          );
      // WHY: Signal a successful credential submission so Chrome can offer to save the staff login.
      TextInput.finishAutofillContext(shouldSave: true);
    } catch (_) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return AuthScaffold(
      title: 'Staff Login',
      subtitle:
          'Use your invite-created account to see only the requests assigned to you.',
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[
                AutofillHints.username,
                AutofillHints.email,
              ],
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Staff email'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const <String>[AutofillHints.password],
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            if (authState.errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                authState.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: authState.isSubmitting ? null : _submit,
                child: Text(
                  authState.isSubmitting
                      ? 'Signing in...'
                      : 'Open Staff Dashboard',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
