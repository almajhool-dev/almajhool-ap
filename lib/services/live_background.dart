import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// متابعة البث برّا التطبيق (مثل تيك توك):
/// - نافذة صغيرة عائمة (Picture-in-Picture) عند الضغط على زر الهاتف الوسطي.
/// - إشعار ثابت «تسمع البث الآن» بأزرار رجوع/إيقاف، والصوت يبقى شغال.
class LiveBackground {
  LiveBackground._();

  static const _ch = MethodChannel('almajhool/pip');
  static const notifId = 9200;
  static const _channel = 'almajhool_live';
  static const actStop = 'live_stop';

  /// هل التطبيق هسه بنافذة صغيرة عائمة.
  static final pip = ValueNotifier<bool>(false);

  /// يُستدعى عند الضغط على «إيقاف» من الإشعار.
  static VoidCallback? onStop;

  static bool _handler = false;
  static bool _shown = false;

  static void _ensureHandler() {
    if (_handler) return;
    _handler = true;
    _ch.setMethodCallHandler((c) async {
      if (c.method == 'pip') pip.value = c.arguments == true;
    });
  }

  /// تفعيل/إلغاء الدخول التلقائي للنافذة العائمة عند الخروج من التطبيق.
  static Future<void> enable(bool on) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _ensureHandler();
    try {
      await _ch.invokeMethod('setAuto', {'on': on});
    } catch (_) {}
    if (!on) pip.value = false;
  }

  static Future<void> showNotification({required String host, String title = ''}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channel,
            'البث المباشر بالخلفية',
            description: 'يظهر وانت تسمع بث مباشر برّا التطبيق',
            importance: Importance.low,
            playSound: false,
            enableVibration: false,
          ));
      await plugin.show(
        notifId,
        '🔴 تسمع بث $host الآن',
        title.isEmpty ? 'اضغط حتى ترجع للبث' : title,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channel,
            'البث المباشر بالخلفية',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            playSound: false,
            enableVibration: false,
            category: AndroidNotificationCategory.transport,
            actions: [
              AndroidNotificationAction('live_open', 'رجوع للبث', showsUserInterface: true, cancelNotification: true),
              AndroidNotificationAction(actStop, 'إيقاف', showsUserInterface: true, cancelNotification: true),
            ],
          ),
        ),
        payload: jsonEncode({'t': 'live_bg'}),
      );
      _shown = true;
    } catch (_) {}
  }

  static Future<void> hideNotification() async {
    if (!_shown) return;
    _shown = false;
    try {
      await FlutterLocalNotificationsPlugin().cancel(notifId);
    } catch (_) {}
  }
}
