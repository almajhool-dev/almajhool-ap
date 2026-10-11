import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_app_installations/firebase_app_installations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_services.dart';
import 'notif_actions.dart';
import 'update_service.dart';

/// إعدادات مشروع Firebase (ليست سرية).
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyB5OQeMl16-4xCoLE_PS3B0Bn7b9T926ZM',
  appId: '1:875006098480:android:c7118ebcd38ad84572c1f5',
  messagingSenderId: '875006098480',
  projectId: 'almajhool-aefc9',
  storageBucket: 'almajhool-aefc9.firebasestorage.app',
);

const msgsChannel = 'almajhool_msgs';

/// يُقرأ من خدمة الخلفية: هذا الجهاز مسجّل لدى Google.
const fcmOkKey = 'fcm_ok';

/// إشعارات Google: تصل حتى لو التطبيق مغلق تمامًا (مثل واتساب).
class PushService {
  PushService._();

  /// تعمل وجاهزة على الخادم: التطبيق لا يحتاج خدمة الخلفية الدائمة.
  static bool active = false;
  static String? lastError;
  static String? _token;
  static StreamSubscription? _refreshSub;
  static bool _firebaseReady = false;

  /// تُستدعى في main قبل تشغيل الواجهة.
  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: firebaseOptions);
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      _firebaseReady = true;
      // التطبيق ظاهر: الرسائل والمكالمات تُعرض من داخله، فنتجاهل إشعار Google هنا
      FirebaseMessaging.onMessage.listen((_) {});
    } catch (e) {
      lastError = 'init: $e';
      debugPrint('firebase init failed: $e');
    }
  }

  static int _attempt = 0;
  static bool _resetDone = false;
  static String? lastDiag;
  static DateTime? _lastManual;
  static Timer? _retry;
  static bool _starting = false;

  static void _report(String info) {
    try {
      supa.rpc('client_log', params: {'p_info': 'b${UpdateService.currentBuild} push $info'}).catchError((_) => null);
    } catch (_) {}
  }

  /// بعد تسجيل الدخول: يسجّل الجهاز. يرجع true إذا صارت إشعارات Google فعّالة.
  /// كل خطوة محمية بمهلة، وإذا فشلت يعيد المحاولة تلقائيًا (ما تتوقف الإشعارات بسبب أي إضافة بالتطبيق).
  static Future<bool> start() async {
    if (_starting) return active;
    _starting = true;
    var stage = 'init';
    try {
      if (!_firebaseReady) {
        // إعادة تهيئة Firebase إذا فشلت عند فتح التطبيق
        if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: firebaseOptions).timeout(const Duration(seconds: 15));
        try {
          FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
        } catch (_) {}
        _firebaseReady = true;
      }
      stage = 'channel';
      try {
        final plugin = FlutterLocalNotificationsPlugin();
        await plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(const AndroidNotificationChannel(
              msgsChannel,
              'الرسائل',
              description: 'إشعار عند وصول رسالة',
              importance: Importance.high,
            ))
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      final m = FirebaseMessaging.instance;
      // طلب الإذن ما يوقف التسجيل أبدًا (أحيانًا ينتظر للأبد إذا انطلب إذن ثاني بنفس الوقت)
      stage = 'permission';
      try {
        await m.requestPermission(alert: true, sound: true, badge: true).timeout(const Duration(seconds: 8));
      } catch (_) {}
      stage = 'token';
      String? t;
      // طلب واحد بس بكل محاولة (الطلبات الكثيرة تخلي Google يحظر هوية الجهاز مؤقتًا)
      try {
        t = await m.getToken().timeout(const Duration(seconds: 45));
      } catch (e) {
        // نجرب من جهة أندرويد مباشرة: يرجع الرمز إذا نجح، أو السبب الحقيقي للرفض
        String d = '';
        try {
          d = await const MethodChannel('almajhool/integrity').invokeMethod<String>('fcmDiag').timeout(const Duration(seconds: 70)) ?? '';
        } catch (x) {
          d = 'diag_unavailable: $x';
        }
        if (d.startsWith('ok:') && d.length > 20) {
          t = d.substring(3);
          _report('native token ok');
        } else {
          lastDiag = d;
          _report('diag ${d.length > 450 ? d.substring(0, 450) : d}');
        }
      }
      if (t == null) {
        // Google رفض: نمسح هوية الجهاز عند Google بالكامل ونسوي هوية جديدة نظيفة، بعدين طلب واحد
        if (_resetDone) throw Exception(lastDiag ?? 'FCM Registration failed');
        _resetDone = true;
        stage = 'reset';
        try {
          await m.deleteToken().timeout(const Duration(seconds: 20));
        } catch (_) {}
        try {
          await FirebaseInstallations.instance.delete().timeout(const Duration(seconds: 20));
        } catch (_) {}
        await Future<void>.delayed(const Duration(seconds: 6));
        try {
          await m.setAutoInitEnabled(true);
        } catch (_) {}
        stage = 'token2';
        t = await m.getToken().timeout(const Duration(seconds: 60));
        _report('new identity ok');
      }
      if (t == null) throw Exception('no token');
      _token = t;
      stage = 'register';
      await supa.rpc('register_fcm2', params: {'p_token': t, 'p_build': UpdateService.currentBuild}).timeout(const Duration(seconds: 20));
      await CacheService.setString(kFcmTokenPref, t);
      await CacheService.setBool(fcmOkKey, true);
      _refreshSub ??= m.onTokenRefresh.listen((nt) {
        _token = nt;
        supa.rpc('register_fcm2', params: {'p_token': nt, 'p_build': UpdateService.currentBuild}).catchError((_) => null);
        CacheService.setString(kFcmTokenPref, nt);
      });
      stage = 'ready';
      final ready = await supa.rpc('push_ready').timeout(const Duration(seconds: 15)) == true;
      active = ready;
      lastError = ready ? null : 'الخادم لم يُجهّز بعد (ملف حساب الخدمة)';
      if (_attempt > 0) _report('ok after ${_attempt + 1} tries');
      _attempt = 0;
      return ready;
    } catch (e) {
      lastError = '$stage: $e';
      active = false;
      _report('fail ${_attempt + 1} $stage: ${'$e'.length > 300 ? '$e'.substring(0, 300) : e}');
      // إعادة محاولة تلقائية: بعد 30 ثانية، دقيقة، دقيقتين... لحد 10 دقايق
      // محاولات متباعدة (دقيقتين، 10، 30، ساعة...) حتى ما نطوّل الحظر
      if (_attempt < 8) {
        const waits = [120, 600, 1800, 3600, 3600, 7200, 7200, 14400];
        final wait = Duration(seconds: waits[_attempt]);
        _attempt++;
        _retry?.cancel();
        _retry = Timer(wait, () => start());
      }
      return false;
    } finally {
      _starting = false;
    }
  }

  /// إعادة الربط مع Google يدويًا (زر بشاشة الفحص) — يبدي من جديد بمسح التسجيل القديم.
  static Future<bool> retryNow() async {
    _retry?.cancel();
    if (_attempt == 0) _attempt = 1;
    // زر «إعادة» يسمح بهوية جديدة مرة كل 5 دقايق بس
    final now = DateTime.now();
    if (_lastManual == null || now.difference(_lastManual!).inMinutes >= 5) {
      _resetDone = false;
      _lastManual = now;
    }
    return start();
  }

  static Future<void> cancelCallNotification() async {
    try {
      await FlutterLocalNotificationsPlugin().cancel(kCallNotifId);
    } catch (_) {}
  }

  static Future<void> stop() async {
    active = false;
    _retry?.cancel();
    _attempt = 0;
    try {
      await CacheService.setBool(fcmOkKey, false);
    } catch (_) {}
    final t = _token;
    if (t != null) {
      try {
        await supa.rpc('unregister_fcm', params: {'p_token': t});
      } catch (_) {}
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _token = null;
  }
}

// =====================================================================
//  يعمل حتى والتطبيق مغلق: Google توقظ التطبيق لعرض المكالمة
// =====================================================================

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: firebaseOptions);
  } catch (_) {}
  final d = message.data;
  final kind = d['kind'];
  final plugin = FlutterLocalNotificationsPlugin();
  await initNotifPlugin(plugin);

  if (kind == 'msg') {
    if (message.notification != null) return; // نسخة قديمة من الخادم: النظام عرضها
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (!(prefs.getBool('notifications_on') ?? true)) return;
    final conv = d['conv'];
    if (conv == null) return;
    await showMessageNotification(plugin, d['title'] ?? 'رسالة جديدة', d['body'] ?? '', conv);
    return;
  }
  if (kind == 'call_end') {
    await plugin.cancel(kCallNotifId);
    return;
  }
  if (kind != 'call') return;

  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final soundsOn = prefs.getBool('sound_calls_on') ?? true;
  final ring = prefs.getString('sound_ringtone') ?? 'ring_naseem';
  final channelId = soundsOn ? 'almajhool_call_$ring' : 'almajhool_call_silent';

  final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(AndroidNotificationChannel(
    channelId,
    soundsOn ? 'المكالمات الواردة' : 'المكالمات الواردة (بدون صوت)',
    description: 'رنين وإشعار ملء الشاشة عند ورود مكالمة',
    importance: Importance.max,
    playSound: soundsOn,
    sound: soundsOn ? RawResourceAndroidNotificationSound(ring) : null,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
  ));

  await showCallNotification(plugin,
      callId: d['call_id'] ?? '', name: d['name'] ?? 'مستخدم', video: d['video'] == '1', channelId: channelId);
}
