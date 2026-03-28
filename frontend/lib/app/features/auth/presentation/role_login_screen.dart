/// WHAT: Provides a reusable role-specific login experience with backend-fetched quick-fill accounts.
/// WHY: Admin, staff, and customer login screens should share the same layout while keeping role labels and routing distinct.
/// HOW: Fetch role demo accounts, auto-fill the first seeded shortcut when available, and submit through the shared auth controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/app_theme.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import '../domain/demo_login_bundle.dart';

class RoleLoginScreen extends ConsumerStatefulWidget {
  const RoleLoginScreen({
    super.key,
    required this.role,
    required this.pageTitle,
    required this.headerTitle,
    required this.headerSubtitle,
    required this.emailLabel,
    required this.submitLabel,
    required this.failureMessage,
    required this.successRoute,
    required this.icon,
    this.footer,
  });

  final String role;
  final String pageTitle;
  final String headerTitle;
  final String headerSubtitle;
  final String emailLabel;
  final String submitLabel;
  final String failureMessage;
  final String successRoute;
  final IconData icon;
  final Widget? footer;

  @override
  ConsumerState<RoleLoginScreen> createState() => _RoleLoginScreenState();
}

class _RoleLoginScreenState extends ConsumerState<RoleLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hasAppliedInitialQuickFill = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _applyQuickFillAccount(DemoLoginAccount account) {
    // WHY: Keep quick-fill behavior explicit and local so tapping an account always hydrates both credentials together.
    _emailController.text = account.email;
    if (account.quickFillPassword != null) {
      _passwordController.text = account.quickFillPassword!;
    }
    setState(() {});
  }

  Future<void> _submit() async {
    debugPrint('RoleLoginScreen._submit: login submitted for ${widget.role}');

    try {
      await ref
          .read(authControllerProvider.notifier)
          .loginAsRole(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            expectedRole: widget.role,
            failureMessage: widget.failureMessage,
          );

      // WHY: Signal a successful credential submission so the browser can offer to save the role-specific login.
      TextInput.finishAutofillContext(shouldSave: true);
    } catch (_) {
      return;
    }

    if (!mounted) {
      return;
    }

    context.go(widget.successRoute);
  }

  Widget _buildQuickFillTile(
    BuildContext context,
    DemoLoginAccount account,
    bool isSelected,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _applyQuickFillAccount(account),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected
                ? AppTheme.cobalt
                : AppTheme.clay.withValues(alpha: 0.75),
            width: isSelected ? 1.3 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                account.fullName,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(account.email, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickFillPanel(
    BuildContext context,
    AsyncValue<DemoLoginBundle> demoAccountsAsync,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE9F0FB),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: demoAccountsAsync.when(
          data: (bundle) {
            if (bundle.accounts.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Quick fill accounts',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No seeded quick-fill accounts are available for this role right now.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Quick fill accounts',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  bundle.passwordAutofillEnabled
                      ? 'Tap a backend account to autofill email and password in this environment.'
                      : 'Backend accounts are listed here, but password autofill is disabled in this environment.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: bundle.accounts.map((account) {
                    final isSelected =
                        _emailController.text.trim().toLowerCase() ==
                        account.email.toLowerCase();

                    return SizedBox(
                      width: 240,
                      child: _buildQuickFillTile(context, account, isSelected),
                    );
                  }).toList(),
                ),
              ],
            );
          },
          loading: () => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Quick fill accounts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ),
          error: (error, stackTrace) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Quick fill accounts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Unable to load quick fill accounts from the backend right now.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final demoAccountsAsync = ref.watch(authDemoAccountsProvider(widget.role));

    ref.listen<
      AsyncValue<DemoLoginBundle>
    >(authDemoAccountsProvider(widget.role), (previous, next) {
      next.whenData((bundle) {
        if (_hasAppliedInitialQuickFill || bundle.accounts.isEmpty) {
          return;
        }

        final firstAccount = bundle.accounts.first;

        // WHY: Seed the first backend-backed shortcut once so local demo login feels immediate without hardcoded UI values.
        if (_emailController.text.isEmpty) {
          _emailController.text = firstAccount.email;
        }
        if (_passwordController.text.isEmpty &&
            firstAccount.quickFillPassword != null) {
          _passwordController.text = firstAccount.quickFillPassword!;
        }

        _hasAppliedInitialQuickFill = true;
      });
    });

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFFF4F7FC),
              Color(0xFFE9F0FB),
              Color(0xFFF6F0E6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1160),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            IconButton(
                              onPressed: () => context.go('/'),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.pageTitle,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(34),
                            border: Border.all(
                              color: AppTheme.sand.withValues(alpha: 0.7),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: AutofillGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      DecoratedBox(
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFDCE7FF),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Icon(
                                            widget.icon,
                                            color: AppTheme.cobalt,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Text(
                                              widget.headerTitle,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.headlineSmall,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              widget.headerSubtitle,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),
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
                                    decoration: InputDecoration(
                                      labelText: widget.emailLabel,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _passwordController,
                                    obscureText: true,
                                    autofillHints: const <String>[
                                      AutofillHints.password,
                                    ],
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _submit(),
                                    decoration: const InputDecoration(
                                      labelText: 'Password',
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    'Seeded accounts can autofill their password in this environment when available from the backend.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppTheme.ink.withValues(
                                            alpha: 0.6,
                                          ),
                                        ),
                                  ),
                                  if (authState.errorMessage !=
                                      null) ...<Widget>[
                                    const SizedBox(height: 14),
                                    Text(
                                      authState.errorMessage!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: <Color>[
                                            Color(0xFF8FD6E6),
                                            Color(0xFFA6DA74),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 18,
                                          ),
                                        ),
                                        onPressed: authState.isSubmitting
                                            ? null
                                            : _submit,
                                        child: Text(
                                          authState.isSubmitting
                                              ? 'Signing in...'
                                              : widget.submitLabel,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (widget.footer != null) ...<Widget>[
                                    const SizedBox(height: 14),
                                    widget.footer!,
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildQuickFillPanel(context, demoAccountsAsync),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
