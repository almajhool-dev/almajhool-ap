import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/core_services.dart';

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
        .select('post_id')
        .eq('user_id', myId!)
        .inFilter('post_id', ids);
    final set = liked.map((e) => e['post_id'] as String).toSet();
    return rows.map((r) => Post.fromMap(r, liked: set.contains(r['id']))).toList();
  }

  Future<List<Post>> feed({DateTime? before, String? authorId}) async {
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
  }) async {
    var url = keepImageUrl;
    if (newImage != null) {
      final path = '${myId!}/${const Uuid().v4()}.jpg';
      await supa.storage.from('posts').uploadBinary(
            path,
            newImage,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      url = supa.storage.from('posts').getPublicUrl(path);
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

  Future<void> like(String postId) =>
      supa.from('post_likes').upsert({'post_id': postId, 'user_id': myId!});

  Future<void> unlike(String postId) =>
      supa.from('post_likes').delete().eq('post_id', postId).eq('user_id', myId!);

  Future<void> delete(String postId) => supa.rpc('delete_post', params: {'pid': postId});

  Future<List<PostComment>> comments(String postId) async {
    final r = await supa
        .from('post_comments')
        .select('*, $_commentAuthor')
        .eq('post_id', postId)
        .order('created_at')
        .limit(200);
    return r.map(PostComment.fromMap).toList();
  }

  Future<void> comment(String postId, String content) => supa.from('post_comments').insert({
        'post_id': postId,
        'author_id': myId!,
        'content': content.trim(),
      });

  Future<void> deleteComment(String id) => supa.rpc('delete_comment', params: {'cid': id});

  Future<String?> ownerId() async {
    final r = await supa.rpc('get_owner_id');
    return r as String?;
  }
}
