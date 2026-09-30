import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات الاتصال بـ Supabase.
/// يمكن تمريرها وقت البناء عبر --dart-define أو إدخالها من داخل التطبيق أول مرة.
class AppConfig {
  AppConfig._();

  static const appName = 'المبرمج المجهول';
  static const pageSize = 30;
  static const maxUploadBytes = 50 * 1024 * 1024;

  static const _bakedUrl = String.fromEnvironment('SUPABASE_URL');
  static const _bakedKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const _prefUrl = 'cfg_supabase_url';
  static const _prefKey = 'cfg_supabase_key';

  static String url = '';
  static String anonKey = '';

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
  static bool get isBaked => _bakedUrl.isNotEmpty && _bakedKey.isNotEmpty;

  static Future<void> load() async {
    if (isBaked) {
      url = _bakedUrl;
      anonKey = _bakedKey;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    url = prefs.getString(_prefUrl) ?? '';
    anonKey = prefs.getString(_prefKey) ?? '';
  }

  static Future<void> save(String newUrl, String newKey) async {
    final prefs = await SharedPreferences.getInstance();
    url = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    anonKey = newKey.trim();
    await prefs.setString(_prefUrl, url);
    await prefs.setString(_prefKey, anonKey);
  }
}
