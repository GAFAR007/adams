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

Future<InvoiceDraftInput?> showInvoiceDraftDialog(
  BuildContext context, {
  RequestInvoiceModel? initialInvoice,
}) {
  return showDialog<InvoiceDraftInput>(
    context: context,
    builder: (BuildContext dialogContext) {
      return _InvoiceDraftDialog(initialInvoice: initialInvoice);
    },
  );
}

class _InvoiceDraftDialog extends StatefulWidget {
  const _InvoiceDraftDialog({this.initialInvoice});

  final RequestInvoiceModel? initialInvoice;

  @override
  State<_InvoiceDraftDialog> createState() => _InvoiceDraftDialogState();
}

class _InvoiceDraftDialogState extends State<_InvoiceDraftDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _dueDateController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _noteController;
  late String _paymentMethod;
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
      title: const Text('Create Invoice'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount (EUR)',
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
                    value: paymentMethodCashOnCompletion,
                    child: Text('Cash on completion'),
                  ),
                ],
                onChanged: (String? value) {
                  if (value == null) {
                    return;
                  }

                  setState(() => _paymentMethod = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _instructionsController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Payment instructions',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Customer note',
                  hintText: 'Optional note to show with the invoice',
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
        FilledButton(onPressed: _submit, child: const Text('Send invoice')),
      ],
    );
  }
}
