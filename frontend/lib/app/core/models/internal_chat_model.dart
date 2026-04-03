/// WHAT: Defines internal admin/staff chat models used by the shared internal messenger UI.
/// WHY: Admin and staff should parse the same backend chat contract once before rendering direct and group threads.
/// HOW: Map directory users, typed chat threads, and receipt-aware messages into immutable Dart models with UI-friendly getters.
library;

import '../../config/app_config.dart';

String? _resolveAbsoluteFileUrl(String relativeUrl) {
  if (relativeUrl.trim().isEmpty) {
    return null;
  }

  final apiBaseUri = Uri.tryParse(AppConfig.apiBaseUrl);
  final relativeUri = Uri.tryParse(relativeUrl);
  if (apiBaseUri == null || relativeUri == null) {
    return relativeUrl;
  }

  return apiBaseUri.resolveUri(relativeUri).toString();
}

class InternalChatUserModel {
  const InternalChatUserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.staffType,
    required this.status,
    required this.staffAvailability,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String fullName;
  final String email;
  final String? phone;
  final String role;
  final String? staffType;
  final String status;
  final String? staffAvailability;

  bool get isOnline => staffAvailability == 'online';
  String get roleLabel {
    switch (staffType) {
      case 'customer_care':
        return 'Customer Care';
      case 'contractor':
        return 'Contractor';
      case 'technician':
        return 'Technician';
      default:
        return role == 'admin' ? 'Admin' : 'Staff';
    }
  }

  String get shortName =>
      firstName.trim().isNotEmpty ? firstName.trim() : fullName;

  factory InternalChatUserModel.fromJson(Map<String, dynamic> json) {
    return InternalChatUserModel(
      id: json['id'] as String? ?? '',
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String?,
      role: json['role'] as String? ?? 'staff',
      staffType: json['staffType'] as String?,
      status: json['status'] as String? ?? 'active',
      staffAvailability: json['staffAvailability'] as String?,
    );
  }
}

class InternalChatAttachmentModel {
  const InternalChatAttachmentModel({
    required this.originalName,
    required this.storedName,
    required this.mimeType,
    required this.sizeBytes,
    required this.relativeUrl,
  });

  final String originalName;
  final String storedName;
  final String mimeType;
  final int sizeBytes;
  final String relativeUrl;

  String? get fileUrl => _resolveAbsoluteFileUrl(relativeUrl);

  factory InternalChatAttachmentModel.fromJson(Map<String, dynamic> json) {
    return InternalChatAttachmentModel(
      originalName: json['originalName'] as String? ?? '',
      storedName: json['storedName'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      relativeUrl: json['relativeUrl'] as String? ?? '',
    );
  }
}

class InternalChatMessageModel {
  const InternalChatMessageModel({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.text,
    required this.attachment,
    required this.createdAt,
    required this.isOwn,
    required this.receiptStatus,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String? senderRole;
  final String text;
  final InternalChatAttachmentModel? attachment;
  final DateTime? createdAt;
  final bool isOwn;
  final String? receiptStatus;

  factory InternalChatMessageModel.fromJson(Map<String, dynamic> json) {
    return InternalChatMessageModel(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      senderName: json['senderName'] as String? ?? '',
      senderRole: json['senderRole'] as String?,
      text: json['text'] as String? ?? '',
      attachment: json['attachment'] is Map<String, dynamic>
          ? InternalChatAttachmentModel.fromJson(
              json['attachment'] as Map<String, dynamic>,
            )
          : null,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      isOwn: json['isOwn'] as bool? ?? false,
      receiptStatus: json['receiptStatus'] as String?,
    );
  }
}

class InternalChatThreadModel {
  const InternalChatThreadModel({
    required this.id,
    required this.threadType,
    required this.title,
    required this.counterpart,
    required this.participants,
    required this.participantCount,
    required this.onlineParticipantCount,
    required this.unreadCount,
    required this.messageCount,
    required this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String threadType;
  final String? title;
  final InternalChatUserModel? counterpart;
  final List<InternalChatUserModel> participants;
  final int participantCount;
  final int onlineParticipantCount;
  final int unreadCount;
  final int messageCount;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<InternalChatMessageModel> messages;

  bool get isGroup => threadType == 'group';
  bool get hasUnread => unreadCount > 0;
  bool get hasAnyOnline =>
      isGroup ? onlineParticipantCount > 0 : (counterpart?.isOnline ?? false);
  InternalChatMessageModel? get latestMessage =>
      messages.isEmpty ? null : messages.last;

  String get displayTitle {
    if (isGroup) {
      final cleanedTitle = title?.trim() ?? '';
      if (cleanedTitle.isNotEmpty) {
        return cleanedTitle;
      }

      if (participants.isEmpty) {
        return 'Group chat';
      }

      final names = participants
          .map((participant) => participant.shortName)
          .where((name) => name.trim().isNotEmpty)
          .take(3)
          .join(', ');
      return names.isEmpty ? 'Group chat' : names;
    }

    return counterpart?.fullName ?? 'Direct chat';
  }

  String get secondaryLabel {
    if (isGroup) {
      final memberLabel = participantCount == 1
          ? '1 member'
          : '$participantCount members';
      if (onlineParticipantCount > 0) {
        final onlineLabel = onlineParticipantCount == 1
            ? '1 online'
            : '$onlineParticipantCount online';
        return '$memberLabel · $onlineLabel';
      }
      return memberLabel;
    }

    return counterpart?.roleLabel ?? 'Direct chat';
  }

  String get participantNamesLabel {
    if (participants.isEmpty) {
      return secondaryLabel;
    }

    return participants.map((participant) => participant.fullName).join(', ');
  }

  factory InternalChatThreadModel.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List<dynamic>? ?? const <dynamic>[];
    final rawParticipants =
        json['participants'] as List<dynamic>? ?? const <dynamic>[];

    return InternalChatThreadModel(
      id: json['id'] as String? ?? '',
      threadType: json['threadType'] as String? ?? 'direct',
      title: json['title'] as String?,
      counterpart: (json['counterpart'] as Map<String, dynamic>?)?.let(
        InternalChatUserModel.fromJson,
      ),
      participants: rawParticipants
          .whereType<Map<String, dynamic>>()
          .map(InternalChatUserModel.fromJson)
          .toList(),
      participantCount: json['participantCount'] as int? ?? 0,
      onlineParticipantCount: json['onlineParticipantCount'] as int? ?? 0,
      unreadCount: json['unreadCount'] as int? ?? 0,
      messageCount: json['messageCount'] as int? ?? 0,
      lastMessageAt: DateTime.tryParse(json['lastMessageAt'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      messages: rawMessages
          .whereType<Map<String, dynamic>>()
          .map(InternalChatMessageModel.fromJson)
          .toList(),
    );
  }
}

class InternalChatBundle {
  const InternalChatBundle({required this.threads, required this.directory});

  final List<InternalChatThreadModel> threads;
  final List<InternalChatUserModel> directory;

  int get totalUnreadCount =>
      threads.fold<int>(0, (sum, thread) => sum + thread.unreadCount);

  factory InternalChatBundle.fromJson(Map<String, dynamic> json) {
    final rawThreads = json['threads'] as List<dynamic>? ?? const <dynamic>[];
    final rawDirectory =
        json['directory'] as List<dynamic>? ?? const <dynamic>[];

    final threads =
        rawThreads
            .whereType<Map<String, dynamic>>()
            .map(InternalChatThreadModel.fromJson)
            .toList()
          ..sort(compareInternalChatThreadsByLatestActivity);
    final directory = rawDirectory
        .whereType<Map<String, dynamic>>()
        .map(InternalChatUserModel.fromJson)
        .toList();

    return InternalChatBundle(threads: threads, directory: directory);
  }
}

int compareInternalChatThreadsByLatestActivity(
  InternalChatThreadModel left,
  InternalChatThreadModel right,
) {
  final leftTime = left.lastMessageAt ?? left.updatedAt ?? left.createdAt;
  final rightTime = right.lastMessageAt ?? right.updatedAt ?? right.createdAt;

  if (leftTime == null && rightTime == null) {
    return left.displayTitle.compareTo(right.displayTitle);
  }

  if (leftTime == null) {
    return 1;
  }

  if (rightTime == null) {
    return -1;
  }

  return rightTime.compareTo(leftTime);
}

extension on Map<String, dynamic> {
  T let<T>(T Function(Map<String, dynamic> value) transform) => transform(this);
}
