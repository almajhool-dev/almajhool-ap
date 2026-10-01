import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات الاتصال بـ Supabase.
/// الترتيب: ملف config.json على GitHub (آخر نسخة محفوظة) ← القيم المدمجة في التطبيق.
class AppConfig {
  AppConfig._();

  static const appName = 'المبرمج المجهول';
  static const pageSize = 30;
  static const maxUploadBytes = 50 * 1024 * 1024;

  // القيم المدمجة (مفتاح Publishable عام ومصمم ليكون داخل التطبيق)
  static const _defaultUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://smjkxsqvdpywumghvnfv.supabase.co');
  static const _defaultKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_xqWRKqnOIKKqKgPJrdP5TA_GA7PCSiV',
  );

  // ملف إعدادات على GitHub يسمح بتصحيح الخادم بدون إصدار نسخة جديدة
  static const _remoteConfig =
      'https://raw.githubusercontent.com/almajhool-dev/almajhool-ap/main/config.json';

  static const _prefUrl = 'cfg_supabase_url';
  static const _prefKey = 'cfg_supabase_key';
  static const _prefRemoteUrl = 'cfg_remote_url';
  static const _prefRemoteKey = 'cfg_remote_key';

  static String url = '';
  static String anonKey = '';

  static const _prefIce = 'cfg_ice_servers';

  /// خوادم الاتصال (STUN/TURN) للمكالمات — قابلة للاستبدال من config.json
  static List<Map<String, dynamic>>? _remoteIce;

  static List<Map<String, dynamic>> get iceServers {
    final list = <Map<String, dynamic>>[
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
          'stun:stun.cloudflare.com:3478',
        ],
      },
    ];
    if (_remoteIce != null && _remoteIce!.isNotEmpty) {
      list.addAll(_remoteIce!);
    }
    return list;
  }

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
  static bool get isBaked => true;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // كل الأجهزة على نفس الخادم: نتجاهل أي إعداد يدوي قديم
    await prefs.remove(_prefUrl);
    await prefs.remove(_prefKey);

    // 2) آخر إعداد من config.json على GitHub (يُحدَّث بالخلفية لتشغيل فوري)
    _refreshRemote(prefs);
    try {
      final ice = prefs.getString(_prefIce);
      if (ice != null) {
        _remoteIce = (jsonDecode(ice) as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      }
    } catch (_) {}
    final rUrl = prefs.getString(_prefRemoteUrl) ?? '';
    final rKey = prefs.getString(_prefRemoteKey) ?? '';
    if (rUrl.isNotEmpty && rKey.isNotEmpty) {
      url = rUrl;
      anonKey = rKey;
      return;
    }

    // 3) القيم المدمجة
    url = _defaultUrl;
    anonKey = _defaultKey;
  }

  static Future<void> _refreshRemote(SharedPreferences prefs) async {
    try {
      final res = await http.get(Uri.parse(_remoteConfig)).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final u = (j['supabase_url'] ?? '').toString().trim();
      final k = (j['supabase_key'] ?? '').toString().trim();
      if (u.startsWith('https://') && k.length > 30) {
        await prefs.setString(_prefRemoteUrl, u);
        await prefs.setString(_prefRemoteKey, k);
      }
      if (j['ice_servers'] is List && (j['ice_servers'] as List).isNotEmpty) {
        await prefs.setString(_prefIce, jsonEncode(j['ice_servers']));
      }
    } catch (_) {
      // بدون إنترنت: لا شيء
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefUrl);
    await prefs.remove(_prefKey);
  }

  static Future<void> save(String newUrl, String newKey) async {
    final prefs = await SharedPreferences.getInstance();
    url = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    anonKey = newKey.trim();
    await prefs.setString(_prefUrl, url);
    await prefs.setString(_prefKey, anonKey);
  }
}
