/// WHAT: Renders the customer registration form for first-time app users.
/// WHY: Customers must have an account before they can submit or track service requests in v1.
/// HOW: Capture profile data, call the auth controller, and route into the customer request area on success.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_controller.dart';
import '../../../shared/presentation/auth_scaffold.dart';

class CustomerRegisterScreen extends ConsumerStatefulWidget {
  const CustomerRegisterScreen({super.key});

  @override
  ConsumerState<CustomerRegisterScreen> createState() =>
      _CustomerRegisterScreenState();
}

class _CustomerRegisterScreenState
    extends ConsumerState<CustomerRegisterScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    debugPrint(
      'CustomerRegisterScreen._submit: customer registration submitted',
    );

    try {
      await ref
          .read(authControllerProvider.notifier)
          .registerCustomer(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            password: _passwordController.text,
          );
      // WHY: Registration creates a reusable credential pair, so finish the autofill session to prompt Chrome to save it.
      TextInput.finishAutofillContext(shouldSave: true);
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
      title: 'Create Customer Account',
      subtitle:
          'Register first, then submit structured requests to the operations team.',
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _firstNameController,
              autofillHints: const <String>[AutofillHints.givenName],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'First name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _lastNameController,
              autofillHints: const <String>[AutofillHints.familyName],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Last name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[
                AutofillHints.newUsername,
                AutofillHints.email,
              ],
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              autofillHints: const <String>[AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofillHints: const <String>[AutofillHints.newPassword],
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
                  authState.isSubmitting ? 'Creating account...' : 'Register',
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.go('/login'),
              child: const Text('Already registered? Customer login'),
            ),
          ],
        ),
      ),
    );
  }
}
