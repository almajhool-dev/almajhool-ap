import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../repositories/chat_repository.dart';
import '../../services/call_service.dart';
import '../../services/core_services.dart';
import '../../services/push_service.dart';
import '../../services/sound_service.dart';
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
  Timer? _poll;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    CallService.instance.inCall = true;
    PushService.cancelCallNotification();
    _vibe = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.vibrate();
      SoundService.startRingtone(); // لا يتكرر إذا كان يرن
    });
    SoundService.startRingtone();
    _timeout = Timer(const Duration(seconds: 45), _close);
    // إذا ألغى المتصل قبل الرد
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        final r = await CallSignal.fetch(widget.callId);
        final st = r?['status'] as String?;
        if (st != null && st != 'ringing' && st != 'accepted') _close();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _vibe?.cancel();
    _timeout?.cancel();
    _poll?.cancel();
    SoundService.stopRingtone();
    super.dispose();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _poll?.cancel();
    SoundService.stopRingtone();
    CallService.instance.inCall = false;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _decline() async {
    _vibe?.cancel();
    unawaited(CallSignal.update(widget.callId, status: 'rejected').catchError((_) {}));
    _close();
  }

  Future<void> _accept() async {
    _vibe?.cancel();
    await SoundService.stopRingtone();
    _timeout?.cancel();
    _poll?.cancel();
    _closed = true;
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

/// إشارات المكالمة محفوظة في قاعدة البيانات (جدول call_sessions):
/// لا تضيع حتى لو كانت الشبكة ضعيفة، وكل طرف يقرأها بشكل دوري.
class CallSignal {
  CallSignal._();

  static Future<Map<String, dynamic>?> fetch(String id) =>
      supa.from('call_sessions').select().eq('id', id).maybeSingle().timeout(const Duration(seconds: 6));

  static Future<void> create(String id, String callee, bool video) =>
      supa.rpc('call_create', params: {'p_id': id, 'p_callee': callee, 'p_video': video});

  static Future<void> update(String id,
          {String? status, Map<String, dynamic>? offer, Map<String, dynamic>? answer, Map<String, dynamic>? ice}) =>
      supa.rpc('call_update', params: {
        'p_id': id,
        'p_status': status,
        'p_offer': offer,
        'p_answer': answer,
        'p_ice': ice,
      }).timeout(const Duration(seconds: 8));
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
  List<Map<String, dynamic>> _iceAll = const [];

  // حالة الإشارات
  Timer? _poll;
  bool _polling = false;
  int _myVersion = 0; // إصدار العرض الذي أرسلناه (المتصل) أو أجبنا عليه (المستقبل)
  bool _remoteSet = false;
  int _remoteIceApplied = 0;
  bool _accepted = false;
  bool _gatheringDone = false;
  bool _sdpSent = false;
  Completer<void>? _gathered;
  bool _relayTried = false;
  Timer? _connectWatch;

  // تشخيص
  String _diagLocal = '';
  String _diagRemote = '';
  String _iceState = '';

  static List<Map<String, dynamic>>? _iceCache;
  static DateTime? _iceCacheAt;

  Future<List<Map<String, dynamic>>> _privateIce() async {
    if (_iceCache != null && DateTime.now().difference(_iceCacheAt!).inMinutes < 30) return _iceCache!;
    try {
      final r = await supa.rpc('get_ice_servers').timeout(const Duration(seconds: 5));
      final list = (r as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
      if (list.isNotEmpty) {
        _iceCache = list;
        _iceCacheAt = DateTime.now();
        return list;
      }
    } catch (_) {}
    // احتياطي: إذا لم يُضبط الخادم من لوحة التحكم نستخدم نسخة مدمجة مشفّرة
    return _iceCache ?? _fallbackRelay();
  }

  static List<Map<String, dynamic>> _fallbackRelay() {
    String d(String b64) {
      const k = 'almajhool-2026-relay';
      final bytes = base64.decode(b64);
      return String.fromCharCodes([for (var i = 0; i < bytes.length; i++) bytes[i] ^ k.codeUnitAt(i % k.length)]);
    }
    return [
      {
        'urls': [
          'turn:global.relay.metered.ca:80',
          'turn:global.relay.metered.ca:80?transport=tcp',
          'turn:global.relay.metered.ca:443',
          'turns:global.relay.metered.ca:443?transport=tcp',
        ],
        'username': d('A1oPAF9bDl4PSAQFVg4aEQRbWBwCXlkD'),
        'credential': d('DQkIUB4jLjk5aGoDAXl6NQ=='),
      },
    ];
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

  void _setStatus(String s) {
    if (_connected || _ended) return;
    if (mounted) setState(() => _status = s);
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

      if (widget.outgoing) {
        // ننشئ المكالمة في قاعدة البيانات أولًا ثم نرسل الدعوة الفورية
        await CallSignal.create(widget.callId, widget.peerId, widget.video);
        unawaited(CallService.sendOnce(CallService.inboxTopic(widget.peerId), 'invite', widget.inviteePayload!)
            .catchError((_) {}));
        _setStatus('يرن...');
        unawaited(SoundService.startRingback(speaker: _speaker));
        _ringTimeout = Timer(const Duration(seconds: 45), () {
          if (!_connected) _end(_accepted ? 'تعذّر الاتصال، حاول مجددًا' : 'لا يوجد رد');
        });
      } else {
        await CallSignal.update(widget.callId, status: 'accepted');
        _ringTimeout = Timer(const Duration(seconds: 50), () {
          if (!_connected) _end('تعذّر الاتصال، تحقق من الإنترنت وحاول مجددًا');
        });
      }

      final ice = [...AppConfig.iceServers, ...await _privateIce()];
      _iceAll = ice;
      _pc = await createPeerConnection({
        'iceServers': ice,
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 2,
      });
      for (final t in _stream!.getTracks()) {
        await _pc!.addTrack(t, _stream!);
      }
      _pc!.onIceCandidate = (c) {
        // العناوين قبل الإرسال موجودة داخل الـ SDP، والمتأخرة تُضاف لقاعدة البيانات
        if (c.candidate == null || !_sdpSent) return;
        unawaited(CallSignal.update(widget.callId, ice: {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        }).catchError((_) {}));
      };
      _pc!.onIceGatheringState = (s) {
        if (s == RTCIceGatheringState.RTCIceGatheringStateComplete) {
          _gatheringDone = true;
          if (!(_gathered?.isCompleted ?? true)) _gathered!.complete();
        }
      };
      _pc!.onIceConnectionState = (s) {
        _iceState = s.toString().split('RTCIceConnectionState').last;
        if (mounted) setState(() {});
        if (s == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            s == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _onConnected();
        } else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          _onIceFailed();
        }
      };
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
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected && _connected) {
          if (mounted) setState(() => _status = 'الشبكة ضعيفة، جارٍ إعادة الاتصال...');
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected && _connected) {
          if (mounted) setState(() => _status = '');
        }
      };

      _poll = Timer.periodic(const Duration(milliseconds: 700), (_) => _tick());
      unawaited(_tick());
    } catch (e) {
      _end('تعذّر بدء المكالمة: ${friendlyError(e)}');
    }
  }

  /// قراءة حالة المكالمة من قاعدة البيانات والتصرف حسبها.
  Future<void> _tick() async {
    if (_polling || _ended || _pc == null) return;
    _polling = true;
    try {
      final r = await CallSignal.fetch(widget.callId);
      if (r == null || _ended) return;
      final st = r['status'] as String? ?? 'ringing';
      if (st == 'rejected') return _end('رُفضت المكالمة');
      if (st == 'busy') return _end('المستخدم في مكالمة أخرى');
      if (st == 'ended') return _end('انتهت المكالمة');

      if (widget.outgoing) {
        if (st == 'accepted' && !_accepted) {
          _accepted = true;
          await _stopRingback();
          _ringTimeout?.cancel();
          _ringTimeout = Timer(const Duration(seconds: 45), () {
            if (!_connected) _end('تعذّر الاتصال، حاول مجددًا');
          });
          _setStatus('جارٍ الربط (1/3)...');
          await _sendOffer();
        }
        final ans = r['answer'];
        if (ans is Map && !_remoteSet && (ans['v'] as num?)?.toInt() == _myVersion && _myVersion > 0) {
          final sdp = ans['sdp'] as String?;
          await _pc!.setRemoteDescription(RTCSessionDescription(sdp, ans['type'] as String? ?? 'answer'));
          _remoteSet = true;
          _diagRemote = _candTypes(sdp ?? '');
          _setStatus('جارٍ الربط (3/3)...');
          _watchConnection();
        }
      } else {
        final off = r['offer'];
        final v = off is Map ? (off['v'] as num?)?.toInt() ?? 0 : 0;
        if (off is Map && v > _myVersion) {
          _myVersion = v;
          _remoteSet = false;
          _remoteIceApplied = 0;
          final sdp = off['sdp'] as String?;
          if (off['relay'] == true) {
            await _pc!.setConfiguration({
              'iceServers': _iceAll,
              'iceTransportPolicy': 'relay',
              'sdpSemantics': 'unified-plan',
            });
          }
          _setStatus('جارٍ الربط (2/3)...');
          await _pc!.setRemoteDescription(RTCSessionDescription(sdp, off['type'] as String? ?? 'offer'));
          _remoteSet = true;
          _diagRemote = _candTypes(sdp ?? '');
          final answer = await _pc!.createAnswer({});
          final full = await _setLocalAndGather(answer);
          await CallSignal.update(widget.callId, answer: {'sdp': full.sdp, 'type': full.type, 'v': v});
          _setStatus('جارٍ الربط (3/3)...');
          _watchConnection();
        }
      }

      // عناوين الشبكة المتأخرة من الطرف الآخر
      if (_remoteSet) {
        final list = (widget.outgoing ? r['callee_ice'] : r['caller_ice']) as List? ?? const [];
        while (_remoteIceApplied < list.length) {
          final p = list[_remoteIceApplied++];
          if (p is! Map) continue;
          try {
            await _pc!.addCandidate(RTCIceCandidate(
              p['candidate'] as String?,
              p['sdpMid'] as String?,
              (p['sdpMLineIndex'] as num?)?.toInt(),
            ));
          } catch (_) {}
        }
      }
    } catch (_) {
      // خطأ مؤقت في الشبكة: نحاول في الدورة القادمة
    } finally {
      _polling = false;
    }
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
    final full = await _setLocalAndGather(offer);
    _myVersion++;
    _remoteSet = false;
    _remoteIceApplied = 0;
    await CallSignal.update(widget.callId,
        offer: {'sdp': full.sdp, 'type': full.type, 'v': _myVersion, if (relayOnly) 'relay': true});
    _setStatus(relayOnly ? 'جارٍ تجربة مسار بديل عبر الخادم الوسيط...' : 'جارٍ الربط (2/3)...');
  }

  /// نضبط الوصف المحلي وننتظر جمع العناوين (حتى 6 ثوانٍ) حتى تُرسل كلها مرة واحدة.
  Future<RTCSessionDescription> _setLocalAndGather(RTCSessionDescription desc) async {
    _gathered = Completer<void>();
    _gatheringDone = false;
    await _pc!.setLocalDescription(desc);
    if (!_gatheringDone) {
      try {
        await _gathered!.future.timeout(const Duration(seconds: 6));
      } catch (_) {}
    }
    final full = await _pc!.getLocalDescription() ?? desc;
    _sdpSent = true;
    _diagLocal = _candTypes(full.sdp ?? '');
    if (mounted) setState(() {});
    return full;
  }

  /// إذا لم يتصل خلال 12 ثانية: نعيد المحاولة عبر الوسيط مرة واحدة.
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
      try {
        await _sendOffer(relayOnly: true);
        _ringTimeout?.cancel();
        _ringTimeout = Timer(const Duration(seconds: 30), () {
          if (!_connected) _end('تعذّر الاتصال: شبكة أحد الطرفين تمنع المكالمات');
        });
      } catch (_) {
        _end('تعذّر الاتصال (الشبكة)');
      }
    } else if (!widget.outgoing) {
      _setStatus('جارٍ تجربة مسار بديل...');
    }
  }

  String _candTypes(String sdp) {
    String mark(String t) => sdp.contains('typ $t') ? '✓' : '✗';
    return 'محلي ${mark('host')} · إنترنت ${mark('srflx')} · وسيط ${mark('relay')}';
  }

  Future<void> _stopRingback() async {
    if (!widget.outgoing) return;
    await SoundService.stopRingback();
    try {
      await Helper.setSpeakerphoneOn(_speaker);
    } catch (_) {}
  }

  void _onConnected() {
    if (_connected) return;
    unawaited(_stopRingback());
    _connectWatch?.cancel();
    _connected = true;
    _ringTimeout?.cancel();
    _startedAt = DateTime.now();
    // بعد الاتصال نتحقق من الإنهاء كل ثانيتين فقط
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() => _status = '');
  }

  Future<void> _hangup() async {
    unawaited(CallSignal.update(widget.callId, status: 'ended').catchError((_) {}));
    _end('انتهت المكالمة');
  }

  Future<void> _end(String reason) async {
    if (_ended) return;
    _ended = true;
    SoundService.stopRingback();
    _poll?.cancel();
    _ticker?.cancel();
    _ringTimeout?.cancel();
    final duration = _startedAt == null ? null : DateTime.now().difference(_startedAt!);
    if (mounted) setState(() => _status = reason);
    unawaited(CallSignal.update(widget.callId, status: 'ended').catchError((_) {}));

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
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _cleanup() async {
    _poll?.cancel();
    _connectWatch?.cancel();
    try {
      for (final t in _stream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _stream?.dispose();
      await _pc?.close();
    } catch (_) {}
    CallService.instance.inCall = false;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ringTimeout?.cancel();
    _poll?.cancel();
    SoundService.stopRingback();
    if (!_ended) {
      _ended = true;
      unawaited(CallSignal.update(widget.callId, status: 'ended').catchError((_) {}));
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
                    if (!_connected && _diagLocal.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'أنا: $_diagLocal'
                        '${_diagRemote.isEmpty ? '' : '\nهو: $_diagRemote'}'
                        '${_iceState.isEmpty ? '' : '\nICE: $_iceState'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
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
