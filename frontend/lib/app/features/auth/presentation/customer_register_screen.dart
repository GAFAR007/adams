/// WHAT: Renders the customer registration form for first-time app users.
/// WHY: Customers must have an account before they can submit or track service requests in v1.
/// HOW: Capture profile data, call the auth controller, and route into the customer request area on success.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
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
  final _verificationCodeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isSendingVerificationCode = false;
  bool _isVerifyingEmail = false;
  bool _hasRequestedVerificationCode = false;
  bool _isEmailVerified = false;
  String? _formErrorMessage;
  String? _verificationMessage;
  String _verifiedEmail = '';
  String _verificationToken = '';

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _verificationCodeController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _resetEmailVerificationState({bool keepMessage = false}) {
    _verificationCodeController.clear();
    _hasRequestedVerificationCode = false;
    _isEmailVerified = false;
    _verifiedEmail = '';
    _verificationToken = '';
    if (!keepMessage) {
      _verificationMessage = null;
    }
  }

  Future<void> _sendVerificationCode() async {
    if (_isSendingVerificationCode || _isVerifyingEmail) {
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!validEmail) {
      setState(() {
        _formErrorMessage = 'Enter a valid email before requesting a code.';
      });
      return;
    }

    setState(() {
      _formErrorMessage = null;
      _verificationMessage = null;
      _isSendingVerificationCode = true;
    });

    try {
      await ref
          .read(authRepositoryProvider)
          .requestCustomerRegistrationCode(email: email);

      if (!mounted) {
        return;
      }

      setState(() {
        _hasRequestedVerificationCode = true;
        _verificationMessage = 'We sent a 6-digit verification code to $email.';
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _formErrorMessage = error.resolutionHint?.trim().isNotEmpty == true
            ? '${error.message}. ${error.resolutionHint}'
            : error.message;
        _verificationMessage =
            error.errorCode == 'CUSTOMER_REGISTER_EMAIL_TAKEN'
            ? 'This email already has an account. Log in instead. If you no longer have the password, request a password reset from support.'
            : null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _formErrorMessage =
            'We could not send the verification code right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSendingVerificationCode = false;
        });
      }
    }
  }

  Future<void> _verifyEmailCode() async {
    if (_isEmailVerified || _isVerifyingEmail) {
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    final code = _verificationCodeController.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() {
        _formErrorMessage = 'Enter the 6-digit code from your email.';
      });
      return;
    }

    setState(() {
      _formErrorMessage = null;
      _verificationMessage = null;
      _isVerifyingEmail = true;
    });

    try {
      final verificationToken = await ref
          .read(authRepositoryProvider)
          .verifyCustomerRegistrationCode(email: email, code: code);

      if (!mounted) {
        return;
      }

      setState(() {
        _verificationToken = verificationToken;
        _verifiedEmail = email;
        _isEmailVerified = true;
        _verificationMessage =
            'Email verified. You can finish registration now.';
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _formErrorMessage = error.resolutionHint?.trim().isNotEmpty == true
            ? '${error.message}. ${error.resolutionHint}'
            : error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _formErrorMessage = 'We could not verify that code right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVerifyingEmail = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    debugPrint(
      'CustomerRegisterScreen._submit: customer registration submitted',
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

    final normalizedEmail = _emailController.text.trim().toLowerCase();
    if (!_isEmailVerified ||
        _verificationToken.isEmpty ||
        _verifiedEmail != normalizedEmail) {
      setState(() {
        _formErrorMessage =
            'Verify your email with the 6-digit code before registering.';
      });
      return;
    }

    setState(() {
      _formErrorMessage = null;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .registerCustomer(
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            password: password,
            verificationToken: _verificationToken,
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
              onChanged: (value) {
                final normalizedValue = value.trim().toLowerCase();
                if (normalizedValue != _verifiedEmail || _isEmailVerified) {
                  setState(() {
                    _resetEmailVerificationState();
                  });
                }
              },
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: _isSendingVerificationCode
                        ? null
                        : _sendVerificationCode,
                    child: Text(
                      _isSendingVerificationCode
                          ? 'Sending code...'
                          : _hasRequestedVerificationCode
                          ? 'Resend code'
                          : 'Send verification code',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _verificationCodeController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    enabled: !_isEmailVerified,
                    decoration: InputDecoration(
                      labelText: 'Email verification code',
                      helperText: _isEmailVerified
                          ? 'This email is verified.'
                          : 'Use the 6-digit code sent to your email.',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed:
                      !_hasRequestedVerificationCode ||
                          _isEmailVerified ||
                          _isVerifyingEmail
                      ? null
                      : _verifyEmailCode,
                  child: Text(
                    _isVerifyingEmail ? 'Checking...' : 'Verify email',
                  ),
                ),
              ],
            ),
            if (_verificationMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _verificationMessage!,
                style: TextStyle(
                  color: _isEmailVerified ? Colors.green.shade700 : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
                labelText: 'Password',
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
                  authState.isSubmitting ? 'Creating account...' : 'Register',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                TextButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Already registered? Customer login'),
                ),
                if ((_verificationMessage ?? '').contains(
                  'already has an account',
                ))
                  Text(
                    'Use login instead if this email is already registered.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
