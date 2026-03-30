/// WHAT: Renders the admin workspace with separate overview, queue, staff, and invite sections.
/// WHY: Admin operations grow quickly, so one long stacked dashboard becomes noisy and hard to use as customer volume rises.
/// HOW: Load the summary bundle once, fetch the request queue with backend filters, and switch sections through a chat-style bottom navigation bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/dashboard_models.dart';
import '../../../core/models/service_request_model.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../shared/data/internal_chat_repository.dart';
import '../../../shared/presentation/invoice_draft_dialog.dart';
import '../../../shared/presentation/workspace_bottom_nav.dart';
import '../../../shared/utils/external_url_opener.dart';
import '../../../shared/utils/request_attachment_picker.dart';
import '../../auth/application/auth_controller.dart';
import '../../staff/presentation/staff_internal_chat_screen.dart';
import '../data/admin_repository.dart';
import 'admin_dashboard_sections.dart';

final adminDashboardProvider = FutureProvider<AdminDashboardBundle>((
  Ref ref,
) async {
  debugPrint('adminDashboardProvider: fetching admin dashboard summary');
  return ref.watch(adminRepositoryProvider).fetchDashboardBundle();
});

final adminRequestsProvider = FutureProvider.autoDispose
    .family<List<ServiceRequestModel>, _AdminRequestQuery>((
      Ref ref,
      _AdminRequestQuery query,
    ) async {
      debugPrint(
        'adminRequestsProvider: fetching requests with status=${query.status} search=${query.search}',
      );
      return ref
          .watch(adminRepositoryProvider)
          .fetchRequests(status: query.status, search: query.search);
    });

enum _AdminTab { overview, queue, staff, invites, chats }

enum _AdminRequestFilter {
  all,
  waiting,
  assigned,
  underReview,
  quoted,
  confirmed,
  closed,
}

class _AdminRequestQuery {
  const _AdminRequestQuery({required this.status, required this.search});

  final String? status;
  final String? search;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is _AdminRequestQuery &&
        other.status == status &&
        other.search == search;
  }

  @override
  int get hashCode => Object.hash(status, search);
}

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _inviteFirstNameController = TextEditingController();
  final _inviteLastNameController = TextEditingController();
  final _inviteEmailController = TextEditingController();
  final _invitePhoneController = TextEditingController();
  final _requestSearchController = TextEditingController();
  final ScrollController _requestThreadScrollController = ScrollController();
  final Map<String, TextEditingController> _messageControllers =
      <String, TextEditingController>{};
  final Map<String, String?> _selectedAssignments = <String, String?>{};
  final Set<String> _assigningRequestIds = <String>{};
  final Set<String> _inviteIdsBeingDeleted = <String>{};
  final Set<String> _sendingMessageRequestIds = <String>{};
  final Set<String> _sendingInvoiceRequestIds = <String>{};
  final Set<String> _uploadingAttachmentRequestIds = <String>{};
  final Set<String> _reviewingPaymentProofRequestIds = <String>{};
  String? _lastThreadScrollSignature;
  _AdminTab _selectedTab = _AdminTab.overview;
  _AdminRequestFilter _selectedRequestFilter = _AdminRequestFilter.all;
  String _appliedSearchQuery = '';
  String? _selectedRequestId;
  bool _isInviteSubmitting = false;

  @override
  void dispose() {
    for (final controller in _messageControllers.values) {
      controller.dispose();
    }
    _inviteFirstNameController.dispose();
    _inviteLastNameController.dispose();
    _inviteEmailController.dispose();
    _invitePhoneController.dispose();
    _requestSearchController.dispose();
    _requestThreadScrollController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(String requestId) {
    return _messageControllers.putIfAbsent(
      requestId,
      () => TextEditingController(),
    );
  }

  Future<void> _submitInvite() async {
    setState(() => _isInviteSubmitting = true);
    debugPrint('AdminDashboardScreen._submitInvite: creating staff invite');

    try {
      await ref
          .read(adminRepositoryProvider)
          .createInvite(
            firstName: _inviteFirstNameController.text.trim(),
            lastName: _inviteLastNameController.text.trim(),
            email: _inviteEmailController.text.trim(),
            phone: _invitePhoneController.text.trim(),
          );
      ref.invalidate(adminDashboardProvider);
      _inviteFirstNameController.clear();
      _inviteLastNameController.clear();
      _inviteEmailController.clear();
      _invitePhoneController.clear();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite created successfully')),
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
        setState(() => _isInviteSubmitting = false);
      }
    }
  }

  Future<void> _assignRequest({
    required String requestId,
    required String staffId,
  }) async {
    setState(() => _assigningRequestIds.add(requestId));
    debugPrint(
      'AdminDashboardScreen._assignRequest: assigning request $requestId to $staffId',
    );

    try {
      await ref
          .read(adminRepositoryProvider)
          .assignRequest(requestId: requestId, staffId: staffId);
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(
        adminRequestsProvider(
          _AdminRequestQuery(
            status: _statusForFilter(_selectedRequestFilter),
            search: _appliedSearchQuery.isEmpty ? null : _appliedSearchQuery,
          ),
        ),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request assigned successfully')),
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
        setState(() => _assigningRequestIds.remove(requestId));
      }
    }
  }

  Future<void> _sendRequestMessage(ServiceRequestModel request) async {
    if (request.status == 'closed') {
      return;
    }

    final controller = _controllerFor(request.id);
    final text = controller.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() => _sendingMessageRequestIds.add(request.id));
    debugPrint(
      'AdminDashboardScreen._sendRequestMessage: sending reply for ${request.id}',
    );

    try {
      await ref
          .read(adminRepositoryProvider)
          .sendMessage(requestId: request.id, message: text);
      controller.clear();
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(adminRequestsProvider(_currentRequestQuery()));

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
        setState(() => _sendingMessageRequestIds.remove(request.id));
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

    setState(() => _uploadingAttachmentRequestIds.add(request.id));
    debugPrint(
      'AdminDashboardScreen._uploadRequestAttachment: uploading attachment for ${request.id}',
    );

    try {
      await ref
          .read(adminRepositoryProvider)
          .uploadRequestAttachment(
            requestId: request.id,
            bytes: pickedFile.bytes,
            fileName: pickedFile.name,
            mimeType: pickedFile.mimeType,
            caption: caption.isEmpty ? null : caption,
          );
      controller.clear();
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(adminRequestsProvider(_currentRequestQuery()));

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Attachment sent')));
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
        setState(() => _uploadingAttachmentRequestIds.remove(request.id));
      }
    }
  }

  Future<void> _deleteInvite(StaffInviteModel invite) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Remove invite link'),
          content: Text(
            'If this invite is still pending it will be canceled. If it was already used, only the processed link record will be removed. Continue for ${invite.fullName.isEmpty ? invite.email : invite.fullName}?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep link'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove link'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    setState(() => _inviteIdsBeingDeleted.add(invite.id));
    debugPrint(
      'AdminDashboardScreen._deleteInvite: removing invite ${invite.id}',
    );

    try {
      await ref.read(adminRepositoryProvider).deleteInvite(inviteId: invite.id);
      ref.invalidate(adminDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invite link removed')));
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
        setState(() => _inviteIdsBeingDeleted.remove(invite.id));
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

    setState(() => _sendingInvoiceRequestIds.add(request.id));

    try {
      await ref
          .read(adminRepositoryProvider)
          .sendInvoice(
            requestId: request.id,
            amount: draft.amount,
            dueDate: draft.dueDate,
            paymentMethod: draft.paymentMethod,
            paymentInstructions: draft.paymentInstructions,
            note: draft.note,
          );
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(adminRequestsProvider(_currentRequestQuery()));

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
        setState(() => _sendingInvoiceRequestIds.remove(request.id));
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

    setState(() => _reviewingPaymentProofRequestIds.add(request.id));

    try {
      await ref
          .read(adminRepositoryProvider)
          .reviewPaymentProof(
            requestId: request.id,
            decision: decision,
            reviewNote: reviewNote,
          );
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(adminRequestsProvider(_currentRequestQuery()));

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
        setState(() => _reviewingPaymentProofRequestIds.remove(request.id));
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

  Future<void> _copyInviteLink(String inviteLink) async {
    // WHY: Copying the invite link is a pure admin convenience action, so keep the clipboard logic in one reusable helper.
    await Clipboard.setData(ClipboardData(text: inviteLink));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Invite link copied')));
  }

  void _applyQueueSearch() {
    // WHY: Apply search explicitly so admins can type naturally without refetching the queue on every single keypress.
    setState(() {
      _appliedSearchQuery = _requestSearchController.text.trim();
      _selectedRequestId = null;
    });
  }

  void _clearQueueSearch() {
    setState(() {
      _requestSearchController.clear();
      _appliedSearchQuery = '';
      _selectedRequestId = null;
    });
  }

  void _selectQueueFilter(_AdminRequestFilter filter) {
    // WHY: Reset the selected thread when the queue slice changes so stale request ids do not linger after a refetch.
    setState(() {
      _selectedRequestFilter = filter;
      _selectedRequestId = null;
    });
  }

  ServiceRequestModel? _resolveSelectedRequest(
    List<ServiceRequestModel> requests,
  ) {
    if (requests.isEmpty) {
      return null;
    }

    for (final request in requests) {
      if (request.id == _selectedRequestId) {
        return request;
      }
    }

    return requests.first;
  }

  _AdminRequestFilter _filterForRequest(ServiceRequestModel request) {
    return switch (request.status) {
      'submitted' => _AdminRequestFilter.waiting,
      'assigned' => _AdminRequestFilter.assigned,
      'under_review' => _AdminRequestFilter.underReview,
      'quoted' => _AdminRequestFilter.quoted,
      'appointment_confirmed' => _AdminRequestFilter.confirmed,
      'closed' => _AdminRequestFilter.closed,
      _ => _AdminRequestFilter.all,
    };
  }

  void _openRequestFromOverview(ServiceRequestModel request) {
    _lastThreadScrollSignature = null;
    setState(() {
      _selectedTab = _AdminTab.queue;
      _selectedRequestFilter = _filterForRequest(request);
      _selectedRequestId = request.id;
      _appliedSearchQuery = '';
      _requestSearchController.clear();
    });
  }

  void _openQueueOverview() {
    _lastThreadScrollSignature = null;
    setState(() {
      _selectedTab = _AdminTab.queue;
      _selectedRequestFilter = _AdminRequestFilter.all;
      _selectedRequestId = null;
      _appliedSearchQuery = '';
      _requestSearchController.clear();
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

  String? _statusForFilter(_AdminRequestFilter filter) {
    return switch (filter) {
      _AdminRequestFilter.all => null,
      _AdminRequestFilter.waiting => 'submitted',
      _AdminRequestFilter.assigned => 'assigned',
      _AdminRequestFilter.underReview => 'under_review',
      _AdminRequestFilter.quoted => 'quoted',
      _AdminRequestFilter.confirmed => 'appointment_confirmed',
      _AdminRequestFilter.closed => 'closed',
    };
  }

  int _filterCount(AdminKpis kpis, _AdminRequestFilter filter) {
    return switch (filter) {
      _AdminRequestFilter.all => kpis.totalRequests,
      _AdminRequestFilter.waiting => kpis.waitingQueueCount,
      _AdminRequestFilter.assigned => kpis.countsByStatus['assigned'] ?? 0,
      _AdminRequestFilter.underReview =>
        kpis.countsByStatus['under_review'] ?? 0,
      _AdminRequestFilter.quoted => kpis.countsByStatus['quoted'] ?? 0,
      _AdminRequestFilter.confirmed =>
        kpis.countsByStatus['appointment_confirmed'] ?? 0,
      _AdminRequestFilter.closed => kpis.countsByStatus['closed'] ?? 0,
    };
  }

  String _filterLabel(_AdminRequestFilter filter) {
    return switch (filter) {
      _AdminRequestFilter.all => 'All',
      _AdminRequestFilter.waiting => 'Waiting',
      _AdminRequestFilter.assigned => 'Assigned',
      _AdminRequestFilter.underReview => 'Review',
      _AdminRequestFilter.quoted => 'Quoted',
      _AdminRequestFilter.confirmed => 'Confirmed',
      _AdminRequestFilter.closed => 'Closed',
    };
  }

  List<AdminRequestFilterChipData> _buildFilterChips(
    AdminDashboardBundle bundle,
  ) {
    return _AdminRequestFilter.values.map((filter) {
      return AdminRequestFilterChipData(
        label: _filterLabel(filter),
        count: _filterCount(bundle.kpis, filter),
        isSelected: _selectedRequestFilter == filter,
        onTap: () => _selectQueueFilter(filter),
      );
    }).toList();
  }

  List<WorkspaceBottomNavItem> _buildNavItems(
    AdminDashboardBundle bundle, {
    required int internalChatUnreadCount,
  }) {
    return <WorkspaceBottomNavItem>[
      const WorkspaceBottomNavItem(
        label: 'Overview',
        icon: Icons.dashboard_customize_rounded,
      ),
      WorkspaceBottomNavItem(
        label: 'Queue',
        icon: Icons.forum_rounded,
        badgeText:
            '${bundle.kpis.waitingQueueCount + bundle.kpis.activeQueueCount}',
      ),
      WorkspaceBottomNavItem(
        label: 'Staff',
        icon: Icons.groups_rounded,
        badgeText: '${bundle.kpis.staffOnlineCount}',
      ),
      WorkspaceBottomNavItem(
        label: 'Invites',
        icon: Icons.person_add_alt_1_rounded,
        badgeText: '${bundle.kpis.pendingInvitesCount}',
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

  _AdminRequestQuery _currentRequestQuery() {
    return _AdminRequestQuery(
      status: _statusForFilter(_selectedRequestFilter),
      search: _appliedSearchQuery.isEmpty ? null : _appliedSearchQuery,
    );
  }

  Widget _buildQueueTab(
    BuildContext context,
    AdminDashboardBundle bundle,
    AsyncValue<List<ServiceRequestModel>> requestsAsync,
  ) {
    return requestsAsync.when(
      data: (List<ServiceRequestModel> requests) {
        final selectedRequest = _resolveSelectedRequest(requests);
        _scheduleThreadScrollToLatest(selectedRequest);
        final validStaffIds = bundle.staff.map((staff) => staff.id).toSet();
        final selectedAssignmentId = selectedRequest == null
            ? null
            : (() {
                final current =
                    _selectedAssignments[selectedRequest.id] ??
                    selectedRequest.assignedStaff?.id;
                return validStaffIds.contains(current) ? current : null;
              })();
        final isAssigning =
            selectedRequest != null &&
            _assigningRequestIds.contains(selectedRequest.id);

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final isDesktop = constraints.maxWidth >= 1180;
            final showDetailOnly = !isDesktop && selectedRequest != null;

            if (isDesktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: 360,
                    child: AdminQueueSidebar(
                      searchController: _requestSearchController,
                      onApplySearch: _applyQueueSearch,
                      onClearSearch: _clearQueueSearch,
                      filterChips: _buildFilterChips(bundle),
                      requests: requests,
                      selectedRequestId: selectedRequest?.id,
                      onSelectRequest: (request) {
                        _lastThreadScrollSignature = null;
                        setState(() => _selectedRequestId = request.id);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AdminRequestDetailPane(
                      request: selectedRequest,
                      staff: bundle.staff,
                      onAssignToStaff: selectedRequest == null
                          ? null
                          : (String staffId) => _assignRequest(
                              requestId: selectedRequest.id,
                              staffId: staffId,
                            ),
                      selectedAssignmentId: selectedAssignmentId,
                      onAssignmentChanged: (String? value) {
                        if (selectedRequest == null) {
                          return;
                        }

                        setState(
                          () =>
                              _selectedAssignments[selectedRequest.id] = value,
                        );
                      },
                      onAssign:
                          selectedRequest == null ||
                              selectedAssignmentId == null
                          ? null
                          : () => _assignRequest(
                              requestId: selectedRequest.id,
                              staffId: selectedAssignmentId,
                            ),
                      isAssigning: isAssigning,
                      onSendInvoice:
                          selectedRequest == null ||
                              selectedRequest.status == 'closed'
                          ? null
                          : () => _sendInvoice(selectedRequest),
                      onOpenPaymentProof:
                          selectedRequest?.invoice?.proof?.fileUrl == null
                          ? null
                          : () => _openPaymentProof(selectedRequest!),
                      onOpenReceipt:
                          selectedRequest?.invoice?.receiptUrl == null
                          ? null
                          : () => _openReceipt(selectedRequest!),
                      onApprovePaymentProof:
                          selectedRequest?.invoice?.isProofSubmitted == true
                          ? () => _reviewPaymentProof(
                              selectedRequest!,
                              decision: 'approved',
                            )
                          : null,
                      onRejectPaymentProof:
                          selectedRequest?.invoice?.isProofSubmitted == true
                          ? () => _reviewPaymentProof(
                              selectedRequest!,
                              decision: 'rejected',
                            )
                          : null,
                      messageController: selectedRequest == null
                          ? null
                          : _controllerFor(selectedRequest.id),
                      isSendingMessage:
                          selectedRequest != null &&
                          _sendingMessageRequestIds.contains(
                            selectedRequest.id,
                          ),
                      isUploadingAttachment:
                          selectedRequest != null &&
                          _uploadingAttachmentRequestIds.contains(
                            selectedRequest.id,
                          ),
                      composerEnabled:
                          selectedRequest != null &&
                          selectedRequest.status != 'closed',
                      onSendMessage: selectedRequest == null
                          ? null
                          : () => _sendRequestMessage(selectedRequest),
                      onUploadAttachment: selectedRequest == null
                          ? null
                          : () => _uploadRequestAttachment(selectedRequest),
                      threadScrollController: _requestThreadScrollController,
                      isSendingInvoice:
                          selectedRequest != null &&
                          _sendingInvoiceRequestIds.contains(
                            selectedRequest.id,
                          ),
                      isReviewingPaymentProof:
                          selectedRequest != null &&
                          _reviewingPaymentProofRequestIds.contains(
                            selectedRequest.id,
                          ),
                    ),
                  ),
                ],
              );
            }

            if (showDetailOnly) {
              return AdminRequestDetailPane(
                request: selectedRequest,
                staff: bundle.staff,
                edgeToEdge: true,
                onAssignToStaff: (String staffId) => _assignRequest(
                  requestId: selectedRequest.id,
                  staffId: staffId,
                ),
                selectedAssignmentId: selectedAssignmentId,
                onAssignmentChanged: (String? value) {
                  setState(
                    () => _selectedAssignments[selectedRequest.id] = value,
                  );
                },
                onAssign: selectedAssignmentId == null
                    ? null
                    : () => _assignRequest(
                        requestId: selectedRequest.id,
                        staffId: selectedAssignmentId,
                      ),
                isAssigning: isAssigning,
                onSendInvoice: selectedRequest.status == 'closed'
                    ? null
                    : () => _sendInvoice(selectedRequest),
                onOpenPaymentProof:
                    selectedRequest.invoice?.proof?.fileUrl == null
                    ? null
                    : () => _openPaymentProof(selectedRequest),
                onOpenReceipt: selectedRequest.invoice?.receiptUrl == null
                    ? null
                    : () => _openReceipt(selectedRequest),
                onApprovePaymentProof:
                    selectedRequest.invoice?.isProofSubmitted == true
                    ? () => _reviewPaymentProof(
                        selectedRequest,
                        decision: 'approved',
                      )
                    : null,
                onRejectPaymentProof:
                    selectedRequest.invoice?.isProofSubmitted == true
                    ? () => _reviewPaymentProof(
                        selectedRequest,
                        decision: 'rejected',
                      )
                    : null,
                messageController: _controllerFor(selectedRequest.id),
                isSendingMessage: _sendingMessageRequestIds.contains(
                  selectedRequest.id,
                ),
                isUploadingAttachment: _uploadingAttachmentRequestIds.contains(
                  selectedRequest.id,
                ),
                composerEnabled: selectedRequest.status != 'closed',
                onSendMessage: () => _sendRequestMessage(selectedRequest),
                onUploadAttachment: () =>
                    _uploadRequestAttachment(selectedRequest),
                isSendingInvoice: _sendingInvoiceRequestIds.contains(
                  selectedRequest.id,
                ),
                isReviewingPaymentProof: _reviewingPaymentProofRequestIds
                    .contains(selectedRequest.id),
                onBack: () {
                  _lastThreadScrollSignature = null;
                  setState(() => _selectedRequestId = null);
                },
                threadScrollController: _requestThreadScrollController,
              );
            }

            return AdminQueueSidebar(
              searchController: _requestSearchController,
              onApplySearch: _applyQueueSearch,
              onClearSearch: _clearQueueSearch,
              filterChips: _buildFilterChips(bundle),
              edgeToEdge: true,
              requests: requests,
              selectedRequestId: selectedRequest?.id,
              onSelectRequest: (request) {
                _lastThreadScrollSignature = null;
                setState(() => _selectedRequestId = request.id);
              },
            );
          },
        );
      },
      loading: () => _buildAdminStatePanel(
        context,
        title: 'Queue',
        subtitle: 'Loading filtered request threads...',
        loading: true,
      ),
      error: (Object error, StackTrace stackTrace) => _buildAdminStatePanel(
        context,
        title: 'Unable to load queue threads',
        subtitle: error.toString(),
      ),
    );
  }

  Widget _buildAdminStatePanel(
    BuildContext context, {
    required String title,
    required String subtitle,
    bool loading = false,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF111316),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                    height: 1.35,
                  ),
                ),
                if (loading) ...<Widget>[
                  const SizedBox(height: 18),
                  const Center(child: CircularProgressIndicator()),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionFrame(
    BuildContext context,
    Widget child, {
    bool edgeToEdgeMobile = false,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 600;
    final horizontalPadding = isCompact ? (edgeToEdgeMobile ? 0.0 : 8.0) : 20.0;
    final topPadding = isCompact ? (edgeToEdgeMobile ? 0.0 : 8.0) : 20.0;
    final bottomPadding = isCompact ? (edgeToEdgeMobile ? 0.0 : 8.0) : 8.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        bottomPadding,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1480),
          child: child,
        ),
      ),
    );
  }

  Widget _buildCurrentSection(
    BuildContext context,
    AdminDashboardBundle bundle,
    AsyncValue<List<ServiceRequestModel>> requestsAsync,
    String currentOperatorId,
    String currentOperatorName,
  ) {
    return switch (_selectedTab) {
      _AdminTab.overview => AdminOverviewSection(
        kpis: bundle.kpis,
        recentRequests: bundle.recentRequests,
        onOpenRequest: _openRequestFromOverview,
        onOpenQueue: _openQueueOverview,
      ),
      _AdminTab.queue => _buildQueueTab(context, bundle, requestsAsync),
      _AdminTab.staff => ListView(
        padding: const EdgeInsets.only(bottom: 124),
        children: <Widget>[AdminStaffSection(staff: bundle.staff)],
      ),
      _AdminTab.invites => AdminInvitesSection(
        firstNameController: _inviteFirstNameController,
        lastNameController: _inviteLastNameController,
        emailController: _inviteEmailController,
        phoneController: _invitePhoneController,
        isInviteSubmitting: _isInviteSubmitting,
        onSubmitInvite: _submitInvite,
        invites: bundle.invites,
        inviteIdsBeingDeleted: _inviteIdsBeingDeleted,
        onCopyInvite: _copyInviteLink,
        onDeleteInvite: _deleteInvite,
      ),
      _AdminTab.chats => InternalChatScreen(
        currentUserId: currentOperatorId,
        currentUserName: currentOperatorName,
        viewerRole: 'admin',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<RealtimeEvent>>(realtimeEventsProvider, (_, next) {
      next.whenData((event) {
        if (!event.affectsRequests) {
          return;
        }

        ref.invalidate(adminDashboardProvider);
        ref.invalidate(adminRequestsProvider(_currentRequestQuery()));
      });
    });

    final bundleAsync = ref.watch(adminDashboardProvider);
    final requestsAsync = ref.watch(
      adminRequestsProvider(_currentRequestQuery()),
    );
    final authState = ref.watch(authControllerProvider);
    final internalChatUnreadAsync = ref.watch(
      internalChatUnreadCountProvider('admin'),
    );
    final isCompactNav = MediaQuery.sizeOf(context).width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0E10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0E10),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        title: Text('Admin Workspace · ${authState.user?.fullName ?? 'Admin'}'),
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
        data: (AdminDashboardBundle bundle) {
          return _buildSectionFrame(
            context,
            _buildCurrentSection(
              context,
              bundle,
              requestsAsync,
              authState.user?.id ?? '',
              authState.user?.fullName ?? 'Admin',
            ),
            edgeToEdgeMobile:
                _selectedTab == _AdminTab.queue ||
                _selectedTab == _AdminTab.chats,
          );
        },
        loading: () => _buildSectionFrame(
          context,
          _buildAdminStatePanel(
            context,
            title: 'Admin workspace',
            subtitle: 'Loading your latest requests, staff, and invite data...',
            loading: true,
          ),
        ),
        error: (Object error, StackTrace stackTrace) => _buildSectionFrame(
          context,
          _buildAdminStatePanel(
            context,
            title: 'Unable to load admin dashboard',
            subtitle: error.toString(),
          ),
        ),
      ),
      bottomNavigationBar: bundleAsync.maybeWhen(
        data: (AdminDashboardBundle bundle) {
          final internalChatUnreadCount = internalChatUnreadAsync.maybeWhen(
            data: (count) => count,
            orElse: () => 0,
          );
          return WorkspaceBottomNav(
            items: _buildNavItems(
              bundle,
              internalChatUnreadCount: internalChatUnreadCount,
            ),
            selectedIndex: _selectedTab.index,
            dark: true,
            compact: isCompactNav,
            onTap: (int index) {
              setState(() => _selectedTab = _AdminTab.values[index]);
            },
          );
        },
        orElse: () => null,
      ),
    );
  }
}
