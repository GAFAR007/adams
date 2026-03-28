/// WHAT: Renders the shared internal admin/staff chat workspace backed by real database users and threads.
/// WHY: Internal chat should show actual operators from the backend, support group messaging, and keep one dark visual language across admin and staff.
/// HOW: Fetch real threads plus the active operator directory, then drive a dark messenger-style list/detail UI with direct and group creation from the `+` action.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/internal_chat_model.dart';
import '../../../shared/data/internal_chat_repository.dart';
import '../../../theme/app_theme.dart';

class InternalChatScreen extends ConsumerStatefulWidget {
  const InternalChatScreen({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.viewerRole,
  });

  final String currentUserId;
  final String currentUserName;
  final String viewerRole;

  @override
  ConsumerState<InternalChatScreen> createState() => _InternalChatScreenState();
}

class _InternalChatScreenState extends ConsumerState<InternalChatScreen> {
  final _searchController = TextEditingController();
  final _composerController = TextEditingController();
  final Set<String> _markingReadThreadIds = <String>{};
  List<InternalChatThreadModel> _threads = const <InternalChatThreadModel>[];
  List<InternalChatUserModel> _directory = const <InternalChatUserModel>[];
  _InternalChatFilter _selectedFilter = _InternalChatFilter.all;
  String? _selectedThreadId;
  bool _isLoading = true;
  bool _isSendingMessage = false;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChats();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) {
        return;
      }
      _loadChats(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    _composerController.dispose();
    super.dispose();
  }

  Future<void> _loadChats({
    bool preserveSelection = true,
    bool silent = false,
  }) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final bundle = await ref
          .read(internalChatRepositoryProvider)
          .fetchBundle(viewerRole: widget.viewerRole);

      if (!mounted) {
        return;
      }

      setState(() {
        _threads = bundle.threads;
        _directory = bundle.directory;
        _isLoading = silent ? _isLoading : false;
        if (!silent) {
          _errorMessage = null;
        }

        if (!preserveSelection) {
          _selectedThreadId = null;
          return;
        }

        if (_selectedThreadId == null) {
          return;
        }

        final stillExists = _threads.any(
          (thread) => thread.id == _selectedThreadId,
        );
        if (!stillExists) {
          _selectedThreadId = null;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        if (!silent) {
          _isLoading = false;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  List<InternalChatThreadModel> _visibleThreads() {
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _threads.where((thread) {
      final matchesFilter = switch (_selectedFilter) {
        _InternalChatFilter.all => true,
        _InternalChatFilter.unread => thread.unreadCount > 0,
        _InternalChatFilter.online => thread.hasAnyOnline,
        _InternalChatFilter.groups => thread.isGroup,
      };

      if (!matchesFilter) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final latestText = thread.latestMessage?.text.toLowerCase() ?? '';
      final memberEmails = thread.participants
          .map((participant) => participant.email.toLowerCase())
          .join(' ');
      final memberNames = thread.participantNamesLabel.toLowerCase();

      return thread.displayTitle.toLowerCase().contains(query) ||
          thread.secondaryLabel.toLowerCase().contains(query) ||
          memberNames.contains(query) ||
          memberEmails.contains(query) ||
          latestText.contains(query);
    }).toList()..sort(compareInternalChatThreadsByLatestActivity);

    return filtered;
  }

  InternalChatThreadModel? _resolveSelectedThread(
    List<InternalChatThreadModel> visibleThreads, {
    required bool preferFirst,
  }) {
    if (visibleThreads.isEmpty) {
      return null;
    }

    if (_selectedThreadId != null) {
      for (final thread in visibleThreads) {
        if (thread.id == _selectedThreadId) {
          return thread;
        }
      }
    }

    return preferFirst ? visibleThreads.first : null;
  }

  void _upsertThread(
    InternalChatThreadModel thread, {
    bool selectThread = true,
  }) {
    final updatedThreads = <InternalChatThreadModel>[
      thread,
      ..._threads.where((existing) => existing.id != thread.id),
    ]..sort(compareInternalChatThreadsByLatestActivity);

    setState(() {
      _threads = updatedThreads;
      if (selectThread) {
        _selectedThreadId = thread.id;
      }
    });
  }

  Future<void> _selectThread(InternalChatThreadModel thread) async {
    setState(() => _selectedThreadId = thread.id);

    await _markThreadReadIfNeeded(thread);
  }

  Future<void> _markThreadReadIfNeeded(InternalChatThreadModel thread) async {
    if (!thread.hasUnread || _markingReadThreadIds.contains(thread.id)) {
      return;
    }

    _markingReadThreadIds.add(thread.id);
    try {
      final updatedThread = await ref
          .read(internalChatRepositoryProvider)
          .markRead(viewerRole: widget.viewerRole, threadId: thread.id);

      if (!mounted) {
        return;
      }

      _upsertThread(updatedThread);
    } catch (_) {
      // WHY: Opening the thread is still useful even if the unread marker cannot be persisted immediately.
    } finally {
      _markingReadThreadIds.remove(thread.id);
    }
  }

  void _scheduleMarkRead(InternalChatThreadModel? thread) {
    if (thread == null ||
        !thread.hasUnread ||
        _markingReadThreadIds.contains(thread.id)) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _markThreadReadIfNeeded(thread);
    });
  }

  Future<void> _sendMessage(InternalChatThreadModel thread) async {
    final text = _composerController.text.trim();
    if (text.isEmpty || _isSendingMessage) {
      return;
    }

    setState(() => _isSendingMessage = true);

    try {
      final updatedThread = await ref
          .read(internalChatRepositoryProvider)
          .sendMessage(
            viewerRole: widget.viewerRole,
            threadId: thread.id,
            message: text,
          );

      if (!mounted) {
        return;
      }

      _composerController.clear();
      _upsertThread(updatedThread);
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
        setState(() => _isSendingMessage = false);
      }
    }
  }

  Future<void> _openNewChatSheet() async {
    final result = await showModalBottomSheet<_NewChatResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return _NewChatSheet(
          directory: _directory,
          onCreateDirect:
              (InternalChatUserModel recipient, String firstMessage) async {
                return ref
                    .read(internalChatRepositoryProvider)
                    .startDirectThread(
                      viewerRole: widget.viewerRole,
                      participantId: recipient.id,
                      message: firstMessage,
                    );
              },
          onCreateGroup:
              ({
                required String title,
                required List<String> participantIds,
                required String firstMessage,
              }) async {
                return ref
                    .read(internalChatRepositoryProvider)
                    .startGroupThread(
                      viewerRole: widget.viewerRole,
                      title: title,
                      participantIds: participantIds,
                      message: firstMessage,
                    );
              },
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    _upsertThread(result.thread);
  }

  int _totalUnreadCount() {
    return _threads.fold<int>(0, (sum, thread) => sum + thread.unreadCount);
  }

  Color _accentForUser(InternalChatUserModel user) {
    if (user.role == 'admin') {
      return AppTheme.ember;
    }

    final palette = <Color>[
      AppTheme.cobalt,
      AppTheme.pine,
      const Color(0xFF5E84F2),
      const Color(0xFF3F7E69),
    ];
    final hash = user.fullName.runes.fold<int>(0, (sum, rune) => sum + rune);
    return palette[hash % palette.length];
  }

  Color _accentForThread(InternalChatThreadModel thread) {
    if (!thread.isGroup && thread.counterpart != null) {
      return _accentForUser(thread.counterpart!);
    }

    final palette = <Color>[
      AppTheme.pine,
      AppTheme.cobalt,
      AppTheme.ember,
      const Color(0xFF6D5CE8),
    ];
    final hash = thread.displayTitle.runes.fold<int>(
      0,
      (sum, rune) => sum + rune,
    );
    return palette[hash % palette.length];
  }

  Color _accentForMessage(InternalChatMessageModel message) {
    return switch (message.senderRole) {
      'admin' => AppTheme.ember,
      'staff' => _accentForName(message.senderName),
      _ => AppTheme.cobalt,
    };
  }

  Color _accentForName(String value) {
    final palette = <Color>[
      AppTheme.cobalt,
      AppTheme.pine,
      const Color(0xFF5E84F2),
      const Color(0xFF7C68D7),
    ];
    final hash = value.runes.fold<int>(0, (sum, rune) => sum + rune);
    return palette[hash % palette.length];
  }

  String _threadPresenceLabel(InternalChatThreadModel thread) {
    if (thread.isGroup) {
      if (thread.onlineParticipantCount == 0) {
        return 'All offline';
      }
      if (thread.onlineParticipantCount == 1) {
        return '1 online';
      }
      return '${thread.onlineParticipantCount} online';
    }

    if (thread.counterpart == null) {
      return 'Offline';
    }

    return thread.counterpart!.isOnline
        ? '${thread.counterpart!.fullName} online'
        : '${thread.counterpart!.roleLabel} offline';
  }

  String _threadPreviewText(InternalChatThreadModel thread) {
    final latestMessage = thread.latestMessage;
    if (latestMessage == null) {
      return 'No messages yet. Use + to start a real chat.';
    }

    final sender = latestMessage.isOwn ? 'You' : latestMessage.senderName;
    return '$sender: ${latestMessage.text}';
  }

  String _formatThreadTimestamp(DateTime? value) {
    if (value == null) {
      return '';
    }

    final now = DateTime.now();
    final local = value.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);

    if (day == today) {
      return _formatTime(local);
    }

    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }

    return '${_monthLabel(local.month)} ${local.day}';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDayLabel(DateTime? value) {
    if (value == null) {
      return 'Today';
    }

    final now = DateTime.now();
    final local = value.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);

    if (day == today) {
      return 'Today';
    }

    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }

    return '${_monthLabel(local.month)} ${local.day}, ${local.year}';
  }

  String _monthLabel(int month) {
    return switch (month) {
      1 => 'Jan',
      2 => 'Feb',
      3 => 'Mar',
      4 => 'Apr',
      5 => 'May',
      6 => 'Jun',
      7 => 'Jul',
      8 => 'Aug',
      9 => 'Sep',
      10 => 'Oct',
      11 => 'Nov',
      _ => 'Dec',
    };
  }

  IconData _receiptIcon(String? receiptStatus) {
    return switch (receiptStatus) {
      'read' => Icons.done_all_rounded,
      'delivered' => Icons.done_all_rounded,
      _ => Icons.done_rounded,
    };
  }

  Color _receiptColor(String? receiptStatus) {
    return switch (receiptStatus) {
      'read' => const Color(0xFF9FD3FF),
      'delivered' => Colors.white.withValues(alpha: 0.82),
      _ => Colors.white.withValues(alpha: 0.68),
    };
  }

  String? _receiptCaption(String? receiptStatus) {
    return switch (receiptStatus) {
      'read' => 'seen',
      'delivered' => 'delivered',
      _ => null,
    };
  }

  Widget _buildHeader(BuildContext context) {
    final unreadCount = _totalUnreadCount();

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    'Chats',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (unreadCount > 0) ...<Widget>[
                    const SizedBox(width: 10),
                    _MetaChip(
                      icon: Icons.notifications_active_rounded,
                      label: unreadCount == 1
                          ? '1 unread'
                          : '$unreadCount unread',
                      accent: AppTheme.pine,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Signed in as ${widget.currentUserName}. Real staff and admin chats only.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.58),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _TopRoundButton(
          icon: Icons.add_rounded,
          onPressed: _directory.isEmpty ? null : _openNewChatSheet,
          backgroundColor: AppTheme.pine,
          foregroundColor: Colors.black,
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return _InputShell(
      icon: Icons.search_rounded,
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          filled: false,
          border: InputBorder.none,
          hintText: 'Search people, groups, or messages',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.42)),
        ),
      ),
    );
  }

  Widget _buildFilterChip(_InternalChatFilter filter) {
    final isSelected = _selectedFilter == filter;
    final label = switch (filter) {
      _InternalChatFilter.all => 'All',
      _InternalChatFilter.unread => 'Unread',
      _InternalChatFilter.online => 'Online',
      _InternalChatFilter.groups => 'Groups',
    };

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _selectedFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.pine.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? AppTheme.pine.withValues(alpha: 0.34)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppTheme.pine : Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildThreadTile(
    BuildContext context,
    InternalChatThreadModel thread,
    bool isSelected,
  ) {
    final accentColor = _accentForThread(thread);
    final latestMessage = thread.latestMessage;
    final previewAccent = latestMessage?.isOwn == true
        ? AppTheme.cobalt
        : _accentForMessage(
            latestMessage ??
                InternalChatMessageModel(
                  id: '',
                  senderId: '',
                  senderName: thread.displayTitle,
                  senderRole: thread.isGroup
                      ? 'staff'
                      : thread.counterpart?.role,
                  text: '',
                  createdAt: null,
                  isOwn: false,
                  receiptStatus: null,
                ),
          );

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _selectThread(thread),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.16)
              : const Color(0xFF0F1115),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? accentColor.withValues(alpha: 0.34)
                : Colors.white.withValues(alpha: 0.06),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isSelected ? 0.24 : 0.12),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ThreadAvatar(
              label: _initialsFromName(thread.displayTitle),
              accentColor: accentColor,
              showPresenceDot: !thread.isGroup && thread.hasAnyOnline,
              groupOverlay: thread.isGroup,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          thread.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatThreadTimestamp(thread.lastMessageAt),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: thread.hasUnread
                              ? AppTheme.pine
                              : Colors.white.withValues(alpha: 0.48),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    thread.isGroup
                        ? thread.participantNamesLabel
                        : thread.secondaryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        if (latestMessage != null)
                          TextSpan(
                            text:
                                '${latestMessage.isOwn ? 'You' : latestMessage.senderName}: ',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: previewAccent,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        TextSpan(
                          text:
                              latestMessage?.text ?? _threadPreviewText(thread),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.7),
                                height: 1.24,
                              ),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _MetaChip(
                        label: _threadPresenceLabel(thread),
                        accent: thread.hasAnyOnline
                            ? AppTheme.pine
                            : Colors.white54,
                        icon: thread.hasAnyOnline
                            ? Icons.circle
                            : Icons.radio_button_unchecked_rounded,
                        compact: true,
                      ),
                      if (thread.isGroup)
                        _MetaChip(
                          label: thread.secondaryLabel,
                          accent: accentColor,
                          icon: Icons.groups_rounded,
                          compact: true,
                        ),
                      if (thread.unreadCount > 0)
                        _MetaChip(
                          label: thread.unreadCount == 1
                              ? '1 new'
                              : '${thread.unreadCount} new',
                          accent: AppTheme.pine,
                          icon: Icons.mark_chat_unread_rounded,
                          compact: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyListState(BuildContext context) {
    final hasDirectory = _directory.isNotEmpty;
    final label = hasDirectory
        ? 'No chats yet. Use the + button to start a direct or group conversation.'
        : 'No active admin or staff accounts are available for internal chat yet.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Icon(
                  Icons.forum_outlined,
                  color: Colors.white.withValues(alpha: 0.78),
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.35,
              ),
            ),
            if (hasDirectory) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _openNewChatSheet,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.pine.withValues(alpha: 0.16),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Start chat'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThreadListPanel(
    BuildContext context,
    List<InternalChatThreadModel> visibleThreads,
    InternalChatThreadModel? selectedThread,
  ) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF090A0C)),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildHeader(context),
              const SizedBox(height: 16),
              _buildSearchField(context),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _buildFilterChip(_InternalChatFilter.all),
                    const SizedBox(width: 8),
                    _buildFilterChip(_InternalChatFilter.unread),
                    const SizedBox(width: 8),
                    _buildFilterChip(_InternalChatFilter.online),
                    const SizedBox(width: 8),
                    _buildFilterChip(_InternalChatFilter.groups),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                    ? _InternalChatErrorState(
                        message: _errorMessage!,
                        onRetry: _loadChats,
                      )
                    : visibleThreads.isEmpty
                    ? _buildEmptyListState(context)
                    : RefreshIndicator(
                        onRefresh: _loadChats,
                        child: ListView.separated(
                          itemCount: visibleThreads.length,
                          padding: const EdgeInsets.only(bottom: 16),
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (BuildContext context, int index) {
                            final thread = visibleThreads[index];
                            return _buildThreadTile(
                              context,
                              thread,
                              selectedThread?.id == thread.id,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    InternalChatThreadModel thread,
    InternalChatMessageModel message,
  ) {
    final isOwn = message.isOwn;
    final accentColor = isOwn ? AppTheme.cobalt : _accentForMessage(message);
    final bubbleColor = isOwn ? AppTheme.cobalt : const Color(0xFF15181D);
    final footerColor = isOwn
        ? Colors.white.withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.56);

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width < 700 ? 294 : 380,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(isOwn ? 22 : 8),
            bottomRight: Radius.circular(isOwn ? 8 : 22),
          ),
          border: Border.all(
            color: isOwn
                ? Colors.white.withValues(alpha: 0.08)
                : accentColor.withValues(alpha: 0.22),
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: isOwn
                      ? Colors.white.withValues(alpha: 0.12)
                      : accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Text(
                    isOwn ? 'You' : message.senderName,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isOwn ? Colors.white : accentColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  height: 1.34,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _formatTime(
                        message.createdAt?.toLocal() ?? DateTime.now(),
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: footerColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isOwn) ...<Widget>[
                      const SizedBox(width: 6),
                      Icon(
                        _receiptIcon(message.receiptStatus),
                        color: _receiptColor(message.receiptStatus),
                        size: 15,
                      ),
                      if (_receiptCaption(message.receiptStatus) !=
                          null) ...<Widget>[
                        const SizedBox(width: 4),
                        Text(
                          _receiptCaption(message.receiptStatus)!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: _receiptColor(message.receiptStatus),
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Row(
      mainAxisAlignment: isOwn
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (!isOwn) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ThreadAvatar(
              label: _initialsFromName(message.senderName),
              accentColor: accentColor,
              size: 30,
            ),
          ),
          const SizedBox(width: 8),
        ],
        bubble,
      ],
    );
  }

  Widget _buildThreadComposer(InternalChatThreadModel thread) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _InputShell(
                icon: Icons.chat_bubble_outline_rounded,
                child: TextField(
                  controller: _composerController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    hintText: 'Message ${thread.displayTitle}',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.42),
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(thread),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _TopRoundButton(
              icon: _isSendingMessage
                  ? Icons.hourglass_top_rounded
                  : Icons.send_rounded,
              onPressed: _isSendingMessage ? null : () => _sendMessage(thread),
              backgroundColor: AppTheme.cobalt,
              size: 46,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadDetail(
    BuildContext context,
    InternalChatThreadModel? thread, {
    VoidCallback? onBack,
  }) {
    if (thread == null) {
      return DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFF0D0E10)),
        child: Center(
          child: Text(
            'Select a real admin, staff, or group chat to open the thread.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }

    final accentColor = _accentForThread(thread);

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF0D0E10)),
      child: Column(
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: <Widget>[
                  if (onBack != null) ...<Widget>[
                    IconButton(
                      onPressed: onBack,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                  _ThreadAvatar(
                    label: _initialsFromName(thread.displayTitle),
                    accentColor: accentColor,
                    size: 42,
                    showPresenceDot: !thread.isGroup && thread.hasAnyOnline,
                    groupOverlay: thread.isGroup,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          thread.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          thread.isGroup
                              ? thread.participantNamesLabel
                              : '${thread.secondaryLabel} chat',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.58),
                              ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _MetaChip(
                              label: _threadPresenceLabel(thread),
                              accent: thread.hasAnyOnline
                                  ? AppTheme.pine
                                  : Colors.white54,
                              icon: thread.hasAnyOnline
                                  ? Icons.circle
                                  : Icons.radio_button_unchecked_rounded,
                            ),
                            if (thread.isGroup)
                              _MetaChip(
                                label: thread.secondaryLabel,
                                accent: accentColor,
                                icon: Icons.groups_rounded,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    const Color(0xFF111214),
                    accentColor.withValues(alpha: 0.08),
                    const Color(0xFF0D0E10),
                  ],
                ),
              ),
              child: thread.messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet. Send the first message below.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.68),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                      itemCount: thread.messages.length + 1,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (BuildContext context, int index) {
                        if (index == 0) {
                          return Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Text(
                                  _formatDayLabel(
                                    thread.messages.first.createdAt?.toLocal(),
                                  ),
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.62,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                          );
                        }

                        final message = thread.messages[index - 1];
                        return _buildMessageBubble(context, thread, message);
                      },
                    ),
            ),
          ),
          _buildThreadComposer(thread),
        ],
      ),
    );
  }

  String _initialsFromName(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final visibleThreads = _visibleThreads();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isWide = constraints.maxWidth >= 1040;
        final selectedThread = _resolveSelectedThread(
          visibleThreads,
          preferFirst: isWide,
        );
        _scheduleMarkRead(selectedThread);

        if (isWide) {
          return DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xFF050607)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 390,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: _buildThreadListPanel(
                        context,
                        visibleThreads,
                        selectedThread,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: _buildThreadDetail(context, selectedThread),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (selectedThread != null) {
          return _buildThreadDetail(
            context,
            selectedThread,
            onBack: () => setState(() => _selectedThreadId = null),
          );
        }

        return _buildThreadListPanel(context, visibleThreads, selectedThread);
      },
    );
  }
}

enum _InternalChatFilter { all, unread, online, groups }

enum _NewChatMode { direct, group }

class _NewChatResult {
  const _NewChatResult({required this.thread});

  final InternalChatThreadModel thread;
}

class _NewChatSheet extends StatefulWidget {
  const _NewChatSheet({
    required this.directory,
    required this.onCreateDirect,
    required this.onCreateGroup,
  });

  final List<InternalChatUserModel> directory;
  final Future<InternalChatThreadModel> Function(
    InternalChatUserModel recipient,
    String firstMessage,
  )
  onCreateDirect;
  final Future<InternalChatThreadModel> Function({
    required String title,
    required List<String> participantIds,
    required String firstMessage,
  })
  onCreateGroup;

  @override
  State<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<_NewChatSheet> {
  final _searchController = TextEditingController();
  final _groupTitleController = TextEditingController();
  final _messageController = TextEditingController();
  _NewChatMode _mode = _NewChatMode.direct;
  String? _selectedRecipientId;
  final Set<String> _selectedGroupIds = <String>{};
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    _groupTitleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  List<InternalChatUserModel> _visibleRecipients() {
    final query = _searchController.text.trim().toLowerCase();
    final users = [...widget.directory]
      ..sort((left, right) {
        final leftOnline = left.isOnline ? 0 : 1;
        final rightOnline = right.isOnline ? 0 : 1;
        if (leftOnline != rightOnline) {
          return leftOnline - rightOnline;
        }

        if (left.role != right.role) {
          return left.role == 'admin' ? -1 : 1;
        }

        return left.fullName.compareTo(right.fullName);
      });

    if (query.isEmpty) {
      return users;
    }

    return users.where((user) {
      return user.fullName.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _submit() async {
    final firstMessage = _messageController.text.trim();

    if (_mode == _NewChatMode.direct) {
      InternalChatUserModel? recipient;
      for (final user in widget.directory) {
        if (user.id == _selectedRecipientId) {
          recipient = user;
          break;
        }
      }

      if (recipient == null || firstMessage.isEmpty || _isSubmitting) {
        setState(() {
          _errorMessage =
              'Choose one recipient and write the first message before sending.';
        });
        return;
      }

      setState(() {
        _isSubmitting = true;
        _errorMessage = null;
      });

      try {
        final thread = await widget.onCreateDirect(recipient, firstMessage);
        if (!mounted) {
          return;
        }

        Navigator.of(context).pop(_NewChatResult(thread: thread));
      } catch (error) {
        if (!mounted) {
          return;
        }

        setState(() {
          _isSubmitting = false;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
      }
      return;
    }

    final title = _groupTitleController.text.trim();
    if (_selectedGroupIds.length < 2 ||
        title.isEmpty ||
        firstMessage.isEmpty ||
        _isSubmitting) {
      setState(() {
        _errorMessage =
            'Choose at least two people, add a group name, and write the first message before sending.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final thread = await widget.onCreateGroup(
        title: title,
        participantIds: _selectedGroupIds.toList(),
        firstMessage: firstMessage,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(_NewChatResult(thread: thread));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSubmitting = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _buildModeButton(
    BuildContext context,
    _NewChatMode mode,
    String label,
  ) {
    final isSelected = _mode == mode;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          setState(() {
            _mode = mode;
            _errorMessage = null;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.cobalt.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected
                  ? AppTheme.cobalt.withValues(alpha: 0.34)
                  : Colors.transparent,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipients = _visibleRecipients();

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0E10),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            top: 16,
            right: 16,
            bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _mode == _NewChatMode.direct
                    ? 'Start a real chat'
                    : 'Create a group chat',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _mode == _NewChatMode.direct
                    ? 'Choose one active admin or staff account, then send the first message.'
                    : 'Choose at least two people, name the group, and send the first message.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.62),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: <Widget>[
                      _buildModeButton(context, _NewChatMode.direct, 'Direct'),
                      _buildModeButton(context, _NewChatMode.group, 'Group'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_mode == _NewChatMode.group) ...<Widget>[
                _InputShell(
                  icon: Icons.groups_rounded,
                  child: TextField(
                    controller: _groupTitleController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      hintText: 'Group name',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _InputShell(
                icon: Icons.search_rounded,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    hintText: 'Find staff or admin',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.42),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: recipients.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            'No matching people found.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.62),
                                ),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: recipients.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final recipient = recipients[index];
                          final accentColor = recipient.role == 'admin'
                              ? AppTheme.ember
                              : AppTheme.cobalt;
                          final isSelected = _mode == _NewChatMode.direct
                              ? recipient.id == _selectedRecipientId
                              : _selectedGroupIds.contains(recipient.id);

                          return InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              setState(() {
                                if (_mode == _NewChatMode.direct) {
                                  _selectedRecipientId = recipient.id;
                                } else if (isSelected) {
                                  _selectedGroupIds.remove(recipient.id);
                                } else {
                                  _selectedGroupIds.add(recipient.id);
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? accentColor.withValues(alpha: 0.14)
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isSelected
                                      ? accentColor.withValues(alpha: 0.32)
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                children: <Widget>[
                                  _ThreadAvatar(
                                    label: _initialsFromName(
                                      recipient.fullName,
                                    ),
                                    accentColor: accentColor,
                                    size: 40,
                                    showPresenceDot: recipient.isOnline,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          recipient.fullName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          recipient.email,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.white.withValues(
                                                  alpha: 0.56,
                                                ),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (_mode == _NewChatMode.group && isSelected)
                                    Icon(
                                      Icons.check_circle_rounded,
                                      color: accentColor,
                                      size: 22,
                                    )
                                  else
                                    _MetaChip(
                                      label: recipient.isOnline
                                          ? 'Online'
                                          : 'Offline',
                                      accent: recipient.isOnline
                                          ? AppTheme.pine
                                          : Colors.white54,
                                      compact: true,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              if (_mode == _NewChatMode.group &&
                  _selectedGroupIds.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _selectedGroupIds.length == 1
                      ? '1 person selected'
                      : '${_selectedGroupIds.length} people selected',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _InputShell(
                icon: Icons.edit_rounded,
                minHeight: 122,
                alignTop: true,
                child: TextField(
                  controller: _messageController,
                  minLines: 3,
                  maxLines: 5,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    hintText: 'Write the first message',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.42),
                    ),
                  ),
                ),
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFFFA4A4),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.cobalt,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    _isSubmitting
                        ? 'Sending...'
                        : _mode == _NewChatMode.direct
                        ? 'Send first message'
                        : 'Create group and send',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initialsFromName(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return '?';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _InputShell extends StatelessWidget {
  const _InputShell({
    required this.icon,
    required this.child,
    this.minHeight = 56,
    this.alignTop = false,
  });

  final IconData icon;
  final Widget child;
  final double minHeight;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: alignTop
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(14, alignTop ? 15 : 0, 10, 0),
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.42),
              size: 20,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 14),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadAvatar extends StatelessWidget {
  const _ThreadAvatar({
    required this.label,
    required this.accentColor,
    this.size = 52,
    this.showPresenceDot = false,
    this.groupOverlay = false,
  });

  final String label;
  final Color accentColor;
  final double size;
  final bool showPresenceDot;
  final bool groupOverlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[accentColor, accentColor.withValues(alpha: 0.62)],
            ),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (groupOverlay)
          Positioned(
            right: -2,
            bottom: -2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF12151A),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF090A0C), width: 2),
              ),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(
                  Icons.groups_rounded,
                  size: 12,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        if (showPresenceDot)
          Positioned(
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.pine,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF090A0C), width: 2),
              ),
              child: const SizedBox(width: 12, height: 12),
            ),
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.accent,
    this.icon,
    this.compact = false,
  });

  final String label;
  final Color accent;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final background = accent.withValues(
      alpha: accent == Colors.white54 ? 0.08 : 0.14,
    );
    final border = accent.withValues(
      alpha: accent == Colors.white54 ? 0.14 : 0.26,
    );
    final foreground = accent == Colors.white54 ? Colors.white70 : accent;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: compact ? 12 : 14, color: foreground),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopRoundButton extends StatelessWidget {
  const _TopRoundButton({
    required this.icon,
    required this.onPressed,
    this.backgroundColor = const Color(0xFF17181B),
    this.foregroundColor = Colors.white,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(size / 2),
      onTap: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: onPressed == null
              ? backgroundColor.withValues(alpha: 0.5)
              : backgroundColor,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: foregroundColor, size: 22),
      ),
    );
  }
}

class _InternalChatErrorState extends StatelessWidget {
  const _InternalChatErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
