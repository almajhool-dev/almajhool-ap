import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:gal/gal.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/live_repository.dart';
import '../../repositories/social_repositories.dart';
import '../../services/call_service.dart';
import '../../services/core_services.dart';
import '../../services/filter_service.dart';
import '../../services/live_recordings.dart';
import '../../repositories/chat_repository.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../feed/image_editor.dart';
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
      appBar: AppBar(title: const Text('🔴 البث المباشر'), actions: [
        TextButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyLivesScreen())),
          icon: const Icon(Icons.history_rounded),
          label: const Text('بثوثي'),
        ),
      ]),
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

class _LiveRoomScreenState extends State<LiveRoomScreen> with WidgetsBindingObserver {
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
  bool _camOn = true;
  bool _front = true;
  String _filter = 'none';
  String? _cover;
  Map<String, String> _guests = {};
  Map<String, String?> _guestCovers = {};
  bool _amGuest = false;
  bool get _publishing => widget.isHost || _amGuest;
  final Map<String, DateTime> _awaySince = {};
  Timer? _awayTimer;
  final _likesN = ValueNotifier<int>(0);
  final _heartsN = ValueNotifier<List<_Heart>>(const []);
  dynamic _rec; // تسجيل البث (MediaRecorder)
  String? _recPath;

  final List<LiveComment> _comments = [];
  final Map<String, Profile> _people = {};
  int _heartSeq = 0;
  final _rnd = Random();

  bool get _canModerate => widget.isHost || _isMod || (context.read<SessionProvider>().isAdmin);

  @override
  void initState() {
    super.initState();
    CallService.instance.inCall = true; // لا مكالمات أثناء البث
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      final info = widget.isHost ? await _repo.start(widget.title) : await _repo.join(widget.liveId!);
      _liveId = (info['live_id'] ?? widget.liveId) as String;
      _hostId = (info['host_id'] ?? myId) as String;
      _title = (info['title'] ?? widget.title) as String;
      _likes = ((info['like_count'] ?? 0) as num).toInt();
      _likesN.value = _likes;
      _isMod = info['is_mod'] == true;
      _cover = info['cover_url'] as String?;

      _host = await _profile(_hostId!);
      await _connectRealtime();

      if (Platform.isAndroid) {
        try {
          await Permission.bluetoothConnect.request();
        } catch (_) {}
      }
      await _connectRoom(info['url'] as String, info['token'] as String, publish: widget.isHost);
      if (widget.isHost) {
        _beat = Timer.periodic(const Duration(seconds: 10), (_) => _heartbeat());
        _heartbeat();
        _awayTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkAwayGuests());
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

  bool _reconnecting = false;

  /// الاتصال بغرفة البث. publish=true لصاحب البث أو الضيف (كاميرا ومايك).
  Future<void> _connectRoom(String url, String token, {required bool publish}) async {
    final old = _room;
    if (old != null) {
      _reconnecting = true;
      _listener?.dispose();
      await old.disconnect();
      await old.dispose();
    }
    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        // صورة واضحة: 720p بجودة عالية، مع طبقات أقل للمشاهدين أصحاب النت الضعيف (تختار تلقائيًا)
        defaultCameraCaptureOptions: lk.CameraCaptureOptions(
          params: const lk.VideoParameters(
            dimensions: lk.VideoDimensions(1280, 720),
            encoding: lk.VideoEncoding(maxBitrate: 2500000, maxFramerate: 30),
          ),
        ),
        defaultVideoPublishOptions: const lk.VideoPublishOptions(
          simulcast: true,
          videoEncoding: lk.VideoEncoding(maxBitrate: 2500000, maxFramerate: 30),
          videoSimulcastLayers: [lk.VideoParametersPresets.h360_169, lk.VideoParametersPresets.h540_169],
          degradationPreference: lk.DegradationPreference.maintainResolution,
        ),
      ),
    );
    _room = room;
    void refresh() {
      if (mounted) setState(() {});
    }

    _listener = room.createListener()
      ..on<lk.ParticipantConnectedEvent>((_) => _refreshCount())
      ..on<lk.ParticipantDisconnectedEvent>((e) {
        _refreshCount();
        if (!widget.isHost && e.participant.identity == _hostId) {
          Future.delayed(const Duration(seconds: 20), () {
            final back = _room?.remoteParticipants.values.any((p) => p.identity == _hostId) ?? false;
            if (mounted && !back && _endedMsg == null) _ended('انتهى البث');
          });
        }
      })
      ..on<lk.TrackSubscribedEvent>((_) => refresh())
      ..on<lk.TrackUnsubscribedEvent>((_) => refresh())
      ..on<lk.TrackMutedEvent>((_) => refresh())
      ..on<lk.TrackUnmutedEvent>((_) => refresh())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => refresh())
      ..on<lk.ParticipantMetadataUpdatedEvent>((_) => refresh())
      ..on<lk.ParticipantPermissionsUpdatedEvent>((_) => refresh())
      ..on<lk.LocalTrackPublishedEvent>((_) {
        _applyFilter();
        refresh();
      })
      ..on<lk.LocalTrackUnpublishedEvent>((_) => refresh())
      ..on<lk.RoomDisconnectedEvent>((_) {
        if (_reconnecting) return;
        if (mounted && _endedMsg == null) _ended(widget.isHost ? 'انقطع البث' : 'انتهى البث');
      });
    await room.connect(url, token);
    _reconnecting = false;
    if (publish) {
      // صاحب البث يبدأ بالكاميرا؛ الضيف يبدأ بالصوت فقط ويقرر هو فتح الكاميرا
      _camOn = widget.isHost;
      _micOn = true;
      if (_camOn) await room.localParticipant?.setCameraEnabled(true);
      await room.localParticipant?.setMicrophoneEnabled(true);
    }
    _refreshCount();
  }

  // ---------- الضيوف ----------
  Future<void> _onGuestsChanged() async {
    if (_liveId == null) return;
    try {
      final rows = await _repo.guests(_liveId!);
      _guests = {for (final r in rows) r['user_id'] as String: r['status'] as String};
      _guestCovers = {for (final r in rows) r['user_id'] as String: r['cover_url'] as String?};
      await _loadPeople(_guests.keys);
    } catch (_) {}
    final mine = _guests[myId];
    // تمت الموافقة على صعودي: الخادم يعطيني صلاحية البث مباشرة (بدون قطع المشاهدة)
    if (!widget.isHost && mine == 'accepted' && !_amGuest) {
      _amGuest = true;
      _camOn = false;
      _micOn = true;
      var ok = false;
      for (var i = 0; i < 12 && !ok && mounted && _amGuest; i++) {
        try {
          await _room?.localParticipant?.setMicrophoneEnabled(true);
          ok = true;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
      if (mounted) showSnack(context, ok ? 'صعدت للبث 🎙 (الكاميرا مغلقة، افتحها من ⋯)' : 'تعذّر الصعود، حاول مجددًا');
      if (!ok) {
        _amGuest = false;
        _repo.guestLeave(_liveId!, myId!).catchError((_) {});
      }
    } else if (!widget.isHost && _amGuest && mine != 'accepted') {
      _amGuest = false;
      await _stopRecording();
      try {
        await _room?.localParticipant?.setCameraEnabled(false);
      } catch (_) {}
      try {
        await _room?.localParticipant?.setMicrophoneEnabled(false);
      } catch (_) {}
      if (mounted) showSnack(context, 'نزلت من البث، تكمل المشاهدة 👀');
    }
    _checkAwayGuests();
    if (mounted) setState(() {});
  }

  Future<void> _guestButton() async {
    if (_liveId == null) return;
    final mine = _guests[myId];
    try {
      if (_amGuest) {
        await _repo.guestLeave(_liveId!, myId!);
      } else if (mine == 'pending') {
        showSnack(context, 'طلبك بانتظار موافقة صاحب البث');
      } else {
        if (!await confirmDialog(context, 'الصعود في البث', 'هل تريد الصعود في البث المباشر؟ سيصل طلبك لصاحب البث.',
            ok: 'طلب الصعود')) {
          return;
        }
        await _repo.guestRequest(_liveId!);
        if (mounted) showSnack(context, 'تم إرسال طلب الصعود 🙋');
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _guestsSheet() async {
    await _onGuestsChanged();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final pending = _guests.entries.where((e) => e.value == 'pending').map((e) => e.key).toList();
        final active = _guests.entries.where((e) => e.value == 'accepted').map((e) => e.key).toList();
        Future<void> act(Future<void> Function() f) async {
          try {
            await f();
            await _onGuestsChanged();
            set(() {});
          } catch (e) {
            if (mounted) showSnack(context, friendlyError(e), error: true);
          }
        }

        return SafeArea(
          child: SizedBox(
            height: 420,
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('على البث الآن (${active.length}/3)', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              for (final id in active)
                ListTile(
                  leading: Avatar(url: _people[id]?.avatarUrl, name: _people[id]?.displayName ?? ''),
                  title: Text(_people[id]?.displayName ?? 'مستخدم'),
                  trailing: TextButton(
                    onPressed: () => act(() => _repo.guestLeave(_liveId!, id)),
                    child: const Text('إنزال', style: TextStyle(color: Colors.redAccent)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('طلبات الصعود (${pending.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              if (pending.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد طلبات')),
              for (final id in pending)
                ListTile(
                  leading: Avatar(url: _people[id]?.avatarUrl, name: _people[id]?.displayName ?? ''),
                  title: Text(_people[id]?.displayName ?? 'مستخدم'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                      onPressed: () => act(() => _repo.guestRespond(_liveId!, id, false)),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(70, 36)),
                      onPressed: () => act(() => _repo.guestRespond(_liveId!, id, true)),
                      child: const Text('قبول'),
                    ),
                  ]),
                ),
            ]),
          ),
        );
      }),
    );
  }

  // ---------- صورة البث (ثابتة أو متحركة GIF) ----------
  Future<void> _pickCover() async {
    if (_liveId == null) return;
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    try {
      final bytes = await x.readAsBytes();
      final gif = x.name.toLowerCase().endsWith('.gif') || (bytes.length > 3 && bytes[0] == 0x47 && bytes[1] == 0x49);
      final data = gif ? bytes : await compressImage(bytes);
      final path = '${myId!}/live/${const Uuid().v4()}.${gif ? 'gif' : 'jpg'}';
      if (mounted) showSnack(context, 'جارٍ رفع الصورة...');
      await supa.storage.from('posts').uploadBinary(path, data,
          fileOptions: FileOptions(contentType: gif ? 'image/gif' : 'image/jpeg'));
      final url = supa.storage.from('posts').getPublicUrl(path);
      if (widget.isHost) {
        await _repo.setCover(_liveId!, url);
        if (mounted) setState(() => _cover = url);
      } else {
        await _repo.guestSetCover(_liveId!, url);
        await _onGuestsChanged();
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
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
      _likesN.value = _likes;
      for (var i = 0; i < min(n, 6); i++) {
        _addHeart();
      }
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
            final t = p.newRecord['title'];
            if (t is String && t != _title && mounted) setState(() => _title = t);
            final cv = p.newRecord['cover_url'];
            if (cv != _cover && mounted) setState(() => _cover = cv as String?);
            final st = p.newRecord['status'];
            if (st == 'ended' && mounted && _endedMsg == null) {
              final reason = p.newRecord['ended_reason'];
              _ended(reason == 'violation' ? 'تم إغلاق البث من الإدارة بسبب مخالفة القواعد' : 'انتهى البث');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_guests',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'live_id', value: id),
          callback: (_) => _onGuestsChanged(),
        )
        .subscribe();
    _toBottom();
    _onGuestsChanged();
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

  /// الضيف غائب (طلع من التطبيق أو انقطع نته)؟
  bool _isAway(String identity) {
    final r = _room;
    if (r == null) return false;
    if (identity == myId) return false;
    for (final p in r.remoteParticipants.values) {
      if (p.identity == identity) return p.metadata == 'away';
    }
    return true; // غير موجود في الغرفة = منقطع
  }

  bool _micMuted(String identity) {
    final r = _room;
    if (r == null) return false;
    if (identity == myId) return !(r.localParticipant?.isMicrophoneEnabled() ?? false);
    for (final p in r.remoteParticipants.values) {
      if (p.identity == identity) return !p.isMicrophoneEnabled();
    }
    return false;
  }

  /// صاحب البث: الضيف الغائب أكثر من 5 دقائق ينزل تلقائيًا
  void _checkAwayGuests() {
    if (!widget.isHost || _liveId == null) return;
    final now = DateTime.now();
    for (final g in _guests.entries.where((e) => e.value == 'accepted')) {
      if (_isAway(g.key)) {
        final since = _awaySince.putIfAbsent(g.key, () => now);
        if (now.difference(since).inMinutes >= 5) {
          _awaySince.remove(g.key);
          _repo.guestLeave(_liveId!, g.key).catchError((_) {});
        }
      } else {
        _awaySince.remove(g.key);
      }
    }
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
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _addHeart() {
    const colors = [Colors.pinkAccent, Colors.redAccent, Colors.amber, Colors.purpleAccent, Colors.cyanAccent];
    final h = _Heart(_heartSeq++, _rnd.nextDouble() * 50, colors[_rnd.nextInt(colors.length)]);
    final list = [..._heartsN.value, h];
    _heartsN.value = list.length > 25 ? list.sublist(list.length - 25) : list;
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      _heartsN.value = _heartsN.value.where((x) => x.id != h.id).toList();
    });
  }

  /// التكبيس: يُجمع ويُرسل كل ثانية (خفيف على النت)
  void _tap() {
    if (_liveId == null || _endedMsg != null) return;
    HapticFeedback.selectionClick();
    _likes++;
    _likesN.value = _likes;
    _pendingTaps++;
    _addHeart();
    _tapFlush ??= Timer(const Duration(milliseconds: 500), () {
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
    _stopRecording();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // الضيف/صاحب البث طلع من التطبيق: يظهر للآخرين أنه غير متصل
    if (!_publishing) return;
    final away = state == AppLifecycleState.paused || state == AppLifecycleState.detached;
    try {
      _room?.localParticipant?.setMetadata(away ? 'away' : '');
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _awayTimer?.cancel();
    _stopRecording();
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

  lk.VideoTrack? _hostVideo() => _videoOf(_hostId ?? '');

  /// فيديو مشارك معيّن (أنا أو غيري) إذا كانت كاميرته شغالة.
  lk.VideoTrack? _videoOf(String identity) {
    final r = _room;
    if (r == null) return null;
    if (identity == myId) {
      for (final p in r.localParticipant?.videoTrackPublications ?? <lk.LocalTrackPublication>[]) {
        if (p.track != null && !p.muted) return p.track as lk.VideoTrack;
      }
      return null;
    }
    for (final part in r.remoteParticipants.values) {
      if (part.identity != identity) continue;
      for (final p in part.videoTrackPublications) {
        if (p.track != null && !p.muted) return p.track as lk.VideoTrack;
      }
    }
    return null;
  }

  bool _speaking(String identity) {
    final r = _room;
    if (r == null) return false;
    if (identity == myId) return r.localParticipant?.isSpeaking ?? false;
    for (final p in r.remoteParticipants.values) {
      if (p.identity == identity) return p.isSpeaking;
    }
    return false;
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
    final t = _videoOf(myId ?? '');
    if (t is! lk.LocalVideoTrack) return;
    if (_rec != null) {
      await _stopRecording();
      if (mounted) showSnack(context, 'توقف التسجيل وحُفظ (تغيرت الكاميرا)');
    }
    _front = !_front;
    try {
      await t.setCameraPosition(_front ? lk.CameraPosition.front : lk.CameraPosition.back);
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await _applyFilter();
    if (mounted) setState(() {});
  }

  Future<void> _applyFilter() async {
    final t = _videoOf(myId ?? '');
    if (!_publishing || t is! lk.LocalVideoTrack) return;
    final id = t.mediaStreamTrack.id;
    if (id == null) return;
    await FilterService.apply(id, _filter);
  }

  Future<void> _toggleCam() async {
    if (_rec != null) {
      await _stopRecording();
      if (mounted) showSnack(context, 'توقف التسجيل وحُفظ (تغيرت الكاميرا)');
    }
    _camOn = !_camOn;
    try {
      await _room?.localParticipant?.setCameraEnabled(_camOn);
    } catch (_) {}
    if (_camOn) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _applyFilter();
    }
    if (mounted) setState(() {});
  }

  Future<void> _filtersSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (c) => SafeArea(
        child: StatefulBuilder(
          builder: (c, set) => SizedBox(
            height: 130,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              children: [
                for (final f in FilterService.filters)
                  GestureDetector(
                    onTap: () async {
                      _filter = f.id;
                      set(() {});
                      if (mounted) setState(() {});
                      await _applyFilter();
                    },
                    child: Container(
                      width: 78,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: _filter == f.id ? Colors.white24 : Colors.white10,
                        border: Border.all(color: _filter == f.id ? Colors.pinkAccent : Colors.transparent, width: 2),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(f.emoji, style: const TextStyle(fontSize: 30)),
                        const SizedBox(height: 6),
                        Text(f.name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editPin() async {
    if (_liveId == null || !(widget.isHost || _isMod)) return;
    final t = await promptText(context, 'الرسالة المثبتة', initial: _title, maxLines: 2, ok: 'تثبيت');
    if (t == null) return;
    try {
      await _repo.setTitle(_liveId!, t);
      if (mounted) setState(() => _title = t);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  // ---------- تسجيل البث (على جهاز صاحب البث) ----------
  Future<void> _toggleRecording() async {
    if (_rec != null) {
      await _stopRecording();
      if (mounted) showSnack(context, 'تم حفظ التسجيل ✅ تجده في «بثوثي»');
      return;
    }
    final t = _videoOf(myId ?? '');
    if (t is! lk.LocalVideoTrack) {
      showSnack(context, 'افتح الكاميرا أولًا حتى يبدأ التسجيل', error: true);
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/recordings');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final path = '${folder.path}/live_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final r = rtc.MediaRecorder();
      await r.start(path, videoTrack: t.mediaStreamTrack, audioChannel: rtc.RecorderAudioChannel.INPUT);
      _rec = r;
      _recPath = path;
      if (mounted) {
        setState(() {});
        showSnack(context, '⏺ بدأ تسجيل البث');
      }
    } catch (e) {
      _rec = null;
      if (mounted) showSnack(context, 'تعذّر بدء التسجيل', error: true);
    }
  }

  Future<void> _stopRecording() async {
    final r = _rec;
    final path = _recPath;
    if (r == null || path == null) return;
    _rec = null;
    _recPath = null;
    try {
      await (r as rtc.MediaRecorder).stop();
      if (File(path).existsSync()) {
        await LiveRecordings.add(LiveRecording(_liveId ?? '', _title, path, DateTime.now()));
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  // ---------- مشاركة البث ----------
  String get _liveLink => 'almajhool://live/$_liveId';

  Future<void> _shareSheet() async {
    if (_liveId == null) return;
    final hub = context.read<ChatHub>();
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(c).size.height * 0.6,
          child: Column(children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.link_rounded)),
              title: const Text('نسخ رابط البث'),
              subtitle: Text(_liveLink, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 11)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: _liveLink));
                _repo.share(_liveId!).catchError((_) {});
                Navigator.pop(c);
                showSnack(context, 'تم نسخ الرابط 🔗');
              },
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('إرسال في الخاص', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: ListView(children: [
                for (final conv in hub.conversations)
                  ListTile(
                    leading: Avatar(url: conv.avatar, name: conv.title, group: conv.isGroup),
                    title: Text(conv.title),
                    trailing: const Icon(Icons.send_rounded),
                    onTap: () async {
                      Navigator.pop(c);
                      try {
                        final repo = ChatRepository();
                        await repo.send(
                          conversationId: conv.id,
                          clientId: repo.newClientId(),
                          content: '🔴 بث مباشر لـ ${_host?.displayName ?? ''}${_title.isNotEmpty ? ': $_title' : ''}\n$_liveLink',
                        );
                        _repo.share(_liveId!).catchError((_) {});
                        if (mounted) showSnack(context, 'تم الإرسال إلى ${conv.title} ✅');
                      } catch (e) {
                        if (mounted) showSnack(context, friendlyError(e), error: true);
                      }
                    },
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _guestMenu() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(_camOn ? Icons.videocam_off_rounded : Icons.videocam_rounded),
            title: Text(_camOn ? 'إغلاق الكاميرا' : 'فتح الكاميرا'),
            onTap: () {
              Navigator.pop(c);
              _toggleCam();
            },
          ),
          if (_camOn)
            ListTile(
              leading: const Icon(Icons.cameraswitch_rounded),
              title: Text(_front ? 'الكاميرا الخلفية' : 'الكاميرا الأمامية'),
              onTap: () {
                Navigator.pop(c);
                _switchCamera();
              },
            ),
          ListTile(
            leading: Icon(_micOn ? Icons.mic_off_rounded : Icons.mic_rounded),
            title: Text(_micOn ? 'كتم المايك' : 'تشغيل المايك'),
            onTap: () {
              Navigator.pop(c);
              _toggleMic();
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_rounded),
            title: const Text('صورتي على البث (ثابتة أو متحركة)'),
            subtitle: const Text('تظهر مكان الكاميرا عندما تكون مغلقة'),
            onTap: () {
              Navigator.pop(c);
              _pickCover();
            },
          ),
          if (_guestCovers[myId] != null)
            ListTile(
              leading: const Icon(Icons.hide_image_rounded),
              title: const Text('إزالة صورتي'),
              onTap: () async {
                Navigator.pop(c);
                try {
                  await _repo.guestSetCover(_liveId!, null);
                  await _onGuestsChanged();
                } catch (_) {}
              },
            ),
          ListTile(
            leading: const Icon(Icons.call_end_rounded, color: Colors.redAccent),
            title: const Text('النزول من البث', style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              Navigator.pop(c);
              _guestButton();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _hostMenu() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(_camOn ? Icons.videocam_off_rounded : Icons.videocam_rounded),
            title: Text(_camOn ? 'إغلاق الكاميرا' : 'فتح الكاميرا'),
            onTap: () {
              Navigator.pop(c);
              _toggleCam();
            },
          ),
          ListTile(
            leading: const Icon(Icons.cameraswitch_rounded),
            title: const Text('تبديل الكاميرا'),
            onTap: () {
              Navigator.pop(c);
              _switchCamera();
            },
          ),
          ListTile(
            leading: Icon(_micOn ? Icons.mic_off_rounded : Icons.mic_rounded),
            title: Text(_micOn ? 'كتم المايك' : 'تشغيل المايك'),
            onTap: () {
              Navigator.pop(c);
              _toggleMic();
            },
          ),
          ListTile(
            leading: Icon(_rec != null ? Icons.stop_circle_rounded : Icons.fiber_manual_record_rounded,
                color: Colors.redAccent),
            title: Text(_rec != null ? 'إيقاف التسجيل وحفظه' : 'تسجيل البث'),
            subtitle: const Text('يُحفظ على جهازك، وتجده في «بثوثي»'),
            onTap: () {
              Navigator.pop(c);
              _toggleRecording();
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_rounded),
            title: const Text('مشاركة البث'),
            onTap: () {
              Navigator.pop(c);
              _shareSheet();
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_rounded),
            title: const Text('صورة للبث (ثابتة أو متحركة)'),
            subtitle: const Text('تظهر للمشاهدين عند إغلاق الكاميرا'),
            onTap: () {
              Navigator.pop(c);
              _pickCover();
            },
          ),
          if (_cover != null)
            ListTile(
              leading: const Icon(Icons.hide_image_rounded),
              title: const Text('إزالة صورة البث'),
              onTap: () async {
                Navigator.pop(c);
                try {
                  await _repo.setCover(_liveId!, null);
                  if (mounted) setState(() => _cover = null);
                } catch (_) {}
              },
            ),
          ListTile(
            leading: const Icon(Icons.push_pin_rounded),
            title: const Text('تعديل الرسالة المثبتة'),
            onTap: () {
              Navigator.pop(c);
              _editPin();
            },
          ),
          ListTile(
            leading: const Icon(Icons.people_alt_rounded),
            title: Text('المشاهدون ($_viewers)'),
            onTap: () {
              Navigator.pop(c);
              _viewersSheet();
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    await _room?.localParticipant?.setMicrophoneEnabled(_micOn);
    if (mounted) setState(() {});
  }

  /// أزرار متوازنة على جانبي مربع التعليق.
  List<Widget> _sideButtons(bool first) {
    final List<Widget> a;
    final List<Widget> b;
    if (widget.isHost) {
      a = [
        _RoundIcon(icon: Icons.auto_awesome_rounded, color: Colors.pinkAccent, onTap: _filtersSheet),
        _RoundIcon(
          icon: Icons.group_add_rounded,
          color: _guests.values.any((v) => v == 'pending') ? Colors.amberAccent : Colors.white,
          onTap: _guestsSheet,
        ),
      ];
      b = [
        _RoundIcon(icon: Icons.favorite_rounded, color: Colors.pinkAccent, onTap: _tap),
        _RoundIcon(icon: Icons.more_horiz_rounded, onTap: _hostMenu),
      ];
    } else if (_amGuest) {
      a = [
        _RoundIcon(icon: Icons.auto_awesome_rounded, color: Colors.pinkAccent, onTap: _filtersSheet),
        _RoundIcon(icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded, onTap: _toggleMic),
      ];
      b = [
        _RoundIcon(icon: Icons.favorite_rounded, color: Colors.pinkAccent, onTap: _tap),
        _RoundIcon(icon: Icons.more_horiz_rounded, onTap: _guestMenu),
      ];
    } else {
      a = [
        _RoundIcon(
          icon: _guests[myId] == 'pending' ? Icons.hourglass_top_rounded : Icons.group_add_rounded,
          color: Colors.amberAccent,
          onTap: _guestButton,
        ),
      ];
      b = [_RoundIcon(icon: Icons.favorite_rounded, color: Colors.pinkAccent, onTap: _tap)];
    }
    return first ? a : b;
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
              onTap: _tap,
              onDoubleTap: _tap,
              child: video != null
                  ? lk.VideoTrackRenderer(
                      video,
                      fit: lk.VideoViewFit.cover,
                      mirrorMode: widget.isHost && _front ? lk.VideoViewMirrorMode.mirror : lk.VideoViewMirrorMode.off,
                    )
                  : _error != null
                      ? Container(
                          color: const Color(0xFF1A1036),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!,
                              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                        )
                      : _connecting
                          ? Container(
                              color: const Color(0xFF1A1036),
                              alignment: Alignment.center,
                              child: const CircularProgressIndicator(color: Colors.white),
                            )
                          : _CameraOffView(
                              muted: _micMuted(_hostId ?? ''),
                              cover: _cover,
                              avatarUrl: host?.avatarUrl,
                              name: host?.displayName ?? '',
                              speaking: _speaking(_hostId ?? ''),
                            ),
            ),
            // الضيوف على البث
            if (_guests.values.any((v) => v == 'accepted'))
              PositionedDirectional(
                top: 110,
                start: 10,
                child: SafeArea(
                  child: Column(children: [
                    for (final g in _guests.entries.where((e) => e.value == 'accepted'))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () => widget.isHost ? _guestsSheet() : _personMenu(g.key),
                          child: _GuestTile(
                            muted: _micMuted(g.key),
                            away: _isAway(g.key),
                            cover: _guestCovers[g.key],
                            video: _videoOf(g.key),
                            mirror: g.key == myId && _front,
                            name: _people[g.key]?.displayName ?? '',
                            avatarUrl: _people[g.key]?.avatarUrl,
                            speaking: _speaking(g.key),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            // القلوب المتطايرة
            IgnorePointer(
              child: ValueListenableBuilder<List<_Heart>>(
                valueListenable: _heartsN,
                builder: (_, hearts, __) => Stack(children: [
                for (final h in hearts)
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
            ),
            // الشريط العلوي
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
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
                              constraints: const BoxConstraints(maxWidth: 170),
                              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Flexible(
                                    child: Text(host.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                  ),
                                  if (host.verified) ...[const SizedBox(width: 3), const VerifiedBadge(size: 14)],
                                  if (_micMuted(host.id)) ...[
                                    const SizedBox(width: 3),
                                    const Icon(Icons.mic_off_rounded, size: 14, color: Colors.redAccent),
                                  ],
                                ]),
                                if (host.isOwner)
                                  const Text('👑 مالك التطبيق',
                                      style: TextStyle(color: Colors.amberAccent, fontSize: 10.5, fontWeight: FontWeight.w800)),
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.favorite_rounded, size: 12, color: Colors.pinkAccent),
                                  const SizedBox(width: 3),
                                  ValueListenableBuilder<int>(
                                    valueListenable: _likesN,
                                    builder: (_, v, __) =>
                                        Text(_compact(v), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                  ),
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
                    if (_rec != null)
                      Container(
                        margin: const EdgeInsetsDirectional.only(start: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                        child: const Text('⏺ REC', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                      ),
                    IconButton(
                      onPressed: _shareSheet,
                      icon: const Icon(Icons.share_rounded, color: Colors.white),
                      tooltip: 'مشاركة',
                    ),
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
                    SizedBox(
                      height: 220,
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: ShaderMask(
                        shaderCallback: (r) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black],
                          stops: [0, 0.25],
                        ).createShader(r),
                        blendMode: BlendMode.dstIn,
                        // أحدث تعليق في الأسفل، والقديمة تصعد للأعلى
                        child: ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: _comments.length,
                          itemBuilder: (_, i) {
                            final c = _comments[_comments.length - 1 - i];
                            final p = _people[c.userId];
                            return Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: GestureDetector(
                              onLongPress: () => _personMenu(c.userId),
                              onTap: _canModerate ? () => _personMenu(c.userId) : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: c.kind == 'system'
                                        ? Colors.amber.withValues(alpha: 0.35)
                                        : Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text.rich(
                                    TextSpan(children: [
                                      if (c.kind != 'system')
                                        TextSpan(
                                          text: '${(p?.isOwner ?? false) ? '👑 ' : ''}${p?.displayName ?? '...'}'
                                              '${(p?.verified ?? false) ? ' ☑️' : ''}${c.userId == _hostId ? ' 🎙' : ''} ',
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
                              ),
                            );
                          },
                        ),
                      ),
                      ),
                      // الرسالة المثبتة: بحجم التعليق، ثابتة أسفل التعليقات
                      if (_title.isNotEmpty)
                        GestureDetector(
                          onTap: _editPin,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(14)),
                            child: Text.rich(
                              TextSpan(children: [
                                const TextSpan(text: '📌 '),
                                TextSpan(text: _title, style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w700)),
                              ]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                      child: Row(
                        children: [
                          ..._sideButtons(true),
                          const SizedBox(width: 4),
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
                                fillColor: Colors.black.withValues(alpha: 0.45),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                                suffixIcon: IconButton(
                                    onPressed: _send, icon: const Icon(Icons.send_rounded, color: Colors.white)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          ..._sideButtons(false),
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
          if (context.mounted) showSnack(context, 'أصبحت تتابعه ✅');
        } catch (_) {}
      },
      child: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(color: Colors.pinkAccent, shape: BoxShape.circle),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}


/// سجل بثوثي السابقة مع إمكانية الحذف.
class MyLivesScreen extends StatefulWidget {
  const MyLivesScreen({super.key});
  @override
  State<MyLivesScreen> createState() => _MyLivesScreenState();
}

class _MyLivesScreenState extends State<MyLivesScreen> {
  final _repo = LiveRepository();
  List<Map<String, dynamic>>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await _repo.myLives();
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _list = []);
    }
  }

  List<LiveRecording> _recs = LiveRecordings.all();

  Future<void> _recMenu(LiveRecording r) async {
    final a = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.play_circle_rounded),
              title: const Text('مشاهدة'),
              onTap: () => Navigator.pop(c, 'play')),
          ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('حفظ في المعرض'),
              onTap: () => Navigator.pop(c, 'save')),
          ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('حذف التسجيل', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (a == null || !mounted) return;
    if (a == 'play') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => _RecordingPlayer(path: r.path)));
    } else if (a == 'save') {
      try {
        await Gal.putVideo(r.path, album: 'المبرمج المجهول');
        if (mounted) showSnack(context, 'تم الحفظ في المعرض ✅');
      } catch (e) {
        if (mounted) showSnack(context, 'تعذّر الحفظ: اسمح للتطبيق بالوصول للصور', error: true);
      }
    } else if (a == 'delete') {
      if (!await confirmDialog(context, 'حذف التسجيل', 'سيُحذف الفيديو من جهازك.', ok: 'حذف', danger: true)) return;
      await LiveRecordings.remove(r);
      if (mounted) setState(() => _recs = LiveRecordings.all());
    }
  }

  Future<void> _delete(Map<String, dynamic> l) async {
    if (!await confirmDialog(context, 'حذف سجل البث', 'سيُحذف هذا البث وتعليقاته من سجلك.', ok: 'حذف', danger: true)) return;
    try {
      await _repo.delete(l['id'] as String);
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _list;
    return Scaffold(
      appBar: AppBar(title: const Text('بثوثي السابقة')),
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : l.isEmpty && _recs.isEmpty
              ? const EmptyState(icon: Icons.history_rounded, title: 'لا يوجد بثوث سابقة')
              : ListView(
                  children: [
                    if (_recs.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('🎬 تسجيلاتي (على هذا الجهاز)', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      for (final r in _recs)
                        ListTile(
                          leading: const CircleAvatar(
                              backgroundColor: Colors.redAccent, child: Icon(Icons.videocam_rounded, color: Colors.white)),
                          title: Text(r.title.isEmpty ? 'تسجيل بث' : r.title),
                          subtitle: Text('${Fmt.chatListTime(r.at)} · ${Fmt.fileSize(File(r.path).lengthSync())}'),
                          trailing: const Icon(Icons.more_vert),
                          onTap: () => _recMenu(r),
                        ),
                      const Divider(),
                    ],
                    for (final x in l)
                      ListTile(
                        leading: Icon(Icons.live_tv_rounded, color: x['status'] == 'live' ? Colors.red : null),
                        title: Text('${x['title']}'.isEmpty ? 'بث مباشر' : '${x['title']}'),
                        subtitle: Text(
                            '${Fmt.chatListTime(DateTime.tryParse('${x['started_at']}') ?? DateTime.now())} · '
                            '👁 ${x['peak']} · ❤️ ${x['likes']} · 💬 ${x['comments']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          onPressed: () => _delete(x),
                        ),
                      ),
                  ],
                ),
    );
  }
}


/// عند إغلاق الكاميرا: خلفية (صورة البث أو تدرّج) + صورة الشخص + موجات الصوت عند الكلام.
class _CameraOffView extends StatelessWidget {
  final String? cover;
  final String? avatarUrl;
  final String name;
  final bool speaking;
  final bool muted;
  const _CameraOffView(
      {required this.cover, required this.avatarUrl, required this.name, required this.speaking, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      if (cover != null)
        Image.network(cover!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => const _LiveGradient())
      else
        const _LiveGradient(),
      Container(color: Colors.black.withValues(alpha: cover != null ? 0.25 : 0)),
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _SpeakingAvatar(avatarUrl: avatarUrl, name: name, speaking: speaking && !muted, size: 104),
          const SizedBox(height: 14),
          if (muted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.mic_off_rounded, color: Colors.redAccent, size: 18),
                SizedBox(width: 6),
                Text('المايك مكتوم', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ]),
            )
          else
            _SoundWave(active: speaking),
        ]),
      ),
    ]);
  }
}

class _LiveGradient extends StatelessWidget {
  const _LiveGradient();
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3A1C71), Color(0xFFD76D77), Color(0xFFFFAF7B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
}

/// صورة دائرية تنبض بحلقات عندما يتكلم صاحبها.
class _SpeakingAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final bool speaking;
  final double size;
  const _SpeakingAvatar({required this.avatarUrl, required this.name, required this.speaking, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size + 40,
      height: size + 40,
      child: Stack(alignment: Alignment.center, children: [
        if (speaking)
          TweenAnimationBuilder<double>(
            key: const ValueKey('ring'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            builder: (_, v, __) => Container(
              width: size + 36 * v,
              height: size + 36 * v,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.8 * (1 - v)), width: 4),
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: speaking ? Colors.greenAccent : Colors.white54, width: 3),
          ),
          child: Avatar(url: avatarUrl, name: name, size: size),
        ),
      ]),
    );
  }
}

/// موجات صوت متحركة (مثل تيك توك) تظهر عند الكلام.
class _SoundWave extends StatefulWidget {
  final bool active;
  const _SoundWave({required this.active});
  @override
  State<_SoundWave> createState() => _SoundWaveState();
}

class _SoundWaveState extends State<_SoundWave> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 7; i++)
              Container(
                width: 5,
                height: widget.active ? 8 + 24 * ((sin((_c.value * pi * 2) + i * 0.9) + 1) / 2) : 5,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
              ),
          ],
        ),
      ),
    );
  }
}

/// مربع ضيف على البث: فيديو أو صورته مع مؤشر الكلام.
class _GuestTile extends StatelessWidget {
  final lk.VideoTrack? video;
  final bool mirror;
  final String name;
  final String? avatarUrl;
  final String? cover;
  final bool speaking;
  final bool muted;
  final bool away;
  const _GuestTile(
      {required this.video,
      required this.mirror,
      required this.name,
      this.avatarUrl,
      this.cover,
      required this.speaking,
      this.muted = false,
      this.away = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 146,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: speaking ? Colors.greenAccent : Colors.white38, width: 2),
        color: const Color(0xFF2A1B4D),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(fit: StackFit.expand, children: [
        if (video != null)
          lk.VideoTrackRenderer(video!,
              fit: lk.VideoViewFit.cover,
              mirrorMode: mirror ? lk.VideoViewMirrorMode.mirror : lk.VideoViewMirrorMode.off)
        else ...[
          if (cover != null) Image.network(cover!, fit: BoxFit.cover, gaplessPlayback: true),
          Center(child: _SpeakingAvatar(avatarUrl: avatarUrl, name: name, speaking: speaking, size: 46)),
          Positioned(left: 0, right: 0, bottom: 20, child: Center(child: Transform.scale(scale: 0.55, child: _SoundWave(active: speaking)))),
        ],
        if (away)
          Container(
            color: Colors.black54,
            alignment: Alignment.center,
            child: const Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.signal_wifi_connected_no_internet_4_rounded, color: Colors.white, size: 26),
              SizedBox(height: 4),
              Text('غير متصل', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        if (muted)
          const Positioned(
            top: 4,
            right: 4,
            child: CircleAvatar(
              radius: 11,
              backgroundColor: Colors.black54,
              child: Icon(Icons.mic_off_rounded, size: 14, color: Colors.redAccent),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.black45,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}


class _RecordingPlayer extends StatefulWidget {
  final String path;
  const _RecordingPlayer({required this.path});
  @override
  State<_RecordingPlayer> createState() => _RecordingPlayerState();
}

class _RecordingPlayerState extends State<_RecordingPlayer> {
  late final VideoPlayerController _c = VideoPlayerController.file(File(widget.path));

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) {
        setState(() {});
        _c.play();
      }
    });
    _c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('تسجيل البث')),
      body: !_c.value.isInitialized
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : GestureDetector(
              onTap: () => _c.value.isPlaying ? _c.pause() : _c.play(),
              child: Stack(alignment: Alignment.center, children: [
                Center(child: AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c))),
                if (!_c.value.isPlaying) const Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 80),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 24,
                  child: VideoProgressIndicator(_c, allowScrubbing: true),
                ),
              ]),
            ),
    );
  }
}
