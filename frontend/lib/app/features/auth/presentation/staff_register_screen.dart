/// WHAT: Renders the invite-based staff registration form.
/// WHY: Staff onboarding is invite-only, so this screen must consume the invite token route parameter.
/// HOW: Collect the remaining staff profile details, submit the invite token, and route into `/staff` on success.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/auth_controller.dart';
import '../../../shared/presentation/auth_scaffold.dart';

class StaffRegisterScreen extends ConsumerStatefulWidget {
  const StaffRegisterScreen({super.key, required this.inviteToken});

  final String inviteToken;

  @override
  ConsumerState<StaffRegisterScreen> createState() =>
      _StaffRegisterScreenState();
}

class _StaffRegisterScreenState extends ConsumerState<StaffRegisterScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  String? _formErrorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    debugPrint(
      'StaffRegisterScreen._submit: staff invite registration submitted',
    );

    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (password.length < 8) {
      setState(() {
        _formErrorMessage = 'Password must be at least 8 characters.';
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _formErrorMessage = 'Passwords do not match.';
      });
      return;
    }

    setState(() {
      _formErrorMessage = null;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .registerStaff(
            inviteToken: widget.inviteToken,
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            phone: _phoneController.text.trim(),
            password: password,
          );
      // WHY: Invite completion ends with a fresh credential pair that Chrome can reuse on the staff login page.
      TextInput.finishAutofillContext(shouldSave: true);
    } catch (_) {
      return;
    }

    if (!mounted) {
      return;
    }

    context.go('/staff');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return AuthScaffold(
      title: 'Staff Invite Registration',
      subtitle: 'Complete the invite flow to activate your staff account.',
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
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              autofillHints: const <String>[AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              autofillHints: const <String>[AutofillHints.newPassword],
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Create password',
                suffixIcon: IconButton(
                  tooltip: _isPasswordVisible
                      ? 'Hide password'
                      : 'Show password',
                  onPressed: () {
                    setState(() => _isPasswordVisible = !_isPasswordVisible);
                  },
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              obscureText: !_isConfirmPasswordVisible,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Confirm password',
                suffixIcon: IconButton(
                  tooltip: _isConfirmPasswordVisible
                      ? 'Hide password'
                      : 'Show password',
                  onPressed: () {
                    setState(() {
                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                    });
                  },
                  icon: Icon(
                    _isConfirmPasswordVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Invite token attached to this route. If this link expires, ask the admin for a new one.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_formErrorMessage != null ||
                authState.errorMessage != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                _formErrorMessage ?? authState.errorMessage!,
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
                      ? 'Activating...'
                      : 'Activate Staff Account',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
