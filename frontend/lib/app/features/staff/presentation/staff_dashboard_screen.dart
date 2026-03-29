/// WHAT: Renders the staff workspace as a queue inbox plus active conversation area.
/// WHY: Staff should manage waiting customers and active requests from a chat-first layout instead of bulky stacked cards.
/// HOW: Show queue filters and compact workload controls on the left, then render the selected waiting or active thread on the right.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/dashboard_models.dart';
import '../../../core/models/service_request_model.dart';
import '../../../shared/data/internal_chat_repository.dart';
import '../../../shared/presentation/invoice_draft_dialog.dart';
import '../../../shared/presentation/presence_chip.dart';
import '../../../shared/presentation/request_message_composer.dart';
import '../../../shared/presentation/request_thread_section.dart';
import '../../../shared/presentation/status_chip.dart';
import '../../../shared/presentation/workspace_bottom_nav.dart';
import '../../../shared/utils/external_url_opener.dart';
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
  final Map<String, DateTime> _lastViewedActivityByRequestId =
      <String, DateTime>{};
  final Map<String, double> _conversationScrollOffsetsByRequestId =
      <String, double>{};
  final Set<String> _attendingQueueIds = <String>{};
  final Set<String> _updatingAiControlIds = <String>{};
  final Set<String> _sendingMessageIds = <String>{};
  final Set<String> _sendingInvoiceIds = <String>{};
  final Set<String> _reviewingPaymentProofIds = <String>{};
  final Set<String> _savingStatusIds = <String>{};
  _StaffInboxFilter _selectedFilter = _StaffInboxFilter.waiting;
  _StaffWorkspaceTab _selectedWorkspaceTab = _StaffWorkspaceTab.queue;
  String? _selectedRequestId;
  bool _isUpdatingAvailability = false;

  @override
  void dispose() {
    // WHY: Each active thread can own a composer controller, so all of those controllers need cleanup on screen exit.
    for (final controller in _messageControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String requestId) {
    // WHY: Keep one controller per request id so draft replies survive rebuilds while staff switch threads.
    return _messageControllers.putIfAbsent(
      requestId,
      () => TextEditingController(),
    );
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
                ? 'You are now online for the queue'
                : 'You are now offline for new queue pickups',
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
          content: Text('You are now attending ${request.contactFullName}'),
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reply sent')));
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
        const SnackBar(content: Text('Customer update request sent to chat')),
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

  Future<void> _sendInvoice(ServiceRequestModel request) async {
    final draft = await showInvoiceDraftDialog(
      context,
      initialInvoice: request.invoice,
      request: request,
    );
    if (draft == null) {
      return;
    }

    setState(() => _sendingInvoiceIds.add(request.id));

    try {
      await ref
          .read(staffRepositoryProvider)
          .sendInvoice(
            requestId: request.id,
            amount: draft.amount,
            dueDate: draft.dueDate,
            paymentMethod: draft.paymentMethod,
            paymentInstructions: draft.paymentInstructions,
            note: draft.note,
          );
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quotation sent to customer')),
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
                ? 'Payment proof approved'
                : 'Payment proof rejected',
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
        const SnackBar(content: Text('Opening proof is not supported here')),
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

  Widget? _buildStaffThreadMessageAction(
    ServiceRequestModel request,
    RequestMessageModel message,
  ) {
    final invoice = request.invoice;
    if (invoice == null || !_isLatestProofUploadMessage(request, message)) {
      return null;
    }

    final invoiceStatus = invoice.status;
    final statusConfig = switch (invoiceStatus) {
      paymentRequestStatusApproved => (
        label: 'Payment approved',
        background: const Color(0xFF1D4930),
        foreground: const Color(0xFFDDF7E4),
      ),
      paymentRequestStatusRejected => (
        label: 'Payment rejected',
        background: const Color(0xFF5A2A21),
        foreground: const Color(0xFFFFE0DA),
      ),
      _ => (
        label: 'Pending review',
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
                      ? 'Saving...'
                      : 'Approve payment',
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
                label: const Text('Reject proof'),
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
        const SnackBar(content: Text('Opening receipt is not supported here')),
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

  Future<void> _updateStatus({
    required ServiceRequestModel request,
    required String status,
  }) async {
    setState(() => _savingStatusIds.add(request.id));
    debugPrint(
      'StaffDashboardScreen._updateStatus: updating request ${request.id} to $status',
    );

    try {
      await ref
          .read(staffRepositoryProvider)
          .updateRequestStatus(requestId: request.id, status: status);
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request status updated')));
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

    return <ServiceRequestModel>[...requests]
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

    final attachmentName = latestMessage.attachment?.originalName.trim();
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
    setState(() {
      _selectedWorkspaceTab = _workspaceTabForFilterValue(_selectedFilter);
      _selectedRequestId = request.id;
      _markRequestViewed(request);
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
      return 'Yesterday';
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
      _StaffInboxFilter.waiting => 'Waiting',
      _StaffInboxFilter.active => 'Active',
      _StaffInboxFilter.quoted => 'Quoted',
      _StaffInboxFilter.confirmed => 'Confirmed',
      _StaffInboxFilter.pending => 'Pending',
      _StaffInboxFilter.closed => 'Closed',
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
      _StaffInboxFilter.waiting => 'No waiting queue threads right now.',
      _StaffInboxFilter.active => 'No active customer threads right now.',
      _StaffInboxFilter.quoted => 'No quoted requests yet.',
      _StaffInboxFilter.confirmed => 'No confirmed appointments yet.',
      _StaffInboxFilter.pending => 'No pending start jobs right now.',
      _StaffInboxFilter.closed => 'No closed threads in this view.',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0E10),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF121418), Color(0xFF0D0E10)],
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
                        'Team Queue',
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
                                ? 'Open for pickup'
                                : 'Pickup paused',
                            isOnline: isOnline,
                            dark: true,
                            compact: true,
                          ),
                          Text(
                            '${bundle.clearedTodayCount} cleared today',
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
    double collapseProgress = 0,
    bool dark = false,
  }) {
    final isWaiting = request.assignedStaff == null;
    final isAttending = _attendingQueueIds.contains(request.id);
    final isOnline = _isCurrentStaffOnline(currentAvailability);
    final isCompact = MediaQuery.sizeOf(context).width < 720;
    final compactCollapse = isCompact ? collapseProgress.clamp(0.0, 1.0) : 0.0;
    final horizontalPadding = isCompact ? 16.0 : 22.0;
    final verticalTopPadding = isCompact ? 8 - (compactCollapse * 3) : 16.0;
    final verticalBottomPadding = isCompact ? 7 - (compactCollapse * 3) : 14.0;
    final titleFontSize = isCompact ? 18 - (compactCollapse * 2) : null;
    final actionsTopSpacing = isCompact ? 6 - (compactCollapse * 2) : 8.0;
    final titleColor = dark ? Colors.white : null;
    final metaColor = dark ? Colors.white.withValues(alpha: 0.68) : null;
    final subtitleColor = dark
        ? Colors.white.withValues(alpha: 0.54)
        : metaColor;
    final backForeground = dark ? Colors.white.withValues(alpha: 0.84) : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        verticalTopPadding,
        horizontalPadding,
        verticalBottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (isCompact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    if (onBack != null)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: onBack,
                            style: TextButton.styleFrom(
                              foregroundColor: backForeground,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 0,
                              ),
                              minimumSize: const Size(0, 26),
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              size: 18,
                            ),
                            label: const Text('Queue'),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                  ],
                ),
                SizedBox(height: 8 - (compactCollapse * 2)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            request.contactFullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.w700,
                                  color: titleColor,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${request.serviceLabel} · ${request.city}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: subtitleColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildConversationHeaderStatusPill(
                      context,
                      request.status,
                      compact: true,
                      dark: dark,
                    ),
                  ],
                ),
                SizedBox(height: actionsTopSpacing + 2),
                Row(
                  children: <Widget>[
                    PresenceChip(
                      label: isOnline ? 'Online' : 'Offline',
                      isOnline: isOnline,
                      dark: dark,
                      compact: true,
                    ),
                    if (!isWaiting && request.status != 'closed') ...<Widget>[
                      const SizedBox(width: 8),
                      _buildAiControlToggle(
                        context,
                        request: request,
                        currentAvailability: currentAvailability,
                        compact: true,
                        dark: dark,
                      ),
                    ],
                    const Spacer(),
                    _buildCompactHeaderButton(
                      context,
                      onPressed: onOpenProfile,
                      icon: Icons.person_outline_rounded,
                      label: '',
                      dark: dark,
                    ),
                    const SizedBox(width: 8),
                    if (isWaiting)
                      _buildCompactHeaderButton(
                        context,
                        onPressed: isAttending
                            ? null
                            : () => _attendQueue(request),
                        icon: Icons.play_arrow_rounded,
                        label: '',
                        filled: true,
                        dark: dark,
                      )
                    else if (onOpenWorkflow != null)
                      _buildCompactHeaderButton(
                        context,
                        onPressed: onOpenWorkflow,
                        icon: Icons.tune_rounded,
                        label: '',
                        dark: dark,
                      ),
                  ],
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        request.contactFullName,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineMedium?.copyWith(color: titleColor),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${request.serviceLabel} · ${request.city}',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: metaColor),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          PresenceChip(
                            label: isOnline
                                ? 'You are online'
                                : 'You are offline',
                            isOnline: isOnline,
                            dark: dark,
                          ),
                          if (!isWaiting && request.status != 'closed')
                            _buildAiControlToggle(
                              context,
                              request: request,
                              currentAvailability: currentAvailability,
                              dark: dark,
                            ),
                          OutlinedButton.icon(
                            onPressed: onOpenProfile,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: dark
                                  ? Colors.white
                                  : AppTheme.ink,
                              backgroundColor: dark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.white,
                              side: BorderSide(
                                color: dark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : AppTheme.clay.withValues(alpha: 0.82),
                              ),
                            ),
                            icon: const Icon(Icons.person_outline_rounded),
                            label: const Text('Profile'),
                          ),
                          if (isWaiting)
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.cobalt,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: isAttending
                                  ? null
                                  : () => _attendQueue(request),
                              child: Text(
                                isAttending ? 'Attending...' : 'Attend',
                              ),
                            )
                          else if (onOpenWorkflow != null)
                            FilledButton.tonalIcon(
                              onPressed: onOpenWorkflow,
                              style: FilledButton.styleFrom(
                                backgroundColor: dark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : null,
                                foregroundColor: dark
                                    ? Colors.white
                                    : AppTheme.ink,
                              ),
                              icon: const Icon(Icons.tune_rounded),
                              label: const Text('Workflow'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                _buildConversationHeaderStatusPill(
                  context,
                  request.status,
                  dark: dark,
                ),
              ],
            ),
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
          requestStatusLabelFor(status),
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
          ? 'Naima stays active while you are offline'
          : isActive
          ? 'Naima is covering this chat'
          : 'Turn Naima on to cover this chat',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: isUpdating ? 0.72 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(compact ? 18 : 14),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 10,
              vertical: compact ? 2 : 5,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.auto_awesome_rounded,
                  size: compact ? 14 : 16,
                  color: iconColor,
                ),
                if (!compact) ...<Widget>[
                  const SizedBox(width: 6),
                  Text(
                    'Naima',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                SizedBox(
                  width: compact ? 30 : 36,
                  child: Transform.scale(
                    scale: compact ? 0.66 : 0.82,
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
                      activeThumbColor: dark && compact
                          ? Colors.white
                          : AppTheme.cobalt,
                      activeTrackColor: dark && compact
                          ? AppTheme.cobalt.withValues(alpha: 0.88)
                          : AppTheme.cobalt.withValues(alpha: 0.42),
                      inactiveThumbColor: dark
                          ? Colors.white.withValues(alpha: 0.88)
                          : AppTheme.ink,
                      inactiveTrackColor: dark && compact
                          ? Colors.white.withValues(alpha: 0.16)
                          : dark
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
        ? AppTheme.cobalt.withValues(alpha: 0.14)
        : Colors.white;
    final borderColor = dark
        ? AppTheme.cobalt.withValues(alpha: filled ? 0 : 0.24)
        : AppTheme.clay.withValues(alpha: 0.82);

    return SizedBox(
      height: 34,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
          side: filled ? null : BorderSide(color: borderColor),
          minimumSize: Size(label.isEmpty ? 34 : 0, 34),
          padding: EdgeInsets.symmetric(
            horizontal: label.isEmpty ? 8 : 10,
            vertical: 0,
          ),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        icon: Icon(icon, size: 16),
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
                      '${request.contactFullName} profile',
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
                      request,
                      composerEnabled: composerEnabled,
                    ),
                    if (composerEnabled) ...<Widget>[
                      const SizedBox(height: 16),
                      _StaffChatActionTray(
                        request: request,
                        isSendingUpdateRequest: _sendingMessageIds.contains(
                          request.id,
                        ),
                        isSendingInvoice: _sendingInvoiceIds.contains(
                          request.id,
                        ),
                        isReviewingPaymentProof: _reviewingPaymentProofIds
                            .contains(request.id),
                        onAskCustomerUpdate: () {
                          Navigator.of(modalContext).pop();
                          _sendCustomerUpdateRequest(request);
                        },
                        onSendInvoice: () {
                          Navigator.of(modalContext).pop();
                          _sendInvoice(request);
                        },
                        onOpenPaymentProof:
                            request.invoice?.proof?.fileUrl == null
                            ? null
                            : () {
                                Navigator.of(modalContext).pop();
                                _openPaymentProof(request);
                              },
                        onOpenReceipt: request.invoice?.receiptUrl == null
                            ? null
                            : () {
                                Navigator.of(modalContext).pop();
                                _openReceipt(request);
                              },
                        onApprovePaymentProof:
                            request.invoice?.isProofSubmitted == true
                            ? () {
                                Navigator.of(modalContext).pop();
                                _reviewPaymentProof(
                                  request,
                                  decision: 'approved',
                                );
                              }
                            : null,
                        onRejectPaymentProof:
                            request.invoice?.isProofSubmitted == true
                            ? () {
                                Navigator.of(modalContext).pop();
                                _reviewPaymentProof(
                                  request,
                                  decision: 'rejected',
                                );
                              }
                            : null,
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
                        'Workflow',
                        style: Theme.of(modalContext).textTheme.titleLarge
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Update the job status without covering the chat.',
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
                              ? 'Select next status'
                              : 'Choose workflow status',
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(
                            value: 'under_review',
                            child: Text('Under review'),
                          ),
                          DropdownMenuItem(
                            value: 'quoted',
                            child: Text('Quoted'),
                          ),
                          DropdownMenuItem(
                            value: 'appointment_confirmed',
                            child: Text('Appointment confirmed'),
                          ),
                          DropdownMenuItem(
                            value: 'pending_start',
                            child: Text('Pending start'),
                          ),
                          DropdownMenuItem(
                            value: 'project_started',
                            child: Text('Project started'),
                          ),
                          DropdownMenuItem(
                            value: 'work_done',
                            child: Text('Work done'),
                          ),
                          DropdownMenuItem(
                            value: 'closed',
                            child: Text('Closed'),
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
                                  await _updateStatus(
                                    request: request,
                                    status: localSelectedStatus!,
                                  );
                                  if (modalContext.mounted) {
                                    Navigator.of(modalContext).pop();
                                  }
                                }
                              : null,
                          child: Text(isSavingStatus ? 'Saving...' : 'Save'),
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
                        'Customer request brief',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reference details for this chat. Download it or review the latest request context.',
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
                  label: 'Customer',
                  value: request.contactFullName.isEmpty
                      ? 'Not provided'
                      : request.contactFullName,
                ),
                _RequestBriefItem(
                  icon: Icons.mail_outline_rounded,
                  label: 'Email',
                  value: request.contactEmail.isEmpty
                      ? 'Not provided'
                      : request.contactEmail,
                ),
                _RequestBriefItem(
                  icon: Icons.call_outlined,
                  label: 'Phone',
                  value: request.contactPhone.isEmpty
                      ? 'Not provided'
                      : request.contactPhone,
                ),
                _RequestBriefItem(
                  icon: Icons.place_outlined,
                  label: 'Address',
                  value: _requestAddress(request),
                ),
                _RequestBriefItem(
                  icon: Icons.event_outlined,
                  label: 'Preferred date',
                  value: _formatRequestDate(request.preferredDate),
                ),
                _RequestBriefItem(
                  icon: Icons.schedule_rounded,
                  label: 'Time window',
                  value: request.preferredTimeWindow.isEmpty
                      ? 'Not provided'
                      : request.preferredTimeWindow,
                ),
                _RequestBriefItem(
                  icon: Icons.play_circle_outline_rounded,
                  label: 'Project started',
                  value: _formatRequestDateTime(request.projectStartedAt),
                ),
                _RequestBriefItem(
                  icon: Icons.task_alt_rounded,
                  label: 'Work finished',
                  value: _formatRequestDateTime(request.finishedAt),
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
                      'Original request',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      request.message.trim().isEmpty
                          ? 'No customer request note was provided.'
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
                  label: const Text('Download brief'),
                ),
              ],
            ),
            if (!composerEnabled) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'Attend the queue item first before sending an update request to the client.',
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
          color: const Color(0xFF0D0E10),
          borderRadius: surfaceRadius,
          border: edgeToEdge
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Center(
          child: Text(
            'Pick a queue thread to continue.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
        ),
      );
    }

    final controller = _controllerFor(request.id);
    final isSending = _sendingMessageIds.contains(request.id);
    final composerEnabled =
        request.assignedStaff != null && request.status != 'closed';
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
        color: const Color(0xFF0D0E10),
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
            onOpenWorkflow:
                request.assignedStaff != null && request.status != 'closed'
                ? () => _showWorkflowSheet(context, request)
                : null,
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
                    const Color(0xFF111214),
                    AppTheme.pine.withValues(alpha: 0.08),
                    const Color(0xFF0D0E10),
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
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                        child: RequestThreadSection(
                          messages: request.messages,
                          viewerRole: 'staff',
                          dark: true,
                          emptyLabel: 'No thread messages yet.',
                          messageActionBuilder: (RequestMessageModel message) =>
                              _buildStaffThreadMessageAction(request, message),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    child: RequestMessageComposer(
                      controller: controller,
                      hintText: composerEnabled
                          ? aiCoverActive
                                ? 'Reply here to take the chat back from Naima'
                                : 'Reply to the customer here'
                          : 'Attend the queue before replying',
                      buttonLabel: aiCoverActive
                          ? 'Send and resume'
                          : 'Send reply',
                      isSubmitting: isSending,
                      dark: true,
                      isEnabled: composerEnabled,
                      onSubmit: () => _sendMessage(request),
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
        label: 'Queue',
        icon: Icons.inbox_rounded,
        badgeText: '${bundle.waitingQueueCount}',
      ),
      WorkspaceBottomNavItem(
        label: 'Active',
        icon: Icons.support_agent_rounded,
        badgeText: '${bundle.assignedCount}',
      ),
      WorkspaceBottomNavItem(
        label: 'Pipeline',
        icon: Icons.rule_folder_rounded,
        badgeText: '$pipelineCount',
      ),
      WorkspaceBottomNavItem(
        label: 'Closed',
        icon: Icons.done_all_rounded,
        badgeText: '${_filterCount(bundle, _StaffInboxFilter.closed)}',
      ),
      WorkspaceBottomNavItem(
        label: 'Chats',
        icon: Icons.forum_rounded,
        badgeText: '$internalChatUnreadCount',
        badgeBackgroundColor: const Color(0xFFE04F5F),
        badgeForegroundColor: Colors.white,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bundleAsync = ref.watch(staffDashboardProvider);
    final authState = ref.watch(authControllerProvider);
    final internalChatUnreadAsync = ref.watch(
      internalChatUnreadCountProvider('staff'),
    );
    final width = MediaQuery.sizeOf(context).width;
    final pagePadding = width < 600 ? 12.0 : 20.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E10),
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(
                text: 'Staff Queue',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.96),
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: ' · ',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: authState.user?.fullName ?? 'Staff',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                context.go('/');
              }
            },
            icon: const Icon(Icons.logout_rounded),
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
            color: const Color(0xFF0D0E10),
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

class _StaffChatActionTray extends StatelessWidget {
  const _StaffChatActionTray({
    required this.request,
    required this.isSendingUpdateRequest,
    required this.isSendingInvoice,
    required this.isReviewingPaymentProof,
    required this.onAskCustomerUpdate,
    required this.onSendInvoice,
    required this.onOpenPaymentProof,
    required this.onOpenReceipt,
    required this.onApprovePaymentProof,
    required this.onRejectPaymentProof,
  });

  final ServiceRequestModel request;
  final bool isSendingUpdateRequest;
  final bool isSendingInvoice;
  final bool isReviewingPaymentProof;
  final VoidCallback onAskCustomerUpdate;
  final VoidCallback onSendInvoice;
  final VoidCallback? onOpenPaymentProof;
  final VoidCallback? onOpenReceipt;
  final VoidCallback? onApprovePaymentProof;
  final VoidCallback? onRejectPaymentProof;

  @override
  Widget build(BuildContext context) {
    final invoice = request.invoice;
    final statusLabel = invoice == null
        ? ''
        : requestStatusLabelFor(invoice.status);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF121418),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Conversation actions',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              invoice == null
                  ? 'Keep the request moving without leaving the chat.'
                  : 'Quotation ${invoice.invoiceNumber} is ${statusLabel.toLowerCase()}.',
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
                  onPressed: isSendingUpdateRequest
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
                        ? 'Sending update request...'
                        : 'Ask client to update',
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: isSendingInvoice ? null : onSendInvoice,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.cobalt.withValues(alpha: 0.16),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: Text(
                    isSendingInvoice
                        ? 'Sending quotation...'
                        : 'Send quotation',
                  ),
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
                    label: const Text('View proof'),
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
                    label: const Text('View receipt'),
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
                      isReviewingPaymentProof ? 'Saving...' : 'Approve proof',
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
                    label: const Text('Reject proof'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactStatusPill extends StatelessWidget {
  const _CompactStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
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
          requestStatusLabelFor(status),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
