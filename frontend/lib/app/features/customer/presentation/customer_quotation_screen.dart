library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/models/service_request_model.dart';
import '../../../theme/app_theme.dart';
import 'customer_requests_screen.dart';

class _ActualWorkdayState {
  const _ActualWorkdayState({
    required this.actualStart,
    required this.actualEnd,
  });

  final DateTime? actualStart;
  final DateTime? actualEnd;
}

class CustomerQuotationScreen extends ConsumerWidget {
  const CustomerQuotationScreen({super.key, required this.requestId});

  final String requestId;

  String _t(AppLanguage language, {required String en, required String de}) {
    return language.pick(en: en, de: de);
  }

  ServiceRequestModel? _findRequest(List<ServiceRequestModel> requests) {
    for (final request in requests) {
      if (request.id == requestId) {
        return request;
      }
    }

    return null;
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Not set';
    }

    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not set';
    }

    final localValue = value.toLocal();
    final hour = localValue.hour.toString().padLeft(2, '0');
    final minute = localValue.minute.toString().padLeft(2, '0');
    return '${_formatDate(localValue)} $hour:$minute';
  }

  String _formatActualTime(DateTime? value) {
    if (value == null) {
      return 'Pending';
    }

    final localValue = value.toLocal();
    final suffix = localValue.hour >= 12 ? 'PM' : 'AM';
    final resolvedHour = localValue.hour % 12 == 0 ? 12 : localValue.hour % 12;
    return '$resolvedHour:${localValue.minute.toString().padLeft(2, '0')} $suffix';
  }

  String _dateKey(DateTime value) {
    final normalized = value.toLocal();
    final year = normalized.year.toString().padLeft(4, '0');
    final month = normalized.month.toString().padLeft(2, '0');
    final day = normalized.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Map<String, _ActualWorkdayState> _actualWorkdayStates(
    ServiceRequestModel request,
  ) {
    final earliestStarts = <String, DateTime>{};
    final latestStops = <String, DateTime>{};

    for (final workLog in request.workLogs) {
      final startedAt = workLog.startedAt;
      final stoppedAt = workLog.stoppedAt;
      final keySource = startedAt ?? stoppedAt;
      if (keySource == null) {
        continue;
      }

      final key = _dateKey(keySource);
      if (startedAt != null) {
        final current = earliestStarts[key];
        if (current == null || startedAt.isBefore(current)) {
          earliestStarts[key] = startedAt;
        }
      }
      if (stoppedAt != null) {
        final current = latestStops[key];
        if (current == null || stoppedAt.isAfter(current)) {
          latestStops[key] = stoppedAt;
        }
      }
    }

    final allKeys = <String>{...earliestStarts.keys, ...latestStops.keys};
    return <String, _ActualWorkdayState>{
      for (final key in allKeys)
        key: _ActualWorkdayState(
          actualStart: earliestStarts[key],
          actualEnd: latestStops[key],
        ),
    };
  }

  String _formatStorageTime(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return 'Not set';
    }

    final parts = raw.split(':');
    if (parts.length != 2) {
      return raw;
    }

    final hour = int.tryParse(parts.first);
    final minute = int.tryParse(parts.last);
    if (hour == null || minute == null) {
      return raw;
    }

    final suffix = hour >= 12 ? 'PM' : 'AM';
    final resolvedHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$resolvedHour:${minute.toString().padLeft(2, '0')} $suffix';
  }

  String _formatHours(double? value) {
    if (value == null) {
      return 'Not set';
    }
    if (value % 1 == 0) {
      return '${value.toStringAsFixed(0)} h';
    }
    return '${value.toStringAsFixed(1)} h';
  }

  Color _pageTopColor() => Color.lerp(AppTheme.ink, AppTheme.cobalt, 0.22)!;

  Color _pageBottomColor() => Color.lerp(AppTheme.ink, AppTheme.cobalt, 0.08)!;

  Color _panelColor() => Color.lerp(AppTheme.ink, AppTheme.cobalt, 0.16)!;

  ({Color background, Color foreground}) _statusColors(String status) {
    return switch (status) {
      paymentRequestStatusApproved => (
        background: const Color(0xFFDDF7E4),
        foreground: const Color(0xFF2F7C3E),
      ),
      paymentRequestStatusRejected => (
        background: const Color(0xFFFFE0DA),
        foreground: const Color(0xFFB04A34),
      ),
      paymentRequestStatusProofSubmitted => (
        background: const Color(0xFFDFF3FF),
        foreground: const Color(0xFF1B6285),
      ),
      _ => (background: const Color(0xFFFFEFD2), foreground: AppTheme.ember),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final requestsAsync = ref.watch(customerRequestsProvider);

    return Scaffold(
      backgroundColor: _pageBottomColor(),
      appBar: AppBar(
        backgroundColor: _pageTopColor(),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          _t(language, en: 'Quotation', de: 'Angebot'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[_pageTopColor(), _pageBottomColor()],
          ),
        ),
        child: requestsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.toString(),
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (List<ServiceRequestModel> requests) {
            final request = _findRequest(requests);
            final invoice = request?.invoice;
            if (request == null || invoice == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _panelColor(),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            Icons.description_outlined,
                            color: Colors.white,
                            size: 42,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _t(
                              language,
                              en: 'Quotation not available',
                              de: 'Angebot nicht verfuegbar',
                            ),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _t(
                              language,
                              en: 'Return to your request workspace and refresh the request list.',
                              de: 'Gehen Sie zur Anfrage zurueck und aktualisieren Sie die Liste.',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.76),
                                  height: 1.4,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            final statusColors = _statusColors(invoice.status);
            final estimation =
                request.selectedEstimation ?? request.quoteReadyEstimation;
            final actualWorkdayStates = _actualWorkdayStates(request);
            final locationLabel = <String>[
              if (request.city.trim().isNotEmpty) request.city.trim(),
              if (request.postalCode.trim().isNotEmpty)
                request.postalCode.trim(),
            ].join(', ');

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: _panelColor(),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  request.serviceLabelForLanguage(language),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  locationLabel.isEmpty
                                      ? invoice.invoiceNumber
                                      : '$locationLabel · ${invoice.invoiceNumber}',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                      ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: <Widget>[
                                    _QuotationChip(
                                      label:
                                          'EUR ${invoice.amount.toStringAsFixed(2)}',
                                      background: Colors.white,
                                      foreground: AppTheme.ink,
                                    ),
                                    _QuotationChip(
                                      label:
                                          '${_t(language, en: 'Due', de: 'Faellig')} ${_formatDate(invoice.dueDate)}',
                                      background: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                      foreground: Colors.white,
                                    ),
                                    _QuotationChip(
                                      label: requestStatusLabelFor(
                                        invoice.status,
                                        language: language,
                                      ),
                                      background: statusColors.background,
                                      foreground: statusColors.foreground,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                LayoutBuilder(
                                  builder:
                                      (
                                        BuildContext context,
                                        BoxConstraints constraints,
                                      ) {
                                        final compact =
                                            constraints.maxWidth < 760;
                                        final cardWidth = compact
                                            ? constraints.maxWidth
                                            : (constraints.maxWidth - 14) / 2;
                                        return Wrap(
                                          spacing: 14,
                                          runSpacing: 14,
                                          children: <Widget>[
                                            SizedBox(
                                              width: cardWidth,
                                              child: _QuotationMetricCard(
                                                label: _t(
                                                  language,
                                                  en: 'Total service charge',
                                                  de: 'Gesamte Servicegebuehr',
                                                ),
                                                value:
                                                    'EUR ${invoice.amount.toStringAsFixed(2)}',
                                              ),
                                            ),
                                            SizedBox(
                                              width: cardWidth,
                                              child: _QuotationMetricCard(
                                                label: _t(
                                                  language,
                                                  en: 'Payment method',
                                                  de: 'Zahlungsart',
                                                ),
                                                value: invoice
                                                    .paymentMethodLabelForLanguage(
                                                      language,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _QuotationSectionCard(
                          title: _t(
                            language,
                            en: 'Quoted schedule',
                            de: 'Geplanter Ablauf',
                          ),
                          child: LayoutBuilder(
                            builder:
                                (
                                  BuildContext context,
                                  BoxConstraints constraints,
                                ) {
                                  final compact = constraints.maxWidth < 760;
                                  final tileWidth = compact
                                      ? constraints.maxWidth
                                      : (constraints.maxWidth - 16) / 2;
                                  return Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    children: <Widget>[
                                      SizedBox(
                                        width: tileWidth,
                                        child: _QuotationDetailCard(
                                          label: _t(
                                            language,
                                            en: 'Estimated start date',
                                            de: 'Geplanter Start',
                                          ),
                                          value: _formatDate(
                                            invoice.plannedStartDate,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: tileWidth,
                                        child: _QuotationDetailCard(
                                          label: _t(
                                            language,
                                            en: 'Estimated end date',
                                            de: 'Geplantes Ende',
                                          ),
                                          value: _formatDate(
                                            invoice.plannedExpectedEndDate,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: tileWidth,
                                        child: _QuotationDetailCard(
                                          label: _t(
                                            language,
                                            en: 'Daily start time',
                                            de: 'Taegliche Startzeit',
                                          ),
                                          value: _formatStorageTime(
                                            invoice.plannedStartTime,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: tileWidth,
                                        child: _QuotationDetailCard(
                                          label: _t(
                                            language,
                                            en: 'Daily end time',
                                            de: 'Taegliche Endzeit',
                                          ),
                                          value: _formatStorageTime(
                                            invoice.plannedEndTime,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: tileWidth,
                                        child: _QuotationDetailCard(
                                          label: _t(
                                            language,
                                            en: 'Hours per day',
                                            de: 'Stunden pro Tag',
                                          ),
                                          value: _formatHours(
                                            invoice.plannedHoursPerDay,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: tileWidth,
                                        child: _QuotationDetailCard(
                                          label: _t(
                                            language,
                                            en: 'Prepared from estimate',
                                            de: 'Basierend auf Schätzung',
                                          ),
                                          value: estimation == null
                                              ? _t(
                                                  language,
                                                  en: 'Not specified',
                                                  de: 'Nicht angegeben',
                                                )
                                              : estimation.submittedBy == null
                                              ? estimation
                                                    .submitterStaffTypeLabel
                                              : '${estimation.submittedBy!.fullName} · ${estimation.submitterStaffTypeLabel}',
                                        ),
                                      ),
                                    ],
                                  );
                                },
                          ),
                        ),
                        if (invoice
                            .plannedDailySchedule
                            .isNotEmpty) ...<Widget>[
                          const SizedBox(height: 18),
                          _QuotationSectionCard(
                            title: _t(
                              language,
                              en: 'Daily work plan',
                              de: 'Taeglicher Arbeitsplan',
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  _t(
                                    language,
                                    en: 'Estimated times stay fixed on the quotation. Actual start and end times are updated by the technician or contractor after each visit, and remain pending until work is logged.',
                                    de: 'Die geplanten Zeiten bleiben im Angebot sichtbar. Tatsaechliche Start- und Endzeiten werden nach jedem Einsatz vom Techniker oder Auftragnehmer aktualisiert und bleiben bis dahin offen.',
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
                                        height: 1.45,
                                      ),
                                ),
                                const SizedBox(height: 14),
                                ...invoice.plannedDailySchedule.map(
                                  (entry) => Padding(
                                    padding: EdgeInsets.only(
                                      bottom:
                                          entry ==
                                              invoice.plannedDailySchedule.last
                                          ? 0
                                          : 12,
                                    ),
                                    child: _QuotationWorkdayCard(
                                      dateLabel: _formatDate(entry.date),
                                      estimatedStartTime: _formatStorageTime(
                                        entry.startTime,
                                      ),
                                      estimatedEndTime: _formatStorageTime(
                                        entry.endTime,
                                      ),
                                      actualStartTime: _formatActualTime(
                                        entry.date == null
                                            ? null
                                            : actualWorkdayStates[_dateKey(
                                                    entry.date!,
                                                  )]
                                                  ?.actualStart,
                                      ),
                                      actualEndTime: _formatActualTime(
                                        entry.date == null
                                            ? null
                                            : actualWorkdayStates[_dateKey(
                                                    entry.date!,
                                                  )]
                                                  ?.actualEnd,
                                      ),
                                      hoursLabel: _formatHours(entry.hours),
                                      language: language,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _QuotationSectionCard(
                          title: _t(
                            language,
                            en: 'Payment details',
                            de: 'Zahlungsdetails',
                          ),
                          child: LayoutBuilder(
                            builder:
                                (
                                  BuildContext context,
                                  BoxConstraints constraints,
                                ) {
                                  final compact = constraints.maxWidth < 760;
                                  final tileWidth = compact
                                      ? constraints.maxWidth
                                      : (constraints.maxWidth - 16) / 2;
                                  return Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    children: <Widget>[
                                      SizedBox(
                                        width: tileWidth,
                                        child: _QuotationDetailCard(
                                          label: _t(
                                            language,
                                            en: 'Payment method',
                                            de: 'Zahlungsart',
                                          ),
                                          value: invoice
                                              .paymentMethodLabelForLanguage(
                                                language,
                                              ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: tileWidth,
                                        child: _QuotationDetailCard(
                                          label: _t(
                                            language,
                                            en: 'Quotation sent',
                                            de: 'Angebot gesendet',
                                          ),
                                          value: _formatDateTime(
                                            invoice.sentAt,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: constraints.maxWidth,
                                        child: _QuotationDetailCard(
                                          label: _t(
                                            language,
                                            en: 'Payment instructions',
                                            de: 'Zahlungshinweise',
                                          ),
                                          value:
                                              invoice.paymentInstructions
                                                  .trim()
                                                  .isEmpty
                                              ? _t(
                                                  language,
                                                  en: 'No payment instructions added',
                                                  de: 'Keine Zahlungshinweise vorhanden',
                                                )
                                              : invoice.paymentInstructions,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                          ),
                        ),
                        if (invoice.note.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 18),
                          _QuotationSectionCard(
                            title: _t(
                              language,
                              en: 'Service note',
                              de: 'Servicehinweis',
                            ),
                            child: _QuotationBodyText(value: invoice.note),
                          ),
                        ],
                        if (invoice.reviewNote.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 18),
                          _QuotationSectionCard(
                            title: _t(
                              language,
                              en: 'Review note',
                              de: 'Pruefhinweis',
                            ),
                            child: _QuotationBodyText(
                              value: invoice.reviewNote,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: _panelColor(),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              invoice.canCustomerUploadProof
                                  ? _t(
                                      language,
                                      en: 'After you send the bank transfer, return to your request chat and use Upload proof.',
                                      de: 'Nach der Ueberweisung gehen Sie zur Anfrage zurueck und nutzen Sie Beleg hochladen.',
                                    )
                                  : invoice.canCustomerPayOnline
                                  ? _t(
                                      language,
                                      en: 'Return to your request workspace to use the online payment button.',
                                      de: 'Gehen Sie zur Anfrage zurueck, um die Online-Zahlung zu starten.',
                                    )
                                  : invoice.isCustomerPaymentMethodLocked
                                  ? _t(
                                      language,
                                      en: '${invoice.paymentMethodLabelForLanguage(language)} is selected, but this customer payment channel is locked for now. Customer care will confirm the next step.',
                                      de: '${invoice.paymentMethodLabelForLanguage(language)} ist ausgewaehlt, aber diese Zahlungsart ist fuer Kunden aktuell gesperrt. Customer Care bestaetigt den naechsten Schritt.',
                                    )
                                  : _t(
                                      language,
                                      en: 'Return to your request workspace for the next step on this quotation.',
                                      de: 'Gehen Sie zur Anfrage zurueck, um mit diesem Angebot fortzufahren.',
                                    ),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.86),
                                    height: 1.45,
                                  ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QuotationChip extends StatelessWidget {
  const _QuotationChip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _QuotationSectionCard extends StatelessWidget {
  const _QuotationSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.lerp(AppTheme.ink, AppTheme.cobalt, 0.16),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _QuotationMetricCard extends StatelessWidget {
  const _QuotationMetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.68),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotationDetailCard extends StatelessWidget {
  const _QuotationDetailCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.68),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotationWorkdayCard extends StatelessWidget {
  const _QuotationWorkdayCard({
    required this.dateLabel,
    required this.estimatedStartTime,
    required this.estimatedEndTime,
    required this.actualStartTime,
    required this.actualEndTime,
    required this.hoursLabel,
    required this.language,
  });

  final String dateLabel;
  final String estimatedStartTime;
  final String estimatedEndTime;
  final String actualStartTime;
  final String actualEndTime;
  final String hoursLabel;
  final AppLanguage language;

  String _t({required String en, required String de}) {
    return language.pick(en: en, de: de);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              dateLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _QuotationMiniPill(
                  label:
                      '${_t(en: 'Estimated start', de: 'Geplanter Start')}: $estimatedStartTime',
                ),
                _QuotationMiniPill(
                  label:
                      '${_t(en: 'Estimated end', de: 'Geplantes Ende')}: $estimatedEndTime',
                ),
                _QuotationMiniPill(
                  label:
                      '${_t(en: 'Actual start', de: 'Tatsaechlicher Start')}: $actualStartTime',
                ),
                _QuotationMiniPill(
                  label:
                      '${_t(en: 'Actual end', de: 'Tatsaechliches Ende')}: $actualEndTime',
                ),
                _QuotationMiniPill(
                  label:
                      '${_t(en: 'Planned hours', de: 'Geplante Stunden')}: $hoursLabel',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotationMiniPill extends StatelessWidget {
  const _QuotationMiniPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.88),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _QuotationBodyText extends StatelessWidget {
  const _QuotationBodyText({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: Colors.white.withValues(alpha: 0.86),
        height: 1.5,
      ),
    );
  }
}
