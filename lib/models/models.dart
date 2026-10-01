DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

class Profile {
  final String id;
  final String username;
  final String displayName;
  final String bio;
  final String? avatarUrl;
  final bool isAdmin;
  final bool isBanned;
  final bool notificationsEnabled;
  final DateTime? lastSeen;
  final DateTime? createdAt;
  final int xp;
  final bool isVerified;
  final bool isOwner;
  final int warnings;

  const Profile({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio = '',
    this.avatarUrl,
    this.isAdmin = false,
    this.isBanned = false,
    this.notificationsEnabled = true,
    this.lastSeen,
    this.createdAt,
    this.xp = 0,
    this.isVerified = false,
    this.isOwner = false,
    this.warnings = 0,
  });

  /// المستوى: كل 100 نقطة = مستوى، والتوثيق عند المستوى 50
  int get level => (xp ~/ 100 + 1).clamp(1, 100);
  double get levelProgress => (xp % 100) / 100;
  bool get verified => isVerified || isOwner;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        username: (m['username'] ?? '') as String,
        displayName: (m['display_name'] ?? m['username'] ?? '') as String,
        bio: (m['bio'] ?? '') as String,
        avatarUrl: m['avatar_url'] as String?,
        isAdmin: (m['is_admin'] ?? false) as bool,
        isBanned: (m['is_banned'] ?? false) as bool,
        notificationsEnabled: (m['notifications_enabled'] ?? true) as bool,
        lastSeen: _dt(m['last_seen']),
        createdAt: _dt(m['created_at']),
        xp: ((m['xp'] ?? 0) as num).toInt(),
        isVerified: (m['is_verified'] ?? false) as bool,
        isOwner: (m['is_owner'] ?? false) as bool,
        warnings: ((m['warnings'] ?? 0) as num).toInt(),
      );
}

class ConversationSummary {
  final String id;
  final String type;
  final String? name;
  final String? avatarUrl;
  final bool isPublic;
  final DateTime lastMessageAt;
  final String preview;
  final bool muted;
  final bool archived;
  final String myRole;
  final int unread;
  final String? otherUserId;
  final String? otherUsername;
  final String? otherDisplayName;
  final String? otherAvatarUrl;
  final DateTime? otherLastSeen;
  final int memberCount;
  final bool otherVerified;

  const ConversationSummary({
    required this.id,
    required this.type,
    this.name,
    this.avatarUrl,
    this.isPublic = false,
    required this.lastMessageAt,
    this.preview = '',
    this.muted = false,
    this.archived = false,
    this.myRole = 'member',
    this.unread = 0,
    this.otherUserId,
    this.otherUsername,
    this.otherDisplayName,
    this.otherAvatarUrl,
    this.otherLastSeen,
    this.memberCount = 0,
    this.otherVerified = false,
  });

  bool get isGroup => type == 'group';
  bool get isGroupAdmin => myRole == 'owner' || myRole == 'admin';
  String get title => isGroup ? (name ?? 'مجموعة') : (otherDisplayName ?? otherUsername ?? 'مستخدم');
  String? get avatar => isGroup ? avatarUrl : otherAvatarUrl;

  factory ConversationSummary.fromMap(Map<String, dynamic> m) => ConversationSummary(
        id: m['id'] as String,
        type: m['type'] as String,
        name: m['name'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        isPublic: (m['is_public'] ?? false) as bool,
        lastMessageAt: _dt(m['last_message_at']) ?? DateTime.now(),
        preview: (m['last_message_preview'] ?? '') as String,
        muted: (m['muted'] ?? false) as bool,
        archived: (m['archived'] ?? false) as bool,
        myRole: (m['my_role'] ?? 'member') as String,
        unread: ((m['unread_count'] ?? 0) as num).toInt(),
        otherUserId: m['other_user_id'] as String?,
        otherUsername: m['other_username'] as String?,
        otherDisplayName: m['other_display_name'] as String?,
        otherAvatarUrl: m['other_avatar_url'] as String?,
        otherLastSeen: _dt(m['other_last_seen']),
        memberCount: ((m['member_count'] ?? 0) as num).toInt(),
        otherVerified: (m['other_verified'] ?? false) as bool,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'name': name,
        'avatar_url': avatarUrl,
        'is_public': isPublic,
        'last_message_at': lastMessageAt.toIso8601String(),
        'last_message_preview': preview,
        'muted': muted,
        'archived': archived,
        'my_role': myRole,
        'unread_count': unread,
        'other_user_id': otherUserId,
        'other_username': otherUsername,
        'other_display_name': otherDisplayName,
        'other_avatar_url': otherAvatarUrl,
        'other_last_seen': otherLastSeen?.toIso8601String(),
        'member_count': memberCount,
        'other_verified': otherVerified,
      };
}

enum SendState { sent, pending, failed }

class Message {
  final String id;
  final String? clientId;
  final String conversationId;
  final String? senderId;
  final String type;
  final String? content;
  final String? mediaPath;
  final String? fileName;
  final int? fileSize;
  final String? replyTo;
  final bool forwarded;
  final bool pinned;
  final bool deleted;
  final DateTime? editedAt;
  final DateTime createdAt;
  final SendState state;

  const Message({
    required this.id,
    this.clientId,
    required this.conversationId,
    this.senderId,
    this.type = 'text',
    this.content,
    this.mediaPath,
    this.fileName,
    this.fileSize,
    this.replyTo,
    this.forwarded = false,
    this.pinned = false,
    this.deleted = false,
    this.editedAt,
    required this.createdAt,
    this.state = SendState.sent,
  });

  bool get isSystem => type == 'system';
  bool get hasMedia => mediaPath != null && mediaPath!.isNotEmpty;

  String get previewText {
    if (deleted) return 'رسالة محذوفة';
    switch (type) {
      case 'image':
        return '📷 صورة';
      case 'video':
        return '🎬 فيديو';
      case 'audio':
        return '🎤 رسالة صوتية';
      case 'file':
        return '📎 ${fileName ?? 'ملف'}';
      default:
        return content ?? '';
    }
  }

  factory Message.fromMap(Map<String, dynamic> m, {SendState state = SendState.sent}) => Message(
        id: m['id'] as String,
        clientId: m['client_id'] as String?,
        conversationId: m['conversation_id'] as String,
        senderId: m['sender_id'] as String?,
        type: (m['type'] ?? 'text') as String,
        content: m['content'] as String?,
        mediaPath: m['media_path'] as String?,
        fileName: m['file_name'] as String?,
        fileSize: (m['file_size'] as num?)?.toInt(),
        replyTo: m['reply_to'] as String?,
        forwarded: (m['forwarded'] ?? false) as bool,
        pinned: (m['pinned'] ?? false) as bool,
        deleted: (m['deleted'] ?? false) as bool,
        editedAt: _dt(m['edited_at']),
        createdAt: _dt(m['created_at']) ?? DateTime.now(),
        state: state,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'client_id': clientId,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'type': type,
        'content': content,
        'media_path': mediaPath,
        'file_name': fileName,
        'file_size': fileSize,
        'reply_to': replyTo,
        'forwarded': forwarded,
        'pinned': pinned,
        'deleted': deleted,
        'edited_at': editedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  Message copyWith({SendState? state}) => Message(
        id: id,
        clientId: clientId,
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        content: content,
        mediaPath: mediaPath,
        fileName: fileName,
        fileSize: fileSize,
        replyTo: replyTo,
        forwarded: forwarded,
        pinned: pinned,
        deleted: deleted,
        editedAt: editedAt,
        createdAt: createdAt,
        state: state ?? this.state,
      );
}

class Member {
  final String userId;
  final String role;
  final DateTime lastReadAt;
  final DateTime lastDeliveredAt;
  final Profile? profile;

  const Member({
    required this.userId,
    required this.role,
    required this.lastReadAt,
    required this.lastDeliveredAt,
    this.profile,
  });

  factory Member.fromMap(Map<String, dynamic> m) => Member(
        userId: m['user_id'] as String,
        role: (m['role'] ?? 'member') as String,
        lastReadAt: _dt(m['last_read_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        lastDeliveredAt: _dt(m['last_delivered_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        profile: m['profiles'] is Map<String, dynamic>
            ? Profile.fromMap(m['profiles'] as Map<String, dynamic>)
            : null,
      );

  String get roleLabel => switch (role) { 'owner' => 'المالك', 'admin' => 'مشرف', _ => 'عضو' };
}

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        type: (m['type'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        body: (m['body'] ?? '') as String,
        data: (m['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        read: (m['read'] ?? false) as bool,
        createdAt: _dt(m['created_at']) ?? DateTime.now(),
      );
}

class ContactRequest {
  final String id;
  final String senderId;
  final String receiverId;
  final String status;
  final DateTime createdAt;
  final Profile? other;

  const ContactRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    this.other,
  });

  factory ContactRequest.fromMap(Map<String, dynamic> m, String myId) {
    final senderMap = m['sender'] as Map<String, dynamic>?;
    final receiverMap = m['receiver'] as Map<String, dynamic>?;
    final isMine = m['sender_id'] == myId;
    final otherMap = isMine ? receiverMap : senderMap;
    return ContactRequest(
      id: m['id'] as String,
      senderId: m['sender_id'] as String,
      receiverId: m['receiver_id'] as String,
      status: m['status'] as String,
      createdAt: _dt(m['created_at']) ?? DateTime.now(),
      other: otherMap == null ? null : Profile.fromMap(otherMap),
    );
  }
}

class GroupSearchResult {
  final String id;
  final String name;
  final String? avatarUrl;
  final String description;

  const GroupSearchResult({required this.id, required this.name, this.avatarUrl, this.description = ''});

  factory GroupSearchResult.fromMap(Map<String, dynamic> m) => GroupSearchResult(
        id: m['id'] as String,
        name: (m['name'] ?? '') as String,
        avatarUrl: m['avatar_url'] as String?,
        description: (m['description'] ?? '') as String,
      );
}

class Post {
  final String id;
  final String authorId;
  final String content;
  final String? imageUrl;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;
  final Profile? author;
  final bool likedByMe;
  final DateTime? editedAt;

  const Post({
    required this.id,
    required this.authorId,
    required this.content,
    this.imageUrl,
    this.likeCount = 0,
    this.commentCount = 0,
    required this.createdAt,
    this.author,
    this.likedByMe = false,
    this.editedAt,
  });

  factory Post.fromMap(Map<String, dynamic> m, {bool liked = false}) => Post(
        id: m['id'] as String,
        authorId: m['author_id'] as String,
        content: (m['content'] ?? '') as String,
        imageUrl: m['image_url'] as String?,
        likeCount: ((m['like_count'] ?? 0) as num).toInt(),
        commentCount: ((m['comment_count'] ?? 0) as num).toInt(),
        createdAt: _dt(m['created_at']) ?? DateTime.now(),
        author: m['author'] is Map<String, dynamic> ? Profile.fromMap(m['author'] as Map<String, dynamic>) : null,
        likedByMe: liked,
        editedAt: _dt(m['edited_at']),
      );

  Post copyWith({int? likeCount, int? commentCount, bool? likedByMe, String? content, DateTime? editedAt}) => Post(
        id: id,
        authorId: authorId,
        content: content ?? this.content,
        editedAt: editedAt ?? this.editedAt,
        imageUrl: imageUrl,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        createdAt: createdAt,
        author: author,
        likedByMe: likedByMe ?? this.likedByMe,
      );
}

class PostComment {
  final String id;
  final String postId;
  final String authorId;
  final String content;
  final DateTime createdAt;
  final Profile? author;

  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.author,
  });

  factory PostComment.fromMap(Map<String, dynamic> m) => PostComment(
        id: m['id'] as String,
        postId: m['post_id'] as String,
        authorId: m['author_id'] as String,
        content: (m['content'] ?? '') as String,
        createdAt: _dt(m['created_at']) ?? DateTime.now(),
        author: m['author'] is Map<String, dynamic> ? Profile.fromMap(m['author'] as Map<String, dynamic>) : null,
      );
}
