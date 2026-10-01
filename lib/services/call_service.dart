import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../screens/call/call_screen.dart';
import 'core_services.dart';
import 'local_notifications.dart';

/// استخراج حمولة رسالة Broadcast (تختلف حسب إصدار المكتبة).
Map<String, dynamic> unwrapBroadcast(Map<String, dynamic> p) {
  final inner = p['payload'];
  if (inner is Map) return Map<String, dynamic>.from(inner);
  return p;
}

/// إدارة المكالمات: استقبال الدعوات وبدء المكالمات.
/// الإشارات (signaling) تمر عبر Supabase Realtime، والصوت/الصورة مباشرة بين الهاتفين (WebRTC).
class CallService {
  CallService._();
  static final instance = CallService._();

  final navigatorKey = GlobalKey<NavigatorState>();
  RealtimeChannel? _inbox;
  bool inCall = false;
  String? _myName;
  String? _myAvatar;

  static String inboxTopic(String uid) => 'call-inbox-$uid';
  static String roomTopic(String callId) => 'call-room-$callId';

  void start(String uid, {String? name, String? avatar}) {
    _myName = name;
    _myAvatar = avatar;
    if (_inbox != null) return;
    _inbox = supa
        .channel(inboxTopic(uid))
        .onBroadcast(event: 'invite', callback: (p) => _onInvite(unwrapBroadcast(p)))
        .subscribe();
  }

  void updateMe({String? name, String? avatar}) {
    _myName = name ?? _myName;
    _myAvatar = avatar ?? _myAvatar;
  }

  Future<void> stop() async {
    if (_inbox != null) await supa.removeChannel(_inbox!);
    _inbox = null;
  }

  /// إرسال حدث إلى قناة مؤقتة (تشترك، ترسل، ثم تغادر).
  static Future<void> sendOnce(String topic, String event, Map<String, dynamic> payload) async {
    final ch = supa.channel(topic);
    final ready = Completer<void>();
    ch.subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed && !ready.isCompleted) ready.complete();
    });
    try {
      await ready.future.timeout(const Duration(seconds: 8));
      await ch.sendBroadcastMessage(event: event, payload: payload);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    } finally {
      await supa.removeChannel(ch);
    }
  }

  void _onInvite(Map<String, dynamic> p) {
    final callId = p['call_id'] as String?;
    final from = p['from'] as String?;
    if (callId == null || from == null) return;
    if (inCall) {
      sendOnce(roomTopic(callId), 'busy', {'from': myId});
      return;
    }
    final name = (p['from_name'] ?? 'مستخدم') as String;
    final video = (p['video'] ?? false) as bool;
    LocalNotifications.show(video ? '📹 مكالمة فيديو واردة' : '📞 مكالمة واردة', name);
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => IncomingCallScreen(
        callId: callId,
        peerId: from,
        peerName: name,
        peerAvatar: p['from_avatar'] as String?,
        video: video,
      ),
    ));
  }

  Future<void> startCall(BuildContext context,
      {required String peerId, required String peerName, String? peerAvatar, required bool video}) async {
    if (inCall) return;
    final callId = const Uuid().v4();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CallScreen(
        callId: callId,
        peerId: peerId,
        peerName: peerName,
        peerAvatar: peerAvatar,
        video: video,
        outgoing: true,
        inviteePayload: {
          'call_id': callId,
          'from': myId,
          'from_name': _myName ?? 'مستخدم',
          'from_avatar': _myAvatar,
          'video': video,
        },
      ),
    ));
  }
}
