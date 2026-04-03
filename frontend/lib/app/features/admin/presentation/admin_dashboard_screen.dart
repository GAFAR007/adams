/// WHAT: Renders the admin workspace with separate overview, queue, staff, and invite sections.
/// WHY: Admin operations grow quickly, so one long stacked dashboard becomes noisy and hard to use as customer volume rises.
/// HOW: Load the summary bundle once, fetch the request queue with backend filters, and switch sections through a chat-style bottom navigation bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/models/service_request_model.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../shared/data/internal_chat_repository.dart';
import '../../../shared/presentation/app_language_toggle.dart';
import '../../../shared/presentation/invoice_draft_dialog.dart';
import '../../../shared/presentation/workspace_bottom_nav.dart';
import '../../../shared/presentation/workspace_profile_action_button.dart';
import '../../../shared/utils/external_url_opener.dart';
import '../../../shared/utils/request_attachment_picker.dart';
import '../../../theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../../staff/presentation/staff_internal_chat_screen.dart';
import '../data/admin_repository.dart';
import 'admin_internal_review_screen.dart';
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
  final Set<String> _deliveringRequestIds = <String>{};
  final Set<String> _uploadingAttachmentRequestIds = <String>{};
  final Set<String> _reviewingPaymentProofRequestIds = <String>{};
  String? _lastThreadScrollSignature;
  _AdminTab _selectedTab = _AdminTab.overview;
  _AdminRequestFilter _selectedRequestFilter = _AdminRequestFilter.all;
  String _inviteStaffType = 'technician';
  String _appliedSearchQuery = '';
  String? _selectedRequestId;
  bool _isInviteSubmitting = false;

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

        ref.invalidate(adminDashboardProvider);
        ref.invalidate(adminRequestsProvider(_currentRequestQuery()));
      });
    });
  }

  String _t({required String en, required String de}) {
    return _language.pick(en: en, de: de);
  }

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
            staffType: _inviteStaffType,
          );
      ref.invalidate(adminDashboardProvider);
      _inviteFirstNameController.clear();
      _inviteLastNameController.clear();
      _inviteEmailController.clear();
      _invitePhoneController.clear();

      if (!mounted) {
        return;
      }

      setState(() => _inviteStaffType = 'technician');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              en: 'Invite created successfully',
              de: 'Einladung erfolgreich erstellt',
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
        SnackBar(
          content: Text(
            _t(
              en: 'Request assigned successfully',
              de: 'Anfrage erfolgreich zugewiesen',
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
        setState(() => _uploadingAttachmentRequestIds.remove(request.id));
      }
    }
  }

  Future<void> _deleteInvite(StaffInviteModel invite) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(
            _t(en: 'Remove invite link', de: 'Einladungslink entfernen'),
          ),
          content: Text(
            _t(
              en: 'If this invite is still pending it will be canceled. If it was already used, only the processed link record will be removed. Continue for ${invite.fullName.isEmpty ? invite.email : invite.fullName}?',
              de: 'Wenn diese Einladung noch aussteht, wird sie storniert. Wenn sie bereits verwendet wurde, wird nur der verarbeitete Link-Eintrag entfernt. Fortfahren für ${invite.fullName.isEmpty ? invite.email : invite.fullName}?',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_t(en: 'Keep link', de: 'Link behalten')),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_t(en: 'Remove link', de: 'Link entfernen')),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(en: 'Invite link removed', de: 'Einladungslink entfernt'),
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
        setState(() => _inviteIdsBeingDeleted.remove(invite.id));
      }
    }
  }

  bool _canOpenInternalReview(ServiceRequestModel request) {
    final hasBlockingInvoice =
        request.invoice != null &&
        // WHY: A paid site-review invoice can still exist while the post-review
        // final estimate is waiting for a new admin quotation review.
        !(request.invoice!.isSiteReview &&
            request.isQuoteReadyForInternalReview &&
            request.quoteReadyEstimation != null);

    if (hasBlockingInvoice ||
        request.isQuotedReadyStateLocked ||
        request.status == 'closed') {
      return false;
    }

    return request.siteReviewReadyEstimation != null ||
        request.quoteReadyEstimation != null;
  }

  bool _canDeliverRequest(ServiceRequestModel request) {
    return request.status == 'work_done';
  }

  Future<void> _saveInternalReview(ServiceRequestModel request) async {
    final draft = await Navigator.of(context).push<InvoiceDraftInput>(
      MaterialPageRoute<InvoiceDraftInput>(
        fullscreenDialog: true,
        builder: (BuildContext context) {
          return AdminInternalReviewScreen(request: request);
        },
      ),
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
            adminServiceChargePercent: draft.adminServiceChargePercent,
            dueDate: draft.dueDate,
            reviewKind: draft.reviewKind,
            siteReviewDate: draft.siteReviewDate,
            siteReviewStartTime: draft.siteReviewStartTime,
            siteReviewEndTime: draft.siteReviewEndTime,
            siteReviewNotes: draft.siteReviewNotes,
            plannedStartDate: draft.plannedStartDate,
            plannedStartTime: draft.plannedStartTime,
            plannedEndTime: draft.plannedEndTime,
            plannedHoursPerDay: draft.plannedHoursPerDay,
            plannedExpectedEndDate: draft.plannedExpectedEndDate,
            plannedDailySchedule: draft.plannedDailySchedule
                .map((entry) => entry.toJson())
                .toList(),
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
        SnackBar(
          content: Text(
            _t(
              en: 'Internal review updated',
              de: 'Interne Prüfung aktualisiert',
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
        setState(() => _sendingInvoiceRequestIds.remove(request.id));
      }
    }
  }

  Future<void> _deliverRequest(ServiceRequestModel request) async {
    setState(() => _deliveringRequestIds.add(request.id));

    try {
      await ref
          .read(adminRepositoryProvider)
          .deliverRequest(requestId: request.id);
      ref.invalidate(adminDashboardProvider);
      ref.invalidate(adminRequestsProvider(_currentRequestQuery()));

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(en: 'Request delivered', de: 'Anfrage als geliefert markiert'),
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
        setState(() => _deliveringRequestIds.remove(request.id));
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
            title: Text(
              _t(en: 'Reject payment proof', de: 'Zahlungsnachweis ablehnen'),
            ),
            content: TextField(
              controller: noteController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: _t(en: 'Reason', de: 'Grund'),
                hintText: _t(
                  en: 'Tell the customer what needs to be corrected',
                  de: 'Teilen Sie dem Kunden mit, was korrigiert werden muss',
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(_t(en: 'Cancel', de: 'Abbrechen')),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(noteController.text.trim()),
                child: Text(_t(en: 'Reject proof', de: 'Nachweis ablehnen')),
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

  Future<void> _copyInviteLink(String inviteLink) async {
    // WHY: Copying the invite link is a pure admin convenience action, so keep the clipboard logic in one reusable helper.
    await Clipboard.setData(ClipboardData(text: inviteLink));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t(en: 'Invite link copied', de: 'Einladungslink kopiert'),
        ),
      ),
    );
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
      _AdminRequestFilter.all => _t(en: 'All', de: 'Alle'),
      _AdminRequestFilter.waiting => _t(en: 'Waiting', de: 'Wartend'),
      _AdminRequestFilter.assigned => _t(en: 'Assigned', de: 'Zugewiesen'),
      _AdminRequestFilter.underReview => _t(en: 'Review', de: 'Prüfung'),
      _AdminRequestFilter.quoted => _t(en: 'Quoted', de: 'Angebot'),
      _AdminRequestFilter.confirmed => _t(en: 'Confirmed', de: 'Bestätigt'),
      _AdminRequestFilter.closed => _t(en: 'Closed', de: 'Geschlossen'),
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
      WorkspaceBottomNavItem(
        label: _t(en: 'Overview', de: 'Überblick'),
        icon: Icons.dashboard_customize_rounded,
      ),
      WorkspaceBottomNavItem(
        label: _t(en: 'Queue', de: 'Warteschlange'),
        icon: Icons.forum_rounded,
        badgeText:
            '${bundle.kpis.waitingQueueCount + bundle.kpis.activeQueueCount}',
      ),
      WorkspaceBottomNavItem(
        label: _t(en: 'Staff', de: 'Team'),
        icon: Icons.groups_rounded,
        badgeText: '${bundle.kpis.staffOnlineCount}',
      ),
      WorkspaceBottomNavItem(
        label: _t(en: 'Invites', de: 'Einladungen'),
        icon: Icons.person_add_alt_1_rounded,
        badgeText: '${bundle.kpis.pendingInvitesCount}',
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
                      language: _language,
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
                      language: _language,
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
                              !_canOpenInternalReview(selectedRequest)
                          ? null
                          : () => _saveInternalReview(selectedRequest),
                      onDeliverRequest:
                          selectedRequest == null ||
                              !_canDeliverRequest(selectedRequest)
                          ? null
                          : () => _deliverRequest(selectedRequest),
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
                      isDeliveringRequest:
                          selectedRequest != null &&
                          _deliveringRequestIds.contains(selectedRequest.id),
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
                language: _language,
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
                onSendInvoice: !_canOpenInternalReview(selectedRequest)
                    ? null
                    : () => _saveInternalReview(selectedRequest),
                onDeliverRequest: !_canDeliverRequest(selectedRequest)
                    ? null
                    : () => _deliverRequest(selectedRequest),
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
                isDeliveringRequest: _deliveringRequestIds.contains(
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
              language: _language,
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
        title: _t(en: 'Queue', de: 'Warteschlange'),
        subtitle: _t(
          en: 'Loading filtered request threads...',
          de: 'Gefilterte Anfrageverläufe werden geladen...',
        ),
        loading: true,
      ),
      error: (Object error, StackTrace stackTrace) => _buildAdminStatePanel(
        context,
        title: _t(
          en: 'Unable to load queue threads',
          de: 'Warteschlangen-Verläufe konnten nicht geladen werden',
        ),
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
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppTheme.darkBorder),
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
        language: _language,
        kpis: bundle.kpis,
        recentRequests: bundle.recentRequests,
        onOpenRequest: _openRequestFromOverview,
        onOpenQueue: _openQueueOverview,
      ),
      _AdminTab.queue => _buildQueueTab(context, bundle, requestsAsync),
      _AdminTab.staff => ListView(
        padding: const EdgeInsets.only(bottom: 124),
        children: <Widget>[
          AdminStaffSection(language: _language, staff: bundle.staff),
        ],
      ),
      _AdminTab.invites => AdminInvitesSection(
        language: _language,
        firstNameController: _inviteFirstNameController,
        lastNameController: _inviteLastNameController,
        emailController: _inviteEmailController,
        phoneController: _invitePhoneController,
        inviteStaffType: _inviteStaffType,
        isInviteSubmitting: _isInviteSubmitting,
        onInviteStaffTypeChanged: (String? value) {
          if (value == null) {
            return;
          }
          setState(() => _inviteStaffType = value);
        },
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
    ref.watch(appLanguageProvider);
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
      backgroundColor: AppTheme.darkPage,
      appBar: AppBar(
        backgroundColor: AppTheme.darkPage,
        foregroundColor: AppTheme.darkText,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: AppTheme.darkText,
          fontWeight: FontWeight.w700,
        ),
        title: Text(
          '${_t(en: 'Admin Workspace', de: 'Admin-Arbeitsbereich')} · ${authState.user?.fullName ?? _t(en: 'Admin', de: 'Admin')}',
        ),
        actions: <Widget>[
          WorkspaceCalendarActionButton(
            tooltip: _t(en: 'Shared calendar', de: 'Gemeinsamer Kalender'),
            onPressed: () => context.go('/admin/calendar'),
            dark: true,
          ),
          WorkspaceProfileActionButton(
            tooltip: _t(en: 'Profile', de: 'Profil'),
            onPressed: () => context.go('/admin/profile'),
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
            title: _t(en: 'Admin workspace', de: 'Admin-Arbeitsbereich'),
            subtitle: _t(
              en: 'Loading your latest requests, staff, and invite data...',
              de: 'Ihre neuesten Anfragen, Teamdaten und Einladungen werden geladen...',
            ),
            loading: true,
          ),
        ),
        error: (Object error, StackTrace stackTrace) => _buildSectionFrame(
          context,
          _buildAdminStatePanel(
            context,
            title: _t(
              en: 'Unable to load admin dashboard',
              de: 'Admin-Dashboard konnte nicht geladen werden',
            ),
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
