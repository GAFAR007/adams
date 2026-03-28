/// WHAT: Renders the customer request area as a compact inbox plus active conversation workspace.
/// WHY: Customers should understand their queue state quickly, then focus on one live thread at a time.
/// HOW: Show request filters and a request list on the left, then render the selected request thread on the right.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/service_request_model.dart';
import '../../../shared/presentation/presence_chip.dart';
import '../../../shared/presentation/request_message_composer.dart';
import '../../../shared/presentation/request_thread_section.dart';
import '../../../shared/presentation/workspace_bottom_nav.dart';
import '../../../shared/utils/payment_proof_picker.dart';
import '../../../shared/utils/request_attachment_picker.dart';
import '../../../theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../data/customer_repository.dart';

final customerRequestsProvider = FutureProvider<List<ServiceRequestModel>>((
  Ref ref,
) async {
  debugPrint('customerRequestsProvider: fetching customer requests');
  return ref.watch(customerRepositoryProvider).fetchRequests();
});

enum _CustomerInboxFilter { all, waiting, withStaff, closed }

enum _CustomerWorkspaceTab { inbox, chat }

class CustomerRequestsScreen extends ConsumerStatefulWidget {
  const CustomerRequestsScreen({super.key});

  @override
  ConsumerState<CustomerRequestsScreen> createState() =>
      _CustomerRequestsScreenState();
}

class _CustomerRequestsScreenState
    extends ConsumerState<CustomerRequestsScreen> {
  final Map<String, TextEditingController> _messageControllers =
      <String, TextEditingController>{};
  final Map<String, DateTime> _lastViewedActivityByRequestId =
      <String, DateTime>{};
  final Set<String> _submittingMessageIds = <String>{};
  final Set<String> _uploadingAttachmentIds = <String>{};
  final Set<String> _uploadingPaymentProofIds = <String>{};
  _CustomerInboxFilter _selectedFilter = _CustomerInboxFilter.all;
  _CustomerWorkspaceTab _selectedWorkspaceTab = _CustomerWorkspaceTab.inbox;
  String? _selectedRequestId;

  @override
  void dispose() {
    // WHY: Each visible request can own a composer controller, so they all need explicit cleanup when the screen leaves.
    for (final controller in _messageControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String requestId) {
    // WHY: Request threads rebuild often, so keep one stable controller per request id instead of recreating on every frame.
    return _messageControllers.putIfAbsent(
      requestId,
      () => TextEditingController(),
    );
  }

  Future<void> _sendMessage(ServiceRequestModel request) async {
    final controller = _controllerFor(request.id);
    final text = controller.text.trim();

    // WHY: Ignore empty queue replies so customers cannot accidentally post blank thread messages.
    if (text.isEmpty) {
      return;
    }

    setState(() => _submittingMessageIds.add(request.id));
    debugPrint(
      'CustomerRequestsScreen._sendMessage: sending message for ${request.id}',
    );

    try {
      await ref
          .read(customerRepositoryProvider)
          .sendMessage(requestId: request.id, message: text);
      controller.clear();
      ref.invalidate(customerRequestsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            request.assignedStaff == null
                ? 'Update added to the queue'
                : 'Message sent to ${request.assignedStaff!.fullName}',
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
        setState(() => _submittingMessageIds.remove(request.id));
      }
    }
  }

  List<ServiceRequestModel> _filterRequests(
    List<ServiceRequestModel> requests,
  ) {
    return requests.where((request) {
      switch (_selectedFilter) {
        case _CustomerInboxFilter.all:
          return true;
        case _CustomerInboxFilter.waiting:
          return request.assignedStaff == null && request.status != 'closed';
        case _CustomerInboxFilter.withStaff:
          return request.assignedStaff != null && request.status != 'closed';
        case _CustomerInboxFilter.closed:
          return request.status == 'closed';
      }
    }).toList()..sort(compareServiceRequestsByLatestActivity);
  }

  ServiceRequestModel? _resolveSelectedRequest(
    List<ServiceRequestModel> filteredRequests, {
    required bool preferFirst,
  }) {
    if (filteredRequests.isEmpty) {
      return null;
    }

    for (final request in filteredRequests) {
      if (request.id == _selectedRequestId) {
        return request;
      }
    }

    // WHY: When a selected request disappears after filtering or refresh, fall back to the first available thread instead of a blank screen.
    return preferFirst ? filteredRequests.first : null;
  }

  String _queueSummary(ServiceRequestModel request) {
    if (request.status == 'closed') {
      return 'This request is closed. The conversation stays here for reference.';
    }

    if (request.assignedStaff != null) {
      final availability = request.assignedStaff!.staffAvailability == 'online'
          ? 'online'
          : 'offline';
      return 'Assigned to ${request.assignedStaff!.fullName}. Staff is currently $availability.';
    }

    return 'Waiting in the live queue. AI is keeping the conversation warm until staff joins.';
  }

  String _messagePreview(ServiceRequestModel request) {
    final latestMessage = request.latestMessage;
    if (latestMessage == null) {
      return request.message;
    }

    final senderPrefix = latestMessage.isCustomer
        ? 'You'
        : latestMessage.senderName.isNotEmpty
        ? latestMessage.senderName
        : latestMessage.isAi
        ? 'AI'
        : latestMessage.isSystem
        ? 'System'
        : 'Staff';

    final attachmentName = latestMessage.attachment?.originalName.trim();
    if (attachmentName != null && attachmentName.isNotEmpty) {
      return '$senderPrefix sent $attachmentName';
    }

    return '$senderPrefix: ${latestMessage.text}';
  }

  bool _hasUnreadIncomingAlert(ServiceRequestModel request) {
    final latestMessage = request.latestMessage;
    final latestActivity = request.latestActivityAt;

    if (latestMessage == null ||
        latestActivity == null ||
        latestMessage.isCustomer) {
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
      _selectedRequestId = request.id;
      _selectedWorkspaceTab = _CustomerWorkspaceTab.chat;
      _markRequestViewed(request);
    });
  }

  Future<void> _uploadPaymentProof(ServiceRequestModel request) async {
    final invoice = request.invoice;
    if (invoice == null || !invoice.canCustomerUploadProof) {
      return;
    }

    final pickedFile = await pickPaymentProofFile();
    if (pickedFile == null) {
      return;
    }

    setState(() => _uploadingPaymentProofIds.add(request.id));

    try {
      await ref
          .read(customerRepositoryProvider)
          .uploadPaymentProof(
            requestId: request.id,
            bytes: pickedFile.bytes,
            fileName: pickedFile.name,
            mimeType: pickedFile.mimeType,
          );
      ref.invalidate(customerRequestsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment proof uploaded')));
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
        setState(() => _uploadingPaymentProofIds.remove(request.id));
      }
    }
  }

  Future<void> _uploadRequestAttachment(ServiceRequestModel request) async {
    if (request.status == 'closed') {
      return;
    }

    final pickedFile = await pickRequestAttachmentFile();
    if (pickedFile == null) {
      return;
    }

    final controller = _controllerFor(request.id);
    final caption = controller.text.trim();

    setState(() => _uploadingAttachmentIds.add(request.id));

    try {
      await ref
          .read(customerRepositoryProvider)
          .uploadRequestAttachment(
            requestId: request.id,
            bytes: pickedFile.bytes,
            fileName: pickedFile.name,
            mimeType: pickedFile.mimeType,
            caption: caption.isEmpty ? null : caption,
          );
      controller.clear();
      ref.invalidate(customerRequestsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            request.assignedStaff == null
                ? 'File added to the queue'
                : 'File sent to ${request.assignedStaff?.fullName ?? 'staff'}',
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
        setState(() => _uploadingAttachmentIds.remove(request.id));
      }
    }
  }

  String _latestAlertLabel(ServiceRequestModel request) {
    if (!_hasUnreadIncomingAlert(request)) {
      return '';
    }

    final latestMessage = request.latestMessage;
    if (latestMessage == null) {
      return '';
    }

    if (latestMessage.isStaff) {
      return 'Staff replied';
    }

    if (latestMessage.isAdmin) {
      return 'Admin replied';
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

  bool _assignedStaffIsOnline(ServiceRequestModel request) =>
      request.assignedStaff?.staffAvailability == 'online';

  String _assignedStaffPresenceLabel(ServiceRequestModel request) {
    final assignedStaff = request.assignedStaff;
    if (assignedStaff == null) {
      return '';
    }

    return _assignedStaffIsOnline(request)
        ? '${assignedStaff.fullName} online'
        : '${assignedStaff.fullName} offline';
  }

  RequestMessageModel? _latestCustomerUpdateRequestAction(
    ServiceRequestModel request,
  ) {
    for (final message in request.messages.reversed) {
      if (message.isCustomerUpdateRequest) {
        return message;
      }
    }

    return null;
  }

  bool _hasPendingCustomerUpdateRequest(ServiceRequestModel request) {
    final message = _latestCustomerUpdateRequestAction(request);
    if (message == null || request.status == 'closed') {
      return false;
    }

    final actionCreatedAt = message.createdAt;
    final detailsUpdatedAt = request.detailsUpdatedAt;

    if (actionCreatedAt == null) {
      return true;
    }

    if (detailsUpdatedAt == null) {
      return true;
    }

    return actionCreatedAt.isAfter(detailsUpdatedAt);
  }

  bool _hasPendingPaymentProofUpload(ServiceRequestModel request) {
    final invoice = request.invoice;
    if (invoice == null || request.status == 'closed') {
      return false;
    }

    return invoice.canCustomerUploadProof;
  }

  String _formatActionDate(DateTime? value) {
    if (value == null) {
      return 'Not set';
    }

    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  String _formatActionDateTime(DateTime? value) {
    if (value == null) {
      return 'Not set';
    }

    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Future<void> _showRequestDetailsSheet(ServiceRequestModel request) {
    final accent = _serviceAccent(request.serviceType);

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF111316),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Request details',
                            style: Theme.of(modalContext).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(modalContext).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request.serviceLabel,
                      style: Theme.of(modalContext).textTheme.bodyMedium
                          ?.copyWith(
                            color: Colors.white.withValues(alpha: 0.64),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (request.assignedStaff != null) ...<Widget>[
                      PresenceChip(
                        label: _assignedStaffPresenceLabel(request),
                        isOnline: _assignedStaffIsOnline(request),
                        dark: true,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _ConversationMetaPill(
                      icon: Icons.location_on_rounded,
                      label:
                          '${request.addressLine1}, ${request.city} ${request.postalCode}',
                      accentColor: accent,
                      dark: true,
                    ),
                    const SizedBox(height: 10),
                    _ConversationMetaPill(
                      icon: Icons.schedule_rounded,
                      label: request.preferredTimeWindow.isEmpty
                          ? 'Flexible time window'
                          : request.preferredTimeWindow,
                      accentColor: accent,
                      dark: true,
                    ),
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF15181D),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _queueSummary(request),
                          style: Theme.of(modalContext).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.82),
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                        ),
                      ),
                    ),
                    if (request.projectStartedAt != null ||
                        request.finishedAt != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          if (request.projectStartedAt != null)
                            _ConversationTimelinePill(
                              icon: Icons.play_circle_outline_rounded,
                              label:
                                  'Started ${_formatActionDateTime(request.projectStartedAt)}',
                            ),
                          if (request.finishedAt != null)
                            _ConversationTimelinePill(
                              icon: Icons.task_alt_rounded,
                              label:
                                  'Finished ${_formatActionDateTime(request.finishedAt)}',
                            ),
                        ],
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

  List<WorkspaceBottomNavItem> _buildMobileNavItems(
    List<ServiceRequestModel> filteredRequests,
  ) {
    return <WorkspaceBottomNavItem>[
      WorkspaceBottomNavItem(
        label: 'Inbox',
        icon: Icons.chat_bubble_outline_rounded,
        badgeText: '${filteredRequests.length}',
      ),
      const WorkspaceBottomNavItem(label: 'Chat', icon: Icons.forum_rounded),
    ];
  }

  IconData _serviceIcon(String serviceType) {
    return switch (serviceType) {
      'building_cleaning' => Icons.apartment_rounded,
      'warehouse_hall_cleaning' => Icons.warehouse_rounded,
      'window_glass_cleaning' => Icons.window_rounded,
      'winter_service' => Icons.ac_unit_rounded,
      'caretaker_service' => Icons.handyman_rounded,
      'garden_care' => Icons.park_rounded,
      'post_construction_cleaning' => Icons.construction_rounded,
      _ => Icons.forum_rounded,
    };
  }

  Color _serviceAccent(String serviceType) {
    return switch (serviceType) {
      'building_cleaning' => AppTheme.cobalt,
      'warehouse_hall_cleaning' => AppTheme.ember,
      'window_glass_cleaning' => const Color(0xFF4A7FB9),
      'winter_service' => const Color(0xFF5A86C6),
      'caretaker_service' => AppTheme.pine,
      'garden_care' => const Color(0xFF4B8A63),
      'post_construction_cleaning' => const Color(0xFF8B6A4E),
      _ => AppTheme.cobalt,
    };
  }

  Widget _buildInboxFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required int count,
  }) {
    final foregroundColor = isSelected
        ? Colors.white
        : Colors.white.withValues(alpha: 0.82);
    final badgeColor = isSelected
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.08);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
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
          boxShadow: isSelected
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppTheme.cobalt.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(width: 8, height: 8),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: Text(
                    '$count',
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

  Widget _buildRequestListTile(
    BuildContext context,
    ServiceRequestModel request,
    bool isSelected,
  ) {
    final accent = _serviceAccent(request.serviceType);
    final preview = _messagePreview(request);
    final latestAlertLabel = _latestAlertLabel(request);
    final latestTimestamp = _formatInboxTimestamp(request.latestActivityAt);
    final backgroundColor = isSelected
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.18),
            const Color(0xFF16191E),
          )
        : const Color(0xFF15171A);

    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: () => _openRequest(request),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isSelected
                ? accent.withValues(alpha: 0.34)
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _RequestAvatar(
                icon: _serviceIcon(request.serviceType),
                accentColor: accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            request.serviceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        if (latestTimestamp.isNotEmpty) ...<Widget>[
                          Text(
                            latestTimestamp,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: latestAlertLabel.isNotEmpty
                                      ? accent
                                      : Colors.white.withValues(alpha: 0.42),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        const SizedBox(width: 10),
                        _CompactStatusPill(status: request.status),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${request.city} · ${request.messageCount} messages',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: accent.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        height: 1.28,
                      ),
                    ),
                    if (request.assignedStaff != null ||
                        latestAlertLabel.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          if (request.assignedStaff != null)
                            PresenceChip(
                              label: _assignedStaffIsOnline(request)
                                  ? 'Staff online'
                                  : 'Staff offline',
                              isOnline: _assignedStaffIsOnline(request),
                              dark: true,
                              compact: true,
                            ),
                          if (latestAlertLabel.isNotEmpty)
                            _InboxAlertPill(
                              label: latestAlertLabel,
                              accentColor: accent,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    List<ServiceRequestModel> requests,
    List<ServiceRequestModel> filteredRequests,
    ServiceRequestModel? selectedRequest, {
    bool edgeToEdge = false,
  }) {
    const chatTopColor = Color(0xFF121418);
    const chatBottomColor = Color(0xFF0D0E10);
    final BorderRadius? surfaceRadius = edgeToEdge
        ? null
        : BorderRadius.circular(34);
    final waitingCount = requests
        .where(
          (request) =>
              request.assignedStaff == null && request.status != 'closed',
        )
        .length;
    final withStaffCount = requests
        .where(
          (request) =>
              request.assignedStaff != null && request.status != 'closed',
        )
        .length;
    final closedCount = requests
        .where((request) => request.status == 'closed')
        .length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: chatBottomColor,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[chatTopColor, chatBottomColor],
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
          edgeToEdge ? 8 : 14,
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
                        'My Requests',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Chat-style inbox for your active jobs and updates.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.cobalt,
                    shape: BoxShape.circle,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppTheme.cobalt.withValues(alpha: 0.24),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: IconButton(
                    tooltip: 'Create new request',
                    onPressed: () => context.go('/app/requests/new'),
                    icon: const Icon(Icons.add_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _MiniCountPill(label: 'All', value: '${requests.length}'),
                _MiniCountPill(label: 'Waiting', value: '$waitingCount'),
                _MiniCountPill(label: 'Live', value: '$withStaffCount'),
                _MiniCountPill(label: 'Closed', value: '$closedCount'),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _buildInboxFilterChip(
                    label: 'All',
                    isSelected: _selectedFilter == _CustomerInboxFilter.all,
                    onTap: () => setState(
                      () => _selectedFilter = _CustomerInboxFilter.all,
                    ),
                    count: requests.length,
                  ),
                  const SizedBox(width: 8),
                  _buildInboxFilterChip(
                    label: 'Waiting',
                    isSelected: _selectedFilter == _CustomerInboxFilter.waiting,
                    onTap: () => setState(
                      () => _selectedFilter = _CustomerInboxFilter.waiting,
                    ),
                    count: waitingCount,
                  ),
                  const SizedBox(width: 8),
                  _buildInboxFilterChip(
                    label: 'With Staff',
                    isSelected:
                        _selectedFilter == _CustomerInboxFilter.withStaff,
                    onTap: () => setState(
                      () => _selectedFilter = _CustomerInboxFilter.withStaff,
                    ),
                    count: withStaffCount,
                  ),
                  const SizedBox(width: 8),
                  _buildInboxFilterChip(
                    label: 'Closed',
                    isSelected: _selectedFilter == _CustomerInboxFilter.closed,
                    onTap: () => setState(
                      () => _selectedFilter = _CustomerInboxFilter.closed,
                    ),
                    count: closedCount,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filteredRequests.isEmpty
                  ? _InboxEmptyState(
                      label: 'No requests in this filter yet.',
                      onCreateRequest: () => context.go('/app/requests/new'),
                      dark: true,
                    )
                  : ListView.separated(
                      itemCount: filteredRequests.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (BuildContext context, int index) {
                        final request = filteredRequests[index];
                        return _buildRequestListTile(
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

  Widget _buildConversationPane(
    BuildContext context,
    ServiceRequestModel? request, {
    VoidCallback? onBack,
    bool edgeToEdge = false,
  }) {
    final BorderRadius? surfaceRadius = edgeToEdge
        ? null
        : BorderRadius.circular(34);
    const chatTopColor = Color(0xFF121418);
    const chatBottomColor = Color(0xFF0D0E10);

    if (request == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: chatBottomColor,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[chatTopColor, chatBottomColor],
          ),
          borderRadius: surfaceRadius,
          border: edgeToEdge
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: _InboxEmptyState(
              label:
                  'Pick a request to open the chat, or create a new one to start a conversation.',
              onCreateRequest: () => context.go('/app/requests/new'),
              dark: true,
            ),
          ),
        ),
      );
    }

    final controller = _controllerFor(request.id);
    final isSubmitting = _submittingMessageIds.contains(request.id);
    final accent = _serviceAccent(request.serviceType);
    final isCompact = MediaQuery.sizeOf(context).width < 760;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: chatBottomColor,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[chatTopColor, chatBottomColor],
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
                  blurRadius: 22,
                  offset: const Offset(0, 14),
                ),
              ],
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(14, isCompact ? 10 : 12, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (onBack != null) ...<Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onBack,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      label: const Text('Back'),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                InkWell(
                  onTap: () => _showRequestDetailsSheet(request),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _RequestAvatar(
                          icon: _serviceIcon(request.serviceType),
                          accentColor: accent,
                          size: isCompact ? 38 : 42,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                request.serviceLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      height: 1.08,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                request.assignedStaff == null
                                    ? 'Queue conversation'
                                    : 'Chat with ${request.assignedStaff!.fullName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.62,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  if (request.assignedStaff != null)
                                    PresenceChip(
                                      label: _assignedStaffIsOnline(request)
                                          ? 'Online'
                                          : 'Offline',
                                      isOnline: _assignedStaffIsOnline(request),
                                      dark: true,
                                      compact: true,
                                    ),
                                  _ConversationHeaderActionChip(
                                    icon: Icons.badge_outlined,
                                    label: 'Request info',
                                    onPressed: () =>
                                        _showRequestDetailsSheet(request),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _CompactStatusPill(status: request.status),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (BuildContext context) {
                final conversationBody = DecoratedBox(
                  decoration: BoxDecoration(
                    color: chatBottomColor,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        chatTopColor,
                        AppTheme.cobalt.withValues(alpha: 0.08),
                        chatBottomColor,
                      ],
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            edgeToEdge ? 14 : 18,
                            edgeToEdge ? 12 : 18,
                            edgeToEdge ? 14 : 18,
                            16,
                          ),
                          child: RequestThreadSection(
                            messages: request.messages,
                            viewerRole: 'customer',
                            dark: true,
                            emptyLabel:
                                'No queue messages yet. New updates will appear here.',
                          ),
                        ),
                      ),
                      if (request.status == 'closed')
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                          child: _ConversationMetaPill(
                            icon: Icons.lock_outline_rounded,
                            label:
                                'This request is closed. You can still read the full thread.',
                            accentColor: AppTheme.ink,
                            dark: true,
                          ),
                        ),
                      if (_hasPendingCustomerUpdateRequest(request))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: _CustomerConversationActionCard(
                            icon: Icons.edit_note_rounded,
                            title: 'Request details need an update',
                            body:
                                'Staff asked you to revise the address, preferred date or time, or work scope.',
                            actionLabel: 'Update request',
                            accentColor: accent,
                            dark: true,
                            onPressed: () =>
                                context.go('/app/requests/${request.id}/edit'),
                          ),
                        ),
                      if (request.invoice != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: _CustomerPaymentCard(
                            invoice: request.invoice!,
                            dueDateLabel: _formatActionDate(
                              request.invoice!.dueDate,
                            ),
                            dark: true,
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          edgeToEdge ? 10 : 14,
                          0,
                          edgeToEdge ? 10 : 14,
                          edgeToEdge ? 10 : 14,
                        ),
                        child: RequestMessageComposer(
                          controller: controller,
                          leadingActions: <Widget>[
                            _ComposerQuickActionButton(
                              tooltip: 'Upload file',
                              dark: true,
                              icon: _uploadingAttachmentIds.contains(request.id)
                                  ? Icons.more_horiz_rounded
                                  : Icons.attach_file_rounded,
                              onPressed:
                                  request.status == 'closed' ||
                                      _uploadingAttachmentIds.contains(
                                        request.id,
                                      )
                                  ? null
                                  : () => _uploadRequestAttachment(request),
                            ),
                            if (_hasPendingPaymentProofUpload(request))
                              _ComposerQuickActionButton(
                                tooltip: 'Upload payment proof',
                                dark: true,
                                icon:
                                    _uploadingPaymentProofIds.contains(
                                      request.id,
                                    )
                                    ? Icons.more_horiz_rounded
                                    : Icons.receipt_long_rounded,
                                accentColor: AppTheme.ember,
                                onPressed:
                                    _uploadingPaymentProofIds.contains(
                                      request.id,
                                    )
                                    ? null
                                    : () => _uploadPaymentProof(request),
                              ),
                          ],
                          hintText: request.assignedStaff == null
                              ? 'Message the queue while you wait'
                              : 'Reply to ${request.assignedStaff!.fullName}',
                          buttonLabel: request.assignedStaff == null
                              ? 'Send queue update'
                              : 'Reply to staff',
                          isSubmitting: isSubmitting,
                          dark: true,
                          isEnabled: request.status != 'closed',
                          onSubmit: () => _sendMessage(request),
                        ),
                      ),
                    ],
                  ),
                );

                if (edgeToEdge) {
                  return conversationBody;
                }

                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(34),
                  ),
                  child: conversationBody,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final requestsAsync = ref.watch(customerRequestsProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final canShowBottomNav = screenWidth < 980;

    return Scaffold(
      appBar: AppBar(
        title: Text('My Requests · ${authState.user?.firstName ?? 'Customer'}'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Create request',
            onPressed: () => context.go('/app/requests/new'),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
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
      body: requestsAsync.when(
        data: (List<ServiceRequestModel> requests) {
          final filteredRequests = _filterRequests(requests);

          return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final isWide = constraints.maxWidth >= 980;
              final showMobileChat =
                  !isWide &&
                  _selectedWorkspaceTab == _CustomerWorkspaceTab.chat;
              final selectedRequest = _resolveSelectedRequest(
                filteredRequests,
                preferFirst: isWide || showMobileChat,
              );
              final isConversationVisible = isWide || showMobileChat;

              if (isConversationVisible) {
                _scheduleMarkRequestViewed(selectedRequest);
              }

              if (requests.isEmpty) {
                return Padding(
                  padding: EdgeInsets.all(isWide ? 20 : 0),
                  child: _buildConversationPane(
                    context,
                    null,
                    edgeToEdge: !isWide,
                  ),
                );
              }

              if (isWide) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: 340,
                        child: _buildSidebar(
                          context,
                          requests,
                          filteredRequests,
                          selectedRequest,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildConversationPane(context, selectedRequest),
                      ),
                    ],
                  ),
                );
              }

              if (showMobileChat) {
                return _buildConversationPane(
                  context,
                  selectedRequest,
                  edgeToEdge: true,
                );
              }

              return _buildSidebar(
                context,
                requests,
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Center(child: Text(error.toString())),
        ),
      ),
      bottomNavigationBar: requestsAsync.maybeWhen(
        data: (List<ServiceRequestModel> requests) {
          if (!canShowBottomNav) {
            return null;
          }

          final filteredRequests = _filterRequests(requests);

          return WorkspaceBottomNav(
            items: _buildMobileNavItems(filteredRequests),
            selectedIndex: _selectedWorkspaceTab.index,
            dark: true,
            compact: true,
            onTap: (int index) {
              setState(() {
                _selectedWorkspaceTab = _CustomerWorkspaceTab.values[index];
              });
            },
          );
        },
        orElse: () => null,
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

class _ComposerQuickActionButton extends StatelessWidget {
  const _ComposerQuickActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.accentColor = AppTheme.cobalt,
    this.dark = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color accentColor;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark
            ? (isEnabled
                  ? const Color(0xFF17181B)
                  : Colors.white.withValues(alpha: 0.08))
            : isEnabled
            ? accentColor.withValues(alpha: 0.1)
            : AppTheme.clay.withValues(alpha: 0.32),
        shape: BoxShape.circle,
        border: Border.all(
          color: dark
              ? (isEnabled
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.06))
              : isEnabled
              ? accentColor.withValues(alpha: 0.22)
              : AppTheme.clay.withValues(alpha: 0.5),
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 42, height: 42),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 20,
          color: isEnabled
              ? (dark ? Colors.white : accentColor)
              : dark
              ? Colors.white.withValues(alpha: 0.26)
              : AppTheme.ink.withValues(alpha: 0.32),
        ),
      ),
    );
  }
}

class _CustomerConversationActionCard extends StatelessWidget {
  const _CustomerConversationActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.accentColor,
    required this.onPressed,
    this.dark = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final Color accentColor;
  final VoidCallback onPressed;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF121418) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : accentColor.withValues(alpha: 0.22),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: accentColor, size: 18),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: dark ? Colors.white : null,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: dark
                          ? Colors.white.withValues(alpha: 0.72)
                          : AppTheme.ink.withValues(alpha: 0.72),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (dark)
                    OutlinedButton.icon(
                      onPressed: onPressed,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.04),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      icon: Icon(icon),
                      label: Text(actionLabel),
                    )
                  else
                    FilledButton.tonalIcon(
                      onPressed: onPressed,
                      icon: Icon(icon),
                      label: Text(actionLabel),
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

class _CustomerPaymentCard extends StatelessWidget {
  const _CustomerPaymentCard({
    required this.invoice,
    required this.dueDateLabel,
    this.dark = false,
  });

  final RequestInvoiceModel invoice;
  final String dueDateLabel;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final status = invoice.status;
    final statusColors = switch (status) {
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
    final amountLabel = 'EUR ${invoice.amount.toStringAsFixed(2)}';
    final subtitle = invoice.requiresCustomerProof
        ? (invoice.isProofSubmitted
              ? 'Payment proof uploaded. Staff will review it here.'
              : invoice.isApproved
              ? 'Payment approved. Staff can now move the job into the start phase.'
              : invoice.isRejected
              ? 'Your last proof was rejected. Use the proof button by the chat box to upload a new one.'
              : 'Pay by ${invoice.paymentMethodLabel} and use the proof button by the chat box.')
        : 'Payment option: ${invoice.paymentMethodLabel}.';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF121418) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.clay.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Invoice ${invoice.invoiceNumber}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: dark ? Colors.white : null,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: statusColors.background,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      requestStatusLabelFor(status),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: statusColors.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$amountLabel · due $dueDateLabel',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: dark
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppTheme.ink.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: dark
                    ? Colors.white.withValues(alpha: 0.74)
                    : AppTheme.ink.withValues(alpha: 0.74),
              ),
            ),
            if (invoice.paymentInstructions.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                invoice.paymentInstructions,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.84)
                      : AppTheme.ink.withValues(alpha: 0.84),
                ),
              ),
            ],
            if (invoice.reviewNote.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Review note: ${invoice.reviewNote}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.ember,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (invoice.proof?.originalName.trim().isNotEmpty ==
                true) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Latest proof: ${invoice.proof!.originalName}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.68)
                      : AppTheme.ink.withValues(alpha: 0.68),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InboxAlertPill extends StatelessWidget {
  const _InboxAlertPill({required this.label, required this.accentColor});

  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accentColor.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.notifications_active_rounded,
              size: 14,
              color: accentColor,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestAvatar extends StatelessWidget {
  const _RequestAvatar({
    required this.icon,
    required this.accentColor,
    this.size = 46,
  });

  final IconData icon;
  final Color accentColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            accentColor.withValues(alpha: 0.9),
            accentColor.withValues(alpha: 0.68),
          ],
        ),
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accentColor.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: size * 0.46),
    );
  }
}

class _MiniCountPill extends StatelessWidget {
  const _MiniCountPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationMetaPill extends StatelessWidget {
  const _ConversationMetaPill({
    required this.icon,
    required this.label,
    required this.accentColor,
    this.dark = false,
  });

  final IconData icon;
  final String label;
  final Color accentColor;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xFF15171A)
            : Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : accentColor.withValues(alpha: 0.16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 16, color: accentColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.74)
                      : AppTheme.ink.withValues(alpha: 0.74),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTimelinePill extends StatelessWidget {
  const _ConversationTimelinePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.74)),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.74),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationHeaderActionChip extends StatelessWidget {
  const _ConversationHeaderActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
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
}

class _InboxEmptyState extends StatelessWidget {
  const _InboxEmptyState({
    required this.label,
    required this.onCreateRequest,
    this.dark = false,
  });

  final String label;
  final VoidCallback onCreateRequest;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: 0.06)
                : AppTheme.cobalt.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              color: dark
                  ? Colors.white.withValues(alpha: 0.86)
                  : AppTheme.cobalt,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: dark ? Colors.white.withValues(alpha: 0.74) : null,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.tonalIcon(
          onPressed: onCreateRequest,
          style: dark
              ? FilledButton.styleFrom(
                  backgroundColor: AppTheme.cobalt.withValues(alpha: 0.18),
                  foregroundColor: Colors.white,
                )
              : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create Request'),
        ),
      ],
    );
  }
}
