import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'secure_vault.dart';

SupabaseClient get supa => Supabase.instance.client;
String? get myId => Supabase.instance.client.auth.currentUser?.id;

/// تخزين محلي خفيف للعمل بدون إنترنت.
/// القوائم الكبيرة (المحادثات/الرسائل/المنشورات) تنحفظ بملفات منفصلة — مو بملف الإعدادات —
/// حتى ملف الإعدادات يبقى صغير وما يعلّك فتح التطبيق مهما كثرت المحادثات.
class CacheService {
  CacheService._();
  static late SharedPreferences _prefs;
  static const _maxCachedMessages = 60;
  static const _maxMessageFiles = 40;
  static Directory? _dir;
  static final Map<String, List<Map<String, dynamic>>> _mem = {};

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/list_cache');
      if (!d.existsSync()) d.createSync(recursive: true);
      _dir = d;
    } catch (_) {}
    // نقل/تنظيف القوائم القديمة من ملف الإعدادات (هي اللي جانت تكبّره)
    try {
      for (final k in _prefs.getKeys().toList()) {
        if (!k.contains('::')) continue;
        final name = k.substring(k.indexOf('::') + 2);
        if (name == 'outbox') {
          final raw = _prefs.getString(k);
          if (raw != null && _dir != null) File(_file(k)).writeAsStringSync(raw, flush: true);
          await _prefs.remove(k);
        } else if (name.startsWith('msgs_') || name == 'conversations' || name == 'feed') {
          await _prefs.remove(k);
        }
      }
    } catch (_) {}
    // الملفات القديمة (قبل التشفير) تتشفّر كلها بالخلفية مرة وحدة
    if (SecureVault.ready && _dir != null) Future(_encryptOldFiles);
  }

  static Future<void> _encryptOldFiles() async {
    try {
      for (final f in _dir!.listSync().whereType<File>()) {
        if (!f.path.endsWith('.json')) continue;
        final raw = await f.readAsString();
        if (raw.isEmpty || SecureVault.isEncrypted(raw)) continue;
        final enc = SecureVault.encrypt(raw);
        if (enc == null) return;
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(enc, flush: true);
        await tmp.rename(f.path);
      }
    } catch (_) {}
  }

  static String _k(String key) => '${myId ?? 'anon'}::$key';
  static String _file(String fullKey) =>
      '${_dir!.path}/${fullKey.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json';

  static List<Map<String, dynamic>> readList(String key) {
    final k = _k(key);
    final m = _mem[k];
    if (m != null) return m;
    if (_dir == null) return [];
    try {
      final f = File(_file(k));
      if (!f.existsSync()) return [];
      // الملفات مشفّرة (AES-256-GCM)؛ الملفات القديمة غير المشفّرة تنقرا مرة وتنشفّر بأول حفظ
      final raw = f.readAsStringSync();
      final text = SecureVault.isEncrypted(raw) ? SecureVault.decrypt(raw) : raw;
      if (text == null) return [];
      final l = (jsonDecode(text) as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      _mem[k] = l;
      return l;
    } catch (_) {
      return [];
    }
  }

  static Future<void> writeList(String key, List<Map<String, dynamic>> list) async {
    final k = _k(key);
    _mem[k] = list;
    if (_dir == null) return;
    try {
      final f = File(_file(k));
      final tmp = File('${f.path}.tmp');
      final text = jsonEncode(list);
      await tmp.writeAsString(SecureVault.encrypt(text) ?? text, flush: true);
      await tmp.rename(f.path);
      if (key.startsWith('msgs_')) _trimMessageFiles();
    } catch (_) {}
  }

  static int _writes = 0;
  /// نخلي آخر 40 محادثة بس محفوظة محليًا (الباقي يتحمّل من الخادم)
  static void _trimMessageFiles() {
    if (++_writes % 20 != 0) return;
    try {
      final files = _dir!.listSync().whereType<File>().where((f) => f.path.contains('__msgs_') && f.path.endsWith('.json')).toList();
      if (files.length <= _maxMessageFiles) return;
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      for (final f in files.skip(_maxMessageFiles)) {
        f.deleteSync();
      }
      _mem.removeWhere((k, _) => k.contains('::msgs_'));
    } catch (_) {}
  }

  static List<Map<String, dynamic>> conversations() => readList('conversations');
  static Future<void> saveConversations(List<Map<String, dynamic>> l) => writeList('conversations', l);

  static List<Map<String, dynamic>> messages(String convId) => readList('msgs_$convId');
  static Future<void> saveMessages(String convId, List<Map<String, dynamic>> newestFirst) =>
      writeList('msgs_$convId', newestFirst.take(_maxCachedMessages).toList());

  static List<Map<String, dynamic>> outbox() => readList('outbox');
  static Future<void> saveOutbox(List<Map<String, dynamic>> l) => writeList('outbox', l);

  static bool? getBool(String key) => _prefs.getBool(key);
  static Future<void> setBool(String key, bool v) => _prefs.setBool(key, v);
  static String? getString(String key) => _prefs.getString(key);
  static Future<void> setString(String key, String v) => _prefs.setString(key, v);
}

/// مراقبة حالة الاتصال بالإنترنت.
class ConnectivityService extends ChangeNotifier {
  bool _online = true;
  bool get online => _online;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  final _onlineController = StreamController<void>.broadcast();
  Stream<void> get onReconnect => _onlineController.stream;

  ConnectivityService() {
    Connectivity().checkConnectivity().then(_update);
    _sub = Connectivity().onConnectivityChanged.listen(_update);
  }

  void _update(List<ConnectivityResult> r) {
    final now = r.any((e) => e != ConnectivityResult.none);
    if (now != _online) {
      _online = now;
      notifyListeners();
      if (now) _onlineController.add(null);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _onlineController.close();
    super.dispose();
  }
}
