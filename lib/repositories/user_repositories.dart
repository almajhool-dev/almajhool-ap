import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import '../services/core_services.dart';

class AuthRepository {
  Future<bool> usernameAvailable(String username) async {
    final r = await supa.rpc('username_available', params: {'uname': username.toLowerCase()});
    return r == true;
  }

  /// يرجع true إذا تم تسجيل الدخول مباشرة، false إذا يحتاج تأكيد البريد.
  Future<bool> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    if (!await usernameAvailable(username)) {
      throw Exception('اسم المستخدم محجوز، اختر اسمًا آخر');
    }
    final res = await supa.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'username': username.toLowerCase().trim(), 'display_name': displayName.trim()},
    );
    return res.session != null;
  }

  Future<void> signIn(String email, String password) =>
      supa.auth.signInWithPassword(email: email.trim(), password: password);

  Future<void> signOut() => supa.auth.signOut();

  Future<void> sendRecovery(String email) => supa.auth.resetPasswordForEmail(email.trim());

  Future<void> resetWithCode(String email, String code, String newPassword) async {
    await supa.auth.verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.recovery);
    await supa.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> resendConfirmation(String email) =>
      supa.auth.resend(type: OtpType.signup, email: email.trim());

  Future<void> changePassword(String newPassword) =>
      supa.auth.updateUser(UserAttributes(password: newPassword));
}

class ProfileRepository {
  Future<Profile?> get(String id) async {
    final r = await supa.from('profiles').select().eq('id', id).maybeSingle();
    return r == null ? null : Profile.fromMap(r);
  }

  Future<void> update({String? displayName, String? username, String? bio, String? avatarUrl, bool? notifications}) async {
    final data = <String, dynamic>{
      if (displayName != null) 'display_name': displayName.trim(),
      if (username != null) 'username': username.trim().toLowerCase(),
      if (bio != null) 'bio': bio.trim(),
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (notifications != null) 'notifications_enabled': notifications,
    };
    if (data.isEmpty) return;
    await supa.from('profiles').update(data).eq('id', myId!);
  }

  Future<List<Profile>> search(String q) async {
    final s = q.trim().replaceAll(RegExp(r'[%,()*]'), '');
    if (s.isEmpty) return [];
    final r = await supa
        .from('profiles')
        .select()
        .or('username.ilike.%$s%,display_name.ilike.%$s%')
        .eq('is_banned', false)
        .neq('id', myId!)
        .limit(30);
    return r.map(Profile.fromMap).toList();
  }

  Future<List<Profile>> suggestions() async {
    final r = await supa.rpc('suggest_users', params: {'lim': 12}) as List;
    return r.cast<Map<String, dynamic>>().map(Profile.fromMap).toList();
  }

  Future<List<GroupSearchResult>> commonGroups(String other) async {
    final r = await supa.rpc('common_groups', params: {'other': other}) as List;
    return r.cast<Map<String, dynamic>>().map(GroupSearchResult.fromMap).toList();
  }

  Future<Set<String>> myBlocks() async {
    final r = await supa.from('blocks').select('blocked_id').eq('blocker_id', myId!);
    return r.map((e) => e['blocked_id'] as String).toSet();
  }

  Future<List<Profile>> blockedProfiles() async {
    final ids = await myBlocks();
    if (ids.isEmpty) return [];
    final r = await supa.from('profiles').select().inFilter('id', ids.toList());
    return r.map(Profile.fromMap).toList();
  }

  Future<void> block(String userId) =>
      supa.from('blocks').upsert({'blocker_id': myId!, 'blocked_id': userId});

  Future<void> unblock(String userId) =>
      supa.from('blocks').delete().eq('blocker_id', myId!).eq('blocked_id', userId);

  Future<void> report({required String reason, String? userId, String? messageId, String? conversationId}) =>
      supa.from('reports').insert({
        'reporter_id': myId!,
        'reported_user_id': userId,
        'message_id': messageId,
        'conversation_id': conversationId,
        'reason': reason,
      });
}
