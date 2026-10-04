import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/core_services.dart';

class Story {
  final String id;
  final String userId;
  final String kind; // image | text
  final String? mediaUrl;
  final String? content;
  final int? bgColor;
  final DateTime createdAt;
  final Profile? author;
  bool seen;

  Story({
    required this.id,
    required this.userId,
    required this.kind,
    this.mediaUrl,
    this.content,
    this.bgColor,
    required this.createdAt,
    this.author,
    this.seen = false,
  });

  factory Story.fromMap(Map<String, dynamic> m) => Story(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        kind: (m['kind'] ?? 'image') as String,
        mediaUrl: m['media_url'] as String?,
        content: m['content'] as String?,
        bgColor: (m['bg_color'] as num?)?.toInt(),
        createdAt: DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
        author: m['author'] is Map<String, dynamic> ? Profile.fromMap(m['author'] as Map<String, dynamic>) : null,
      );
}

/// قصص مستخدم واحد (مجمّعة لشريط القصص).
class StoryGroup {
  final Profile user;
  final List<Story> stories;
  StoryGroup(this.user, this.stories);
  bool get allSeen => stories.every((s) => s.seen);
}

class StoryRepository {
  static const _author =
      'author:profiles!stories_user_id_fkey(id,username,display_name,avatar_url,xp,is_verified,is_owner,is_admin)';

  Future<List<StoryGroup>> active() async {
    final rows = await supa
        .from('stories')
        .select('*, $_author')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at')
        .limit(300);
    final stories = rows.map(Story.fromMap).toList();
    if (stories.isEmpty) return [];
    final seen = await supa
        .from('story_views')
        .select('story_id')
        .eq('viewer_id', myId!)
        .inFilter('story_id', stories.map((s) => s.id).toList());
    final seenIds = seen.map((e) => e['story_id'] as String).toSet();
    final groups = <String, StoryGroup>{};
    for (final s in stories) {
      s.seen = s.userId == myId || seenIds.contains(s.id);
      if (s.author == null) continue;
      groups.putIfAbsent(s.userId, () => StoryGroup(s.author!, [])).stories.add(s);
    }
    final list = groups.values.toList();
    // قصتي أولًا، ثم غير المشاهدة، ثم الأحدث
    list.sort((a, b) {
      if (a.user.id == myId) return -1;
      if (b.user.id == myId) return 1;
      if (a.allSeen != b.allSeen) return a.allSeen ? 1 : -1;
      return b.stories.last.createdAt.compareTo(a.stories.last.createdAt);
    });
    return list;
  }

  Future<void> addImage(Uint8List jpg) async {
    final path = '${myId!}/stories/${const Uuid().v4()}.jpg';
    await supa.storage.from('posts').uploadBinary(path, jpg,
        fileOptions: const FileOptions(contentType: 'image/jpeg'));
    final url = supa.storage.from('posts').getPublicUrl(path);
    await supa.from('stories').insert({'user_id': myId!, 'kind': 'image', 'media_url': url});
  }

  Future<void> addText(String text, int bg) =>
      supa.from('stories').insert({'user_id': myId!, 'kind': 'text', 'content': text.trim(), 'bg_color': bg});

  Future<void> markSeen(String storyId) =>
      supa.from('story_views').upsert({'story_id': storyId, 'viewer_id': myId!}, ignoreDuplicates: true);

  Future<void> delete(String storyId) => supa.from('stories').delete().eq('id', storyId);

  Future<List<Profile>> viewers(String storyId) async {
    final r = await supa
        .from('story_views')
        .select('p:profiles!story_views_viewer_id_fkey(*)')
        .eq('story_id', storyId)
        .order('viewed_at', ascending: false);
    return r.map((m) => Profile.fromMap(m['p'] as Map<String, dynamic>)).toList();
  }
}
