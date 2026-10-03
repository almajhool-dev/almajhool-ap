import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:permission_handler/permission_handler.dart' as ph show openAppSettings;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';
import 'call_service.dart';
import 'core_services.dart';
import 'push_service.dart';
import 'update_service.dart';

/// خدمة تعمل في الخلفية حتى لو أُغلق التطبيق:
/// تستقبل المكالمات (رنين + إشعار ملء الشاشة) والرسائل (إشعار مع صوت).
/// لا تحتاج أي حساب خارجي (Firebase): تتصل بالخادم مباشرة بمفتاح جهاز سري.
class BackgroundBridge {
  BackgroundBridge._();

  static const _kToken = 'bg_token';
  static const _kUrl = 'bg_url';
  static const _kKey = 'bg_key';
  static const _kSince = 'bg_since';
  static const _kBatteryAsked = 'bg_battery_asked';
  static const serviceChannel = 'almajhool_bg';
  static const callsChannel = 'almajhool_calls';
  static const msgsChannel = 'almajhool_msgs';

  static bool _configured = false;

  /// الخدمة تعمل: الإشعارات والرنين أثناء غياب التطبيق تتكفل بها هي.
  static bool active = false;

  /// آخر إشارة حياة من خدمة الخلفية + آخر خطأ (للتشخيص).
  static DateTime? lastAlive;
  static String? lastError;
  static DateTime? lastPoll;
  static StreamSubscription? _aliveSub;

  /// الخدمة شغالة فعلًا (أرسلت إشارة خلال آخر دقيقتين).
  static bool get healthy =>
      PushService.active ||
      (active && lastAlive != null && DateTime.now().difference(lastAlive!).inSeconds < 120);

  static bool get appVisible => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  static Timer? _heartbeat;
  static _Lifecycle? _observer;

  /// تهيئة (مرة واحدة عند فتح التطبيق).
  static Future<void> configure() async {
    if (_configured || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(const AndroidNotificationChannel(
        serviceChannel,
        'التشغيل في الخلفية',
        description: 'يبقي التطبيق جاهزًا لاستقبال المكالمات والرسائل',
        importance: Importance.min,
        showBadge: false,
        playSound: false,
        enableVibration: false,
      ));
      await FlutterBackgroundService().configure(
        androidConfiguration: AndroidConfiguration(
          onStart: bgMain,
          autoStart: false,
          autoStartOnBoot: true,
          isForegroundMode: true,
          notificationChannelId: serviceChannel,
          initialNotificationTitle: AppConfig.appName,
          initialNotificationContent: 'جاهز لاستقبال المكالمات والرسائل',
          foregroundServiceNotificationId: 7311,
          foregroundServiceTypes: [AndroidForegroundType.remoteMessaging],
        ),
        iosConfiguration: IosConfiguration(autoStart: false),
      );
      _aliveSub ??= FlutterBackgroundService().on('alive').listen((e) {
        lastAlive = DateTime.now();
        final err = e?['error'] as String?;
        if (err != null) lastError = err;
        if (e?['poll'] == true) {
          lastPoll = DateTime.now();
          lastError = null;
        }
      });
      _configured = true;
    } catch (e) {
      lastError = 'configure: $e';
      log('configure: $e');
      debugPrint('bg configure failed: $e');
    }
  }

  /// تشغيل بعد تسجيل الدخول.
  static Future<void> start() async {
    if (!_configured) await configure();
    if (!_configured) return;
    try {
      var token = CacheService.getString(_kToken);
      if (token == null || token.length < 32) {
        final r = Random.secure();
        token = List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        await CacheService.setString(_kToken, token);
      }
      await supa.rpc('register_device', params: {'p_token': token});
      await CacheService.setString(_kUrl, AppConfig.url);
      await CacheService.setString(_kKey, AppConfig.anonKey);
      if (CacheService.getString(_kSince) == null) {
        await CacheService.setString(_kSince, DateTime.now().toUtc().toIso8601String());
      }
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) await service.startService();
      active = true;
      _startHeartbeat();
      unawaited(_askPermissions());
      // تقرير حالة بعد 25 ثانية (للتشخيص، بدون بيانات شخصية)
      Future.delayed(const Duration(seconds: 25), () async {
        final st = await status();
        log('status $st err=$lastError');
      });
    } catch (e) {
      lastError = 'start: $e';
      log('start: $e');
      debugPrint('bg start failed: $e');
    }
  }

  /// إيقاف عند تسجيل الخروج.
  static Future<void> stop() async {
    active = false;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (_observer != null) WidgetsBinding.instance.removeObserver(_observer!);
    _observer = null;
    try {
      final token = CacheService.getString(_kToken);
      if (token != null) {
        unawaited(supa.rpc('unregister_device', params: {'p_token': token}).catchError((_) => null));
      }
      await CacheService.setString(_kToken, '');
      FlutterBackgroundService().invoke('stop');
    } catch (_) {}
  }

  /// نبض كل 4 ثوانٍ ما دام التطبيق ظاهرًا: الخدمة لا تُظهر إشعارات وقتها (التطبيق يتكفل بها).
  static void _startHeartbeat() {
    if (_observer == null) {
      _observer = _Lifecycle();
      WidgetsBinding.instance.addObserver(_observer!);
    }
    _beat();
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 4), (_) => _beat());
  }

  /// سجل تشخيص مختصر إلى الخادم.
  static void log(String info) {
    try {
      supa.rpc('client_log', params: {'p_info': 'b${UpdateService.currentBuild} $info'}).catchError((_) => null);
    } catch (_) {}
  }

  static int _beats = 0;

  static void _beat() {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      FlutterBackgroundService().invoke('fg');
      // إصلاح ذاتي: إذا توقفت الخدمة (أطفأها النظام) نعيد تشغيلها
      if (active && _beats++ % 8 == 0) unawaited(_ensureRunning());
    }
  }

  static Future<void> _ensureRunning() async {
    try {
      final service = FlutterBackgroundService();
      if (!await service.isRunning()) await service.startService();
    } catch (e) {
      lastError = 'restart: $e';
    }
  }

  /// إعادة تشغيل الخدمة من شاشة الفحص.
  static Future<void> restart() async {
    try {
      FlutterBackgroundService().invoke('stop');
      await Future<void>.delayed(const Duration(seconds: 2));
    } catch (_) {}
    await start();
  }

  /// إشعار تجريبي من خدمة الخلفية بعد 6 ثوانٍ (اخرج من التطبيق لتراه).
  static void test() => FlutterBackgroundService().invoke('test');

  /// حالة كاملة لشاشة الفحص.
  static Future<Map<String, bool?>> status() async {
    bool? running;
    try {
      running = await FlutterBackgroundService().isRunning();
    } catch (_) {}
    bool? notifs;
    bool? battery;
    try {
      notifs = await Permission.notification.isGranted;
      battery = await Permission.ignoreBatteryOptimizations.isGranted;
    } catch (_) {}
    return {
      'push': PushService.active,
      'configured': _configured,
      'registered': (CacheService.getString(_kToken) ?? '').length >= 32,
      'running': running,
      'alive': healthy,
      'notifications': notifs,
      'battery': battery,
    };
  }

  static Future<void> openAppSettings() async {
    try {
      await ph.openAppSettings();
    } catch (_) {}
  }

  static Future<void> requestBattery() async {
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {}
  }

  static Future<void> requestNotifications() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestFullScreenIntentPermission();
    } catch (_) {}
  }

  static Future<void> _askPermissions() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestFullScreenIntentPermission();
      if (CacheService.getBool(_kBatteryAsked) != true) {
        await CacheService.setBool(_kBatteryAsked, true);
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
  }
}

class _Lifecycle extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      PushService.cancelCallNotification();
      BackgroundBridge._beat();
      CallService.instance.checkPending();
    }
  }
}

// =====================================================================
//  ما يلي يعمل داخل خدمة الخلفية (Isolate منفصل)
// =====================================================================

@pragma('vm:entry-point')
Future<void> bgMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final w = _BgWorker(service);
  await w.run();
}

class _BgWorker {
  final ServiceInstance service;
  _BgWorker(this.service);

  late SharedPreferences prefs;
  SupabaseClient? client;
  RealtimeChannel? channel;
  final notif = FlutterLocalNotificationsPlugin();
  final ring = AudioPlayer();
  String token = '';
  DateTime lastFg = DateTime(2000);
  bool polling = false;
  bool pollAgain = false;
  String? ringingCall;
  Timer? ringWatch;
  DateTime? ringStarted;
  final notifiedCalls = <String>{};

  bool get appVisible => DateTime.now().difference(lastFg).inSeconds < 9;

  DateTime _lastReport = DateTime(2000);
  int nPoll = 0, nMsg = 0, nShown = 0, nCall = 0, nPing = 0;
  String lastShowErr = '';

  void _alive({bool poll = false, String? error, bool force = false}) {
    try {
      service.invoke('alive', {'poll': poll, if (error != null) 'error': error});
    } catch (_) {}
    // تقرير للخادم: عند الخطأ فورًا، وإلا كل 10 دقائق
    final now = DateTime.now();
    if (client != null && token.isNotEmpty && (error != null || force || now.difference(_lastReport).inMinutes >= 10)) {
      _lastReport = now;
      client!
          .rpc('bg_report', params: {
            'p_token': token,
            'p_info': 'b${UpdateService.currentBuild} vis=$appVisible poll=$nPoll ping=$nPing msg=$nMsg shown=$nShown call=$nCall $lastShowErr',
            'p_error': error,
          })
          .catchError((_) => null);
    }
  }

  Future<void> run() async {
    try {
      await _run();
    } catch (e) {
      _alive(error: 'run: $e');
      try {
        if (url0.isNotEmpty) {
          SupabaseClient(url0, key0).rpc('client_log', params: {'p_info': 'bg run: $e'}).catchError((_) => null);
        }
      } catch (_) {}
      // نحاول مجددًا بعد قليل بدل أن تموت الخدمة
      Future.delayed(const Duration(seconds: 20), run);
    }
  }

  String url0 = '';
  String key0 = '';

  Future<void> _run() async {
    prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    token = prefs.getString(BackgroundBridge._kToken) ?? '';
    final url = prefs.getString(BackgroundBridge._kUrl) ?? '';
    final key = prefs.getString(BackgroundBridge._kKey) ?? '';
    url0 = url;
    key0 = key;
    if (token.length < 32 || url.isEmpty || key.isEmpty) {
      _alive(error: 'no token');
      await service.stopSelf();
      return;
    }
    service.on('test').listen((_) async {
      await Future<void>.delayed(const Duration(seconds: 6));
      await notif.show(
        9200,
        'تجربة ✅',
        'الإشعارات تعمل حتى والتطبيق مغلق',
        const NotificationDetails(
          android: AndroidNotificationDetails(BackgroundBridge.msgsChannel, 'الرسائل',
              importance: Importance.high, priority: Priority.high),
        ),
      );
    });

    service.on('stop').listen((_) async {
      await _stopRinging();
      await channel?.unsubscribe();
      await service.stopSelf();
    });
    service.on('fg').listen((_) {
      lastFg = DateTime.now();
      _alive();
      if (ringingCall != null) _stopRinging(); // التطبيق ظاهر: هو يعرض المكالمة
    });

    await notif.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    final android = notif.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      BackgroundBridge.callsChannel,
      'المكالمات الواردة',
      description: 'إشعار ملء الشاشة عند ورود مكالمة',
      importance: Importance.max,
      playSound: false, // النغمة تُشغّل من التطبيق حسب اختيار المستخدم
      enableVibration: true,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      BackgroundBridge.msgsChannel,
      'الرسائل',
      description: 'إشعار عند وصول رسالة',
      importance: Importance.high,
    ));
    try {
      await ring.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notificationRingtone,
          audioFocus: AndroidAudioFocus.gainTransient,
          stayAwake: true,
        ),
      ));
      await ring.setReleaseMode(ReleaseMode.loop);
    } catch (_) {}

    client = SupabaseClient(url, key, authOptions: const AuthClientOptions(autoRefreshToken: false));
    _subscribe();
    // احتياط: فحص دوري حتى لو انقطع الاتصال الفوري
    Timer.periodic(const Duration(seconds: 40), (_) => poll());
    await poll();
  }

  void _subscribe() {
    channel = client!
        .channel('bg-$token')
        .onBroadcast(event: 'ping', callback: (_) {
          nPing++;
          poll();
        })
        .subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        poll(); // بعد كل إعادة اتصال نتأكد ما فاتنا شيء
      } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
        Future.delayed(const Duration(seconds: 5), () {
          channel?.unsubscribe();
          _subscribe();
        });
      }
    });
  }

  Future<void> poll() async {
    if (polling) {
      pollAgain = true;
      return;
    }
    polling = true;
    try {
      do {
        pollAgain = false;
        await _pollOnce();
      } while (pollAgain);
    } catch (e) {
      _alive(error: 'poll: $e');
      debugPrint('bg poll failed: $e');
    } finally {
      polling = false;
    }
  }

  Future<void> _pollOnce() async {
    await prefs.reload();
    final since = prefs.getString(BackgroundBridge._kSince) ?? DateTime.now().toUtc().toIso8601String();
    final r = await client!
        .rpc('bg_poll', params: {'p_token': token, 'p_since': since})
        .timeout(const Duration(seconds: 15));
    final data = (r is String ? jsonDecode(r) : r) as Map;
    if (data['invalid'] == true) {
      _alive(error: 'invalid token');
      await service.stopSelf();
      return;
    }
    nPoll++;

    // ---- المكالمات ----
    final calls = (data['calls'] as List? ?? const []).cast<Map>();
    nCall += calls.isEmpty ? 0 : 1;
    final ids = calls.map((c) => c['id'] as String).toSet();
    if (ringingCall != null && !ids.contains(ringingCall)) await _stopRinging();
    if (calls.isNotEmpty && ringingCall == null && !appVisible) {
      final c = calls.first;
      final id = c['id'] as String;
      if (!notifiedCalls.contains(id)) {
        notifiedCalls.add(id);
        await _ring(id, (c['name'] ?? 'مستخدم') as String, c['video'] == true);
      }
    }

    // ---- الرسائل ----
    final msgs = (data['messages'] as List? ?? const []).cast<Map>();
    nMsg += msgs.length;
    final notifyOn = prefs.getBool('notifications_on') ?? true;
    if (msgs.isNotEmpty) {
      await prefs.setString(BackgroundBridge._kSince, msgs.last['created_at'] as String);
      if (!appVisible && notifyOn) {
        for (final m in msgs.length > 5 ? msgs.sublist(msgs.length - 5) : msgs) {
          await _showMessage(m);
        }
      }
    }
    _alive(poll: true, force: msgs.isNotEmpty || calls.isNotEmpty);
  }

  Future<void> _ring(String callId, String name, bool video) async {
    ringingCall = callId;
    ringStarted = DateTime.now();
    await notif.show(
      9100,
      video ? '📹 مكالمة فيديو واردة' : '📞 مكالمة واردة',
      '$name يتصل بك — اضغط للرد',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          BackgroundBridge.callsChannel,
          'المكالمات الواردة',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: true,
          playSound: false,
          timeoutAfter: 45000,
          visibility: NotificationVisibility.public,
        ),
      ),
    );
    final soundsOn = prefs.getBool('sound_calls_on') ?? true;
    if (soundsOn) {
      final id = prefs.getString('sound_ringtone') ?? 'ring_naseem';
      try {
        await ring.play(AssetSource('sounds/$id.wav'), volume: 1.0);
      } catch (_) {}
    }
    // نراقب المكالمة كل ثانيتين: إذا أُلغيت أو رُد عليها نوقف الرنين
    ringWatch?.cancel();
    ringWatch = Timer.periodic(const Duration(seconds: 2), (_) {
      if (DateTime.now().difference(ringStarted!).inSeconds > 45) {
        _stopRinging();
      } else {
        poll();
      }
    });
  }

  Future<void> _stopRinging() async {
    ringWatch?.cancel();
    ringWatch = null;
    ringingCall = null;
    try {
      await ring.stop();
    } catch (_) {}
    try {
      await notif.cancel(9100);
    } catch (_) {}
  }

  Future<void> _showMessage(Map m) async {
    try {
      await _showMessage0(m);
      nShown++;
    } catch (e) {
      lastShowErr = 'show: $e';
    }
  }

  Future<void> _showMessage0(Map m) async {
    final title = (m['title'] ?? 'رسالة جديدة') as String;
    final body = (m['body'] ?? '') as String;
    final conv = (m['conversation_id'] ?? '') as String;
    await notif.show(
      conv.hashCode & 0x7fffffff,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          BackgroundBridge.msgsChannel,
          'الرسائل',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
    );
  }
}
