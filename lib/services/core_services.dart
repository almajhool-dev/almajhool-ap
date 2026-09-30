import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get supa => Supabase.instance.client;
String? get myId => Supabase.instance.client.auth.currentUser?.id;

/// تخزين محلي خفيف للعمل بدون إنترنت.
class CacheService {
  CacheService._();
  static late SharedPreferences _prefs;
  static const _maxCachedMessages = 60;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String _k(String key) => '${myId ?? 'anon'}::$key';

  static List<Map<String, dynamic>> readList(String key) {
    final raw = _prefs.getString(_k(key));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> writeList(String key, List<Map<String, dynamic>> list) =>
      _prefs.setString(_k(key), jsonEncode(list));

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
