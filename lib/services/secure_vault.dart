import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'integrity_service.dart';

/// خزنة الهاتف 🔐
/// مفتاح تشفير عشوائي (256 بت) لكل تثبيت، محفوظ داخل خزنة أندرويد (Keystore) / سلسلة مفاتيح آيفون،
/// وكل اللي ينحفظ بالهاتف من بيانات حساسة (الرسائل والمحادثات المخزّنة، الرسائل المعلّقة، جلسة الدخول)
/// يتشفّر AES-256-GCM (تشفير + ختم يكشف أي تعديل). حتى لو أحد سحب ملفات التطبيق من هاتف مروّت
/// ما يكدر يقراها بدون المفتاح اللي بالخزنة.
class SecureVault {
  SecureVault._();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  static const _keyName = 'vyfri_vault_key_v1';
  static const prefix = 'VYF1:';
  static Uint8List? _key;

  static bool get ready => _key != null;

  @visibleForTesting
  static void debugSetKey(Uint8List? k) => _key = k;

  static Future<void> init() async {
    if (_key != null) return;
    // مانع عبث: إذا التطبيق معدّل أو شغّالة عليه أداة اختراق، ما نحمّل المفتاح أبدًا —
    // فأي نسخة مكسورة ما تگدر تفك تشفير ولا بيانة (تطلع فارغة).
    if (IntegrityService.tampered) return;
    for (var attempt = 0; attempt < 2 && _key == null; attempt++) {
      try {
        final s = await _storage.read(key: _keyName).timeout(const Duration(seconds: 4));
        if (s != null) {
          final k = base64Decode(s);
          if (k.length == 32) {
            _key = Uint8List.fromList(k);
            return;
          }
        }
        final k = _random(32);
        await _storage.write(key: _keyName, value: base64Encode(k)).timeout(const Duration(seconds: 4));
        // نتأكد إنه انحفظ فعلًا قبل ما نشفّر بيه
        if (await _storage.read(key: _keyName).timeout(const Duration(seconds: 4)) == base64Encode(k)) _key = k;
      } catch (_) {
        // الخزنة ما اشتغلت بهذا الجهاز: التطبيق يكمل بدون تشفير محلي بدل ما يوكف
      }
    }
  }

  static Uint8List _random(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  static GCMBlockCipher _cipher(bool forEncryption, Uint8List key, Uint8List iv) =>
      GCMBlockCipher(AESEngine())..init(forEncryption, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

  /// نص مشفّر جاهز للحفظ، أو null إذا الخزنة مو جاهزة أو التطبيق معدّل
  static String? encrypt(String plain) {
    final k = _key;
    if (k == null || IntegrityService.tampered) return null;
    final iv = _random(12);
    final out = _cipher(true, k, iv).process(Uint8List.fromList(utf8.encode(plain)));
    final b = BytesBuilder(copy: false)
      ..add(iv)
      ..add(out);
    return prefix + base64Encode(b.takeBytes());
  }

  /// يفك التشفير؛ null إذا البيانات انعدلت أو المفتاح غير مطابق أو التطبيق معدّل
  static String? decrypt(String data) {
    final k = _key;
    if (k == null || IntegrityService.tampered || !data.startsWith(prefix)) return null;
    try {
      final raw = base64Decode(data.substring(prefix.length));
      if (raw.length < 12 + 16) return null;
      return utf8.decode(_cipher(false, k, Uint8List.sublistView(raw, 0, 12)).process(Uint8List.sublistView(raw, 12)));
    } catch (_) {
      return null;
    }
  }

  static bool isEncrypted(String data) => data.startsWith(prefix);
}

/// جلسة الدخول تنحفظ مشفّرة (بدل ما تنحفظ نص واضح بملف الإعدادات).
/// أول تشغيل بعد التحديث ينقل الجلسة القديمة ويشفّرها — المستخدم ما يطلع من حسابه.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(this.legacyKey);

  /// المفتاح القديم اللي چانت تنحفظ بيه الجلسة بدون تشفير
  final String legacyKey;
  static const _encKey = 'vyfri_session_v1';
  SharedPreferences? _prefs;
  String? _session;

  @override
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await SecureVault.init();
    final enc = _prefs!.getString(_encKey);
    if (enc != null) _session = SecureVault.decrypt(enc);
    final legacy = _prefs!.getString(legacyKey);
    _session ??= legacy;
    if (_session != null && legacy != null && SecureVault.ready) await _save(_session!);
  }

  Future<void> _save(String s) async {
    final p = _prefs ??= await SharedPreferences.getInstance();
    final enc = SecureVault.encrypt(s);
    if (enc != null) {
      await p.setString(_encKey, enc);
      await p.remove(legacyKey);
    } else {
      // الخزنة مو متوفرة بهذا الجهاز: نحفظ بالطريقة القديمة حتى ما يطلع من حسابه
      await p.setString(legacyKey, s);
    }
  }

  @override
  Future<bool> hasAccessToken() async => _session != null;

  @override
  Future<String?> accessToken() async => _session;

  @override
  Future<void> removePersistedSession() async {
    _session = null;
    final p = _prefs ??= await SharedPreferences.getInstance();
    await p.remove(_encKey);
    await p.remove(legacyKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    _session = persistSessionString;
    await _save(persistSessionString);
  }
}
