import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/live_repository.dart';
import '../../repositories/social_repositories.dart';
import '../../services/call_service.dart';
import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../profile/profile_screens.dart';

String _compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

/// بدء بث (يسأل عن العنوان ثم يفتح شاشة البث).
Future<void> startLive(BuildContext context) async {
  final title = await promptText(context, 'عنوان البث', hint: 'مثلاً: دردشة مع المتابعين 🔥', ok: 'ابدأ البث');
  if (title == null || !context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => LiveRoomScreen.host(title: title)));
}

Future<void> openLive(BuildContext context, String liveId) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => LiveRoomScreen.viewer(liveId: liveId)));

/// قائمة البثوث المباشرة الآن.
class LiveListScreen extends StatefulWidget {
  const LiveListScreen({super.key});
  @override
  State<LiveListScreen> createState() => _LiveListScreenState();
}

class _LiveListScreenState extends State<LiveListScreen> {
  final _repo = LiveRepository();
  List<LiveSummary>? _lives;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await _repo.active();
      if (mounted) setState(() => _lives = l);
    } catch (e) {
      if (mounted) setState(() => _lives ??= []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _lives;
    return Scaffold(
      appBar: AppBar(title: const Text('🔴 البث المباشر')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        onPressed: () async {
          await startLive(context);
          _load();
        },
        icon: const Icon(Icons.videocam_rounded),
        label: const Text('ابدأ بث', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: l == null
            ? const Center(child: CircularProgressIndicator())
            : l.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    EmptyState(icon: Icons.live_tv_rounded, title: 'لا يوجد بث الآن', subtitle: 'كن أول من يبدأ بثًا مباشرًا!'),
                  ])
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, childAspectRatio: 0.72, mainAxisSpacing: 10, crossAxisSpacing: 10),
                    itemCount: l.length,
                    itemBuilder: (_, i) => _LiveTile(live: l[i], onTap: () async {
                      await openLive(context, l[i].id);
                      _load();
                    }),
                  ),
      ),
    );
  }
}

class _LiveTile extends StatelessWidget {
  final LiveSummary live;
  final VoidCallback onTap;
  const _LiveTile({required this.live, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final h = live.host;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
              colors: [Color(0xFF3A1C71), Color(0xFFD76D77)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const _LiveBadge(),
              const Spacer(),
              const Icon(Icons.visibility_rounded, size: 15, color: Colors.white),
              const SizedBox(width: 3),
              Text(_compact(live.viewers), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ]),
            const Spacer(),
            Center(child: Avatar(url: h.avatarUrl, name: h.displayName, size: 72)),
            const Spacer(),
            Row(children: [
              Flexible(
                child: NameWithBadge(h.displayName,
                    verified: h.verified, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              if (h.isOwner) ...[const SizedBox(width: 4), const OwnerChip()],
            ]),
            if (live.title.isNotEmpty)
              Text(live.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.favorite_rounded, size: 14, color: Colors.pinkAccent),
              const SizedBox(width: 3),
              Text(_compact(live.likes), style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
        child: const Text('مباشر', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
      );
}

/// شاشة البث: لصاحب البث (كاميرا) أو للمشاهد.
class LiveRoomScreen extends StatefulWidget {
  final bool isHost;
  final String? liveId;
  final String title;
  const LiveRoomScreen.host({super.key, required this.title})
      : isHost = true,
        liveId = null;
  const LiveRoomScreen.viewer({super.key, required String this.liveId})
      : isHost = false,
        title = '';

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _Heart {
  final int id;
  final double x;
  final Color color;
  _Heart(this.id, this.x, this.color);
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  final _repo = LiveRepository();
  final _text = TextEditingController();
  final _scroll = ScrollController();
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _listener;
  RealtimeChannel? _ch;
  RealtimeChannel? _db;
  Timer? _beat;
  Timer? _tapFlush;

  String? _liveId;
  String _title = '';
  String? _hostId;
  Profile? _host;
  bool _isMod = false;
  bool _connecting = true;
  String? _error;
  String? _endedMsg;

  int _viewers = 0;
  int _likes = 0;
  int _pendingTaps = 0;
  bool _micOn = true;
  bool _front = true;

  final List<LiveComment> _comments = [];
  final Map<String, Profile> _people = {};
  final List<_Heart> _hearts = [];
  int _heartSeq = 0;
  final _rnd = Random();

  bool get _canModerate => widget.isHost || _isMod || (context.read<SessionProvider>().isAdmin);

  @override
  void initState() {
    super.initState();
    CallService.instance.inCall = true; // لا مكالمات أثناء البث
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      final info = widget.isHost ? await _repo.start(widget.title) : await _repo.join(widget.liveId!);
      _liveId = (info['live_id'] ?? widget.liveId) as String;
      _hostId = (info['host_id'] ?? myId) as String;
      _title = (info['title'] ?? widget.title) as String;
      _likes = ((info['like_count'] ?? 0) as num).toInt();
      _isMod = info['is_mod'] == true;

      _host = await _profile(_hostId!);
      await _connectRealtime();

      final room = lk.Room(
        roomOptions: lk.RoomOptions(
          adaptiveStream: true,
          dynacast: true,
          defaultCameraCaptureOptions: lk.CameraCaptureOptions(params: lk.VideoParametersPresets.h720_169),
          defaultVideoPublishOptions: lk.VideoPublishOptions(simulcast: true),
        ),
      );
      _room = room;
      _listener = room.createListener()
        ..on<lk.ParticipantConnectedEvent>((_) => _refreshCount())
        ..on<lk.ParticipantDisconnectedEvent>((e) {
          _refreshCount();
          if (!widget.isHost && e.participant.identity == _hostId) {
            Future.delayed(const Duration(seconds: 15), () {
              if (mounted && _hostVideo() == null && _endedMsg == null) _ended('انتهى البث');
            });
          }
        })
        ..on<lk.TrackSubscribedEvent>((_) => mounted ? setState(() {}) : null)
        ..on<lk.TrackUnsubscribedEvent>((_) => mounted ? setState(() {}) : null)
        ..on<lk.LocalTrackPublishedEvent>((_) => mounted ? setState(() {}) : null)
        ..on<lk.RoomDisconnectedEvent>((_) {
          if (mounted && _endedMsg == null) _ended(widget.isHost ? 'انقطع البث' : 'انتهى البث');
        });

      await room.connect(info['url'] as String, info['token'] as String);
      if (widget.isHost) {
        await room.localParticipant?.setCameraEnabled(true);
        await room.localParticipant?.setMicrophoneEnabled(true);
        _beat = Timer.periodic(const Duration(seconds: 10), (_) => _heartbeat());
        _heartbeat();
      }
      _refreshCount();
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _connectRealtime() async {
    final id = _liveId!;
    _comments
      ..clear()
      ..addAll(await _repo.recentComments(id).catchError((_) => <LiveComment>[]));
    await _loadPeople(_comments.map((c) => c.userId));
    _ch = supa.channel('live-$id').onBroadcast(event: 'tap', callback: (p) {
      final n = ((p['payload'] is Map ? p['payload']['n'] : p['n']) as num?)?.toInt() ?? 1;
      _likes += n;
      for (var i = 0; i < min(n, 6); i++) {
        _addHeart();
      }
      if (mounted) setState(() {});
    }).subscribe();
    _db = supa
        .channel('live-db-$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_comments',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'live_id', value: id),
          callback: (p) async {
            final c = LiveComment.fromMap(p.newRecord);
            await _loadPeople([c.userId]);
            if (!mounted) return;
            setState(() {
              _comments.add(c);
              if (_comments.length > 120) _comments.removeRange(0, 40);
            });
            _toBottom();
            if (c.kind == 'system' && c.userId == myId && c.content.contains('طرد')) {
              _ended('تم طردك من هذا البث');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'lives',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
          callback: (p) {
            final st = p.newRecord['status'];
            if (st == 'ended' && mounted && _endedMsg == null) {
              final reason = p.newRecord['ended_reason'];
              _ended(reason == 'violation' ? 'تم إغلاق البث من الإدارة بسبب مخالفة القواعد' : 'انتهى البث');
            }
          },
        )
        .subscribe();
    _toBottom();
  }

  Future<Profile?> _profile(String id) async {
    if (_people.containsKey(id)) return _people[id];
    await _loadPeople([id]);
    return _people[id];
  }

  Future<void> _loadPeople(Iterable<String> ids) async {
    final missing = ids.where((i) => !_people.containsKey(i)).toSet().toList();
    if (missing.isEmpty) return;
    try {
      final r = await supa.from('profiles').select().inFilter('id', missing);
      for (final m in r) {
        final p = Profile.fromMap(m);
        _people[p.id] = p;
      }
    } catch (_) {}
  }

  void _refreshCount() {
    final r = _room;
    if (r == null) return;
    final others = r.remoteParticipants.values.where((p) => p.identity != _hostId).length;
    _viewers = widget.isHost ? others : others + 1;
    if (mounted) setState(() {});
  }

  Future<void> _heartbeat() async {
    final id = _liveId;
    if (id == null) return;
    try {
      final st = await _repo.heartbeat(id, _viewers, _likes);
      if (st == 'ended' && mounted && _endedMsg == null) {
        _ended('تم إغلاق البث من الإدارة بسبب مخالفة القواعد');
      }
    } catch (_) {}
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _addHeart() {
    const colors = [Colors.pinkAccent, Colors.redAccent, Colors.amber, Colors.purpleAccent, Colors.cyanAccent];
    final h = _Heart(_heartSeq++, _rnd.nextDouble() * 50, colors[_rnd.nextInt(colors.length)]);
    _hearts.add(h);
    if (_hearts.length > 30) _hearts.removeAt(0);
    Future.delayed(const Duration(milliseconds: 1800), () {
      _hearts.remove(h);
      if (mounted) setState(() {});
    });
  }

  /// التكبيس: يُجمع ويُرسل كل ثانية (خفيف على النت)
  void _tap() {
    if (_liveId == null || _endedMsg != null) return;
    HapticFeedback.selectionClick();
    _likes++;
    _pendingTaps++;
    _addHeart();
    setState(() {});
    _tapFlush ??= Timer(const Duration(milliseconds: 900), () {
      final n = _pendingTaps;
      _pendingTaps = 0;
      _tapFlush = null;
      if (n > 0) _ch?.sendBroadcastMessage(event: 'tap', payload: {'n': n});
    });
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _liveId == null) return;
    _text.clear();
    try {
      await _repo.comment(_liveId!, t);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  void _ended(String msg) {
    _endedMsg = msg;
    _beat?.cancel();
    _room?.disconnect();
    if (mounted) setState(() {});
  }

  Future<void> _close() async {
    if (widget.isHost && _liveId != null && _endedMsg == null) {
      if (!await confirmDialog(context, 'إنهاء البث', 'هل تريد إنهاء البث المباشر؟', ok: 'إنهاء', danger: true)) return;
      try {
        await _repo.end(_liveId!);
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    CallService.instance.inCall = false;
    _beat?.cancel();
    _tapFlush?.cancel();
    if (widget.isHost && _liveId != null && _endedMsg == null) {
      _repo.end(_liveId!).catchError((_) {});
    }
    _listener?.dispose();
    _room?.disconnect();
    _room?.dispose();
    if (_ch != null) supa.removeChannel(_ch!);
    if (_db != null) supa.removeChannel(_db!);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  lk.VideoTrack? _hostVideo() {
    final r = _room;
    if (r == null) return null;
    if (widget.isHost) {
      for (final p in r.localParticipant?.videoTrackPublications ?? <lk.LocalTrackPublication>[]) {
        if (p.track != null) return p.track as lk.VideoTrack;
      }
      return null;
    }
    for (final part in r.remoteParticipants.values) {
      if (part.identity != _hostId) continue;
      for (final p in part.videoTrackPublications) {
        if (p.track != null && !p.muted) return p.track as lk.VideoTrack;
      }
    }
    return null;
  }

  Future<void> _personMenu(String userId) async {
    if (_liveId == null) return;
    final p = await _profile(userId);
    if (!mounted) return;
    final isHostTarget = userId == _hostId;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Avatar(url: p?.avatarUrl, name: p?.displayName ?? ''),
              title: Text(p?.displayName ?? ''),
              subtitle: Text('@${p?.username ?? ''}'),
            ),
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: const Text('عرض الملف الشخصي'),
              onTap: () => Navigator.pop(c, 'profile'),
            ),
            if (_canModerate && !isHostTarget && userId != myId) ...[
              const Divider(),
              ListTile(
                  leading: const Icon(Icons.timer_rounded),
                  title: const Text('كتم 5 دقائق'),
                  onTap: () => Navigator.pop(c, 'mute5')),
              ListTile(
                  leading: const Icon(Icons.volume_off_rounded),
                  title: const Text('كتم للأبد'),
                  onTap: () => Navigator.pop(c, 'mute')),
              ListTile(
                  leading: const Icon(Icons.volume_up_rounded),
                  title: const Text('إلغاء الكتم'),
                  onTap: () => Navigator.pop(c, 'unmute')),
              ListTile(
                  leading: const Icon(Icons.block_rounded, color: Colors.redAccent),
                  title: const Text('طرد وحظر من البث', style: TextStyle(color: Colors.redAccent)),
                  onTap: () => Navigator.pop(c, 'kick')),
              if (widget.isHost || context.read<SessionProvider>().isAdmin) ...[
                ListTile(
                    leading: const Icon(Icons.shield_rounded, color: Colors.green),
                    title: const Text('تعيين مشرفًا'),
                    onTap: () => Navigator.pop(c, 'mod')),
                ListTile(
                    leading: const Icon(Icons.remove_moderator_rounded),
                    title: const Text('إزالة الإشراف'),
                    onTap: () => Navigator.pop(c, 'unmod')),
              ],
            ],
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'profile') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)));
      return;
    }
    try {
      await _repo.modAction(_liveId!, userId, action);
      if (mounted) showSnack(context, 'تم ✅');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _viewersSheet() async {
    final r = _room;
    if (r == null) return;
    final ids = r.remoteParticipants.values.map((p) => p.identity).where((i) => i != _hostId).toList();
    await _loadPeople(ids);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: 420,
          child: ids.isEmpty
              ? const Center(child: Text('لا يوجد مشاهدون بعد'))
              : ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('المشاهدون (${ids.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  for (final id in ids)
                    ListTile(
                      leading: Avatar(url: _people[id]?.avatarUrl, name: _people[id]?.displayName ?? ''),
                      title: Text(_people[id]?.displayName ?? 'مستخدم'),
                      trailing: const Icon(Icons.more_vert),
                      onTap: () {
                        Navigator.pop(c);
                        _personMenu(id);
                      },
                    ),
                ]),
        ),
      ),
    );
  }

  Future<void> _report() async {
    final reason = await promptText(context, 'الإبلاغ عن البث', hint: 'مثلاً: سب وشتم، محتوى مسيء...', maxLines: 3, ok: 'إبلاغ');
    if (reason == null || _liveId == null) return;
    try {
      await _repo.report(_liveId!, reason);
      if (mounted) showSnack(context, 'تم إرسال البلاغ للإدارة، شكرًا لك');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _switchCamera() async {
    final t = _hostVideo();
    if (t is! lk.LocalVideoTrack) return;
    _front = !_front;
    try {
      await t.setCameraPosition(_front ? lk.CameraPosition.front : lk.CameraPosition.back);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    await _room?.localParticipant?.setMicrophoneEnabled(_micOn);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final video = _hostVideo();
    final host = _host;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // الفيديو
            GestureDetector(
              onTap: widget.isHost ? null : _tap,
              onDoubleTap: widget.isHost ? null : _tap,
              child: video != null
                  ? lk.VideoTrackRenderer(
                      video,
                      fit: lk.VideoViewFit.cover,
                      mirrorMode: widget.isHost && _front ? lk.VideoViewMirrorMode.mirror : lk.VideoViewMirrorMode.off,
                    )
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFF1A1036), AppColors.darkBg],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter),
                      ),
                      child: Center(
                        child: _error != null
                            ? Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(_error!,
                                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                              )
                            : _connecting
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text('بانتظار الصورة...', style: TextStyle(color: Colors.white70)),
                      ),
                    ),
            ),
            // القلوب المتطايرة
            IgnorePointer(
              child: Stack(children: [
                for (final h in _hearts)
                  PositionedDirectional(
                    key: ValueKey(h.id),
                    end: 18 + h.x,
                    bottom: 120,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 1700),
                      builder: (_, v, child) => Opacity(
                        opacity: 1 - v,
                        child: Transform.translate(offset: Offset(sin(v * 6) * 12, -260 * v), child: child),
                      ),
                      child: Icon(Icons.favorite_rounded, color: h.color, size: 34),
                    ),
                  ),
              ]),
            ),
            // الشريط العلوي
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (host != null)
                      GestureDetector(
                        onTap: () => _personMenu(host.id),
                        child: Container(
                          padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 12, 4),
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(30)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Avatar(url: host.avatarUrl, name: host.displayName, size: 34),
                            const SizedBox(width: 6),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 140),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(host.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                Row(children: [
                                  const Icon(Icons.favorite_rounded, size: 12, color: Colors.pinkAccent),
                                  const SizedBox(width: 3),
                                  Text(_compact(_likes), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ]),
                              ]),
                            ),
                            if (!widget.isHost && host.id != myId) ...[
                              const SizedBox(width: 6),
                              _FollowPill(userId: host.id),
                            ],
                          ]),
                        ),
                      ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _canModerate ? _viewersSheet : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                        child: Row(children: [
                          const _LiveBadge(),
                          const SizedBox(width: 6),
                          const Icon(Icons.visibility_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 3),
                          Text(_compact(_viewers), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (!widget.isHost)
                      IconButton(
                        onPressed: _report,
                        icon: const Icon(Icons.flag_outlined, color: Colors.white),
                        tooltip: 'إبلاغ',
                      ),
                    IconButton(
                      onPressed: _close,
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                    ),
                  ],
                ),
              ),
            ),
            // التعليقات + الإدخال
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_title.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(_title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 4)])),
                      ),
                    SizedBox(
                      height: 220,
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: ShaderMask(
                        shaderCallback: (r) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                          stops: [0, 0.25],
                        ).createShader(r),
                        blendMode: BlendMode.dstIn,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: _comments.length,
                          itemBuilder: (_, i) {
                            final c = _comments[i];
                            final p = _people[c.userId];
                            return GestureDetector(
                              onLongPress: () => _personMenu(c.userId),
                              onTap: _canModerate ? () => _personMenu(c.userId) : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: c.kind == 'system' ? Colors.amber.withValues(alpha: 0.25) : Colors.black38,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text.rich(
                                    TextSpan(children: [
                                      if (c.kind != 'system')
                                        TextSpan(
                                          text: '${p?.displayName ?? '...'}${c.userId == _hostId ? ' 🎙' : ''} ',
                                          style: TextStyle(
                                              color: c.userId == _hostId ? Colors.amberAccent : Colors.cyanAccent,
                                              fontWeight: FontWeight.w800),
                                        ),
                                      TextSpan(
                                        text: c.kind == 'join' ? 'انضم 👋' : c.content,
                                        style: TextStyle(color: c.kind == 'join' ? Colors.white60 : Colors.white),
                                      ),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _text,
                              enabled: _endedMsg == null && !_connecting && _error == null,
                              style: const TextStyle(color: Colors.white),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: InputDecoration(
                                hintText: 'اكتب تعليقًا...',
                                hintStyle: const TextStyle(color: Colors.white60),
                                filled: true,
                                fillColor: Colors.white12,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                                suffixIcon: IconButton(
                                    onPressed: _send, icon: const Icon(Icons.send_rounded, color: Colors.white)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (widget.isHost) ...[
                            _RoundIcon(icon: Icons.cameraswitch_rounded, onTap: _switchCamera),
                            _RoundIcon(icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded, onTap: _toggleMic),
                            _RoundIcon(icon: Icons.people_alt_rounded, onTap: _viewersSheet),
                          ] else
                            _RoundIcon(icon: Icons.favorite_rounded, color: Colors.pinkAccent, onTap: _tap),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_endedMsg != null)
              Container(
                color: Colors.black87,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.live_tv_rounded, color: Colors.white, size: 64),
                  const SizedBox(height: 14),
                  Text(_endedMsg!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('❤️ ${_compact(_likes)}', style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 22),
                  FilledButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _RoundIcon({required this.icon, required this.onTap, this.color = Colors.white});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Material(
          color: Colors.white12,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: color)),
          ),
        ),
      );
}

class _FollowPill extends StatefulWidget {
  final String userId;
  const _FollowPill({required this.userId});
  @override
  State<_FollowPill> createState() => _FollowPillState();
}

class _FollowPillState extends State<_FollowPill> {
  bool? _following;

  @override
  void initState() {
    super.initState();
    ContactRepository().counts(widget.userId).then((c) {
      if (mounted) setState(() => _following = c['i_follow'] == true);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_following != false) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () async {
        setState(() => _following = true);
        try {
          await ContactRepository().follow(widget.userId);
        } catch (_) {}
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.pinkAccent, borderRadius: BorderRadius.circular(14)),
        child: const Text('متابعة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
      ),
    );
  }
}
