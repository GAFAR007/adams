/// WHAT: Renders the authenticated customer request list as a live queue-and-thread workspace.
/// WHY: Customers should see queue progress, AI waiting messages, assigned staff, and thread replies in one place.
/// HOW: Load customer-owned requests, render each queue card with thread history, and post inline updates through the repository.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/presentation/panel_card.dart';
import '../../../shared/presentation/request_message_composer.dart';
import '../../../shared/presentation/request_thread_section.dart';
import '../../../shared/presentation/status_chip.dart';
import '../../auth/application/auth_controller.dart';
import '../data/customer_repository.dart';
import '../../../core/models/service_request_model.dart';

final customerRequestsProvider = FutureProvider<List<ServiceRequestModel>>((
  Ref ref,
) async {
  debugPrint('customerRequestsProvider: fetching customer requests');
  return ref.watch(customerRepositoryProvider).fetchRequests();
});

class CustomerRequestsScreen extends ConsumerStatefulWidget {
  const CustomerRequestsScreen({super.key});

  @override
  ConsumerState<CustomerRequestsScreen> createState() =>
      _CustomerRequestsScreenState();
}

class _CustomerRequestsScreenState extends ConsumerState<CustomerRequestsScreen> {
  final Map<String, TextEditingController> _messageControllers =
      <String, TextEditingController>{};
  final Set<String> _submittingMessageIds = <String>{};

  @override
  void dispose() {
    // WHY: Each visible request can own a composer controller, so they all need explicit cleanup when the screen leaves.
    for (final controller in _messageControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String requestId) {
    // WHY: Request cards rebuild often, so keep one stable controller per request id instead of recreating on every frame.
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

    return 'Pending in the live queue. AI is keeping the thread warm while staff joins.';
  }

  String _messageButtonLabel(ServiceRequestModel request) {
    return request.assignedStaff == null ? 'Send queue update' : 'Reply to staff';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final requestsAsync = ref.watch(customerRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Requests'),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/app/requests/new'),
        label: const Text('New Request'),
        icon: const Icon(Icons.add_task_rounded),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Welcome back, ${authState.user?.firstName ?? 'Customer'}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'Track queue progress, continue the conversation, and see when staff picks up each request.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: requestsAsync.when(
                data: (List<ServiceRequestModel> requests) {
                  if (requests.isEmpty) {
                    return const PanelCard(
                      title: 'No requests yet',
                      subtitle:
                          'Create your first service request to join the live operations queue.',
                      child: SizedBox.shrink(),
                    );
                  }

                  return ListView.separated(
                    itemCount: requests.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (BuildContext context, int index) {
                      final request = requests[index];
                      final controller = _controllerFor(request.id);
                      final isSubmitting = _submittingMessageIds.contains(
                        request.id,
                      );
                      final canSend =
                          request.status != 'closed' &&
                          controller.text.trim().isNotEmpty;

                      return PanelCard(
                        title: request.serviceLabel,
                        subtitle:
                            '${request.addressLine1}, ${request.city} ${request.postalCode}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: <Widget>[
                                StatusChip(status: request.status),
                                Text('Messages: ${request.messageCount}'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _queueSummary(request),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              request.message,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 16),
                            RequestThreadSection(
                              messages: request.messages,
                              viewerRole: 'customer',
                              emptyLabel:
                                  'No queue messages yet. New updates will appear here.',
                            ),
                            const SizedBox(height: 16),
                            StatefulBuilder(
                              builder:
                                  (
                                    BuildContext context,
                                    void Function(void Function()) setLocalState,
                                  ) {
                                    return RequestMessageComposer(
                                      controller: controller,
                                      hintText: request.assignedStaff == null
                                          ? 'Send an update while you wait in queue'
                                          : 'Reply to the staff handling this request',
                                      buttonLabel: _messageButtonLabel(request),
                                      isSubmitting: isSubmitting,
                                      isEnabled: canSend,
                                      onSubmit: () => _sendMessage(request),
                                    );
                                  },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace stackTrace) => PanelCard(
                  title: 'Unable to load requests',
                  subtitle: error.toString(),
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
