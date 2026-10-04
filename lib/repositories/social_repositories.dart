import '../models/models.dart';
import '../services/core_services.dart';

class ContactRepository {
  static const _select =
      '*, sender:profiles!contact_requests_sender_id_fkey(*), receiver:profiles!contact_requests_receiver_id_fkey(*)';

  Future<List<ContactRequest>> _all() async {
    final uid = myId!;
    final r = await supa
        .from('contact_requests')
        .select(_select)
        .or('sender_id.eq.$uid,receiver_id.eq.$uid')
        .order('created_at', ascending: false);
    return r.map((m) => ContactRequest.fromMap(m, uid)).toList();
  }

  Future<({List<ContactRequest> incoming, List<ContactRequest> outgoing, List<Profile> contacts})> load() async {
    final all = await _all();
    final uid = myId!;
    return (
      incoming: all.where((r) => r.status == 'pending' && r.receiverId == uid).toList(),
      outgoing: all.where((r) => r.status == 'pending' && r.senderId == uid).toList(),
      contacts: all.where((r) => r.status == 'accepted' && r.other != null).map((r) => r.other!).toList(),
    );
  }

  /// حالة العلاقة مع مستخدم: none | pending_out | pending_in | accepted
  Future<(String, String?)> statusWith(String userId) async {
    final uid = myId!;
    final r = await supa
        .from('contact_requests')
        .select('id, sender_id, status')
        .or('and(sender_id.eq.$uid,receiver_id.eq.$userId),and(sender_id.eq.$userId,receiver_id.eq.$uid)')
        .maybeSingle();
    if (r == null || r['status'] == 'rejected') return ('none', null);
    if (r['status'] == 'accepted') return ('accepted', r['id'] as String);
    return (r['sender_id'] == uid ? 'pending_out' : 'pending_in', r['id'] as String);
  }

  Future<void> send(String userId) => supa.rpc('send_contact_request', params: {'target': userId});

  Future<void> respond(String requestId, bool accept) =>
      supa.rpc('respond_contact_request', params: {'req': requestId, 'accept': accept});

  Future<void> remove(String userId) => supa.rpc('remove_contact', params: {'target': userId});

  // ---- المتابعة ----
  Future<void> follow(String userId) => supa.from('follows').insert({'follower_id': myId!, 'followee_id': userId});

  Future<void> unfollow(String userId) =>
      supa.from('follows').delete().eq('follower_id', myId!).eq('followee_id', userId);

  /// أعداد الملف الشخصي: friends, followers, following, posts, i_follow
  Future<Map<String, dynamic>> counts(String userId) async {
    final r = await supa.rpc('profile_counts', params: {'uid': userId});
    return Map<String, dynamic>.from(r as Map);
  }

  /// قائمة: friends | followers | following
  Future<List<Profile>> people(String userId, String kind) async {
    if (kind == 'friends') {
      final r = await supa
          .from('contact_requests')
          .select('sender:profiles!contact_requests_sender_id_fkey(*), receiver:profiles!contact_requests_receiver_id_fkey(*)')
          .eq('status', 'accepted')
          .or('sender_id.eq.$userId,receiver_id.eq.$userId')
          .limit(500);
      return r.map((m) {
        final s = m['sender'] as Map<String, dynamic>;
        final rc = m['receiver'] as Map<String, dynamic>;
        return Profile.fromMap(s['id'] == userId ? rc : s);
      }).toList();
    }
    final followers = kind == 'followers';
    final r = await supa
        .from('follows')
        .select(followers
            ? 'p:profiles!follows_follower_id_fkey(*)'
            : 'p:profiles!follows_followee_id_fkey(*)')
        .eq(followers ? 'followee_id' : 'follower_id', userId)
        .order('created_at', ascending: false)
        .limit(500);
    return r.map((m) => Profile.fromMap(m['p'] as Map<String, dynamic>)).toList();
  }
}

class NotificationRepository {
  Future<List<AppNotification>> list() async {
    final r = await supa
        .from('notifications')
        .select()
        .eq('user_id', myId!)
        .order('created_at', ascending: false)
        .limit(100);
    return r.map(AppNotification.fromMap).toList();
  }

  Future<int> unreadCount() async {
    final r = await supa
        .from('notifications')
        .select('id')
        .eq('user_id', myId!)
        .eq('read', false)
        .limit(100);
    return r.length;
  }

  Future<void> markAllRead() =>
      supa.from('notifications').update({'read': true}).eq('user_id', myId!).eq('read', false);

  Future<void> clearAll() => supa.from('notifications').delete().eq('user_id', myId!);
}

class AdminRepository {
  Future<Map<String, dynamic>> stats() async {
    final r = await supa.rpc('admin_stats');
    return (r as Map).cast<String, dynamic>();
  }

  Future<void> setApp(bool enabled, String message) =>
      supa.rpc('admin_set_app', params: {'enabled': enabled, 'message': message});

  Future<List<Profile>> users(String q) async {
    final s = q.trim().replaceAll(RegExp(r'[%,()*]'), '');
    var query = supa.from('profiles').select();
    if (s.isNotEmpty) query = query.or('username.ilike.%$s%,display_name.ilike.%$s%');
    final r = await query.order('created_at', ascending: false).limit(100);
    return r.map(Profile.fromMap).toList();
  }

  Future<void> setBan(String userId, bool banned) =>
      supa.rpc('admin_set_ban', params: {'target': userId, 'banned': banned});

  Future<int> warn(String userId, String reason) async {
    final r = await supa.rpc('admin_warn', params: {'target': userId, 'reason': reason});
    return (r as num?)?.toInt() ?? 0;
  }

  Future<void> setPassword(String userId, String password) =>
      supa.rpc('admin_set_password', params: {'target': userId, 'new_password': password});

  Future<void> clearWarnings(String userId) =>
      supa.rpc('admin_clear_warnings', params: {'target': userId});

  Future<bool> turnConfigured() async => (await supa.rpc('admin_turn_status')) == true;

  Future<void> setTurn(String user, String pass) =>
      supa.rpc('admin_set_turn', params: {'turn_user': user, 'turn_pass': pass});

  Future<void> setVerified(String userId, bool verified) =>
      supa.rpc('admin_set_verified', params: {'target': userId, 'verified': verified});

  Future<List<Post>> posts() async {
    final r = await supa
        .from('posts')
        .select('*, author:profiles!posts_author_id_fkey(id,username,display_name,avatar_url,xp,is_verified,is_owner)')
        .eq('deleted', false)
        .order('created_at', ascending: false)
        .limit(100);
    return r.map((m) => Post.fromMap(m)).toList();
  }

  Future<void> deletePost(String id) => supa.rpc('delete_post', params: {'pid': id});

  Future<void> setAdmin(String userId, bool admin) =>
      supa.rpc('admin_set_role', params: {'target': userId, 'make_admin': admin});

  Future<List<Map<String, dynamic>>> reports() async {
    final r = await supa.rpc('admin_list_reports') as List;
    return r.cast<Map<String, dynamic>>();
  }

  Future<void> resolveReport(String id, {bool deleteMessage = false}) =>
      supa.rpc('admin_resolve_report', params: {'rid': id, 'delete_msg': deleteMessage});

  Future<List<Map<String, dynamic>>> groups() async {
    final r = await supa.rpc('admin_list_groups') as List;
    return r.cast<Map<String, dynamic>>();
  }

  Future<void> deleteGroup(String id) => supa.rpc('delete_group', params: {'conv': id});

  Future<int> broadcast(String title, String body) async {
    final r = await supa.rpc('admin_broadcast', params: {'ntitle': title, 'nbody': body});
    return (r as num?)?.toInt() ?? 0;
  }
}
