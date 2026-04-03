/// WHAT: Provides the presentational sections used by the admin workspace.
/// WHY: The admin dashboard now spans overview, queue, staff, and invite surfaces, so the UI should be split into smaller focused widgets.
/// HOW: Accept typed admin models plus small callbacks from the screen state and render queue-first workspace panels.
library;

import 'package:flutter/material.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/models/dashboard_models.dart';
import '../../../core/models/service_request_model.dart';
import '../../../shared/presentation/request_message_composer.dart';
import '../../../shared/presentation/request_thread_section.dart';
import '../../../shared/presentation/request_workflow_progress_bar.dart';
import '../../../shared/presentation/status_chip.dart';
import '../../../theme/app_theme.dart';

String _pick(AppLanguage language, {required String en, required String de}) {
  return language.pick(en: en, de: de);
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

String _adminStatusLabel(ServiceRequestModel request, AppLanguage language) {
  if (request.status == 'closed') {
    return _pick(language, en: 'delivered', de: 'Geliefert');
  }

  if (request.isQuoteReadyForInternalReview ||
      request.isQuoteReadyForCustomerCare) {
    return requestStatusLabelFor(request.status, language: language);
  }

  if (request.status == 'under_review' &&
      (request.isSiteReviewReadyForInternalReview ||
          request.isSiteReviewReadyForCustomerCare ||
          request.quoteReview?.isSiteReview == true ||
          (request.invoice?.isSiteReview == true &&
              request.isSiteReviewPending))) {
    return _pick(
      language,
      en: 'site review under review',
      de: 'Besichtigung in Pruefung',
    );
  }

  return requestStatusLabelFor(request.status, language: language);
}

class AdminRequestFilterChipData {
  const AdminRequestFilterChipData({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
}

class AdminOverviewSection extends StatelessWidget {
  const AdminOverviewSection({
    super.key,
    required this.language,
    required this.kpis,
    required this.recentRequests,
    required this.onOpenRequest,
    required this.onOpenQueue,
  });

  final AppLanguage language;
  final AdminKpis kpis;
  final List<ServiceRequestModel> recentRequests;
  final ValueChanged<ServiceRequestModel> onOpenRequest;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompact = constraints.maxWidth < 720;
        final metricWidth = isCompact ? (constraints.maxWidth - 16) / 2 : 200.0;

        return ListView(
          padding: const EdgeInsets.only(bottom: 124),
          children: <Widget>[
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: <Widget>[
                _MetricCard(
                  label: _pick(
                    language,
                    en: 'Total Requests',
                    de: 'Anfragen gesamt',
                  ),
                  value: '${kpis.totalRequests}',
                  width: metricWidth,
                ),
                _MetricCard(
                  label: _pick(
                    language,
                    en: 'Waiting Queue',
                    de: 'Warteschlange',
                  ),
                  value: '${kpis.waitingQueueCount}',
                  width: metricWidth,
                ),
                _MetricCard(
                  label: _pick(
                    language,
                    en: 'Active Queue',
                    de: 'Aktive Queue',
                  ),
                  value: '${kpis.activeQueueCount}',
                  width: metricWidth,
                ),
                _MetricCard(
                  label: _pick(language, en: 'Staff Online', de: 'Team online'),
                  value: '${kpis.staffOnlineCount}',
                  width: metricWidth,
                ),
                _MetricCard(
                  label: _pick(
                    language,
                    en: 'Pending Invites',
                    de: 'Offene Einladungen',
                  ),
                  value: '${kpis.pendingInvitesCount}',
                  width: metricWidth,
                ),
                _MetricCard(
                  label: _pick(
                    language,
                    en: 'Cleared Today',
                    de: 'Heute erledigt',
                  ),
                  value: '${kpis.clearedTodayCount}',
                  width: metricWidth,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _RecentQueueActivityPanel(
              language: language,
              requests: recentRequests,
              onOpenRequest: onOpenRequest,
              onOpenQueue: onOpenQueue,
            ),
          ],
        );
      },
    );
  }
}

class AdminQueueSidebar extends StatelessWidget {
  const AdminQueueSidebar({
    super.key,
    required this.language,
    required this.searchController,
    required this.onApplySearch,
    required this.onClearSearch,
    required this.filterChips,
    required this.requests,
    required this.selectedRequestId,
    required this.onSelectRequest,
    this.edgeToEdge = false,
  });

  final AppLanguage language;
  final TextEditingController searchController;
  final VoidCallback onApplySearch;
  final VoidCallback onClearSearch;
  final List<AdminRequestFilterChipData> filterChips;
  final List<ServiceRequestModel> requests;
  final String? selectedRequestId;
  final ValueChanged<ServiceRequestModel> onSelectRequest;
  final bool edgeToEdge;

  @override
  Widget build(BuildContext context) {
    final BorderRadius? surfaceRadius = edgeToEdge
        ? null
        : BorderRadius.circular(30);

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
          edgeToEdge ? 8 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _pick(language, en: 'Admin queue', de: 'Admin-Warteschlange'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _pick(
                language,
                en: 'Find the right customer thread fast, then open the full queue conversation on the right.',
                de: 'Finden Sie schnell den passenden Kunden-Chat und öffnen Sie rechts den vollständigen Verlauf.',
              ),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onApplySearch(),
              decoration: InputDecoration(
                hintText: _pick(
                  language,
                  en: 'Search customer, email, or city',
                  de: 'Kunde, E-Mail oder Stadt suchen',
                ),
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.48),
                ),
                suffixIcon: searchController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: _pick(
                          language,
                          en: 'Clear search',
                          de: 'Suche leeren',
                        ),
                        onPressed: onClearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: AppTheme.cobalt.withValues(alpha: 0.52),
                  ),
                ),
              ),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.88)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: filterChips.map((chip) {
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: chip.onTap,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: chip.isSelected
                          ? AppTheme.cobalt
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: chip.isSelected
                            ? AppTheme.cobalt
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
                            chip.label,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: chip.isSelected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.82),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(width: 8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: chip.isSelected
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
                                '${chip.count}',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: chip.isSelected
                                          ? Colors.white
                                          : Colors.white.withValues(
                                              alpha: 0.82,
                                            ),
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
              }).toList(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: requests.isEmpty
                  ? Center(
                      child: _AdminEmptyState(
                        icon: Icons.inbox_outlined,
                        label: _pick(
                          language,
                          en: 'No request threads match this filter.',
                          de: 'Keine Anfrageverläufe passen zu diesem Filter.',
                        ),
                        dark: true,
                      ),
                    )
                  : ListView.separated(
                      itemCount: requests.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final request = requests[index];
                        final isSelected = request.id == selectedRequestId;

                        return InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => onSelectRequest(request),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Color.alphaBlend(
                                      AppTheme.cobalt.withValues(alpha: 0.14),
                                      const Color(0xFF16191E),
                                    )
                                  : const Color(0xFF15171A),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.cobalt.withValues(alpha: 0.35)
                                    : Colors.white.withValues(alpha: 0.06),
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: isSelected ? 0.22 : 0.14,
                                  ),
                                  blurRadius: isSelected ? 24 : 18,
                                  offset: const Offset(0, 12),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          request.serviceLabelForLanguage(
                                            language,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      StatusChip(
                                        status: request.status,
                                        labelOverride: _adminStatusLabel(
                                          request,
                                          language,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${request.contactFullName} · ${request.city}',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.62,
                                          ),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _messagePreview(request),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.74,
                                          ),
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _pick(
                                      language,
                                      en: '${request.messageCount} messages',
                                      de: '${request.messageCount} Nachrichten',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.54,
                                          ),
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _messagePreview(ServiceRequestModel request) {
    if (request.messages.isEmpty) {
      return request.message;
    }

    final latestMessage = request.messages.last;
    return '${latestMessage.senderName}: ${latestMessage.text}';
  }
}

class AdminRequestDetailPane extends StatelessWidget {
  const AdminRequestDetailPane({
    super.key,
    required this.language,
    required this.request,
    required this.staff,
    this.edgeToEdge = false,
    required this.onAssignToStaff,
    required this.selectedAssignmentId,
    required this.onAssignmentChanged,
    required this.onAssign,
    required this.isAssigning,
    required this.onSendInvoice,
    required this.onDeliverRequest,
    required this.onOpenPaymentProof,
    required this.onOpenReceipt,
    required this.onApprovePaymentProof,
    required this.onRejectPaymentProof,
    required this.isSendingInvoice,
    required this.isDeliveringRequest,
    required this.isReviewingPaymentProof,
    required this.messageController,
    required this.isSendingMessage,
    required this.isUploadingAttachment,
    required this.composerEnabled,
    required this.onSendMessage,
    required this.onUploadAttachment,
    required this.threadScrollController,
    this.onBack,
  });

  final AppLanguage language;
  final ServiceRequestModel? request;
  final List<StaffMemberSummary> staff;
  final bool edgeToEdge;
  final Future<void> Function(String staffId)? onAssignToStaff;
  final String? selectedAssignmentId;
  final ValueChanged<String?> onAssignmentChanged;
  final VoidCallback? onAssign;
  final bool isAssigning;
  final VoidCallback? onSendInvoice;
  final VoidCallback? onDeliverRequest;
  final VoidCallback? onOpenPaymentProof;
  final VoidCallback? onOpenReceipt;
  final VoidCallback? onApprovePaymentProof;
  final VoidCallback? onRejectPaymentProof;
  final bool isSendingInvoice;
  final bool isDeliveringRequest;
  final bool isReviewingPaymentProof;
  final TextEditingController? messageController;
  final bool isSendingMessage;
  final bool isUploadingAttachment;
  final bool composerEnabled;
  final VoidCallback? onSendMessage;
  final VoidCallback? onUploadAttachment;
  final ScrollController threadScrollController;
  final VoidCallback? onBack;

  Future<void> _showAssignmentSheet(
    BuildContext context,
    ServiceRequestModel request,
  ) async {
    final assignableStaff = staff
        .where((person) => person.staffType != 'customer_care')
        .toList();
    String? localSelection = selectedAssignmentId ?? request.assignedStaff?.id;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        return StatefulBuilder(
          builder: (BuildContext modalContext, StateSetter setModalState) {
            return _AdminSheetCard(
              title: _pick(language, en: 'Assignment', de: 'Zuweisung'),
              subtitle: _pick(
                language,
                en: 'Assign this customer to staff without crowding the chat view.',
                de: 'Weisen Sie diesen Kunden dem Team zu, ohne die Chatansicht zu überladen.',
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (assignableStaff.isEmpty)
                    Text(
                      _pick(
                        language,
                        en: 'No technician or contractor accounts are available for assignment yet.',
                        de: 'Derzeit sind keine Techniker- oder Auftragnehmerkonten für eine Zuweisung verfügbar.',
                      ),
                      style: Theme.of(modalContext).textTheme.bodyMedium
                          ?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                    )
                  else ...<Widget>[
                    DropdownButtonFormField<String>(
                      initialValue: localSelection,
                      decoration: InputDecoration(
                        labelText: _pick(
                          language,
                          en: 'Assign to staff',
                          de: 'Team zuweisen',
                        ),
                      ),
                      items: assignableStaff
                          .map(
                            (person) => DropdownMenuItem<String>(
                              value: person.id,
                              child: Text(
                                '${person.fullName} · ${person.staffTypeLabel} · ${person.staffAvailability ?? 'offline'} · ${person.assignedOpenRequestCount} open',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) {
                        setModalState(() => localSelection = value);
                        onAssignmentChanged(value);
                      },
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed:
                            localSelection == null ||
                                onAssignToStaff == null ||
                                isAssigning
                            ? null
                            : () async {
                                await onAssignToStaff!(localSelection!);
                                if (modalContext.mounted) {
                                  Navigator.of(modalContext).pop();
                                }
                              },
                        child: Text(
                          isAssigning
                              ? _pick(
                                  language,
                                  en: 'Assigning...',
                                  de: 'Wird zugewiesen...',
                                )
                              : _pick(
                                  language,
                                  en: 'Assign request',
                                  de: 'Anfrage zuweisen',
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showProfileSheet(
    BuildContext context,
    ServiceRequestModel request,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        Future<void> openAssignment() async {
          Navigator.of(modalContext).pop();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (context.mounted) {
            await _showAssignmentSheet(context, request);
          }
        }

        Future<void> openBilling() async {
          Navigator.of(modalContext).pop();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (context.mounted && onSendInvoice != null) {
            onSendInvoice!();
          }
        }

        Future<void> openDelivery() async {
          Navigator.of(modalContext).pop();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (context.mounted && onDeliverRequest != null) {
            onDeliverRequest!();
          }
        }

        final canDeliver = onDeliverRequest != null;
        final actionLabel = canDeliver
            ? _pick(language, en: 'Deliver', de: 'Liefern')
            : _pick(language, en: 'Internal review', de: 'Interne Prüfung');
        final actionIcon = canDeliver
            ? Icons.local_shipping_outlined
            : Icons.receipt_long_rounded;
        final actionCallback = canDeliver
            ? (isDeliveringRequest ? null : openDelivery)
            : (onSendInvoice == null || isSendingInvoice ? null : openBilling);

        return _AdminSheetCard(
          title:
              '${request.contactFullName} ${_pick(language, en: 'profile', de: 'Profil')}',
          subtitle: _pick(
            language,
            en: 'Keep the chat clear and open the full customer/request context only when needed.',
            de: 'Halten Sie den Chat übersichtlich und öffnen Sie den vollständigen Kunden- und Anfragekontext nur bei Bedarf.',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: <Widget>[
                  _MetaChip(
                    icon: Icons.mail_outline_rounded,
                    label: request.contactEmail,
                    dark: true,
                  ),
                  _MetaChip(
                    icon: Icons.call_outlined,
                    label: request.contactPhone,
                    dark: true,
                  ),
                  _MetaChip(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: _pick(
                      language,
                      en: '${request.messageCount} messages',
                      de: '${request.messageCount} Nachrichten',
                    ),
                    dark: true,
                  ),
                ],
              ),
              if (request.projectStartedAt != null ||
                  request.finishedAt != null) ...<Widget>[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    if (request.projectStartedAt != null)
                      _MetaChip(
                        icon: Icons.play_circle_outline_rounded,
                        label: _pick(
                          language,
                          en: 'Started ${_formatDateTime(request.projectStartedAt)}',
                          de: 'Gestartet ${_formatDateTime(request.projectStartedAt)}',
                        ),
                        dark: true,
                      ),
                    if (request.finishedAt != null)
                      _MetaChip(
                        icon: Icons.task_alt_rounded,
                        label: _pick(
                          language,
                          en: 'Finished ${_formatDateTime(request.finishedAt)}',
                          de: 'Abgeschlossen ${_formatDateTime(request.finishedAt)}',
                        ),
                        dark: true,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    request.message,
                    style: Theme.of(modalContext).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.86),
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  _AdminDetailActionButton(
                    icon: Icons.assignment_ind_rounded,
                    label: _pick(language, en: 'Assignment', de: 'Zuweisung'),
                    onPressed: openAssignment,
                  ),
                  _AdminDetailActionButton(
                    icon: actionIcon,
                    label: isDeliveringRequest
                        ? _pick(
                            language,
                            en: 'Delivering...',
                            de: 'Wird geliefert...',
                          )
                        : isSendingInvoice
                        ? _pick(
                            language,
                            en: 'Opening review...',
                            de: 'Prüfung wird geöffnet...',
                          )
                        : actionLabel,
                    onPressed: actionCallback,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 720;
    final BorderRadius? surfaceRadius = edgeToEdge
        ? null
        : BorderRadius.circular(30);

    if (request == null) {
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
        ),
        child: Center(
          child: _AdminEmptyState(
            icon: Icons.chat_bubble_outline_rounded,
            label: _pick(
              language,
              en: 'Pick a customer thread to review the full queue context.',
              de: 'Wählen Sie einen Kunden-Chat, um den vollständigen Anfragekontext zu prüfen.',
            ),
            dark: true,
          ),
        ),
      );
    }

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
      child: Column(
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 14 : 22,
              isCompact ? 14 : 20,
              isCompact ? 14 : 22,
              isCompact ? 12 : 18,
            ),
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
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: Text(
                        _pick(language, en: 'Back to queue', de: 'Zur Queue'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    SizedBox.square(
                      dimension: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _showProfileSheet(context, request!),
                        icon: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppTheme.cobalt.withValues(
                            alpha: 0.15,
                          ),
                          child: Text(
                            _requestInitials(request!.contactFullName),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AppTheme.cobalt,
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
                            request!.contactFullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${request!.serviceLabelForLanguage(language)} · ${request!.city}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.62),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _AdminHeaderActionButton(
                      icon: onDeliverRequest != null
                          ? Icons.local_shipping_outlined
                          : Icons.receipt_long_rounded,
                      label: onDeliverRequest != null
                          ? _pick(
                              language,
                              en: isCompact
                                  ? (isDeliveringRequest
                                        ? 'Delivering'
                                        : 'Deliver')
                                  : (isDeliveringRequest
                                        ? 'Delivering...'
                                        : 'Deliver'),
                              de: isCompact
                                  ? (isDeliveringRequest
                                        ? 'Lieferung'
                                        : 'Liefern')
                                  : (isDeliveringRequest
                                        ? 'Wird geliefert...'
                                        : 'Liefern'),
                            )
                          : _pick(
                              language,
                              en: isCompact ? 'Review' : 'Internal review',
                              de: isCompact ? 'Pruefen' : 'Interne Pruefung',
                            ),
                      onPressed: onDeliverRequest != null
                          ? (isDeliveringRequest ? null : onDeliverRequest)
                          : (isSendingInvoice ? null : onSendInvoice),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(
                      status: request!.status,
                      compact: true,
                      labelOverride: _adminStatusLabel(request!, language),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                RequestWorkflowProgressBar(request: request!, dark: true),
              ],
            ),
          ),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    AppTheme.darkSurface,
                    AppTheme.ember.withValues(alpha: 0.08),
                    AppTheme.darkPage,
                  ],
                ),
              ),
              child: SingleChildScrollView(
                controller: threadScrollController,
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    RequestThreadSection(
                      key: ValueKey<String>(request!.id),
                      messages: request!.messages,
                      viewerRole: 'admin',
                      dark: true,
                      emptyLabel: _pick(
                        language,
                        en: 'No thread messages yet.',
                        de: 'Noch keine Nachrichten im Verlauf.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 14 : 18,
              0,
              isCompact ? 14 : 18,
              isCompact ? 14 : 18,
            ),
            child: RequestMessageComposer(
              controller: messageController ?? TextEditingController(),
              leadingActions: <Widget>[
                _AdminComposerActionButton(
                  tooltip: _pick(
                    language,
                    en: 'Upload file',
                    de: 'Datei hochladen',
                  ),
                  icon: isUploadingAttachment
                      ? Icons.more_horiz_rounded
                      : Icons.attach_file_rounded,
                  onPressed: !composerEnabled || isUploadingAttachment
                      ? null
                      : onUploadAttachment,
                ),
              ],
              hintText: composerEnabled
                  ? _pick(
                      language,
                      en: 'Reply to the customer here',
                      de: 'Hier dem Kunden antworten',
                    )
                  : _pick(
                      language,
                      en: 'Closed requests cannot accept new replies',
                      de: 'Geschlossene Anfragen nehmen keine neuen Antworten an',
                    ),
              buttonLabel: _pick(
                language,
                en: 'Send reply',
                de: 'Antwort senden',
              ),
              isSubmitting: isSendingMessage,
              isEnabled: composerEnabled,
              onSubmit: onSendMessage ?? () {},
              dark: true,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '';
    }

    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

class _AdminComposerActionButton extends StatelessWidget {
  const _AdminComposerActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
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
          color: Colors.white.withValues(alpha: onPressed == null ? 0.38 : 0.9),
        ),
      ),
    );
  }
}

enum _AdminStaffRoleFilter { all, customerCare, technician, contractor }

enum _AdminStaffAvailabilityFilter { all, online, offline }

class AdminStaffSection extends StatefulWidget {
  const AdminStaffSection({
    super.key,
    required this.language,
    required this.staff,
  });

  final AppLanguage language;
  final List<StaffMemberSummary> staff;

  @override
  State<AdminStaffSection> createState() => _AdminStaffSectionState();
}

class _AdminStaffSectionState extends State<AdminStaffSection> {
  _AdminStaffRoleFilter _selectedRoleFilter = _AdminStaffRoleFilter.all;
  _AdminStaffAvailabilityFilter _selectedAvailabilityFilter =
      _AdminStaffAvailabilityFilter.all;

  bool _matchesRoleFilter(StaffMemberSummary person) {
    switch (_selectedRoleFilter) {
      case _AdminStaffRoleFilter.customerCare:
        return person.staffType == 'customer_care';
      case _AdminStaffRoleFilter.technician:
        return person.staffType == 'technician';
      case _AdminStaffRoleFilter.contractor:
        return person.staffType == 'contractor';
      case _AdminStaffRoleFilter.all:
        return true;
    }
  }

  bool _matchesAvailabilityFilter(StaffMemberSummary person) {
    final availability = person.staffAvailability ?? 'offline';

    switch (_selectedAvailabilityFilter) {
      case _AdminStaffAvailabilityFilter.online:
        return availability == 'online';
      case _AdminStaffAvailabilityFilter.offline:
        return availability != 'online';
      case _AdminStaffAvailabilityFilter.all:
        return true;
    }
  }

  String _roleFilterLabel(AppLanguage language, _AdminStaffRoleFilter filter) {
    switch (filter) {
      case _AdminStaffRoleFilter.customerCare:
        return _pick(language, en: 'Customer care', de: 'Customer Care');
      case _AdminStaffRoleFilter.technician:
        return _pick(language, en: 'Technicians', de: 'Techniker');
      case _AdminStaffRoleFilter.contractor:
        return _pick(language, en: 'Contractors', de: 'Auftragnehmer');
      case _AdminStaffRoleFilter.all:
        return _pick(language, en: 'All staff', de: 'Gesamtes Team');
    }
  }

  int _roleFilterCount(
    List<StaffMemberSummary> staff,
    _AdminStaffRoleFilter filter,
  ) {
    switch (filter) {
      case _AdminStaffRoleFilter.customerCare:
        return staff
            .where((person) => person.staffType == 'customer_care')
            .length;
      case _AdminStaffRoleFilter.technician:
        return staff.where((person) => person.staffType == 'technician').length;
      case _AdminStaffRoleFilter.contractor:
        return staff.where((person) => person.staffType == 'contractor').length;
      case _AdminStaffRoleFilter.all:
        return staff.length;
    }
  }

  String _availabilityFilterLabel(
    AppLanguage language,
    _AdminStaffAvailabilityFilter filter,
  ) {
    switch (filter) {
      case _AdminStaffAvailabilityFilter.online:
        return _pick(language, en: 'Online', de: 'Online');
      case _AdminStaffAvailabilityFilter.offline:
        return _pick(language, en: 'Offline', de: 'Offline');
      case _AdminStaffAvailabilityFilter.all:
        return _pick(language, en: 'All statuses', de: 'Alle Status');
    }
  }

  int _availabilityFilterCount(
    List<StaffMemberSummary> staff,
    _AdminStaffAvailabilityFilter filter,
  ) {
    switch (filter) {
      case _AdminStaffAvailabilityFilter.online:
        return staff
            .where(
              (person) => (person.staffAvailability ?? 'offline') == 'online',
            )
            .length;
      case _AdminStaffAvailabilityFilter.offline:
        return staff
            .where(
              (person) => (person.staffAvailability ?? 'offline') != 'online',
            )
            .length;
      case _AdminStaffAvailabilityFilter.all:
        return staff.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final staff = widget.staff;
    final filteredStaff = staff
        .where(_matchesRoleFilter)
        .where(_matchesAvailabilityFilter)
        .toList();
    final sortedStaff = <StaffMemberSummary>[...filteredStaff]
      ..sort((a, b) {
        final aOnline = (a.staffAvailability ?? 'offline') == 'online' ? 0 : 1;
        final bOnline = (b.staffAvailability ?? 'offline') == 'online' ? 0 : 1;
        if (aOnline != bOnline) {
          return aOnline.compareTo(bOnline);
        }

        final loadCompare = b.assignedOpenRequestCount.compareTo(
          a.assignedOpenRequestCount,
        );
        if (loadCompare != 0) {
          return loadCompare;
        }

        return a.fullName.compareTo(b.fullName);
      });
    final onlineCount = sortedStaff.where((person) {
      return (person.staffAvailability ?? 'offline') == 'online';
    }).length;

    if (staff.isEmpty) {
      return _AdminOverviewPanel(
        title: _pick(language, en: 'Team', de: 'Team'),
        subtitle: _pick(
          language,
          en: 'No active staff accounts exist yet. Create an invite to onboard someone.',
          de: 'Es gibt noch keine aktiven Teamkonten. Erstellen Sie eine Einladung, um jemanden aufzunehmen.',
        ),
        child: _AdminEmptyState(
          icon: Icons.group_outlined,
          label: _pick(
            language,
            en: 'No staff accounts added yet.',
            de: 'Es wurden noch keine Teamkonten hinzugefügt.',
          ),
          dark: true,
        ),
      );
    }

    return _AdminOverviewPanel(
      title: _pick(language, en: 'Team', de: 'Team'),
      subtitle: _pick(
        language,
        en: 'Track staff availability, open queue load, and how much work each person cleared today.',
        de: 'Behalten Sie Teamverfügbarkeit, offene Queue-Last und heutige Abschlüsse im Blick.',
      ),
      child: Column(
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _AdminSummaryChip(
                icon: Icons.group_rounded,
                label: _pick(
                  language,
                  en: '${sortedStaff.length} shown',
                  de: '${sortedStaff.length} sichtbar',
                ),
              ),
              _AdminSummaryChip(
                icon: Icons.circle,
                label: _pick(
                  language,
                  en: '$onlineCount online',
                  de: '$onlineCount online',
                ),
                accentColor: AppTheme.pine,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _pick(language, en: 'Filter by role', de: 'Nach Rolle filtern'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.78),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _AdminStaffRoleFilter.values.map((filter) {
              final isSelected = filter == _selectedRoleFilter;
              return _AdminFilterChip(
                label:
                    '${_roleFilterLabel(language, filter)} (${_roleFilterCount(staff, filter)})',
                selected: isSelected,
                accentColor: AppTheme.cobalt,
                onTap: () => setState(() => _selectedRoleFilter = filter),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _pick(
                language,
                en: 'Filter by availability',
                de: 'Nach Verfügbarkeit filtern',
              ),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.78),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _AdminStaffAvailabilityFilter.values.map((filter) {
              final isSelected = filter == _selectedAvailabilityFilter;
              return _AdminFilterChip(
                label:
                    '${_availabilityFilterLabel(language, filter)} (${_availabilityFilterCount(staff, filter)})',
                selected: isSelected,
                accentColor: AppTheme.pine,
                onTap: () =>
                    setState(() => _selectedAvailabilityFilter = filter),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (sortedStaff.isEmpty)
            _AdminEmptyState(
              icon: Icons.filter_alt_off_rounded,
              label: _pick(
                language,
                en: 'No staff match this filter set yet.',
                de: 'Für diese Filter gibt es noch keine Teammitglieder.',
              ),
              dark: true,
            )
          else
            ...sortedStaff.map((person) {
              final availability = person.staffAvailability ?? 'offline';
              final isOnline = availability == 'online';

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    child: Row(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          child: Text(
                            person.fullName.trim().isEmpty
                                ? '?'
                                : person.fullName.trim()[0].toUpperCase(),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                person.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                person.staffTypeLabel,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppTheme.mist,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _pick(
                                  language,
                                  en: '${person.assignedOpenRequestCount} open · ${person.clearedTodayCount} cleared today',
                                  de: '${person.assignedOpenRequestCount} offen · ${person.clearedTodayCount} heute erledigt',
                                ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.62,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _AdminPresenceChip(
                          label: isOnline
                              ? _pick(language, en: 'online', de: 'online')
                              : _pick(language, en: 'offline', de: 'offline'),
                          online: isOnline,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class AdminInvitesSection extends StatelessWidget {
  const AdminInvitesSection({
    super.key,
    required this.language,
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.phoneController,
    required this.inviteStaffType,
    required this.isInviteSubmitting,
    required this.onInviteStaffTypeChanged,
    required this.onSubmitInvite,
    required this.invites,
    required this.inviteIdsBeingDeleted,
    required this.onCopyInvite,
    required this.onDeleteInvite,
  });

  final AppLanguage language;
  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final String inviteStaffType;
  final bool isInviteSubmitting;
  final ValueChanged<String?> onInviteStaffTypeChanged;
  final VoidCallback onSubmitInvite;
  final List<StaffInviteModel> invites;
  final Set<String> inviteIdsBeingDeleted;
  final ValueChanged<String> onCopyInvite;
  final ValueChanged<StaffInviteModel> onDeleteInvite;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyLarge?.copyWith(color: Colors.white);

    return ListView(
      padding: const EdgeInsets.only(bottom: 124),
      children: <Widget>[
        _AdminOverviewPanel(
          title: _pick(
            language,
            en: 'Create staff invite',
            de: 'Teameinladung erstellen',
          ),
          subtitle: _pick(
            language,
            en: 'Generate a copyable link and share it outside the app.',
            de: 'Erstellen Sie einen kopierbaren Link und teilen Sie ihn außerhalb der App.',
          ),
          child: Column(
            children: <Widget>[
              TextField(
                controller: firstNameController,
                style: textStyle,
                decoration: _adminDarkInputDecoration(
                  _pick(language, en: 'First name', de: 'Vorname'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastNameController,
                style: textStyle,
                decoration: _adminDarkInputDecoration(
                  _pick(language, en: 'Last name', de: 'Nachname'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                style: textStyle,
                decoration: _adminDarkInputDecoration(
                  _pick(language, en: 'Email', de: 'E-Mail'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                style: textStyle,
                decoration: _adminDarkInputDecoration(
                  _pick(language, en: 'Phone', de: 'Telefon'),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: inviteStaffType,
                dropdownColor: AppTheme.darkPageRaised,
                style: textStyle,
                decoration: _adminDarkInputDecoration(
                  _pick(language, en: 'Staff type', de: 'Mitarbeitertyp'),
                ),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: 'customer_care',
                    child: Text('Customer Care'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'technician',
                    child: Text('Technician'),
                  ),
                  DropdownMenuItem<String>(
                    value: 'contractor',
                    child: Text('Contractor'),
                  ),
                ],
                onChanged: isInviteSubmitting ? null : onInviteStaffTypeChanged,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.cobalt,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: isInviteSubmitting ? null : onSubmitInvite,
                  child: Text(
                    isInviteSubmitting
                        ? _pick(
                            language,
                            en: 'Creating...',
                            de: 'Wird erstellt...',
                          )
                        : _pick(
                            language,
                            en: 'Create invite',
                            de: 'Einladung erstellen',
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AdminOverviewPanel(
          title: _pick(
            language,
            en: 'Pending invite links',
            de: 'Offene Einladungslinks',
          ),
          subtitle: _pick(
            language,
            en: 'Copy these links manually, or remove them if the onboarding path changes.',
            de: 'Kopieren Sie diese Links manuell oder entfernen Sie sie, wenn sich der Onboarding-Weg ändert.',
          ),
          child: Column(
            children: invites.isEmpty
                ? <Widget>[
                    _AdminEmptyState(
                      icon: Icons.link_off_rounded,
                      label: _pick(
                        language,
                        en: 'No pending staff invites yet.',
                        de: 'Noch keine offenen Teameinladungen.',
                      ),
                      dark: true,
                    ),
                  ]
                : invites.map((invite) {
                    final isDeleting = inviteIdsBeingDeleted.contains(
                      invite.id,
                    );
                    final displayName = invite.fullName.isEmpty
                        ? invite.email
                        : invite.fullName;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                displayName,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              if (invite.fullName.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 4),
                                Text(
                                  invite.email,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.62,
                                        ),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                invite.staffTypeLabel,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppTheme.mist,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    invite.inviteLink,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.white.withValues(
                                            alpha: 0.78,
                                          ),
                                          height: 1.35,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        onCopyInvite(invite.inviteLink),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppTheme.cobalt
                                          .withValues(alpha: 0.18),
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.copy_rounded),
                                    label: Text(
                                      _pick(
                                        language,
                                        en: 'Copy link',
                                        de: 'Link kopieren',
                                      ),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: isDeleting
                                        ? null
                                        : () => onDeleteInvite(invite),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.04,
                                      ),
                                      side: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.12,
                                        ),
                                      ),
                                    ),
                                    icon: isDeleting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                    label: Text(
                                      isDeleting
                                          ? _pick(
                                              language,
                                              en: 'Removing...',
                                              de: 'Wird entfernt...',
                                            )
                                          : _pick(
                                              language,
                                              en: 'Remove',
                                              de: 'Entfernen',
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }
}

InputDecoration _adminDarkInputDecoration(String labelText) {
  return InputDecoration(
    labelText: labelText,
    labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
    floatingLabelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
    filled: true,
    fillColor: Colors.white.withValues(alpha: 0.05),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: AppTheme.cobalt.withValues(alpha: 0.52)),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
  );
}

class _RecentQueueActivityPanel extends StatelessWidget {
  const _RecentQueueActivityPanel({
    required this.language,
    required this.requests,
    required this.onOpenRequest,
    required this.onOpenQueue,
  });

  final AppLanguage language;
  final List<ServiceRequestModel> requests;
  final ValueChanged<ServiceRequestModel> onOpenRequest;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 720;
    final previewLimit = isCompact ? 3 : 4;
    final previewRequests = requests.take(previewLimit).toList();
    final hiddenCount = requests.length > previewLimit
        ? requests.length - previewLimit
        : 0;

    return _AdminOverviewPanel(
      title: _pick(
        language,
        en: 'Recent queue activity',
        de: 'Aktuelle Queue-Aktivität',
      ),
      subtitle: _pick(
        language,
        en: 'Latest customer updates and request changes. Open the queue for the full live list.',
        de: 'Neueste Kundenupdates und Anfrageänderungen. Öffnen Sie die Queue für die vollständige Live-Liste.',
      ),
      actionLabel: _pick(language, en: 'Open queue', de: 'Queue öffnen'),
      onAction: onOpenQueue,
      child: Column(
        children: previewRequests.isEmpty
            ? <Widget>[
                _AdminEmptyState(
                  icon: Icons.inbox_outlined,
                  label: _pick(
                    language,
                    en: 'No recent queue activity yet.',
                    de: 'Noch keine aktuelle Queue-Aktivität.',
                  ),
                  dark: true,
                ),
              ]
            : <Widget>[
                ...previewRequests.map((request) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => onOpenRequest(request),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      request.serviceLabelForLanguage(language),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${request.contactFullName} · ${request.city}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.62,
                                            ),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _messagePreview(request),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.76,
                                            ),
                                            height: 1.3,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: <Widget>[
                                  StatusChip(
                                    status: request.status,
                                    labelOverride: _adminStatusLabel(
                                      request,
                                      language,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _pick(language, en: 'Open', de: 'Öffnen'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: AppTheme.cobalt,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                if (hiddenCount > 0)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _pick(
                        language,
                        en: '$hiddenCount more updates in the full queue view.',
                        de: '$hiddenCount weitere Updates in der vollständigen Queue-Ansicht.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.54),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
      ),
    );
  }

  String _messagePreview(ServiceRequestModel request) {
    if (request.messages.isEmpty) {
      return request.message;
    }

    final latestMessage = request.messages.last;
    return '${latestMessage.senderName}: ${latestMessage.text}';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    this.width = 200,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppTheme.darkBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminOverviewPanel extends StatelessWidget {
  const _AdminOverviewPanel({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.62),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (actionLabel != null && onAction != null) ...<Widget>[
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _AdminSummaryChip extends StatelessWidget {
  const _AdminSummaryChip({
    required this.icon,
    required this.label,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Colors.white.withValues(alpha: 0.72);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminFilterChip extends StatelessWidget {
  const _AdminFilterChip({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = selected
        ? AppTheme.blendOn(accentColor.withValues(alpha: 0.28))
        : AppTheme.blendOn(Colors.white.withValues(alpha: 0.06));
    final borderColor = selected
        ? accentColor.withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.14);
    final foregroundColor = AppTheme.readableForegroundFor(
      backgroundColor,
      light: Colors.white,
      dark: AppTheme.ink,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (selected) ...<Widget>[
              Icon(Icons.check_rounded, size: 18, color: foregroundColor),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPresenceChip extends StatelessWidget {
  const _AdminPresenceChip({required this.label, required this.online});

  final String label;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = online
        ? AppTheme.pine.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.06);
    final Color borderColor = online
        ? AppTheme.pine.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.12);
    final Color foregroundColor = online
        ? const Color(0xFF8BD0B8)
        : Colors.white.withValues(alpha: 0.74);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.circle, size: 10, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, this.dark = false});

  final IconData icon;
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.05) : AppTheme.sand,
        borderRadius: BorderRadius.circular(999),
        border: dark
            ? Border.all(color: Colors.white.withValues(alpha: 0.08))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: AppTheme.cobalt),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.82)
                      : AppTheme.ink,
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

class _AdminDetailActionButton extends StatelessWidget {
  const _AdminDetailActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        foregroundColor: Colors.white,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _AdminHeaderActionButton extends StatelessWidget {
  const _AdminHeaderActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _AdminSheetCard extends StatelessWidget {
  const _AdminSheetCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppTheme.darkBorder),
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
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminEmptyState extends StatelessWidget {
  const _AdminEmptyState({
    required this.icon,
    required this.label,
    this.dark = false,
  });

  final IconData icon;
  final String label;
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
            padding: const EdgeInsets.all(16),
            child: Icon(
              icon,
              size: 28,
              color: dark
                  ? Colors.white.withValues(alpha: 0.84)
                  : AppTheme.cobalt,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: dark ? Colors.white.withValues(alpha: 0.74) : null,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
