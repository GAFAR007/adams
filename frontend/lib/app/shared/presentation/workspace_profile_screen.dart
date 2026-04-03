library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_language.dart';
import '../../core/models/auth_user.dart';
import '../../core/models/service_request_model.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/staff/data/staff_repository.dart';
import '../../theme/app_theme.dart';
import 'app_language_toggle.dart';
import 'workspace_profile_action_button.dart';

enum WorkspaceProfileScope { customer, admin, staff }

final _staffProfileTodayRequestsProvider = FutureProvider.autoDispose
    .family<List<ServiceRequestModel>, String>((Ref ref, String userId) async {
      if (userId.trim().isEmpty) {
        return const <ServiceRequestModel>[];
      }

      final today = _profileDateOnly(DateTime.now().toLocal());
      final formattedToday = _formatProfileApiDate(today);
      final requests = await ref
          .watch(staffRepositoryProvider)
          .fetchCalendarRequests(start: formattedToday, end: formattedToday);

      final visibleRequests =
          requests
              .where(
                (request) =>
                    request.assignedStaff?.id == userId &&
                    _requestOccursOnProfileDay(request, today) &&
                    request.status != 'closed',
              )
              .toList()
            ..sort(_compareProfileScheduleRequests);

      return visibleRequests;
    });

class WorkspaceProfileScreen extends ConsumerWidget {
  const WorkspaceProfileScreen({super.key, required this.scope});

  final WorkspaceProfileScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final language = ref.watch(appLanguageProvider);
    final user = authState.user;
    final dark = scope != WorkspaceProfileScope.customer;

    if (!authState.hasBootstrapped ||
        authState.isBootstrapping ||
        user == null) {
      return Scaffold(
        backgroundColor: dark ? AppTheme.darkPage : AppTheme.sand,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final backRoute = _workspaceRoute(scope);
    final exactRoleLabel = _roleLabel(language, user);
    final title = _screenTitle(language, scope, user);
    final subtitle = _screenSubtitle(language, scope, user);
    final statusTone = _statusTone(user.status, dark: dark);
    final initials = _initialsFor(user);
    final gradientColors = dark
        ? <Color>[
            AppTheme.darkPage,
            AppTheme.darkSurface,
            AppTheme.darkPageRaised,
          ]
        : <Color>[
            Color.lerp(AppTheme.sand, AppTheme.mist, 0.58)!,
            Color.lerp(AppTheme.sand, AppTheme.shellRaised, 0.86)!,
            AppTheme.shell,
          ];

    return Scaffold(
      backgroundColor: gradientColors.first,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: gradientColors.first,
        foregroundColor: dark ? AppTheme.darkText : AppTheme.ink,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        leading: IconButton(
          tooltip: _t(
            language,
            en: 'Back to workspace',
            de: 'Zuruck zum Bereich',
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: () => context.go(backRoute),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: <Widget>[
          WorkspaceCalendarActionButton(
            tooltip: _t(language, en: 'Calendar', de: 'Kalender'),
            onPressed: () => context.go(_calendarRoute(scope)),
            dark: dark,
          ),
          AppLanguageToggle(
            language: language,
            onChanged: ref.read(appLanguageProvider.notifier).setLanguage,
            dark: dark,
            compact: true,
          ),
          WorkspaceLogoutActionButton(
            tooltip: _t(language, en: 'Logout', de: 'Abmelden'),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                context.go('/');
              }
            },
            dark: dark,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _ProfileHeroCard(
                      dark: dark,
                      initials: initials,
                      name: user.fullName.trim().isEmpty
                          ? _fallbackName(language, scope, user)
                          : user.fullName,
                      subtitle: subtitle,
                      roleLabel: exactRoleLabel,
                      statusLabel: _statusLabel(language, user.status),
                      statusTone: statusTone,
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints constraints) {
                        final wide = constraints.maxWidth >= 860;
                        final children = <Widget>[
                          _ProfileSectionCard(
                            dark: dark,
                            title: _t(language, en: 'Contact', de: 'Kontakt'),
                            subtitle: _t(
                              language,
                              en: 'The account details currently attached to this workspace.',
                              de: 'Die Kontaktdaten, die aktuell mit diesem Arbeitsbereich verknupft sind.',
                            ),
                            child: Column(
                              children: <Widget>[
                                _ProfileInfoRow(
                                  dark: dark,
                                  icon: Icons.mail_outline_rounded,
                                  label: _t(
                                    language,
                                    en: 'Email',
                                    de: 'E-Mail',
                                  ),
                                  value: user.email,
                                ),
                                const SizedBox(height: 12),
                                _ProfileInfoRow(
                                  dark: dark,
                                  icon: Icons.call_outlined,
                                  label: _t(
                                    language,
                                    en: 'Phone',
                                    de: 'Telefon',
                                  ),
                                  value: (user.phone ?? '').trim().isEmpty
                                      ? _t(
                                          language,
                                          en: 'Not provided yet',
                                          de: 'Noch nicht hinterlegt',
                                        )
                                      : user.phone!,
                                ),
                              ],
                            ),
                          ),
                          _ProfileSectionCard(
                            dark: dark,
                            title: _t(language, en: 'Account', de: 'Konto'),
                            subtitle: _t(
                              language,
                              en: 'Role and session information for this signed-in user.',
                              de: 'Rollen- und Sitzungsinformationen fur diesen angemeldeten Benutzer.',
                            ),
                            child: Column(
                              children: <Widget>[
                                _ProfileInfoRow(
                                  dark: dark,
                                  icon: Icons.badge_outlined,
                                  label: _t(language, en: 'Role', de: 'Rolle'),
                                  value: exactRoleLabel,
                                ),
                                const SizedBox(height: 12),
                                _ProfileInfoRow(
                                  dark: dark,
                                  icon: Icons.verified_user_outlined,
                                  label: _t(
                                    language,
                                    en: 'Status',
                                    de: 'Status',
                                  ),
                                  value: _statusLabel(language, user.status),
                                  tone: statusTone,
                                ),
                                const SizedBox(height: 12),
                                _ProfileInfoRow(
                                  dark: dark,
                                  icon: Icons.fingerprint_rounded,
                                  label: _t(
                                    language,
                                    en: 'User ID',
                                    de: 'Benutzer-ID',
                                  ),
                                  value: user.id,
                                ),
                              ],
                            ),
                          ),
                        ];

                        if (!wide) {
                          return Column(
                            children: <Widget>[
                              children[0],
                              const SizedBox(height: 16),
                              children[1],
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(child: children[0]),
                            const SizedBox(width: 16),
                            Expanded(child: children[1]),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    if (_supportsProfileClocking(scope, user)) ...<Widget>[
                      _ProfileTodayClockSection(
                        dark: dark,
                        language: language,
                        user: user,
                      ),
                      const SizedBox(height: 18),
                    ],
                    _ProfileSectionCard(
                      dark: dark,
                      title: _t(
                        language,
                        en: 'Workspace',
                        de: 'Arbeitsbereich',
                      ),
                      subtitle: _t(
                        language,
                        en: 'Jump back into your main workspace or close this session.',
                        de: 'Wechseln Sie direkt zuruck in Ihren Bereich oder melden Sie sich ab.',
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: () => context.go(backRoute),
                            style: FilledButton.styleFrom(
                              backgroundColor: dark
                                  ? AppTheme.darkAccent
                                  : AppTheme.cobalt,
                              foregroundColor: dark
                                  ? AppTheme.darkPage
                                  : Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                            ),
                            icon: const Icon(Icons.dashboard_customize_rounded),
                            label: Text(
                              _t(
                                language,
                                en: 'Open workspace',
                                de: 'Bereich offnen',
                              ),
                            ),
                          ),
                          if (scope == WorkspaceProfileScope.customer)
                            OutlinedButton.icon(
                              onPressed: () => context.go('/app/requests/new'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: dark
                                    ? AppTheme.darkText
                                    : AppTheme.ink,
                                side: BorderSide(
                                  color: dark
                                      ? AppTheme.darkBorderStrong
                                      : AppTheme.borderStrong,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                              ),
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                              ),
                              label: Text(
                                _t(
                                  language,
                                  en: 'Create request',
                                  de: 'Anfrage erstellen',
                                ),
                              ),
                            ),
                          TextButton.icon(
                            onPressed: () async {
                              await ref
                                  .read(authControllerProvider.notifier)
                                  .logout();
                              if (context.mounted) {
                                context.go('/');
                              }
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: dark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.textMuted,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                            ),
                            icon: const Icon(Icons.logout_rounded),
                            label: Text(
                              _t(language, en: 'Logout', de: 'Abmelden'),
                            ),
                          ),
                        ],
                      ),
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
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.dark,
    required this.initials,
    required this.name,
    required this.subtitle,
    required this.roleLabel,
    required this.statusLabel,
    required this.statusTone,
  });

  final bool dark;
  final String initials;
  final String name;
  final String subtitle;
  final String roleLabel;
  final String statusLabel;
  final AppTone statusTone;

  @override
  Widget build(BuildContext context) {
    final surfaceColor = dark ? AppTheme.darkSurfaceRaised : AppTheme.shell;
    final borderColor = dark ? AppTheme.darkBorder : AppTheme.border;
    final titleColor = dark ? AppTheme.darkText : AppTheme.ink;
    final subtitleColor = dark ? AppTheme.darkTextMuted : AppTheme.textMuted;
    final avatarBackground = dark
        ? AppTheme.darkAccentSurface
        : AppTheme.accentSurface;
    final avatarForeground = dark ? AppTheme.darkAccent : AppTheme.cobalt;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: dark
                ? Colors.black.withValues(alpha: 0.18)
                : AppTheme.ink.withValues(alpha: 0.07),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: avatarBackground,
                shape: BoxShape.circle,
                border: Border.all(
                  color: dark ? AppTheme.darkBorderStrong : AppTheme.border,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: avatarForeground,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: subtitleColor),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      _ProfileBadge(
                        label: roleLabel,
                        backgroundColor: dark
                            ? AppTheme.darkAccentSurface
                            : AppTheme.accentSurface,
                        foregroundColor: dark
                            ? AppTheme.darkAccent
                            : AppTheme.cobalt,
                        borderColor: dark
                            ? AppTheme.darkBorderStrong
                            : AppTheme.border,
                      ),
                      _ProfileBadge(
                        label: statusLabel,
                        backgroundColor: statusTone.background,
                        foregroundColor: statusTone.foreground,
                        borderColor: statusTone.border,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({
    required this.dark,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final bool dark;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? AppTheme.darkSurface : AppTheme.shell,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: dark ? AppTheme.darkBorder : AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: dark ? AppTheme.darkText : AppTheme.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: dark ? AppTheme.darkTextMuted : AppTheme.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProfileTodayClockSection extends ConsumerStatefulWidget {
  const _ProfileTodayClockSection({
    required this.dark,
    required this.language,
    required this.user,
  });

  final bool dark;
  final AppLanguage language;
  final AuthUser user;

  @override
  ConsumerState<_ProfileTodayClockSection> createState() =>
      _ProfileTodayClockSectionState();
}

class _ProfileTodayClockSectionState
    extends ConsumerState<_ProfileTodayClockSection> {
  final Set<String> _submittingRequestIds = <String>{};

  Future<void> _clockRequest(
    BuildContext context,
    ServiceRequestModel request,
    String action,
  ) async {
    setState(() => _submittingRequestIds.add(request.id));

    try {
      await ref
          .read(staffRepositoryProvider)
          .clockRequestWork(requestId: request.id, action: action);
      ref.invalidate(_staffProfileTodayRequestsProvider(widget.user.id));

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'clock_in'
                ? _t(
                    widget.language,
                    en: 'Clocked in successfully.',
                    de: 'Erfolgreich eingestempelt.',
                  )
                : _t(
                    widget.language,
                    en: 'Clocked out successfully.',
                    de: 'Erfolgreich ausgestempelt.',
                  ),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submittingRequestIds.remove(request.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(
      _staffProfileTodayRequestsProvider(widget.user.id),
    );

    return _ProfileSectionCard(
      dark: widget.dark,
      title: _t(widget.language, en: 'Today\'s work', de: 'Heutige Einsätze'),
      subtitle: _t(
        widget.language,
        en: 'Technicians and contractors can clock in or out only for work scheduled today.',
        de: 'Techniker und Auftragnehmer können sich nur für heute geplante Einsätze ein- oder ausstempeln.',
      ),
      child: requestsAsync.when(
        data: (List<ServiceRequestModel> requests) {
          if (requests.isEmpty) {
            return Text(
              _t(
                widget.language,
                en: 'No assigned reviews or jobs are scheduled for today.',
                de: 'Für heute sind keine zugewiesenen Reviews oder Einsätze geplant.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: widget.dark
                    ? AppTheme.darkTextMuted
                    : AppTheme.textMuted,
              ),
            );
          }

          return Column(
            children: <Widget>[
              for (var index = 0; index < requests.length; index += 1)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: index == requests.length - 1 ? 0 : 12,
                  ),
                  child: _ProfileTodayClockRow(
                    dark: widget.dark,
                    language: widget.language,
                    request: requests[index],
                    userId: widget.user.id,
                    isSubmitting: _submittingRequestIds.contains(
                      requests[index].id,
                    ),
                    onClock: (String action) =>
                        _clockRequest(context, requests[index], action),
                  ),
                ),
            ],
          );
        },
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (Object error, StackTrace stackTrace) => Text(
          error.toString(),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.ember),
        ),
      ),
    );
  }
}

class _ProfileTodayClockRow extends StatelessWidget {
  const _ProfileTodayClockRow({
    required this.dark,
    required this.language,
    required this.request,
    required this.userId,
    required this.isSubmitting,
    required this.onClock,
  });

  final bool dark;
  final AppLanguage language;
  final ServiceRequestModel request;
  final String userId;
  final bool isSubmitting;
  final ValueChanged<String> onClock;

  @override
  Widget build(BuildContext context) {
    final activeLog = _activeWorkLogForUser(request, userId);
    final buttonAction = activeLog == null ? 'clock_in' : 'clock_out';
    final buttonLabel = activeLog == null
        ? _t(language, en: 'Clock in', de: 'Einstempeln')
        : _t(language, en: 'Clock out', de: 'Ausstempeln');
    final buttonIcon = activeLog == null
        ? Icons.login_rounded
        : Icons.logout_rounded;
    final secondaryTextColor = dark
        ? AppTheme.darkTextMuted
        : AppTheme.textMuted;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? AppTheme.darkSurfaceRaised : AppTheme.shellRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dark ? AppTheme.darkBorder : AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    request.serviceLabelForLanguage(language),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: dark ? AppTheme.darkText : AppTheme.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${request.contactFullName} · ${request.city}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: secondaryTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _todayScheduleSummary(language, request, activeLog),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: secondaryTextColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: isSubmitting ? null : () => onClock(buttonAction),
              style: FilledButton.styleFrom(
                backgroundColor: dark ? AppTheme.darkAccent : AppTheme.cobalt,
                foregroundColor: dark ? AppTheme.darkPage : Colors.white,
              ),
              icon: Icon(
                isSubmitting ? Icons.more_horiz_rounded : buttonIcon,
                size: 18,
              ),
              label: Text(isSubmitting ? '...' : buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.dark,
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
  });

  final bool dark;
  final IconData icon;
  final String label;
  final String value;
  final AppTone? tone;

  @override
  Widget build(BuildContext context) {
    final iconSurface = dark
        ? AppTheme.darkSurfaceMuted
        : AppTheme.accentSurface;
    final iconForeground = dark ? AppTheme.darkAccent : AppTheme.cobalt;
    final labelColor = dark ? AppTheme.darkTextSoft : AppTheme.textSoft;
    final valueColor = dark ? AppTheme.darkText : AppTheme.ink;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: iconSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: dark ? AppTheme.darkBorder : AppTheme.border,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: iconForeground),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: labelColor),
              ),
              const SizedBox(height: 6),
              if (tone == null)
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                _ProfileBadge(
                  label: value,
                  backgroundColor: tone!.background,
                  foregroundColor: tone!.foreground,
                  borderColor: tone!.border,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null ? null : Border.all(color: borderColor!),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: foregroundColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _workspaceRoute(WorkspaceProfileScope scope) {
  return switch (scope) {
    WorkspaceProfileScope.customer => '/app/requests',
    WorkspaceProfileScope.admin => '/admin',
    WorkspaceProfileScope.staff => '/staff',
  };
}

String _calendarRoute(WorkspaceProfileScope scope) {
  return switch (scope) {
    WorkspaceProfileScope.customer => '/app/calendar',
    WorkspaceProfileScope.admin => '/admin/calendar',
    WorkspaceProfileScope.staff => '/staff/calendar',
  };
}

String _screenTitle(
  AppLanguage language,
  WorkspaceProfileScope scope,
  AuthUser user,
) {
  final exactRole = _roleLabel(language, user);

  if (scope == WorkspaceProfileScope.customer) {
    return _t(language, en: 'Customer profile', de: 'Kundenprofil');
  }

  return _t(language, en: '$exactRole profile', de: '$exactRole-Profil');
}

String _screenSubtitle(
  AppLanguage language,
  WorkspaceProfileScope scope,
  AuthUser user,
) {
  final exactRole = _roleLabel(language, user);

  return switch (scope) {
    WorkspaceProfileScope.customer => _t(
      language,
      en: 'Review the details attached to your customer workspace.',
      de: 'Prufen Sie die Daten, die Ihrem Kundenbereich zugeordnet sind.',
    ),
    WorkspaceProfileScope.admin => _t(
      language,
      en: 'Review the details attached to your admin workspace.',
      de: 'Prufen Sie die Daten, die Ihrem Admin-Bereich zugeordnet sind.',
    ),
    WorkspaceProfileScope.staff => _t(
      language,
      en: 'Review the details attached to your ${exactRole.toLowerCase()} workspace.',
      de: 'Prufen Sie die Daten, die Ihrem ${exactRole.toLowerCase()}-Bereich zugeordnet sind.',
    ),
  };
}

String _fallbackName(
  AppLanguage language,
  WorkspaceProfileScope scope,
  AuthUser user,
) {
  final exactRole = _roleLabel(language, user);

  return switch (scope) {
    WorkspaceProfileScope.customer => _t(
      language,
      en: 'Customer account',
      de: 'Kundenkonto',
    ),
    WorkspaceProfileScope.admin => _t(
      language,
      en: 'Admin account',
      de: 'Admin-Konto',
    ),
    WorkspaceProfileScope.staff => _t(
      language,
      en: '$exactRole account',
      de: '$exactRole-Konto',
    ),
  };
}

String _roleLabel(AppLanguage language, AuthUser user) {
  if (user.role == 'staff') {
    return switch (user.staffType) {
      'customer_care' => _t(language, en: 'Customer Care', de: 'Customer Care'),
      'contractor' => _t(language, en: 'Contractor', de: 'Auftragnehmer'),
      'technician' => _t(language, en: 'Technician', de: 'Techniker'),
      _ => _t(language, en: 'Staff', de: 'Mitarbeiter'),
    };
  }

  return switch (user.role) {
    'admin' => _t(language, en: 'Admin', de: 'Admin'),
    'customer' => _t(language, en: 'Customer', de: 'Kunde'),
    _ =>
      user.role.trim().isEmpty
          ? _t(language, en: 'User', de: 'Benutzer')
          : user.role,
  };
}

String _statusLabel(AppLanguage language, String status) {
  return switch (status) {
    'active' => _t(language, en: 'Active', de: 'Aktiv'),
    'inactive' => _t(language, en: 'Inactive', de: 'Inaktiv'),
    'invited' => _t(language, en: 'Invited', de: 'Eingeladen'),
    _ =>
      status.trim().isEmpty
          ? _t(language, en: 'Unknown', de: 'Unbekannt')
          : status.replaceAll('_', ' '),
  };
}

AppTone _statusTone(String status, {required bool dark}) {
  return switch (status) {
    'active' =>
      dark
          ? const AppTone(
              background: AppTheme.darkSuccessSurface,
              foreground: AppTheme.darkAccent,
              border: AppTheme.darkBorderStrong,
            )
          : const AppTone(
              background: AppTheme.successSurface,
              foreground: AppTheme.pine,
              border: AppTheme.border,
            ),
    'inactive' =>
      dark
          ? const AppTone(
              background: AppTheme.darkWarningSurface,
              foreground: AppTheme.ember,
              border: AppTheme.darkBorder,
            )
          : const AppTone(
              background: AppTheme.warningSurface,
              foreground: AppTheme.ember,
              border: AppTheme.border,
            ),
    'invited' =>
      dark
          ? const AppTone(
              background: AppTheme.darkInfoSurface,
              foreground: AppTheme.darkText,
              border: AppTheme.darkBorderStrong,
            )
          : const AppTone(
              background: AppTheme.infoSurface,
              foreground: AppTheme.info,
              border: AppTheme.border,
            ),
    _ =>
      dark
          ? const AppTone(
              background: AppTheme.darkSurfaceMuted,
              foreground: AppTheme.darkTextMuted,
              border: AppTheme.darkBorder,
            )
          : const AppTone(
              background: AppTheme.neutralSurface,
              foreground: AppTheme.textMuted,
              border: AppTheme.border,
            ),
  };
}

String _initialsFor(AuthUser user) {
  final seed = <String>[
    user.firstName,
    user.lastName,
  ].where((String value) => value.trim().isNotEmpty).toList(growable: false);

  if (seed.isEmpty) {
    if (user.fullName.trim().isNotEmpty) {
      final parts = user.fullName.trim().split(RegExp(r'\s+'));
      return parts.take(2).map((part) => part[0]).join().toUpperCase();
    }

    if (user.email.trim().isNotEmpty) {
      return user.email.trim()[0].toUpperCase();
    }

    return 'U';
  }

  return seed.take(2).map((part) => part[0]).join().toUpperCase();
}

String _t(AppLanguage language, {required String en, required String de}) {
  return language.pick(en: en, de: de);
}

bool _supportsProfileClocking(WorkspaceProfileScope scope, AuthUser user) {
  return scope == WorkspaceProfileScope.staff &&
      user.role == 'staff' &&
      (user.staffType == 'technician' || user.staffType == 'contractor');
}

DateTime _profileDateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _formatProfileApiDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

bool _requestOccursOnProfileDay(ServiceRequestModel request, DateTime day) {
  final start = _profileDateOnly(
    request.calendarStartDate ??
        request.estimatedStartDate ??
        request.preferredDate ??
        request.actualStartDate ??
        request.createdAt ??
        day,
  );
  final end = _profileDateOnly(
    request.calendarEndDate ??
        request.estimatedEndDate ??
        request.actualEndDate ??
        request.preferredDate ??
        request.calendarStartDate ??
        request.estimatedStartDate ??
        request.actualStartDate ??
        request.createdAt ??
        day,
  );

  return !day.isBefore(start) && !day.isAfter(end);
}

int _compareProfileScheduleRequests(
  ServiceRequestModel a,
  ServiceRequestModel b,
) {
  final aStart = a.calendarStartDate ?? a.estimatedStartDate ?? a.preferredDate;
  final bStart = b.calendarStartDate ?? b.estimatedStartDate ?? b.preferredDate;

  if (aStart != null && bStart != null) {
    final compare = aStart.compareTo(bStart);
    if (compare != 0) {
      return compare;
    }
  } else if (aStart != null) {
    return -1;
  } else if (bStart != null) {
    return 1;
  }

  return compareServiceRequestsByLatestActivity(a, b);
}

RequestWorkLogModel? _activeWorkLogForUser(
  ServiceRequestModel request,
  String userId,
) {
  final matchingLogs =
      request.workLogs.where((log) => log.actor?.id == userId).toList()
        ..sort((left, right) {
          final leftTime = left.startedAt?.millisecondsSinceEpoch ?? 0;
          final rightTime = right.startedAt?.millisecondsSinceEpoch ?? 0;
          return rightTime.compareTo(leftTime);
        });

  for (final log in matchingLogs) {
    if (log.stoppedAt == null) {
      return log;
    }
  }

  return null;
}

String _todayScheduleSummary(
  AppLanguage language,
  ServiceRequestModel request,
  RequestWorkLogModel? activeLog,
) {
  final siteReviewEstimate = _scheduledSiteReviewEstimation(request);
  final timeLabel =
      siteReviewEstimate != null &&
          siteReviewEstimate.siteReviewStartTime.trim().isNotEmpty &&
          siteReviewEstimate.siteReviewEndTime.trim().isNotEmpty
      ? '${siteReviewEstimate.siteReviewStartTime} - ${siteReviewEstimate.siteReviewEndTime}'
      : '';

  final scheduleLabel = request.assessmentStatus == 'site_visit_scheduled'
      ? _t(language, en: 'Site review today', de: 'Vor-Ort-Termin heute')
      : _t(language, en: 'Scheduled work today', de: 'Geplante Arbeit heute');

  if (activeLog?.startedAt != null) {
    final startedAt = activeLog!.startedAt!;
    final startedLabel =
        '${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';
    return _t(
      language,
      en: '$scheduleLabel · Clocked in at $startedLabel',
      de: '$scheduleLabel · Eingestempelt um $startedLabel',
    );
  }

  if (timeLabel.isNotEmpty) {
    return '$scheduleLabel · $timeLabel';
  }

  return scheduleLabel;
}

RequestEstimationModel? _scheduledSiteReviewEstimation(
  ServiceRequestModel request,
) {
  if (request.selectedEstimation?.siteReviewDate != null) {
    return request.selectedEstimation;
  }

  for (final estimation in request.estimations.reversed) {
    if (estimation.siteReviewDate != null) {
      return estimation;
    }
  }

  return null;
}
