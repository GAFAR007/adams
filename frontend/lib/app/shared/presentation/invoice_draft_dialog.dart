library;

import 'package:flutter/material.dart';

import '../../core/models/service_request_model.dart';

const int _mandatoryAppServiceChargePercent = 5;
const int _minimumAdminServiceChargePercent = 5;
const int _maximumAdminServiceChargePercent = 50;
const int _maximumSiteReviewAdminServiceChargePercent = 20;
const int _defaultAdminServiceChargePercent = 5;
const String _defaultSepaPaymentInstructions =
    'SEPA transfer to C L Logistic and Facility Management UG (haftungsbeschraenkt)\n'
    'IBAN: DE04100101236288080859\n'
    'BIC: QNTODEB2XXX\n'
    'Address: Kuenkelstrasse 44, 41063 Moenchengladbach, DE\n'
    'Use your invoice number as the payment reference.';

class InvoiceDraftPlannedDayInput {
  const InvoiceDraftPlannedDayInput({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.hours,
  });

  final String date;
  final String? startTime;
  final String? endTime;
  final double? hours;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'date': date,
      'startTime': startTime,
      'endTime': endTime,
      'hours': hours,
    };
  }
}

class InvoiceDraftInput {
  const InvoiceDraftInput({
    required this.amount,
    required this.adminServiceChargePercent,
    required this.reviewKind,
    required this.dueDate,
    required this.siteReviewDate,
    required this.siteReviewStartTime,
    required this.siteReviewEndTime,
    required this.siteReviewNotes,
    required this.plannedStartDate,
    required this.plannedStartTime,
    required this.plannedEndTime,
    required this.plannedHoursPerDay,
    required this.plannedExpectedEndDate,
    required this.plannedDailySchedule,
    required this.paymentMethod,
    required this.paymentInstructions,
    required this.note,
  });

  final double amount;
  final double adminServiceChargePercent;
  final String reviewKind;
  final String dueDate;
  final String? siteReviewDate;
  final String? siteReviewStartTime;
  final String? siteReviewEndTime;
  final String siteReviewNotes;
  final String? plannedStartDate;
  final String? plannedStartTime;
  final String? plannedEndTime;
  final double? plannedHoursPerDay;
  final String? plannedExpectedEndDate;
  final List<InvoiceDraftPlannedDayInput> plannedDailySchedule;
  final String paymentMethod;
  final String paymentInstructions;
  final String note;
}

class _PlannedWorkDayDraft {
  const _PlannedWorkDayDraft({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.hours,
  });

  final DateTime date;
  final TimeOfDay? startTime;
  final TimeOfDay? endTime;
  final double? hours;
}

class _GeneratedQuotationDraft {
  const _GeneratedQuotationDraft({
    required this.quotedBaseAmount,
    required this.dueDate,
    required this.reviewKind,
    required this.siteReviewDate,
    required this.siteReviewStartTime,
    required this.siteReviewEndTime,
    required this.siteReviewNotes,
    required this.plannedStartDate,
    required this.plannedExpectedEndDate,
    required this.plannedHoursPerDay,
    required this.paymentMethod,
    required this.paymentInstructions,
    required this.note,
  });

  final double quotedBaseAmount;
  final DateTime dueDate;
  final String reviewKind;
  final DateTime? siteReviewDate;
  final String? siteReviewStartTime;
  final String? siteReviewEndTime;
  final String siteReviewNotes;
  final DateTime? plannedStartDate;
  final DateTime? plannedExpectedEndDate;
  final int? plannedHoursPerDay;
  final String paymentMethod;
  final String paymentInstructions;
  final String note;
}

Future<InvoiceDraftInput?> showInvoiceDraftDialog(
  BuildContext context, {
  RequestInvoiceModel? initialInvoice,
  ServiceRequestModel? request,
}) {
  return showDialog<InvoiceDraftInput>(
    context: context,
    builder: (BuildContext dialogContext) {
      return InvoiceDraftDialog(
        initialInvoice: initialInvoice,
        request: request,
      );
    },
  );
}

class InvoiceDraftDialog extends StatefulWidget {
  const InvoiceDraftDialog({
    super.key,
    this.initialInvoice,
    this.request,
    this.title = 'Internal review',
    this.submitLabel = 'Save internal review',
  });

  final RequestInvoiceModel? initialInvoice;
  final ServiceRequestModel? request;
  final String title;
  final String submitLabel;

  @override
  State<InvoiceDraftDialog> createState() => _InvoiceDraftDialogState();
}

class _InvoiceDraftDialogState extends State<InvoiceDraftDialog> {
  late final TextEditingController _quotedBaseAmountController;
  late final TextEditingController _appServiceChargeAmountController;
  late final TextEditingController _customerTotalAmountController;
  late final TextEditingController _dueDateController;
  late final TextEditingController _siteReviewDateController;
  late final TextEditingController _siteReviewStartTimeController;
  late final TextEditingController _siteReviewEndTimeController;
  late final TextEditingController _siteReviewNotesController;
  late final TextEditingController _plannedStartDateController;
  late final TextEditingController _plannedStartTimeController;
  late final TextEditingController _plannedEndTimeController;
  late final TextEditingController _plannedExpectedEndDateController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _noteController;
  late String _paymentMethod;
  late String _reviewKind;
  late bool _usedGeneratedDraft;
  late double _quotedBaseAmount;
  late int _adminServiceChargePercent;
  DateTime? _selectedDueDate;
  DateTime? _siteReviewDate;
  TimeOfDay? _siteReviewStartTime;
  TimeOfDay? _siteReviewEndTime;
  DateTime? _plannedStartDate;
  DateTime? _plannedExpectedEndDate;
  TimeOfDay? _plannedStartTime;
  TimeOfDay? _plannedEndTime;
  int? _plannedHoursPerDay;
  List<_PlannedWorkDayDraft> _plannedDailySchedule = <_PlannedWorkDayDraft>[];

  @override
  void initState() {
    super.initState();
    final initialInvoice = widget.initialInvoice;
    _reviewKind =
        initialInvoice?.kind ??
        widget.request?.quoteReview?.kind ??
        (widget.request?.isSiteReviewPending == true
            ? requestReviewKindSiteReview
            : requestReviewKindQuotation);
    final quoteEstimation = _reviewKind == requestReviewKindSiteReview
        ? widget.request?.siteReviewReadyEstimation
        : widget.request?.quoteReadyEstimation;
    _quotedBaseAmount = _resolveQuotedBaseAmount(
      initialInvoice,
      quoteEstimation,
    );
    _adminServiceChargePercent = _normalizeAdminServiceChargePercent(
      initialInvoice?.adminServiceChargePercent,
    );
    _selectedDueDate =
        initialInvoice?.dueDate ?? DateTime.now().add(const Duration(days: 7));
    _siteReviewDate =
        initialInvoice?.siteReviewDate ??
        widget.request?.quoteReview?.siteReviewDate ??
        quoteEstimation?.siteReviewDate;
    _siteReviewStartTime =
        _parseStoredTime(initialInvoice?.siteReviewStartTime) ??
        _parseStoredTime(widget.request?.quoteReview?.siteReviewStartTime) ??
        _parseStoredTime(quoteEstimation?.siteReviewStartTime);
    _siteReviewEndTime =
        _parseStoredTime(initialInvoice?.siteReviewEndTime) ??
        _parseStoredTime(widget.request?.quoteReview?.siteReviewEndTime) ??
        _parseStoredTime(quoteEstimation?.siteReviewEndTime);
    _plannedStartDate =
        initialInvoice?.plannedStartDate ??
        quoteEstimation?.estimatedStartDate ??
        widget.request?.preferredDate;
    _plannedExpectedEndDate =
        initialInvoice?.plannedExpectedEndDate ??
        quoteEstimation?.estimatedEndDate;
    _plannedStartTime =
        _parseStoredTime(initialInvoice?.plannedStartTime) ??
        const TimeOfDay(hour: 8, minute: 0);
    _quotedBaseAmountController = TextEditingController(
      text: _formatCurrencyAmount(_quotedBaseAmount),
    );
    _appServiceChargeAmountController = TextEditingController(
      text: _formatCurrencyAmount(_appServiceChargeAmount),
    );
    _customerTotalAmountController = TextEditingController(
      text: _formatCurrencyAmount(_customerTotalAmount),
    );
    _dueDateController = TextEditingController(
      text: _formatDate(_selectedDueDate),
    );
    _siteReviewDateController = TextEditingController(
      text: _formatDate(_siteReviewDate),
    );
    _siteReviewStartTimeController = TextEditingController(
      text: _formatTime(_siteReviewStartTime),
    );
    _siteReviewEndTimeController = TextEditingController(
      text: _formatTime(_siteReviewEndTime),
    );
    _siteReviewNotesController = TextEditingController(
      text:
          initialInvoice?.siteReviewNotes ??
          widget.request?.quoteReview?.siteReviewNotes ??
          quoteEstimation?.siteReviewNotes ??
          '',
    );
    _plannedStartDateController = TextEditingController(
      text: _formatDate(_plannedStartDate),
    );
    _plannedStartTimeController = TextEditingController(
      text: _formatTime(_plannedStartTime),
    );
    _plannedHoursPerDay = _normalizeHoursPerDay(
      initialInvoice?.plannedHoursPerDay ??
          _deriveDefaultHoursPerDay(quoteEstimation),
    );
    _syncDefaultEndTime();
    _plannedEndTimeController = TextEditingController(
      text: _formatTime(_plannedEndTime),
    );
    _plannedExpectedEndDate ??= _plannedStartDate;
    _plannedExpectedEndDateController = TextEditingController(
      text: _formatDate(_plannedExpectedEndDate),
    );
    _instructionsController = TextEditingController(
      text:
          initialInvoice?.paymentInstructions ??
          _defaultSepaPaymentInstructions,
    );
    _noteController = TextEditingController(text: initialInvoice?.note ?? '');
    _paymentMethod =
        initialInvoice?.paymentMethod ?? paymentMethodSepaBankTransfer;
    _usedGeneratedDraft = false;
    _plannedDailySchedule = initialInvoice != null
        ? _hydratePlannedDailySchedule(initialInvoice.plannedDailySchedule)
        : _hydrateEstimationDailySchedule(
            quoteEstimation?.estimatedDailySchedule ??
                const <RequestEstimationPlannedDayModel>[],
          );

    if (initialInvoice == null && widget.request != null) {
      _applyGeneratedDraft();
    } else if (_plannedDailySchedule.isEmpty) {
      _rebuildPlannedDailySchedule(resetTimes: true);
    }
  }

  double _roundCurrency(num value) {
    return (value * 100).round() / 100;
  }

  String _formatCurrencyAmount(num value) {
    return _roundCurrency(value).toStringAsFixed(2);
  }

  double _resolveQuotedBaseAmount(
    RequestInvoiceModel? initialInvoice,
    RequestEstimationModel? quoteEstimation,
  ) {
    final estimationCost = _reviewKind == requestReviewKindSiteReview
        ? quoteEstimation?.siteReviewCost
        : quoteEstimation?.cost;
    if (estimationCost != null && estimationCost > 0) {
      return estimationCost;
    }

    final storedQuotedBaseAmount = initialInvoice?.quotedBaseAmount ?? 0;
    if (storedQuotedBaseAmount > 0) {
      return storedQuotedBaseAmount;
    }

    return initialInvoice?.amount ?? 0;
  }

  int _normalizeAdminServiceChargePercent(num? value) {
    final parsedValue = value?.round();
    final maxPercent = _reviewKind == requestReviewKindSiteReview
        ? _maximumSiteReviewAdminServiceChargePercent
        : _maximumAdminServiceChargePercent;
    if (parsedValue == null) {
      return _defaultAdminServiceChargePercent;
    }

    if (parsedValue < _minimumAdminServiceChargePercent) {
      return _minimumAdminServiceChargePercent;
    }
    if (parsedValue > maxPercent) {
      return maxPercent;
    }

    return parsedValue;
  }

  double get _appServiceChargeAmount => _roundCurrency(
    _quotedBaseAmount * (_mandatoryAppServiceChargePercent / 100),
  );

  double get _adminServiceChargeAmount =>
      _roundCurrency(_quotedBaseAmount * (_adminServiceChargePercent / 100));

  double get _customerTotalAmount => _roundCurrency(
    _quotedBaseAmount + _appServiceChargeAmount + _adminServiceChargeAmount,
  );

  void _syncPricingControllers() {
    _quotedBaseAmountController.text = _formatCurrencyAmount(_quotedBaseAmount);
    _appServiceChargeAmountController.text = _formatCurrencyAmount(
      _appServiceChargeAmount,
    );
    _customerTotalAmountController.text = _formatCurrencyAmount(
      _customerTotalAmount,
    );
  }

  String _defaultInstructionsFor(String paymentMethod) {
    return switch (paymentMethod) {
      paymentMethodStripeCheckout =>
        'Pay securely using the hosted checkout link. A receipt will be issued after payment confirms.',
      paymentMethodCashOnCompletion =>
        'Cash payment will be collected on completion. A receipt can be issued once the team confirms payment.',
      _ => _defaultSepaPaymentInstructions,
    };
  }

  _GeneratedQuotationDraft _generateDraftForRequest(
    ServiceRequestModel request,
  ) {
    final estimation = _reviewKind == requestReviewKindSiteReview
        ? request.siteReviewReadyEstimation
        : request.quoteReadyEstimation;
    if (_reviewKind == requestReviewKindSiteReview) {
      final reviewDate = estimation?.siteReviewDate ?? request.preferredDate;
      final reviewStartTime =
          estimation?.siteReviewStartTime.trim().isNotEmpty == true
          ? estimation!.siteReviewStartTime
          : '08:00';
      final reviewEndTime =
          estimation?.siteReviewEndTime.trim().isNotEmpty == true
          ? estimation!.siteReviewEndTime
          : '09:00';
      final reviewCost = estimation?.siteReviewCost ?? estimation?.cost ?? 0;
      final paymentMethod = paymentMethodSepaBankTransfer;
      return _GeneratedQuotationDraft(
        quotedBaseAmount: reviewCost,
        dueDate: DateTime.now().add(const Duration(days: 1)),
        reviewKind: requestReviewKindSiteReview,
        siteReviewDate: reviewDate,
        siteReviewStartTime: reviewStartTime,
        siteReviewEndTime: reviewEndTime,
        siteReviewNotes: estimation?.siteReviewNotes ?? '',
        plannedStartDate: null,
        plannedExpectedEndDate: null,
        plannedHoursPerDay: null,
        paymentMethod: paymentMethod,
        paymentInstructions: _defaultInstructionsFor(paymentMethod),
        note:
            'Site review booking prepared from ${estimation?.submitterStaffTypeLabel.toLowerCase() ?? 'staff'} planning. Customer care will confirm the visit once payment proof is received.',
      );
    }
    const baseAmounts = <String, double>{
      'fire_damage_cleaning': 860,
      'needle_sweeps_sharps_cleanups': 340,
      'hoarding_cleanups': 680,
      'trauma_decomposition_cleanups': 1250,
      'infection_control_cleaning': 420,
      'building_cleaning': 220,
      'window_cleaning': 185,
      'office_cleaning': 240,
      'house_cleaning': 210,
      'warehouse_hall_cleaning': 420,
      'window_glass_cleaning': 185,
      'winter_service': 160,
      'caretaker_service': 260,
      'garden_care': 210,
      'post_construction_cleaning': 360,
    };

    final normalizedMessage = request.message.toLowerCase();
    final normalizedWindow = request.preferredTimeWindow.toLowerCase();
    final keywords = <String, int>{
      'urgent': 45,
      'asap': 45,
      'today': 45,
      'tomorrow': 35,
      'weekend': 30,
      'night': 30,
      'fire': 120,
      'smoke': 80,
      'soot': 90,
      'needle': 60,
      'sharps': 60,
      'hoarding': 140,
      'trauma': 180,
      'decomposition': 220,
      'biohazard': 150,
      'infection': 90,
      'disinfection': 75,
      'odor': 60,
      'odour': 60,
      'dust': 35,
      'machine': 30,
      'deep': 40,
      'glass': 20,
      'warehouse': 35,
      'hall': 25,
      'post-construction': 55,
    };

    var amount = estimation?.cost ?? baseAmounts[request.serviceType] ?? 240;
    if (estimation == null) {
      if (normalizedMessage.length > 110) {
        amount += 35;
      }
      if (normalizedWindow.isNotEmpty &&
          !normalizedWindow.contains('flexible') &&
          !normalizedWindow.contains('business hours')) {
        amount += 20;
      }
      for (final entry in keywords.entries) {
        if (normalizedMessage.contains(entry.key)) {
          amount += entry.value;
        }
      }
    }

    final roundedAmount = ((amount / 5).round() * 5).toDouble();
    final draftDueDate = DateTime.now().add(const Duration(days: 7));
    final paymentMethod = paymentMethodSepaBankTransfer;
    final citySegment = request.city.trim().isEmpty
        ? ''
        : ' in ${request.city}';
    final scopeHint = normalizedMessage.trim().isEmpty
        ? 'based on the service request details already shared'
        : 'based on the current work scope and access details shared in chat';
    final timeWindowNote = request.preferredTimeWindow.trim().isEmpty
        ? ''
        : ' Preferred timing: ${request.preferredTimeWindow.trim()}.';
    final plannedWindowNote =
        estimation?.estimatedStartDate != null &&
            estimation?.estimatedEndDate != null
        ? ' Planned work window: ${_formatDate(estimation!.estimatedStartDate)} to ${_formatDate(estimation.estimatedEndDate)}.'
        : '';
    final effortNote = <String>[
      if (estimation?.estimatedHours != null)
        '${estimation!.estimatedHours!.toStringAsFixed(estimation.estimatedHours! % 1 == 0 ? 0 : 1)}h',
      if (estimation?.effectiveEstimatedDays != null)
        '${estimation!.effectiveEstimatedDays} day${estimation.effectiveEstimatedDays == 1 ? '' : 's'}',
    ].join(' · ');
    final estimationSourceNote = estimation?.submittedBy != null
        ? ' Prepared from the ${estimation!.submitterStaffTypeLabel.toLowerCase()} estimate submitted by ${estimation.submittedBy!.fullName}.'
        : estimation != null
        ? ' Prepared from the selected staff estimate.'
        : '';
    final effortSummary = effortNote.isEmpty
        ? ''
        : ' Estimated effort: $effortNote.';

    return _GeneratedQuotationDraft(
      quotedBaseAmount: roundedAmount,
      dueDate: draftDueDate,
      reviewKind: requestReviewKindQuotation,
      siteReviewDate: null,
      siteReviewStartTime: null,
      siteReviewEndTime: null,
      siteReviewNotes: '',
      plannedStartDate: estimation?.estimatedStartDate ?? request.preferredDate,
      plannedExpectedEndDate: estimation?.estimatedEndDate,
      plannedHoursPerDay: _deriveDefaultHoursPerDay(estimation),
      paymentMethod: paymentMethod,
      paymentInstructions: _defaultInstructionsFor(paymentMethod),
      note:
          'Draft estimate for ${request.serviceLabel}$citySegment, prepared $scopeHint.$timeWindowNote$plannedWindowNote$effortSummary$estimationSourceNote Final price can still be adjusted after final review if scope or site access changes.',
    );
  }

  void _applyGeneratedDraft() {
    final request = widget.request;
    if (request == null) {
      return;
    }

    final generated = _generateDraftForRequest(request);
    final hasExistingPlannedSchedule = _plannedDailySchedule.isNotEmpty;
    _reviewKind = generated.reviewKind;
    _quotedBaseAmount = generated.quotedBaseAmount;
    _syncPricingControllers();
    _selectedDueDate = generated.dueDate;
    _dueDateController.text = _formatDate(generated.dueDate);
    _siteReviewDate = generated.siteReviewDate;
    _siteReviewDateController.text = _formatDate(generated.siteReviewDate);
    _siteReviewStartTime = _parseStoredTime(generated.siteReviewStartTime);
    _siteReviewEndTime = _parseStoredTime(generated.siteReviewEndTime);
    _siteReviewStartTimeController.text = _formatTime(_siteReviewStartTime);
    _siteReviewEndTimeController.text = _formatTime(_siteReviewEndTime);
    _siteReviewNotesController.text = generated.siteReviewNotes;
    _plannedStartDate = generated.plannedStartDate;
    _plannedStartDateController.text = _formatDate(generated.plannedStartDate);
    _plannedExpectedEndDate = generated.plannedExpectedEndDate;
    _plannedExpectedEndDateController.text = _formatDate(
      generated.plannedExpectedEndDate,
    );
    _plannedHoursPerDay = generated.plannedHoursPerDay;
    _plannedStartTime ??= const TimeOfDay(hour: 8, minute: 0);
    _plannedStartTimeController.text = _formatTime(_plannedStartTime);
    _syncDefaultEndTime();
    _plannedEndTimeController.text = _formatTime(_plannedEndTime);
    if (!hasExistingPlannedSchedule) {
      _maybeSyncExpectedEndDate();
    }
    _rebuildPlannedDailySchedule(resetTimes: !hasExistingPlannedSchedule);
    _paymentMethod = generated.paymentMethod;
    _instructionsController.text = generated.paymentInstructions;
    _noteController.text = generated.note;
    _usedGeneratedDraft = true;
  }

  @override
  void dispose() {
    _quotedBaseAmountController.dispose();
    _appServiceChargeAmountController.dispose();
    _customerTotalAmountController.dispose();
    _dueDateController.dispose();
    _siteReviewDateController.dispose();
    _siteReviewStartTimeController.dispose();
    _siteReviewEndTimeController.dispose();
    _siteReviewNotesController.dispose();
    _plannedStartDateController.dispose();
    _plannedStartTimeController.dispose();
    _plannedEndTimeController.dispose();
    _plannedExpectedEndDateController.dispose();
    _instructionsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }

    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  String _formatNumber(num value) {
    if (value % 1 == 0) {
      return value.toStringAsFixed(0);
    }

    return value.toStringAsFixed(1);
  }

  int? _normalizeHoursPerDay(num? value) {
    if (value == null || value <= 0) {
      return null;
    }

    return value.round().clamp(1, 10);
  }

  int? _deriveDefaultHoursPerDay(RequestEstimationModel? estimation) {
    if (estimation == null) {
      return null;
    }

    final directHoursPerDay = _normalizeHoursPerDay(
      estimation.estimatedHoursPerDay,
    );
    if (directHoursPerDay != null) {
      return directHoursPerDay;
    }

    final totalHours = estimation.estimatedHours;
    final totalDays = estimation.effectiveEstimatedDays;
    if (totalHours == null ||
        totalHours <= 0 ||
        totalDays == null ||
        totalDays <= 0) {
      return null;
    }

    return _normalizeHoursPerDay(totalHours / totalDays);
  }

  String _toIsoDate(DateTime value) => value.toIso8601String().split('T').first;

  DateTime _normalizeDate(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  TimeOfDay? _parseStoredTime(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }

    final parts = raw.split(':');
    if (parts.length != 2) {
      return null;
    }

    final hour = int.tryParse(parts.first);
    final minute = int.tryParse(parts.last);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  String _formatStorageTime(TimeOfDay? value) {
    if (value == null) {
      return '';
    }

    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTime(TimeOfDay? value) {
    if (value == null) {
      return '';
    }

    final hour = value.hourOfPeriod == 0 ? 12 : value.hourOfPeriod;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $suffix';
  }

  String _formatDayLabel(DateTime value) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${_formatDate(value)} (${weekdays[value.weekday - 1]})';
  }

  List<_PlannedWorkDayDraft> _hydratePlannedDailySchedule(
    List<RequestInvoicePlannedDayModel> schedule,
  ) {
    return schedule
        .where((entry) => entry.date != null)
        .map(
          (entry) => _PlannedWorkDayDraft(
            date: _normalizeDate(entry.date!),
            startTime: _parseStoredTime(entry.startTime),
            endTime: _parseStoredTime(entry.endTime),
            hours:
                entry.hours ??
                _calculateHoursBetween(
                  _parseStoredTime(entry.startTime),
                  _parseStoredTime(entry.endTime),
                ),
          ),
        )
        .toList();
  }

  List<_PlannedWorkDayDraft> _hydrateEstimationDailySchedule(
    List<RequestEstimationPlannedDayModel> schedule,
  ) {
    return schedule
        .where((entry) => entry.date != null)
        .map(
          (entry) => _PlannedWorkDayDraft(
            date: _normalizeDate(entry.date!),
            startTime: _parseStoredTime(entry.startTime),
            endTime: _parseStoredTime(entry.endTime),
            hours:
                entry.hours ??
                _calculateHoursBetween(
                  _parseStoredTime(entry.startTime),
                  _parseStoredTime(entry.endTime),
                ),
          ),
        )
        .toList();
  }

  double? _calculateHoursBetween(TimeOfDay? start, TimeOfDay? end) {
    if (start == null || end == null) {
      return null;
    }

    final startMinutes = (start.hour * 60) + start.minute;
    final endMinutes = (end.hour * 60) + end.minute;
    var diffMinutes = endMinutes - startMinutes;
    if (diffMinutes <= 0) {
      diffMinutes += 24 * 60;
    }
    if (diffMinutes <= 0) {
      return null;
    }

    return diffMinutes / 60;
  }

  TimeOfDay? _addHoursToTime(TimeOfDay? start, num? hours) {
    if (start == null || hours == null || hours <= 0) {
      return null;
    }

    final totalMinutes =
        (start.hour * 60) + start.minute + (hours * 60).round();
    final normalizedMinutes = totalMinutes % (24 * 60);

    return TimeOfDay(
      hour: normalizedMinutes ~/ 60,
      minute: normalizedMinutes % 60,
    );
  }

  void _syncDefaultEndTime() {
    _plannedEndTime = _addHoursToTime(_plannedStartTime, _plannedHoursPerDay);
  }

  int? _derivePlannedDayCount(int? hoursPerDay) {
    if (hoursPerDay == null || hoursPerDay <= 0) {
      return null;
    }

    final estimation = widget.request?.quoteReadyEstimation;
    final totalHours = estimation?.estimatedHours;
    if (totalHours != null && totalHours > 0) {
      return (totalHours / hoursPerDay).ceil();
    }

    return estimation?.effectiveEstimatedDays;
  }

  void _maybeSyncExpectedEndDate() {
    final startDate = _plannedStartDate;
    if (startDate == null) {
      return;
    }

    final totalDays = _derivePlannedDayCount(_plannedHoursPerDay);
    if (totalDays == null || totalDays <= 0) {
      _plannedExpectedEndDate ??= startDate;
      _plannedExpectedEndDateController.text = _formatDate(
        _plannedExpectedEndDate,
      );
      return;
    }

    _plannedExpectedEndDate = startDate.add(Duration(days: totalDays - 1));
    _plannedExpectedEndDateController.text = _formatDate(
      _plannedExpectedEndDate,
    );
  }

  Future<void> _pickPlannedStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _plannedStartDate ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _plannedStartDate = selected;
      _plannedStartDateController.text = _formatDate(selected);
      if (_plannedExpectedEndDate == null ||
          _plannedExpectedEndDate!.isBefore(selected)) {
        _plannedExpectedEndDate = selected;
      }
      _maybeSyncExpectedEndDate();
      _plannedExpectedEndDateController.text = _formatDate(
        _plannedExpectedEndDate,
      );
      _rebuildPlannedDailySchedule(resetTimes: false);
    });
  }

  Future<void> _pickPlannedExpectedEndDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate:
          _plannedExpectedEndDate ?? _plannedStartDate ?? DateTime.now(),
      firstDate: _plannedStartDate ?? DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _plannedExpectedEndDate = selected;
      _plannedExpectedEndDateController.text = _formatDate(selected);
      _rebuildPlannedDailySchedule(resetTimes: false);
    });
  }

  void _rebuildPlannedDailySchedule({required bool resetTimes}) {
    final startDate = _plannedStartDate;
    final endDate = _plannedExpectedEndDate;
    if (startDate == null || endDate == null) {
      _plannedDailySchedule = <_PlannedWorkDayDraft>[];
      return;
    }

    final normalizedStart = _normalizeDate(startDate);
    final normalizedEnd = _normalizeDate(endDate);
    if (normalizedEnd.isBefore(normalizedStart)) {
      _plannedDailySchedule = <_PlannedWorkDayDraft>[];
      return;
    }

    final existingByDate = <String, _PlannedWorkDayDraft>{
      for (final entry in _plannedDailySchedule) _toIsoDate(entry.date): entry,
    };
    final defaultEndTime = _addHoursToTime(
      _plannedStartTime,
      _plannedHoursPerDay,
    );
    final rebuilt = <_PlannedWorkDayDraft>[];

    for (
      var cursor = normalizedStart;
      !cursor.isAfter(normalizedEnd);
      cursor = cursor.add(const Duration(days: 1))
    ) {
      final existing = existingByDate[_toIsoDate(cursor)];
      if (!resetTimes && existing != null) {
        rebuilt.add(existing);
        continue;
      }

      rebuilt.add(
        _PlannedWorkDayDraft(
          date: cursor,
          startTime: _plannedStartTime,
          endTime: defaultEndTime,
          hours: _plannedHoursPerDay?.toDouble(),
        ),
      );
    }

    _plannedDailySchedule = rebuilt;
  }

  bool get _isSiteReviewMode => _reviewKind == requestReviewKindSiteReview;

  Future<void> _pickSiteReviewDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _siteReviewDate ?? DateTime.now(),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected == null) {
      return;
    }

    setState(() {
      _siteReviewDate = selected;
      _siteReviewDateController.text = _formatDate(selected);
    });
  }

  Future<void> _pickSiteReviewTime({required bool isStart}) async {
    final selected = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (_siteReviewStartTime ?? const TimeOfDay(hour: 8, minute: 0))
          : (_siteReviewEndTime ?? const TimeOfDay(hour: 9, minute: 0)),
    );
    if (selected == null) {
      return;
    }

    setState(() {
      if (isStart) {
        _siteReviewStartTime = selected;
        _siteReviewStartTimeController.text = _formatTime(selected);
        _siteReviewEndTime ??=
            _addHoursToTime(selected, 1) ?? const TimeOfDay(hour: 9, minute: 0);
        _siteReviewEndTimeController.text = _formatTime(_siteReviewEndTime);
      } else {
        _siteReviewEndTime = selected;
        _siteReviewEndTimeController.text = _formatTime(selected);
      }
    });
  }

  Future<void> _pickPlanningTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _plannedStartTime ?? const TimeOfDay(hour: 8, minute: 0),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _plannedStartTime = selected;
      _plannedStartTimeController.text = _formatTime(selected);
      _syncDefaultEndTime();
      _plannedEndTimeController.text = _formatTime(_plannedEndTime);
      _rebuildPlannedDailySchedule(resetTimes: true);
    });
  }

  Future<void> _pickDailyScheduleTime(
    int index, {
    required bool isStart,
  }) async {
    final current = _plannedDailySchedule[index];
    final selected = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (current.startTime ??
                _plannedStartTime ??
                const TimeOfDay(hour: 8, minute: 0))
          : (current.endTime ??
                _plannedEndTime ??
                const TimeOfDay(hour: 17, minute: 0)),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      final hoursBasis = current.hours ?? _plannedHoursPerDay?.toDouble();
      final updatedEntry = isStart
          ? _PlannedWorkDayDraft(
              date: current.date,
              startTime: selected,
              endTime: _addHoursToTime(selected, hoursBasis),
              hours: hoursBasis,
            )
          : _PlannedWorkDayDraft(
              date: current.date,
              startTime: current.startTime,
              endTime: selected,
              hours: _calculateHoursBetween(current.startTime, selected),
            );
      _plannedDailySchedule = <_PlannedWorkDayDraft>[
        for (var i = 0; i < _plannedDailySchedule.length; i += 1)
          i == index ? updatedEntry : _plannedDailySchedule[i],
      ];
    });
  }

  Future<void> _pickDueDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _selectedDueDate = selected;
      _dueDateController.text = _formatDate(selected);
    });
  }

  void _submit() {
    final dueDate = _selectedDueDate;
    final instructions = _instructionsController.text.trim();
    final hasPlanningValues =
        !_isSiteReviewMode &&
        (_plannedStartDate != null ||
            _plannedExpectedEndDate != null ||
            _plannedStartTime != null ||
            _plannedHoursPerDay != null ||
            _plannedDailySchedule.isNotEmpty);

    if (_quotedBaseAmount <= 0) {
      _showError('A valid staff or contractor estimate is required');
      return;
    }

    if (dueDate == null) {
      _showError('Choose a due date');
      return;
    }

    if (instructions.length < 4) {
      _showError('Add payment instructions');
      return;
    }

    if (_isSiteReviewMode) {
      if (_siteReviewDate == null) {
        _showError('Choose the site review date');
        return;
      }
      if (_siteReviewStartTime == null || _siteReviewEndTime == null) {
        _showError('Choose the site review time');
        return;
      }
      final reviewHours = _calculateHoursBetween(
        _siteReviewStartTime,
        _siteReviewEndTime,
      );
      if (reviewHours == null || reviewHours <= 0) {
        _showError('Site review end time must be after the start time');
        return;
      }
    }

    if (hasPlanningValues) {
      if (_plannedStartDate == null) {
        _showError('Choose a planned start date');
        return;
      }
      if (_plannedExpectedEndDate == null) {
        _showError('Choose an expected end date');
        return;
      }
      if (_plannedExpectedEndDate!.isBefore(_plannedStartDate!)) {
        _showError(
          'Expected end date must be on or after the planned start date',
        );
        return;
      }
      if (_plannedStartTime == null || _plannedEndTime == null) {
        _showError('Choose a daily start time and hours per day');
        return;
      }
      if (_plannedHoursPerDay == null || _plannedHoursPerDay! < 1) {
        _showError('Choose hours per day');
        return;
      }
      if (_plannedDailySchedule.isEmpty) {
        _showError('Review the daily work plan');
        return;
      }
      for (final entry in _plannedDailySchedule) {
        if (entry.startTime == null || entry.endTime == null) {
          _showError('Each planned workday needs a start and end time');
          return;
        }
        final entryHours =
            entry.hours ??
            _calculateHoursBetween(entry.startTime, entry.endTime);
        if (entryHours == null || entryHours <= 0 || entryHours > 10) {
          _showError('Each planned workday must stay between 1 and 10 hours');
          return;
        }
      }
      if (_plannedDailySchedule.length !=
          _normalizeDate(
                _plannedExpectedEndDate!,
              ).difference(_normalizeDate(_plannedStartDate!)).inDays +
              1) {
        _showError('The daily work plan must cover every day in the range');
        return;
      }
    }

    Navigator.of(context).pop(
      InvoiceDraftInput(
        amount: _customerTotalAmount,
        adminServiceChargePercent: _adminServiceChargePercent.toDouble(),
        reviewKind: _reviewKind,
        dueDate: _toIsoDate(dueDate),
        // WHY: Quotation reviews must not submit stale site-review timing fields;
        // the backend validator treats empty strings as invalid instead of absent.
        siteReviewDate: !_isSiteReviewMode || _siteReviewDate == null
            ? null
            : _toIsoDate(_siteReviewDate!),
        siteReviewStartTime: !_isSiteReviewMode || _siteReviewStartTime == null
            ? null
            : _formatStorageTime(_siteReviewStartTime),
        siteReviewEndTime: !_isSiteReviewMode || _siteReviewEndTime == null
            ? null
            : _formatStorageTime(_siteReviewEndTime),
        siteReviewNotes: _isSiteReviewMode
            ? _siteReviewNotesController.text.trim()
            : '',
        plannedStartDate: _isSiteReviewMode || _plannedStartDate == null
            ? null
            : _toIsoDate(_plannedStartDate!),
        plannedStartTime: _isSiteReviewMode || _plannedStartTime == null
            ? null
            : _formatStorageTime(_plannedStartTime),
        plannedEndTime: _isSiteReviewMode || _plannedEndTime == null
            ? null
            : _formatStorageTime(_plannedEndTime),
        plannedHoursPerDay: _isSiteReviewMode
            ? null
            : _plannedHoursPerDay?.toDouble(),
        plannedExpectedEndDate:
            _isSiteReviewMode || _plannedExpectedEndDate == null
            ? null
            : _toIsoDate(_plannedExpectedEndDate!),
        plannedDailySchedule: _isSiteReviewMode
            ? const <InvoiceDraftPlannedDayInput>[]
            : _plannedDailySchedule
                  .map(
                    (entry) => InvoiceDraftPlannedDayInput(
                      date: _toIsoDate(entry.date),
                      startTime: _formatStorageTime(entry.startTime),
                      endTime: _formatStorageTime(entry.endTime),
                      hours:
                          entry.hours ??
                          _calculateHoursBetween(
                            entry.startTime,
                            entry.endTime,
                          ),
                    ),
                  )
                  .toList(),
        paymentMethod: _paymentMethod,
        paymentInstructions: instructions,
        note: _noteController.text.trim(),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final quoteEstimation = _isSiteReviewMode
        ? widget.request?.siteReviewReadyEstimation
        : widget.request?.quoteReadyEstimation;

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.request != null) ...<Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _usedGeneratedDraft
                                    ? _isSiteReviewMode
                                          ? 'AI draft filled for this site review'
                                          : 'AI draft filled from this request'
                                    : _isSiteReviewMode
                                    ? 'Use a quick AI draft for this site review'
                                    : 'Use a quick AI draft for this request',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isSiteReviewMode
                                    ? 'Review the site-review timing, payment option, and booking note before customer care sends the booking invoice.'
                                    : 'Review the planned timing, payment option, and customer note before customer care sends the quotation.',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(height: 1.35),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _isSiteReviewMode
                                    ? 'The generated draft keeps the payment option editable so internal review can finish before the customer-care handoff.'
                                    : 'The generated draft keeps the payment option editable so internal review can be finished before the customer-care handoff.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      height: 1.3,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color
                                          ?.withValues(alpha: 0.72),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(_applyGeneratedDraft);
                          },
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _usedGeneratedDraft ? 'Regenerate' : 'Generate',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (quoteEstimation?.submittedBy != null) ...<Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _isSiteReviewMode
                        ? 'Site review from ${quoteEstimation!.submittedBy!.fullName} · ${quoteEstimation.submitterStaffTypeLabel}'
                        : 'Estimate from ${quoteEstimation!.submittedBy!.fullName} · ${quoteEstimation.submitterStaffTypeLabel}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_isSiteReviewMode) ...<Widget>[
                TextField(
                  controller: _siteReviewDateController,
                  readOnly: true,
                  onTap: _pickSiteReviewDate,
                  decoration: const InputDecoration(
                    labelText: 'Site review date',
                    suffixIcon: Icon(Icons.event_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _siteReviewStartTimeController,
                        readOnly: true,
                        onTap: () => _pickSiteReviewTime(isStart: true),
                        decoration: const InputDecoration(
                          labelText: 'Site review start time',
                          suffixIcon: Icon(Icons.schedule_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _siteReviewEndTimeController,
                        readOnly: true,
                        onTap: () => _pickSiteReviewTime(isStart: false),
                        decoration: const InputDecoration(
                          labelText: 'Site review end time',
                          suffixIcon: Icon(Icons.schedule_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _siteReviewNotesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Site review notes',
                    hintText: 'Optional note shown with the booking details',
                  ),
                ),
              ] else ...<Widget>[
                TextField(
                  controller: _plannedStartDateController,
                  readOnly: true,
                  onTap: _pickPlannedStartDate,
                  decoration: const InputDecoration(
                    labelText: 'Planned start date',
                    suffixIcon: Icon(Icons.event_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _plannedStartTimeController,
                        readOnly: true,
                        onTap: _pickPlanningTime,
                        decoration: const InputDecoration(
                          labelText: 'Daily start time',
                          suffixIcon: Icon(Icons.schedule_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _plannedEndTimeController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Daily end time',
                          suffixIcon: Icon(Icons.schedule_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _plannedHoursPerDay,
                  decoration: const InputDecoration(labelText: 'Hours per day'),
                  items: List<DropdownMenuItem<int>>.generate(
                    10,
                    (index) => DropdownMenuItem<int>(
                      value: index + 1,
                      child: Text('${index + 1} h'),
                    ),
                  ),
                  onChanged: (int? value) {
                    setState(() {
                      _plannedHoursPerDay = value;
                      _syncDefaultEndTime();
                      _plannedEndTimeController.text = _formatTime(
                        _plannedEndTime,
                      );
                      _maybeSyncExpectedEndDate();
                      _rebuildPlannedDailySchedule(resetTimes: true);
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _plannedExpectedEndDateController,
                  readOnly: true,
                  onTap: _pickPlannedExpectedEndDate,
                  decoration: const InputDecoration(
                    labelText: 'Expected end date',
                    suffixIcon: Icon(Icons.event_available_rounded),
                  ),
                ),
              ],
              if (!_isSiteReviewMode &&
                  _plannedDailySchedule.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Daily work plan',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ..._plannedDailySchedule.asMap().entries.map((entry) {
                  final index = entry.key;
                  final day = entry.value;
                  final dayHours =
                      day.hours ??
                      _calculateHoursBetween(day.startTime, day.endTime);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.32),
                        ),
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.22),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _formatDayLabel(day.date),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _pickDailyScheduleTime(
                                      index,
                                      isStart: true,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    child: InputDecorator(
                                      decoration: const InputDecoration(
                                        labelText: 'Start time',
                                        suffixIcon: Icon(
                                          Icons.schedule_rounded,
                                        ),
                                      ),
                                      child: Text(_formatTime(day.startTime)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _pickDailyScheduleTime(
                                      index,
                                      isStart: false,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    child: InputDecorator(
                                      decoration: const InputDecoration(
                                        labelText: 'End time',
                                        suffixIcon: Icon(
                                          Icons.schedule_rounded,
                                        ),
                                      ),
                                      child: Text(_formatTime(day.endTime)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              dayHours == null
                                  ? 'Hours pending'
                                  : '${_formatNumber(dayHours)} hours planned',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withValues(alpha: 0.76),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _quotedBaseAmountController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: _isSiteReviewMode
                      ? 'Base site review charge from staff / contractor (EUR)'
                      : 'Base quote from staff / contractor (EUR)',
                  prefixText: 'EUR ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _appServiceChargeAmountController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Mandatory app service charge (5%)',
                  prefixText: 'EUR ',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _adminServiceChargePercent,
                decoration: const InputDecoration(
                  labelText: 'Admin service charge',
                ),
                items: List<DropdownMenuItem<int>>.generate(
                  (((_isSiteReviewMode
                                  ? _maximumSiteReviewAdminServiceChargePercent
                                  : _maximumAdminServiceChargePercent) -
                              _minimumAdminServiceChargePercent) ~/
                          5) +
                      1,
                  (index) {
                    final value =
                        _minimumAdminServiceChargePercent + (index * 5);
                    return DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value%'),
                    );
                  },
                ),
                onChanged: (int? value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _adminServiceChargePercent =
                        _normalizeAdminServiceChargePercent(value);
                    _syncPricingControllers();
                  });
                },
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _isSiteReviewMode
                      ? 'Adds EUR ${_formatCurrencyAmount(_adminServiceChargeAmount)} internally to the site review booking. Customer only sees the total service cost.'
                      : 'Adds EUR ${_formatCurrencyAmount(_adminServiceChargeAmount)} internally. Customer only sees the total service cost.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withValues(alpha: 0.72),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _customerTotalAmountController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Total shown to customer (EUR)',
                  prefixText: 'EUR ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dueDateController,
                readOnly: true,
                onTap: _pickDueDate,
                decoration: const InputDecoration(
                  labelText: 'Due date',
                  suffixIcon: Icon(Icons.event_rounded),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment option'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: paymentMethodSepaBankTransfer,
                    child: Text('SEPA bank transfer'),
                  ),
                  DropdownMenuItem(
                    value: paymentMethodStripeCheckout,
                    child: Text('Online card / wallet payment'),
                  ),
                  DropdownMenuItem(
                    value: paymentMethodCashOnCompletion,
                    child: Text('Cash on completion'),
                  ),
                ],
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _paymentMethod = value;
                    _instructionsController.text = _defaultInstructionsFor(
                      value,
                    );
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _instructionsController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Payment instructions or checkout note',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: _isSiteReviewMode
                      ? 'Customer booking note'
                      : 'Customer note',
                  hintText: _isSiteReviewMode
                      ? 'Optional note to show on the site review booking card'
                      : 'Optional note to show on the quotation page',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.submitLabel)),
      ],
    );
  }
}
