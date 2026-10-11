import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'core_services.dart';

class CouplePartner {
  final String id;
  final String name;
  final String username;
  final String? avatar;
  final bool verified;
  CouplePartner(this.id, this.name, this.username, this.avatar, this.verified);
}

class CoupleStatus {
  final bool linked;
  final String? coupleId;
  final DateTime? since;
  final DateTime? linkedAt;
  final CouplePartner? partner;
  final int memories;
  const CoupleStatus({required this.linked, this.coupleId, this.since, this.linkedAt, this.partner, this.memories = 0});

  /// عدد الأيام من تاريخكما (أو من يوم الربط إذا ما محدد).
  int? get days {
    final s = since;
    if (s == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).difference(DateTime(s.year, s.month, s.day)).inDays;
  }

  static CoupleStatus fromJson(Map<String, dynamic> j) {
    if (j['linked'] != true) return const CoupleStatus(linked: false);
    final p = (j['partner'] as Map).cast<String, dynamic>();
    return CoupleStatus(
      linked: true,
      coupleId: j['couple_id'] as String?,
      since: j['since'] == null ? null : DateTime.tryParse(j['since'] as String),
      linkedAt: j['linked_at'] == null ? null : DateTime.tryParse(j['linked_at'] as String)?.toLocal(),
      memories: (j['memories'] as num?)?.toInt() ?? 0,
      partner: CouplePartner(p['id'] as String, (p['display_name'] ?? '') as String, (p['username'] ?? '') as String,
          p['avatar_url'] as String?, p['verified'] == true),
    );
  }
}

class CoupleMemory {
  final String id;
  final String authorId;
  final String title;
  final String note;
  final DateTime day;
  final String? image;
  CoupleMemory(this.id, this.authorId, this.title, this.note, this.day, this.image);
  static CoupleMemory fromJson(Map<String, dynamic> m) => CoupleMemory(
        m['id'] as String,
        m['author_id'] as String,
        (m['title'] ?? '') as String,
        (m['note'] ?? '') as String,
        DateTime.tryParse((m['happened_on'] ?? '') as String) ?? DateTime.now(),
        m['image_url'] as String?,
      );
}

/// مساحة الشريك 💞 — ميزة اختيارية يفعّلها المستخدم من الإعدادات.
class CoupleService {
  CoupleService._();

  static const _prefKey = 'couple_mode_enabled';

  /// هل الميزة مفعّلة على هذا الجهاز (إذا لا، التطبيق يبقى بنسخته الأصلية).
  static final enabled = ValueNotifier<bool>(false);
  static final status = ValueNotifier<CoupleStatus?>(null);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      enabled.value = p.getBool('${myId ?? ''}::$_prefKey') ?? false;
      if (enabled.value) unawaited(refresh().then((_) {}, onError: (_) {}));
    } catch (_) {}
  }

  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('${myId ?? ''}::$_prefKey', v);
    } catch (_) {}
    if (v) unawaited(refresh().then((_) {}, onError: (_) {}));
  }

  /// يرجع للحالة الأولية عند تسجيل الخروج/تبديل الحساب.
  static void reset() {
    _loaded = false;
    enabled.value = false;
    status.value = null;
  }

  static Future<CoupleStatus> refresh() async {
    final r = await supa.rpc('couple_status');
    final s = CoupleStatus.fromJson((r as Map).cast<String, dynamic>());
    status.value = s;
    return s;
  }

  static Future<({String code, DateTime expires})> myCode() async {
    final r = ((await supa.rpc('couple_my_code')) as Map).cast<String, dynamic>();
    return (code: r['code'] as String, expires: DateTime.parse(r['expires_at'] as String).toLocal());
  }

  /// يرجع false إذا الرمز غلط أو منتهي.
  static Future<bool> link(String code) async {
    final r = await supa.rpc('couple_link', params: {'p_code': code.trim()});
    if (r == null) return false;
    await refresh();
    return true;
  }

  static Future<void> unlink() async {
    await supa.rpc('couple_unlink');
    await refresh();
  }

  static Future<void> setSince(DateTime? d) async {
    await supa.rpc('couple_set_since', params: {
      'p_date': d == null ? null : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    });
    await refresh();
  }

  static Future<List<CoupleMemory>> memories() async {
    final r = await supa.from('couple_memories').select().order('happened_on').order('created_at');
    return [for (final m in r) CoupleMemory.fromJson(m)];
  }

  static Future<void> addMemory({required String title, String note = '', required DateTime day, Uint8List? image}) async {
    final cid = status.value?.coupleId;
    if (cid == null) throw Exception('اربط حسابك بشريكك أول');
    String? url;
    if (image != null) {
      final path = '${myId!}/couple/${const Uuid().v4()}.jpg';
      await supa.storage.from('posts').uploadBinary(path, image, fileOptions: const FileOptions(contentType: 'image/jpeg'));
      url = supa.storage.from('posts').getPublicUrl(path);
    }
    await supa.from('couple_memories').insert({
      'couple_id': cid,
      'author_id': myId,
      'title': title.trim(),
      'note': note.trim(),
      'happened_on': '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      'image_url': url,
    });
  }

  static Future<void> deleteMemory(String id) => supa.from('couple_memories').delete().eq('id', id);

  static Future<Uint8List?> pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1440, maxHeight: 1440, imageQuality: 82);
    return x?.readAsBytes();
  }

  static Future<Map<String, dynamic>> question([String? answer]) async {
    final r = await supa.rpc('couple_question', params: {'p_answer': answer});
    return (r as Map).cast<String, dynamic>();
  }

  // ---------- سهرتنا (مشاهدة يوتيوب سوا) ----------
  static Future<Map<String, dynamic>?> watchState() async {
    final cid = status.value?.coupleId;
    if (cid == null) return null;
    final r = await supa.from('couple_watch').select().eq('couple_id', cid).maybeSingle();
    return r;
  }

  static Future<void> pushWatch({String? videoId, required bool playing, required double position}) async {
    final cid = status.value?.coupleId;
    if (cid == null) return;
    await supa.from('couple_watch').upsert({
      'couple_id': cid,
      if (videoId != null) 'video_id': videoId,
      'playing': playing,
      'position': position < 0 ? 0 : position,
      'updated_by': myId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static RealtimeChannel watchChannel(void Function(Map<String, dynamic>) onChange) {
    final cid = status.value!.coupleId!;
    return supa
        .channel('couple-watch-$cid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'couple_watch',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'couple_id', value: cid),
          callback: (p) => onChange(p.newRecord),
        )
        .subscribe();
  }

  static RealtimeChannel memoriesChannel(VoidCallback onChange) {
    final cid = status.value!.coupleId!;
    return supa
        .channel('couple-mem-$cid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'couple_memories',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'couple_id', value: cid),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// يستخرج معرّف فيديو يوتيوب من أي رابط (watch / youtu.be / shorts / live / embed).
  static String? youtubeId(String input) {
    final s = input.trim();
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(s)) return s;
    final u = Uri.tryParse(s.startsWith('http') ? s : 'https://$s');
    if (u == null) return null;
    final host = u.host.replaceFirst('www.', '').replaceFirst('m.', '');
    String? id;
    if (host == 'youtu.be') {
      id = u.pathSegments.isNotEmpty ? u.pathSegments.first : null;
    } else if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
      id = u.queryParameters['v'];
      if (id == null && u.pathSegments.length >= 2 && ['shorts', 'live', 'embed', 'v'].contains(u.pathSegments.first)) {
        id = u.pathSegments[1];
      }
    }
    if (id != null && RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id)) return id;
    return null;
  }

  static const questions = <String>[
    'شنو أول شي لفت انتباهك بيّ؟',
    'لو نسافر سوا باچر، وين تختار؟',
    'شنو أحلى ذكرى إلنا لحد هسه؟',
    'شنو الأغنية اللي تذكرك بيّ؟',
    'شنو الشي اللي أسويه ويفرحك حتى لو صغير؟',
    'لو تكدر ترجع ليوم واحد ويانا، يا يوم تختار؟',
    'شنو حلمك اللي تتمنى نحققه سوا؟',
    'شنو أكلة تحب ناكلها سوا دائمًا؟',
    'شنو الصفة اللي تحبها بيّ أكثر شي؟',
    'شلون تتخيلنا بعد خمس سنين؟',
    'شنو الكلمة اللي تحب تسمعها مني؟',
    'شنو الشي اللي تعلمته مني؟',
    'لو نسوي فلم عن قصتنا، شنو يكون اسمه؟',
    'شنو أكثر لحظة ضحكنا بيها سوا؟',
    'شنو هدية تتمنى توصلك مني؟',
    'شنو اللون اللي يذكرك بيّ؟ وليش؟',
    'شنو الشي اللي تحب نسويه بالويكند؟',
    'شنو أول رسالة تتذكرها بيناتنا؟',
    'شنو الشي اللي يخليك تشتاقلي؟',
    'لو عدنا يوم كامل بدون موبايلات، شنو نسوي؟',
    'شنو أكثر صفة تشبهني بيها؟',
    'شنو المكان اللي تحس بيه بالراحة ويّاي؟',
    'شنو العادة الحلوة اللي تتمنى نبديها سوا؟',
    'اكتبلي ثلاث كلمات توصفني بيها',
    'شنو الشي اللي تحب تشكرني عليه اليوم؟',
    'شنو أحلى مفاجأة تتمنى أسويهالك؟',
    'شنو أكثر شي تحبه بعلاقتنا؟',
    'شنو أول شي تسويه إذا شفتني بعد غياب طويل؟',
    'شنو الأكلة اللي تتمنى أطبخهالك؟',
    'شنو الذكرى اللي ما تنساها أبد؟',
  ];
}
