/// WHAT: Renders the authenticated customer form for submitting a new service request.
/// WHY: The request form is the first structured intake step before admin review and staff assignment.
/// HOW: Collect service details, submit through the repository, and invalidate the customer request timeline.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../core/models/service_request_model.dart';
import '../../../shared/presentation/panel_card.dart';
import '../../customer/data/customer_repository.dart';
import 'customer_requests_screen.dart';

class CustomerCreateRequestScreen extends ConsumerStatefulWidget {
  const CustomerCreateRequestScreen({super.key, this.requestId});

  final String? requestId;

  @override
  ConsumerState<CustomerCreateRequestScreen> createState() =>
      _CustomerCreateRequestScreenState();
}

class _CustomerCreateRequestScreenState
    extends ConsumerState<CustomerCreateRequestScreen> {
  static const List<_RequestDraftSeed> _requestDraftSeeds = <_RequestDraftSeed>[
    _RequestDraftSeed(
      serviceType: 'building_cleaning',
      addressLine1: '12 Clean Street',
      city: 'Monchengladbach',
      postalCode: '41189',
      preferredTimeWindow: 'Weekday morning (08:00 - 11:00)',
      message:
          'We need weekly building cleaning for the entrance, hallways, and kitchen before staff arrive.',
    ),
    _RequestDraftSeed(
      serviceType: 'warehouse_hall_cleaning',
      addressLine1: '45 Warehouse Lane',
      city: 'Dusseldorf',
      postalCode: '40210',
      preferredTimeWindow: 'Afternoon (13:00 - 16:00)',
      message:
          'Please prepare a draft request for warehouse floor cleaning and dust removal around the loading area.',
    ),
    _RequestDraftSeed(
      serviceType: 'window_glass_cleaning',
      addressLine1: '99 Glass Road',
      city: 'Cologne',
      postalCode: '50667',
      preferredTimeWindow: 'Flexible during business hours',
      message:
          'Storefront glass and upper window panels need cleaning before the next customer event.',
    ),
    _RequestDraftSeed(
      serviceType: 'winter_service',
      addressLine1: '28 Frost Avenue',
      city: 'Dortmund',
      postalCode: '44135',
      preferredTimeWindow: 'Early morning (06:00 - 09:00)',
      message:
          'We need snow clearing and grit service around the front entrance, bins, and parking access.',
    ),
    _RequestDraftSeed(
      serviceType: 'caretaker_service',
      addressLine1: '7 Garden Court',
      city: 'Essen',
      postalCode: '45127',
      preferredTimeWindow: 'Morning visit preferred',
      message:
          'Caretaker support is needed for a walkthrough, light fixes, and weekly property checks.',
    ),
    _RequestDraftSeed(
      serviceType: 'garden_care',
      addressLine1: '31 Linden Park',
      city: 'Bonn',
      postalCode: '53111',
      preferredTimeWindow: 'Late morning (10:00 - 12:00)',
      message:
          'Please prepare a garden care draft for hedge trimming, leaf cleanup, and tidying shared outdoor areas.',
    ),
    _RequestDraftSeed(
      serviceType: 'post_construction_cleaning',
      addressLine1: '63 Builder Square',
      city: 'Aachen',
      postalCode: '52062',
      preferredTimeWindow: 'Any time after 09:00',
      message:
          'A post-construction clean is needed after renovation, including dust removal, floors, and window frames.',
    ),
  ];

  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeWindowController = TextEditingController();
  final _messageController = TextEditingController();
  final Random _random = Random();

  String? _selectedServiceType = AppConfig.serviceLabels.keys.first;
  String? _hydratedRequestId;
  bool _isSubmitting = false;

  bool get _isEditing => widget.requestId != null;

  @override
  void dispose() {
    _addressController.dispose();
    _cityController.dispose();
    _postalCodeController.dispose();
    _dateController.dispose();
    _timeWindowController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selectedDate == null) {
      return;
    }

    _dateController.text = _formatDate(selectedDate);
  }

  String _formatDate(DateTime date) => date.toIso8601String().split('T').first;

  void _generateTestDraft() {
    final seed = _requestDraftSeeds[_random.nextInt(_requestDraftSeeds.length)];
    final preferredDate = DateTime.now().add(
      Duration(days: _random.nextInt(21) + 1),
    );

    // WHY: Keep the test-draft generator explicit so production-flow testing does not require typing the full form every time.
    setState(() {
      _selectedServiceType = seed.serviceType;
      _addressController.text = seed.addressLine1;
      _cityController.text = seed.city;
      _postalCodeController.text = seed.postalCode;
      _dateController.text = _formatDate(preferredDate);
      _timeWindowController.text = seed.preferredTimeWindow;
      _messageController.text = seed.message;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Random test draft generated')),
      );
  }

  void _hydrateFromRequest(ServiceRequestModel request) {
    if (_hydratedRequestId == request.id) {
      return;
    }

    _hydratedRequestId = request.id;
    _selectedServiceType = request.serviceType;
    _addressController.text = request.addressLine1;
    _cityController.text = request.city;
    _postalCodeController.text = request.postalCode;
    _dateController.text = request.preferredDate == null
        ? ''
        : _formatDate(request.preferredDate!);
    _timeWindowController.text = request.preferredTimeWindow;
    _messageController.text = request.message;
  }

  Widget _buildTestDraftHelper(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE6F6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Testing shortcut',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Generate a random request draft, including address details, so you can test the flow without manual typing.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isSubmitting ? null : _generateTestDraft,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Generate Test Draft'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    debugPrint(
      'CustomerCreateRequestScreen._submit: ${_isEditing ? 'updating' : 'creating'} request',
    );

    try {
      final repository = ref.read(customerRepositoryProvider);
      final payload = <String, String>{
        'serviceType':
            _selectedServiceType ?? AppConfig.serviceLabels.keys.first,
        'addressLine1': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'postalCode': _postalCodeController.text.trim(),
        'preferredDate': _dateController.text.trim(),
        'preferredTimeWindow': _timeWindowController.text.trim(),
        'message': _messageController.text.trim(),
      };

      if (_isEditing) {
        await repository.updateRequest(
          requestId: widget.requestId!,
          serviceType: payload['serviceType']!,
          addressLine1: payload['addressLine1']!,
          city: payload['city']!,
          postalCode: payload['postalCode']!,
          preferredDate: payload['preferredDate']!,
          preferredTimeWindow: payload['preferredTimeWindow']!,
          message: payload['message']!,
        );
      } else {
        await repository.createRequest(
          serviceType: payload['serviceType']!,
          addressLine1: payload['addressLine1']!,
          city: payload['city']!,
          postalCode: payload['postalCode']!,
          preferredDate: payload['preferredDate']!,
          preferredTimeWindow: payload['preferredTimeWindow']!,
          message: payload['message']!,
        );
      }

      ref.invalidate(customerRequestsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Request updated successfully'
                : 'Request submitted successfully',
          ),
        ),
      );
      context.go('/app/requests');
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
        setState(() => _isSubmitting = false);
      }
    }
  }

  Widget _buildFormScaffold(BuildContext context) {
    final title = _isEditing ? 'Update Request' : 'Create Request';
    final panelTitle = _isEditing ? 'Update your request' : 'Request a service';
    final panelSubtitle = _isEditing
        ? 'Revise your request details so staff can continue with the latest information.'
        : 'Structured details make the admin review and staff assignment faster.';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: PanelCard(
              title: panelTitle,
              subtitle: panelSubtitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!_isEditing) ...<Widget>[
                    _buildTestDraftHelper(context),
                    const SizedBox(height: 16),
                  ],
                  DropdownButtonFormField<String>(
                    key: ValueKey<String?>(_selectedServiceType),
                    initialValue: _selectedServiceType,
                    decoration: const InputDecoration(
                      labelText: 'Service type',
                    ),
                    items: AppConfig.serviceLabels.entries
                        .map(
                          (MapEntry<String, String> entry) =>
                              DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                        )
                        .toList(),
                    onChanged: (String? value) =>
                        setState(() => _selectedServiceType = value),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _addressController,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _cityController,
                          decoration: const InputDecoration(labelText: 'City'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _postalCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Postal code',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _dateController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Preferred date',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _timeWindowController,
                    decoration: const InputDecoration(
                      labelText: 'Preferred time window',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _messageController,
                    minLines: 5,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Describe the work',
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: Text(
                        _isSubmitting
                            ? (_isEditing ? 'Updating...' : 'Submitting...')
                            : (_isEditing ? 'Save Changes' : 'Send Request'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEditing) {
      return _buildFormScaffold(context);
    }

    final requestsAsync = ref.watch(customerRequestsProvider);

    return requestsAsync.when(
      data: (List<ServiceRequestModel> requests) {
        ServiceRequestModel? request;
        for (final item in requests) {
          if (item.id == widget.requestId) {
            request = item;
            break;
          }
        }

        if (request == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Update Request')),
            body: const Center(
              child: Text(
                'Request not found. Return to your inbox and try again.',
              ),
            ),
          );
        }

        _hydrateFromRequest(request);
        return _buildFormScaffold(context);
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Update Request')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('Update Request')),
        body: Center(child: Text(error.toString())),
      ),
    );
  }
}

class _RequestDraftSeed {
  const _RequestDraftSeed({
    required this.serviceType,
    required this.addressLine1,
    required this.city,
    required this.postalCode,
    required this.preferredTimeWindow,
    required this.message,
  });

  final String serviceType;
  final String addressLine1;
  final String city;
  final String postalCode;
  final String preferredTimeWindow;
  final String message;
}
