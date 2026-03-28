/// WHAT: Renders a reusable message composer for request-thread replies.
/// WHY: Customer and staff screens both need the same small send-message control with consistent button states.
/// HOW: Accept an external controller plus submit callback and render a text field with shared enabled/loading behavior.
library;

import 'package:flutter/material.dart';

class RequestMessageComposer extends StatelessWidget {
  const RequestMessageComposer({
    super.key,
    required this.controller,
    required this.hintText,
    required this.buttonLabel,
    required this.isSubmitting,
    required this.isEnabled,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String hintText;
  final String buttonLabel;
  final bool isSubmitting;
  final bool isEnabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            enabled: isEnabled && !isSubmitting,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(hintText: hintText),
            onSubmitted: (_) {
              // WHY: Keyboard submit should reuse the same guarded callback path as the button to keep behavior consistent.
              if (isEnabled && !isSubmitting) {
                onSubmit();
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: !isEnabled || isSubmitting ? null : onSubmit,
          child: Text(isSubmitting ? 'Sending...' : buttonLabel),
        ),
      ],
    );
  }
}
