/// WHAT: Renders a compact request-thread timeline for customer and staff queue conversations.
/// WHY: Both customer and staff screens need the same message presentation without duplicating bubble logic.
/// HOW: Map typed request messages into chat-style bubbles for people and compact note cards for AI/system updates.
library;

import 'package:flutter/material.dart';
import 'package:frontend/app/core/models/service_request_model.dart';
import 'package:frontend/app/theme/app_theme.dart';

import '../utils/external_url_opener.dart';

class RequestThreadSection extends StatelessWidget {
  const RequestThreadSection({
    super.key,
    required this.messages,
    required this.viewerRole,
    required this.emptyLabel,
    this.dark = false,
    this.messageActionBuilder,
  });

  final List<RequestMessageModel> messages;
  final String viewerRole;
  final String emptyLabel;
  final bool dark;
  final Widget? Function(RequestMessageModel message)? messageActionBuilder;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Align(
        alignment: Alignment.center,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.1)
                  : AppTheme.clay.withValues(alpha: 0.28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              emptyLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: dark ? Colors.white.withValues(alpha: 0.76) : null,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: messages.map((RequestMessageModel message) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _RequestMessageBubble(
            message: message,
            viewerRole: viewerRole,
            dark: dark,
            messageActionBuilder: messageActionBuilder,
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
    required this.dark,
    required this.messageActionBuilder,
  });

  final RequestMessageModel message;
  final String viewerRole;
  final bool dark;
  final Widget? Function(RequestMessageModel message)? messageActionBuilder;

  bool get _isOwnMessage {
    if (viewerRole == 'customer') {
      return message.isCustomer;
    }

    if (viewerRole == 'staff') {
      return message.isStaff;
    }

    if (viewerRole == 'admin') {
      return message.isAdmin;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (message.isAi || message.isSystem) {
      return _RequestThreadNote(message: message, dark: dark);
    }

    final ownBubbleColor = switch (viewerRole) {
      'staff' => AppTheme.pine,
      'admin' => AppTheme.ember,
      _ => AppTheme.cobalt,
    };
    final incomingAccentColor = _incomingAccentFor(message);
    final bubbleColor = dark
        ? (_isOwnMessage ? ownBubbleColor : const Color(0xFF15171A))
        : _isOwnMessage
        ? ownBubbleColor
        : Colors.white.withValues(alpha: 0.92);
    final foregroundColor = dark
        ? Colors.white
        : _isOwnMessage
        ? Colors.white
        : AppTheme.ink;
    final alignment = _isOwnMessage
        ? Alignment.centerRight
        : Alignment.centerLeft;
    final timestampLabel = _formatTimestamp(message.createdAt);
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(22),
      topRight: const Radius.circular(22),
      bottomLeft: Radius.circular(_isOwnMessage ? 22 : 8),
      bottomRight: Radius.circular(_isOwnMessage ? 8 : 22),
    );
    final maxBubbleWidth = MediaQuery.sizeOf(context).width < 600
        ? MediaQuery.sizeOf(context).width * 0.74
        : 420.0;
    final action = messageActionBuilder?.call(message);
    final hasVisibleBodyText = _hasVisibleBodyText(message);
    final senderLabel = _isOwnMessage
        ? 'You'
        : message.senderName.isNotEmpty
        ? message.senderName
        : message.isCustomer
        ? 'Customer'
        : message.isStaff
        ? 'Staff'
        : message.isAdmin
        ? 'Admin'
        : 'Message';
    final footerColor = dark
        ? (_isOwnMessage
              ? Colors.white.withValues(alpha: 0.82)
              : Colors.white.withValues(alpha: 0.56))
        : foregroundColor.withValues(alpha: 0.74);

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: borderRadius,
            border: dark
                ? Border.all(
                    color: _isOwnMessage
                        ? Colors.white.withValues(alpha: 0.08)
                        : incomingAccentColor.withValues(alpha: 0.22),
                  )
                : !_isOwnMessage
                ? Border.all(color: AppTheme.clay.withValues(alpha: 0.2))
                : null,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color:
                    (dark
                            ? Colors.black
                            : (_isOwnMessage ? bubbleColor : AppTheme.ink))
                        .withValues(
                          alpha: dark
                              ? 0.18
                              : _isOwnMessage
                              ? 0.18
                              : 0.06,
                        ),
                blurRadius: dark
                    ? 16
                    : _isOwnMessage
                    ? 22
                    : 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (dark) ...<Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _isOwnMessage
                          ? Colors.white.withValues(alpha: 0.12)
                          : incomingAccentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(
                        senderLabel,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: _isOwnMessage
                                  ? Colors.white
                                  : incomingAccentColor,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else if (!_isOwnMessage &&
                    message.senderName.isNotEmpty) ...<Widget>[
                  Text(
                    message.senderName,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foregroundColor.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (message.attachment != null) ...<Widget>[
                  _RequestAttachmentTile(
                    attachment: message.attachment!,
                    foregroundColor: foregroundColor,
                    accentColor: dark ? incomingAccentColor : ownBubbleColor,
                    isOwnMessage: _isOwnMessage,
                    dark: dark,
                  ),
                  if (action != null) ...<Widget>[
                    const SizedBox(height: 10),
                    action,
                  ],
                  if (hasVisibleBodyText) const SizedBox(height: 10),
                ],
                if (hasVisibleBodyText)
                  Text(
                    message.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foregroundColor,
                      height: 1.32,
                    ),
                  ),
                if (action != null && message.attachment == null) ...<Widget>[
                  const SizedBox(height: 12),
                  action,
                ],
                if (timestampLabel.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 7),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      timestampLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: footerColor,
                        fontWeight: FontWeight.w600,
                      ),
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

class _RequestAttachmentTile extends StatelessWidget {
  const _RequestAttachmentTile({
    required this.attachment,
    required this.foregroundColor,
    required this.accentColor,
    required this.isOwnMessage,
    required this.dark,
  });

  final RequestMessageAttachmentModel attachment;
  final Color foregroundColor;
  final Color accentColor;
  final bool isOwnMessage;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fileUrl = attachment.fileUrl;
    final tileColor = dark
        ? (isOwnMessage
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.16))
        : isOwnMessage
        ? Colors.white.withValues(alpha: 0.16)
        : accentColor.withValues(alpha: 0.08);
    final borderColor = dark
        ? (isOwnMessage
              ? Colors.white.withValues(alpha: 0.12)
              : accentColor.withValues(alpha: 0.18))
        : isOwnMessage
        ? Colors.white.withValues(alpha: 0.18)
        : AppTheme.clay.withValues(alpha: 0.32);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: fileUrl == null
            ? null
            : () async {
                final opened = await openExternalUrl(fileUrl);
                if (!context.mounted || opened) {
                  return;
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Opening attachments is not supported here'),
                  ),
                );
              },
        child: Ink(
          decoration: BoxDecoration(
            color: tileColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: <Widget>[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: isOwnMessage
                        ? Colors.white.withValues(alpha: 0.14)
                        : accentColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _attachmentIconFor(attachment.mimeType),
                      color: foregroundColor,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        attachment.originalName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_attachmentTypeLabelFor(attachment.mimeType)} · ${_formatBytes(attachment.sizeBytes)}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: foregroundColor.withValues(alpha: 0.74),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: foregroundColor.withValues(alpha: 0.78),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestThreadNote extends StatelessWidget {
  const _RequestThreadNote({required this.message, required this.dark});

  final RequestMessageModel message;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = dark
        ? (message.isAi ? const Color(0xFF1A1711) : const Color(0xFF17191C))
        : message.isAi
        ? const Color(0xFFFFF1D6)
        : const Color(0xFFECE6DA);
    final timestampLabel = _formatTimestamp(message.createdAt);
    final title = message.isAi
        ? (message.senderName.trim().isNotEmpty
              ? message.senderName
              : 'Naima AI')
        : 'System update';
    final icon = message.isAi
        ? Icons.auto_awesome_rounded
        : Icons.info_outline_rounded;
    final foregroundColor = dark ? Colors.white : AppTheme.ink;

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppTheme.clay.withValues(alpha: 0.28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 15, color: foregroundColor),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  message.text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.32,
                    color: foregroundColor.withValues(alpha: dark ? 0.88 : 1),
                  ),
                ),
                if (timestampLabel.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    timestampLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: foregroundColor.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
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

String _formatTimestamp(DateTime? createdAt) {
  if (createdAt == null) {
    return '';
  }

  return '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
}

Color _incomingAccentFor(RequestMessageModel message) {
  if (message.isCustomer) {
    return AppTheme.ember;
  }

  if (message.isStaff) {
    return AppTheme.pine;
  }

  if (message.isAdmin) {
    return const Color(0xFFF0C86B);
  }

  return const Color(0xFF8DA4C8);
}

bool _hasVisibleBodyText(RequestMessageModel message) {
  final trimmedText = message.text.trim();
  if (trimmedText.isEmpty) {
    return false;
  }

  if (message.attachment == null) {
    return true;
  }

  return trimmedText != 'Shared a file' &&
      !trimmedText.startsWith('Shared a file:');
}

IconData _attachmentIconFor(String mimeType) {
  if (mimeType.startsWith('image/')) {
    return Icons.image_rounded;
  }

  if (mimeType.contains('pdf')) {
    return Icons.picture_as_pdf_rounded;
  }

  if (mimeType.contains('word') || mimeType.contains('document')) {
    return Icons.description_rounded;
  }

  if (mimeType.startsWith('text/')) {
    return Icons.notes_rounded;
  }

  return Icons.attach_file_rounded;
}

String _attachmentTypeLabelFor(String mimeType) {
  if (mimeType.startsWith('image/')) {
    return 'Image';
  }

  if (mimeType.contains('pdf')) {
    return 'PDF';
  }

  if (mimeType.contains('word') || mimeType.contains('document')) {
    return 'Document';
  }

  if (mimeType.startsWith('text/')) {
    return 'Text';
  }

  return 'File';
}

String _formatBytes(int value) {
  if (value >= 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  if (value >= 1024) {
    return '${(value / 1024).toStringAsFixed(1)} KB';
  }

  return '$value B';
}
