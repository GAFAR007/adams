/// WHAT: Renders a compact request-thread timeline for customer and staff queue conversations.
/// WHY: Both customer and staff screens need the same message presentation without duplicating bubble logic.
/// HOW: Map typed request messages into lightweight aligned cards with sender labels and timestamps.
library;

import 'package:flutter/material.dart';
import 'package:frontend/app/core/models/service_request_model.dart';
import 'package:frontend/app/theme/app_theme.dart';

class RequestThreadSection extends StatelessWidget {
  const RequestThreadSection({
    super.key,
    required this.messages,
    required this.viewerRole,
    required this.emptyLabel,
  });

  final List<RequestMessageModel> messages;
  final String viewerRole;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Text(emptyLabel, style: Theme.of(context).textTheme.bodyMedium);
    }

    return Column(
      children: messages.map((RequestMessageModel message) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _RequestMessageBubble(
            message: message,
            viewerRole: viewerRole,
          ),
        );
      }).toList(),
    );
  }
}

class _RequestMessageBubble extends StatelessWidget {
  const _RequestMessageBubble({
    required this.message,
    required this.viewerRole,
  });

  final RequestMessageModel message;
  final String viewerRole;

  bool get _isOwnMessage {
    if (viewerRole == 'customer') {
      return message.isCustomer;
    }

    if (viewerRole == 'staff') {
      return message.isStaff;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bubbleColor = switch (message.senderType) {
      'customer' => _isOwnMessage ? AppTheme.cobalt : const Color(0xFFDCE7FF),
      'staff' => _isOwnMessage ? AppTheme.pine : const Color(0xFFD8F2E8),
      'ai' => const Color(0xFFFFF1D6),
      'system' => const Color(0xFFEAE4D7),
      _ => AppTheme.clay,
    };
    final foregroundColor = _isOwnMessage ? Colors.white : AppTheme.ink;
    final alignment = _isOwnMessage
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final timestampLabel = message.createdAt == null
        ? ''
        : '${message.createdAt!.hour.toString().padLeft(2, '0')}:${message.createdAt!.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message.senderName,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message.text,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: foregroundColor),
                ),
                if (timestampLabel.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    timestampLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foregroundColor.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
