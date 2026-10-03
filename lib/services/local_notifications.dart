import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'core_services.dart';
import 'notif_actions.dart';

/// إشعارات النظام (تظهر في شريط الإشعارات أثناء عمل التطبيق أو وجوده بالخلفية).
class LocalNotifications {
  LocalNotifications._();
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _id = 0;
  static const prefKey = 'notifications_on';

  static bool get enabled => CacheService.getBool(prefKey) ?? true;
  static Future<void> setEnabled(bool v) => CacheService.setBool(prefKey, v);

  static Future<void> init() async {
    try {
      await initNotifPlugin(_plugin);
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('notifications init failed: $e');
    }
  }

  /// إشعار رسالة مع زر «رد».
  static Future<void> showMessage(String conv, String title, String body) async {
    if (!_ready || !enabled) return;
    try {
      await showMessageNotification(_plugin, title, body, conv);
    } catch (e) {
      debugPrint('notification show failed: $e');
    }
  }

  static Future<void> cancelMessage(String conv) async {
    try {
      await _plugin.cancel(msgNotifId(conv));
    } catch (_) {}
  }

  static Future<NotificationResponse?> launchResponse() async {
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) return d!.notificationResponse;
    } catch (_) {}
    return null;
  }

  static Future<void> show(String title, String body) async {
    if (!_ready || !enabled) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'الرسائل والإشعارات',
        channelDescription: 'إشعارات المبرمج المجهول',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    try {
      await _plugin.show(_id++ % 100000, title, body, details);
    } catch (e) {
      debugPrint('notification show failed: $e');
    }
  }
}
