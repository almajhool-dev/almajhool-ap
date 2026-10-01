import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات الاتصال بـ Supabase.
/// الترتيب: إعداد يدوي محفوظ ← ملف config.json على GitHub ← القيم المدمجة في التطبيق.
class AppConfig {
  AppConfig._();

  static const appName = 'المبرمج المجهول';
  static const pageSize = 30;
  static const maxUploadBytes = 50 * 1024 * 1024;

  // القيم المدمجة (مفتاح Publishable عام ومصمم ليكون داخل التطبيق)
  static const _defaultUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://wuptldtquupuptrwigkxy.supabase.co');
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

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
  static bool get isBaked => true;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) إعداد أدخله المستخدم يدويًا سابقًا
    final manualUrl = prefs.getString(_prefUrl) ?? '';
    final manualKey = prefs.getString(_prefKey) ?? '';
    if (manualUrl.isNotEmpty && manualKey.isNotEmpty) {
      url = manualUrl;
      anonKey = manualKey;
      return;
    }

    // 2) ملف config.json على GitHub (مع حفظ آخر نسخة ناجحة)
    try {
      final res = await http
          .get(Uri.parse(_remoteConfig))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final u = (j['supabase_url'] ?? '').toString().trim();
        final k = (j['supabase_key'] ?? '').toString().trim();
        if (u.startsWith('https://') && k.length > 30) {
          await prefs.setString(_prefRemoteUrl, u);
          await prefs.setString(_prefRemoteKey, k);
        }
      }
    } catch (_) {
      // بدون إنترنت أو تعذر الوصول: نستخدم آخر نسخة محفوظة
    }
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
