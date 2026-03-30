library;

import 'package:flutter/material.dart';

import '../../core/models/service_request_model.dart';

class InvoiceDraftInput {
  const InvoiceDraftInput({
    required this.amount,
    required this.dueDate,
    required this.paymentMethod,
    required this.paymentInstructions,
    required this.note,
  });

  final double amount;
  final String dueDate;
  final String paymentMethod;
  final String paymentInstructions;
  final String note;
}

class _GeneratedQuotationDraft {
  const _GeneratedQuotationDraft({
    required this.amount,
    required this.dueDate,
    required this.paymentMethod,
    required this.paymentInstructions,
    required this.note,
  });

  final double amount;
  final DateTime dueDate;
  final String paymentMethod;
  final String paymentInstructions;
  final String note;
}

Future<InvoiceDraftInput?> showInvoiceDraftDialog(
  BuildContext context, {
  RequestInvoiceModel? initialInvoice,
  ServiceRequestModel? request,
}) {
  return showDialog<InvoiceDraftInput>(
    context: context,
    builder: (BuildContext dialogContext) {
      return _InvoiceDraftDialog(
        initialInvoice: initialInvoice,
        request: request,
      );
    },
  );
}

class _InvoiceDraftDialog extends StatefulWidget {
  const _InvoiceDraftDialog({this.initialInvoice, this.request});

  final RequestInvoiceModel? initialInvoice;
  final ServiceRequestModel? request;

  @override
  State<_InvoiceDraftDialog> createState() => _InvoiceDraftDialogState();
}

class _InvoiceDraftDialogState extends State<_InvoiceDraftDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _dueDateController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _noteController;
  late String _paymentMethod;
  late bool _usedGeneratedDraft;
  DateTime? _selectedDueDate;

  @override
  void initState() {
    super.initState();
    final initialInvoice = widget.initialInvoice;
    _selectedDueDate =
        initialInvoice?.dueDate ?? DateTime.now().add(const Duration(days: 7));
    _amountController = TextEditingController(
      text: initialInvoice == null
          ? ''
          : initialInvoice.amount.toStringAsFixed(2),
    );
    _dueDateController = TextEditingController(
      text: _formatDate(_selectedDueDate),
    );
    _instructionsController = TextEditingController(
      text:
          initialInvoice?.paymentInstructions ??
          'SEPA transfer. Use your invoice number as the payment reference.',
    );
    _noteController = TextEditingController(text: initialInvoice?.note ?? '');
    _paymentMethod =
        initialInvoice?.paymentMethod ?? paymentMethodSepaBankTransfer;
    _usedGeneratedDraft = false;

    if (initialInvoice == null && widget.request != null) {
      _applyGeneratedDraft();
    }
  }

  String _defaultInstructionsFor(String paymentMethod) {
    return switch (paymentMethod) {
      paymentMethodStripeCheckout =>
        'Pay securely using the hosted checkout link. A receipt will be issued after payment confirms.',
      paymentMethodCashOnCompletion =>
        'Cash payment will be collected on completion. A receipt can be issued once the team confirms payment.',
      _ => 'SEPA transfer. Use your invoice number as the payment reference.',
    };
  }

  _GeneratedQuotationDraft _generateDraftForRequest(
    ServiceRequestModel request,
  ) {
    const baseAmounts = <String, double>{
      'fire_damage_cleaning': 860,
      'needle_sweeps_sharps_cleanups': 340,
      'hoarding_cleanups': 680,
      'trauma_decomposition_cleanups': 1250,
      'infection_control_cleaning': 420,
      'building_cleaning': 220,
      'window_cleaning': 185,
      'office_cleaning': 240,
      'house_cleaning': 210,
      'warehouse_hall_cleaning': 420,
      'window_glass_cleaning': 185,
      'winter_service': 160,
      'caretaker_service': 260,
      'garden_care': 210,
      'post_construction_cleaning': 360,
    };

    final normalizedMessage = request.message.toLowerCase();
    final normalizedWindow = request.preferredTimeWindow.toLowerCase();
    final keywords = <String, int>{
      'urgent': 45,
      'asap': 45,
      'today': 45,
      'tomorrow': 35,
      'weekend': 30,
      'night': 30,
      'fire': 120,
      'smoke': 80,
      'soot': 90,
      'needle': 60,
      'sharps': 60,
      'hoarding': 140,
      'trauma': 180,
      'decomposition': 220,
      'biohazard': 150,
      'infection': 90,
      'disinfection': 75,
      'odor': 60,
      'odour': 60,
      'dust': 35,
      'machine': 30,
      'deep': 40,
      'glass': 20,
      'warehouse': 35,
      'hall': 25,
      'post-construction': 55,
    };

    var amount = baseAmounts[request.serviceType] ?? 240;
    if (normalizedMessage.length > 110) {
      amount += 35;
    }
    if (normalizedWindow.isNotEmpty &&
        !normalizedWindow.contains('flexible') &&
        !normalizedWindow.contains('business hours')) {
      amount += 20;
    }
    for (final entry in keywords.entries) {
      if (normalizedMessage.contains(entry.key)) {
        amount += entry.value;
      }
    }

    final roundedAmount = ((amount / 5).round() * 5).toDouble();
    final draftDueDate = DateTime.now().add(const Duration(days: 7));
    final paymentMethod = paymentMethodSepaBankTransfer;
    final citySegment = request.city.trim().isEmpty
        ? ''
        : ' in ${request.city}';
    final scopeHint = normalizedMessage.trim().isEmpty
        ? 'based on the service request details already shared'
        : 'based on the current work scope and access details shared in chat';
    final timeWindowNote = request.preferredTimeWindow.trim().isEmpty
        ? ''
        : ' Preferred timing: ${request.preferredTimeWindow.trim()}.';

    return _GeneratedQuotationDraft(
      amount: roundedAmount,
      dueDate: draftDueDate,
      paymentMethod: paymentMethod,
      paymentInstructions: _defaultInstructionsFor(paymentMethod),
      note:
          'Draft estimate for ${request.serviceLabel}$citySegment, prepared $scopeHint.$timeWindowNote Final price can still be adjusted after final review if scope or site access changes.',
    );
  }

  void _applyGeneratedDraft() {
    final request = widget.request;
    if (request == null) {
      return;
    }

    final generated = _generateDraftForRequest(request);
    _amountController.text = generated.amount.toStringAsFixed(2);
    _selectedDueDate = generated.dueDate;
    _dueDateController.text = _formatDate(generated.dueDate);
    _paymentMethod = generated.paymentMethod;
    _instructionsController.text = generated.paymentInstructions;
    _noteController.text = generated.note;
    _usedGeneratedDraft = true;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _dueDateController.dispose();
    _instructionsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }

    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  String _toIsoDate(DateTime value) => value.toIso8601String().split('T').first;

  Future<void> _pickDueDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _selectedDueDate = selected;
      _dueDateController.text = _formatDate(selected);
    });
  }

  void _submit() {
    final amount = double.tryParse(_amountController.text.trim());
    final dueDate = _selectedDueDate;
    final instructions = _instructionsController.text.trim();

    if (amount == null || amount <= 0) {
      _showError('Enter a valid invoice amount');
      return;
    }

    if (dueDate == null) {
      _showError('Choose a due date');
      return;
    }

    if (instructions.length < 4) {
      _showError('Add payment instructions');
      return;
    }

    Navigator.of(context).pop(
      InvoiceDraftInput(
        amount: amount,
        dueDate: _toIsoDate(dueDate),
        paymentMethod: _paymentMethod,
        paymentInstructions: instructions,
        note: _noteController.text.trim(),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send quotation'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.request != null) ...<Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                _usedGeneratedDraft
                                    ? 'AI draft filled from this request'
                                    : 'Use a quick AI draft for this request',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Temporary helper for production. Review the amount, payment option, and note before sending.',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(height: 1.35),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'The generated draft starts on a manual payment option so it still works before hosted checkout is configured.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      height: 1.3,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color
                                          ?.withValues(alpha: 0.72),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            setState(_applyGeneratedDraft);
                          },
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _usedGeneratedDraft ? 'Regenerate' : 'Generate',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quoted amount (EUR)',
                  prefixText: 'EUR ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dueDateController,
                readOnly: true,
                onTap: _pickDueDate,
                decoration: const InputDecoration(
                  labelText: 'Due date',
                  suffixIcon: Icon(Icons.event_rounded),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment option'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: paymentMethodSepaBankTransfer,
                    child: Text('SEPA bank transfer'),
                  ),
                  DropdownMenuItem(
                    value: paymentMethodStripeCheckout,
                    child: Text('Online card / wallet payment'),
                  ),
                  DropdownMenuItem(
                    value: paymentMethodCashOnCompletion,
                    child: Text('Cash on completion'),
                  ),
                ],
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _paymentMethod = value;
                    _instructionsController.text = _defaultInstructionsFor(
                      value,
                    );
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _instructionsController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Payment instructions or checkout note',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Customer note',
                  hintText: 'Optional note to show with the quotation',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Send quotation')),
      ],
    );
  }
}
