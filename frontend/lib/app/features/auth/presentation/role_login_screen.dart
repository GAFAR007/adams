/// WHAT: Provides a reusable role-specific login experience with backend-fetched quick-fill accounts.
/// WHY: Public-facing login screens should match the same branded shell as the homepage instead of using a disconnected auth-only layout.
/// HOW: Load the backend company profile, render the login inside the shared public shell, and keep role-specific login contracts in a single screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/models/public_company_profile.dart';
import '../../../theme/app_theme.dart';
import '../../public/data/public_repository.dart';
import '../../public/presentation/public_site_shell.dart';
import '../../public/presentation/public_visuals.dart';
import '../application/auth_controller.dart';
import '../data/auth_repository.dart';
import '../domain/auth_state.dart';
import '../domain/demo_login_bundle.dart';

class RoleLoginCopy {
  const RoleLoginCopy({
    required this.pageTitle,
    required this.pageTitleDe,
    required this.eyebrow,
    required this.eyebrowDe,
    required this.headerTitle,
    required this.headerTitleDe,
    required this.headerSubtitle,
    required this.headerSubtitleDe,
    required this.emailLabel,
    required this.emailLabelDe,
    required this.submitLabel,
    required this.submitLabelDe,
    required this.failureMessage,
    required this.failureMessageDe,
    required this.heroVisualKey,
    this.footerLabel,
    this.footerLabelDe,
    this.footerRoute,
  });

  final String pageTitle;
  final String pageTitleDe;
  final String eyebrow;
  final String eyebrowDe;
  final String headerTitle;
  final String headerTitleDe;
  final String headerSubtitle;
  final String headerSubtitleDe;
  final String emailLabel;
  final String emailLabelDe;
  final String submitLabel;
  final String submitLabelDe;
  final String failureMessage;
  final String failureMessageDe;
  final String heroVisualKey;
  final String? footerLabel;
  final String? footerLabelDe;
  final String? footerRoute;

  String pageTitleFor(PublicSiteLanguage language) {
    return language == PublicSiteLanguage.german ? pageTitleDe : pageTitle;
  }

  String eyebrowFor(PublicSiteLanguage language) {
    return language == PublicSiteLanguage.german ? eyebrowDe : eyebrow;
  }

  String headerTitleFor(PublicSiteLanguage language) {
    return language == PublicSiteLanguage.german ? headerTitleDe : headerTitle;
  }

  String headerSubtitleFor(PublicSiteLanguage language) {
    return language == PublicSiteLanguage.german
        ? headerSubtitleDe
        : headerSubtitle;
  }

  String emailLabelFor(PublicSiteLanguage language) {
    return language == PublicSiteLanguage.german ? emailLabelDe : emailLabel;
  }

  String submitLabelFor(PublicSiteLanguage language) {
    return language == PublicSiteLanguage.german ? submitLabelDe : submitLabel;
  }

  String failureMessageFor(PublicSiteLanguage language) {
    return language == PublicSiteLanguage.german
        ? failureMessageDe
        : failureMessage;
  }

  String? footerLabelFor(PublicSiteLanguage language) {
    final resolved = language == PublicSiteLanguage.german
        ? footerLabelDe
        : footerLabel;
    if (resolved == null || resolved.trim().isEmpty) {
      return null;
    }

    return resolved;
  }
}

class RoleLoginScreen extends ConsumerStatefulWidget {
  const RoleLoginScreen({
    super.key,
    required this.role,
    required this.copy,
    required this.successRoute,
    required this.icon,
    this.initialLanguageCode,
  });

  final String role;
  final RoleLoginCopy copy;
  final String successRoute;
  final IconData icon;
  final String? initialLanguageCode;

  @override
  ConsumerState<RoleLoginScreen> createState() => _RoleLoginScreenState();
}

class _RoleLoginScreenState extends ConsumerState<RoleLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _hasAppliedInitialQuickFill = false;
  bool _isPasswordVisible = false;
  late PublicSiteLanguage _language;

  bool get _isGerman => _language == PublicSiteLanguage.german;

  String get _passwordLabel => _isGerman ? 'Passwort' : 'Password';
  String get _showPasswordLabel =>
      _isGerman ? 'Passwort anzeigen' : 'Show password';
  String get _hidePasswordLabel =>
      _isGerman ? 'Passwort ausblenden' : 'Hide password';
  String get _signingInLabel =>
      _isGerman ? 'Anmeldung läuft...' : 'Signing in...';
  String get _quickFillTitle =>
      _isGerman ? 'Schnellzugriffe' : 'Quick fill accounts';
  String get _quickFillIntro => _isGerman
      ? 'Nutzen Sie vorhandene Testkonten oder gehen Sie von hier direkt zum passenden Einstieg.'
      : 'Use seeded shortcut accounts when available, or jump straight to the right entry point from here.';
  String get _loadingQuickFillLabel =>
      _isGerman ? 'Schnellzugriffe laden' : 'Loading quick fill accounts';
  String get _quickFillErrorLabel => _isGerman
      ? 'Backend-Konten konnten gerade nicht geladen werden.'
      : 'Unable to load quick fill accounts from the backend right now.';
  String get _manualPasswordLabel =>
      _isGerman ? 'Passwort manuell eingeben' : 'Enter password manually';
  String get _seededPasswordReadyLabel =>
      _isGerman ? 'Passwort hinterlegt' : 'Seeded password ready';
  String get _seededPasswordHint => _isGerman
      ? 'Seed-Konten können in dieser Umgebung ihr Passwort automatisch ergänzen, wenn es vom Backend bereitgestellt wird.'
      : 'Seeded accounts can autofill their password in this environment when available from the backend.';
  String get _secureAccessTitle =>
      _isGerman ? 'Sicherer Zugang' : 'Secure access';
  String get _secureAccessSubtitle => _isGerman
      ? 'Rollenbasiertes Login im gleichen visuellen Stil wie die öffentliche Website.'
      : 'Role-based sign-in styled to match the public website experience.';
  String get _highlightsTitle =>
      _isGerman ? 'Wofür dieser Zugang ist' : 'What this access is for';
  String get _highlightsSubtitle => _isGerman
      ? 'Die Oberfläche bleibt nah am öffentlichen Auftritt, der Zugang führt aber direkt in den richtigen Arbeitsbereich.'
      : 'The look stays close to the public site while the access route still lands in the correct workspace.';
  String get _backHomeLabel =>
      _isGerman ? 'Zur Startseite' : 'Back to homepage';
  String get _noQuickFillTitle =>
      _isGerman ? 'Kein Schnellzugriff verfügbar' : 'No quick fill accounts';
  String get _customerNoQuickFillBody => _isGerman
      ? 'Kundenzugänge werden in dieser Umgebung über den Service-Chat erstellt. Starten Sie dort Ihre erste Buchung.'
      : 'Customer access is created through the service chat in this environment. Start there for a first booking.';
  String get _staffAdminNoQuickFillBody => _isGerman
      ? 'Für diese Rolle stehen gerade keine hinterlegten Testkonten bereit.'
      : 'No backend-backed shortcut accounts are available for this role right now.';
  String get _fallbackSubtitle => _isGerman
      ? 'Öffentliche Profildaten konnten gerade nicht geladen werden. Die Anmeldung bleibt trotzdem verfügbar.'
      : 'Public profile data could not be loaded right now, but sign-in is still available.';

  @override
  void initState() {
    super.initState();
    final initialCode = widget.initialLanguageCode;
    _language = initialCode == null || initialCode.trim().isEmpty
        ? ref.read(appLanguageProvider)
        : publicSiteLanguageFromCode(initialCode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(appLanguageProvider.notifier).setLanguage(_language);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _routeWithLanguage(String path) {
    final code = publicSiteLanguageCode(_language);
    return code == 'de' ? '$path?lang=de' : path;
  }

  PublicPageVisualData get _heroVisualData {
    switch (widget.copy.heroVisualKey) {
      case 'about':
      case 'contact':
      case 'legal':
      case 'services':
        return publicPageVisualForKey(widget.copy.heroVisualKey);
      default:
        return publicPageVisualForKey('about');
    }
  }

  void _applyQuickFillAccount(DemoLoginAccount account) {
    _emailController.text = account.email;
    _passwordController.text = account.quickFillPassword ?? '';
    setState(() {});
  }

  String _quickFillRoleLabel(DemoLoginAccount account) {
    switch (account.staffType) {
      case 'customer_care':
        return _isGerman ? 'Customer Care' : 'Customer Care';
      case 'technician':
        return _isGerman ? 'Techniker' : 'Technician';
      case 'contractor':
        return _isGerman ? 'Auftragnehmer' : 'Contractor';
    }

    switch (account.role) {
      case 'admin':
        return _isGerman ? 'Admin' : 'Admin';
      case 'customer':
        return _isGerman ? 'Kunde' : 'Customer';
      case 'staff':
        return _isGerman ? 'Mitarbeiter' : 'Staff';
      default:
        return _isGerman ? 'Benutzer' : 'User';
    }
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
            failureMessage: widget.copy.failureMessageFor(_language),
          );

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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Color.lerp(Colors.white, AppTheme.sand, 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected
              ? AppTheme.cobalt
              : AppTheme.clay.withValues(alpha: 0.72),
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: isSelected
            ? <BoxShadow>[
                BoxShadow(
                  color: AppTheme.cobalt.withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _applyQuickFillAccount(account),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        account.fullName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.cobalt,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _quickFillRoleLabel(account),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppTheme.cobalt,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  account.email,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.ink.withValues(alpha: 0.72),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  account.quickFillPassword == null
                      ? _manualPasswordLabel
                      : _seededPasswordReadyLabel,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: account.quickFillPassword == null
                        ? AppTheme.ember
                        : AppTheme.pine,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickFillContent(
    BuildContext context,
    AsyncValue<DemoLoginBundle> demoAccountsAsync,
  ) {
    final footerLabel = widget.copy.footerLabelFor(_language);

    return demoAccountsAsync.when(
      data: (bundle) {
        if (bundle.accounts.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _noQuickFillTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                widget.role == 'customer'
                    ? _customerNoQuickFillBody
                    : _staffAdminNoQuickFillBody,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.55),
              ),
              if (widget.copy.footerRoute != null &&
                  footerLabel != null) ...<Widget>[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.go(_routeWithLanguage(widget.copy.footerRoute!)),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(footerLabel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.cobalt,
                    side: BorderSide(
                      color: AppTheme.cobalt.withValues(alpha: 0.24),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
              ],
            ],
          );
        }

        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: bundle.accounts
              .map((account) {
                final isSelected =
                    _emailController.text.trim().toLowerCase() ==
                    account.email.toLowerCase();

                return SizedBox(
                  width: 240,
                  child: _buildQuickFillTile(context, account, isSelected),
                );
              })
              .toList(growable: false),
        );
      },
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _loadingQuickFillLabel,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          const LinearProgressIndicator(minHeight: 3),
        ],
      ),
      error: (error, stackTrace) => Text(
        _quickFillErrorLabel,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.55),
      ),
    );
  }

  Widget _buildFormCard(BuildContext context, AuthState authState) {
    final footerLabel = widget.copy.footerLabelFor(_language);

    return PublicSurfaceCard(
      title: widget.copy.headerTitleFor(_language),
      subtitle: widget.copy.headerSubtitleFor(_language),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color.lerp(Colors.white, AppTheme.cobalt, 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Icon(widget.icon, color: AppTheme.cobalt, size: 24),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _secureAccessTitle,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _secureAccessSubtitle,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(height: 1.5),
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
                labelText: widget.copy.emailLabelFor(_language),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: !_isPasswordVisible,
              autofillHints: const <String>[AutofillHints.password],
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: _passwordLabel,
                suffixIcon: IconButton(
                  tooltip: _isPasswordVisible
                      ? _hidePasswordLabel
                      : _showPasswordLabel,
                  onPressed: () {
                    setState(() {
                      _isPasswordVisible = !_isPasswordVisible;
                    });
                  },
                  icon: Icon(
                    _isPasswordVisible
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Color.lerp(Colors.white, AppTheme.sand, 0.6),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                _seededPasswordHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.ink.withValues(alpha: 0.72),
                  height: 1.45,
                ),
              ),
            ),
            if (authState.errorMessage != null) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.errorContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  authState.errorMessage!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: authState.isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.cobalt,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  authState.isSubmitting
                      ? _signingInLabel
                      : widget.copy.submitLabelFor(_language),
                ),
              ),
            ),
            if (widget.copy.footerRoute != null &&
                footerLabel != null) ...<Widget>[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      context.go(_routeWithLanguage(widget.copy.footerRoute!)),
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(footerLabel),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.cobalt,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightsCard(BuildContext context) {
    final items = switch (widget.role) {
      'customer' =>
        _isGerman
            ? const <String>[
                'Anfragen, Rückmeldungen und Dateiuploads an einem Ort verfolgen',
                'Sehen, wann ein Mitarbeitender Ihre Anfrage übernimmt',
                'Mit Ihrem Service-Postfach verbunden bleiben',
              ]
            : const <String>[
                'Track requests, replies, and file uploads in one place',
                'See when a staff member picks up your queue',
                'Stay connected to your service inbox',
              ],
      'staff' =>
        _isGerman
            ? const <String>[
                'Wartende Kunden direkt aus der Queue übernehmen',
                'Live im Thread antworten und Dateien teilen',
                'Eigene Arbeitslast und Status kompakt steuern',
              ]
            : const <String>[
                'Pick up waiting customers directly from the queue',
                'Reply in live threads and share files immediately',
                'Manage assigned workload and status in one place',
              ],
      _ =>
        _isGerman
            ? const <String>[
                'Queue, Einladungen und Teamübergaben zentral steuern',
                'Live-Anfragen, Staff-Last und interne Chats überblicken',
                'Operative Kontrolle ohne zwischen Tools zu springen',
              ]
            : const <String>[
                'Manage queue flow, invites, and team handoff centrally',
                'Monitor live requests, staff load, and internal chats',
                'Keep operations control without jumping between tools',
              ],
    };

    return PublicSurfaceCard(
      title: _highlightsTitle,
      subtitle: _highlightsSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PublicBulletList(items: items),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              PublicTagChip(
                text: _isGerman ? 'Sicherer Zugang' : 'Secure access',
                icon: Icons.lock_outline_rounded,
                backgroundColor: const Color(0xFFE7EEF9),
                foregroundColor: AppTheme.cobalt,
              ),
              PublicTagChip(
                text: _isGerman ? 'Live verbunden' : 'Live connected',
                icon: Icons.wifi_tethering_rounded,
                backgroundColor: const Color(0xFFE7F4EE),
                foregroundColor: AppTheme.pine,
              ),
              PublicTagChip(
                text: _isGerman ? 'Rollenbasiert' : 'Role-based',
                icon: Icons.verified_user_outlined,
                backgroundColor: const Color(0xFFF3EBDD),
                foregroundColor: AppTheme.ember,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedLayout(
    BuildContext context,
    PublicCompanyProfileModel profile,
    AuthState authState,
    AsyncValue<DemoLoginBundle> demoAccountsAsync,
  ) {
    final heroVisual = _heroVisualData;

    return PublicSiteShell(
      profile: profile,
      language: _language,
      onLanguageChanged: (language) {
        setState(() => _language = language);
        ref.read(appLanguageProvider.notifier).setLanguage(language);
      },
      activeItem: PublicNavItem.none,
      eyebrow: widget.copy.eyebrowFor(_language),
      pageTitle: widget.copy.pageTitleFor(_language),
      pageSubtitle: widget.copy.headerSubtitleFor(_language),
      heroVisual: PublicImageCard(
        imageUrl: heroVisual.imageUrl,
        eyebrow: resolvePublicText(heroVisual.kicker, _language),
        title: widget.copy.headerTitleFor(_language),
        subtitle: resolvePublicText(heroVisual.supportingLine, _language),
        aspectRatio: 16 / 11,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 980;
          final formCard = PublicReveal(
            delay: const Duration(milliseconds: 90),
            child: _buildFormCard(context, authState),
          );
          final quickFillCard = PublicReveal(
            delay: const Duration(milliseconds: 140),
            child: PublicSurfaceCard(
              title: _quickFillTitle,
              subtitle: _quickFillIntro,
              child: _buildQuickFillContent(context, demoAccountsAsync),
            ),
          );
          final highlightsCard = PublicReveal(
            delay: const Duration(milliseconds: 190),
            child: _buildHighlightsCard(context),
          );

          if (isCompact) {
            return Column(
              children: <Widget>[
                formCard,
                const SizedBox(height: 18),
                quickFillCard,
                const SizedBox(height: 18),
                highlightsCard,
              ],
            );
          }

          return Column(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 7, child: formCard),
                  const SizedBox(width: 18),
                  Expanded(flex: 5, child: quickFillCard),
                ],
              ),
              const SizedBox(height: 18),
              highlightsCard,
            ],
          );
        },
      ),
    );
  }

  Widget _buildFallbackLayout(
    BuildContext context,
    AuthState authState,
    AsyncValue<DemoLoginBundle> demoAccountsAsync,
  ) {
    return Scaffold(
      backgroundColor: AppTheme.sand,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color.lerp(AppTheme.cobalt, AppTheme.ink, 0.18)!,
              Color.lerp(AppTheme.sand, Colors.white, 0.22)!,
              AppTheme.sand,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const <double>[0, 0.34, 1],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: () => context.go(_routeWithLanguage('/')),
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: Text(_backHomeLabel),
                    ),
                    const SizedBox(height: 14),
                    _buildFormCard(context, authState),
                    const SizedBox(height: 18),
                    PublicSurfaceCard(
                      title: _quickFillTitle,
                      subtitle: _fallbackSubtitle,
                      child: _buildQuickFillContent(context, demoAccountsAsync),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final demoAccountsAsync = ref.watch(authDemoAccountsProvider(widget.role));
    final publicProfileAsync = ref.watch(publicCompanyProfileProvider);

    ref.listen<AsyncValue<DemoLoginBundle>>(
      authDemoAccountsProvider(widget.role),
      (previous, next) {
        next.whenData((bundle) {
          if (_hasAppliedInitialQuickFill || bundle.accounts.isEmpty) {
            return;
          }

          final firstAccount = bundle.accounts.first;
          if (_emailController.text.isEmpty) {
            _emailController.text = firstAccount.email;
          }
          if (_passwordController.text.isEmpty &&
              firstAccount.quickFillPassword != null) {
            _passwordController.text = firstAccount.quickFillPassword!;
          }

          _hasAppliedInitialQuickFill = true;
        });
      },
    );

    return publicProfileAsync.when(
      data: (profile) =>
          _buildLoadedLayout(context, profile, authState, demoAccountsAsync),
      loading: () => const _RoleLoginLoadingScreen(),
      error: (error, stackTrace) =>
          _buildFallbackLayout(context, authState, demoAccountsAsync),
    );
  }
}

class _RoleLoginLoadingScreen extends StatelessWidget {
  const _RoleLoginLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.sand,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color.lerp(AppTheme.cobalt, AppTheme.ink, 0.18)!,
              Color.lerp(AppTheme.sand, Colors.white, 0.22)!,
              AppTheme.sand,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const <double>[0, 0.34, 1],
          ),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppTheme.cobalt),
        ),
      ),
    );
  }
}
