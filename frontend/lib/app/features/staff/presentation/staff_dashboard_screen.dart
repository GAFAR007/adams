/// WHAT: Renders the staff dashboard with assigned requests and workflow status updates.
/// WHY: Staff should only see the work assigned to them, with a simple surface to move status forward.
/// HOW: Fetch the compact staff dashboard bundle, render KPIs, and update request status through the repository.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/panel_card.dart';
import '../../../shared/presentation/status_chip.dart';
import '../../auth/application/auth_controller.dart';
import '../data/staff_repository.dart';
import '../../../core/models/dashboard_models.dart';

final staffDashboardProvider = FutureProvider<StaffDashboardBundle>((Ref ref) async {
  debugPrint('staffDashboardProvider: fetching staff dashboard');
  return ref.watch(staffRepositoryProvider).fetchDashboard();
});

class StaffDashboardScreen extends ConsumerStatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  ConsumerState<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends ConsumerState<StaffDashboardScreen> {
  final Map<String, String> _selectedStatuses = <String, String>{};

  Future<void> _updateStatus({
    required String requestId,
    required String status,
  }) async {
    debugPrint('StaffDashboardScreen._updateStatus: updating request $requestId to $status');

    try {
      await ref.read(staffRepositoryProvider).updateRequestStatus(requestId: requestId, status: status);
      ref.invalidate(staffDashboardProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request status updated')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundleAsync = ref.watch(staffDashboardProvider);
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Staff Dashboard · ${authState.user?.fullName ?? 'Staff'}'),
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
          data: (StaffDashboardBundle bundle) {
            return ListView(
              children: <Widget>[
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: <Widget>[
                    _StaffKpiCard(label: 'Assigned', value: '${bundle.assignedCount}'),
                    _StaffKpiCard(label: 'Quoted', value: '${bundle.quotedCount}'),
                    _StaffKpiCard(label: 'Confirmed', value: '${bundle.confirmedCount}'),
                  ],
                ),
                const SizedBox(height: 24),
                if (bundle.assignedRequests.isEmpty)
                  const PanelCard(
                    title: 'No assigned requests',
                    subtitle: 'Assigned work will appear here once the admin queue sends you jobs.',
                    child: SizedBox.shrink(),
                  )
                else
                  ...bundle.assignedRequests.map((request) {
                    final selectedStatus = _selectedStatuses[request.id] ?? request.status;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: PanelCard(
                        title: request.serviceLabel,
                        subtitle: '${request.contactFullName} · ${request.city}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            StatusChip(status: request.status),
                            const SizedBox(height: 12),
                            Text(request.message),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: selectedStatus,
                              decoration: const InputDecoration(labelText: 'Update workflow status'),
                              items: const <DropdownMenuItem<String>>[
                                DropdownMenuItem(value: 'under_review', child: Text('Under review')),
                                DropdownMenuItem(value: 'quoted', child: Text('Quoted')),
                                DropdownMenuItem(
                                  value: 'appointment_confirmed',
                                  child: Text('Appointment confirmed'),
                                ),
                                DropdownMenuItem(value: 'closed', child: Text('Closed')),
                              ],
                              onChanged: (String? value) {
                                if (value == null) {
                                  return;
                                }

                                setState(() => _selectedStatuses[request.id] = value);
                              },
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonal(
                                onPressed: () => _updateStatus(requestId: request.id, status: selectedStatus),
                                child: const Text('Save status'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stackTrace) => PanelCard(
            title: 'Unable to load staff dashboard',
            subtitle: error.toString(),
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _StaffKpiCard extends StatelessWidget {
  const _StaffKpiCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: PanelCard(
        title: label,
        child: Text(
          value,
          style: Theme.of(context).textTheme.displaySmall,
        ),
      ),
    );
  }
}
