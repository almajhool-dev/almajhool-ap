import '../models/models.dart';
import '../services/core_services.dart';

class LiveSummary {
  final String id;
  final String title;
  final Profile host;
  final int viewers;
  final int likes;
  final DateTime startedAt;
  LiveSummary(this.id, this.title, this.host, this.viewers, this.likes, this.startedAt);

  factory LiveSummary.fromMap(Map<String, dynamic> m) => LiveSummary(
        m['id'] as String,
        (m['title'] ?? '') as String,
        Profile.fromMap(Map<String, dynamic>.from(m['host'] as Map)),
        ((m['viewers'] ?? 0) as num).toInt(),
        ((m['likes'] ?? 0) as num).toInt(),
        DateTime.tryParse('${m['started_at']}')?.toLocal() ?? DateTime.now(),
      );
}

class LiveComment {
  final int id;
  final String userId;
  final String kind; // text | join | system
  final String content;
  LiveComment(this.id, this.userId, this.kind, this.content);
  factory LiveComment.fromMap(Map<String, dynamic> m) => LiveComment(
        (m['id'] as num).toInt(),
        m['user_id'] as String,
        (m['kind'] ?? 'text') as String,
        (m['content'] ?? '') as String,
      );
}

class LiveRepository {
  Future<bool> ready() async => (await supa.rpc('live_ready')) == true;

  Future<List<LiveSummary>> active() async {
    final r = await supa.rpc('active_lives') as List;
    return r.map((e) => LiveSummary.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Map<String, dynamic>> start(String title) async =>
      Map<String, dynamic>.from(await supa.rpc('live_start', params: {'p_title': title}) as Map);

  Future<Map<String, dynamic>> join(String liveId) async =>
      Map<String, dynamic>.from(await supa.rpc('live_join', params: {'p_live': liveId}) as Map);

  Future<String> heartbeat(String liveId, int viewers, int likes) async =>
      (await supa.rpc('live_heartbeat', params: {'p_live': liveId, 'p_viewers': viewers, 'p_likes': likes}))
          as String;

  Future<void> end(String liveId) => supa.rpc('live_end', params: {'p_live': liveId});

  Future<void> comment(String liveId, String text) =>
      supa.rpc('live_comment', params: {'p_live': liveId, 'p_text': text});

  Future<void> modAction(String liveId, String target, String action) =>
      supa.rpc('live_mod_action', params: {'p_live': liveId, 'p_target': target, 'p_action': action});

  Future<int> report(String liveId, String reason) async =>
      ((await supa.rpc('live_report', params: {'p_live': liveId, 'p_reason': reason})) as num).toInt();

  Future<List<LiveComment>> recentComments(String liveId) async {
    final r = await supa
        .from('live_comments')
        .select()
        .eq('live_id', liveId)
        .order('id', ascending: false)
        .limit(40);
    return r.map(LiveComment.fromMap).toList().reversed.toList();
  }

  // ---- المدير ----
  Future<void> configure(String url, String key, String secret) =>
      supa.rpc('admin_set_live', params: {'p_url': url, 'p_key': key, 'p_secret': secret});

  Future<List<Map<String, dynamic>>> adminLives() async =>
      (await supa.rpc('admin_lives') as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<List<Map<String, dynamic>>> adminPenalties() async =>
      (await supa.rpc('admin_live_penalties') as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Future<String> violation(String liveId) async =>
      (await supa.rpc('admin_live_violation', params: {'p_live': liveId})) as String;

  Future<void> unban(String userId) => supa.rpc('admin_live_unban', params: {'p_user': userId});
}
