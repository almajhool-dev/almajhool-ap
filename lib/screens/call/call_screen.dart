import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../repositories/chat_repository.dart';
import '../../services/call_service.dart';
import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';

/// شاشة مكالمة واردة.
class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String peerId;
  final String peerName;
  final String? peerAvatar;
  final bool video;
  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
    required this.video,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  Timer? _vibe;
  Timer? _timeout;
  RealtimeChannel? _room;

  @override
  void initState() {
    super.initState();
    CallService.instance.inCall = true;
    _vibe = Timer.periodic(const Duration(milliseconds: 1500), (_) => HapticFeedback.vibrate());
    _timeout = Timer(const Duration(seconds: 45), _close);
    // إذا ألغى المتصل قبل الرد
    _room = supa
        .channel(CallService.roomTopic(widget.callId))
        .onBroadcast(event: 'hangup', callback: (_) => _close())
        .subscribe();
  }

  @override
  void dispose() {
    _vibe?.cancel();
    _timeout?.cancel();
    if (_room != null) supa.removeChannel(_room!);
    super.dispose();
  }

  void _close() {
    CallService.instance.inCall = false;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _decline() async {
    _vibe?.cancel();
    try {
      await _room?.sendBroadcastMessage(event: 'reject', payload: {'from': myId});
    } catch (_) {}
    _close();
  }

  Future<void> _accept() async {
    _vibe?.cancel();
    _timeout?.cancel();
    // نغادر قناة الغرفة هنا قبل أن تشترك بها شاشة المكالمة
    if (_room != null) {
      await supa.removeChannel(_room!);
      _room = null;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => CallScreen(
        callId: widget.callId,
        peerId: widget.peerId,
        peerName: widget.peerName,
        peerAvatar: widget.peerAvatar,
        video: widget.video,
        outgoing: false,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Avatar(url: widget.peerAvatar, name: widget.peerName, size: 120),
            const SizedBox(height: 20),
            Text(widget.peerName,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(widget.video ? 'مكالمة فيديو واردة...' : 'مكالمة صوتية واردة...',
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundButton(icon: Icons.call_end_rounded, color: AppColors.danger, label: 'رفض', onTap: _decline),
                  _RoundButton(
                    icon: widget.video ? Icons.videocam_rounded : Icons.call_rounded,
                    color: AppColors.green,
                    label: 'رد',
                    onTap: _accept,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// شاشة المكالمة (صوت أو فيديو) — WebRTC.
class CallScreen extends StatefulWidget {
  final String callId;
  final String peerId;
  final String peerName;
  final String? peerAvatar;
  final bool video;
  final bool outgoing;
  final Map<String, dynamic>? inviteePayload;

  const CallScreen({
    super.key,
    required this.callId,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
    required this.video,
    required this.outgoing,
    this.inviteePayload,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  RealtimeChannel? _room;
  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteSet = false;
  // خدمة Realtime تُسقط الرسائل المتلاحقة بسرعة، لذلك نرسل العناوين داخل الـ SDP دفعة واحدة
  // وأي عناوين متأخرة تُرسل ببطء عبر طابور
  bool _localSent = false;
  bool _offering = false;
  Map<String, dynamic>? _lastSignal; // آخر عرض/رد مرسل لإعادة إرساله إذا ضاع
  final List<Map<String, dynamic>> _iceOut = [];
  Timer? _iceTimer;
  Completer<void>? _gathered;
  bool _awaitingAnswer = false;
  String? _lastOfferSdp;
  bool _relayTried = false;
  Timer? _connectWatch;
  String _diag = ''; // تشخيص: أنواع العناوين المتاحة
  List<Map<String, dynamic>> _iceAll = const [];

  static List<Map<String, dynamic>>? _iceCache;
  static DateTime? _iceCacheAt;

  Future<List<Map<String, dynamic>>> _privateIce() async {
    if (_iceCache != null && DateTime.now().difference(_iceCacheAt!).inMinutes < 30) return _iceCache!;
    try {
      final r = await supa.rpc('get_ice_servers').timeout(const Duration(seconds: 5));
      final list = (r as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      _iceCache = list;
      _iceCacheAt = DateTime.now();
      return list;
    } catch (_) {
      return _iceCache ?? const [];
    }
  }

  String _status = '';
  bool _connected = false;
  bool _ended = false;
  bool _muted = false;
  bool _cameraOff = false;
  late bool _speaker = widget.video;
  bool _remoteHasVideo = false;
  DateTime? _startedAt;
  Timer? _ticker;
  Timer? _ringTimeout;
  bool _swapViews = false;

  @override
  void initState() {
    super.initState();
    CallService.instance.inCall = true;
    _status = widget.outgoing ? 'جارٍ الاتصال...' : 'جارٍ الربط...';
    _init();
  }

  Future<void> _init() async {
    try {
      await _local.initialize();
      await _remote.initialize();

      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': widget.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
                'frameRate': {'ideal': 30},
              }
            : false,
      });
      _local.srcObject = _stream;
      await Helper.setSpeakerphoneOn(_speaker);

      // بيانات الخادم الوسيط تُجلب من قاعدة البيانات للمستخدم المسجّل فقط (غير مخزنة في التطبيق)
      final ice = [...AppConfig.iceServers, ...await _privateIce()];
      _iceAll = ice;
      _pc = await createPeerConnection({
        'iceServers': ice,
        'sdpSemantics': 'unified-plan',
      });
      for (final t in _stream!.getTracks()) {
        await _pc!.addTrack(t, _stream!);
      }
      _pc!.onIceCandidate = (c) {
        if (c.candidate == null || !_localSent) return; // قبل الإرسال: موجودة داخل الـ SDP
        _iceOut.add({'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
      };
      _pc!.onIceGatheringState = (s) {
        if (s == RTCIceGatheringState.RTCIceGatheringStateComplete && !(_gathered?.isCompleted ?? true)) {
          _gathered!.complete();
        }
      };
      _pc!.onIceConnectionState = (s) {
        if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _onConnected();
        } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _onIceFailed();
        }
      };
      _iceTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (_iceOut.isNotEmpty) _send('ice', _iceOut.removeAt(0));
      });
      _pc!.onTrack = (e) {
        if (e.streams.isNotEmpty) {
          _remote.srcObject = e.streams.first;
          if (e.track.kind == 'video') _remoteHasVideo = true;
          if (mounted) setState(() {});
        }
      };
      _pc!.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _onConnected();
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _onIceFailed();
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          if (mounted) setState(() => _status = 'انقطع الاتصال، جارٍ إعادة المحاولة...');
        }
      };

      final ready = Completer<void>();
      _room = supa
          .channel(CallService.roomTopic(widget.callId))
          .onBroadcast(event: 'accept', callback: (_) => _onAccept())
          .onBroadcast(event: 'offer', callback: (p) => _onOffer(unwrapBroadcast(p)))
          .onBroadcast(event: 'answer', callback: (p) => _onAnswer(unwrapBroadcast(p)))
          .onBroadcast(event: 'ice', callback: (p) => _onIce(unwrapBroadcast(p)))
          .onBroadcast(event: 'reject', callback: (_) => _end('رُفضت المكالمة'))
          .onBroadcast(event: 'busy', callback: (_) => _end('المستخدم في مكالمة أخرى'))
          .onBroadcast(event: 'hangup', callback: (_) => _end('انتهت المكالمة'))
          .subscribe((status, _) {
        if (status == RealtimeSubscribeStatus.subscribed && !ready.isCompleted) ready.complete();
      });
      await ready.future.timeout(const Duration(seconds: 10));

      if (widget.outgoing) {
        await CallService.sendOnce(CallService.inboxTopic(widget.peerId), 'invite', widget.inviteePayload!);
        if (mounted) setState(() => _status = 'يرن...');
        _ringTimeout = Timer(const Duration(seconds: 45), () {
          if (!_connected) _end('لا يوجد رد');
        });
      } else {
        // نعيد إرسال القبول حتى يصل العرض (في حال ضاعت الرسالة)
        for (var i = 0; i < 6 && !_remoteSet && !_ended; i++) {
          await _send('accept', {});
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        _ringTimeout = Timer(const Duration(seconds: 30), () {
          if (!_connected) _end('تعذّر الاتصال، تحقق من الإنترنت وحاول مجددًا');
        });
      }
    } catch (e) {
      _end('تعذّر بدء المكالمة: ${friendlyError(e)}');
    }
  }

  Future<void> _send(String event, Map<String, dynamic> payload) async {
    try {
      await _room?.sendBroadcastMessage(event: event, payload: payload);
    } catch (_) {}
  }

  Future<void> _onAccept() async {
    if (!widget.outgoing || _pc == null || _offering) return;
    _offering = true;
    _ringTimeout?.cancel();
    _ringTimeout = Timer(const Duration(seconds: 40), () {
      if (!_connected) _end('تعذّر الاتصال، تحقق من الإنترنت وحاول مجددًا');
    });
    if (mounted) setState(() => _status = 'جارٍ الربط...');
    await _sendOffer();
  }

  /// المتصل يرسل العرض. عند إعادة المحاولة نجبر المرور عبر الخادم الوسيط.
  Future<void> _sendOffer({bool relayOnly = false}) async {
    if (relayOnly) {
      await _pc!.setConfiguration({
        'iceServers': _iceAll,
        'iceTransportPolicy': 'relay',
        'sdpSemantics': 'unified-plan',
      });
    }
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': widget.video,
      if (relayOnly) 'iceRestart': true,
    });
    _awaitingAnswer = true;
    await _setLocalAndSend(offer, 'offer');
  }

  /// إذا لم يتصل خلال 12 ثانية من وصول الرد: نعيد المحاولة عبر الوسيط مرة واحدة.
  void _watchConnection() {
    _connectWatch?.cancel();
    _connectWatch = Timer(const Duration(seconds: 12), () {
      if (!_connected && !_ended) _onIceFailed();
    });
  }

  Future<void> _onIceFailed() async {
    if (_connected || _ended) return;
    if (widget.outgoing && !_relayTried) {
      _relayTried = true;
      if (mounted) setState(() => _status = 'جارٍ تجربة مسار بديل عبر الخادم الوسيط...');
      try {
        await _sendOffer(relayOnly: true);
      } catch (_) {
        _end('تعذّر الاتصال (الشبكة)');
      }
    } else if (!widget.outgoing) {
      // المستقبل ينتظر عرض المسار البديل من المتصل
      if (mounted) setState(() => _status = 'جارٍ تجربة مسار بديل...');
    } else {
      _end('تعذّر الاتصال: شبكة أحد الطرفين تمنع المكالمات');
    }
  }

  Future<void> _onOffer(Map<String, dynamic> p) async {
    if (widget.outgoing || _pc == null) return;
    final sdp = p['sdp'] as String?;
    if (sdp == _lastOfferSdp) {
      if (_lastSignal != null) await _send('answer', _lastSignal!); // الرد السابق ضاع
      return;
    }
    _lastOfferSdp = sdp;
    if (sdp != null && sdp.contains('typ relay') && !sdp.contains('typ host')) {
      // المتصل انتقل للمسار الوسيط: نفعل مثله
      await _pc!.setConfiguration({
        'iceServers': _iceAll,
        'iceTransportPolicy': 'relay',
        'sdpSemantics': 'unified-plan',
      });
    }
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, p['type'] as String?));
    _remoteSet = true;
    await _flushIce();
    final answer = await _pc!.createAnswer({});
    await _setLocalAndSend(answer, 'answer');
    _watchConnection();
  }

  /// نضبط الوصف المحلي، ننتظر جمع العناوين (حتى 4 ثوانٍ)، ثم نرسل رسالة واحدة كاملة.
  Future<void> _setLocalAndSend(RTCSessionDescription desc, String event) async {
    _gathered = Completer<void>();
    await _pc!.setLocalDescription(desc);
    try {
      await _gathered!.future.timeout(const Duration(seconds: 4));
    } catch (_) {}
    final full = await _pc!.getLocalDescription() ?? desc;
    _localSent = true;
    _lastSignal = {'sdp': full.sdp, 'type': full.type};
    _updateDiag(full.sdp ?? '');
    await _send(event, _lastSignal!);
    if (event == 'offer') {
      // إعادة إرسال العرض إذا لم يصل رد
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(seconds: 4));
        if (!_awaitingAnswer || _ended) break;
        await _send('offer', _lastSignal!);
      }
    }
  }

  void _updateDiag(String sdp) {
    final host = 'typ host'.allMatches(sdp).length;
    final srflx = 'typ srflx'.allMatches(sdp).length;
    final relay = 'typ relay'.allMatches(sdp).length;
    String mark(int n) => n > 0 ? '✓' : '✗';
    _diag = 'محلي ${mark(host)} · إنترنت ${mark(srflx)} · وسيط ${mark(relay)}';
    if (mounted) setState(() {});
  }

  Future<void> _onAnswer(Map<String, dynamic> p) async {
    if (!widget.outgoing || _pc == null || !_awaitingAnswer) return;
    _awaitingAnswer = false;
    await _pc!.setRemoteDescription(RTCSessionDescription(p['sdp'] as String?, p['type'] as String?));
    _remoteSet = true;
    await _flushIce();
    _watchConnection();
  }

  Future<void> _onIce(Map<String, dynamic> p) async {
    final c = RTCIceCandidate(
      p['candidate'] as String?,
      p['sdpMid'] as String?,
      (p['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (_remoteSet && _pc != null) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    } else {
      _pendingIce.add(c);
    }
  }

  Future<void> _flushIce() async {
    for (final c in _pendingIce) {
      try {
        await _pc?.addCandidate(c);
      } catch (_) {}
    }
    _pendingIce.clear();
  }

  void _onConnected() {
    if (_connected) return;
    _connectWatch?.cancel();
    _connected = true;
    _ringTimeout?.cancel();
    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() => _status = '');
  }

  Future<void> _hangup() async {
    await _send('hangup', {});
    _end('انتهت المكالمة');
  }

  Future<void> _end(String reason) async {
    if (_ended) return;
    _ended = true;
    _ticker?.cancel();
    _ringTimeout?.cancel();
    final duration = _startedAt == null ? null : DateTime.now().difference(_startedAt!);
    if (mounted) setState(() => _status = reason);

    // سجل المكالمة في المحادثة (من طرف المتصل فقط)
    if (widget.outgoing) {
      final kind = widget.video ? '📹 مكالمة فيديو' : '📞 مكالمة صوتية';
      final text = duration == null ? '$kind · لم يتم الرد' : '$kind · ${Fmt.duration(duration)}';
      unawaited(() async {
        try {
          final repo = ChatRepository();
          final conv = await repo.openDirect(widget.peerId);
          await repo.send(conversationId: conv, clientId: repo.newClientId(), content: text);
        } catch (_) {}
      }());
    }

    await _cleanup();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cleanup() async {
    _iceTimer?.cancel();
    _connectWatch?.cancel();
    try {
      for (final t in _stream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _stream?.dispose();
      await _pc?.close();
    } catch (_) {}
    if (_room != null) {
      await supa.removeChannel(_room!);
      _room = null;
    }
    CallService.instance.inCall = false;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ringTimeout?.cancel();
    _iceTimer?.cancel();
    if (!_ended) {
      _send('hangup', {});
      _cleanup();
    }
    _local.dispose();
    _remote.dispose();
    super.dispose();
  }

  void _toggleMute() {
    _muted = !_muted;
    for (final t in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_muted;
    }
    setState(() {});
  }

  void _toggleCamera() {
    _cameraOff = !_cameraOff;
    for (final t in _stream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !_cameraOff;
    }
    setState(() {});
  }

  Future<void> _switchCamera() async {
    final tracks = _stream?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  Future<void> _toggleSpeaker() async {
    _speaker = !_speaker;
    await Helper.setSpeakerphoneOn(_speaker);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final showRemoteVideo = widget.video && _connected && _remoteHasVideo;
    final elapsed = _startedAt == null ? null : DateTime.now().difference(_startedAt!);
    return PopScope(
      canPop: _ended,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangup();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: showRemoteVideo
                  ? RTCVideoView(
                      _swapViews ? _local : _remote,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      mirror: _swapViews,
                    )
                  : (widget.video && !_cameraOff && !_connected)
                      ? RTCVideoView(_local, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF1A1036), AppColors.darkBg],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
            ),
            if (!showRemoteVideo)
              Align(
                alignment: const Alignment(0, -0.35),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Avatar(url: widget.peerAvatar, name: widget.peerName, size: 116),
                    const SizedBox(height: 18),
                    Text(widget.peerName,
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      elapsed != null && _status.isEmpty ? Fmt.duration(elapsed) : _status,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    if (!_connected && _diag.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(_diag, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            if (showRemoteVideo)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.peerName,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
                              shadows: [Shadow(blurRadius: 6)])),
                      Text(elapsed == null ? _status : Fmt.duration(elapsed),
                          style: const TextStyle(color: Colors.white70, shadows: [Shadow(blurRadius: 6)])),
                    ],
                  ),
                ),
              ),
            if (widget.video && _connected && !_cameraOff)
              PositionedDirectional(
                top: 48,
                end: 16,
                child: GestureDetector(
                  onTap: () => setState(() => _swapViews = !_swapViews),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 110,
                      height: 160,
                      child: RTCVideoView(
                        _swapViews ? _remote : _local,
                        mirror: !_swapViews,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 28, left: 12, right: 12),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _RoundButton(
                        icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        color: _muted ? Colors.white : Colors.white24,
                        iconColor: _muted ? Colors.black : Colors.white,
                        onTap: _toggleMute,
                      ),
                      if (widget.video)
                        _RoundButton(
                          icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                          color: _cameraOff ? Colors.white : Colors.white24,
                          iconColor: _cameraOff ? Colors.black : Colors.white,
                          onTap: _toggleCamera,
                        ),
                      if (widget.video)
                        _RoundButton(icon: Icons.cameraswitch_rounded, color: Colors.white24, onTap: _switchCamera),
                      _RoundButton(
                        icon: _speaker ? Icons.volume_up_rounded : Icons.hearing_rounded,
                        color: _speaker ? Colors.white : Colors.white24,
                        iconColor: _speaker ? Colors.black : Colors.white,
                        onTap: _toggleSpeaker,
                      ),
                      _RoundButton(icon: Icons.call_end_rounded, color: AppColors.danger, onTap: _hangup),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String? label;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.color, required this.onTap, this.iconColor = Colors.white, this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 64, height: 64, child: Icon(icon, color: iconColor, size: 30)),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(label!, style: const TextStyle(color: Colors.white)),
        ],
      ],
    );
  }
}
