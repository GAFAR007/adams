library;

import 'package:flutter/material.dart';

import '../../core/models/service_request_model.dart';

class RequestEstimationPlannedDayInput {
  const RequestEstimationPlannedDayInput({
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

class RequestEstimationDraftInput {
  const RequestEstimationDraftInput({
    required this.assessmentType,
    required this.assessmentStatus,
    required this.stage,
    required this.siteReviewDate,
    required this.siteReviewStartTime,
    required this.siteReviewEndTime,
    required this.siteReviewCost,
    required this.siteReviewNotes,
    required this.estimatedStartDate,
    required this.estimatedEndDate,
    required this.estimatedHoursPerDay,
    required this.estimatedHours,
    required this.estimatedDays,
    required this.estimatedDailySchedule,
    required this.cost,
    required this.note,
    required this.inspectionNote,
  });

  final String assessmentType;
  final String assessmentStatus;
  final String stage;
  final String? siteReviewDate;
  final String? siteReviewStartTime;
  final String? siteReviewEndTime;
  final double? siteReviewCost;
  final String siteReviewNotes;
  final String? estimatedStartDate;
  final String? estimatedEndDate;
  final double? estimatedHoursPerDay;
  final double? estimatedHours;
  final int? estimatedDays;
  final List<RequestEstimationPlannedDayInput> estimatedDailySchedule;
  final double? cost;
  final String note;
  final String inspectionNote;
}

enum RequestEstimationDialogMode {
  standard,
  siteReviewBooking,
  finalEstimateAfterReview,
}

Future<RequestEstimationDraftInput?> showRequestEstimationDialog(
  BuildContext context, {
  required ServiceRequestModel request,
  RequestEstimationModel? initialEstimation,
  RequestEstimationDialogMode mode = RequestEstimationDialogMode.standard,
}) {
  return showDialog<RequestEstimationDraftInput>(
    context: context,
    builder: (BuildContext dialogContext) {
      return _RequestEstimationDialog(
        request: request,
        initialEstimation: initialEstimation,
        mode: mode,
      );
    },
  );
}

class _EstimatedWorkDayDraft {
  const _EstimatedWorkDayDraft({
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

class _RequestEstimationDialog extends StatefulWidget {
  const _RequestEstimationDialog({
    required this.request,
    this.initialEstimation,
    required this.mode,
  });

  final ServiceRequestModel request;
  final RequestEstimationModel? initialEstimation;
  final RequestEstimationDialogMode mode;

  @override
  State<_RequestEstimationDialog> createState() =>
      _RequestEstimationDialogState();
}

class _RequestEstimationDialogState extends State<_RequestEstimationDialog> {
  static const String _assessmentTypeRemoteReview = 'remote_review';
  static const String _assessmentTypeSiteReviewRequired =
      'site_review_required';
  static const String _assessmentStatusAwaitingReview = 'awaiting_review';
  static const String _assessmentStatusAwaitingCustomerMedia =
      'awaiting_customer_media';
  static const String _assessmentStatusSiteVisitRequired =
      'site_visit_required';
  static const String _assessmentStatusSiteVisitScheduled =
      'site_visit_scheduled';
  static const String _assessmentStatusSiteVisitCompleted =
      'site_visit_completed';
  static const String _estimationStageDraft = 'draft';
  static const String _estimationStageFinal = 'final';

  late final TextEditingController _startDateController;
  late final TextEditingController _endDateController;
  late final TextEditingController _siteReviewDateController;
  late final TextEditingController _siteReviewStartTimeController;
  late final TextEditingController _siteReviewEndTimeController;
  late final TextEditingController _siteReviewCostController;
  late final TextEditingController _siteReviewNotesController;
  late final TextEditingController _costController;
  late final TextEditingController _noteController;
  late final TextEditingController _inspectionNoteController;
  late DateTime _estimatedStartDate;
  late DateTime _estimatedEndDate;
  DateTime? _siteReviewDate;
  TimeOfDay? _siteReviewStartTime;
  TimeOfDay? _siteReviewEndTime;
  late int _hoursPerDay;
  late String _assessmentType;
  late String _assessmentStatus;
  late String _stage;
  List<_EstimatedWorkDayDraft> _estimatedDailySchedule =
      <_EstimatedWorkDayDraft>[];

  bool get _isSiteReviewBookingMode =>
      widget.mode == RequestEstimationDialogMode.siteReviewBooking;

  bool get _isFinalEstimateMode =>
      widget.mode == RequestEstimationDialogMode.finalEstimateAfterReview;

  bool get _hasLockedWorkflowMode =>
      _isSiteReviewBookingMode || _isFinalEstimateMode;

  @override
  void initState() {
    super.initState();
    final initialEstimation = widget.initialEstimation;
    _estimatedStartDate =
        initialEstimation?.estimatedStartDate ??
        widget.request.preferredDate ??
        DateTime.now();
    _estimatedEndDate =
        initialEstimation?.estimatedEndDate ?? _estimatedStartDate;
    _hoursPerDay = _normalizeHoursPerDay(
      initialEstimation?.estimatedHoursPerDay,
    );
    _assessmentType = _resolveInitialAssessmentType();
    _assessmentStatus = _resolveInitialAssessmentStatus();
    _stage = _resolveInitialStage();
    _startDateController = TextEditingController(
      text: _formatDate(_estimatedStartDate),
    );
    _endDateController = TextEditingController(
      text: _formatDate(_estimatedEndDate),
    );
    _siteReviewDate = initialEstimation?.siteReviewDate;
    _siteReviewStartTime = _parseStoredTime(
      initialEstimation?.siteReviewStartTime,
    );
    _siteReviewEndTime = _parseStoredTime(initialEstimation?.siteReviewEndTime);
    _siteReviewDateController = TextEditingController(
      text: _siteReviewDate == null ? '' : _formatDate(_siteReviewDate!),
    );
    _siteReviewStartTimeController = TextEditingController(
      text: _formatTime(_siteReviewStartTime),
    );
    _siteReviewEndTimeController = TextEditingController(
      text: _formatTime(_siteReviewEndTime),
    );
    _siteReviewCostController = TextEditingController(
      text: initialEstimation?.siteReviewCost == null
          ? ''
          : initialEstimation!.siteReviewCost!.toStringAsFixed(2),
    );
    _siteReviewNotesController = TextEditingController(
      text: initialEstimation?.siteReviewNotes ?? '',
    );
    _costController = TextEditingController(
      text: initialEstimation == null
          ? ''
          : initialEstimation.cost.toStringAsFixed(2),
    );
    _noteController = TextEditingController(
      text: initialEstimation?.note ?? '',
    );
    _inspectionNoteController = TextEditingController(
      text: initialEstimation?.inspectionNote ?? '',
    );
    _estimatedDailySchedule = _hydrateDailySchedule(
      initialEstimation?.estimatedDailySchedule ??
          const <RequestEstimationPlannedDayModel>[],
    );
    _rebuildDailySchedule(resetTimes: _estimatedDailySchedule.isEmpty);
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    _siteReviewDateController.dispose();
    _siteReviewStartTimeController.dispose();
    _siteReviewEndTimeController.dispose();
    _siteReviewCostController.dispose();
    _siteReviewNotesController.dispose();
    _costController.dispose();
    _noteController.dispose();
    _inspectionNoteController.dispose();
    super.dispose();
  }

  TimeOfDay get _defaultStartTime => const TimeOfDay(hour: 8, minute: 0);

  bool get _isSiteReviewPending =>
      _assessmentType == _assessmentTypeSiteReviewRequired &&
      _assessmentStatus != _assessmentStatusSiteVisitCompleted;

  String _resolveInitialAssessmentType() {
    if (_isSiteReviewBookingMode || _isFinalEstimateMode) {
      return _assessmentTypeSiteReviewRequired;
    }

    return widget.request.assessmentType ?? _assessmentTypeRemoteReview;
  }

  String _resolveInitialAssessmentStatus() {
    if (_isFinalEstimateMode) {
      return _assessmentStatusSiteVisitCompleted;
    }
    if (_isSiteReviewBookingMode) {
      return _assessmentStatusSiteVisitScheduled;
    }

    final currentValue = widget.request.assessmentStatus;
    final validStatuses = _assessmentStatusOptionsFor(_assessmentType);
    if (currentValue != null && validStatuses.contains(currentValue)) {
      return currentValue;
    }

    if (_assessmentType == _assessmentTypeSiteReviewRequired) {
      return _assessmentStatusSiteVisitRequired;
    }

    return _assessmentStatusAwaitingReview;
  }

  String _resolveInitialStage() {
    if (_isSiteReviewBookingMode) {
      return _estimationStageDraft;
    }
    if (_isFinalEstimateMode) {
      return _estimationStageFinal;
    }

    return widget.initialEstimation?.stage ?? _estimationStageFinal;
  }

  String _dialogTitle(bool isUpdating) {
    switch (widget.mode) {
      case RequestEstimationDialogMode.siteReviewBooking:
        return isUpdating ? 'Update site review' : 'Book site review';
      case RequestEstimationDialogMode.finalEstimateAfterReview:
        return isUpdating ? 'Update final estimate' : 'Create final estimate';
      case RequestEstimationDialogMode.standard:
        if (_assessmentType == _assessmentTypeSiteReviewRequired) {
          return _isSiteReviewPending
              ? (isUpdating ? 'Update site review' : 'Book site review')
              : (isUpdating
                    ? 'Update estimate after review'
                    : 'Create estimate after review');
        }
        return isUpdating ? 'Update estimate' : 'Create estimate';
    }
  }

  String _dialogSummary() {
    switch (widget.mode) {
      case RequestEstimationDialogMode.siteReviewBooking:
        return 'Book the review date, time, and review charge. Saving from this flow marks the review as scheduled so it appears on the calendar.';
      case RequestEstimationDialogMode.finalEstimateAfterReview:
        return 'Use this after the review visit to submit the actual work estimate. Saving from this flow marks the site review as completed and sends the estimate for admin review.';
      case RequestEstimationDialogMode.standard:
        if (_assessmentType == _assessmentTypeSiteReviewRequired) {
          return _isSiteReviewPending
              ? 'Book the review date, time, and review charge. Saving from this form marks the review as scheduled so it appears on the calendar.'
              : 'Use this after the review visit to submit the actual work estimate. Saving from this form sends the estimate for admin review.';
        }
        return _stage == _estimationStageDraft
            ? 'Draft estimates can stay incomplete while you review media or prepare a site visit.'
            : 'Customer care can quote the customer only after this estimate includes a price, date range, hours per day, and a full daily work plan.';
    }
  }

  String _submitLabel(bool isUpdating) {
    switch (widget.mode) {
      case RequestEstimationDialogMode.siteReviewBooking:
        return isUpdating ? 'Update scheduled review' : 'Book scheduled review';
      case RequestEstimationDialogMode.finalEstimateAfterReview:
        return isUpdating
            ? 'Update estimate after review'
            : 'Save estimate after review';
      case RequestEstimationDialogMode.standard:
        if (_assessmentType == _assessmentTypeSiteReviewRequired) {
          return _isSiteReviewPending
              ? (isUpdating
                    ? 'Update scheduled review'
                    : 'Book scheduled review')
              : (isUpdating
                    ? 'Update estimate after review'
                    : 'Save estimate after review');
        }
        return _stage == _estimationStageDraft
            ? (isUpdating ? 'Update draft' : 'Save draft')
            : (isUpdating ? 'Update estimate' : 'Save estimate');
    }
  }

  List<String> _assessmentStatusOptionsFor(String assessmentType) {
    if (assessmentType == _assessmentTypeSiteReviewRequired) {
      return const <String>[
        _assessmentStatusSiteVisitRequired,
        _assessmentStatusSiteVisitScheduled,
        _assessmentStatusSiteVisitCompleted,
      ];
    }

    return const <String>[
      _assessmentStatusAwaitingReview,
      _assessmentStatusAwaitingCustomerMedia,
    ];
  }

  String _assessmentTypeLabel(String value) {
    switch (value) {
      case _assessmentTypeSiteReviewRequired:
        return 'Site review required';
      default:
        return 'Remote review';
    }
  }

  String _assessmentStatusLabel(String value) {
    switch (value) {
      case _assessmentStatusAwaitingCustomerMedia:
        return 'Awaiting customer media';
      case _assessmentStatusSiteVisitRequired:
        return 'Site visit required';
      case _assessmentStatusSiteVisitScheduled:
        return 'Site visit scheduled';
      case _assessmentStatusSiteVisitCompleted:
        return 'Site visit completed';
      default:
        return 'Awaiting review';
    }
  }

  int _normalizeHoursPerDay(double? value) {
    final resolved = value?.round();
    if (resolved == null || resolved < 1) {
      return 8;
    }
    if (resolved > 10) {
      return 10;
    }
    return resolved;
  }

  String _formatDate(DateTime value) {
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

  String _formatDayLabel(DateTime value) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${_formatDate(value)} (${weekdays[value.weekday - 1]})';
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

  List<_EstimatedWorkDayDraft> _hydrateDailySchedule(
    List<RequestEstimationPlannedDayModel> schedule,
  ) {
    return schedule
        .where((entry) => entry.date != null)
        .map(
          (entry) => _EstimatedWorkDayDraft(
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

  int get _estimatedDays {
    final start = _normalizeDate(_estimatedStartDate);
    final end = _normalizeDate(_estimatedEndDate);
    return end.difference(start).inDays + 1;
  }

  double get _estimatedHours {
    if (_estimatedDailySchedule.isEmpty) {
      return _hoursPerDay * _estimatedDays.toDouble();
    }

    return _estimatedDailySchedule.fold<double>(0, (total, entry) {
      return total +
          (entry.hours ??
              _calculateHoursBetween(entry.startTime, entry.endTime) ??
              0);
    });
  }

  void _rebuildDailySchedule({required bool resetTimes}) {
    final normalizedStart = _normalizeDate(_estimatedStartDate);
    final normalizedEnd = _normalizeDate(_estimatedEndDate);
    if (normalizedEnd.isBefore(normalizedStart)) {
      _estimatedDailySchedule = <_EstimatedWorkDayDraft>[];
      return;
    }

    final existingByDate = <String, _EstimatedWorkDayDraft>{
      for (final entry in _estimatedDailySchedule)
        _toIsoDate(entry.date): entry,
    };
    final rebuilt = <_EstimatedWorkDayDraft>[];

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

      final startTime = existing?.startTime ?? _defaultStartTime;
      rebuilt.add(
        _EstimatedWorkDayDraft(
          date: cursor,
          startTime: startTime,
          endTime: _addHoursToTime(startTime, _hoursPerDay),
          hours: _hoursPerDay.toDouble(),
        ),
      );
    }

    _estimatedDailySchedule = rebuilt;
  }

  Future<void> _pickStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _estimatedStartDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected == null) {
      return;
    }

    setState(() {
      _estimatedStartDate = selected;
      if (_estimatedEndDate.isBefore(selected)) {
        _estimatedEndDate = selected;
        _endDateController.text = _formatDate(_estimatedEndDate);
      }
      _startDateController.text = _formatDate(_estimatedStartDate);
      _rebuildDailySchedule(resetTimes: false);
    });
  }

  Future<void> _pickEndDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _estimatedEndDate,
      firstDate: _estimatedStartDate,
      lastDate: DateTime(2100, 12, 31),
    );
    if (selected == null) {
      return;
    }

    setState(() {
      _estimatedEndDate = selected;
      _endDateController.text = _formatDate(_estimatedEndDate);
      _rebuildDailySchedule(resetTimes: false);
    });
  }

  Future<void> _pickSiteReviewDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate:
          _siteReviewDate ?? widget.request.preferredDate ?? DateTime.now(),
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
          ? (_siteReviewStartTime ?? _defaultStartTime)
          : (_siteReviewEndTime ??
                _addHoursToTime(_siteReviewStartTime ?? _defaultStartTime, 1) ??
                const TimeOfDay(hour: 9, minute: 0)),
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

  Future<void> _pickDailyScheduleTime(
    int index, {
    required bool isStart,
  }) async {
    final current = _estimatedDailySchedule[index];
    final selected = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (current.startTime ?? _defaultStartTime)
          : (current.endTime ??
                _addHoursToTime(
                  current.startTime ?? _defaultStartTime,
                  current.hours ?? _hoursPerDay.toDouble(),
                ) ??
                _addHoursToTime(_defaultStartTime, _hoursPerDay) ??
                const TimeOfDay(hour: 16, minute: 0)),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      final hoursBasis = current.hours ?? _hoursPerDay.toDouble();
      final updatedEntry = isStart
          ? _EstimatedWorkDayDraft(
              date: current.date,
              startTime: selected,
              endTime: _addHoursToTime(selected, hoursBasis),
              hours: hoursBasis,
            )
          : _EstimatedWorkDayDraft(
              date: current.date,
              startTime: current.startTime,
              endTime: selected,
              hours: _calculateHoursBetween(current.startTime, selected),
            );

      _estimatedDailySchedule = <_EstimatedWorkDayDraft>[
        for (var i = 0; i < _estimatedDailySchedule.length; i += 1)
          i == index ? updatedEntry : _estimatedDailySchedule[i],
      ];
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _submit() {
    final effectiveAssessmentType =
        _isSiteReviewBookingMode || _isFinalEstimateMode
        ? _assessmentTypeSiteReviewRequired
        : _assessmentType;
    final effectiveAssessmentStatus = _isFinalEstimateMode
        ? _assessmentStatusSiteVisitCompleted
        : _isSiteReviewBookingMode
        ? _assessmentStatusSiteVisitScheduled
        : _assessmentStatus;
    final effectiveStage = _isFinalEstimateMode
        ? _estimationStageFinal
        : _isSiteReviewBookingMode
        ? _estimationStageDraft
        : _stage;
    final pendingSiteReview = _isSiteReviewPending;
    final costText = _costController.text.trim();
    final cost = costText.isEmpty ? null : double.tryParse(costText);
    final siteReviewCostText = _siteReviewCostController.text.trim();
    final siteReviewCost = siteReviewCostText.isEmpty
        ? null
        : double.tryParse(siteReviewCostText);

    if (pendingSiteReview) {
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
      if (siteReviewCost == null || siteReviewCost <= 0) {
        _showError('Enter the site review charge');
        return;
      }
    } else {
      if (_estimatedEndDate.isBefore(_estimatedStartDate)) {
        _showError('Estimated end date must be on or after the start date');
        return;
      }

      if (_estimatedDailySchedule.isEmpty) {
        _showError('Review the daily work plan');
        return;
      }

      if (_estimatedDailySchedule.length != _estimatedDays) {
        _showError('The daily work plan must cover every day in the range');
        return;
      }

      for (final entry in _estimatedDailySchedule) {
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

      if (_stage == _estimationStageFinal) {
        if (cost == null || cost <= 0) {
          _showError('Enter a valid estimated cost');
          return;
        }
      } else if (cost != null && cost <= 0) {
        _showError('Estimated cost must be greater than zero');
        return;
      }
    }

    Navigator.of(context).pop(
      RequestEstimationDraftInput(
        assessmentType: effectiveAssessmentType,
        assessmentStatus: effectiveAssessmentStatus,
        stage: pendingSiteReview ? _estimationStageDraft : effectiveStage,
        siteReviewDate: _siteReviewDate == null
            ? null
            : _toIsoDate(_siteReviewDate!),
        siteReviewStartTime: _formatStorageTime(_siteReviewStartTime),
        siteReviewEndTime: _formatStorageTime(_siteReviewEndTime),
        siteReviewCost: siteReviewCost,
        siteReviewNotes: _siteReviewNotesController.text.trim(),
        estimatedStartDate: pendingSiteReview
            ? null
            : _toIsoDate(_estimatedStartDate),
        estimatedEndDate: pendingSiteReview
            ? null
            : _toIsoDate(_estimatedEndDate),
        estimatedHoursPerDay: pendingSiteReview
            ? null
            : _hoursPerDay.toDouble(),
        estimatedHours: pendingSiteReview ? null : _estimatedHours,
        estimatedDays: pendingSiteReview ? null : _estimatedDays,
        estimatedDailySchedule: pendingSiteReview
            ? const <RequestEstimationPlannedDayInput>[]
            : _estimatedDailySchedule
                  .map(
                    (entry) => RequestEstimationPlannedDayInput(
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
        cost: pendingSiteReview ? null : cost,
        note: _noteController.text.trim(),
        inspectionNote: _inspectionNoteController.text.trim(),
      ),
    );
  }

  Widget _buildTimeField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(
          suffixIcon: Icon(Icons.schedule_rounded),
        ).copyWith(labelText: label),
        child: Text(value),
      ),
    );
  }

  Widget _buildReadOnlyWorkflowStatusChip() {
    final statusLabel = _assessmentStatusLabel(_assessmentStatus);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF2F7C6E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF2F7C6E).withValues(alpha: 0.24),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.verified_outlined,
              size: 16,
              color: Color(0xFF2F7C6E),
            ),
            const SizedBox(width: 8),
            Text(
              'Review status: $statusLabel',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFF2F7C6E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUpdating = widget.initialEstimation != null;
    final summaryHours = _estimatedHours;

    return AlertDialog(
      title: Text(_dialogTitle(isUpdating)),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _dialogSummary(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              if (_hasLockedWorkflowMode) ...<Widget>[
                _buildReadOnlyWorkflowStatusChip(),
                const SizedBox(height: 12),
              ],
              if (!_hasLockedWorkflowMode) ...<Widget>[
                DropdownButtonFormField<String>(
                  initialValue: _assessmentType,
                  decoration: const InputDecoration(
                    labelText: 'Assessment type',
                  ),
                  items:
                      const <String>[
                        _assessmentTypeRemoteReview,
                        _assessmentTypeSiteReviewRequired,
                      ].map((value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(_assessmentTypeLabel(value)),
                        );
                      }).toList(),
                  onChanged: (String? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _assessmentType = value;
                      final validStatuses = _assessmentStatusOptionsFor(value);
                      if (!validStatuses.contains(_assessmentStatus)) {
                        _assessmentStatus = validStatuses.first;
                      }
                      if (_isSiteReviewPending) {
                        _stage = _estimationStageDraft;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _assessmentStatus,
                  decoration: const InputDecoration(
                    labelText: 'Assessment status',
                  ),
                  items: _assessmentStatusOptionsFor(_assessmentType).map((
                    value,
                  ) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(_assessmentStatusLabel(value)),
                    );
                  }).toList(),
                  onChanged: (String? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _assessmentStatus = value;
                      if (_isSiteReviewPending) {
                        _stage = _estimationStageDraft;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _stage,
                  decoration: const InputDecoration(
                    labelText: 'Estimate stage',
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: _estimationStageDraft,
                      child: Text('Draft'),
                    ),
                    DropdownMenuItem<String>(
                      value: _estimationStageFinal,
                      child: Text('Final'),
                    ),
                  ],
                  onChanged: _isSiteReviewPending
                      ? null
                      : (String? value) {
                          if (value == null) {
                            return;
                          }
                          setState(() => _stage = value);
                        },
                ),
                const SizedBox(height: 12),
              ],
              if (_assessmentType == _assessmentTypeSiteReviewRequired &&
                  !_isFinalEstimateMode) ...<Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Site review booking',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
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
                  controller: _siteReviewCostController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Site review charge (EUR)',
                    prefixText: 'EUR ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _siteReviewNotesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Site review notes',
                    hintText:
                        'Optional booking or access note for the review visit',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_isSiteReviewPending)
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.4),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Final pricing stays locked until the site review is completed. Book the review first, then switch the assessment status to site visit completed to finish the actual estimate.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ),
                ),
              if (!_isSiteReviewPending) ...<Widget>[
                TextField(
                  controller: _startDateController,
                  readOnly: true,
                  onTap: _pickStartDate,
                  decoration: const InputDecoration(
                    labelText: 'Estimated start date',
                    suffixIcon: Icon(Icons.event_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _endDateController,
                  readOnly: true,
                  onTap: _pickEndDate,
                  decoration: const InputDecoration(
                    labelText: 'Estimated end date',
                    suffixIcon: Icon(Icons.event_available_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _hoursPerDay,
                  decoration: const InputDecoration(labelText: 'Hours per day'),
                  items: List<DropdownMenuItem<int>>.generate(
                    10,
                    (index) => DropdownMenuItem<int>(
                      value: index + 1,
                      child: Text('${index + 1} h'),
                    ),
                  ),
                  onChanged: (int? value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _hoursPerDay = value;
                      _rebuildDailySchedule(resetTimes: true);
                    });
                  },
                ),
                const SizedBox(height: 18),
                Text(
                  'Daily work plan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                ..._estimatedDailySchedule.asMap().entries.map((entry) {
                  final index = entry.key;
                  final day = entry.value;
                  final dayHours =
                      day.hours ??
                      _calculateHoursBetween(day.startTime, day.endTime);
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == _estimatedDailySchedule.length - 1
                          ? 0
                          : 12,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.35),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _formatDayLabel(day.date),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: _buildTimeField(
                                    label: 'Start time',
                                    value: _formatTime(day.startTime),
                                    onTap: () => _pickDailyScheduleTime(
                                      index,
                                      isStart: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildTimeField(
                                    label: 'End time',
                                    value: _formatTime(day.endTime),
                                    onTap: () => _pickDailyScheduleTime(
                                      index,
                                      isStart: false,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              dayHours == null
                                  ? 'Set the work hours for this day'
                                  : '${_formatNumber(dayHours)} hours planned',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color
                                        ?.withValues(alpha: 0.7),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                TextField(
                  controller: _costController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _stage == _estimationStageDraft
                        ? 'Estimated cost (EUR, optional for draft)'
                        : 'Estimated cost (EUR)',
                    prefixText: 'EUR ',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Estimate note',
                  hintText: 'Optional note for customer care review',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _inspectionNoteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Inspection note',
                  hintText:
                      'Optional note about media review or site inspection',
                ),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.4),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.28),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Estimate summary',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_isSiteReviewPending) ...<Widget>[
                        Text(
                          _siteReviewDate == null
                              ? 'Site review date pending'
                              : 'Review booked for ${_formatDate(_siteReviewDate!)}',
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _siteReviewCostController.text.trim().isEmpty
                              ? 'Review charge pending'
                              : 'EUR ${_siteReviewCostController.text.trim()} site review charge',
                        ),
                      ] else ...<Widget>[
                        Text(
                          '$_estimatedDays day${_estimatedDays == 1 ? '' : 's'} planned',
                        ),
                        const SizedBox(height: 2),
                        Text('${_formatNumber(summaryHours)} total hours'),
                      ],
                    ],
                  ),
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
        FilledButton(onPressed: _submit, child: Text(_submitLabel(isUpdating))),
      ],
    );
  }
}
