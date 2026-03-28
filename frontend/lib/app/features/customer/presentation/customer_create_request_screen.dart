/// WHAT: Renders the authenticated customer form for submitting a new service request.
/// WHY: The request form is the first structured intake step before admin review and staff assignment.
/// HOW: Collect service details, submit through the repository, and invalidate the customer request timeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/app_config.dart';
import '../../../shared/presentation/panel_card.dart';
import '../../customer/data/customer_repository.dart';
import 'customer_requests_screen.dart';

class CustomerCreateRequestScreen extends ConsumerStatefulWidget {
  const CustomerCreateRequestScreen({super.key});

  @override
  ConsumerState<CustomerCreateRequestScreen> createState() => _CustomerCreateRequestScreenState();
}

class _CustomerCreateRequestScreenState extends ConsumerState<CustomerCreateRequestScreen> {
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _dateController = TextEditingController();
  final _timeWindowController = TextEditingController();
  final _messageController = TextEditingController();

  String? _selectedServiceType = AppConfig.serviceLabels.keys.first;
  bool _isSubmitting = false;

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

    _dateController.text = selectedDate.toIso8601String().split('T').first;
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    debugPrint('CustomerCreateRequestScreen._submit: creating request');

    try {
      await ref.read(customerRepositoryProvider).createRequest(
            serviceType: _selectedServiceType ?? AppConfig.serviceLabels.keys.first,
            addressLine1: _addressController.text.trim(),
            city: _cityController.text.trim(),
            postalCode: _postalCodeController.text.trim(),
            preferredDate: _dateController.text.trim(),
            preferredTimeWindow: _timeWindowController.text.trim(),
            message: _messageController.text.trim(),
          );

      ref.invalidate(customerRequestsProvider);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request submitted successfully')),
      );
      context.go('/app/requests');
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Request')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: PanelCard(
              title: 'Request a service',
              subtitle: 'Structured details make the admin review and staff assignment faster.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedServiceType,
                    decoration: const InputDecoration(labelText: 'Service type'),
                    items: AppConfig.serviceLabels.entries
                        .map(
                          (MapEntry<String, String> entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    onChanged: (String? value) => setState(() => _selectedServiceType = value),
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: _addressController, decoration: const InputDecoration(labelText: 'Address')),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(controller: _cityController, decoration: const InputDecoration(labelText: 'City')),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _postalCodeController,
                          decoration: const InputDecoration(labelText: 'Postal code'),
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
                          decoration: const InputDecoration(labelText: 'Preferred date'),
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
                    decoration: const InputDecoration(labelText: 'Preferred time window'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _messageController,
                    minLines: 5,
                    maxLines: 7,
                    decoration: const InputDecoration(labelText: 'Describe the work'),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: Text(_isSubmitting ? 'Submitting...' : 'Send Request'),
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
}
