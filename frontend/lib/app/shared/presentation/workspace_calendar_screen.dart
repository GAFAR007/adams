library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/app_language.dart';
import '../../core/models/service_request_model.dart';
import '../../core/realtime/realtime_service.dart';
import '../../features/admin/data/admin_repository.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/customer/data/customer_repository.dart';
import '../../features/staff/data/staff_repository.dart';
import '../../theme/app_theme.dart';
import 'app_language_toggle.dart';
import 'workspace_profile_action_button.dart';

enum WorkspaceCalendarScope { customer, admin, staff }

enum _WorkspaceCalendarViewMode { day, month, year }

final workspaceCalendarRequestsProvider = FutureProvider.autoDispose
    .family<List<ServiceRequestModel>, _WorkspaceCalendarQuery>((
      Ref ref,
      _WorkspaceCalendarQuery query,
    ) async {
      switch (query.scope) {
        case WorkspaceCalendarScope.admin:
          return ref
              .watch(adminRepositoryProvider)
              .fetchCalendarRequests(
                start: query.rangeStart,
                end: query.rangeEnd,
              );
        case WorkspaceCalendarScope.staff:
          return ref
              .watch(staffRepositoryProvider)
              .fetchCalendarRequests(
                start: query.rangeStart,
                end: query.rangeEnd,
              );
        case WorkspaceCalendarScope.customer:
          return ref.watch(customerRepositoryProvider).fetchRequests();
      }
    });

class _WorkspaceCalendarQuery {
  const _WorkspaceCalendarQuery({
    required this.scope,
    required this.rangeStart,
    required this.rangeEnd,
  });

  final WorkspaceCalendarScope scope;
  final String rangeStart;
  final String rangeEnd;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is _WorkspaceCalendarQuery &&
        other.scope == scope &&
        other.rangeStart == rangeStart &&
        other.rangeEnd == rangeEnd;
  }

  @override
  int get hashCode => Object.hash(scope, rangeStart, rangeEnd);
}

class WorkspaceCalendarScreen extends ConsumerStatefulWidget {
  const WorkspaceCalendarScreen({super.key, required this.scope});

  final WorkspaceCalendarScope scope;

  @override
  ConsumerState<WorkspaceCalendarScreen> createState() =>
      _WorkspaceCalendarScreenState();
}

class _WorkspaceCalendarScreenState
    extends ConsumerState<WorkspaceCalendarScreen> {
  late DateTime _visibleMonth;
  late DateTime _selectedDay;
  _WorkspaceCalendarViewMode _viewMode = _WorkspaceCalendarViewMode.month;

  AppLanguage get _language => ref.read(appLanguageProvider);

  String _t({required String en, required String de}) {
    return _language.pick(en: en, de: de);
  }

  bool get _dark => widget.scope != WorkspaceCalendarScope.customer;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now().toLocal())!;
    _visibleMonth = DateTime(today.year, today.month);
    _selectedDay = today;

    ref.listenManual<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (
      _,
      next,
    ) {
      next.whenData((event) {
        if (!event.affectsRequests || !mounted) {
          return;
        }

        ref.invalidate(workspaceCalendarRequestsProvider(_currentQuery()));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final language = ref.watch(appLanguageProvider);
    final user = authState.user;

    if (!authState.hasBootstrapped ||
        authState.isBootstrapping ||
        user == null) {
      return Scaffold(
        backgroundColor: _dark ? AppTheme.darkPage : AppTheme.sand,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final query = _currentQuery();
    final requestsAsync = ref.watch(workspaceCalendarRequestsProvider(query));
    final backgroundColors = _dark
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
      backgroundColor: backgroundColors.first,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: backgroundColors.first,
        foregroundColor: _dark ? AppTheme.darkText : AppTheme.ink,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '${_screenTitle(language)} · ${user.fullName.trim().isEmpty ? _roleName(language) : user.fullName}',
        ),
        leading: IconButton(
          tooltip: _t(en: 'Back to workspace', de: 'Zuruck zum Bereich'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: () => context.go(_workspaceRoute(widget.scope)),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: <Widget>[
          WorkspaceProfileActionButton(
            tooltip: _t(en: 'Profile', de: 'Profil'),
            onPressed: () => context.go(_profileRoute(widget.scope)),
            displayName: user.fullName,
            dark: _dark,
          ),
          AppLanguageToggle(
            language: language,
            onChanged: ref.read(appLanguageProvider.notifier).setLanguage,
            dark: _dark,
            compact: true,
          ),
          WorkspaceLogoutActionButton(
            tooltip: _t(en: 'Logout', de: 'Abmelden'),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                context.go('/');
              }
            },
            dark: _dark,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: backgroundColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: requestsAsync.when(
            data: (List<ServiceRequestModel> requests) =>
                _buildLoaded(context, requests, query),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, StackTrace stackTrace) =>
                _buildErrorState(context, error.toString()),
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    List<ServiceRequestModel> requests,
    _WorkspaceCalendarQuery query,
  ) {
    final monthDays = _visibleDaysForMonth(_visibleMonth);
    final monthRequestsByDay = _requestsByDay(requests, monthDays);
    final yearDays = _visibleDaysForYear(_visibleMonth.year);
    final yearRequestsByDay = _requestsByDay(requests, yearDays);
    final selectedRequests =
        _requestsByDay(requests, <DateTime>[_selectedDay])[_dayKey(
          _selectedDay,
        )] ??
        const <ServiceRequestModel>[];
    final rangeRequestCount = _rangeRequestCountForCurrentView(requests);

    return RefreshIndicator(
      color: _dark ? AppTheme.darkAccent : AppTheme.cobalt,
      backgroundColor: _dark ? AppTheme.darkSurface : Colors.white,
      onRefresh: () async {
        ref.invalidate(workspaceCalendarRequestsProvider(query));
        await ref.read(workspaceCalendarRequestsProvider(query).future);
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final horizontalPadding = constraints.maxWidth < 720 ? 16.0 : 24.0;
          final primaryCard = switch (_viewMode) {
            _WorkspaceCalendarViewMode.day => _buildDayCard(
              context,
              selectedRequests: selectedRequests,
            ),
            _WorkspaceCalendarViewMode.month => _buildMonthCard(
              context,
              visibleDays: monthDays,
              requestsByDay: monthRequestsByDay,
            ),
            _WorkspaceCalendarViewMode.year => _buildYearCard(
              context,
              requestsByDay: yearRequestsByDay,
            ),
          };
          final secondaryCard = _viewMode == _WorkspaceCalendarViewMode.day
              ? null
              : _buildAgendaCard(context, selectedRequests);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              18,
              horizontalPadding,
              28,
            ),
            children: <Widget>[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1220),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildHeroCard(
                        context,
                        rangeRequestCount: rangeRequestCount,
                        selectedCount: selectedRequests.length,
                      ),
                      const SizedBox(height: 18),
                      primaryCard,
                      if (secondaryCard != null) ...<Widget>[
                        const SizedBox(height: 18),
                        secondaryCard,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeroCard(
    BuildContext context, {
    required int rangeRequestCount,
    required int selectedCount,
  }) {
    final cardColor = _dark ? AppTheme.darkSurface : AppTheme.shell;
    final borderColor = _dark
        ? AppTheme.darkBorder.withValues(alpha: 0.92)
        : AppTheme.border.withValues(alpha: 0.84);
    final titleColor = _dark ? AppTheme.darkText : AppTheme.ink;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: (_dark ? Colors.black : AppTheme.ink).withValues(
              alpha: _dark ? 0.18 : 0.08,
            ),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _t(en: 'Calendar view', de: 'Kalenderansicht'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: titleColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _CalendarViewModeToggle(
              dark: _dark,
              selectedMode: _viewMode,
              dayLabel: _t(en: 'Day', de: 'Tag'),
              monthLabel: _t(en: 'Month', de: 'Monat'),
              yearLabel: _t(en: 'Year', de: 'Jahr'),
              onChanged: _setViewMode,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _CalendarInfoChip(
                  dark: _dark,
                  icon: Icons.public_rounded,
                  label: _t(
                    en: 'Times shown in: British Summer Time (UTC+01:00)',
                    de: 'Zeiten gezeigt in: British Summer Time (UTC+01:00)',
                  ),
                ),
                _CalendarInfoChip(
                  dark: _dark,
                  icon: Icons.access_time_rounded,
                  label: _t(
                    en: 'Work blocks: 09:00-13:00, 14:00-17:00',
                    de: 'Arbeitsblöcke: 09:00-13:00, 14:00-17:00',
                  ),
                ),
                _CalendarInfoChip(
                  dark: _dark,
                  icon: Icons.event_note_rounded,
                  label: _rangeSummaryLabel(rangeRequestCount),
                ),
                _CalendarInfoChip(
                  dark: _dark,
                  icon: Icons.calendar_today_rounded,
                  label: _t(
                    en: '$selectedCount on ${_formatSelectedDay(_selectedDay)}',
                    de: '$selectedCount am ${_formatSelectedDay(_selectedDay)}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(
    BuildContext context, {
    required List<ServiceRequestModel> selectedRequests,
  }) {
    final cardColor = _dark ? AppTheme.darkSurface : AppTheme.shell;
    final borderColor = _dark
        ? AppTheme.darkBorder.withValues(alpha: 0.92)
        : AppTheme.border.withValues(alpha: 0.84);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildRangeHeader(
              context,
              title: _formatDayViewTitle(_selectedDay),
            ),
            const SizedBox(height: 20),
            if (selectedRequests.isEmpty)
              _EmptyAgendaState(
                dark: _dark,
                title: _t(
                  en: 'Nothing scheduled on this day',
                  de: 'An diesem Tag ist nichts geplant',
                ),
                subtitle: widget.scope == WorkspaceCalendarScope.customer
                    ? _t(
                        en: 'Customer dates still stay editable inside the request chat whenever the date step appears.',
                        de: 'Kundentermine bleiben weiterhin im Anfrage-Chat bearbeitbar, sobald der Datumsschritt erscheint.',
                      )
                    : _t(
                        en: 'Open estimates and assigned jobs will appear here as soon as staff adds schedule windows.',
                        de: 'Offene Schätzungen und zugewiesene Jobs erscheinen hier, sobald Zeitfenster hinterlegt werden.',
                      ),
              )
            else
              ...selectedRequests.map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CalendarRequestCard(
                    request: request,
                    language: _language,
                    dark: _dark,
                    scope: widget.scope,
                    dateLabel: _requestDateLabel(request),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildYearCard(
    BuildContext context, {
    required Map<String, List<ServiceRequestModel>> requestsByDay,
  }) {
    final cardColor = _dark ? AppTheme.darkSurface : AppTheme.shell;
    final borderColor = _dark
        ? AppTheme.darkBorder.withValues(alpha: 0.92)
        : AppTheme.border.withValues(alpha: 0.84);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildRangeHeader(context, title: '${_visibleMonth.year}'),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final crossAxisCount = constraints.maxWidth >= 1120
                    ? 4
                    : constraints.maxWidth >= 820
                    ? 3
                    : constraints.maxWidth >= 520
                    ? 2
                    : 1;
                final months = List<DateTime>.generate(
                  12,
                  (index) => DateTime(_visibleMonth.year, index + 1),
                  growable: false,
                );

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: months.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: constraints.maxWidth >= 1120
                        ? 1.08
                        : constraints.maxWidth >= 820
                        ? 1.02
                        : 0.98,
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final month = months[index];
                    return _YearMonthCard(
                      month: month,
                      visibleDays: _visibleDaysForMonth(month),
                      selectedDay: _selectedDay,
                      today: _dateOnly(DateTime.now().toLocal())!,
                      dark: _dark,
                      language: _language,
                      requestCounts: requestsByDay.map(
                        (key, value) => MapEntry(key, value.length),
                      ),
                      onSelectDay: _selectDay,
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthCard(
    BuildContext context, {
    required List<DateTime> visibleDays,
    required Map<String, List<ServiceRequestModel>> requestsByDay,
  }) {
    final cardColor = _dark ? AppTheme.darkSurface : AppTheme.shell;
    final borderColor = _dark
        ? AppTheme.darkBorder.withValues(alpha: 0.92)
        : AppTheme.border.withValues(alpha: 0.84);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final rows = (visibleDays.length / 7).ceil().clamp(4, 6);
            final gridWidth = constraints.maxWidth;
            final cellWidth = (gridWidth - (6 * 10)) / 7;
            final targetCellHeight = switch (rows) {
              4 || 5 =>
                gridWidth >= 1080
                    ? 118.0
                    : gridWidth >= 760
                    ? 102.0
                    : 88.0,
              _ =>
                gridWidth >= 1080
                    ? 108.0
                    : gridWidth >= 760
                    ? 96.0
                    : 84.0,
            };
            final childAspectRatio = cellWidth / targetCellHeight;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildRangeHeader(
                  context,
                  title: _monthYearLabel(_visibleMonth),
                ),
                const SizedBox(height: 18),
                Row(
                  children: _weekdayLabels()
                      .map(
                        (label) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: _dark
                                        ? AppTheme.darkTextMuted
                                        : AppTheme.textMuted,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visibleDays.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final day = visibleDays[index];
                    final items =
                        requestsByDay[_dayKey(day)] ??
                        const <ServiceRequestModel>[];

                    return _CalendarDayCell(
                      day: day,
                      selected: _isSameDay(day, _selectedDay),
                      today: _isSameDay(
                        day,
                        _dateOnly(DateTime.now().toLocal())!,
                      ),
                      inMonth: day.month == _visibleMonth.month,
                      dark: _dark,
                      requestCount: items.length,
                      onTap: () => _selectDay(day),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAgendaCard(
    BuildContext context,
    List<ServiceRequestModel> selectedRequests,
  ) {
    final cardColor = _dark ? AppTheme.darkSurface : AppTheme.shell;
    final borderColor = _dark
        ? AppTheme.darkBorder.withValues(alpha: 0.92)
        : AppTheme.border.withValues(alpha: 0.84);
    final titleColor = _dark ? AppTheme.darkText : AppTheme.ink;
    final bodyColor = _dark ? AppTheme.darkTextMuted : AppTheme.textMuted;

    final sortedRequests = [...selectedRequests]
      ..sort(_compareCalendarRequests);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              _formatSelectedDay(_selectedDay),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: titleColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              selectedRequests.isEmpty
                  ? _t(
                      en: 'No scheduled items on this day yet.',
                      de: 'Für diesen Tag sind noch keine Einträge geplant.',
                    )
                  : _t(
                      en: '${selectedRequests.length} item${selectedRequests.length == 1 ? '' : 's'} on this day',
                      de: '${selectedRequests.length} Eintrag${selectedRequests.length == 1 ? '' : 'e'} an diesem Tag',
                    ),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: bodyColor),
            ),
            const SizedBox(height: 18),
            if (selectedRequests.isEmpty)
              _EmptyAgendaState(
                dark: _dark,
                title: _t(
                  en: 'Nothing scheduled here',
                  de: 'Hier ist nichts geplant',
                ),
                subtitle: widget.scope == WorkspaceCalendarScope.customer
                    ? _t(
                        en: 'Customers only see their own requested or confirmed dates here. You can still pick dates inside the chat flow.',
                        de: 'Kunden sehen hier nur ihre eigenen angefragten oder bestätigten Termine. Datumswahl bleibt weiterhin im Chat-Ablauf verfügbar.',
                      )
                    : _t(
                        en: 'Open jobs, estimated windows, and assigned work will appear here as dates are added.',
                        de: 'Offene Jobs, geschätzte Zeitfenster und zugewiesene Arbeiten erscheinen hier, sobald Termine hinterlegt sind.',
                      ),
              )
            else
              ...sortedRequests.map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CalendarRequestCard(
                    request: request,
                    language: _language,
                    dark: _dark,
                    scope: widget.scope,
                    dateLabel: _requestDateLabel(request),
                  ),
                ),
              ),
            if (selectedRequests.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => context.go(_workspaceRoute(widget.scope)),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: Text(
                    widget.scope == WorkspaceCalendarScope.customer
                        ? _t(
                            en: 'Open request workspace',
                            de: 'Anfragebereich öffnen',
                          )
                        : _t(
                            en: 'Open team workspace',
                            de: 'Arbeitsbereich öffnen',
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String message) {
    final cardColor = _dark ? AppTheme.darkSurface : AppTheme.shell;
    final borderColor = _dark
        ? AppTheme.darkBorder.withValues(alpha: 0.92)
        : AppTheme.border.withValues(alpha: 0.84);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _t(
                      en: 'Unable to load calendar',
                      de: 'Kalender konnte nicht geladen werden',
                    ),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: _dark ? AppTheme.darkText : AppTheme.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _dark
                          ? AppTheme.darkTextMuted
                          : AppTheme.textMuted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: () {
                      ref.invalidate(
                        workspaceCalendarRequestsProvider(_currentQuery()),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(_t(en: 'Try again', de: 'Erneut versuchen')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRangeHeader(
    BuildContext context, {
    required String title,
    String? subtitle,
    bool showNavigationControls = true,
  }) {
    final titleColor = _dark ? AppTheme.darkText : AppTheme.ink;
    final bodyColor = _dark ? AppTheme.darkTextMuted : AppTheme.textMuted;

    Widget buildTextBlock() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: titleColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: bodyColor),
            ),
          ],
        ],
      );
    }

    Widget buildNavigation() {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _MonthHeaderButton(
            icon: Icons.chevron_left_rounded,
            tooltip: _previousPeriodTooltip(),
            dark: _dark,
            onPressed: _goToPreviousPeriod,
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _goToToday,
            style: TextButton.styleFrom(
              foregroundColor: _dark ? AppTheme.darkText : AppTheme.ink,
              backgroundColor: _dark
                  ? AppTheme.darkSurfaceMuted
                  : AppTheme.accentSoft,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: BorderSide(
                  color: _dark
                      ? AppTheme.darkBorder
                      : AppTheme.border.withValues(alpha: 0.84),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text(_t(en: 'Today', de: 'Heute')),
          ),
          const SizedBox(width: 8),
          _MonthHeaderButton(
            icon: Icons.chevron_right_rounded,
            tooltip: _nextPeriodTooltip(),
            dark: _dark,
            onPressed: _goToNextPeriod,
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final stacked = constraints.maxWidth < 760;
        if (!showNavigationControls) {
          return buildTextBlock();
        }

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              buildTextBlock(),
              const SizedBox(height: 14),
              buildNavigation(),
            ],
          );
        }

        return Row(
          children: <Widget>[
            Expanded(child: buildTextBlock()),
            const SizedBox(width: 12),
            buildNavigation(),
          ],
        );
      },
    );
  }

  _WorkspaceCalendarQuery _currentQuery() {
    final queryDays = _queryDaysForCurrentView();
    final start = queryDays.first;
    final end = queryDays.last;
    return _WorkspaceCalendarQuery(
      scope: widget.scope,
      rangeStart: _formatApiDate(start),
      rangeEnd: _formatApiDate(end),
    );
  }

  void _setViewMode(_WorkspaceCalendarViewMode mode) {
    setState(() {
      _viewMode = mode;
      _visibleMonth = DateTime(_selectedDay.year, _selectedDay.month);
    });
  }

  void _goToPreviousPeriod() {
    setState(() {
      if (_viewMode == _WorkspaceCalendarViewMode.day) {
        final day = _selectedDay.subtract(const Duration(days: 1));
        _selectedDay = day;
        _visibleMonth = DateTime(day.year, day.month);
      } else if (_viewMode == _WorkspaceCalendarViewMode.month) {
        final month = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
        _selectVisibleMonth(month);
      } else {
        final year = DateTime(_visibleMonth.year - 1, _visibleMonth.month);
        _selectVisibleMonth(year);
      }
    });
  }

  void _goToNextPeriod() {
    setState(() {
      if (_viewMode == _WorkspaceCalendarViewMode.day) {
        final day = _selectedDay.add(const Duration(days: 1));
        _selectedDay = day;
        _visibleMonth = DateTime(day.year, day.month);
      } else if (_viewMode == _WorkspaceCalendarViewMode.month) {
        final month = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
        _selectVisibleMonth(month);
      } else {
        final year = DateTime(_visibleMonth.year + 1, _visibleMonth.month);
        _selectVisibleMonth(year);
      }
    });
  }

  void _selectVisibleMonth(DateTime month) {
    final maxDay = DateTime(month.year, month.month + 1, 0).day;
    final nextDay = _selectedDay.day > maxDay ? maxDay : _selectedDay.day;
    _visibleMonth = DateTime(month.year, month.month);
    _selectedDay = DateTime(month.year, month.month, nextDay);
  }

  void _goToToday() {
    final today = _dateOnly(DateTime.now().toLocal())!;
    setState(() {
      _visibleMonth = DateTime(today.year, today.month);
      _selectedDay = today;
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = _dateOnly(day)!;
      _visibleMonth = DateTime(day.year, day.month);
    });
  }

  List<DateTime> _queryDaysForCurrentView() {
    return switch (_viewMode) {
      _WorkspaceCalendarViewMode.day => <DateTime>[_selectedDay],
      _WorkspaceCalendarViewMode.month => _visibleDaysForMonth(_visibleMonth),
      _WorkspaceCalendarViewMode.year => _visibleDaysForYear(
        _visibleMonth.year,
      ),
    };
  }

  String _screenTitle(AppLanguage language) {
    return switch (widget.scope) {
      WorkspaceCalendarScope.customer => language.pick(
        en: 'My calendar',
        de: 'Mein Kalender',
      ),
      WorkspaceCalendarScope.admin || WorkspaceCalendarScope.staff =>
        language.pick(en: 'Shared calendar', de: 'Gemeinsamer Kalender'),
    };
  }

  String _roleName(AppLanguage language) {
    final user = ref.read(authControllerProvider).user;
    if (user == null) {
      return language.pick(en: 'User', de: 'Benutzer');
    }

    if (user.role == 'staff') {
      return switch (user.staffType) {
        'customer_care' => language.pick(
          en: 'Customer Care',
          de: 'Customer Care',
        ),
        'contractor' => language.pick(en: 'Contractor', de: 'Auftragnehmer'),
        'technician' => language.pick(en: 'Technician', de: 'Techniker'),
        _ => language.pick(en: 'Staff', de: 'Mitarbeiter'),
      };
    }

    return switch (user.role) {
      'admin' => language.pick(en: 'Admin', de: 'Admin'),
      'customer' => language.pick(en: 'Customer', de: 'Kunde'),
      _ => language.pick(en: 'User', de: 'Benutzer'),
    };
  }

  List<DateTime> _visibleDaysForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final firstWeekdayOffset = (firstDay.weekday + 6) % 7;
    final lastWeekdayOffset = 6 - ((lastDay.weekday + 6) % 7);
    final gridStart = firstDay.subtract(Duration(days: firstWeekdayOffset));
    final gridEnd = lastDay.add(Duration(days: lastWeekdayOffset));
    final totalDays = gridEnd.difference(gridStart).inDays + 1;
    return List<DateTime>.generate(
      totalDays,
      (index) => _dateOnly(gridStart.add(Duration(days: index)))!,
      growable: false,
    );
  }

  List<DateTime> _visibleDaysForYear(int year) {
    final start = DateTime(year, 1, 1);
    final end = DateTime(year, 12, 31);
    final totalDays = end.difference(start).inDays + 1;
    return List<DateTime>.generate(
      totalDays,
      (index) => _dateOnly(start.add(Duration(days: index)))!,
      growable: false,
    );
  }

  Map<String, List<ServiceRequestModel>> _requestsByDay(
    List<ServiceRequestModel> requests,
    List<DateTime> visibleDays,
  ) {
    final result = <String, List<ServiceRequestModel>>{};
    for (final day in visibleDays) {
      final matches =
          requests
              .where((request) => _requestOccursOnDay(request, day))
              .toList()
            ..sort(_compareCalendarRequests);
      if (matches.isNotEmpty) {
        result[_dayKey(day)] = matches;
      }
    }
    return result;
  }

  bool _requestTouchesMonth(ServiceRequestModel request, DateTime month) {
    final range = _calendarRangeFor(request);
    if (range == null) {
      return false;
    }

    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    return _dateRangesOverlap(
      range,
      _DateRange(start: monthStart, end: monthEnd),
    );
  }

  bool _requestOccursOnDay(ServiceRequestModel request, DateTime day) {
    final range = _calendarRangeFor(request);
    if (range == null) {
      return false;
    }

    return !day.isBefore(range.start) && !day.isAfter(range.end);
  }

  bool _requestTouchesRange(
    ServiceRequestModel request,
    DateTime start,
    DateTime end,
  ) {
    final range = _calendarRangeFor(request);
    if (range == null) {
      return false;
    }

    return _dateRangesOverlap(range, _DateRange(start: start, end: end));
  }

  _DateRange? _calendarRangeFor(ServiceRequestModel request) {
    final start = _dateOnly(
      request.calendarStartDate ??
          request.estimatedStartDate ??
          request.preferredDate ??
          request.actualStartDate ??
          request.createdAt,
    );
    final end = _dateOnly(
      request.calendarEndDate ??
          request.estimatedEndDate ??
          request.actualEndDate ??
          request.preferredDate ??
          request.calendarStartDate ??
          request.estimatedStartDate ??
          request.actualStartDate ??
          request.createdAt,
    );

    if (start == null || end == null) {
      return null;
    }

    if (end.isBefore(start)) {
      return _DateRange(start: start, end: start);
    }

    return _DateRange(start: start, end: end);
  }

  int _compareCalendarRequests(ServiceRequestModel a, ServiceRequestModel b) {
    final aRange = _calendarRangeFor(a);
    final bRange = _calendarRangeFor(b);
    final aStart = aRange?.start;
    final bStart = bRange?.start;

    if (aStart != null && bStart != null) {
      final startCompare = aStart.compareTo(bStart);
      if (startCompare != 0) {
        return startCompare;
      }
    } else if (aStart != null) {
      return -1;
    } else if (bStart != null) {
      return 1;
    }

    return compareServiceRequestsByLatestActivity(a, b);
  }

  bool _dateRangesOverlap(_DateRange a, _DateRange b) {
    return !a.end.isBefore(b.start) && !a.start.isAfter(b.end);
  }

  int _rangeRequestCountForCurrentView(List<ServiceRequestModel> requests) {
    return switch (_viewMode) {
      _WorkspaceCalendarViewMode.day =>
        requests
            .where((request) => _requestOccursOnDay(request, _selectedDay))
            .length,
      _WorkspaceCalendarViewMode.month =>
        requests
            .where((request) => _requestTouchesMonth(request, _visibleMonth))
            .length,
      _WorkspaceCalendarViewMode.year =>
        requests
            .where(
              (request) => _requestTouchesRange(
                request,
                DateTime(_visibleMonth.year, 1, 1),
                DateTime(_visibleMonth.year, 12, 31),
              ),
            )
            .length,
    };
  }

  String _rangeSummaryLabel(int count) {
    return switch (_viewMode) {
      _WorkspaceCalendarViewMode.day => _t(
        en: '$count item${count == 1 ? '' : 's'} on this day',
        de: '$count Eintrag${count == 1 ? '' : 'e'} an diesem Tag',
      ),
      _WorkspaceCalendarViewMode.month => _t(
        en: '$count item${count == 1 ? '' : 's'} this month',
        de: '$count Eintrag${count == 1 ? '' : 'e'} in diesem Monat',
      ),
      _WorkspaceCalendarViewMode.year => _t(
        en: '$count item${count == 1 ? '' : 's'} this year',
        de: '$count Eintrag${count == 1 ? '' : 'e'} in diesem Jahr',
      ),
    };
  }

  String _previousPeriodTooltip() {
    return switch (_viewMode) {
      _WorkspaceCalendarViewMode.day => _t(
        en: 'Previous day',
        de: 'Vorheriger Tag',
      ),
      _WorkspaceCalendarViewMode.month => _t(
        en: 'Previous month',
        de: 'Vorheriger Monat',
      ),
      _WorkspaceCalendarViewMode.year => _t(
        en: 'Previous year',
        de: 'Vorheriges Jahr',
      ),
    };
  }

  String _nextPeriodTooltip() {
    return switch (_viewMode) {
      _WorkspaceCalendarViewMode.day => _t(en: 'Next day', de: 'Nächster Tag'),
      _WorkspaceCalendarViewMode.month => _t(
        en: 'Next month',
        de: 'Nächster Monat',
      ),
      _WorkspaceCalendarViewMode.year => _t(
        en: 'Next year',
        de: 'Nächstes Jahr',
      ),
    };
  }

  String _requestDateLabel(ServiceRequestModel request) {
    final range = _calendarRangeFor(request);
    if (range == null) {
      return _t(en: 'Date pending', de: 'Termin ausstehend');
    }

    final startLabel = _formatShortDate(range.start);
    final endLabel = _formatShortDate(range.end);
    if (_isSameDay(range.start, range.end)) {
      return startLabel;
    }

    return '$startLabel - $endLabel';
  }

  List<String> _weekdayLabels() {
    return _language.isGerman
        ? const <String>['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So']
        : const <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  }

  String _monthYearLabel(DateTime value) {
    const englishMonths = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const germanMonths = <String>[
      'Januar',
      'Februar',
      'Marz',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ];

    final months = _language.isGerman ? germanMonths : englishMonths;
    return '${months[value.month - 1]} ${value.year}';
  }

  String _formatSelectedDay(DateTime value) {
    const englishWeekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const germanWeekdays = <String>[
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ];
    final weekdays = _language.isGerman ? germanWeekdays : englishWeekdays;
    return '${weekdays[value.weekday - 1]}, ${_formatShortDate(value)}';
  }

  String _formatShortDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  String _formatIsoDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$year-$month-$day';
  }

  String _formatShortWeekday(DateTime value) {
    final englishWeekdays = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    final germanWeekdays = <String>['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final weekdays = _language.isGerman ? germanWeekdays : englishWeekdays;
    return weekdays[value.weekday - 1];
  }

  String _formatDayViewTitle(DateTime value) {
    return '${_formatIsoDate(value)} (${_formatShortWeekday(value)})';
  }
}

class _CalendarInfoChip extends StatelessWidget {
  const _CalendarInfoChip({
    required this.label,
    required this.dark,
    required this.icon,
  });

  final String label;
  final bool dark;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? AppTheme.darkPageRaised : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark
              ? AppTheme.darkBorder
              : AppTheme.border.withValues(alpha: 0.82),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: dark ? AppTheme.darkAccent : AppTheme.cobalt,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: dark ? AppTheme.darkText : AppTheme.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarViewModeToggle extends StatelessWidget {
  const _CalendarViewModeToggle({
    required this.dark,
    required this.selectedMode,
    required this.dayLabel,
    required this.monthLabel,
    required this.yearLabel,
    required this.onChanged,
  });

  final bool dark;
  final _WorkspaceCalendarViewMode selectedMode;
  final String dayLabel;
  final String monthLabel;
  final String yearLabel;
  final ValueChanged<_WorkspaceCalendarViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = dark
        ? AppTheme.darkPageRaised
        : AppTheme.shellRaised;
    final borderColor = dark
        ? AppTheme.darkBorder
        : AppTheme.border.withValues(alpha: 0.84);

    Widget buildItem(
      _WorkspaceCalendarViewMode mode,
      String label, {
      bool leading = false,
      bool trailing = false,
    }) {
      final selected = selectedMode == mode;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(mode),
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(leading ? 999 : 0),
            right: Radius.circular(trailing ? 999 : 0),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? (dark ? AppTheme.darkAccentSurface : AppTheme.accentSurface)
                  : Colors.transparent,
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(leading ? 999 : 0),
                right: Radius.circular(trailing ? 999 : 0),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: selected
                    ? (dark ? AppTheme.darkAccent : AppTheme.ink)
                    : (dark ? AppTheme.darkTextMuted : AppTheme.textMuted),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: <Widget>[
          buildItem(_WorkspaceCalendarViewMode.day, dayLabel, leading: true),
          Container(width: 1, height: 26, color: borderColor),
          buildItem(_WorkspaceCalendarViewMode.month, monthLabel),
          Container(width: 1, height: 26, color: borderColor),
          buildItem(_WorkspaceCalendarViewMode.year, yearLabel, trailing: true),
        ],
      ),
    );
  }
}

class _MonthHeaderButton extends StatelessWidget {
  const _MonthHeaderButton({
    required this.icon,
    required this.tooltip,
    required this.dark,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool dark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? AppTheme.darkSurfaceMuted : AppTheme.accentSoft,
        shape: BoxShape.circle,
        border: Border.all(
          color: dark
              ? AppTheme.darkBorder
              : AppTheme.border.withValues(alpha: 0.84),
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.inMonth,
    required this.dark,
    required this.requestCount,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool today;
  final bool inMonth;
  final bool dark;
  final int requestCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final baseBackground = selected
        ? (dark ? AppTheme.darkAccentSurface : AppTheme.accentSurface)
        : dark
        ? AppTheme.darkPageRaised
        : Colors.white;
    final borderColor = selected
        ? (dark ? AppTheme.darkAccent : AppTheme.cobalt)
        : today
        ? (dark ? AppTheme.darkBorderStrong : AppTheme.borderStrong)
        : dark
        ? AppTheme.darkBorder.withValues(alpha: 0.72)
        : AppTheme.border.withValues(alpha: 0.72);
    final dayColor = !inMonth
        ? (dark ? AppTheme.darkTextSoft : AppTheme.textSoft)
        : selected
        ? (dark ? AppTheme.darkAccent : AppTheme.cobalt)
        : dark
        ? AppTheme.darkText
        : AppTheme.ink;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: baseBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: dayColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (requestCount > 0)
                  Icon(
                    Icons.event_note_rounded,
                    size: 18,
                    color: selected
                        ? (dark ? AppTheme.darkAccent : AppTheme.cobalt)
                        : (dark ? AppTheme.darkTextMuted : AppTheme.textMuted),
                  ),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _YearMonthCard extends StatelessWidget {
  const _YearMonthCard({
    required this.month,
    required this.visibleDays,
    required this.selectedDay,
    required this.today,
    required this.dark,
    required this.language,
    required this.requestCounts,
    required this.onSelectDay,
  });

  final DateTime month;
  final List<DateTime> visibleDays;
  final DateTime selectedDay;
  final DateTime today;
  final bool dark;
  final AppLanguage language;
  final Map<String, int> requestCounts;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = dark ? AppTheme.darkPageRaised : Colors.white;
    final borderColor = dark
        ? AppTheme.darkBorder.withValues(alpha: 0.78)
        : AppTheme.border.withValues(alpha: 0.78);
    final monthColor = dark ? AppTheme.darkAccent : AppTheme.ember;
    final weekdayLabels = language.isGerman
        ? const <String>['M', 'D', 'M', 'D', 'F', 'S', 'S']
        : const <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final monthLabel = language.pick(
      en: const <String>[
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ][month.month - 1],
      de: const <String>[
        'Januar',
        'Februar',
        'Marz',
        'April',
        'Mai',
        'Juni',
        'Juli',
        'August',
        'September',
        'Oktober',
        'November',
        'Dezember',
      ][month.month - 1],
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              monthLabel,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: monthColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: weekdayLabels
                  .map(
                    (label) => Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: dark
                                  ? AppTheme.darkTextMuted
                                  : AppTheme.textMuted,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 8),
            ...List<Widget>.generate(visibleDays.length ~/ 7, (rowIndex) {
              final rowDays = visibleDays
                  .skip(rowIndex * 7)
                  .take(7)
                  .toList(growable: false);

              return Padding(
                padding: EdgeInsets.only(
                  bottom: rowIndex == (visibleDays.length ~/ 7) - 1 ? 0 : 4,
                ),
                child: Row(
                  children: rowDays
                      .map(
                        (day) => Expanded(
                          child: _YearCalendarDay(
                            day: day,
                            inMonth: day.month == month.month,
                            selected: _isSameDay(day, selectedDay),
                            today: _isSameDay(day, today),
                            dark: dark,
                            hasItems: (requestCounts[_dayKey(day)] ?? 0) > 0,
                            onTap: day.month == month.month
                                ? () => onSelectDay(day)
                                : null,
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _YearCalendarDay extends StatelessWidget {
  const _YearCalendarDay({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.dark,
    required this.hasItems,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool selected;
  final bool today;
  final bool dark;
  final bool hasItems;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = !inMonth
        ? (dark ? AppTheme.darkTextSoft : AppTheme.textSoft)
        : selected
        ? Colors.white
        : dark
        ? AppTheme.darkText
        : AppTheme.ink;
    final backgroundColor = selected
        ? (dark ? AppTheme.darkAccent : AppTheme.ember)
        : dark
        ? Colors.transparent
        : Colors.transparent;
    final borderColor = today && !selected
        ? (dark ? AppTheme.darkBorderStrong : AppTheme.borderStrong)
        : Colors.transparent;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 28,
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor),
        ),
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: textColor,
            fontWeight: hasItems && inMonth ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CalendarRequestCard extends ConsumerStatefulWidget {
  const _CalendarRequestCard({
    required this.request,
    required this.language,
    required this.dark,
    required this.scope,
    required this.dateLabel,
  });

  final ServiceRequestModel request;
  final AppLanguage language;
  final bool dark;
  final WorkspaceCalendarScope scope;
  final String dateLabel;

  @override
  ConsumerState<_CalendarRequestCard> createState() =>
      _CalendarRequestCardState();
}

class _CalendarRequestCardState extends ConsumerState<_CalendarRequestCard> {
  late ServiceRequestModel _currentRequest;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _currentRequest = widget.request;
  }

  @override
  void didUpdateWidget(covariant _CalendarRequestCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _currentRequest = widget.request;
  }

  String _t({required String en, required String de}) {
    return widget.language.pick(en: en, de: de);
  }

  bool _requestOccursToday(ServiceRequestModel request) {
    final now = DateTime.now().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final startSource =
        request.calendarStartDate ??
        request.estimatedStartDate ??
        request.preferredDate ??
        request.actualStartDate ??
        request.createdAt ??
        today;
    final endSource =
        request.calendarEndDate ??
        request.estimatedEndDate ??
        request.actualEndDate ??
        request.preferredDate ??
        request.calendarStartDate ??
        request.estimatedStartDate ??
        request.actualStartDate ??
        request.createdAt ??
        today;
    final start = DateTime(
      startSource.year,
      startSource.month,
      startSource.day,
    );
    final end = DateTime(endSource.year, endSource.month, endSource.day);
    return !today.isBefore(start) && !today.isAfter(end);
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

  String _formatTimeOfDay(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _clockSummary(ServiceRequestModel request, String userId) {
    final activeLog = _activeWorkLogForUser(request, userId);
    final siteReviewEstimate = _scheduledSiteReviewEstimation(request);
    final timeLabel =
        siteReviewEstimate != null &&
            siteReviewEstimate.siteReviewStartTime.trim().isNotEmpty &&
            siteReviewEstimate.siteReviewEndTime.trim().isNotEmpty
        ? '${siteReviewEstimate.siteReviewStartTime} - ${siteReviewEstimate.siteReviewEndTime}'
        : '';
    final scheduleLabel = request.assessmentStatus == 'site_visit_scheduled'
        ? _t(en: 'Site review today', de: 'Vor-Ort-Termin heute')
        : _t(en: 'Scheduled work today', de: 'Geplante Arbeit heute');

    if (activeLog?.startedAt != null) {
      final startedAt = activeLog!.startedAt;
      return _t(
        en: '$scheduleLabel · Clocked in at ${_formatTimeOfDay(startedAt!)}',
        de: '$scheduleLabel · Eingestempelt um ${_formatTimeOfDay(startedAt)}',
      );
    }

    if (timeLabel.isNotEmpty) {
      return '$scheduleLabel · $timeLabel';
    }

    return scheduleLabel;
  }

  bool _canClock(ServiceRequestModel request) {
    final user = ref.watch(authControllerProvider).user;
    if (widget.scope != WorkspaceCalendarScope.staff ||
        user == null ||
        user.role != 'staff') {
      return false;
    }

    if (user.staffType != 'technician' && user.staffType != 'contractor') {
      return false;
    }

    if (request.status == 'closed' || request.assignedStaff?.id != user.id) {
      return false;
    }

    return _requestOccursToday(request);
  }

  Future<void> _clockRequest(String action) async {
    setState(() => _isSubmitting = true);

    try {
      final updatedRequest = await ref
          .read(staffRepositoryProvider)
          .clockRequestWork(requestId: _currentRequest.id, action: action);
      if (!mounted) {
        return;
      }

      setState(() => _currentRequest = updatedRequest);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'clock_in'
                ? _t(
                    en: 'Clocked in successfully.',
                    de: 'Erfolgreich eingestempelt.',
                  )
                : _t(
                    en: 'Clocked out successfully.',
                    de: 'Erfolgreich ausgestempelt.',
                  ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _currentRequest;
    final tone = _calendarTone(request);
    final surfaceColor = widget.dark
        ? AppTheme.darkPageRaised
        : AppTheme.shellRaised;
    final borderColor = widget.dark
        ? AppTheme.darkBorder.withValues(alpha: 0.9)
        : AppTheme.border.withValues(alpha: 0.82);
    final authUser = ref.watch(authControllerProvider).user;
    final canClock = _canClock(request);
    final activeLog = authUser == null
        ? null
        : _activeWorkLogForUser(request, authUser.id);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        request.serviceLabelForLanguage(widget.language),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: widget.dark
                                  ? AppTheme.darkText
                                  : AppTheme.ink,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.scope == WorkspaceCalendarScope.customer
                            ? '${request.city} · ${request.postalCode}'
                            : '${request.contactFullName} · ${request.city}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: widget.dark
                              ? AppTheme.darkTextMuted
                              : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tone.background,
                    borderRadius: BorderRadius.circular(999),
                    border: tone.border == null
                        ? null
                        : Border.all(color: tone.border!),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      requestCalendarStatusLabelFor(
                        request.calendarStatus,
                        language: widget.language,
                      ),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tone.foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _CalendarMetaRow(
              dark: widget.dark,
              icon: Icons.event_rounded,
              label: _t(en: 'Date', de: 'Datum'),
              value: widget.dateLabel,
            ),
            if (request.preferredTimeWindow.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              _CalendarMetaRow(
                dark: widget.dark,
                icon: Icons.schedule_rounded,
                label: _t(en: 'Window', de: 'Zeitfenster'),
                value: request.preferredTimeWindow,
              ),
            ],
            if (widget.scope != WorkspaceCalendarScope.customer &&
                request.assignedStaff != null) ...<Widget>[
              const SizedBox(height: 10),
              _CalendarMetaRow(
                dark: widget.dark,
                icon: Icons.person_outline_rounded,
                label: _t(en: 'Assigned', de: 'Zugewiesen'),
                value:
                    '${request.assignedStaff!.fullName} · ${request.assignedStaff!.staffTypeLabel}',
              ),
            ],
            if (canClock && authUser != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _clockSummary(request, authUser.id),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: widget.dark
                      ? AppTheme.darkTextMuted
                      : AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _clockRequest(
                        activeLog == null ? 'clock_in' : 'clock_out',
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.dark
                      ? AppTheme.darkAccent
                      : AppTheme.cobalt,
                  foregroundColor: widget.dark
                      ? AppTheme.darkPage
                      : Colors.white,
                ),
                icon: Icon(
                  _isSubmitting
                      ? Icons.more_horiz_rounded
                      : activeLog == null
                      ? Icons.login_rounded
                      : Icons.logout_rounded,
                  size: 18,
                ),
                label: Text(
                  _isSubmitting
                      ? _t(en: 'Saving...', de: 'Speichert...')
                      : activeLog == null
                      ? _t(en: 'Clock in', de: 'Einstempeln')
                      : _t(en: 'Clock out', de: 'Ausstempeln'),
                ),
              ),
            ],
            if (request.message.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                request.message.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: widget.dark
                      ? AppTheme.darkTextMuted
                      : AppTheme.textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  AppTone _calendarTone(ServiceRequestModel request) {
    if (widget.dark) {
      return switch (request.calendarStatus) {
        'pending_estimation' => const AppTone(
          background: AppTheme.darkWarningSurface,
          foreground: Color(0xFFF2C18F),
          border: Color(0xFF674C33),
        ),
        'estimated' => const AppTone(
          background: AppTheme.darkInfoSurface,
          foreground: Color(0xFF8EC7D2),
          border: Color(0xFF32505A),
        ),
        'assigned' || 'scheduled' => const AppTone(
          background: AppTheme.darkAccentSurface,
          foreground: AppTheme.darkAccent,
          border: AppTheme.darkBorderStrong,
        ),
        'quoted' => const AppTone(
          background: AppTheme.darkWarningSurface,
          foreground: Color(0xFFF0C08A),
          border: Color(0xFF6E5235),
        ),
        'pending_start' => const AppTone(
          background: Color(0xFF372D47),
          foreground: Color(0xFFD5C7F7),
          border: Color(0xFF52426A),
        ),
        'started' => const AppTone(
          background: AppTheme.darkInfoSurface,
          foreground: Color(0xFF8EC7D2),
          border: Color(0xFF32505A),
        ),
        'finished' || 'completed' => const AppTone(
          background: AppTheme.darkSuccessSurface,
          foreground: Color(0xFF9CD5B8),
          border: Color(0xFF335547),
        ),
        _ => const AppTone(
          background: AppTheme.darkSurfaceMuted,
          foreground: AppTheme.darkText,
          border: AppTheme.darkBorder,
        ),
      };
    }

    return switch (request.calendarStatus) {
      'pending_estimation' => const AppTone(
        background: AppTheme.warningSurface,
        foreground: AppTheme.ember,
        border: Color(0xFFE3C7A5),
      ),
      'estimated' => const AppTone(
        background: AppTheme.infoSurface,
        foreground: AppTheme.info,
        border: Color(0xFFBCDCE3),
      ),
      'assigned' || 'scheduled' => const AppTone(
        background: AppTheme.mist,
        foreground: AppTheme.cobalt,
        border: Color(0xFFB7D4D2),
      ),
      'quoted' => const AppTone(
        background: AppTheme.warningSurface,
        foreground: AppTheme.ember,
        border: Color(0xFFE4C29B),
      ),
      'pending_start' => const AppTone(
        background: AppTheme.violetSurface,
        foreground: AppTheme.violet,
        border: Color(0xFFD6CBE9),
      ),
      'started' => const AppTone(
        background: AppTheme.infoSurface,
        foreground: AppTheme.info,
        border: Color(0xFFBED8E2),
      ),
      'finished' || 'completed' => const AppTone(
        background: AppTheme.successSurface,
        foreground: AppTheme.pine,
        border: Color(0xFFB8D5C8),
      ),
      _ => const AppTone(
        background: AppTheme.shellRaised,
        foreground: AppTheme.ink,
        border: AppTheme.border,
      ),
    };
  }
}

class _CalendarMetaRow extends StatelessWidget {
  const _CalendarMetaRow({
    required this.dark,
    required this.icon,
    required this.label,
    required this.value,
  });

  final bool dark;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          icon,
          size: 18,
          color: dark ? AppTheme.darkAccent : AppTheme.cobalt,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '$label: ',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: dark ? AppTheme.darkText : AppTheme.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: dark ? AppTheme.darkTextMuted : AppTheme.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyAgendaState extends StatelessWidget {
  const _EmptyAgendaState({
    required this.dark,
    required this.title,
    required this.subtitle,
  });

  final bool dark;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? AppTheme.darkPageRaised : AppTheme.shellRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: dark
              ? AppTheme.darkBorder.withValues(alpha: 0.9)
              : AppTheme.border.withValues(alpha: 0.82),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.calendar_view_month_rounded,
              color: dark ? AppTheme.darkAccent : AppTheme.cobalt,
              size: 28,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: dark ? AppTheme.darkText : AppTheme.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: dark ? AppTheme.darkTextMuted : AppTheme.textMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRange {
  const _DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

String _workspaceRoute(WorkspaceCalendarScope scope) {
  return switch (scope) {
    WorkspaceCalendarScope.customer => '/app/requests',
    WorkspaceCalendarScope.admin => '/admin',
    WorkspaceCalendarScope.staff => '/staff',
  };
}

String _profileRoute(WorkspaceCalendarScope scope) {
  return switch (scope) {
    WorkspaceCalendarScope.customer => '/app/profile',
    WorkspaceCalendarScope.admin => '/admin/profile',
    WorkspaceCalendarScope.staff => '/staff/profile',
  };
}

String _dayKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _formatApiDate(DateTime value) => _dayKey(value);

DateTime? _dateOnly(DateTime? value) {
  if (value == null) {
    return null;
  }

  return DateTime(value.year, value.month, value.day);
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
