import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import '../models/models.dart';
import '../services/core_services.dart';

class ChatRepository {
  static const _uuid = Uuid();

  Future<List<ConversationSummary>> myConversations() async {
    final r = await supa.rpc('get_my_conversations') as List;
    final maps = r.cast<Map<String, dynamic>>();
    await CacheService.saveConversations(maps);
    return maps.map(ConversationSummary.fromMap).toList();
  }

  List<ConversationSummary> cachedConversations() =>
      CacheService.conversations().map(ConversationSummary.fromMap).toList();

  Future<String> openDirect(String otherUserId) async {
    final r = await supa.rpc('get_or_create_direct', params: {'other': otherUserId});
    return r as String;
  }

  Future<ConversationSummary?> summary(String conversationId) async {
    final list = await myConversations();
    for (final c in list) {
      if (c.id == conversationId) return c;
    }
    return null;
  }

  /// آخر الرسائل (الأحدث أولًا) مع Pagination.
  Future<List<Message>> fetchMessages(String conversationId, {DateTime? before, int limit = AppConfig.pageSize}) async {
    var q = supa.from('messages').select().eq('conversation_id', conversationId);
    if (before != null) q = q.lt('created_at', before.toUtc().toIso8601String());
    final r = await q.order('created_at', ascending: false).limit(limit);
    final list = r.map((m) => Message.fromMap(m)).toList();
    if (before == null) {
      await CacheService.saveMessages(conversationId, r);
    }
    return list;
  }

  List<Message> cachedMessages(String conversationId) =>
      CacheService.messages(conversationId).map((m) => Message.fromMap(m)).toList();

  Future<Message?> fetchOne(String id) async {
    final r = await supa.from('messages').select().eq('id', id).maybeSingle();
    return r == null ? null : Message.fromMap(r);
  }

  String newClientId() => _uuid.v4();

  Future<Message> send({
    required String conversationId,
    required String clientId,
    String type = 'text',
    String? content,
    String? mediaPath,
    String? fileName,
    int? fileSize,
    String? replyTo,
    bool forwarded = false,
  }) async {
    try {
      final r = await supa
          .from('messages')
          .insert({
            'client_id': clientId,
            'conversation_id': conversationId,
            'sender_id': myId!,
            'type': type,
            'content': content,
            'media_path': mediaPath,
            'file_name': fileName,
            'file_size': fileSize,
            'reply_to': replyTo,
            'forwarded': forwarded,
          })
          .select()
          .single();
      return Message.fromMap(r);
    } catch (e) {
      // رسالة سبق إرسالها (إعادة محاولة بعد انقطاع)
      if (e.toString().contains('23505')) {
        final r = await supa.from('messages').select().eq('client_id', clientId).single();
        return Message.fromMap(r);
      }
      rethrow;
    }
  }

  Future<void> edit(String id, String content) =>
      supa.rpc('edit_message', params: {'mid': id, 'new_content': content});

  Future<void> delete(String id) => supa.rpc('delete_message', params: {'mid': id});

  Future<void> togglePin(String id) => supa.rpc('toggle_pin', params: {'mid': id});

  Future<List<Message>> pinned(String conversationId) async {
    final r = await supa
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .eq('pinned', true)
        .eq('deleted', false)
        .order('created_at', ascending: false)
        .limit(20);
    return r.map((m) => Message.fromMap(m)).toList();
  }

  Future<List<Message>> searchIn(String conversationId, String q) async {
    final s = q.trim().replaceAll(RegExp(r'[%_]'), '');
    if (s.isEmpty) return [];
    final r = await supa
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .eq('deleted', false)
        .ilike('content', '%$s%')
        .order('created_at', ascending: false)
        .limit(50);
    return r.map((m) => Message.fromMap(m)).toList();
  }

  Future<void> markRead(String conversationId) =>
      supa.rpc('mark_read', params: {'conv': conversationId});

  Future<void> markAllDelivered() => supa.rpc('mark_all_delivered');

  Future<void> setFlags(String conversationId, {bool? muted, bool? archived}) =>
      supa.rpc('set_conversation_flags', params: {
        'conv': conversationId,
        'is_muted': muted,
        'is_archived': archived,
      });

  Future<List<Member>> members(String conversationId) async {
    final r = await supa
        .from('conversation_members')
        .select('*, profiles(*)')
        .eq('conversation_id', conversationId)
        .order('joined_at');
    return r.map(Member.fromMap).toList();
  }

  Future<Map<String, dynamic>?> conversation(String id) =>
      supa.from('conversations').select().eq('id', id).maybeSingle();

  // ---------------- المجموعات ----------------

  Future<String> createGroup({
    required String name,
    String description = '',
    bool isPublic = false,
    required List<String> memberIds,
  }) async {
    final r = await supa.rpc('create_group', params: {
      'gname': name,
      'gdescription': description,
      'gavatar': null,
      'gpublic': isPublic,
      'member_ids': memberIds,
    });
    return r as String;
  }

  Future<void> updateGroup(String id, {String? name, String? description, String? avatarUrl, bool? isPublic}) =>
      supa.rpc('update_group', params: {
        'conv': id,
        'gname': name,
        'gdescription': description,
        'gavatar': avatarUrl,
        'gpublic': isPublic,
      });

  Future<void> addMembers(String id, List<String> userIds) =>
      supa.rpc('add_group_members', params: {'conv': id, 'member_ids': userIds});

  Future<void> removeMember(String id, String userId) =>
      supa.rpc('remove_group_member', params: {'conv': id, 'member': userId});

  Future<void> setRole(String id, String userId, String role) =>
      supa.rpc('set_member_role', params: {'conv': id, 'member': userId, 'new_role': role});

  Future<void> leave(String id) => supa.rpc('leave_conversation', params: {'conv': id});

  Future<void> deleteGroup(String id) => supa.rpc('delete_group', params: {'conv': id});

  Future<void> joinPublic(String id) => supa.rpc('join_public_group', params: {'conv': id});

  Future<List<GroupSearchResult>> searchGroups(String q) async {
    final s = q.trim().replaceAll(RegExp(r'[%_]'), '');
    if (s.isEmpty) return [];
    final r = await supa
        .from('conversations')
        .select('id, name, avatar_url, description')
        .eq('type', 'group')
        .ilike('name', '%$s%')
        .limit(30);
    return r.map(GroupSearchResult.fromMap).toList();
  }
}

/// قائمة انتظار الرسائل غير المرسلة (للعمل بدون إنترنت).
class Outbox {
  Outbox._();

  static List<Map<String, dynamic>> items() => CacheService.outbox();

  static List<Map<String, dynamic>> forConversation(String id) =>
      items().where((e) => e['conversation_id'] == id).toList();

  static Future<void> add(Map<String, dynamic> m) async {
    final l = items()..removeWhere((e) => e['client_id'] == m['client_id']);
    l.add(m);
    await CacheService.saveOutbox(l);
  }

  static Future<void> remove(String clientId) async {
    final l = items()..removeWhere((e) => e['client_id'] == clientId);
    await CacheService.saveOutbox(l);
  }

  static bool _flushing = false;

  /// إعادة إرسال الرسائل النصية المعلقة عند عودة الإنترنت.
  static Future<int> flush(ChatRepository repo) async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      for (final m in items()) {
        try {
          await repo.send(
            conversationId: m['conversation_id'] as String,
            clientId: m['client_id'] as String,
            content: m['content'] as String?,
            replyTo: m['reply_to'] as String?,
          );
          await remove(m['client_id'] as String);
          sent++;
        } on PostgrestException catch (_) {
          // رفض دائم من الخادم (حظر/خروج من المجموعة): نشيلها حتى ما توقف باقي الرسائل
          await remove(m['client_id'] as String);
        } catch (_) {
          break; // انقطاع إنترنت: نحاول لاحقًا
        }
      }
    } finally {
      _flushing = false;
    }
    return sent;
  }
}
