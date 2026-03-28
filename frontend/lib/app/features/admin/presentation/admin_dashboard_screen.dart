/// WHAT: Renders the admin dashboard with KPIs, request assignment, staff list, and invite generation.
/// WHY: Admins need one operational surface to manage the request pipeline and staff access.
/// HOW: Fetch the compact dashboard bundle, render responsive panels, and invalidate it after actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/panel_card.dart';
import '../../../shared/presentation/status_chip.dart';
import '../../auth/application/auth_controller.dart';
import '../data/admin_repository.dart';
import '../../../core/models/dashboard_models.dart';

final adminDashboardProvider = FutureProvider<AdminDashboardBundle>((
  Ref ref,
) async {
  debugPrint('adminDashboardProvider: fetching admin dashboard bundle');
  return ref.watch(adminRepositoryProvider).fetchDashboardBundle();
});

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
  final Map<String, String?> _selectedAssignments = <String, String?>{};
  final Set<String> _inviteIdsBeingDeleted = <String>{};
  bool _isInviteSubmitting = false;

  @override
  void dispose() {
    _inviteFirstNameController.dispose();
    _inviteLastNameController.dispose();
    _inviteEmailController.dispose();
    _invitePhoneController.dispose();
    super.dispose();
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
    debugPrint(
      'AdminDashboardScreen._assignRequest: assigning request $requestId',
    );

    try {
      await ref
          .read(adminRepositoryProvider)
          .assignRequest(requestId: requestId, staffId: staffId);
      ref.invalidate(adminDashboardProvider);

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

  @override
  Widget build(BuildContext context) {
    final bundleAsync = ref.watch(adminDashboardProvider);
    final authState = ref.watch(authControllerProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 1080;

    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Dashboard · ${authState.user?.fullName ?? 'Admin'}'),
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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: bundleAsync.when(
          data: (AdminDashboardBundle bundle) {
            return ListView(
              children: <Widget>[
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: <Widget>[
                    _KpiCard(
                      label: 'Total Requests',
                      value: '${bundle.kpis.totalRequests}',
                    ),
                    _KpiCard(
                      label: 'Staff',
                      value: '${bundle.kpis.staffCount}',
                    ),
                    _KpiCard(
                      label: 'Pending Invites',
                      value: '${bundle.kpis.pendingInvitesCount}',
                    ),
                    _KpiCard(
                      label: 'Submitted',
                      value: '${bundle.kpis.countsByStatus['submitted'] ?? 0}',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Flex(
                  direction: isWide ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: PanelCard(
                        title: 'Request queue',
                        subtitle:
                            'Review recent work and assign staff where needed.',
                        child: Column(
                          children: bundle.requests.map((request) {
                            final selectedStaffId =
                                _selectedAssignments[request.id] ??
                                request.assignedStaff?.id;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: PanelCard(
                                title: request.serviceLabel,
                                subtitle:
                                    '${request.contactFullName} · ${request.city}',
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    StatusChip(status: request.status),
                                    const SizedBox(height: 12),
                                    Text(request.message),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      initialValue: selectedStaffId,
                                      decoration: const InputDecoration(
                                        labelText: 'Assign to staff',
                                      ),
                                      items: bundle.staff
                                          .map(
                                            (
                                              StaffMemberSummary staff,
                                            ) => DropdownMenuItem<String>(
                                              value: staff.id,
                                              child: Text(
                                                '${staff.fullName} (${staff.assignedOpenRequestCount} open)',
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (String? value) {
                                        setState(
                                          () =>
                                              _selectedAssignments[request.id] =
                                                  value,
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.tonal(
                                        onPressed: selectedStaffId == null
                                            ? null
                                            : () => _assignRequest(
                                                requestId: request.id,
                                                staffId: selectedStaffId,
                                              ),
                                        child: const Text('Assign request'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    SizedBox(width: isWide ? 16 : 0, height: isWide ? 0 : 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: <Widget>[
                          PanelCard(
                            title: 'Create staff invite',
                            subtitle:
                                'Generate a copyable link and share it outside the app.',
                            child: Column(
                              children: <Widget>[
                                TextField(
                                  controller: _inviteFirstNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'First name',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _inviteLastNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Last name',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _inviteEmailController,
                                  decoration: const InputDecoration(
                                    labelText: 'Email',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _invitePhoneController,
                                  decoration: const InputDecoration(
                                    labelText: 'Phone',
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _isInviteSubmitting
                                        ? null
                                        : _submitInvite,
                                    child: Text(
                                      _isInviteSubmitting
                                          ? 'Creating...'
                                          : 'Create invite',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          PanelCard(
                            title: 'Pending invite links',
                            subtitle:
                                'Copy these links manually and send them to new staff members.',
                            child: Column(
                              children: bundle.invites.isEmpty
                                  ? <Widget>[
                                      const Text(
                                        'No pending staff invites yet.',
                                      ),
                                    ]
                                  : bundle.invites.map((invite) {
                                      return ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(
                                          invite.fullName.isEmpty
                                              ? invite.email
                                              : invite.fullName,
                                        ),
                                        subtitle: Text(invite.inviteLink),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            IconButton(
                                              tooltip: 'Copy invite link',
                                              onPressed: () async {
                                                final messenger =
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    );
                                                await Clipboard.setData(
                                                  ClipboardData(
                                                    text: invite.inviteLink,
                                                  ),
                                                );
                                                if (!mounted) {
                                                  return;
                                                }

                                                messenger.showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Invite link copied',
                                                    ),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.copy_rounded,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Remove invite link',
                                              onPressed:
                                                  _inviteIdsBeingDeleted
                                                      .contains(invite.id)
                                                  ? null
                                                  : () => _deleteInvite(invite),
                                              icon:
                                                  _inviteIdsBeingDeleted
                                                      .contains(invite.id)
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : const Icon(
                                                      Icons
                                                          .delete_outline_rounded,
                                                    ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          PanelCard(
                            title: 'Active staff',
                            subtitle:
                                'Quick view of the team and their open request load.',
                            child: Column(
                              children: bundle.staff.map((staff) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(staff.fullName),
                                  subtitle: Text(staff.email),
                                  trailing: Text(
                                    '${staff.assignedOpenRequestCount} open',
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stackTrace) => PanelCard(
            title: 'Unable to load admin dashboard',
            subtitle: error.toString(),
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: PanelCard(
        title: label,
        child: Text(value, style: Theme.of(context).textTheme.displaySmall),
      ),
    );
  }
}
