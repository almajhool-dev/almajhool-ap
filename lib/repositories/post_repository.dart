import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/core_services.dart';
import '../services/xfile_util.dart';

class PostRepository {
  static const _author =
      'author:profiles!posts_author_id_fkey(id,username,display_name,avatar_url,xp,is_verified,is_owner,is_admin)';
  static const _commentAuthor =
      'author:profiles!post_comments_author_id_fkey(id,username,display_name,avatar_url,xp,is_verified,is_owner)';
  static const pageSize = 15;

  Future<List<Post>> _withLikes(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['id'] as String).toList();
    final liked = await supa
        .from('post_likes')
        .select('post_id, reaction')
        .eq('user_id', myId!)
        .inFilter('post_id', ids);
    final map = {for (final e in liked) e['post_id'] as String: e['reaction'] as String?};
    return rows
        .map((r) => Post.fromMap({...r, '_reaction': map[r['id']]}, liked: map.containsKey(r['id'])))
        .toList();
  }

  Future<List<Post>> feed({DateTime? before, String? authorId}) async {
    // طلب واحد للسيرفر (المنشورات + الكاتب + إعجابي) بدل طلبين
    try {
      final r = await supa.rpc('feed_page', params: {
        'p_before': before?.toUtc().toIso8601String(),
        'p_author': authorId,
        'p_limit': pageSize,
      }) as List;
      final rows = r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final posts = rows.map((m) => Post.fromMap(m, liked: m['_liked'] == true)).toList();
      if (before == null && authorId == null) {
        await CacheService.writeList('feed', rows);
      }
      return posts;
    } catch (e) {
      if (!'$e'.contains('PGRST202') && !'$e'.contains('feed_page')) rethrow;
    }
    var q = supa.from('posts').select('*, $_author').eq('deleted', false);
    if (authorId != null) q = q.eq('author_id', authorId);
    if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
    final rows = await q.order('created_at', ascending: false).limit(pageSize);
    final posts = await _withLikes(rows);
    if (before == null && authorId == null) {
      // تخزين الصفحة الأولى لعرض فوري عند فتح التطبيق حتى مع إنترنت ضعيف
      final liked = posts.where((p) => p.likedByMe).map((p) => p.id).toSet();
      await CacheService.writeList('feed', rows.map((r) => {...r, '_liked': liked.contains(r['id'])}).toList());
    }
    return posts;
  }

  List<Post> cachedFeed() => CacheService.readList('feed')
      .map((r) => Post.fromMap(r, liked: (r['_liked'] ?? false) as bool))
      .toList();

  Future<void> edit(String postId, String content) =>
      supa.rpc('edit_post', params: {'pid': postId, 'new_content': content.trim()});

  Future<Post?> one(String id) async {
    try {
      final j = await supa.rpc('post_one', params: {'p_id': id});
      if (j is Map) return Post.fromMap(Map<String, dynamic>.from(j), liked: j['_liked'] == true);
      if (j == null) return null;
    } catch (_) {}
    final r = await supa.from('posts').select('*, $_author').eq('id', id).maybeSingle();
    if (r == null) return null;
    return (await _withLikes([r])).first;
  }

  Future<void> create({required String content, File? image}) async {
    String? url;
    if (image != null) {
      final path = '${myId!}/${const Uuid().v4()}.jpg';
      await supa.storage.from('posts').upload(
            path,
            image,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      url = supa.storage.from('posts').getPublicUrl(path);
    }
    await supa.from('posts').insert({
      'author_id': myId!,
      'content': content.trim(),
      'image_url': url,
    });
  }

  /// إنشاء أو تعديل منشور (النص، الصورة، الألوان، والخصوصية).
  Future<String> save({
    String? id,
    required String content,
    Uint8List? newImage,
    String? keepImageUrl,
    int? textColor,
    int? bgColor,
    String visibility = 'public',
    List<String> audience = const [],
    XFile? newVideo,
    String? keepVideoUrl,
    bool capcut = false,
    Uint8List? videoPoster,
  }) async {
    var url = keepImageUrl;
    var video = keepVideoUrl;
    if (newVideo != null) {
      final size = await newVideo.length();
      if (size > 50 * 1024 * 1024) throw Exception('الفيديو كبير، اختاره مرة ثانية حتى ينضغط تلقائيًا');
      final name = '${newVideo.name} ${newVideo.path}'.toLowerCase();
      final ext = name.contains('.mov') ? 'mov' : (name.contains('.webm') ? 'webm' : 'mp4');
      final path = '${myId!}/${const Uuid().v4()}.$ext';
      await uploadXFile('posts', path, newVideo, ext == 'mov' ? 'video/quicktime' : 'video/$ext');
      video = supa.storage.from('posts').getPublicUrl(path);
      if (videoPoster != null) {
        try {
          await supa.storage.from('posts').uploadBinary(
                path.replaceFirst(RegExp(r'\.[a-z0-9]+$'), '.poster.jpg'),
                videoPoster,
                fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
              );
        } catch (_) {}
      }
    }
    if (newImage != null) {
      final path = '${myId!}/${const Uuid().v4()}.jpg';
      await supa.storage.from('posts').uploadBinary(
            path,
            newImage,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      url = supa.storage.from('posts').getPublicUrl(path);
    }
    try {
      final r = await supa.rpc('save_post2', params: {
        'pid': id,
        'p_content': content.trim(),
        'p_image': video != null ? null : url,
        'p_video': video,
        'p_made_with': video != null && capcut ? 'capcut' : null,
        'p_text_color': textColor,
        'p_bg_color': bgColor,
        'p_visibility': visibility,
        'p_audience': visibility == 'custom' ? audience : null,
      });
      return r as String;
    } catch (e) {
      // خادم قديم ما بيه دالة الفيديو بعد
      if (!'$e'.contains('PGRST202') || video != null) rethrow;
    }
    final r = await supa.rpc('save_post', params: {
      'pid': id,
      'p_content': content.trim(),
      'p_image': url,
      'p_text_color': textColor,
      'p_bg_color': bgColor,
      'p_visibility': visibility,
      'p_audience': visibility == 'custom' ? audience : null,
    });
    return r as String;
  }

  Future<List<String>> audience(String postId) async {
    final r = await supa.from('post_audience').select('user_id').eq('post_id', postId);
    return r.map((e) => e['user_id'] as String).toList();
  }

  Future<void> like(String postId, [String reaction = 'like']) =>
      supa.from('post_likes').upsert({'post_id': postId, 'user_id': myId!, 'reaction': reaction});

  /// مشاركة منشور على صفحتي مع كلام فوقه (مثل فيسبوك)
  Future<void> share(String postId, String caption) async {
    await supa.from('posts').insert({
      'author_id': myId!,
      'content': caption.trim(),
      'shared_post_id': postId,
    });
  }

  /// منو تفاعل على المنشور
  Future<List<Map<String, dynamic>>> reactors(String postId, {String? reaction}) async {
    final r = await supa.rpc('post_reactors', params: {'p_post': postId, 'p_reaction': reaction});
    return [for (final e in r as List) Map<String, dynamic>.from(e as Map)];
  }

  /// الريلز: منشورات الفيديو
  Future<List<Post>> reels({DateTime? before}) async {
    final r = await supa.rpc('reels_page', params: {'p_before': before?.toUtc().toIso8601String(), 'p_limit': 10}) as List;
    return [for (final e in r) Post.fromMap(Map<String, dynamic>.from(e as Map), liked: (e as Map)['_liked'] == true)];
  }

  Future<void> unlike(String postId) =>
      supa.from('post_likes').delete().eq('post_id', postId).eq('user_id', myId!);

  Future<void> delete(String postId) => supa.rpc('delete_post', params: {'pid': postId});

  Future<List<PostComment>> comments(String postId) async {
    final r = await supa
        .from('post_comments')
        .select('*, $_commentAuthor')
        .eq('post_id', postId)
        .order('created_at')
        .limit(500);
    final ids = [for (final c in r) c['id'] as String];
    var mine = <String>{};
    if (ids.isNotEmpty) {
      try {
        final l = await supa.from('comment_likes').select('comment_id').eq('user_id', myId!).inFilter('comment_id', ids);
        mine = {for (final e in l) e['comment_id'] as String};
      } catch (_) {}
    }
    return [for (final c in r) PostComment.fromMap({...c, '_liked': mine.contains(c['id'])})];
  }

  Future<void> likeComment(String id, bool like) => like
      ? supa.from('comment_likes').upsert({'comment_id': id, 'user_id': myId!})
      : supa.from('comment_likes').delete().eq('comment_id', id).eq('user_id', myId!);

  Future<void> comment(String postId, String content, {String? parentId}) => supa.from('post_comments').insert({
        'post_id': postId,
        'author_id': myId!,
        'content': content.trim(),
        if (parentId != null) 'parent_id': parentId,
      });

  Future<void> deleteComment(String id) => supa.rpc('delete_comment', params: {'cid': id});

  Future<String?> ownerId() async {
    final r = await supa.rpc('get_owner_id');
    return r as String?;
  }
}
