/// WHAT: Renders a compact request-thread timeline for customer and staff queue conversations.
/// WHY: Both customer and staff screens need the same message presentation without duplicating bubble logic.
/// HOW: Map typed request messages into chat-style bubbles for people and compact note cards for AI/system updates.
library;

import 'package:flutter/material.dart';
import 'package:frontend/app/core/models/service_request_model.dart';
import 'package:frontend/app/theme/app_theme.dart';

import '../utils/external_url_opener.dart';

class RequestThreadSection extends StatefulWidget {
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
  State<RequestThreadSection> createState() => _RequestThreadSectionState();
}

class _RequestThreadSectionState extends State<RequestThreadSection> {
  bool _isAttachmentGalleryVisible = true;

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) {
      return Align(
        alignment: Alignment.center,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: widget.dark
                  ? Colors.white.withValues(alpha: 0.1)
                  : AppTheme.clay.withValues(alpha: 0.28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              widget.emptyLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: widget.dark
                    ? Colors.white.withValues(alpha: 0.76)
                    : null,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final attachmentEntries = widget.messages
        .where((RequestMessageModel message) => message.attachment != null)
        .map(
          (RequestMessageModel message) => _ThreadAttachmentEntry(
            message: message,
            attachment: message.attachment!,
          ),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ...widget.messages.map((RequestMessageModel message) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RequestMessageBubble(
              message: message,
              viewerRole: widget.viewerRole,
              dark: widget.dark,
              messageActionBuilder: widget.messageActionBuilder,
            ),
          );
        }),
        if (attachmentEntries.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          if (_isAttachmentGalleryVisible)
            _RequestAttachmentGallery(
              entries: attachmentEntries,
              dark: widget.dark,
              onDismiss: () {
                setState(() {
                  _isAttachmentGalleryVisible = false;
                });
              },
            )
          else
            _RequestAttachmentGalleryToggle(
              attachmentCount: attachmentEntries.length,
              dark: widget.dark,
              onPressed: () {
                setState(() {
                  _isAttachmentGalleryVisible = true;
                });
              },
            ),
        ],
      ],
    );
  }
}

class _ThreadAttachmentEntry {
  const _ThreadAttachmentEntry({
    required this.message,
    required this.attachment,
  });

  final RequestMessageModel message;
  final RequestMessageAttachmentModel attachment;
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

class _RequestAttachmentGallery extends StatelessWidget {
  const _RequestAttachmentGallery({
    required this.entries,
    required this.dark,
    required this.onDismiss,
  });

  final List<_ThreadAttachmentEntry> entries;
  final bool dark;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final titleColor = dark ? Colors.white : AppTheme.ink;
    final subtitleColor = dark
        ? Colors.white.withValues(alpha: 0.68)
        : AppTheme.ink.withValues(alpha: 0.62);
    final cardColor = dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.88);
    final borderColor = dark
        ? Colors.white.withValues(alpha: 0.08)
        : AppTheme.clay.withValues(alpha: 0.26);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.perm_media_rounded, size: 18, color: titleColor),
                const SizedBox(width: 8),
                Text(
                  'Files in chat',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: dark
                        ? Colors.white.withValues(alpha: 0.08)
                        : AppTheme.cobalt.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      '${entries.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: dark ? Colors.white : AppTheme.cobalt,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onDismiss,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: subtitleColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Every file shared in this request thread stays available here.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: subtitleColor,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 148,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (BuildContext context, int index) {
                  final entry = entries[index];
                  return _RequestAttachmentGalleryCard(
                    entry: entry,
                    dark: dark,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestAttachmentGalleryToggle extends StatelessWidget {
  const _RequestAttachmentGalleryToggle({
    required this.attachmentCount,
    required this.dark,
    required this.onPressed,
  });

  final int attachmentCount;
  final bool dark;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: dark ? Colors.white : AppTheme.cobalt,
          backgroundColor: dark
              ? Colors.white.withValues(alpha: 0.08)
              : AppTheme.cobalt.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: BorderSide(
              color: dark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppTheme.cobalt.withValues(alpha: 0.18),
            ),
          ),
        ),
        icon: const Icon(Icons.perm_media_rounded, size: 16),
        label: Text(
          'Show files ($attachmentCount)',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: dark ? Colors.white : AppTheme.cobalt,
          ),
        ),
      ),
    );
  }
}

class _RequestAttachmentGalleryCard extends StatelessWidget {
  const _RequestAttachmentGalleryCard({
    required this.entry,
    required this.dark,
  });

  final _ThreadAttachmentEntry entry;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final attachment = entry.attachment;
    final fileUrl = attachment.fileUrl;
    final senderName = entry.message.senderName.trim().isNotEmpty
        ? entry.message.senderName.trim()
        : entry.message.isCustomer
        ? 'Customer'
        : entry.message.isStaff
        ? 'Staff'
        : entry.message.isAdmin
        ? 'Admin'
        : 'Attachment';
    final accentColor = _incomingAccentFor(entry.message);
    final baseColor = dark ? const Color(0xFF121417) : Colors.white;
    final footerColor = dark
        ? Colors.white.withValues(alpha: 0.68)
        : AppTheme.ink.withValues(alpha: 0.66);

    Future<void> handleOpen() async {
      if (fileUrl == null) {
        return;
      }

      final opened = await openExternalUrl(fileUrl);
      if (!context.mounted || opened) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening attachments is not supported here'),
        ),
      );
    }

    return SizedBox(
      width: 164,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: fileUrl == null ? null : handleOpen,
          child: Ink(
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppTheme.clay.withValues(alpha: 0.24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    child: _RequestAttachmentGalleryPreview(
                      attachment: attachment,
                      accentColor: accentColor,
                      dark: dark,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        attachment.originalName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: dark ? Colors.white : AppTheme.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$senderName · ${_formatTimestamp(entry.message.createdAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: footerColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestAttachmentGalleryPreview extends StatelessWidget {
  const _RequestAttachmentGalleryPreview({
    required this.attachment,
    required this.accentColor,
    required this.dark,
  });

  final RequestMessageAttachmentModel attachment;
  final Color accentColor;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fileUrl = attachment.fileUrl;
    if (_isImageAttachment(attachment.mimeType) && fileUrl != null) {
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.network(
            fileUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _AttachmentPreviewFallback(
              attachment: attachment,
              accentColor: accentColor,
              dark: dark,
            ),
            loadingBuilder:
                (
                  BuildContext context,
                  Widget child,
                  ImageChunkEvent? loadingProgress,
                ) {
                  if (loadingProgress == null) {
                    return child;
                  }

                  return _AttachmentPreviewFallback(
                    attachment: attachment,
                    accentColor: accentColor,
                    dark: dark,
                  );
                },
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.28),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return _AttachmentPreviewFallback(
      attachment: attachment,
      accentColor: accentColor,
      dark: dark,
    );
  }
}

class _AttachmentPreviewFallback extends StatelessWidget {
  const _AttachmentPreviewFallback({
    required this.attachment,
    required this.accentColor,
    required this.dark,
  });

  final RequestMessageAttachmentModel attachment;
  final Color accentColor;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? <Color>[
                  accentColor.withValues(alpha: 0.18),
                  Colors.black.withValues(alpha: 0.12),
                ]
              : <Color>[accentColor.withValues(alpha: 0.14), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              _attachmentIconFor(attachment.mimeType),
              size: 26,
              color: dark ? Colors.white : accentColor,
            ),
            const SizedBox(height: 8),
            Text(
              _attachmentTypeLabelFor(attachment.mimeType),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: dark ? Colors.white : AppTheme.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatBytes(attachment.sizeBytes),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: dark
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppTheme.ink.withValues(alpha: 0.68),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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

bool _isImageAttachment(String mimeType) {
  return mimeType.startsWith('image/');
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
