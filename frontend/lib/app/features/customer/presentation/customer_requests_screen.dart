/// WHAT: Renders the customer request area as a compact inbox plus active conversation workspace.
/// WHY: Customers should understand their queue state quickly, then focus on one live thread at a time.
/// HOW: Show request filters and a request list on the left, then render the selected request thread on the right.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/models/service_request_model.dart';
import '../../../core/network/api_client.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../shared/presentation/app_language_toggle.dart';
import '../../../shared/presentation/presence_chip.dart';
import '../../../shared/presentation/request_message_composer.dart';
import '../../../shared/presentation/request_thread_section.dart';
import '../../../shared/presentation/request_workflow_progress_bar.dart';
import '../../../shared/presentation/workspace_bottom_nav.dart';
import '../../../shared/presentation/workspace_profile_action_button.dart';
import '../../../shared/utils/external_url_opener.dart';
import '../../../shared/utils/payment_proof_picker.dart';
import '../../../shared/utils/payment_proof_picker_types.dart';
import '../../../shared/utils/request_attachment_flow_labels.dart';
import '../../../shared/utils/request_attachment_picker.dart';
import '../../../theme/app_theme.dart';
import '../../auth/application/auth_controller.dart';
import '../data/customer_repository.dart';

final customerRequestsProvider = FutureProvider<List<ServiceRequestModel>>((
  Ref ref,
) async {
  final customerId = ref.watch(
    authControllerProvider.select((state) => state.user?.id),
  );
  final role = ref.watch(authControllerProvider.select((state) => state.role));

  if (customerId == null || customerId.isEmpty || role != 'customer') {
    return const <ServiceRequestModel>[];
  }

  debugPrint(
    'customerRequestsProvider: fetching customer requests for $customerId',
  );
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
  final ScrollController _threadScrollController = ScrollController();
  final Map<String, TextEditingController> _messageControllers =
      <String, TextEditingController>{};
  final Map<String, DateTime> _lastViewedActivityByRequestId =
      <String, DateTime>{};
  final Set<String> _submittingMessageIds = <String>{};
  final Set<String> _uploadingAttachmentIds = <String>{};
  final Set<String> _refiningMessageIds = <String>{};
  final Set<String> _replacingAttachmentMessageIds = <String>{};
  final Set<String> _uploadingPaymentProofIds = <String>{};
  final Map<String, String> _dismissedInvoiceCardKeysByRequestId =
      <String, String>{};
  final Map<String, double?> _paymentProofUploadProgressByRequestId =
      <String, double?>{};
  final Map<String, String> _paymentProofUploadErrorsByRequestId =
      <String, String>{};
  final Set<String> _refreshingInvoiceIds = <String>{};
  String? _lastThreadScrollSignature;
  _CustomerInboxFilter _selectedFilter = _CustomerInboxFilter.all;
  _CustomerWorkspaceTab _selectedWorkspaceTab = _CustomerWorkspaceTab.inbox;
  String? _selectedRequestId;

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

        ref.invalidate(customerRequestsProvider);
      });
    });
  }

  String _t({required String en, required String de}) {
    return _language.pick(en: en, de: de);
  }

  String _serviceLabel(ServiceRequestModel request) {
    return request.serviceLabelForLanguage(_language);
  }

  String _requestInitials(String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      return 'U';
    }

    final parts = trimmedName.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first[0].toUpperCase();
    }

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  void dispose() {
    // WHY: Each visible request can own a composer controller, so they all need explicit cleanup when the screen leaves.
    for (final controller in _messageControllers.values) {
      controller.dispose();
    }
    _threadScrollController.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(String requestId) {
    // WHY: Request threads rebuild often, so keep one stable controller per request id instead of recreating on every frame.
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

  Future<void> _sendMessage(ServiceRequestModel request) async {
    final controller = _controllerFor(request.id);
    final text = controller.text.trim();

    // WHY: Ignore empty queue replies so customers cannot accidentally post blank thread messages.
    if (text.isEmpty) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
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
      await ref.read(customerRequestsProvider.future);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_sentMessageLabel(request))));
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

  Future<void> _refineDraftWithAi(ServiceRequestModel request) async {
    final controller = _controllerFor(request.id);
    if (_refiningMessageIds.contains(request.id)) {
      return;
    }

    final currentDraft = controller.text;
    setState(() => _refiningMessageIds.add(request.id));

    try {
      final suggestion = await ref
          .read(customerRepositoryProvider)
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
      return _t(
        en: 'This request is closed. The conversation stays here for reference.',
        de: 'Diese Anfrage ist geschlossen. Der Verlauf bleibt hier zur Referenz sichtbar.',
      );
    }

    if (request.assignedStaff != null) {
      final staffName = request.assignedStaff!.fullName;
      if (request.isAiInControl) {
        return _assignedStaffIsOnline(request)
            ? _t(
                en: 'Assigned to $staffName. Naima is covering the chat for now and $staffName can resume from the same thread.',
                de: '$staffName ist zugewiesen. Naima übernimmt den Chat vorübergehend und $staffName kann denselben Verlauf später fortsetzen.',
              )
            : _t(
                en: 'Assigned to $staffName. $staffName is offline right now, so Naima is holding the chat until staff resumes.',
                de: '$staffName ist zugewiesen. Momentan ist $staffName offline, deshalb hält Naima den Chat offen, bis das Team zurück ist.',
              );
      }

      final availability = _assignedStaffIsOnline(request)
          ? _t(en: 'online', de: 'online')
          : _t(en: 'offline', de: 'offline');
      return _t(
        en: 'Assigned to $staffName. Staff is currently $availability.',
        de: '$staffName ist zugewiesen. Das Team ist aktuell $availability.',
      );
    }

    return _t(
      en: 'Waiting in the live queue. Naima can answer quick questions and keep extra notes organised until a staff member joins.',
      de: 'Wartet in der Live-Queue. Naima beantwortet kurze Fragen und hält weitere Hinweise fest, bis ein Mitarbeiter übernimmt.',
    );
  }

  String _messagePreview(ServiceRequestModel request) {
    final latestMessage = request.latestMessage;
    if (latestMessage == null) {
      return request.message;
    }

    final senderPrefix = latestMessage.isCustomer
        ? _t(en: 'You', de: 'Sie')
        : latestMessage.senderName.isNotEmpty
        ? latestMessage.senderName
        : latestMessage.isAi
        ? 'KI'
        : latestMessage.isSystem
        ? _t(en: 'System', de: 'System')
        : _t(en: 'Staff', de: 'Team');

    final attachmentName = latestMessage.attachment == null
        ? null
        : requestAttachmentDisplayNameForMessage(
            latestMessage,
            language: ref.read(appLanguageProvider),
          );
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
    _lastThreadScrollSignature = null;
    setState(() {
      _selectedRequestId = request.id;
      _selectedWorkspaceTab = _CustomerWorkspaceTab.chat;
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
      if (!mounted || !_threadScrollController.hasClients) {
        return;
      }

      _threadScrollController.jumpTo(
        _threadScrollController.position.maxScrollExtent,
      );
    });
  }

  Future<void> _uploadPaymentProof(ServiceRequestModel request) async {
    final invoice = request.invoice;
    if (invoice == null || !invoice.canCustomerUploadProof) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    PickedPaymentProofFile? pickedFile;
    try {
      pickedFile = await pickPaymentProofFile();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _paymentProofUploadErrorsByRequestId[request.id] =
            _buildPaymentProofUploadPickerDebugMessage(
              error,
              requestId: request.id,
            );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not read the selected proof file. See the payment card for details.',
          ),
        ),
      );
      return;
    }

    if (pickedFile == null) {
      return;
    }
    final selectedFile = pickedFile;

    setState(() {
      _uploadingPaymentProofIds.add(request.id);
      _paymentProofUploadProgressByRequestId[request.id] = 0;
      _paymentProofUploadErrorsByRequestId.remove(request.id);
    });

    try {
      await ref
          .read(customerRepositoryProvider)
          .uploadPaymentProof(
            requestId: request.id,
            bytes: selectedFile.bytes,
            fileName: selectedFile.name,
            mimeType: selectedFile.mimeType,
            onSendProgress: (int sent, int total) {
              if (!mounted) {
                return;
              }

              final progress = total <= 0
                  ? null
                  : (sent / total).clamp(0.0, 1.0);
              setState(
                () => _paymentProofUploadProgressByRequestId[request.id] =
                    progress,
              );
            },
          );
      ref.invalidate(customerRequestsProvider);
      await ref.read(customerRequestsProvider.future);

      if (!mounted) {
        return;
      }

      setState(() {
        _paymentProofUploadErrorsByRequestId.remove(request.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            invoice.isSiteReview
                ? 'Site review payment proof sent to staff'
                : 'Quotation payment proof sent to staff',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      final failureSummary = _friendlyApiErrorMessage(error);
      setState(() {
        _paymentProofUploadErrorsByRequestId[request.id] =
            _buildPaymentProofUploadDebugMessage(
              error,
              requestId: request.id,
              fileName: selectedFile.name,
              mimeType: selectedFile.mimeType,
              sizeBytes: selectedFile.bytes.length,
            );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$failureSummary. See the payment card for details.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPaymentProofIds.remove(request.id);
          _paymentProofUploadProgressByRequestId.remove(request.id);
        });
      }
    }
  }

  String _friendlyApiErrorMessage(Object error) {
    if (error is ApiException) {
      final hint = error.resolutionHint?.trim() ?? '';
      if (hint.isNotEmpty) {
        return '${error.message}. $hint';
      }

      return error.message;
    }

    return error.toString().replaceFirst('Exception: ', '');
  }

  String _buildPaymentProofUploadDebugMessage(
    Object error, {
    required String requestId,
    required String fileName,
    required String mimeType,
    required int sizeBytes,
  }) {
    final details = <String>[
      if (error is ApiException)
        error.message
      else
        _friendlyApiErrorMessage(error),
      if (error is ApiException && error.debugSummary.isNotEmpty)
        error.debugSummary,
      'File: $fileName',
      'Mime: ${mimeType.trim().isEmpty ? 'unknown' : mimeType}',
      'Size: ${_formatUploadSize(sizeBytes)}',
      'Request: $requestId',
    ];

    return details.join('\n');
  }

  String _formatUploadSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '$bytes B';
  }

  String _buildPaymentProofUploadPickerDebugMessage(
    Object error, {
    required String requestId,
  }) {
    final details = <String>[
      'Proof picker failed before upload started.',
      _friendlyApiErrorMessage(error),
      'Request: $requestId',
    ];

    return details.join('\n');
  }

  Widget? _buildCustomerThreadMessageAction(
    ServiceRequestModel request,
    RequestMessageModel message,
  ) {
    final invoice = request.invoice;
    if (invoice == null || !message.isCustomerUploadPaymentProof) {
      if (request.status == 'closed' ||
          !message.isCustomer ||
          message.attachment == null ||
          message.isCustomerUploadPaymentProof) {
        return null;
      }

      final isReplacing = _replacingAttachmentMessageIds.contains(message.id);

      return OutlinedButton.icon(
        onPressed: isReplacing
            ? null
            : () => _replaceRequestAttachment(request, message),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        icon: isReplacing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.upload_file_outlined, size: 18),
        label: Text(isReplacing ? 'Updating file...' : 'Replace file'),
      );
    }

    if (invoice.isSiteReview) {
      return null;
    }

    return OutlinedButton.icon(
      onPressed: () => _openQuotationScreen(request),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      icon: const Icon(Icons.description_outlined, size: 18),
      label: const Text('View quotation'),
    );
  }

  String _invoiceCardDismissKey(RequestInvoiceModel invoice) {
    return <String>[
      invoice.invoiceNumber,
      invoice.status,
      invoice.proof?.relativeUrl ?? '',
      invoice.reviewedAt?.toIso8601String() ?? '',
      invoice.receiptIssuedAt?.toIso8601String() ?? '',
    ].join('|');
  }

  bool _shouldShowInvoiceCard(ServiceRequestModel request) {
    final invoice = request.invoice;
    if (invoice == null) {
      return false;
    }

    final dismissedKey = _dismissedInvoiceCardKeysByRequestId[request.id];
    if (dismissedKey == null) {
      return true;
    }

    return dismissedKey != _invoiceCardDismissKey(invoice);
  }

  Future<void> _refreshInvoiceStatus(ServiceRequestModel request) async {
    final invoice = request.invoice;
    if (invoice == null || !invoice.supportsOnlineCheckout) {
      return;
    }

    setState(() => _refreshingInvoiceIds.add(request.id));

    try {
      ref.invalidate(customerRequestsProvider);
      await ref.read(customerRequestsProvider.future);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Payment status refreshed')));
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
        setState(() => _refreshingInvoiceIds.remove(request.id));
      }
    }
  }

  Future<void> _openExternalPaymentUrl(
    String? url, {
    required String failureMessage,
  }) async {
    if (url == null || url.trim().isEmpty) {
      return;
    }

    final opened = await openExternalUrl(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  void _openQuotationScreen(ServiceRequestModel request) {
    context.push('/app/requests/${request.id}/quotation');
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
      await ref.read(customerRequestsProvider.future);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_sentAttachmentLabel(request))));
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

  Future<void> _replaceRequestAttachment(
    ServiceRequestModel request,
    RequestMessageModel message,
  ) async {
    if (request.status == 'closed' || message.attachment == null) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    final pickedFile = await pickRequestAttachmentFile();
    if (pickedFile == null) {
      return;
    }

    setState(() => _replacingAttachmentMessageIds.add(message.id));

    try {
      await ref
          .read(customerRepositoryProvider)
          .replaceRequestAttachment(
            requestId: request.id,
            messageId: message.id,
            bytes: pickedFile.bytes,
            fileName: pickedFile.name,
            mimeType: pickedFile.mimeType,
          );
      ref.invalidate(customerRequestsProvider);
      await ref.read(customerRequestsProvider.future);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File updated in chat')));
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
        setState(() => _replacingAttachmentMessageIds.remove(message.id));
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
      return _t(en: 'Staff replied', de: 'Team hat geantwortet');
    }

    if (latestMessage.isAdmin) {
      return _t(en: 'Admin replied', de: 'Admin hat geantwortet');
    }

    if (latestMessage.isAi) {
      return _t(en: 'AI update', de: 'KI-Update');
    }

    return _t(en: 'System alert', de: 'Systemhinweis');
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

  bool _assignedStaffIsOnline(ServiceRequestModel request) =>
      request.assignedStaff?.staffAvailability == 'online';

  String _assignedStaffPresenceLabel(ServiceRequestModel request) {
    final assignedStaff = request.assignedStaff;
    if (assignedStaff == null) {
      return '';
    }

    return _assignedStaffIsOnline(request)
        ? '${assignedStaff.fullName} ${_t(en: 'online', de: 'online')}'
        : '${assignedStaff.fullName} ${_t(en: 'offline', de: 'offline')}';
  }

  String _conversationSubtitle(ServiceRequestModel request) {
    final assignedStaff = request.assignedStaff;
    if (assignedStaff == null) {
      return _t(en: 'Queue conversation', de: 'Queue-Verlauf');
    }

    if (request.isAiInControl) {
      return _assignedStaffIsOnline(request)
          ? _t(
              en: 'Naima is covering for ${assignedStaff.fullName}',
              de: 'Naima übernimmt für ${assignedStaff.fullName}',
            )
          : _t(
              en: 'Naima is covering while ${assignedStaff.fullName} is offline',
              de: 'Naima übernimmt, solange ${assignedStaff.fullName} offline ist',
            );
    }

    return _t(
      en: 'Chat with ${assignedStaff.fullName}',
      de: 'Chat mit ${assignedStaff.fullName}',
    );
  }

  String _composerHintText(ServiceRequestModel request) {
    final assignedStaff = request.assignedStaff;
    if (assignedStaff == null) {
      return _t(
        en: 'Message the queue while you wait',
        de: 'Nachricht an die Queue senden, während Sie warten',
      );
    }

    if (request.isAiInControl) {
      return _assignedStaffIsOnline(request)
          ? _t(
              en: 'Ask Naima while ${assignedStaff.fullName} steps away',
              de: 'Fragen Sie Naima, solange ${assignedStaff.fullName} kurz weg ist',
            )
          : _t(
              en: 'Ask Naima while ${assignedStaff.fullName} is away',
              de: 'Fragen Sie Naima, solange ${assignedStaff.fullName} nicht da ist',
            );
    }

    return _t(
      en: 'Reply to ${assignedStaff.fullName}',
      de: 'An ${assignedStaff.fullName} antworten',
    );
  }

  String _composerButtonLabel(ServiceRequestModel request) {
    if (request.assignedStaff == null) {
      return _t(en: 'Send queue update', de: 'Queue-Update senden');
    }

    return request.isAiInControl
        ? _t(en: 'Ask Naima', de: 'Naima fragen')
        : _t(en: 'Reply to staff', de: 'An Team antworten');
  }

  String _sentMessageLabel(ServiceRequestModel request) {
    final assignedStaff = request.assignedStaff;
    if (assignedStaff == null) {
      return _t(
        en: 'Update added to the queue',
        de: 'Update zur Queue hinzugefügt',
      );
    }

    if (request.isAiInControl) {
      return _t(
        en: 'Message sent while Naima covers the chat',
        de: 'Nachricht gesendet, während Naima den Chat betreut',
      );
    }

    return _t(
      en: 'Message sent to ${assignedStaff.fullName}',
      de: 'Nachricht an ${assignedStaff.fullName} gesendet',
    );
  }

  String _sentAttachmentLabel(ServiceRequestModel request) {
    final assignedStaff = request.assignedStaff;
    if (assignedStaff == null) {
      return _t(
        en: 'File added to the queue',
        de: 'Datei zur Queue hinzugefügt',
      );
    }

    if (request.isAiInControl) {
      return _t(
        en: 'File sent while Naima covers the chat',
        de: 'Datei gesendet, während Naima den Chat betreut',
      );
    }

    return _t(
      en: 'File sent to ${assignedStaff.fullName}',
      de: 'Datei an ${assignedStaff.fullName} gesendet',
    );
  }

  Widget _buildAiCoverageChip(
    BuildContext context,
    ServiceRequestModel request, {
    bool compact = false,
  }) {
    final label = _assignedStaffIsOnline(request)
        ? 'Naima covering'
        : 'Naima active';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.cobalt.withValues(alpha: compact ? 0.18 : 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.cobalt.withValues(alpha: 0.34)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.auto_awesome_rounded,
              size: compact ? 13 : 14,
              color: Colors.white.withValues(alpha: 0.92),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
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

  RequestMessageModel? _latestCustomerUpdateRequestClearAction(
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
    final requestMessage = _latestCustomerUpdateRequestAction(request);
    if (requestMessage == null ||
        request.status == 'closed' ||
        request.invoice != null) {
      return false;
    }

    final clearMessage = _latestCustomerUpdateRequestClearAction(request);
    final requestCreatedAt = requestMessage.createdAt;
    final clearCreatedAt = clearMessage?.createdAt;

    if (requestCreatedAt == null) {
      return true;
    }

    if (clearCreatedAt == null) {
      return true;
    }

    return requestCreatedAt.isAfter(clearCreatedAt);
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
                color: _customerWorkspacePanelColor(),
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
                            _t(en: 'Request details', de: 'Anfragedetails'),
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
                      _serviceLabel(request),
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
                      if (request.isAiInControl) ...<Widget>[
                        const SizedBox(height: 8),
                        _buildAiCoverageChip(modalContext, request),
                      ],
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
                          ? _t(
                              en: 'Flexible time window',
                              de: 'Flexibles Zeitfenster',
                            )
                          : request.preferredTimeWindow,
                      accentColor: accent,
                      dark: true,
                    ),
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          _customerWorkspaceBottomColor(),
                          Colors.white,
                          0.04,
                        ),
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
                              label: _t(
                                en: 'Started ${_formatActionDateTime(request.projectStartedAt)}',
                                de: 'Begonnen ${_formatActionDateTime(request.projectStartedAt)}',
                              ),
                            ),
                          if (request.finishedAt != null)
                            _ConversationTimelinePill(
                              icon: Icons.task_alt_rounded,
                              label: _t(
                                en: 'Finished ${_formatActionDateTime(request.finishedAt)}',
                                de: 'Beendet ${_formatActionDateTime(request.finishedAt)}',
                              ),
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
        label: _t(en: 'Inbox', de: 'Postfach'),
        icon: Icons.chat_bubble_outline_rounded,
        badgeText: '${filteredRequests.length}',
      ),
      WorkspaceBottomNavItem(
        label: _t(en: 'Chat', de: 'Chat'),
        icon: Icons.forum_rounded,
      ),
    ];
  }

  IconData _serviceIcon(String serviceType) {
    return switch (serviceType) {
      'fire_damage_cleaning' => Icons.local_fire_department_rounded,
      'needle_sweeps_sharps_cleanups' => Icons.health_and_safety_rounded,
      'hoarding_cleanups' => Icons.inventory_2_rounded,
      'trauma_decomposition_cleanups' => Icons.healing_rounded,
      'infection_control_cleaning' => Icons.coronavirus_rounded,
      'building_cleaning' => Icons.apartment_rounded,
      'window_cleaning' => Icons.window_rounded,
      'office_cleaning' => Icons.business_center_rounded,
      'house_cleaning' => Icons.house_rounded,
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
      'fire_damage_cleaning' => const Color(0xFFC65A3A),
      'needle_sweeps_sharps_cleanups' => const Color(0xFF4B7A92),
      'hoarding_cleanups' => const Color(0xFF8A684E),
      'trauma_decomposition_cleanups' => const Color(0xFF6B5A88),
      'infection_control_cleaning' => const Color(0xFF2E7F73),
      'building_cleaning' => AppTheme.cobalt,
      'window_cleaning' => const Color(0xFF4A7FB9),
      'office_cleaning' => const Color(0xFF47668F),
      'house_cleaning' => const Color(0xFF6A6F90),
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
                            _serviceLabel(request),
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
                                  ? _t(en: 'Staff online', de: 'Team online')
                                  : _t(en: 'Staff offline', de: 'Team offline'),
                              isOnline: _assignedStaffIsOnline(request),
                              dark: true,
                              compact: true,
                            ),
                          if (request.assignedStaff != null &&
                              request.isAiInControl)
                            _buildAiCoverageChip(
                              context,
                              request,
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
    final chatTopColor = _customerWorkspaceTopColor();
    final chatBottomColor = _customerWorkspaceBottomColor();
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
        gradient: LinearGradient(
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
                        _t(en: 'My Requests', de: 'Meine Anfragen'),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _t(
                          en: 'Chat-style inbox for your active jobs and updates.',
                          de: 'Chat-Postfach fuer Ihre aktiven Einsaetze und Updates.',
                        ),
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
                    tooltip: _t(
                      en: 'Create new request',
                      de: 'Neue Anfrage erstellen',
                    ),
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
                _MiniCountPill(
                  label: _t(en: 'All', de: 'Alle'),
                  value: '${requests.length}',
                ),
                _MiniCountPill(
                  label: _t(en: 'Waiting', de: 'Wartend'),
                  value: '$waitingCount',
                ),
                _MiniCountPill(
                  label: _t(en: 'Live', de: 'Live'),
                  value: '$withStaffCount',
                ),
                _MiniCountPill(
                  label: _t(en: 'Closed', de: 'Geschlossen'),
                  value: '$closedCount',
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  _buildInboxFilterChip(
                    label: _t(en: 'All', de: 'Alle'),
                    isSelected: _selectedFilter == _CustomerInboxFilter.all,
                    onTap: () => setState(
                      () => _selectedFilter = _CustomerInboxFilter.all,
                    ),
                    count: requests.length,
                  ),
                  const SizedBox(width: 8),
                  _buildInboxFilterChip(
                    label: _t(en: 'Waiting', de: 'Wartend'),
                    isSelected: _selectedFilter == _CustomerInboxFilter.waiting,
                    onTap: () => setState(
                      () => _selectedFilter = _CustomerInboxFilter.waiting,
                    ),
                    count: waitingCount,
                  ),
                  const SizedBox(width: 8),
                  _buildInboxFilterChip(
                    label: _t(en: 'With Staff', de: 'Mit Team'),
                    isSelected:
                        _selectedFilter == _CustomerInboxFilter.withStaff,
                    onTap: () => setState(
                      () => _selectedFilter = _CustomerInboxFilter.withStaff,
                    ),
                    count: withStaffCount,
                  ),
                  const SizedBox(width: 8),
                  _buildInboxFilterChip(
                    label: _t(en: 'Closed', de: 'Geschlossen'),
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
                      label: _t(
                        en: 'No requests in this filter yet.',
                        de: 'Noch keine Anfragen in diesem Filter.',
                      ),
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
    final chatTopColor = _customerWorkspaceTopColor();
    final chatBottomColor = _customerWorkspaceBottomColor();

    if (request == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: chatBottomColor,
          gradient: LinearGradient(
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
              label: _t(
                en: 'Pick a request to open the chat, or create a new one to start a conversation.',
                de: 'Waehlen Sie eine Anfrage fuer den Chat oder erstellen Sie eine neue Unterhaltung.',
              ),
              onCreateRequest: () => context.go('/app/requests/new'),
              dark: true,
            ),
          ),
        ),
      );
    }

    final controller = _controllerFor(request.id);
    final isSubmitting = _submittingMessageIds.contains(request.id);
    final isRefiningMessage = _refiningMessageIds.contains(request.id);
    final isUploadingAttachment = _uploadingAttachmentIds.contains(request.id);
    final isComposerBusy =
        isSubmitting || isRefiningMessage || isUploadingAttachment;
    final accent = _serviceAccent(request.serviceType);
    final isCompact = MediaQuery.sizeOf(context).width < 760;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: chatBottomColor,
        gradient: LinearGradient(
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
            padding: EdgeInsets.fromLTRB(14, isCompact ? 8 : 10, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                InkWell(
                  onTap: () => _showRequestDetailsSheet(request),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        if (onBack != null) ...<Widget>[
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            visualDensity: VisualDensity.compact,
                            iconSize: 18,
                            onPressed: onBack,
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        SizedBox.square(
                          dimension: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _showRequestDetailsSheet(request),
                            icon: CircleAvatar(
                              radius: 14,
                              backgroundColor: accent.withValues(alpha: 0.18),
                              child: Text(
                                _requestInitials(request.contactFullName),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: accent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                _serviceLabel(request),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      height: 1.0,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _conversationSubtitle(request),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.62,
                                      ),
                                      fontWeight: FontWeight.w600,
                                      height: 1.0,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (request.assignedStaff != null) ...<Widget>[
                          const SizedBox(width: 6),
                          PresenceChip(
                            label: _assignedStaffIsOnline(request)
                                ? _t(en: 'Online', de: 'Online')
                                : _t(en: 'Offline', de: 'Offline'),
                            isOnline: _assignedStaffIsOnline(request),
                            dark: true,
                            compact: true,
                          ),
                        ],
                        const SizedBox(width: 6),
                        _CompactStatusPill(status: request.status),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                RequestWorkflowProgressBar(request: request, dark: true),
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
                          controller: _threadScrollController,
                          padding: EdgeInsets.fromLTRB(
                            edgeToEdge ? 14 : 18,
                            edgeToEdge ? 6 : 10,
                            edgeToEdge ? 14 : 18,
                            16,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              RequestThreadSection(
                                key: ValueKey<String>(request.id),
                                messages: request.messages,
                                viewerRole: 'customer',
                                dark: true,
                                emptyLabel: _t(
                                  en: 'No queue messages yet. New updates will appear here.',
                                  de: 'Noch keine Nachrichten in der Queue. Neue Updates erscheinen hier.',
                                ),
                                messageActionBuilder:
                                    (RequestMessageModel message) =>
                                        _buildCustomerThreadMessageAction(
                                          request,
                                          message,
                                        ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (request.status == 'closed')
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                          child: _ConversationMetaPill(
                            icon: Icons.lock_outline_rounded,
                            label: _t(
                              en: 'This request is closed. You can still read the full thread.',
                              de: 'Diese Anfrage ist geschlossen. Sie koennen den Verlauf weiter lesen.',
                            ),
                            accentColor: AppTheme.ink,
                            dark: true,
                          ),
                        ),
                      if (_hasPendingCustomerUpdateRequest(request))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: _CustomerConversationActionCard(
                            icon: Icons.edit_note_rounded,
                            title: _t(
                              en: 'Request details need an update',
                              de: 'Anfragedetails muessen aktualisiert werden',
                            ),
                            body: _t(
                              en: 'Staff asked you to revise the address, preferred date or time, or work scope.',
                              de: 'Das Team bittet um eine Anpassung von Adresse, Termin, Zeitfenster oder Leistungsumfang.',
                            ),
                            actionLabel: _t(
                              en: 'Update request',
                              de: 'Anfrage aktualisieren',
                            ),
                            accentColor: accent,
                            dark: true,
                            onPressed: () =>
                                context.go('/app/requests/${request.id}/edit'),
                          ),
                        ),
                      if (_shouldShowInvoiceCard(request))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: _CustomerPaymentCard(
                            invoice: request.invoice!,
                            dueDateLabel: _formatActionDate(
                              request.invoice!.dueDate,
                            ),
                            isUploadingProof: _uploadingPaymentProofIds
                                .contains(request.id),
                            uploadProgress:
                                _paymentProofUploadProgressByRequestId[request
                                    .id],
                            uploadErrorDetails:
                                _paymentProofUploadErrorsByRequestId[request
                                    .id],
                            isRefreshingStatus: _refreshingInvoiceIds.contains(
                              request.id,
                            ),
                            onDismissUploadError:
                                _paymentProofUploadErrorsByRequestId[request
                                        .id] !=
                                    null
                                ? () => setState(
                                    () => _paymentProofUploadErrorsByRequestId
                                        .remove(request.id),
                                  )
                                : null,
                            onDismissNotification:
                                request.invoice!.isProofSubmitted &&
                                    !_uploadingPaymentProofIds.contains(
                                      request.id,
                                    ) &&
                                    (_paymentProofUploadErrorsByRequestId[request
                                                .id]
                                            ?.trim()
                                            .isNotEmpty !=
                                        true)
                                ? () => setState(
                                    () =>
                                        _dismissedInvoiceCardKeysByRequestId[request
                                            .id] = _invoiceCardDismissKey(
                                          request.invoice!,
                                        ),
                                  )
                                : null,
                            onViewQuotation: () =>
                                _openQuotationScreen(request),
                            onUploadProof:
                                request.invoice!.canCustomerUploadProof
                                ? () => _uploadPaymentProof(request)
                                : null,
                            onPayOnline: request.invoice!.canCustomerPayOnline
                                ? () => _openExternalPaymentUrl(
                                    request.invoice!.paymentLinkUrl,
                                    failureMessage: _t(
                                      en: 'Opening the payment page is not supported here',
                                      de: 'Die Zahlungsseite kann hier nicht geoeffnet werden',
                                    ),
                                  )
                                : null,
                            onRefreshPaymentStatus:
                                request.invoice!.supportsOnlineCheckout &&
                                    !request.invoice!.isApproved
                                ? () => _refreshInvoiceStatus(request)
                                : null,
                            onOpenReceipt: request.invoice!.receiptUrl != null
                                ? () => _openExternalPaymentUrl(
                                    request.invoice!.receiptUrl,
                                    failureMessage: _t(
                                      en: 'Opening the receipt is not supported here',
                                      de: 'Der Beleg kann hier nicht geoeffnet werden',
                                    ),
                                  )
                                : null,
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
                              tooltip: _t(
                                en: isRefiningMessage
                                    ? 'Naima AI is refining your reply'
                                    : 'Naima AI can read this conversation and refine your reply',
                                de: isRefiningMessage
                                    ? 'Naima KI verfeinert gerade Ihre Antwort'
                                    : 'Naima KI kann diesen Verlauf lesen und Ihre Antwort verfeinern',
                              ),
                              dark: true,
                              icon: isRefiningMessage
                                  ? Icons.more_horiz_rounded
                                  : Icons.auto_awesome_rounded,
                              accentColor: AppTheme.pine,
                              onPressed:
                                  request.status == 'closed' || isComposerBusy
                                  ? null
                                  : () => _refineDraftWithAi(request),
                            ),
                            _ComposerQuickActionButton(
                              tooltip: _t(
                                en: 'Upload file',
                                de: 'Datei hochladen',
                              ),
                              dark: true,
                              icon: isUploadingAttachment
                                  ? Icons.more_horiz_rounded
                                  : Icons.attach_file_rounded,
                              onPressed:
                                  request.status == 'closed' || isComposerBusy
                                  ? null
                                  : () => _uploadRequestAttachment(request),
                            ),
                            if (_hasPendingPaymentProofUpload(request))
                              _ComposerQuickActionButton(
                                tooltip: _t(
                                  en: 'Upload payment proof',
                                  de: 'Zahlungsnachweis hochladen',
                                ),
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
                          hintText: _composerHintText(request),
                          buttonLabel: _composerButtonLabel(request),
                          isSubmitting: isComposerBusy,
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
    final language = ref.watch(appLanguageProvider);
    final authState = ref.watch(authControllerProvider);
    final requestsAsync = ref.watch(customerRequestsProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final canShowBottomNav = screenWidth < 980;
    final pageTopColor = _customerWorkspacePageTopColor();
    final pageMiddleColor = _customerWorkspacePageMiddleColor();
    final pageBottomColor = _customerWorkspacePageBottomColor();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${_t(en: 'My Requests', de: 'Meine Anfragen')} · ${authState.user?.firstName ?? _t(en: 'Customer', de: 'Kunde')}',
        ),
        backgroundColor: pageTopColor,
        surfaceTintColor: Colors.transparent,
        actions: <Widget>[
          WorkspaceCalendarActionButton(
            tooltip: _t(en: 'My calendar', de: 'Mein Kalender'),
            onPressed: () => context.go('/app/calendar'),
          ),
          WorkspaceProfileActionButton(
            tooltip: _t(en: 'My profile', de: 'Mein Profil'),
            onPressed: () => context.go('/app/profile'),
            displayName: authState.user?.fullName ?? '',
          ),
          AppLanguageToggle(
            language: language,
            onChanged: ref.read(appLanguageProvider.notifier).setLanguage,
            compact: true,
          ),
          IconButton(
            tooltip: _t(en: 'Create request', de: 'Anfrage erstellen'),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () => context.go('/app/requests/new'),
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          WorkspaceLogoutActionButton(
            tooltip: _t(en: 'Logout', de: 'Abmelden'),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) {
                context.go('/');
              }
            },
          ),
        ],
      ),
      backgroundColor: pageTopColor,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[pageTopColor, pageMiddleColor, pageBottomColor],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const <double>[0, 0.42, 1],
          ),
        ),
        child: Stack(
          children: <Widget>[
            Positioned(
              top: -120,
              right: -90,
              child: _WorkspaceBackdropGlow(
                diameter: 320,
                color: AppTheme.cobalt.withValues(alpha: 0.11),
              ),
            ),
            Positioned(
              top: 180,
              left: -110,
              child: _WorkspaceBackdropGlow(
                diameter: 260,
                color: Color.lerp(
                  AppTheme.cobalt,
                  Colors.white,
                  0.55,
                )!.withValues(alpha: 0.16),
              ),
            ),
            Positioned(
              bottom: -160,
              left: -70,
              child: _WorkspaceBackdropGlow(
                diameter: 250,
                color: AppTheme.clay.withValues(alpha: 0.22),
              ),
            ),
            requestsAsync.when(
              skipLoadingOnRefresh: true,
              skipLoadingOnReload: true,
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
                      _scheduleThreadScrollToLatest(selectedRequest);
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
                              child: _buildConversationPane(
                                context,
                                selectedRequest,
                              ),
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
              error: (Object error, StackTrace stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(error.toString()),
                    ),
                  ),
                ),
              ),
            ),
          ],
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

Color _customerWorkspaceTopColor() =>
    Color.lerp(AppTheme.ink, AppTheme.cobalt, 0.22)!;

Color _customerWorkspaceBottomColor() =>
    Color.lerp(AppTheme.ink, AppTheme.cobalt, 0.08)!;

Color _customerWorkspacePanelColor() =>
    Color.lerp(AppTheme.ink, AppTheme.cobalt, 0.16)!;

Color _customerWorkspacePageTopColor() =>
    Color.lerp(AppTheme.sand, AppTheme.cobalt, 0.12)!;

Color _customerWorkspacePageMiddleColor() =>
    Color.lerp(AppTheme.sand, AppTheme.ink, 0.07)!;

Color _customerWorkspacePageBottomColor() =>
    Color.lerp(AppTheme.sand, AppTheme.clay, 0.3)!;

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
                  ? Color.lerp(
                      _customerWorkspaceBottomColor(),
                      Colors.white,
                      0.04,
                    )!
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
        color: dark ? _customerWorkspacePanelColor() : Colors.white,
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
    this.onDismissNotification,
    this.onViewQuotation,
    this.onUploadProof,
    this.onPayOnline,
    this.onRefreshPaymentStatus,
    this.onOpenReceipt,
    this.uploadProgress,
    this.uploadErrorDetails,
    this.onDismissUploadError,
    this.isUploadingProof = false,
    this.isRefreshingStatus = false,
    this.dark = false,
  });

  final RequestInvoiceModel invoice;
  final String dueDateLabel;
  final VoidCallback? onDismissNotification;
  final VoidCallback? onViewQuotation;
  final VoidCallback? onUploadProof;
  final VoidCallback? onPayOnline;
  final VoidCallback? onRefreshPaymentStatus;
  final VoidCallback? onOpenReceipt;
  final double? uploadProgress;
  final String? uploadErrorDetails;
  final VoidCallback? onDismissUploadError;
  final bool isUploadingProof;
  final bool isRefreshingStatus;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final isSiteReview = invoice.isSiteReview;
    final title = isSiteReview
        ? 'Site review booking ${invoice.invoiceNumber}'
        : 'Quotation ${invoice.invoiceNumber}';
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
    final subtitle = invoice.isApproved
        ? (invoice.receiptUrl != null
              ? 'Payment received. Your receipt is ready below.'
              : isSiteReview
              ? 'Payment received. Staff approved the site review booking.'
              : 'Payment received. Staff has approved the quotation.')
        : invoice.canCustomerPayOnline
        ? (isSiteReview
              ? 'Use the secure checkout button below to pay for the site review booking. After payment, refresh the status here to pull the latest update.'
              : 'Use the secure checkout button below. After payment, refresh the status here to pull the latest update.')
        : invoice.isCustomerPaymentMethodLocked
        ? 'Payment option: ${invoice.paymentMethodLabel}. This payment channel is locked for customers right now. Customer care will confirm the next step.'
        : invoice.requiresCustomerProof
        ? (invoice.isProofSubmitted
              ? isSiteReview
                    ? 'Payment proof uploaded. Staff will review the site review booking here.'
                    : 'Payment proof uploaded. Staff will review it here.'
              : invoice.isRejected
              ? isSiteReview
                    ? 'Your last site review payment proof was rejected. Upload a fresh proof once the correction is ready.'
                    : 'Your last transfer proof was rejected. Upload a fresh proof once the correction is ready.'
              : invoice.isProofUploadExpired
              ? isSiteReview
                    ? 'The 24-hour proof window expired and the site review booking is now on hold. Contact customer care if it needs to be reopened.'
                    : 'The 24-hour proof window expired for this quotation payment. Contact customer care if it needs to be reopened.'
              : isSiteReview
              ? 'Pay by ${invoice.paymentMethodLabel} and upload your proof within 24 hours to keep the site review booking.'
              : 'Pay by ${invoice.paymentMethodLabel} and upload your transfer proof here once the payment is sent.')
        : 'Payment option: ${invoice.paymentMethodLabel}.';
    final amountAndDueLabel = isSiteReview
        ? '$amountLabel · review payment due $dueDateLabel'
        : '$amountLabel · due $dueDateLabel';
    final outlineButtonStyle = OutlinedButton.styleFrom(
      foregroundColor: dark ? Colors.white : AppTheme.ink,
      backgroundColor: dark
          ? Colors.white.withValues(alpha: 0.04)
          : AppTheme.cobalt.withValues(alpha: 0.04),
      side: BorderSide(
        color: dark
            ? Colors.white.withValues(alpha: 0.12)
            : AppTheme.cobalt.withValues(alpha: 0.18),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? _customerWorkspacePanelColor() : Colors.white,
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
                    title,
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
                if (onDismissNotification != null) ...<Widget>[
                  const SizedBox(width: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: dark
                          ? Colors.white.withValues(alpha: 0.06)
                          : AppTheme.cobalt.withValues(alpha: 0.06),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.08)
                            : AppTheme.cobalt.withValues(alpha: 0.16),
                      ),
                    ),
                    child: IconButton(
                      tooltip: 'Dismiss notification',
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onDismissNotification,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: dark
                            ? Colors.white.withValues(alpha: 0.88)
                            : AppTheme.ink,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              amountAndDueLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: dark
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppTheme.ink.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isSiteReview &&
                (invoice.siteReviewDate != null ||
                    invoice.siteReviewStartTime.trim().isNotEmpty ||
                    invoice.siteReviewEndTime.trim().isNotEmpty)) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: <Widget>[
                  if (invoice.siteReviewDate != null)
                    _PaymentMetaChip(
                      label:
                          'Review ${_CustomerRequestDateFormatter.date(invoice.siteReviewDate!)}',
                      dark: dark,
                    ),
                  if (invoice.siteReviewStartTime.trim().isNotEmpty ||
                      invoice.siteReviewEndTime.trim().isNotEmpty)
                    _PaymentMetaChip(
                      label:
                          'Time ${invoice.siteReviewStartTime.trim().isEmpty ? 'TBD' : invoice.siteReviewStartTime} - ${invoice.siteReviewEndTime.trim().isEmpty ? 'TBD' : invoice.siteReviewEndTime}',
                      dark: dark,
                    ),
                ],
              ),
            ],
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
            if (invoice.isProofUploadExpired &&
                !invoice.isProofUploadUnlocked &&
                invoice.requiresCustomerProof &&
                !invoice.isProofSubmitted &&
                !invoice.isApproved) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Proof upload is locked because the 24-hour window has expired. Customer care can reopen it if needed.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.ember,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
            if (invoice.paidAt != null ||
                invoice.paymentReference?.trim().isNotEmpty == true ||
                invoice.receiptNumber?.trim().isNotEmpty == true) ...<Widget>[
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: <Widget>[
                  if (invoice.paidAt != null)
                    _PaymentMetaChip(
                      label:
                          'Paid ${_CustomerRequestDateFormatter.dateTime(invoice.paidAt!)}',
                      dark: dark,
                    ),
                  if (invoice.paymentReference?.trim().isNotEmpty == true)
                    _PaymentMetaChip(
                      label: 'Ref ${invoice.paymentReference!}',
                      dark: dark,
                    ),
                  if (invoice.receiptNumber?.trim().isNotEmpty == true)
                    _PaymentMetaChip(
                      label: 'Receipt ${invoice.receiptNumber!}',
                      dark: dark,
                    ),
                ],
              ),
            ],
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
            if (isSiteReview &&
                invoice.siteReviewNotes.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Review notes: ${invoice.siteReviewNotes}',
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
            if (isUploadingProof) ...<Widget>[
              const SizedBox(height: 12),
              _CustomerUploadProgressCard(progress: uploadProgress, dark: dark),
            ],
            if (uploadErrorDetails?.trim().isNotEmpty == true) ...<Widget>[
              const SizedBox(height: 12),
              _CustomerUploadDebugCard(
                details: uploadErrorDetails!,
                dark: dark,
                onDismiss: onDismissUploadError,
              ),
            ],
            if (onPayOnline != null ||
                (onViewQuotation != null && !isSiteReview) ||
                onRefreshPaymentStatus != null ||
                onUploadProof != null ||
                onOpenReceipt != null) ...<Widget>[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  if (onViewQuotation != null && !isSiteReview)
                    OutlinedButton.icon(
                      onPressed: onViewQuotation,
                      style: outlineButtonStyle,
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('View quotation'),
                    ),
                  if (onPayOnline != null)
                    FilledButton.icon(
                      onPressed: onPayOnline,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.cobalt,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Pay online'),
                    ),
                  if (onRefreshPaymentStatus != null)
                    OutlinedButton.icon(
                      onPressed: isRefreshingStatus
                          ? null
                          : onRefreshPaymentStatus,
                      style: outlineButtonStyle,
                      icon: Icon(
                        isRefreshingStatus
                            ? Icons.more_horiz_rounded
                            : Icons.refresh_rounded,
                      ),
                      label: Text(
                        isRefreshingStatus ? 'Refreshing...' : 'Refresh status',
                      ),
                    ),
                  if (onUploadProof != null)
                    FilledButton.tonalIcon(
                      onPressed: isUploadingProof ? null : onUploadProof,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.ember.withValues(alpha: 0.18),
                        foregroundColor: dark ? Colors.white : AppTheme.ink,
                      ),
                      icon: Icon(
                        isUploadingProof
                            ? Icons.more_horiz_rounded
                            : Icons.upload_file_rounded,
                      ),
                      label: Text(
                        isUploadingProof ? 'Uploading...' : 'Upload proof',
                      ),
                    ),
                  if (onOpenReceipt != null)
                    OutlinedButton.icon(
                      onPressed: onOpenReceipt,
                      style: outlineButtonStyle,
                      icon: const Icon(Icons.receipt_long_rounded),
                      label: const Text('View receipt'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentMetaChip extends StatelessWidget {
  const _PaymentMetaChip({required this.label, required this.dark});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.06)
            : AppTheme.cobalt.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.1)
              : AppTheme.cobalt.withValues(alpha: 0.14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: dark
                ? Colors.white.withValues(alpha: 0.86)
                : AppTheme.ink.withValues(alpha: 0.82),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CustomerUploadProgressCard extends StatelessWidget {
  const _CustomerUploadProgressCard({
    required this.progress,
    required this.dark,
  });

  final double? progress;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final progressLabel = progress == null
        ? 'Preparing upload...'
        : '${(progress! * 100).round()}% uploaded';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.05)
            : AppTheme.cobalt.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.cobalt.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Uploading payment proof',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: dark ? Colors.white : AppTheme.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              progressLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: dark
                    ? Colors.white.withValues(alpha: 0.72)
                    : AppTheme.ink.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppTheme.cobalt.withValues(alpha: 0.12),
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.ember),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerUploadDebugCard extends StatelessWidget {
  const _CustomerUploadDebugCard({
    required this.details,
    required this.dark,
    this.onDismiss,
  });

  final String details;
  final bool dark;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF4B1F1B).withValues(alpha: dark ? 0.68 : 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE38B79).withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.bug_report_outlined, color: Color(0xFFFFB8A8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Upload failed',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    tooltip: 'Dismiss upload error',
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
              ],
            ),
            SelectableText(
              details,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                height: 1.4,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerRequestDateFormatter {
  static String date(DateTime value) {
    final localValue = value.toLocal();
    final day = localValue.day.toString().padLeft(2, '0');
    final month = localValue.month.toString().padLeft(2, '0');
    final year = localValue.year.toString();
    return '$day/$month/$year';
  }

  static String dateTime(DateTime value) {
    final localValue = value.toLocal();
    final day = localValue.day.toString().padLeft(2, '0');
    final month = localValue.month.toString().padLeft(2, '0');
    final year = localValue.year.toString();
    final hour = localValue.hour.toString().padLeft(2, '0');
    final minute = localValue.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
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
  const _RequestAvatar({required this.icon, required this.accentColor});

  final IconData icon;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
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
      child: Icon(icon, color: Colors.white, size: 21),
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
                ? Colors.white.withValues(alpha: 0.08)
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
                  backgroundColor: Color.lerp(
                    AppTheme.cobalt,
                    Colors.white,
                    0.08,
                  )!.withValues(alpha: 0.22),
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

class _WorkspaceBackdropGlow extends StatelessWidget {
  const _WorkspaceBackdropGlow({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color,
              blurRadius: diameter * 0.4,
              spreadRadius: diameter * 0.05,
            ),
          ],
        ),
      ),
    );
  }
}
