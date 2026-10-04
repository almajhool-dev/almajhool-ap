import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../repositories/chat_repository.dart';
import '../screens/call/call_screen.dart';
import '../screens/home/home_shell.dart';
import '../screens/live/live_screens.dart';
import 'call_service.dart';
import 'local_notifications.dart';
import 'notif_actions.dart';

/// ماذا يحدث عند الضغط على إشعار أو أحد أزراره والتطبيق يعمل.
class NotifRouter {
  NotifRouter._();
  static bool _launchHandled = false;

  static void install() {
    foregroundNotificationHandler = handle;
    try {
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _openData(m.data));
    } catch (_) {}
  }

  /// فتح إشعار Google (بث مباشر أو رسالة) عند الضغط عليه.
  static Future<void> _openData(Map<String, dynamic> d) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final ctx = CallService.instance.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    if (d['kind'] == 'live' && d['live_id'] is String) {
      await openLive(ctx, d['live_id'] as String);
    } else if (d['kind'] == 'msg' && d['conv'] is String) {
      await openChat(ctx, d['conv'] as String);
    }
  }

  /// إذا فُتح التطبيق بالضغط على إشعار (والتطبيق كان مغلقًا).
  static Future<void> handleLaunch() async {
    if (_launchHandled) return;
    _launchHandled = true;
    try {
      final m = await FirebaseMessaging.instance.getInitialMessage();
      if (m != null) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await _openData(m.data);
        return;
      }
    } catch (_) {}
    final r = await LocalNotifications.launchResponse();
    if (r != null) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      handle(r);
    }
  }

  static Future<void> handle(NotificationResponse r) async {
    final p = parsePayload(r.payload);
    final ctx = CallService.instance.navigatorKey.currentContext;
    if (p['t'] == 'msg' && p['conv'] is String) {
      final conv = p['conv'] as String;
      if (r.actionId == actReply) {
        final text = (r.input ?? '').trim();
        if (text.isEmpty) return;
        try {
          final repo = ChatRepository();
          await repo.send(conversationId: conv, clientId: repo.newClientId(), content: text);
          await LocalNotifications.cancelMessage(conv);
        } catch (_) {
          await deviceReply(conv, text);
        }
        return;
      }
      if (ctx != null && ctx.mounted) await openChat(ctx, conv);
    } else if (p['t'] == 'call' && p['call'] is String) {
      final id = p['call'] as String;
      if (r.actionId == actDecline) {
        try {
          await CallSignal.update(id, status: 'rejected');
        } catch (_) {
          await deviceDeclineCall(id);
        }
        return;
      }
      await CallService.instance.openFromNotification(id, accept: r.actionId == actAccept);
    }
  }
}
