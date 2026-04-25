/// WHAT: Renders the staff workspace as a queue inbox plus active conversation area.
/// WHY: Staff should manage waiting customers and active requests from a chat-first layout instead of bulky stacked cards.
/// HOW: Show queue filters and compact workload controls on the left, then render the selected waiting or active thread on the right.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/models/service_request_model.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../shared/data/internal_chat_repository.dart';
import '../../../shared/presentation/app_language_toggle.dart';
import '../../../shared/presentation/presence_chip.dart';
import '../../../shared/presentation/request_estimation_dialog.dart';
import '../../../shared/presentation/request_message_composer.dart';
import '../../../shared/presentation/request_thread_section.dart';
import '../../../shared/presentation/request_workflow_progress_bar.dart';
import '../../../shared/presentation/status_chip.dart';
import '../../../shared/presentation/workspace_bottom_nav.dart';
import '../../../shared/presentation/workspace_profile_action_button.dart';
import '../../../shared/utils/external_url_opener.dart';
import '../../../shared/utils/request_attachment_flow_labels.dart';
import '../../../shared/utils/request_attachment_picker.dart';
import '../../../shared/utils/text_file_downloader.dart';
import '../../../theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../data/staff_repository.dart';
import 'staff_internal_chat_screen.dart';

final staffDashboardProvider = FutureProvider<StaffDashboardBundle>((
  Ref ref,
) async {
  debugPrint('staffDashboardProvider: fetching staff dashboard');
  return ref.watch(staffRepositoryProvider).fetchDashboard();
});

enum _StaffInboxFilter { waiting, active, quoted, confirmed, pending, closed }

enum _StaffWorkspaceTab { queue, active, pipeline, closed, chats }

class StaffDashboardScreen extends ConsumerStatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  ConsumerState<StaffDashboardScreen> createState() =>
      _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends ConsumerState<StaffDashboardScreen> {
  static const List<String> _actionableStatuses = <String>[
    'under_review',
    'quoted',
    'appointment_confirmed',
    'pending_start',
    'project_started',
    'work_done',
    'closed',
  ];

  final Map<String, String> _selectedStatuses = <String, String>{};
  final Map<String, TextEditingController> _messageControllers =
      <String, TextEditingController>{};
  final ScrollController _requestThreadScrollController = ScrollController();
  final Map<String, DateTime> _lastViewedActivityByRequestId =
      <String, DateTime>{};
  final Map<String, double> _conversationScrollOffsetsByRequestId =
      <String, double>{};
  // WHY: Mutation endpoints already return the updated request, so the active thread can update immediately without a broad dashboard refetch.
  final Map<String, ServiceRequestModel> _requestOverrides =
      <String, ServiceRequestModel>{};
  final Set<String> _attendingQueueIds = <String>{};
  final Set<String> _updatingAiControlIds = <String>{};
  final Set<String> _sendingMessageIds = <String>{};
  final Set<String> _uploadingAttachmentIds = <String>{};
  final Set<String> _refiningMessageIds = <String>{};
  final Set<String> _sendingInvoiceIds = <String>{};
  final Set<String> _completingWorkRequestIds = <String>{};
  final Set<String> _reviewingPaymentProofIds = <String>{};
  final Set<String> _savingStatusIds = <String>{};
  final Set<String> _clockingRequestIds = <String>{};
  String? _lastThreadScrollSignature;
  _StaffInboxFilter _selectedFilter = _StaffInboxFilter.waiting;
  _StaffWorkspaceTab _selectedWorkspaceTab = _StaffWorkspaceTab.queue;
  String? _selectedRequestId;
  bool _isUpdatingAvailability = false;

  AppLanguage get _language => ref.read(appLanguageProvider);

  @override
  void initState() {
    super.initState();
    ref.listenManual<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (
      _,
      next,
    ) {
      next.whenData((event) {
        if (!event.affectsRequests || !mounted) {
          return;
        }

        ref.invalidate(staffDashboardProvider);
      });
    });
  }

  String _t({required String en, required String de}) {
    return _language.pick(en: en, de: de);
  }

  String _serviceLabel(ServiceRequestModel request) {
    return request.serviceLabelForLanguage(_language);
  }

  bool get _isCustomerCareUser =>
      (ref.read(authControllerProvider).user?.staffType ?? '') ==
      'customer_care';

  bool get _isClockingStaffUser {
    final staffType = ref.read(authControllerProvider).user?.staffType ?? '';
    return staffType == 'technician' || staffType == 'contractor';
  }

  String get _currentStaffUserId =>
      ref.read(authControllerProvider).user?.id ?? '';

  ServiceRequestModel _applyRequestOverride(ServiceRequestModel request) {
    return _requestOverrides[request.id] ?? request;
  }

  List<ServiceRequestModel> _applyRequestOverrides(
    List<ServiceRequestModel> requests,
  ) {
    return requests.map(_applyRequestOverride).toList(growable: false);
  }

  void _storeRequestOverride(ServiceRequestModel request) {
    setState(() {
      _requestOverrides[request.id] = request;
    });
  }

  @override
  void dispose() {
    // WHY: Each active thread can own a composer controller, so all of those controllers need cleanup on screen exit.
    for (final controller in _messageControllers.values) {
      controller.dispose();
    }
    _requestThreadScrollController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(String requestId) {
    // WHY: Keep one controller per request id so draft replies survive rebuilds while staff switch threads.
    return _messageControllers.putIfAbsent(
      requestId,
      () => TextEditingController(),
    );
  }

  String _normalizeAiSuggestionForComparison(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _updateConversationScrollOffset(String requestId, double offset) {
    final clampedOffset = offset < 0 ? 0.0 : offset;
    final currentOffset =
        _conversationScrollOffsetsByRequestId[requestId] ?? 0.0;

    if ((currentOffset - clampedOffset).abs() < 4) {
      return;
    }

    setState(() {
      _conversationScrollOffsetsByRequestId[requestId] = clampedOffset;
    });
  }

  Future<void> _updateAvailability(String availability) async {
    setState(() => _isUpdatingAvailability = true);
    debugPrint(
      'StaffDashboardScreen._updateAvailability: setting availability to $availability',
    );

    try {
      await ref
          .read(staffRepositoryProvider)
          .updateAvailability(availability: availability);
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            availability == 'online'
                ? _t(
                    en: 'You are now online for the queue',
                    de: 'Sie sind jetzt online für die Warteschlange',
                  )
                : _t(
                    en: 'You are now offline for new queue pickups',
                    de: 'Sie sind jetzt offline für neue Übernahmen',
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
        setState(() => _isUpdatingAvailability = false);
      }
    }
  }

  bool _requestOccursToday(ServiceRequestModel request) {
    final now = DateTime.now().toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      (request.calendarStartDate ??
              request.estimatedStartDate ??
              request.preferredDate ??
              request.actualStartDate ??
              request.createdAt ??
              today)
          .year,
      (request.calendarStartDate ??
              request.estimatedStartDate ??
              request.preferredDate ??
              request.actualStartDate ??
              request.createdAt ??
              today)
          .month,
      (request.calendarStartDate ??
              request.estimatedStartDate ??
              request.preferredDate ??
              request.actualStartDate ??
              request.createdAt ??
              today)
          .day,
    );
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
    final end = DateTime(endSource.year, endSource.month, endSource.day);
    return !today.isBefore(start) && !today.isAfter(end);
  }

  bool _canCurrentStaffClockRequest(ServiceRequestModel request) {
    if (!_isClockingStaffUser || request.status == 'closed') {
      return false;
    }

    if (request.assignedStaff?.id != _currentStaffUserId) {
      return false;
    }

    return _requestOccursToday(request);
  }

  bool _canCurrentStaffCompleteRequestWork(ServiceRequestModel request) {
    if (!_canCurrentStaffClockRequest(request) || request.isSiteReviewPending) {
      return false;
    }

    if (request.status == 'work_done' || request.status == 'closed') {
      return false;
    }

    if (_activeCurrentStaffWorkLog(request) != null) {
      return false;
    }

    return request.projectStartedAt != null ||
        request.status == 'project_started' ||
        request.workLogs.any(
          (log) =>
              log.workType == requestWorkLogTypeMainJob &&
              log.startedAt != null,
        );
  }

  RequestWorkLogModel? _activeCurrentStaffWorkLog(ServiceRequestModel request) {
    final userId = _currentStaffUserId;
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

  String _clockingSummary(ServiceRequestModel request) {
    final activeLog = _activeCurrentStaffWorkLog(request);
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

  Future<ServiceRequestModel?> _clockRequestWork(
    ServiceRequestModel request,
    String action,
  ) async {
    setState(() => _clockingRequestIds.add(request.id));

    try {
      final updatedRequest = await ref
          .read(staffRepositoryProvider)
          .clockRequestWork(requestId: request.id, action: action);
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return updatedRequest;
      }

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

      return updatedRequest;
    } catch (error) {
      if (!mounted) {
        return null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() => _clockingRequestIds.remove(request.id));
      }
    }
  }

  Future<String?> _promptForWorkCompletionPassword() async {
    final passwordController = TextEditingController();
    var obscureText = true;
    String? errorText;

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: Text(_t(en: 'Complete work', de: 'Arbeit abschließen')),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _t(
                        en: 'Enter your staff password before marking this job completed.',
                        de: 'Geben Sie Ihr Mitarbeiterpasswort ein, bevor Sie diesen Job als erledigt markieren.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: obscureText,
                      autofocus: true,
                      onChanged: (_) {
                        if (errorText != null) {
                          setDialogState(() => errorText = null);
                        }
                      },
                      onSubmitted: (_) {
                        final trimmedPassword = passwordController.text.trim();
                        if (trimmedPassword.isEmpty) {
                          setDialogState(
                            () => errorText = _t(
                              en: 'Password is required.',
                              de: 'Passwort ist erforderlich.',
                            ),
                          );
                          return;
                        }
                        Navigator.of(dialogContext).pop(trimmedPassword);
                      },
                      decoration: InputDecoration(
                        labelText: _t(en: 'Password', de: 'Passwort'),
                        errorText: errorText,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setDialogState(() => obscureText = !obscureText);
                          },
                          icon: Icon(
                            obscureText
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(_t(en: 'Cancel', de: 'Abbrechen')),
                ),
                FilledButton(
                  onPressed: () {
                    final trimmedPassword = passwordController.text.trim();
                    if (trimmedPassword.isEmpty) {
                      setDialogState(
                        () => errorText = _t(
                          en: 'Password is required.',
                          de: 'Passwort ist erforderlich.',
                        ),
                      );
                      return;
                    }
                    Navigator.of(dialogContext).pop(trimmedPassword);
                  },
                  child: Text(
                    _t(en: 'Complete work', de: 'Arbeit abschließen'),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    passwordController.dispose();
    return password;
  }

  Future<ServiceRequestModel?> _completeRequestWork(
    ServiceRequestModel request,
  ) async {
    final password = await _promptForWorkCompletionPassword();
    if (password == null || password.isEmpty) {
      return null;
    }

    setState(() => _completingWorkRequestIds.add(request.id));

    try {
      final updatedRequest = await ref
          .read(staffRepositoryProvider)
          .updateRequestStatus(
            requestId: request.id,
            status: 'work_done',
            password: password,
          );
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return updatedRequest;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Work completed successfully.',
              de: 'Arbeit erfolgreich abgeschlossen.',
            ),
          ),
        ),
      );

      return updatedRequest;
    } catch (error) {
      if (!mounted) {
        return null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() => _completingWorkRequestIds.remove(request.id));
      }
    }
  }

  Future<void> _attendQueue(ServiceRequestModel request) async {
    setState(() => _attendingQueueIds.add(request.id));
    debugPrint(
      'StaffDashboardScreen._attendQueue: attending queue ${request.id}',
    );

    try {
      await ref
          .read(staffRepositoryProvider)
          .attendQueueRequest(requestId: request.id);
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'You are now attending ${request.contactFullName}',
              de: 'Sie betreuen jetzt ${request.contactFullName}',
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
        setState(() => _attendingQueueIds.remove(request.id));
      }
    }
  }

  Future<void> _sendMessage(ServiceRequestModel request) async {
    final controller = _controllerFor(request.id);
    final text = controller.text.trim();

    // WHY: Ignore accidental empty replies so the shared thread never receives blank staff bubbles.
    if (text.isEmpty) {
      return;
    }

    setState(() => _sendingMessageIds.add(request.id));
    debugPrint(
      'StaffDashboardScreen._sendMessage: sending reply for ${request.id}',
    );

    try {
      await ref
          .read(staffRepositoryProvider)
          .sendMessage(requestId: request.id, message: text);
      controller.clear();
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(en: 'Reply sent', de: 'Antwort gesendet')),
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
        setState(() => _sendingMessageIds.remove(request.id));
      }
    }
  }

  Future<void> _refineDraftWithAi(ServiceRequestModel request) async {
    final controller = _controllerFor(request.id);
    if (_refiningMessageIds.contains(request.id)) {
      return;
    }

    final currentDraft = controller.text;
    setState(() => _refiningMessageIds.add(request.id));

    try {
      final suggestion = await ref
          .read(staffRepositoryProvider)
          .refineReply(requestId: request.id, draft: currentDraft.trim());

      if (!mounted) {
        return;
      }

      final resolvedSuggestion = suggestion.trim();
      if (resolvedSuggestion.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                en: 'Naima AI could not prepare a better reply just now.',
                de: 'Naima KI konnte gerade keine bessere Antwort vorbereiten.',
              ),
            ),
          ),
        );
        return;
      }

      final normalizedCurrentDraft = _normalizeAiSuggestionForComparison(
        currentDraft,
      );
      final normalizedSuggestion = _normalizeAiSuggestionForComparison(
        resolvedSuggestion,
      );

      if (normalizedCurrentDraft == normalizedSuggestion) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                en: 'Naima AI reviewed the message and found no stronger rewrite.',
                de: 'Naima KI hat die Nachricht geprueft und keine bessere Umformulierung gefunden.',
              ),
            ),
          ),
        );
        return;
      }

      controller.value = TextEditingValue(
        text: resolvedSuggestion,
        selection: TextSelection.collapsed(offset: resolvedSuggestion.length),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Naima AI prepared a refined reply from the conversation.',
              de: 'Naima KI hat eine verfeinerte Antwort aus dem Verlauf vorbereitet.',
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
        setState(() => _refiningMessageIds.remove(request.id));
      }
    }
  }

  Future<void> _uploadRequestAttachment(ServiceRequestModel request) async {
    if (request.status == 'closed') {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    final pickedFile = await pickRequestAttachmentFile();
    if (pickedFile == null) {
      return;
    }

    final controller = _controllerFor(request.id);
    final caption = controller.text.trim();

    setState(() => _uploadingAttachmentIds.add(request.id));
    debugPrint(
      'StaffDashboardScreen._uploadRequestAttachment: uploading attachment for ${request.id}',
    );

    try {
      await ref
          .read(staffRepositoryProvider)
          .uploadRequestAttachment(
            requestId: request.id,
            bytes: pickedFile.bytes,
            fileName: pickedFile.name,
            mimeType: pickedFile.mimeType,
            caption: caption.isEmpty ? null : caption,
          );
      controller.clear();
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t(en: 'Attachment sent', de: 'Anhang gesendet')),
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
        setState(() => _uploadingAttachmentIds.remove(request.id));
      }
    }
  }

  Future<void> _updateAiControl(
    ServiceRequestModel request,
    bool enabled, {
    required String currentAvailability,
  }) async {
    if (request.assignedStaff == null || request.status == 'closed') {
      return;
    }

    setState(() => _updatingAiControlIds.add(request.id));
    debugPrint(
      'StaffDashboardScreen._updateAiControl: setting ai control for ${request.id} to $enabled',
    );

    try {
      await ref
          .read(staffRepositoryProvider)
          .updateRequestAiControl(requestId: request.id, enabled: enabled);
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      final isOnline = _isCurrentStaffOnline(currentAvailability);
      final message = enabled
          ? 'Naima is now covering this chat'
          : isOnline
          ? 'Direct staff chat resumed'
          : 'Naima stays active while you are offline';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
        setState(() => _updatingAiControlIds.remove(request.id));
      }
    }
  }

  Future<void> _sendCustomerUpdateRequest(ServiceRequestModel request) async {
    if (request.invoice != null) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Customer updates are locked after the quotation has been sent.',
              de: 'Kundenupdates sind gesperrt, nachdem das Angebot gesendet wurde.',
            ),
          ),
        ),
      );
      return;
    }

    const updatePrompt =
        'Please review your request details and use the update button below to revise the address, preferred date or time, access instructions, or work scope so I can keep your request accurate.';

    setState(() => _sendingMessageIds.add(request.id));

    try {
      await ref
          .read(staffRepositoryProvider)
          .sendMessage(
            requestId: request.id,
            message: updatePrompt,
            actionType: requestMessageActionCustomerUpdateRequest,
          );
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Customer update request sent to chat',
              de: 'Aktualisierungsanfrage an den Chat gesendet',
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
        setState(() => _sendingMessageIds.remove(request.id));
      }
    }
  }

  RequestMessageModel? _latestCustomerUpdateRequestMessage(
    ServiceRequestModel request,
  ) {
    for (final message in request.messages.reversed) {
      if (message.isCustomerUpdateRequest) {
        return message;
      }
    }

    return null;
  }

  RequestMessageModel? _latestCustomerUpdateRequestClearMessage(
    ServiceRequestModel request,
  ) {
    for (final message in request.messages.reversed) {
      if (message.isCustomerUpdateRequestCleared) {
        return message;
      }
    }

    return null;
  }

  bool _hasPendingCustomerUpdateRequest(ServiceRequestModel request) {
    final requestMessage = _latestCustomerUpdateRequestMessage(request);
    if (requestMessage == null || request.invoice != null) {
      return false;
    }

    final requestCreatedAt = requestMessage.createdAt;
    final clearCreatedAt = _latestCustomerUpdateRequestClearMessage(
      request,
    )?.createdAt;

    if (requestCreatedAt == null) {
      return true;
    }

    if (clearCreatedAt == null) {
      return true;
    }

    return requestCreatedAt.isAfter(clearCreatedAt);
  }

  Future<void> _clearCustomerUpdateRequest(ServiceRequestModel request) async {
    const clearPrompt =
        'The request details are confirmed. No further customer update is needed right now.';

    setState(() => _sendingMessageIds.add(request.id));

    try {
      await ref
          .read(staffRepositoryProvider)
          .sendMessage(
            requestId: request.id,
            message: clearPrompt,
            actionType: requestMessageActionCustomerUpdateRequestCleared,
          );
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Customer update request cleared',
              de: 'Aktualisierungsanfrage wurde entfernt',
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
        setState(() => _sendingMessageIds.remove(request.id));
      }
    }
  }

  void _showQuotationWorkflowNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            en: 'Quotations are sent from the request chat after the estimate and internal review are both ready.',
            de: 'Angebote werden aus dem Anfrage-Chat gesendet, sobald Schätzung und interne Prüfung bereit sind.',
          ),
        ),
      ),
    );
  }

  void _showCustomerCareEstimateNotice() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(
            en: 'Customer care cannot edit staff estimates. Wait for a technician or contractor update, then send from the request chat when the quotation is ready.',
            de: 'Der Kundenservice kann keine Mitarbeiterschätzungen bearbeiten. Warten Sie auf ein Update von Techniker oder Auftragnehmer und senden Sie dann aus dem Anfrage-Chat, sobald das Angebot bereit ist.',
          ),
        ),
      ),
    );
  }

  RequestEstimationModel? _currentUserEstimationFor(
    ServiceRequestModel request,
  ) {
    final currentUserId = ref.read(authControllerProvider).user?.id ?? '';
    return request.estimationForSubmitter(currentUserId);
  }

  Future<ServiceRequestModel?> _editEstimation(
    ServiceRequestModel request, {
    RequestEstimationDialogMode mode = RequestEstimationDialogMode.standard,
  }) async {
    if (_isCustomerCareUser) {
      _showCustomerCareEstimateNotice();
      return null;
    }

    if (request.estimationLocked) {
      _showQuotationWorkflowNotice();
      return null;
    }

    final existingEstimation = _currentUserEstimationFor(request);
    final draft = await showRequestEstimationDialog(
      context,
      request: request,
      initialEstimation: existingEstimation,
      mode: mode,
    );
    if (draft == null) {
      return null;
    }

    setState(() => _sendingInvoiceIds.add(request.id));

    try {
      final updatedRequest = await ref
          .read(staffRepositoryProvider)
          .submitEstimation(
            requestId: request.id,
            assessmentType: draft.assessmentType,
            assessmentStatus: draft.assessmentStatus,
            stage: draft.stage,
            siteReviewDate: draft.siteReviewDate,
            siteReviewStartTime: draft.siteReviewStartTime,
            siteReviewEndTime: draft.siteReviewEndTime,
            siteReviewCost: draft.siteReviewCost,
            siteReviewNotes: draft.siteReviewNotes,
            estimatedStartDate: draft.estimatedStartDate,
            estimatedEndDate: draft.estimatedEndDate,
            estimatedHoursPerDay: draft.estimatedHoursPerDay,
            estimatedHours: draft.estimatedHours,
            estimatedDays: draft.estimatedDays,
            estimatedDailySchedule: draft.estimatedDailySchedule
                .map((entry) => entry.toJson())
                .toList(),
            cost: draft.cost,
            note: draft.note,
            inspectionNote: draft.inspectionNote,
          );
      _storeRequestOverride(updatedRequest);

      if (!mounted) {
        return updatedRequest;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (mode) {
            RequestEstimationDialogMode.siteReviewBooking => _t(
              en: existingEstimation?.hasSiteReviewBooking == true
                  ? 'Site review booking updated in the calendar'
                  : 'Site review booked and added to the calendar',
              de: existingEstimation?.hasSiteReviewBooking == true
                  ? 'Besichtigung im Kalender aktualisiert'
                  : 'Besichtigung gebucht und im Kalender eingetragen',
            ),
            RequestEstimationDialogMode.finalEstimateAfterReview => _t(
              en: existingEstimation?.stage == 'final'
                  ? 'Final estimate updated for admin review'
                  : 'Final estimate submitted for admin review',
              de: existingEstimation?.stage == 'final'
                  ? 'Endgueltige Schaetzung fuer die Admin-Pruefung aktualisiert'
                  : 'Endgueltige Schaetzung fuer die Admin-Pruefung gespeichert',
            ),
            RequestEstimationDialogMode.standard => _t(
              en: draft.stage == 'draft'
                  ? (existingEstimation == null
                        ? 'Draft estimate saved'
                        : 'Draft estimate updated')
                  : (existingEstimation == null
                        ? 'Estimate saved for internal review'
                        : 'Estimate updated for internal review'),
              de: draft.stage == 'draft'
                  ? (existingEstimation == null
                        ? 'Schätzungsentwurf gespeichert'
                        : 'Schätzungsentwurf aktualisiert')
                  : (existingEstimation == null
                        ? 'Schätzung für die interne Prüfung gespeichert'
                        : 'Schätzung für die interne Prüfung aktualisiert'),
            ),
          }),
        ),
      );
      return updatedRequest;
    } catch (error) {
      if (!mounted) {
        return null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() => _sendingInvoiceIds.remove(request.id));
      }
    }
  }

  Future<ServiceRequestModel?> _bookSiteReview(ServiceRequestModel request) {
    return _editEstimation(
      request,
      mode: RequestEstimationDialogMode.siteReviewBooking,
    );
  }

  Future<ServiceRequestModel?> _runFinalEstimate(ServiceRequestModel request) {
    return _editEstimation(
      request,
      mode: RequestEstimationDialogMode.finalEstimateAfterReview,
    );
  }

  Future<void> _sendQuotationToCustomer(ServiceRequestModel request) async {
    if (!_isCustomerCareUser) {
      _showQuotationWorkflowNotice();
      return;
    }

    setState(() => _sendingInvoiceIds.add(request.id));

    try {
      await ref
          .read(staffRepositoryProvider)
          .sendQuotation(requestId: request.id);
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: request.quoteReview?.isSiteReview == true
                  ? 'Site review booking sent to customer'
                  : 'Quotation sent to customer',
              de: request.quoteReview?.isSiteReview == true
                  ? 'Besichtigungstermin an den Kunden gesendet'
                  : 'Angebot an den Kunden gesendet',
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
        setState(() => _sendingInvoiceIds.remove(request.id));
      }
    }
  }

  Future<void> _unlockPaymentProofUpload(ServiceRequestModel request) async {
    if (!_isCustomerCareUser) {
      _showQuotationWorkflowNotice();
      return;
    }

    setState(() => _reviewingPaymentProofIds.add(request.id));

    try {
      await ref
          .read(staffRepositoryProvider)
          .unlockPaymentProofUpload(requestId: request.id);
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Payment proof upload reopened',
              de: 'Upload fuer Zahlungsnachweis wieder freigegeben',
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
        setState(() => _reviewingPaymentProofIds.remove(request.id));
      }
    }
  }

  Future<void> _reviewPaymentProof(
    ServiceRequestModel request, {
    required String decision,
  }) async {
    String? reviewNote;
    if (decision == 'rejected') {
      final noteController = TextEditingController();
      reviewNote = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Reject payment proof'),
            content: TextField(
              controller: noteController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Tell the customer what needs to be corrected',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(noteController.text.trim()),
                child: const Text('Reject proof'),
              ),
            ],
          );
        },
      );
      noteController.dispose();
      if (reviewNote == null) {
        return;
      }
    }

    setState(() => _reviewingPaymentProofIds.add(request.id));

    try {
      await ref
          .read(staffRepositoryProvider)
          .reviewPaymentProof(
            requestId: request.id,
            decision: decision,
            reviewNote: reviewNote,
          );
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            decision == 'approved'
                ? _t(
                    en: 'Payment proof approved',
                    de: 'Zahlungsnachweis bestätigt',
                  )
                : _t(
                    en: 'Payment proof rejected',
                    de: 'Zahlungsnachweis abgelehnt',
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
        setState(() => _reviewingPaymentProofIds.remove(request.id));
      }
    }
  }

  Future<void> _openPaymentProof(ServiceRequestModel request) async {
    final fileUrl = request.invoice?.proof?.fileUrl;
    if (fileUrl == null || fileUrl.isEmpty) {
      return;
    }

    final opened = await openExternalUrl(fileUrl);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Opening proof is not supported here',
              de: 'Der Nachweis kann hier nicht geöffnet werden',
            ),
          ),
        ),
      );
    }
  }

  bool _isLatestProofUploadMessage(
    ServiceRequestModel request,
    RequestMessageModel message,
  ) {
    if (!message.isCustomerUploadPaymentProof) {
      return false;
    }

    final latestProofUrl = request.invoice?.proof?.relativeUrl ?? '';
    final messageProofUrl = message.attachment?.relativeUrl ?? '';
    if (latestProofUrl.isEmpty || messageProofUrl.isEmpty) {
      return false;
    }

    return latestProofUrl == messageProofUrl;
  }

  String _formatWorkflowDate(String? isoDate) {
    final parsed = DateTime.tryParse(isoDate ?? '');
    if (parsed == null) {
      return _t(en: 'Not set', de: 'Nicht gesetzt');
    }

    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final year = parsed.year.toString();
    return '$day/$month/$year';
  }

  String _formatWorkflowCurrency(dynamic amount, [String currency = 'EUR']) {
    final numericAmount = amount is num ? amount.toDouble() : 0;
    return '$currency ${numericAmount.toStringAsFixed(2)}';
  }

  Widget _buildQuoteWorkflowCard(
    ServiceRequestModel request,
    RequestMessageModel message,
  ) {
    final payload = message.actionPayload ?? const <String, dynamic>{};
    final title = (payload['title'] as String?) ?? message.text;
    final summary = (payload['summary'] as String?) ?? '';
    final sourceName = (payload['sourceEstimateOwnerName'] as String?) ?? '';
    final sourceRole =
        (payload['sourceEstimateOwnerStaffTypeLabel'] as String?) ?? '';
    final totalAmount = payload['totalAmount'];
    final currency = (payload['currency'] as String?) ?? 'EUR';
    final reviewKind =
        (payload['reviewKind'] as String?) ??
        (message.isSiteReviewReadyForCustomerCare ||
                message.isSiteReviewReadyForInternalReview ||
                message.isSiteReviewSent
            ? requestReviewKindSiteReview
            : requestReviewKindQuotation);
    final plannedStartDate = payload['plannedStartDate'] as String?;
    final plannedExpectedEndDate = payload['plannedExpectedEndDate'] as String?;
    final siteReviewDate = payload['siteReviewDate'] as String?;
    final canSendFromThisCard =
        (message.isQuotationReadyForCustomerCare ||
            message.isSiteReviewReadyForCustomerCare) &&
        _isCustomerCareUser &&
        request.canCustomerCareSendQuotation;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.cobalt.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.assignment_turned_in_rounded,
                    color: AppTheme.cobalt,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (summary.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                summary,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (totalAmount is num)
                  _WorkflowMetaPill(
                    label: _formatWorkflowCurrency(totalAmount, currency),
                  ),
                if (reviewKind == requestReviewKindSiteReview &&
                    siteReviewDate != null)
                  _WorkflowMetaPill(
                    label:
                        '${_t(en: 'Review', de: 'Besichtigung')}: ${_formatWorkflowDate(siteReviewDate)}',
                  ),
                if (plannedStartDate != null)
                  _WorkflowMetaPill(
                    label:
                        '${_t(en: 'Start', de: 'Start')}: ${_formatWorkflowDate(plannedStartDate)}',
                  ),
                if (plannedExpectedEndDate != null)
                  _WorkflowMetaPill(
                    label:
                        '${_t(en: 'End', de: 'Ende')}: ${_formatWorkflowDate(plannedExpectedEndDate)}',
                  ),
                if (sourceName.isNotEmpty)
                  _WorkflowMetaPill(
                    label: sourceRole.isEmpty
                        ? sourceName
                        : '$sourceName · $sourceRole',
                  ),
              ],
            ),
            if (message.isQuotationReadyForCustomerCare ||
                message.isSiteReviewReadyForCustomerCare) ...<Widget>[
              const SizedBox(height: 12),
              if (canSendFromThisCard)
                FilledButton.tonalIcon(
                  onPressed: _sendingInvoiceIds.contains(request.id)
                      ? null
                      : () => _sendQuotationToCustomer(request),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.cobalt.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _sendingInvoiceIds.contains(request.id)
                        ? reviewKind == requestReviewKindSiteReview
                              ? _t(
                                  en: 'Sending site review...',
                                  de: 'Besichtigung wird gesendet...',
                                )
                              : _t(
                                  en: 'Sending quotation...',
                                  de: 'Angebot wird gesendet...',
                                )
                        : reviewKind == requestReviewKindSiteReview
                        ? _t(
                            en: 'Send site review to customer',
                            de: 'Besichtigung an Kunden senden',
                          )
                        : _t(
                            en: 'Send quotation to customer',
                            de: 'Angebot an Kunden senden',
                          ),
                  ),
                )
              else
                Text(
                  _isCustomerCareUser
                      ? _t(
                          en: 'Waiting for the latest internal review before send.',
                          de: 'Warten auf die aktuelle interne Prüfung vor dem Senden.',
                        )
                      : _t(
                          en: 'Customer care can send this quotation from the chat once ready.',
                          de: 'Der Kundenservice kann dieses Angebot senden, sobald es im Chat bereit ist.',
                        ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _buildStaffThreadMessageAction(
    ServiceRequestModel request,
    RequestMessageModel message,
  ) {
    if (message.isEstimateUpdated ||
        message.isSiteReviewReadyForInternalReview ||
        message.isQuoteReadyForInternalReview ||
        message.isInternalReviewUpdated ||
        message.isSiteReviewReadyForCustomerCare ||
        message.isQuotationReadyForCustomerCare ||
        message.isQuotationInvalidated ||
        message.isSiteReviewSent ||
        message.isQuotationSent) {
      return _buildQuoteWorkflowCard(request, message);
    }

    final invoice = request.invoice;
    if (invoice == null || !_isLatestProofUploadMessage(request, message)) {
      return null;
    }

    final invoiceStatus = invoice.status;
    final statusConfig = switch (invoiceStatus) {
      paymentRequestStatusApproved => (
        label: _t(en: 'Payment approved', de: 'Zahlung bestätigt'),
        background: const Color(0xFF1D4930),
        foreground: const Color(0xFFDDF7E4),
      ),
      paymentRequestStatusRejected => (
        label: _t(en: 'Payment rejected', de: 'Zahlung abgelehnt'),
        background: const Color(0xFF5A2A21),
        foreground: const Color(0xFFFFE0DA),
      ),
      _ => (
        label: _t(en: 'Pending review', de: 'Prüfung ausstehend'),
        background: const Color(0xFF193446),
        foreground: const Color(0xFFDFF3FF),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: statusConfig.background,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Text(
                  statusConfig.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: statusConfig.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (invoiceStatus == paymentRequestStatusProofSubmitted)
              FilledButton.tonalIcon(
                onPressed: _reviewingPaymentProofIds.contains(request.id)
                    ? null
                    : () => _reviewPaymentProof(request, decision: 'approved'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.pine.withValues(alpha: 0.18),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.verified_rounded, size: 18),
                label: Text(
                  _reviewingPaymentProofIds.contains(request.id)
                      ? _t(en: 'Saving...', de: 'Speichert...')
                      : _t(en: 'Approve payment', de: 'Zahlung bestätigen'),
                ),
              ),
            if (invoiceStatus == paymentRequestStatusProofSubmitted)
              OutlinedButton.icon(
                onPressed: _reviewingPaymentProofIds.contains(request.id)
                    ? null
                    : () => _reviewPaymentProof(request, decision: 'rejected'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.04),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(_t(en: 'Reject proof', de: 'Nachweis ablehnen')),
              ),
            if (_isCustomerCareUser &&
                invoice.requiresCustomerProof &&
                invoice.isProofUploadExpired &&
                !invoice.isProofUploadUnlocked &&
                invoice.proof == null &&
                !invoice.isProofSubmitted &&
                !invoice.isApproved)
              OutlinedButton.icon(
                onPressed: _reviewingPaymentProofIds.contains(request.id)
                    ? null
                    : () => _unlockPaymentProofUpload(request),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: 0.04),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                ),
                icon: const Icon(Icons.lock_open_rounded, size: 18),
                label: Text(
                  _t(
                    en: 'Unlock proof upload',
                    de: 'Nachweis-Upload entsperren',
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _openReceipt(ServiceRequestModel request) async {
    final receiptUrl = request.invoice?.receiptUrl;
    if (receiptUrl == null || receiptUrl.isEmpty) {
      return;
    }

    final opened = await openExternalUrl(receiptUrl);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Opening receipt is not supported here',
              de: 'Der Beleg kann hier nicht geöffnet werden',
            ),
          ),
        ),
      );
    }
  }

  String _requestAddress(ServiceRequestModel request) {
    final parts = <String>[
      request.addressLine1,
      request.city,
      request.postalCode,
    ].where((part) => part.trim().isNotEmpty).toList();

    return parts.isEmpty ? 'Not provided' : parts.join(', ');
  }

  String _formatRequestDate(DateTime? value) {
    if (value == null) {
      return 'Not provided';
    }

    final localValue = value.toLocal();
    final day = localValue.day.toString().padLeft(2, '0');
    final month = localValue.month.toString().padLeft(2, '0');
    final year = localValue.year.toString();
    return '$day/$month/$year';
  }

  String _formatRequestDateTime(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }

    final localValue = value.toLocal();
    final day = localValue.day.toString().padLeft(2, '0');
    final month = localValue.month.toString().padLeft(2, '0');
    final year = localValue.year.toString();
    final hour = localValue.hour.toString().padLeft(2, '0');
    final minute = localValue.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  bool _isSiteReviewWorkLog(
    ServiceRequestModel request,
    RequestWorkLogModel workLog,
  ) {
    if (workLog.workType == requestWorkLogTypeSiteReview) {
      return true;
    }

    if (workLog.workType == requestWorkLogTypeMainJob) {
      return false;
    }

    // WHY: Older saved work logs do not have workType yet, so infer site-review
    // logs from the pre-quotation timeline instead of mixing them into main-job
    // clock rows.
    if (!request.isSiteReviewRequired) {
      return false;
    }

    final timestamp =
        workLog.startedAt ?? workLog.createdAt ?? workLog.stoppedAt;
    final reviewBoundary =
        request.quoteReadyAt ??
        request.internalReviewUpdatedAt ??
        request.latestEstimateUpdatedAt;
    if (timestamp == null || reviewBoundary == null) {
      return true;
    }

    return !timestamp.isAfter(reviewBoundary);
  }

  RequestWorkLogModel? _firstWorkLog(
    ServiceRequestModel request, {
    required bool siteReviewOnly,
  }) {
    final sortedLogs =
        request.workLogs
            .where(
              (log) =>
                  log.startedAt != null &&
                  _isSiteReviewWorkLog(request, log) == siteReviewOnly,
            )
            .toList()
          ..sort((left, right) {
            final leftTime = left.startedAt?.millisecondsSinceEpoch ?? 0;
            final rightTime = right.startedAt?.millisecondsSinceEpoch ?? 0;
            return leftTime.compareTo(rightTime);
          });

    return sortedLogs.isEmpty ? null : sortedLogs.first;
  }

  RequestWorkLogModel? _latestStoppedWorkLog(
    ServiceRequestModel request, {
    required bool siteReviewOnly,
  }) {
    final sortedLogs =
        request.workLogs
            .where(
              (log) =>
                  log.stoppedAt != null &&
                  _isSiteReviewWorkLog(request, log) == siteReviewOnly,
            )
            .toList()
          ..sort((left, right) {
            final leftTime = left.stoppedAt?.millisecondsSinceEpoch ?? 0;
            final rightTime = right.stoppedAt?.millisecondsSinceEpoch ?? 0;
            return rightTime.compareTo(leftTime);
          });

    return sortedLogs.isEmpty ? null : sortedLogs.first;
  }

  String _formatRequestWorkLogLabel(
    RequestWorkLogModel? workLog,
    DateTime? timestamp,
  ) {
    if (timestamp == null) {
      return _t(en: 'Not available', de: 'Nicht verfügbar');
    }

    final actorName = workLog?.actor?.fullName.trim() ?? '';
    if (actorName.isEmpty) {
      return _formatRequestDateTime(timestamp);
    }

    return '${_formatRequestDateTime(timestamp)} · $actorName';
  }

  String _formatEstimatedScheduleBoundary(
    ServiceRequestModel request, {
    required bool isStart,
  }) {
    final estimation = request.selectedEstimation;
    final scheduleEntries =
        estimation?.estimatedDailySchedule ??
        const <RequestEstimationPlannedDayModel>[];
    RequestEstimationPlannedDayModel? scheduleEntry;

    if (scheduleEntries.isNotEmpty) {
      final sortedEntries = scheduleEntries.toList()
        ..sort((left, right) {
          final leftTime = left.date?.millisecondsSinceEpoch ?? 0;
          final rightTime = right.date?.millisecondsSinceEpoch ?? 0;
          return leftTime.compareTo(rightTime);
        });
      scheduleEntry = isStart ? sortedEntries.first : sortedEntries.last;
    }

    final fallbackDate = isStart
        ? request.estimatedStartDate
        : request.estimatedEndDate;
    final scheduleDate = scheduleEntry?.date ?? fallbackDate;
    if (scheduleDate == null) {
      return _t(en: 'Not available', de: 'Nicht verfügbar');
    }

    final scheduleTime = isStart
        ? scheduleEntry?.startTime.trim() ?? ''
        : scheduleEntry?.endTime.trim() ?? '';
    final dateLabel = _formatRequestDate(scheduleDate);
    return scheduleTime.isEmpty ? dateLabel : '$dateLabel $scheduleTime';
  }

  String _formatScheduledSiteReviewDate(ServiceRequestModel request) {
    final estimation = _scheduledSiteReviewEstimation(request);
    if (estimation?.siteReviewDate == null) {
      return _t(en: 'Not available', de: 'Nicht verfügbar');
    }

    return _formatRequestDate(estimation!.siteReviewDate);
  }

  String _formatScheduledSiteReviewTime(ServiceRequestModel request) {
    final estimation = _scheduledSiteReviewEstimation(request);
    final startTime = estimation?.siteReviewStartTime.trim() ?? '';
    final endTime = estimation?.siteReviewEndTime.trim() ?? '';
    if (startTime.isEmpty && endTime.isEmpty) {
      return _t(en: 'Not available', de: 'Nicht verfügbar');
    }
    if (startTime.isEmpty) {
      return endTime;
    }
    if (endTime.isEmpty) {
      return startTime;
    }

    return '$startTime - $endTime';
  }

  String _slugify(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );

    return normalized
        .replaceAll(RegExp(r'^-+'), '')
        .replaceAll(RegExp(r'-+$'), '');
  }

  String _requestBriefFileName(ServiceRequestModel request) {
    final service = _slugify(request.serviceLabel);
    final customer = _slugify(request.contactFullName);
    final suffix = request.id.length > 8
        ? request.id.substring(0, 8)
        : request.id;

    return 'request-${service.isEmpty ? 'job' : service}-${customer.isEmpty ? 'customer' : customer}-$suffix.txt';
  }

  String _buildRequestBrief(ServiceRequestModel request) {
    final buffer = StringBuffer()
      ..writeln('Adams Service Ops - Customer Request Brief')
      ..writeln('')
      ..writeln('Request ID: ${request.id}')
      ..writeln('Status: ${request.status.replaceAll('_', ' ')}')
      ..writeln('Service: ${request.serviceLabel}')
      ..writeln(
        'Customer: ${request.contactFullName.isEmpty ? 'Not provided' : request.contactFullName}',
      )
      ..writeln(
        'Customer email: ${request.contactEmail.isEmpty ? 'Not provided' : request.contactEmail}',
      )
      ..writeln(
        'Customer phone: ${request.contactPhone.isEmpty ? 'Not provided' : request.contactPhone}',
      )
      ..writeln('Address: ${_requestAddress(request)}')
      ..writeln('Preferred date: ${_formatRequestDate(request.preferredDate)}')
      ..writeln(
        'Preferred time window: ${request.preferredTimeWindow.isEmpty ? 'Not provided' : request.preferredTimeWindow}',
      )
      ..writeln('Created: ${_formatRequestDateTime(request.createdAt)}')
      ..writeln(
        'Queue entered: ${_formatRequestDateTime(request.queueEnteredAt)}',
      )
      ..writeln('Attended: ${_formatRequestDateTime(request.attendedAt)}')
      ..writeln('Closed: ${_formatRequestDateTime(request.closedAt)}')
      ..writeln('Message count: ${request.messageCount}')
      ..writeln('')
      ..writeln('Customer request')
      ..writeln(
        request.message.trim().isEmpty
            ? 'No request note provided.'
            : request.message.trim(),
      );

    if (request.messages.isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln('Conversation log')
        ..writeln('');

      for (final message in request.messages) {
        final sender = message.senderName.isNotEmpty
            ? message.senderName
            : message.isCustomer
            ? 'Customer'
            : message.isStaff
            ? 'Staff'
            : message.isAi
            ? 'AI'
            : 'System';
        buffer.writeln(
          '[${_formatRequestDateTime(message.createdAt)}] $sender: ${message.text}${message.attachment == null ? '' : ' [attachment: ${message.attachment!.originalName}]'}',
        );
      }
    }

    return buffer.toString();
  }

  Future<void> _downloadRequestBrief(ServiceRequestModel request) async {
    final content = _buildRequestBrief(request);
    final didDownload = await downloadTextFile(
      fileName: _requestBriefFileName(request),
      content: content,
    );

    if (!mounted) {
      return;
    }

    if (didDownload) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request brief downloaded')));
      return;
    }

    await Clipboard.setData(ClipboardData(text: content));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Download is not available here. Request brief copied.'),
      ),
    );
  }

  Future<ServiceRequestModel?> _updateStatus({
    required ServiceRequestModel request,
    required String status,
    String? password,
  }) async {
    setState(() => _savingStatusIds.add(request.id));
    debugPrint(
      'StaffDashboardScreen._updateStatus: updating request ${request.id} to $status',
    );

    try {
      final updatedRequest = await ref
          .read(staffRepositoryProvider)
          .updateRequestStatus(
            requestId: request.id,
            status: status,
            password: password,
          );
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return updatedRequest;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'work_done'
                ? _t(
                    en: 'Work completed successfully.',
                    de: 'Arbeit erfolgreich abgeschlossen.',
                  )
                : _t(
                    en: 'Request status updated',
                    de: 'Anfragestatus aktualisiert',
                  ),
          ),
        ),
      );
      return updatedRequest;
    } catch (error) {
      if (!mounted) {
        return null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() => _savingStatusIds.remove(request.id));
      }
    }
  }

  List<ServiceRequestModel> _requestsForFilter(
    StaffDashboardBundle bundle,
    _StaffInboxFilter filter,
  ) {
    final requests = switch (filter) {
      _StaffInboxFilter.waiting => bundle.queueRequests,
      _StaffInboxFilter.active =>
        bundle.assignedRequests
            .where(
              (request) =>
                  request.status == 'assigned' ||
                  request.status == 'under_review' ||
                  request.status == 'project_started' ||
                  request.status == 'work_done',
            )
            .toList(),
      _StaffInboxFilter.quoted =>
        bundle.assignedRequests
            .where((request) => request.status == 'quoted')
            .toList(),
      _StaffInboxFilter.confirmed =>
        bundle.assignedRequests
            .where((request) => request.status == 'appointment_confirmed')
            .toList(),
      _StaffInboxFilter.pending =>
        bundle.assignedRequests
            .where((request) => request.status == 'pending_start')
            .toList(),
      _StaffInboxFilter.closed =>
        bundle.assignedRequests
            .where((request) => request.status == 'closed')
            .toList(),
    };

    return _applyRequestOverrides(<ServiceRequestModel>[...requests])
      ..sort(compareServiceRequestsByLatestActivity);
  }

  ServiceRequestModel? _resolveSelectedRequest(
    List<ServiceRequestModel> requests, {
    required bool preferFirst,
  }) {
    if (requests.isEmpty) {
      return null;
    }

    for (final request in requests) {
      if (request.id == _selectedRequestId) {
        return request;
      }
    }

    return preferFirst ? requests.first : null;
  }

  String _messagePreview(ServiceRequestModel request) {
    final latestMessage = request.latestMessage;
    if (latestMessage == null) {
      return request.message;
    }

    final senderLabel = latestMessage.senderName.isNotEmpty
        ? latestMessage.senderName
        : latestMessage.isCustomer
        ? 'Customer'
        : latestMessage.isAi
        ? 'AI'
        : latestMessage.isSystem
        ? 'System'
        : 'Staff';

    final attachmentName = latestMessage.attachment == null
        ? null
        : requestAttachmentDisplayNameForMessage(
            latestMessage,
            language: ref.read(appLanguageProvider),
          );
    if (attachmentName != null && attachmentName.isNotEmpty) {
      return '$senderLabel sent $attachmentName';
    }

    return '$senderLabel: ${latestMessage.text}';
  }

  bool _hasUnreadIncomingAlert(ServiceRequestModel request) {
    final latestMessage = request.latestMessage;
    final latestActivity = request.latestActivityAt;

    if (latestMessage == null ||
        latestActivity == null ||
        latestMessage.isStaff) {
      return false;
    }

    final lastViewed = _lastViewedActivityByRequestId[request.id];
    return lastViewed == null || latestActivity.isAfter(lastViewed);
  }

  void _markRequestViewed(ServiceRequestModel request) {
    final latestActivity = request.latestActivityAt;
    if (latestActivity == null) {
      return;
    }

    _lastViewedActivityByRequestId[request.id] = latestActivity;
  }

  void _scheduleMarkRequestViewed(ServiceRequestModel? request) {
    if (request == null || !_hasUnreadIncomingAlert(request)) {
      return;
    }

    final latestActivity = request.latestActivityAt;
    if (latestActivity == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final lastViewed = _lastViewedActivityByRequestId[request.id];
      if (lastViewed != null && !latestActivity.isAfter(lastViewed)) {
        return;
      }

      setState(
        () => _lastViewedActivityByRequestId[request.id] = latestActivity,
      );
    });
  }

  void _openRequest(ServiceRequestModel request) {
    _lastThreadScrollSignature = null;
    setState(() {
      _selectedWorkspaceTab = _workspaceTabForFilterValue(_selectedFilter);
      _selectedRequestId = request.id;
      _markRequestViewed(request);
    });
  }

  void _scheduleThreadScrollToLatest(ServiceRequestModel? request) {
    if (request == null) {
      _lastThreadScrollSignature = null;
      return;
    }

    final signature =
        '${request.id}:${request.latestActivityAt?.millisecondsSinceEpoch ?? 0}:${request.messageCount}';
    if (_lastThreadScrollSignature == signature) {
      return;
    }

    _lastThreadScrollSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_requestThreadScrollController.hasClients) {
        return;
      }

      _requestThreadScrollController.jumpTo(
        _requestThreadScrollController.position.maxScrollExtent,
      );
    });
  }

  String _latestAlertLabel(ServiceRequestModel request) {
    if (!_hasUnreadIncomingAlert(request)) {
      return '';
    }

    final latestMessage = request.latestMessage;
    if (latestMessage == null) {
      return '';
    }

    if (latestMessage.isCustomer) {
      return 'Customer replied';
    }

    if (latestMessage.isAi) {
      return 'AI update';
    }

    return 'System alert';
  }

  String _formatInboxTimestamp(DateTime? value) {
    if (value == null) {
      return '';
    }

    final localValue = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(
      localValue.year,
      localValue.month,
      localValue.day,
    );

    if (messageDay == today) {
      final hour = localValue.hour.toString().padLeft(2, '0');
      final minute = localValue.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    if (messageDay == today.subtract(const Duration(days: 1))) {
      return _t(en: 'Yesterday', de: 'Gestern');
    }

    final day = localValue.day.toString().padLeft(2, '0');
    final month = localValue.month.toString().padLeft(2, '0');
    return '$day/$month';
  }

  bool _isCurrentStaffOnline(String currentAvailability) =>
      currentAvailability == 'online';

  bool _isAiCoverActive(
    ServiceRequestModel request,
    String currentAvailability,
  ) {
    return request.assignedStaff != null &&
        (request.aiControlEnabled ||
            !_isCurrentStaffOnline(currentAvailability));
  }

  String _filterLabel(_StaffInboxFilter filter) {
    return switch (filter) {
      _StaffInboxFilter.waiting => _t(en: 'Waiting', de: 'Wartend'),
      _StaffInboxFilter.active => _t(en: 'Active', de: 'Aktiv'),
      _StaffInboxFilter.quoted => _t(en: 'Quoted', de: 'Angebot'),
      _StaffInboxFilter.confirmed => _t(en: 'Confirmed', de: 'Bestaetigt'),
      _StaffInboxFilter.pending => _t(en: 'Pending', de: 'Ausstehend'),
      _StaffInboxFilter.closed => _t(en: 'Closed', de: 'Geschlossen'),
    };
  }

  int _filterCount(StaffDashboardBundle bundle, _StaffInboxFilter filter) {
    // WHY: Each chip must show its own real backend-backed count, not the count of whichever filter is currently selected.
    return _requestsForFilter(bundle, filter).length;
  }

  _StaffWorkspaceTab _workspaceTabForFilterValue(_StaffInboxFilter filter) {
    return switch (filter) {
      _StaffInboxFilter.waiting => _StaffWorkspaceTab.queue,
      _StaffInboxFilter.active => _StaffWorkspaceTab.active,
      _StaffInboxFilter.quoted ||
      _StaffInboxFilter.confirmed ||
      _StaffInboxFilter.pending => _StaffWorkspaceTab.pipeline,
      _StaffInboxFilter.closed => _StaffWorkspaceTab.closed,
    };
  }

  void _selectWorkspaceTab(_StaffWorkspaceTab tab) {
    // WHY: Bottom navigation should jump to a sensible staff queue slice while still leaving fine-grained filter chips available inside the workspace.
    setState(() {
      _selectedWorkspaceTab = tab;
      if (tab != _StaffWorkspaceTab.chats) {
        _selectedFilter = switch (tab) {
          _StaffWorkspaceTab.queue => _StaffInboxFilter.waiting,
          _StaffWorkspaceTab.active => _StaffInboxFilter.active,
          _StaffWorkspaceTab.pipeline => _StaffInboxFilter.quoted,
          _StaffWorkspaceTab.closed => _StaffInboxFilter.closed,
          _StaffWorkspaceTab.chats => _selectedFilter,
        };
      }
      _selectedRequestId = null;
    });
  }

  void _selectFilter(_StaffInboxFilter filter) {
    setState(() {
      _selectedFilter = filter;
      _selectedWorkspaceTab = _workspaceTabForFilterValue(filter);
      _selectedRequestId = null;
    });
  }

  Widget _buildFilterChip(
    BuildContext context,
    StaffDashboardBundle bundle,
    _StaffInboxFilter filter,
  ) {
    final isSelected = _selectedFilter == filter;
    final foregroundColor = isSelected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.82);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _selectFilter(filter),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.cobalt
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? AppTheme.cobalt
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 8, height: 8),
              ),
              const SizedBox(width: 8),
              Text(
                _filterLabel(filter),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Text(
                    '${_filterCount(bundle, filter)}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInboxTile(
    BuildContext context,
    ServiceRequestModel request,
    bool isSelected,
  ) {
    final isWaiting = _selectedFilter == _StaffInboxFilter.waiting;
    final latestAlertLabel = _latestAlertLabel(request);
    final latestTimestamp = _formatInboxTimestamp(request.latestActivityAt);
    final backgroundColor = isSelected
        ? Color.alphaBlend(
            AppTheme.cobalt.withValues(alpha: 0.14),
            const Color(0xFF16191E),
          )
        : const Color(0xFF15171A);

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _openRequest(request),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? AppTheme.cobalt.withValues(alpha: 0.34)
                : Colors.white.withValues(alpha: 0.06),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.22 : 0.14),
              blurRadius: isSelected ? 24 : 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      request.serviceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (latestTimestamp.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    Text(
                      latestTimestamp,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: latestAlertLabel.isNotEmpty
                            ? AppTheme.cobalt
                            : Colors.white.withValues(alpha: 0.42),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(width: 12),
                  _CompactStatusPill(status: request.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${request.contactFullName} · ${request.city}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _messagePreview(request),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.74),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(
                    isWaiting
                        ? 'Waiting queue'
                        : '${request.messageCount} messages',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.54),
                    ),
                  ),
                  if (latestAlertLabel.isNotEmpty)
                    _QueueAlertPill(label: latestAlertLabel),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    StaffDashboardBundle bundle,
    List<ServiceRequestModel> filteredRequests,
    ServiceRequestModel? selectedRequest, {
    bool edgeToEdge = false,
  }) {
    final isOnline = bundle.currentAvailability == 'online';
    final BorderRadius? surfaceRadius = edgeToEdge
        ? null
        : BorderRadius.circular(30);
    final emptyLabel = switch (_selectedFilter) {
      _StaffInboxFilter.waiting => _t(
        en: 'No waiting queue threads right now.',
        de: 'Derzeit keine wartenden Warteschlangen-Chats.',
      ),
      _StaffInboxFilter.active => _t(
        en: 'No active customer threads right now.',
        de: 'Derzeit keine aktiven Kunden-Chats.',
      ),
      _StaffInboxFilter.quoted => _t(
        en: 'No quoted requests yet.',
        de: 'Noch keine Angebotsanfragen.',
      ),
      _StaffInboxFilter.confirmed => _t(
        en: 'No confirmed appointments yet.',
        de: 'Noch keine bestätigten Termine.',
      ),
      _StaffInboxFilter.pending => _t(
        en: 'No pending start jobs right now.',
        de: 'Derzeit keine ausstehenden Startaufträge.',
      ),
      _StaffInboxFilter.closed => _t(
        en: 'No closed threads in this view.',
        de: 'In dieser Ansicht keine geschlossenen Chats.',
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.darkPage,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[AppTheme.darkPageRaised, AppTheme.darkPage],
        ),
        borderRadius: surfaceRadius,
        border: edgeToEdge
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: edgeToEdge
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          edgeToEdge ? 14 : 18,
          edgeToEdge ? 14 : 18,
          edgeToEdge ? 14 : 18,
          edgeToEdge ? 8 : 12,
        ),
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
                        _t(en: 'Team Queue', de: 'Team-Warteschlange'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          PresenceChip(
                            label: isOnline
                                ? _t(
                                    en: 'Open for pickup',
                                    de: 'Bereit zur Übernahme',
                                  )
                                : _t(
                                    en: 'Pickup paused',
                                    de: 'Übernahme pausiert',
                                  ),
                            isOnline: isOnline,
                            dark: true,
                            compact: true,
                          ),
                          Text(
                            _t(
                              en: '${bundle.clearedTodayCount} cleared today',
                              de: '${bundle.clearedTodayCount} heute erledigt',
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.58),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Transform.scale(
                      scale: 0.88,
                      child: Switch.adaptive(
                        value: isOnline,
                        onChanged: _isUpdatingAvailability
                            ? null
                            : (bool value) => _updateAvailability(
                                value ? 'online' : 'offline',
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _StaffInboxFilter.values
                  .map((filter) => _buildFilterChip(context, bundle, filter))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filteredRequests.isEmpty
                  ? Center(child: _StaffSidebarEmptyState(label: emptyLabel))
                  : ListView.separated(
                      itemCount: filteredRequests.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final request = filteredRequests[index];
                        return _buildInboxTile(
                          context,
                          request,
                          selectedRequest?.id == request.id,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationHeader(
    BuildContext context,
    ServiceRequestModel request, {
    VoidCallback? onBack,
    required String currentAvailability,
    required VoidCallback onOpenProfile,
    required VoidCallback? onOpenWorkflow,
    bool workflowButtonOpensRequestActions = false,
    double collapseProgress = 0,
    bool dark = false,
  }) {
    final isWaiting = request.assignedStaff == null;
    final isAttending = _attendingQueueIds.contains(request.id);
    final isCompact = MediaQuery.sizeOf(context).width < 720;
    final compactCollapse = collapseProgress.clamp(0.0, 1.0);
    final horizontalPadding = isCompact ? 10.0 : 14.0;
    final verticalPadding = isCompact
        ? 6 - (compactCollapse * 2)
        : 8 - (compactCollapse * 2);
    final titleColor = dark ? Colors.white : null;
    final metaColor = dark ? Colors.white.withValues(alpha: 0.68) : null;
    final subtitleColor = dark
        ? Colors.white.withValues(alpha: 0.54)
        : metaColor;
    final backForeground = dark ? Colors.white.withValues(alpha: 0.84) : null;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: isCompact ? 16 : 18,
      color: titleColor,
      fontWeight: FontWeight.w700,
      height: 1.0,
    );
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: subtitleColor,
      fontWeight: FontWeight.w600,
      fontSize: isCompact ? 12 : 13,
      height: 1.1,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        verticalPadding,
        horizontalPadding,
        verticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (onBack != null) ...<Widget>[
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onBack,
                  icon: Icon(Icons.arrow_back_rounded, color: backForeground),
                ),
                const SizedBox(width: 6),
              ],
              _buildConversationAvatarButton(
                context,
                fullName: request.contactFullName,
                onPressed: onOpenProfile,
                dark: dark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      request.contactFullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_serviceLabel(request)} · ${request.city}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ],
                ),
              ),
              if (!isWaiting && request.status != 'closed') ...<Widget>[
                const SizedBox(width: 6),
                _buildAiControlToggle(
                  context,
                  request: request,
                  currentAvailability: currentAvailability,
                  compact: true,
                  dark: dark,
                ),
              ],
              const SizedBox(width: 6),
              _buildConversationHeaderStatusPill(
                context,
                request.status,
                compact: true,
                dark: dark,
              ),
              if (isWaiting || onOpenWorkflow != null) ...<Widget>[
                const SizedBox(width: 6),
                _buildCompactHeaderButton(
                  context,
                  onPressed: isWaiting
                      ? (isAttending ? null : () => _attendQueue(request))
                      : onOpenWorkflow,
                  icon: isWaiting
                      ? Icons.play_arrow_rounded
                      : workflowButtonOpensRequestActions
                      ? Icons.more_horiz_rounded
                      : Icons.tune_rounded,
                  label: '',
                  filled: isWaiting,
                  dark: dark,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          RequestWorkflowProgressBar(request: request, dark: dark),
        ],
      ),
    );
  }

  Widget _buildConversationHeaderStatusPill(
    BuildContext context,
    String status, {
    bool compact = false,
    bool dark = false,
  }) {
    if (!dark) {
      return StatusChip(status: status, compact: compact);
    }

    final colors = switch (status) {
      'submitted' => (
        background: Colors.white.withValues(alpha: 0.08),
        border: Colors.white.withValues(alpha: 0.12),
        foreground: Colors.white.withValues(alpha: 0.86),
      ),
      'under_review' => (
        background: AppTheme.ember.withValues(alpha: 0.18),
        border: AppTheme.ember.withValues(alpha: 0.34),
        foreground: const Color(0xFFFFE3C5),
      ),
      'assigned' => (
        background: AppTheme.cobalt.withValues(alpha: 0.2),
        border: AppTheme.cobalt.withValues(alpha: 0.4),
        foreground: const Color(0xFFD7E6FF),
      ),
      'quoted' => (
        background: AppTheme.ember.withValues(alpha: 0.18),
        border: AppTheme.ember.withValues(alpha: 0.34),
        foreground: const Color(0xFFFFE3C5),
      ),
      'appointment_confirmed' => (
        background: AppTheme.pine.withValues(alpha: 0.18),
        border: AppTheme.pine.withValues(alpha: 0.34),
        foreground: const Color(0xFFD6F0E7),
      ),
      'pending_start' => (
        background: const Color(0xFF5B4C8A).withValues(alpha: 0.24),
        border: const Color(0xFF8772C9).withValues(alpha: 0.36),
        foreground: const Color(0xFFE6DDFF),
      ),
      'project_started' => (
        background: const Color(0xFF174D65).withValues(alpha: 0.24),
        border: const Color(0xFF2C87B3).withValues(alpha: 0.36),
        foreground: const Color(0xFFD8F2FF),
      ),
      'work_done' => (
        background: AppTheme.pine.withValues(alpha: 0.2),
        border: AppTheme.pine.withValues(alpha: 0.36),
        foreground: const Color(0xFFD6F0E7),
      ),
      'closed' => (
        background: Colors.white.withValues(alpha: 0.08),
        border: Colors.white.withValues(alpha: 0.12),
        foreground: Colors.white.withValues(alpha: 0.78),
      ),
      _ => (
        background: Colors.white.withValues(alpha: 0.08),
        border: Colors.white.withValues(alpha: 0.12),
        foreground: Colors.white.withValues(alpha: 0.86),
      ),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 7,
        ),
        child: Text(
          requestStatusLabelFor(status, language: _language),
          style:
              (compact
                      ? Theme.of(context).textTheme.labelSmall
                      : Theme.of(context).textTheme.labelMedium)
                  ?.copyWith(
                    color: colors.foreground,
                    fontWeight: FontWeight.w700,
                  ),
        ),
      ),
    );
  }

  Widget _buildAiControlToggle(
    BuildContext context, {
    required ServiceRequestModel request,
    required String currentAvailability,
    bool compact = false,
    bool dark = false,
  }) {
    final isOnline = _isCurrentStaffOnline(currentAvailability);
    final isForcedOn = !isOnline;
    final isActive = _isAiCoverActive(request, currentAvailability);
    final isUpdating = _updatingAiControlIds.contains(request.id);
    final allowInteraction =
        !isForcedOn && !isUpdating && request.status != 'closed';
    final darkCompactBackground = isActive
        ? AppTheme.cobalt.withValues(alpha: 0.18)
        : const Color(0xFF182438);
    final backgroundColor = dark
        ? compact
              ? darkCompactBackground
              : Colors.white.withValues(alpha: isActive ? 0.08 : 0.04)
        : Colors.white;
    final borderColor = dark
        ? compact
              ? (isActive
                    ? AppTheme.cobalt.withValues(alpha: 0.38)
                    : Colors.white.withValues(alpha: 0.08))
              : Colors.white.withValues(alpha: isActive ? 0.18 : 0.1)
        : AppTheme.clay.withValues(alpha: 0.78);
    final textColor = dark ? Colors.white : AppTheme.ink;
    final iconColor = dark && compact
        ? (isActive
              ? const Color(0xFFD8E7FF)
              : Colors.white.withValues(alpha: 0.72))
        : isActive
        ? AppTheme.cobalt
        : textColor.withValues(alpha: 0.64);

    return Tooltip(
      message: isForcedOn
          ? _t(
              en: 'Naima stays active while you are offline',
              de: 'Naima bleibt aktiv, solange Sie offline sind',
            )
          : isActive
          ? _t(
              en: 'Naima is covering this chat',
              de: 'Naima betreut diesen Chat',
            )
          : _t(
              en: 'Turn Naima on to cover this chat',
              de: 'Naima für diesen Chat einschalten',
            ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: isUpdating ? 0.72 : 1,
        child: compact
            ? SizedBox(
                height: 24,
                width: 34,
                child: Transform.scale(
                  scale: 0.58,
                  child: Switch.adaptive(
                    value: isActive,
                    onChanged: allowInteraction
                        ? (bool value) => _updateAiControl(
                            request,
                            value,
                            currentAvailability: currentAvailability,
                          )
                        : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeThumbColor: dark ? Colors.white : AppTheme.cobalt,
                    activeTrackColor: AppTheme.cobalt.withValues(alpha: 0.54),
                    inactiveThumbColor: dark
                        ? Colors.white.withValues(alpha: 0.88)
                        : AppTheme.ink,
                    inactiveTrackColor: dark
                        ? Colors.white.withValues(alpha: 0.18)
                        : AppTheme.clay.withValues(alpha: 0.42),
                  ),
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: iconColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _t(en: 'Naima', de: 'Naima'),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      SizedBox(
                        width: 36,
                        child: Transform.scale(
                          scale: 0.82,
                          child: Switch.adaptive(
                            value: isActive,
                            onChanged: allowInteraction
                                ? (bool value) => _updateAiControl(
                                    request,
                                    value,
                                    currentAvailability: currentAvailability,
                                  )
                                : null,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            activeThumbColor: AppTheme.cobalt,
                            activeTrackColor: AppTheme.cobalt.withValues(
                              alpha: 0.42,
                            ),
                            inactiveThumbColor: dark
                                ? Colors.white.withValues(alpha: 0.88)
                                : AppTheme.ink,
                            inactiveTrackColor: dark
                                ? Colors.white.withValues(alpha: 0.18)
                                : AppTheme.clay.withValues(alpha: 0.42),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildCompactHeaderButton(
    BuildContext context, {
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    String? avatarText,
    bool filled = false,
    bool dark = false,
  }) {
    final foregroundColor = filled
        ? Colors.white
        : dark
        ? Colors.white.withValues(alpha: 0.9)
        : AppTheme.ink;
    final backgroundColor = filled
        ? AppTheme.cobalt
        : dark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white;
    final borderColor = dark
        ? Colors.white.withValues(alpha: filled ? 0 : 0.12)
        : AppTheme.clay.withValues(alpha: 0.82);

    if (label.isEmpty) {
      return SizedBox.square(
        dimension: 28,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            shape: BoxShape.circle,
            border: Border.all(color: borderColor),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: onPressed,
            icon: avatarText == null
                ? Icon(icon, size: 16, color: foregroundColor)
                : CircleAvatar(
                    radius: 14,
                    backgroundColor: AppTheme.cobalt.withValues(alpha: 0.16),
                    child: Text(
                      avatarText,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.cobalt,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 32,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
          side: filled ? null : BorderSide(color: borderColor),
          minimumSize: Size(label.isEmpty ? 32 : 0, 32),
          padding: EdgeInsets.symmetric(
            horizontal: label.isEmpty ? 6 : 8,
            vertical: 0,
          ),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        icon: avatarText == null
            ? Icon(icon, size: 15)
            : Text(
                avatarText,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
        label: label.isEmpty
            ? const SizedBox.shrink()
            : Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  Widget _buildConversationAvatarButton(
    BuildContext context, {
    required String fullName,
    required VoidCallback onPressed,
    required bool dark,
  }) {
    final primaryColor = dark ? AppTheme.darkAccent : AppTheme.cobalt;

    return SizedBox.square(
      dimension: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: CircleAvatar(
          radius: 14,
          backgroundColor: primaryColor.withValues(alpha: 0.15),
          child: Text(
            getInitials(fullName),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: primaryColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRequestProfileSheet(
    BuildContext context,
    ServiceRequestModel request, {
    required bool composerEnabled,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        var sheetRequest = request;

        return StatefulBuilder(
          builder: (BuildContext modalContext, StateSetter setModalState) {
            final sheetComposerEnabled =
                sheetRequest.assignedStaff != null &&
                sheetRequest.status != 'closed';

            return SafeArea(
              top: false,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF0F1216),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    top: 14,
                    right: 16,
                    bottom: 16 + MediaQuery.viewInsetsOf(modalContext).bottom,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Center(
                          child: Container(
                            width: 44,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${sheetRequest.contactFullName} profile',
                          style: Theme.of(modalContext).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Reference details and quick actions for this request.',
                          style: Theme.of(modalContext).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.62),
                              ),
                        ),
                        const SizedBox(height: 16),
                        _buildRequestBriefCard(
                          modalContext,
                          sheetRequest,
                          composerEnabled: sheetComposerEnabled,
                          showClockAction: _canCurrentStaffClockRequest(
                            sheetRequest,
                          ),
                          isClocking: _clockingRequestIds.contains(
                            sheetRequest.id,
                          ),
                          onClockAction: () async {
                            final action =
                                _activeCurrentStaffWorkLog(sheetRequest) == null
                                ? 'clock_in'
                                : 'clock_out';
                            final updatedRequest = await _clockRequestWork(
                              sheetRequest,
                              action,
                            );
                            if (updatedRequest != null) {
                              setModalState(
                                () => sheetRequest = updatedRequest,
                              );
                            }
                          },
                          showCompleteAction:
                              _canCurrentStaffCompleteRequestWork(sheetRequest),
                          isCompleting: _completingWorkRequestIds.contains(
                            sheetRequest.id,
                          ),
                          onCompleteAction: () async {
                            final updatedRequest = await _completeRequestWork(
                              sheetRequest,
                            );
                            if (updatedRequest != null) {
                              setModalState(
                                () => sheetRequest = updatedRequest,
                              );
                            }
                          },
                        ),
                        if (sheetComposerEnabled) ...<Widget>[
                          const SizedBox(height: 16),
                          Builder(
                            builder: (BuildContext _) {
                              final ownEstimation = _currentUserEstimationFor(
                                sheetRequest,
                              );
                              return _StaffChatActionTray(
                                request: sheetRequest,
                                isCustomerCareUser: _isCustomerCareUser,
                                isSendingUpdateRequest: _sendingMessageIds
                                    .contains(sheetRequest.id),
                                isSendingInvoice: _sendingInvoiceIds.contains(
                                  sheetRequest.id,
                                ),
                                hasPendingCustomerUpdateRequest:
                                    _hasPendingCustomerUpdateRequest(
                                      sheetRequest,
                                    ),
                                ownEstimation: ownEstimation,
                                isEstimationLocked:
                                    sheetRequest.estimationLocked,
                                isReviewingPaymentProof:
                                    _reviewingPaymentProofIds.contains(
                                      sheetRequest.id,
                                    ),
                                onAskCustomerUpdate: () {
                                  Navigator.of(modalContext).pop();
                                  _sendCustomerUpdateRequest(sheetRequest);
                                },
                                onClearCustomerUpdate: () {
                                  Navigator.of(modalContext).pop();
                                  _clearCustomerUpdateRequest(sheetRequest);
                                },
                                onEditEstimate: () {
                                  Navigator.of(modalContext).pop();
                                  _editEstimation(sheetRequest);
                                },
                                canClockRequest: _canCurrentStaffClockRequest(
                                  sheetRequest,
                                ),
                                isClockingRequest: _clockingRequestIds.contains(
                                  sheetRequest.id,
                                ),
                                hasActiveClockLog:
                                    _activeCurrentStaffWorkLog(sheetRequest) !=
                                    null,
                                onClockRequest: () async {
                                  final action =
                                      _activeCurrentStaffWorkLog(
                                            sheetRequest,
                                          ) ==
                                          null
                                      ? 'clock_in'
                                      : 'clock_out';
                                  Navigator.of(modalContext).pop();
                                  await _clockRequestWork(sheetRequest, action);
                                },
                                canCompleteWork:
                                    _canCurrentStaffCompleteRequestWork(
                                      sheetRequest,
                                    ),
                                isCompletingWork: _completingWorkRequestIds
                                    .contains(sheetRequest.id),
                                onCompleteWork: () async {
                                  final updatedRequest =
                                      await _completeRequestWork(sheetRequest);
                                  if (updatedRequest != null) {
                                    setModalState(
                                      () => sheetRequest = updatedRequest,
                                    );
                                  }
                                },
                                onBookSiteReview: () {
                                  Navigator.of(modalContext).pop();
                                  _bookSiteReview(sheetRequest);
                                },
                                onRunFinalEstimate: () {
                                  Navigator.of(modalContext).pop();
                                  _runFinalEstimate(sheetRequest);
                                },
                                onOpenPaymentProof:
                                    sheetRequest.invoice?.proof?.fileUrl == null
                                    ? null
                                    : () {
                                        Navigator.of(modalContext).pop();
                                        _openPaymentProof(sheetRequest);
                                      },
                                onOpenReceipt:
                                    sheetRequest.invoice?.receiptUrl == null
                                    ? null
                                    : () {
                                        Navigator.of(modalContext).pop();
                                        _openReceipt(sheetRequest);
                                      },
                                onApprovePaymentProof:
                                    sheetRequest.invoice?.isProofSubmitted ==
                                        true
                                    ? () {
                                        Navigator.of(modalContext).pop();
                                        _reviewPaymentProof(
                                          sheetRequest,
                                          decision: 'approved',
                                        );
                                      }
                                    : null,
                                onRejectPaymentProof:
                                    sheetRequest.invoice?.isProofSubmitted ==
                                        true
                                    ? () {
                                        Navigator.of(modalContext).pop();
                                        _reviewPaymentProof(
                                          sheetRequest,
                                          decision: 'rejected',
                                        );
                                      }
                                    : null,
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showWorkflowSheet(
    BuildContext context,
    ServiceRequestModel request,
  ) async {
    if (request.assignedStaff == null || request.status == 'closed') {
      return;
    }

    final baseStatus = _actionableStatuses.contains(request.status)
        ? request.status
        : null;
    String? localSelectedStatus = _selectedStatuses[request.id] ?? baseStatus;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        return StatefulBuilder(
          builder: (BuildContext modalContext, StateSetter setModalState) {
            final isSavingStatus = _savingStatusIds.contains(request.id);
            final canSaveStatus =
                !isSavingStatus &&
                localSelectedStatus != null &&
                localSelectedStatus != request.status;

            return SafeArea(
              top: false,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF0F1216),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    top: 14,
                    right: 16,
                    bottom: 16 + MediaQuery.viewInsetsOf(modalContext).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _t(en: 'Workflow', de: 'Ablauf'),
                        style: Theme.of(modalContext).textTheme.titleLarge
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _t(
                          en: 'Update the job status without covering the chat.',
                          de: 'Aktualisieren Sie den Auftragsstatus, ohne den Chat zu überdecken.',
                        ),
                        style: Theme.of(modalContext).textTheme.bodyMedium
                            ?.copyWith(
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: localSelectedStatus,
                        hint: Text(
                          request.status == 'assigned'
                              ? _t(
                                  en: 'Select next status',
                                  de: 'Nächsten Status wählen',
                                )
                              : _t(
                                  en: 'Choose workflow status',
                                  de: 'Ablaufstatus wählen',
                                ),
                        ),
                        decoration: InputDecoration(
                          labelText: _t(en: 'Status', de: 'Status'),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                            value: 'under_review',
                            child: Text(
                              _t(en: 'Under review', de: 'In Prüfung'),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'quoted',
                            child: Text(
                              _t(en: 'Quoted', de: 'Angebot gesendet'),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'appointment_confirmed',
                            child: Text(
                              _t(
                                en: 'Appointment confirmed',
                                de: 'Termin bestätigt',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'pending_start',
                            child: Text(
                              _t(en: 'Pending start', de: 'Start ausstehend'),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'project_started',
                            child: Text(
                              _t(
                                en: 'Project started',
                                de: 'Projekt gestartet',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'work_done',
                            child: Text(
                              _t(en: 'Work done', de: 'Arbeit erledigt'),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'closed',
                            child: Text(_t(en: 'Closed', de: 'Geschlossen')),
                          ),
                        ],
                        onChanged: (String? value) {
                          if (value == null) {
                            return;
                          }

                          setState(() => _selectedStatuses[request.id] = value);
                          setModalState(() => localSelectedStatus = value);
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonal(
                          onPressed: canSaveStatus
                              ? () async {
                                  String? password;
                                  if (localSelectedStatus == 'work_done') {
                                    password =
                                        await _promptForWorkCompletionPassword();
                                    if (password == null || password.isEmpty) {
                                      return;
                                    }
                                  }

                                  final updatedRequest = await _updateStatus(
                                    request: request,
                                    status: localSelectedStatus!,
                                    password: password,
                                  );
                                  if (updatedRequest != null &&
                                      modalContext.mounted) {
                                    Navigator.of(modalContext).pop();
                                  }
                                }
                              : null,
                          child: Text(
                            isSavingStatus
                                ? _t(en: 'Saving...', de: 'Speichert...')
                                : _t(en: 'Save', de: 'Speichern'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRequestBriefCard(
    BuildContext context,
    ServiceRequestModel request, {
    required bool composerEnabled,
    bool showClockAction = false,
    bool isClocking = false,
    VoidCallback? onClockAction,
    bool showCompleteAction = false,
    bool isCompleting = false,
    VoidCallback? onCompleteAction,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFFCF7), Color(0xFFF6EFE3)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppTheme.clay.withValues(alpha: 0.7)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        _t(
                          en: 'Customer request brief',
                          de: 'Kundenanfrage kompakt',
                        ),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _t(
                          en: 'Reference details for this chat. Download it or review the latest request context.',
                          de: 'Referenzdetails zu diesem Chat. Laden Sie sie herunter oder prüfen Sie den aktuellen Anfragestatus.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.ink.withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppTheme.clay.withValues(alpha: 0.65),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      '#${request.id.length > 8 ? request.id.substring(0, 8) : request.id}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppTheme.ink.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _RequestBriefItem(
                  icon: Icons.person_outline_rounded,
                  label: _t(en: 'Customer', de: 'Kunde'),
                  value: request.contactFullName.isEmpty
                      ? _t(en: 'Not provided', de: 'Nicht angegeben')
                      : request.contactFullName,
                ),
                _RequestBriefItem(
                  icon: Icons.mail_outline_rounded,
                  label: _t(en: 'Email', de: 'E-Mail'),
                  value: request.contactEmail.isEmpty
                      ? _t(en: 'Not provided', de: 'Nicht angegeben')
                      : request.contactEmail,
                ),
                _RequestBriefItem(
                  icon: Icons.call_outlined,
                  label: _t(en: 'Phone', de: 'Telefon'),
                  value: request.contactPhone.isEmpty
                      ? _t(en: 'Not provided', de: 'Nicht angegeben')
                      : request.contactPhone,
                ),
                _RequestBriefItem(
                  icon: Icons.place_outlined,
                  label: _t(en: 'Address', de: 'Adresse'),
                  value: _requestAddress(request),
                ),
                _RequestBriefItem(
                  icon: Icons.event_outlined,
                  label: _t(en: 'Preferred date', de: 'Wunschtermin'),
                  value: _formatRequestDate(request.preferredDate),
                ),
                _RequestBriefItem(
                  icon: Icons.schedule_rounded,
                  label: _t(en: 'Time window', de: 'Zeitfenster'),
                  value: request.preferredTimeWindow.isEmpty
                      ? _t(en: 'Not provided', de: 'Nicht angegeben')
                      : request.preferredTimeWindow,
                ),
                _RequestBriefItem(
                  icon: Icons.event_available_rounded,
                  label: _t(en: 'Estimated start', de: 'Geplanter Start'),
                  value: _formatEstimatedScheduleBoundary(
                    request,
                    isStart: true,
                  ),
                ),
                _RequestBriefItem(
                  icon: Icons.event_busy_rounded,
                  label: _t(en: 'Estimated finish', de: 'Geplantes Ende'),
                  value: _formatEstimatedScheduleBoundary(
                    request,
                    isStart: false,
                  ),
                ),
                _RequestBriefItem(
                  icon: Icons.event_note_rounded,
                  label: _t(
                    en: 'Estimated review date',
                    de: 'Geplantes Besichtigungsdatum',
                  ),
                  value: _formatScheduledSiteReviewDate(request),
                ),
                _RequestBriefItem(
                  icon: Icons.more_time_rounded,
                  label: _t(
                    en: 'Estimated review time',
                    de: 'Geplante Besichtigungszeit',
                  ),
                  value: _formatScheduledSiteReviewTime(request),
                ),
                _RequestBriefItem(
                  icon: Icons.rate_review_outlined,
                  label: _t(
                    en: 'Review clock in',
                    de: 'Besichtigung eingestempelt',
                  ),
                  value: _formatRequestWorkLogLabel(
                    _firstWorkLog(request, siteReviewOnly: true),
                    _firstWorkLog(request, siteReviewOnly: true)?.startedAt,
                  ),
                ),
                _RequestBriefItem(
                  icon: Icons.rate_review_rounded,
                  label: _t(
                    en: 'Review clock out',
                    de: 'Besichtigung ausgestempelt',
                  ),
                  value: _formatRequestWorkLogLabel(
                    _latestStoppedWorkLog(request, siteReviewOnly: true),
                    _latestStoppedWorkLog(
                      request,
                      siteReviewOnly: true,
                    )?.stoppedAt,
                  ),
                ),
                _RequestBriefItem(
                  icon: Icons.play_circle_outline_rounded,
                  label: _t(en: 'Job clock in', de: 'Job eingestempelt'),
                  value: _formatRequestWorkLogLabel(
                    _firstWorkLog(request, siteReviewOnly: false),
                    request.projectStartedAt ??
                        _firstWorkLog(
                          request,
                          siteReviewOnly: false,
                        )?.startedAt,
                  ),
                ),
                _RequestBriefItem(
                  icon: Icons.task_alt_rounded,
                  label: _t(en: 'Job clock out', de: 'Job ausgestempelt'),
                  value: _formatRequestWorkLogLabel(
                    _latestStoppedWorkLog(request, siteReviewOnly: false),
                    request.finishedAt ??
                        _latestStoppedWorkLog(
                          request,
                          siteReviewOnly: false,
                        )?.stoppedAt,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.clay.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _t(en: 'Original request', de: 'Originalanfrage'),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      request.message.trim().isEmpty
                          ? _t(
                              en: 'No customer request note was provided.',
                              de: 'Es wurde keine Kundennotiz angegeben.',
                            )
                          : request.message.trim(),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: () => _downloadRequestBrief(request),
                  icon: const Icon(Icons.download_rounded),
                  label: Text(_t(en: 'Download brief', de: 'Briefing laden')),
                ),
                if (showClockAction)
                  FilledButton.icon(
                    onPressed: isClocking ? null : onClockAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.cobalt,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      isClocking
                          ? Icons.more_horiz_rounded
                          : _activeCurrentStaffWorkLog(request) == null
                          ? Icons.login_rounded
                          : Icons.logout_rounded,
                    ),
                    label: Text(
                      isClocking
                          ? _t(en: 'Saving...', de: 'Speichert...')
                          : _activeCurrentStaffWorkLog(request) == null
                          ? _t(en: 'Clock in', de: 'Einstempeln')
                          : _t(en: 'Clock out', de: 'Ausstempeln'),
                    ),
                  ),
                if (showCompleteAction)
                  FilledButton.icon(
                    onPressed: isCompleting ? null : onCompleteAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.pine,
                      foregroundColor: Colors.white,
                    ),
                    icon: Icon(
                      isCompleting
                          ? Icons.more_horiz_rounded
                          : Icons.task_alt_rounded,
                    ),
                    label: Text(
                      isCompleting
                          ? _t(en: 'Saving...', de: 'Speichert...')
                          : _t(en: 'Complete work', de: 'Arbeit abschließen'),
                    ),
                  ),
              ],
            ),
            if (showClockAction) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _clockingSummary(request),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.ink.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (!composerEnabled) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _t(
                  en: 'Attend the queue item first before sending an update request to the client.',
                  de: 'Übernehmen Sie zuerst diesen Warteschlangeneintrag, bevor Sie eine Aktualisierungsanfrage an den Kunden senden.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.ink.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConversationClockStrip(ServiceRequestModel request) {
    final hasActiveClockLog = _activeCurrentStaffWorkLog(request) != null;
    final isClockingRequest = _clockingRequestIds.contains(request.id);
    final canCompleteWork = _canCurrentStaffCompleteRequestWork(request);
    final isCompletingWork = _completingWorkRequestIds.contains(request.id);
    final isSiteReviewClockAction = request.isSiteReviewPending;
    final actionLabel = isSiteReviewClockAction
        ? hasActiveClockLog
              ? _t(en: 'Clock out review', de: 'Besichtigung ausstempeln')
              : _t(en: 'Clock in review', de: 'Zur Besichtigung einstempeln')
        : hasActiveClockLog
        ? _t(en: 'Clock out work', de: 'Arbeit ausstempeln')
        : _t(en: 'Clock in work', de: 'Arbeit einstempeln');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.darkSurfaceMuted.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  Icon(
                    hasActiveClockLog
                        ? Icons.timer_outlined
                        : Icons.schedule_rounded,
                    color: AppTheme.cobalt,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _clockingSummary(request),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: isClockingRequest
                      ? null
                      : () => _clockRequestWork(
                          request,
                          hasActiveClockLog ? 'clock_out' : 'clock_in',
                        ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.cobalt,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 38),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(
                    isClockingRequest
                        ? Icons.more_horiz_rounded
                        : hasActiveClockLog
                        ? Icons.logout_rounded
                        : Icons.login_rounded,
                    size: 18,
                  ),
                  label: Text(actionLabel),
                ),
                if (canCompleteWork)
                  FilledButton.icon(
                    onPressed: isCompletingWork
                        ? null
                        : () => _completeRequestWork(request),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.pine,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      minimumSize: const Size(0, 38),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      isCompletingWork
                          ? Icons.more_horiz_rounded
                          : Icons.task_alt_rounded,
                      size: 18,
                    ),
                    label: Text(
                      isCompletingWork
                          ? _t(en: 'Saving...', de: 'Speichert...')
                          : _t(en: 'Complete work', de: 'Arbeit abschließen'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationPane(
    BuildContext context,
    ServiceRequestModel? request, {
    VoidCallback? onBack,
    bool edgeToEdge = false,
    required String currentAvailability,
  }) {
    final BorderRadius? surfaceRadius = edgeToEdge
        ? null
        : BorderRadius.circular(30);

    if (request == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.darkPage,
          borderRadius: surfaceRadius,
          border: edgeToEdge
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Center(
          child: Text(
            _t(
              en: 'Pick a queue thread to continue.',
              de: 'Wählen Sie einen Warteschlangen-Chat zum Fortfahren.',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
        ),
      );
    }

    final controller = _controllerFor(request.id);
    final isSending = _sendingMessageIds.contains(request.id);
    final isUploadingAttachment = _uploadingAttachmentIds.contains(request.id);
    final canAttendWaitingRequest =
        request.assignedStaff == null && request.status != 'closed';
    final isAttending = _attendingQueueIds.contains(request.id);
    final composerEnabled =
        request.assignedStaff != null && request.status != 'closed';
    final canOpenRequestActions = composerEnabled;
    final canOpenWorkflowActions = composerEnabled && !_isCustomerCareUser;
    final aiCoverActive = _isAiCoverActive(request, currentAvailability);
    final isCompact = MediaQuery.sizeOf(context).width < 720;
    final collapseProgress = isCompact
        ? ((_conversationScrollOffsetsByRequestId[request.id] ?? 0) / 88).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.darkPage,
        borderRadius: surfaceRadius,
        border: edgeToEdge
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: <Widget>[
          _buildConversationHeader(
            context,
            request,
            onBack: onBack,
            currentAvailability: currentAvailability,
            onOpenProfile: () => _showRequestProfileSheet(
              context,
              request,
              composerEnabled: composerEnabled,
            ),
            onOpenWorkflow: canOpenRequestActions
                ? () => canOpenWorkflowActions
                      ? _showWorkflowSheet(context, request)
                      : _showRequestProfileSheet(
                          context,
                          request,
                          composerEnabled: composerEnabled,
                        )
                : null,
            workflowButtonOpensRequestActions:
                canOpenRequestActions && !canOpenWorkflowActions,
            collapseProgress: collapseProgress,
            dark: true,
          ),
          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    AppTheme.darkSurface,
                    AppTheme.pine.withValues(alpha: 0.08),
                    AppTheme.darkPage,
                  ],
                ),
              ),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification notification) {
                        if (notification.metrics.axis == Axis.vertical &&
                            isCompact) {
                          _updateConversationScrollOffset(
                            request.id,
                            notification.metrics.pixels,
                          );
                        }

                        return false;
                      },
                      child: SingleChildScrollView(
                        controller: _requestThreadScrollController,
                        padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            RequestThreadSection(
                              key: ValueKey<String>(request.id),
                              messages: request.messages,
                              viewerRole: 'staff',
                              dark: true,
                              emptyLabel: _t(
                                en: 'No thread messages yet.',
                                de: 'Noch keine Chat-Nachrichten vorhanden.',
                              ),
                              messageActionBuilder:
                                  (RequestMessageModel message) =>
                                      _buildStaffThreadMessageAction(
                                        request,
                                        message,
                                      ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: Builder(
                      builder: (BuildContext context) {
                        final isRefiningMessage = _refiningMessageIds.contains(
                          request.id,
                        );
                        final isComposerBusy =
                            isSending ||
                            isRefiningMessage ||
                            isUploadingAttachment;

                        return Column(
                          children: <Widget>[
                            if (_canCurrentStaffClockRequest(request) ||
                                _canCurrentStaffCompleteRequestWork(
                                  request,
                                )) ...<Widget>[
                              _buildConversationClockStrip(request),
                              const SizedBox(height: 10),
                            ],
                            if (canAttendWaitingRequest) ...<Widget>[
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: isAttending
                                      ? null
                                      : () => _attendQueue(request),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.cobalt,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                  icon: Icon(
                                    isAttending
                                        ? Icons.more_horiz_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  label: Text(
                                    isAttending
                                        ? _t(
                                            en: 'Taking request...',
                                            de: 'Anfrage wird übernommen...',
                                          )
                                        : _t(
                                            en: 'Take this customer request',
                                            de: 'Diese Kundenanfrage übernehmen',
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (canOpenRequestActions) ...<Widget>[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.tonalIcon(
                                  onPressed: () => canOpenWorkflowActions
                                      ? _showWorkflowSheet(context, request)
                                      : _showRequestProfileSheet(
                                          context,
                                          request,
                                          composerEnabled: composerEnabled,
                                        ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.08,
                                    ),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: Icon(
                                    canOpenWorkflowActions
                                        ? Icons.tune_rounded
                                        : Icons.more_horiz_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    canOpenWorkflowActions
                                        ? _t(
                                            en: 'Workflow actions',
                                            de: 'Ablaufaktionen',
                                          )
                                        : _t(
                                            en: 'Request actions',
                                            de: 'Anfrageaktionen',
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            RequestMessageComposer(
                              controller: controller,
                              leadingActions: <Widget>[
                                _StaffComposerActionButton(
                                  tooltip: _t(
                                    en: isRefiningMessage
                                        ? 'Naima AI is refining your reply'
                                        : 'Naima AI can read this conversation and refine your reply',
                                    de: isRefiningMessage
                                        ? 'Naima KI verfeinert gerade Ihre Antwort'
                                        : 'Naima KI kann diesen Verlauf lesen und Ihre Antwort verfeinern',
                                  ),
                                  icon: isRefiningMessage
                                      ? Icons.more_horiz_rounded
                                      : Icons.auto_awesome_rounded,
                                  accentColor: AppTheme.pine,
                                  onPressed: !composerEnabled || isComposerBusy
                                      ? null
                                      : () => _refineDraftWithAi(request),
                                ),
                                _StaffComposerActionButton(
                                  tooltip: _t(
                                    en: 'Upload file',
                                    de: 'Datei hochladen',
                                  ),
                                  icon: isUploadingAttachment
                                      ? Icons.more_horiz_rounded
                                      : Icons.attach_file_rounded,
                                  onPressed: !composerEnabled || isComposerBusy
                                      ? null
                                      : () => _uploadRequestAttachment(request),
                                ),
                              ],
                              hintText: composerEnabled
                                  ? aiCoverActive
                                        ? _t(
                                            en: 'Reply here to take the chat back from Naima',
                                            de: 'Hier antworten, um den Chat von Naima zurückzunehmen',
                                          )
                                        : _t(
                                            en: 'Reply to the customer here',
                                            de: 'Hier dem Kunden antworten',
                                          )
                                  : _t(
                                      en: 'Attend the queue before replying',
                                      de: 'Übernehmen Sie die Warteschlange, bevor Sie antworten',
                                    ),
                              buttonLabel: aiCoverActive
                                  ? _t(
                                      en: 'Send and resume',
                                      de: 'Senden und fortsetzen',
                                    )
                                  : _t(en: 'Send reply', de: 'Antwort senden'),
                              isSubmitting: isComposerBusy,
                              dark: true,
                              isEnabled: composerEnabled,
                              onSubmit: () => _sendMessage(request),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<WorkspaceBottomNavItem> _buildNavItems(
    StaffDashboardBundle bundle, {
    required int internalChatUnreadCount,
  }) {
    final pipelineCount =
        bundle.quotedCount + bundle.confirmedCount + bundle.pendingStartCount;

    return <WorkspaceBottomNavItem>[
      WorkspaceBottomNavItem(
        label: _t(en: 'Queue', de: 'Warteschlange'),
        icon: Icons.inbox_rounded,
        badgeText: '${bundle.waitingQueueCount}',
      ),
      WorkspaceBottomNavItem(
        label: _t(en: 'Active', de: 'Aktiv'),
        icon: Icons.support_agent_rounded,
        badgeText: '${bundle.assignedCount}',
      ),
      WorkspaceBottomNavItem(
        label: _t(en: 'Pipeline', de: 'Ablauf'),
        icon: Icons.rule_folder_rounded,
        badgeText: '$pipelineCount',
      ),
      WorkspaceBottomNavItem(
        label: _t(en: 'Closed', de: 'Geschlossen'),
        icon: Icons.done_all_rounded,
        badgeText: '${_filterCount(bundle, _StaffInboxFilter.closed)}',
      ),
      WorkspaceBottomNavItem(
        label: _t(en: 'Chats', de: 'Chats'),
        icon: Icons.forum_rounded,
        badgeText: '$internalChatUnreadCount',
        badgeBackgroundColor: const Color(0xFFE04F5F),
        badgeForegroundColor: Colors.white,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLanguageProvider);
    final bundleAsync = ref.watch(staffDashboardProvider);
    final authState = ref.watch(authControllerProvider);
    final internalChatUnreadAsync = ref.watch(
      internalChatUnreadCountProvider('staff'),
    );
    final width = MediaQuery.sizeOf(context).width;
    final pagePadding = width < 600 ? 12.0 : 20.0;

    return Scaffold(
      backgroundColor: AppTheme.darkPage,
      appBar: AppBar(
        backgroundColor: AppTheme.darkPage,
        foregroundColor: AppTheme.darkText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: _t(en: 'Staff Queue', de: 'Team-Warteschlange'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.darkText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: ' · ',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.darkTextSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: authState.user?.fullName ?? _t(en: 'Staff', de: 'Team'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.darkTextMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          WorkspaceCalendarActionButton(
            tooltip: _t(en: 'Shared calendar', de: 'Gemeinsamer Kalender'),
            onPressed: () => context.go('/staff/calendar'),
            dark: true,
          ),
          WorkspaceProfileActionButton(
            tooltip: _t(en: 'Profile', de: 'Profil'),
            onPressed: () => context.go('/staff/profile'),
            displayName: authState.user?.fullName ?? '',
            dark: true,
          ),
          AppLanguageToggle(
            language: _language,
            onChanged: ref.read(appLanguageProvider.notifier).setLanguage,
            dark: true,
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
            dark: true,
          ),
        ],
      ),
      body: bundleAsync.when(
        data: (StaffDashboardBundle bundle) {
          if (_selectedWorkspaceTab == _StaffWorkspaceTab.chats) {
            return InternalChatScreen(
              currentUserId: authState.user?.id ?? '',
              currentUserName: authState.user?.fullName ?? 'Staff',
              viewerRole: 'staff',
            );
          }

          final filteredRequests = _requestsForFilter(bundle, _selectedFilter);

          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final isDesktop = constraints.maxWidth >= 1180;
              final selectedRequest = _resolveSelectedRequest(
                filteredRequests,
                preferFirst: isDesktop,
              );
              final showDetailOnly =
                  !isDesktop &&
                  _selectedRequestId != null &&
                  selectedRequest != null;
              final isConversationVisible = isDesktop || showDetailOnly;

              if (isConversationVisible) {
                _scheduleMarkRequestViewed(selectedRequest);
                _scheduleThreadScrollToLatest(selectedRequest);
              }

              if (isDesktop) {
                return Padding(
                  padding: EdgeInsets.all(pagePadding),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1480),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          SizedBox(
                            width: 360,
                            child: _buildSidebar(
                              context,
                              bundle,
                              filteredRequests,
                              selectedRequest,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildConversationPane(
                              context,
                              selectedRequest,
                              currentAvailability: bundle.currentAvailability,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              if (showDetailOnly) {
                return _buildConversationPane(
                  context,
                  selectedRequest,
                  onBack: () => setState(() => _selectedRequestId = null),
                  edgeToEdge: true,
                  currentAvailability: bundle.currentAvailability,
                );
              }

              return _buildSidebar(
                context,
                bundle,
                filteredRequests,
                selectedRequest,
                edgeToEdge: true,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.darkPage,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Center(
            child: Text(
              error.toString(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
      bottomNavigationBar: bundleAsync.maybeWhen(
        data: (StaffDashboardBundle bundle) {
          final internalChatUnreadCount = internalChatUnreadAsync.maybeWhen(
            data: (count) => count,
            orElse: () => 0,
          );
          return WorkspaceBottomNav(
            items: _buildNavItems(
              bundle,
              internalChatUnreadCount: internalChatUnreadCount,
            ),
            selectedIndex: _selectedWorkspaceTab.index,
            dark: true,
            compact: true,
            onTap: (int index) {
              _selectWorkspaceTab(_StaffWorkspaceTab.values[index]);
            },
          );
        },
        orElse: () => null,
      ),
    );
  }
}

class _StaffComposerActionButton extends StatelessWidget {
  const _StaffComposerActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.accentColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final resolvedAccentColor = accentColor ?? Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: onPressed == null ? 0.05 : 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: onPressed == null
              ? resolvedAccentColor.withValues(alpha: 0.38)
              : resolvedAccentColor.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

class _QueueAlertPill extends StatelessWidget {
  const _QueueAlertPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.ember.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.ember.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.notifications_active_rounded,
              size: 14,
              color: AppTheme.ember.withValues(alpha: 0.92),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppTheme.ember.withValues(alpha: 0.92),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffSidebarEmptyState extends StatelessWidget {
  const _StaffSidebarEmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Icon(
              Icons.inbox_outlined,
              size: 28,
              color: Colors.white.withValues(alpha: 0.84),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.74),
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _RequestBriefItem extends StatelessWidget {
  const _RequestBriefItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.clay.withValues(alpha: 0.46)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.cobalt.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, size: 16, color: AppTheme.cobalt),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppTheme.ink.withValues(alpha: 0.62),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w600,
                        height: 1.28,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffChatActionTray extends ConsumerWidget {
  const _StaffChatActionTray({
    required this.request,
    required this.isCustomerCareUser,
    required this.isSendingUpdateRequest,
    required this.isSendingInvoice,
    required this.hasPendingCustomerUpdateRequest,
    required this.ownEstimation,
    required this.isEstimationLocked,
    required this.isReviewingPaymentProof,
    required this.onAskCustomerUpdate,
    required this.onClearCustomerUpdate,
    required this.onEditEstimate,
    required this.canClockRequest,
    required this.isClockingRequest,
    required this.hasActiveClockLog,
    required this.onClockRequest,
    required this.canCompleteWork,
    required this.isCompletingWork,
    required this.onCompleteWork,
    required this.onBookSiteReview,
    required this.onRunFinalEstimate,
    required this.onOpenPaymentProof,
    required this.onOpenReceipt,
    required this.onApprovePaymentProof,
    required this.onRejectPaymentProof,
  });

  final ServiceRequestModel request;
  final bool isCustomerCareUser;
  final bool isSendingUpdateRequest;
  final bool isSendingInvoice;
  final bool hasPendingCustomerUpdateRequest;
  final RequestEstimationModel? ownEstimation;
  final bool isEstimationLocked;
  final bool isReviewingPaymentProof;
  final VoidCallback onAskCustomerUpdate;
  final VoidCallback onClearCustomerUpdate;
  final VoidCallback onEditEstimate;
  final bool canClockRequest;
  final bool isClockingRequest;
  final bool hasActiveClockLog;
  final VoidCallback onClockRequest;
  final bool canCompleteWork;
  final bool isCompletingWork;
  final VoidCallback onCompleteWork;
  final VoidCallback onBookSiteReview;
  final VoidCallback onRunFinalEstimate;
  final VoidCallback? onOpenPaymentProof;
  final VoidCallback? onOpenReceipt;
  final VoidCallback? onApprovePaymentProof;
  final VoidCallback? onRejectPaymentProof;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final invoice = request.invoice;
    final customerUpdatesLocked = invoice != null;
    final statusLabel = invoice == null
        ? ''
        : requestStatusLabelFor(invoice.status, language: language);
    final showSiteReviewFlow =
        !isCustomerCareUser && request.isSiteReviewRequired;
    final hasOwnEstimation = ownEstimation != null;
    final hasSiteReviewBooking =
        ownEstimation?.hasSiteReviewBooking == true ||
        request.siteReviewReadyEstimation != null;
    final isSiteReviewBookingLocked =
        invoice?.isSiteReview == true &&
        request.assessmentStatus != 'site_visit_completed';
    final isSiteReviewClockAction = request.isSiteReviewPending;
    final hasOwnFinalEstimate =
        ownEstimation?.stage == 'final' &&
        ((ownEstimation?.estimatedStartDate != null &&
                ownEstimation?.estimatedEndDate != null) ||
            ownEstimation?.isComplete == true);
    final estimationActionLabel = isSendingInvoice
        ? language.pick(
            en: 'Saving estimate...',
            de: 'Schätzung wird gespeichert...',
          )
        : isCustomerCareUser
        ? language.pick(
            en: 'Customer care sends from chat',
            de: 'Kundenservice sendet im Chat',
          )
        : isEstimationLocked
        ? language.pick(
            en: 'Estimate locked after quoted',
            de: 'Schätzung nach Angebot gesperrt',
          )
        : hasOwnEstimation
        ? language.pick(en: 'Update estimate', de: 'Schätzung aktualisieren')
        : language.pick(en: 'Create estimate', de: 'Schätzung erstellen');
    final estimationSummary = invoice == null
        ? isCustomerCareUser
              ? language.pick(
                  en: 'Customer care does not edit field estimates. Wait for staff updates and send only from the quotation-ready chat card.',
                  de: 'Der Kundenservice bearbeitet keine Feldeinschätzungen. Warten Sie auf Mitarbeiter-Updates und senden Sie nur über die angebotbereite Chat-Karte.',
                )
              : isEstimationLocked
              ? language.pick(
                  en: 'Customer care already marked this request quoted, so the estimate is now locked.',
                  de: 'Der Kundenservice hat diese Anfrage bereits als angeboten markiert, daher ist die Schätzung nun gesperrt.',
                )
              : language.pick(
                  en: 'Create or update your estimate here. Admin reviews internally, then customer care sends from the request chat.',
                  de: 'Erstellen oder aktualisieren Sie hier Ihre Schätzung. Admin prüft intern, danach sendet der Kundenservice aus dem Anfrage-Chat.',
                )
        : language.pick(
            en: 'Quotation ${invoice.invoiceNumber} is ${statusLabel.toLowerCase()}.',
            de: 'Angebot ${invoice.invoiceNumber} ist ${statusLabel.toLowerCase()}.',
          );
    final siteReviewActionLabel = hasSiteReviewBooking
        ? language.pick(
            en: 'Update scheduled review',
            de: 'Geplante Besichtigung aktualisieren',
          )
        : language.pick(en: 'Book scheduled review', de: 'Besichtigung buchen');
    final finalEstimateActionLabel = hasOwnFinalEstimate
        ? language.pick(
            en: 'Update estimate after review',
            de: 'Schätzung nach Besichtigung aktualisieren',
          )
        : language.pick(
            en: 'Run estimate after review',
            de: 'Schätzung nach Besichtigung starten',
          );
    final stageSummary = switch ((invoice != null, showSiteReviewFlow)) {
      (true, _) => estimationSummary,
      (false, true) when request.isSiteReviewReadyForCustomerCare => language.pick(
        en: 'Next: customer care sends the reviewed site review package to the customer.',
        de: 'Als Nächstes sendet der Kundenservice das geprüfte Besichtigungspaket an den Kunden.',
      ),
      (false, true) when isSiteReviewBookingLocked => language.pick(
        en: 'Next: wait for the booked review to happen. Clock in and out on the visit day, then run the final estimate.',
        de: 'Als Nächstes warten Sie auf die gebuchte Besichtigung. Stempeln Sie am Einsatztag ein und aus und erstellen Sie dann die finale Schätzung.',
      ),
      (false, true)
          when request.isSiteReviewReadyForInternalReview ||
              request.hasQuoteReview =>
        language.pick(
          en: 'Next: admin updates the review package, then customer care sends it.',
          de: 'Als Nächstes aktualisiert der Admin das Prüfungspaket, dann sendet der Kundenservice es.',
        ),
      (false, true) when request.assessmentStatus == 'site_visit_completed' =>
        language.pick(
          en: 'Next: submit the final estimate so admin can review it.',
          de: 'Als Nächstes reichen Sie die finale Schätzung ein, damit der Admin sie prüfen kann.',
        ),
      (false, true) when hasSiteReviewBooking => language.pick(
        en: 'Next: attend the review, clock in and out on the visit day, then run the final estimate.',
        de: 'Als Nächstes nehmen Sie die Besichtigung wahr, stempeln am Einsatztag ein und aus und erstellen dann die finale Schätzung.',
      ),
      (false, true) => language.pick(
        en: 'Next: book the review. Saving from that action marks it scheduled and puts it on the calendar.',
        de: 'Als Nächstes buchen Sie die Besichtigung. Diese Aktion markiert sie als geplant und legt sie im Kalender an.',
      ),
      _ => estimationSummary,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.darkPageRaised,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              language.pick(en: 'Conversation actions', de: 'Chat-Aktionen'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              stageSummary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: isSendingUpdateRequest || customerUpdatesLocked
                      ? null
                      : onAskCustomerUpdate,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  icon: const Icon(Icons.edit_note_rounded),
                  label: Text(
                    isSendingUpdateRequest
                        ? language.pick(
                            en: 'Sending update request...',
                            de: 'Aktualisierungsanfrage wird gesendet...',
                          )
                        : customerUpdatesLocked
                        ? language.pick(
                            en: 'Customer updates locked after quoted',
                            de: 'Kundenupdates nach Angebot gesperrt',
                          )
                        : language.pick(
                            en: 'Ask client to update',
                            de: 'Kunden um Update bitten',
                          ),
                  ),
                ),
                if (hasPendingCustomerUpdateRequest)
                  OutlinedButton.icon(
                    onPressed: isSendingUpdateRequest
                        ? null
                        : onClearCustomerUpdate,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.04),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    icon: const Icon(Icons.task_alt_rounded),
                    label: Text(
                      isSendingUpdateRequest
                          ? language.pick(
                              en: 'Clearing update request...',
                              de: 'Aktualisierungsanfrage wird entfernt...',
                            )
                          : language.pick(
                              en: 'Clear update request',
                              de: 'Aktualisierung entfernen',
                            ),
                    ),
                  ),
                if (showSiteReviewFlow) ...<Widget>[
                  FilledButton.tonalIcon(
                    onPressed:
                        isSendingInvoice ||
                            isEstimationLocked ||
                            isSiteReviewBookingLocked
                        ? null
                        : onBookSiteReview,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.cobalt.withValues(alpha: 0.16),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.event_available_rounded),
                    label: Text(
                      isSendingInvoice
                          ? language.pick(
                              en: 'Saving review...',
                              de: 'Besichtigung wird gespeichert...',
                            )
                          : siteReviewActionLabel,
                    ),
                  ),
                  if (canClockRequest)
                    FilledButton.icon(
                      onPressed: isClockingRequest ? null : onClockRequest,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.cobalt,
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(
                        isClockingRequest
                            ? Icons.more_horiz_rounded
                            : hasActiveClockLog
                            ? Icons.logout_rounded
                            : Icons.login_rounded,
                      ),
                      label: Text(
                        isClockingRequest
                            ? language.pick(en: 'Saving...', de: 'Speichert...')
                            : isSiteReviewClockAction && hasActiveClockLog
                            ? language.pick(
                                en: 'Clock out review',
                                de: 'Besichtigung ausstempeln',
                              )
                            : isSiteReviewClockAction
                            ? language.pick(
                                en: 'Clock in review',
                                de: 'Zur Besichtigung einstempeln',
                              )
                            : hasActiveClockLog
                            ? language.pick(
                                en: 'Clock out work',
                                de: 'Arbeit ausstempeln',
                              )
                            : language.pick(
                                en: 'Clock in work',
                                de: 'Arbeit einstempeln',
                              ),
                      ),
                    ),
                  if (canCompleteWork)
                    FilledButton.icon(
                      onPressed: isCompletingWork ? null : onCompleteWork,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.pine,
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(
                        isCompletingWork
                            ? Icons.more_horiz_rounded
                            : Icons.task_alt_rounded,
                      ),
                      label: Text(
                        isCompletingWork
                            ? language.pick(en: 'Saving...', de: 'Speichert...')
                            : language.pick(
                                en: 'Complete work',
                                de: 'Arbeit abschließen',
                              ),
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed:
                        isSendingInvoice ||
                            isEstimationLocked ||
                            !hasSiteReviewBooking
                        ? null
                        : onRunFinalEstimate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.cobalt.withValues(alpha: 0.16),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.calculate_rounded),
                    label: Text(
                      isSendingInvoice
                          ? language.pick(
                              en: 'Saving estimate...',
                              de: 'Schätzung wird gespeichert...',
                            )
                          : finalEstimateActionLabel,
                    ),
                  ),
                ] else if (!isCustomerCareUser)
                  FilledButton.tonalIcon(
                    onPressed: isSendingInvoice || isEstimationLocked
                        ? null
                        : onEditEstimate,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.cobalt.withValues(alpha: 0.16),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.calculate_rounded),
                    label: Text(estimationActionLabel),
                  ),
                if (onOpenPaymentProof != null)
                  OutlinedButton.icon(
                    onPressed: onOpenPaymentProof,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.04),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(
                      language.pick(en: 'View proof', de: 'Nachweis ansehen'),
                    ),
                  ),
                if (onOpenReceipt != null)
                  OutlinedButton.icon(
                    onPressed: onOpenReceipt,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.04),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: Text(
                      language.pick(en: 'View receipt', de: 'Beleg ansehen'),
                    ),
                  ),
                if (onApprovePaymentProof != null)
                  FilledButton.icon(
                    onPressed: isReviewingPaymentProof
                        ? null
                        : onApprovePaymentProof,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.pine.withValues(alpha: 0.18),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.verified_rounded),
                    label: Text(
                      isReviewingPaymentProof
                          ? language.pick(en: 'Saving...', de: 'Speichert...')
                          : language.pick(
                              en: 'Approve proof',
                              de: 'Nachweis bestätigen',
                            ),
                    ),
                  ),
                if (onRejectPaymentProof != null)
                  OutlinedButton.icon(
                    onPressed: isReviewingPaymentProof
                        ? null
                        : onRejectPaymentProof,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.04),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(
                      language.pick(
                        en: 'Reject proof',
                        de: 'Nachweis ablehnen',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowMetaPill extends StatelessWidget {
  const _WorkflowMetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.86),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CompactStatusPill extends ConsumerWidget {
  const _CompactStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final colors = switch (status) {
      'submitted' => (background: AppTheme.clay, foreground: AppTheme.ink),
      'under_review' => (
        background: const Color(0xFFFFF0C9),
        foreground: AppTheme.ink,
      ),
      'assigned' => (
        background: const Color(0xFFD7E7FF),
        foreground: AppTheme.cobalt,
      ),
      'quoted' => (
        background: const Color(0xFFFFE2C8),
        foreground: AppTheme.ember,
      ),
      'appointment_confirmed' => (
        background: const Color(0xFFD8F2E8),
        foreground: AppTheme.pine,
      ),
      'pending_start' => (
        background: const Color(0xFFE9E1FF),
        foreground: const Color(0xFF5E41A8),
      ),
      'project_started' => (
        background: const Color(0xFFD9F4FF),
        foreground: const Color(0xFF15607A),
      ),
      'work_done' => (
        background: const Color(0xFFDDF7E4),
        foreground: const Color(0xFF2F7C3E),
      ),
      'closed' => (
        background: const Color(0xFFE7E7E7),
        foreground: AppTheme.ink,
      ),
      _ => (background: AppTheme.clay, foreground: AppTheme.ink),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          requestStatusLabelFor(status, language: language),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
