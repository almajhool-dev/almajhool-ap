import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// إشعارات بأزرار: «رد» على الرسالة من الإشعار، و«رد/رفض» للمكالمة.
/// تعمل حتى والتطبيق مغلق (الرد يُرسل بمفتاح الجهاز بدون فتح التطبيق).
const _sbUrl = 'https://smjkxsqvdpywumghvnfv.supabase.co';
const _sbKey = 'sb_publishable_xqWRKqnOIKKqKgPJrdP5TA_GA7PCSiV';

const kMsgsChannel = 'almajhool_msgs';
const kCallNotifId = 9100;
const kFcmTokenPref = 'fcm_token';
const kBgTokenPref = 'bg_token';

const actReply = 'reply';
const actAccept = 'accept';
const actDecline = 'decline';

/// معالج الضغط على الإشعار حين يكون التطبيق ظاهرًا (يُضبط من main).
void Function(NotificationResponse r)? foregroundNotificationHandler;

Future<void> initNotifPlugin(FlutterLocalNotificationsPlugin plugin) async {
  await plugin.initialize(
    const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    onDidReceiveNotificationResponse: (r) => foregroundNotificationHandler?.call(r),
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(const AndroidNotificationChannel(
        kMsgsChannel,
        'الرسائل',
        description: 'إشعار عند وصول رسالة',
        importance: Importance.high,
      ));
}

int msgNotifId(String conv) => conv.hashCode & 0x3fffffff;

Future<void> showMessageNotification(
    FlutterLocalNotificationsPlugin plugin, String title, String body, String conv) {
  return plugin.show(
    msgNotifId(conv),
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        kMsgsChannel,
        'الرسائل',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        styleInformation: BigTextStyleInformation(body),
        actions: const [
          AndroidNotificationAction(
            actReply,
            'رد',
            inputs: [AndroidNotificationActionInput(label: 'اكتب ردّك...')],
            allowGeneratedReplies: true,
          ),
        ],
      ),
    ),
    payload: jsonEncode({'t': 'msg', 'conv': conv}),
  );
}

Future<void> showCallNotification(FlutterLocalNotificationsPlugin plugin,
    {required String callId, required String name, required bool video, required String channelId}) {
  return plugin.show(
    kCallNotifId,
    video ? '📹 مكالمة فيديو واردة' : '📞 مكالمة واردة',
    '$name يتصل بك',
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        'المكالمات الواردة',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true,
        ongoing: true,
        autoCancel: true,
        timeoutAfter: 45000,
        visibility: NotificationVisibility.public,
        // FLAG_INSISTENT: يتكرر الرنين حتى الرد أو انتهاء المهلة
        additionalFlags: Int32List.fromList(<int>[4]),
        actions: const [
          AndroidNotificationAction(actDecline, '❌ رفض', cancelNotification: true),
          AndroidNotificationAction(actAccept, '✅ رد', showsUserInterface: true, cancelNotification: true),
        ],
      ),
    ),
    payload: jsonEncode({'t': 'call', 'call': callId}),
  );
}

Map<String, dynamic> parsePayload(String? p) {
  if (p == null || p.isEmpty) return const {};
  try {
    return Map<String, dynamic>.from(jsonDecode(p) as Map);
  } catch (_) {
    return const {};
  }
}

Future<bool> _rpc(String name, Map<String, dynamic> args) async {
  try {
    final r = await http
        .post(Uri.parse('$_sbUrl/rest/v1/rpc/$name'),
            headers: {'apikey': _sbKey, 'Content-Type': 'application/json'}, body: jsonEncode(args))
        .timeout(const Duration(seconds: 15));
    return r.statusCode >= 200 && r.statusCode < 300;
  } catch (_) {
    return false;
  }
}

Future<List<String>> _deviceTokens() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return [prefs.getString(kFcmTokenPref), prefs.getString(kBgTokenPref)]
      .whereType<String>()
      .where((t) => t.length >= 20)
      .toList();
}

/// إرسال رد من الإشعار باستخدام مفتاح الجهاز (لا يحتاج فتح التطبيق).
Future<bool> deviceReply(String conv, String text) async {
  for (final t in await _deviceTokens()) {
    if (await _rpc('device_reply', {'p_token': t, 'p_conv': conv, 'p_text': text})) return true;
  }
  return false;
}

Future<bool> deviceDeclineCall(String callId) async {
  for (final t in await _deviceTokens()) {
    if (await _rpc('device_call_action', {'p_token': t, 'p_call': callId, 'p_status': 'rejected'})) return true;
  }
  return false;
}

/// يعمل والتطبيق مغلق: Android يوقظ التطبيق لتنفيذ زر الإشعار.
@pragma('vm:entry-point')
Future<void> notificationTapBackground(NotificationResponse r) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final p = parsePayload(r.payload);
  final plugin = FlutterLocalNotificationsPlugin();
  if (r.actionId == actReply && p['conv'] is String) {
    final text = (r.input ?? '').trim();
    if (text.isEmpty) return;
    final ok = await deviceReply(p['conv'] as String, text);
    await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    if (ok) {
      await plugin.cancel(msgNotifId(p['conv'] as String));
    } else {
      await plugin.show(
        msgNotifId(p['conv'] as String),
        'تعذّر إرسال الرد',
        'افتح التطبيق وحاول مجددًا',
        const NotificationDetails(android: AndroidNotificationDetails(kMsgsChannel, 'الرسائل')),
        payload: r.payload,
      );
    }
  } else if (r.actionId == actDecline && p['call'] is String) {
    await deviceDeclineCall(p['call'] as String);
    await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await plugin.cancel(kCallNotifId);
  }
}
