/// WHAT: Provides the presentational sections used by the admin workspace.
/// WHY: The admin dashboard now spans overview, queue, staff, and invite surfaces, so the UI should be split into smaller focused widgets.
/// HOW: Accept typed admin models plus small callbacks from the screen state and render queue-first workspace panels.
library;

import 'package:flutter/material.dart';

import '../../../core/models/dashboard_models.dart';
import '../../../core/models/service_request_model.dart';
import '../../../shared/presentation/request_thread_section.dart';
import '../../../shared/presentation/status_chip.dart';
import '../../../theme/app_theme.dart';

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
    required this.kpis,
    required this.recentRequests,
    required this.onOpenRequest,
    required this.onOpenQueue,
  });

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
                  label: 'Total Requests',
                  value: '${kpis.totalRequests}',
                  width: metricWidth,
                ),
                _MetricCard(
                  label: 'Waiting Queue',
                  value: '${kpis.waitingQueueCount}',
                  width: metricWidth,
                ),
                _MetricCard(
                  label: 'Active Queue',
                  value: '${kpis.activeQueueCount}',
                  width: metricWidth,
                ),
                _MetricCard(
                  label: 'Staff Online',
                  value: '${kpis.staffOnlineCount}',
                  width: metricWidth,
                ),
                _MetricCard(
                  label: 'Pending Invites',
                  value: '${kpis.pendingInvitesCount}',
                  width: metricWidth,
                ),
                _MetricCard(
                  label: 'Cleared Today',
                  value: '${kpis.clearedTodayCount}',
                  width: metricWidth,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _RecentQueueActivityPanel(
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
    required this.searchController,
    required this.onApplySearch,
    required this.onClearSearch,
    required this.filterChips,
    required this.requests,
    required this.selectedRequestId,
    required this.onSelectRequest,
    this.edgeToEdge = false,
  });

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
          edgeToEdge ? 8 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Admin queue',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Find the right customer thread fast, then open the full queue conversation on the right.',
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
                hintText: 'Search customer, email, or city',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.48),
                ),
                suffixIcon: searchController.text.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
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
                        label: 'No request threads match this filter.',
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
                                          request.serviceLabel,
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
                                      StatusChip(status: request.status),
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
                                    '${request.messageCount} messages',
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
    required this.request,
    required this.staff,
    this.edgeToEdge = false,
    required this.onAssignToStaff,
    required this.selectedAssignmentId,
    required this.onAssignmentChanged,
    required this.onAssign,
    required this.isAssigning,
    required this.onSendInvoice,
    required this.onOpenPaymentProof,
    required this.onOpenReceipt,
    required this.onApprovePaymentProof,
    required this.onRejectPaymentProof,
    required this.isSendingInvoice,
    required this.isReviewingPaymentProof,
    this.onBack,
  });

  final ServiceRequestModel? request;
  final List<StaffMemberSummary> staff;
  final bool edgeToEdge;
  final Future<void> Function(String staffId)? onAssignToStaff;
  final String? selectedAssignmentId;
  final ValueChanged<String?> onAssignmentChanged;
  final VoidCallback? onAssign;
  final bool isAssigning;
  final VoidCallback? onSendInvoice;
  final VoidCallback? onOpenPaymentProof;
  final VoidCallback? onOpenReceipt;
  final VoidCallback? onApprovePaymentProof;
  final VoidCallback? onRejectPaymentProof;
  final bool isSendingInvoice;
  final bool isReviewingPaymentProof;
  final VoidCallback? onBack;

  Future<void> _showAssignmentSheet(
    BuildContext context,
    ServiceRequestModel request,
  ) async {
    String? localSelection = selectedAssignmentId ?? request.assignedStaff?.id;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        return StatefulBuilder(
          builder: (BuildContext modalContext, StateSetter setModalState) {
            return _AdminSheetCard(
              title: 'Assignment',
              subtitle:
                  'Assign this customer to staff without crowding the chat view.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (staff.isEmpty)
                    Text(
                      'No active staff accounts are available for assignment yet.',
                      style: Theme.of(modalContext).textTheme.bodyMedium
                          ?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                    )
                  else ...<Widget>[
                    DropdownButtonFormField<String>(
                      initialValue: localSelection,
                      decoration: const InputDecoration(
                        labelText: 'Assign to staff',
                      ),
                      items: staff
                          .map(
                            (person) => DropdownMenuItem<String>(
                              value: person.id,
                              child: Text(
                                '${person.fullName} · ${person.staffAvailability ?? 'offline'} · ${person.assignedOpenRequestCount} open',
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
                          isAssigning ? 'Assigning...' : 'Assign request',
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

  Future<void> _showBillingSheet(
    BuildContext context,
    ServiceRequestModel request,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext modalContext) {
        return _AdminSheetCard(
          title: 'Billing',
          subtitle:
              'Create the quotation, review proof, and resolve payment actions here.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                request.invoice != null
                    ? 'Quotation ${request.invoice!.invoiceNumber} is ${requestStatusLabelFor(request.invoice!.status)}.'
                    : 'Create and send a quotation directly from this request detail pane.',
                style: Theme.of(modalContext).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: isSendingInvoice ? null : onSendInvoice,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.cobalt.withValues(alpha: 0.18),
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
          if (context.mounted) {
            await _showBillingSheet(context, request);
          }
        }

        return _AdminSheetCard(
          title: '${request.contactFullName} profile',
          subtitle:
              'Keep the chat clear and open the full customer/request context only when needed.',
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
                    label: '${request.messageCount} messages',
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
                        label:
                            'Started ${_formatDateTime(request.projectStartedAt)}',
                        dark: true,
                      ),
                    if (request.finishedAt != null)
                      _MetaChip(
                        icon: Icons.task_alt_rounded,
                        label:
                            'Finished ${_formatDateTime(request.finishedAt)}',
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
                    label: 'Assignment',
                    onPressed: openAssignment,
                  ),
                  _AdminDetailActionButton(
                    icon: Icons.receipt_long_rounded,
                    label: 'Billing',
                    onPressed: openBilling,
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
        ),
        child: const Center(
          child: _AdminEmptyState(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Pick a customer thread to review the full queue context.',
            dark: true,
          ),
        ),
      );
    }

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
                      label: const Text('Back to queue'),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            request!.contactFullName,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${request!.serviceLabel} · ${request!.city}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.62),
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _queueSummary(request!),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.84),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    StatusChip(status: request!.status),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _showProfileSheet(context, request!),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  icon: const Icon(Icons.person_outline_rounded),
                  label: const Text('Profile'),
                ),
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
                    const Color(0xFF111214),
                    AppTheme.ember.withValues(alpha: 0.08),
                    const Color(0xFF0D0E10),
                  ],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                child: RequestThreadSection(
                  messages: request!.messages,
                  viewerRole: 'admin',
                  dark: true,
                  emptyLabel: 'No thread messages yet.',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _queueSummary(ServiceRequestModel request) {
    if (request.status == 'closed') {
      return 'Closed request';
    }

    if (request.assignedStaff != null) {
      return 'Assigned to ${request.assignedStaff!.fullName}';
    }

    return 'Waiting in live queue';
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

class AdminStaffSection extends StatelessWidget {
  const AdminStaffSection({super.key, required this.staff});

  final List<StaffMemberSummary> staff;

  @override
  Widget build(BuildContext context) {
    final sortedStaff = <StaffMemberSummary>[...staff]
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
      return const _AdminOverviewPanel(
        title: 'Team',
        subtitle:
            'No active staff accounts exist yet. Create an invite to onboard someone.',
        child: _AdminEmptyState(
          icon: Icons.group_outlined,
          label: 'No staff accounts added yet.',
          dark: true,
        ),
      );
    }

    return _AdminOverviewPanel(
      title: 'Team',
      subtitle:
          'Track staff availability, open queue load, and how much work each person cleared today.',
      child: Column(
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _AdminSummaryChip(
                icon: Icons.group_rounded,
                label: '${sortedStaff.length} staff',
              ),
              _AdminSummaryChip(
                icon: Icons.circle,
                label: '$onlineCount online',
                accentColor: AppTheme.pine,
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                              '${person.assignedOpenRequestCount} open · ${person.clearedTodayCount} cleared today',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.62),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _AdminPresenceChip(
                        label: isOnline ? 'online' : 'offline',
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
    required this.firstNameController,
    required this.lastNameController,
    required this.emailController,
    required this.phoneController,
    required this.isInviteSubmitting,
    required this.onSubmitInvite,
    required this.invites,
    required this.inviteIdsBeingDeleted,
    required this.onCopyInvite,
    required this.onDeleteInvite,
  });

  final TextEditingController firstNameController;
  final TextEditingController lastNameController;
  final TextEditingController emailController;
  final TextEditingController phoneController;
  final bool isInviteSubmitting;
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
          title: 'Create staff invite',
          subtitle: 'Generate a copyable link and share it outside the app.',
          child: Column(
            children: <Widget>[
              TextField(
                controller: firstNameController,
                style: textStyle,
                decoration: _adminDarkInputDecoration('First name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastNameController,
                style: textStyle,
                decoration: _adminDarkInputDecoration('Last name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                style: textStyle,
                decoration: _adminDarkInputDecoration('Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                style: textStyle,
                decoration: _adminDarkInputDecoration('Phone'),
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
                    isInviteSubmitting ? 'Creating...' : 'Create invite',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _AdminOverviewPanel(
          title: 'Pending invite links',
          subtitle:
              'Copy these links manually, or remove them if the onboarding path changes.',
          child: Column(
            children: invites.isEmpty
                ? <Widget>[
                    const _AdminEmptyState(
                      icon: Icons.link_off_rounded,
                      label: 'No pending staff invites yet.',
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
                                    label: const Text('Copy link'),
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
                                      isDeleting ? 'Removing...' : 'Remove',
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
    required this.requests,
    required this.onOpenRequest,
    required this.onOpenQueue,
  });

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
      title: 'Recent queue activity',
      subtitle:
          'Latest customer updates and request changes. Open the queue for the full live list.',
      actionLabel: 'Open queue',
      onAction: onOpenQueue,
      child: Column(
        children: previewRequests.isEmpty
            ? <Widget>[
                const _AdminEmptyState(
                  icon: Icons.inbox_outlined,
                  label: 'No recent queue activity yet.',
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
                                      request.serviceLabel,
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
                                  StatusChip(status: request.status),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Open',
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
                      '$hiddenCount more updates in the full queue view.',
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
          color: const Color(0xFF111316),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
        color: const Color(0xFF111316),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
  final VoidCallback onPressed;

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
