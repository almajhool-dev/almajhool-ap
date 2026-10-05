import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/sound_service.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/user_repositories.dart';
import '../../services/call_service.dart';
import '../../services/core_services.dart';
import '../../services/media_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/sticker_sheet.dart';
import '../groups/group_screens.dart';
import '../profile/profile_screens.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _repo = ChatRepository();
  final _profiles = ProfileRepository();
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();

  late final ChatHub _hub;
  String get _id => widget.conversationId;

  ConversationSummary? _conv;
  List<Member> _members = [];
  List<Message> _messages = []; // الأحدث أولًا
  List<Message> _pinned = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _uploading = 0;
  bool _blockedByMe = false;

  Message? _replyTo;
  Message? _editing;

  RealtimeChannel? _channel;
  final Map<String, Timer> _typing = {};
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _readDebounce;

  bool _recording = false;
  DateTime? _recordStart;
  Timer? _recordTicker;

  @override
  void initState() {
    super.initState();
    _hub = context.read<ChatHub>();
    _hub.openConversationId = _id;
    _scroll.addListener(_onScroll);
    _text.addListener(() => setState(() {}));
    _messages = _repo.cachedMessages(_id);
    for (final c in _hub.conversations) {
      if (c.id == _id) _conv = c;
    }
    _load();
    _loadInfo();
    _subscribe();
  }

  @override
  void dispose() {
    _hub.openConversationId = null;
    if (_channel != null) supa.removeChannel(_channel!);
    for (final t in _typing.values) {
      t.cancel();
    }
    _readDebounce?.cancel();
    _cacheDebounce?.cancel();
    final sent = _messages.where((m) => m.state == SendState.sent && !m.id.startsWith('local-')).take(60);
    CacheService.saveMessages(_id, sent.map((m) => m.toMap()).toList()).catchError((_) {});
    _recordTicker?.cancel();
    _recorder.dispose();
    _repo.markRead(_id).catchError((_) {});
    _hub.refreshSoon();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ data

  Future<void> _load() async {
    // 1) الرسائل أولًا وتطلع فورًا (بدون انتظار باقي الطلبات)
    try {
      final fetched = await _repo.fetchMessages(_id);
      final pending = Outbox.forConversation(_id).map((m) => Message(
            id: 'local-${m['client_id']}',
            clientId: m['client_id'] as String,
            conversationId: _id,
            senderId: myId,
            content: m['content'] as String?,
            replyTo: m['reply_to'] as String?,
            createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
            state: SendState.pending,
          ));
      if (!mounted) return;
      setState(() {
        // نحافظ على أي رسالة وصلت/انرسلت أثناء التحميل
        final ids = fetched.map((m) => m.id).toSet();
        final extra = _messages.where((m) =>
            !ids.contains(m.id) && (m.state != SendState.sent || m.createdAt.isAfter(fetched.isEmpty ? DateTime(2000) : fetched.first.createdAt)));
        final pend = pending.toList().reversed.toList();
        final pendIds = pend.map((m) => m.id).toSet();
        _messages = [...pend, ...extra.where((m) => !pendIds.contains(m.id)), ...fetched];
        _messages.sort((x, y) => y.createdAt.compareTo(x.createdAt));
        _hasMore = fetched.length >= 30;
        _loading = false;
      });
      _repo.markRead(_id).catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (_messages.isEmpty) showSnack(context, friendlyError(e), error: true);
    }
  }

  /// معلومات المحادثة (الأعضاء، المثبتة، الحظر) بالخلفية بدون ما تأخر الرسائل.
  Future<void> _loadInfo() async {
    try {
      final results = await Future.wait([
        _repo.members(_id),
        _repo.pinned(_id),
        _profiles.myBlocks(),
      ]);
      if (!mounted) return;
      setState(() {
        _members = results[0] as List<Member>;
        _pinned = results[1] as List<Message>;
        final blocks = results[2] as Set<String>;
        _blockedByMe = _conv != null && !_conv!.isGroup && blocks.contains(_conv!.otherUserId);
      });
    } catch (_) {}
    if (_conv == null) {
      try {
        final c = await _repo.summary(_id);
        if (mounted && c != null) setState(() => _conv = c);
      } catch (_) {}
    }
  }

  Timer? _cacheDebounce;

  /// نحفظ آخر الرسائل حتى من ترجع للمحادثة تطلع فورًا وبآخر شي.
  void _saveCache() {
    _cacheDebounce?.cancel();
    _cacheDebounce = Timer(const Duration(milliseconds: 800), () {
      final sent = _messages.where((m) => m.state == SendState.sent && !m.id.startsWith('local-')).take(60);
      CacheService.saveMessages(_id, sent.map((m) => m.toMap()).toList()).catchError((_) {});
    });
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final oldest = _messages.lastWhere((m) => m.state == SendState.sent, orElse: () => _messages.last);
      final older = await _repo.fetchMessages(_id, before: oldest.createdAt);
      if (!mounted) return;
      setState(() {
        _messages.addAll(older.where((o) => !_messages.any((m) => m.id == o.id)));
        _hasMore = older.length >= 30;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _subscribe() {
    final filter = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: _id);
    _channel = supa
        .channel('chat-$_id')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (p) => _upsert(Message.fromMap(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: filter,
          callback: (p) {
            final m = Message.fromMap(p.newRecord);
            _upsert(m);
            _refreshPinned();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversation_members',
          filter: filter,
          callback: (_) => _reloadMembers(),
        )
        .onBroadcast(
          event: 'typing',
          callback: (raw) {
            final payload = unwrapBroadcast(raw);
            final uid = payload['user_id'] as String?;
            if (uid == null || uid == myId || !mounted) return;
            _typing[uid]?.cancel();
            _typing[uid] = Timer(const Duration(seconds: 3), () {
              if (mounted) setState(() => _typing.remove(uid));
            });
            setState(() {});
          },
        )
        .subscribe();
  }

  Future<void> _reloadMembers() async {
    try {
      final m = await _repo.members(_id);
      if (mounted) setState(() => _members = m);
    } catch (_) {}
  }

  Future<void> _refreshPinned() async {
    try {
      final p = await _repo.pinned(_id);
      if (mounted) setState(() => _pinned = p);
    } catch (_) {}
  }

  void _upsert(Message m) {
    if (!mounted) return;
    setState(() {
      final i = _messages.indexWhere((x) => x.id == m.id || (m.clientId != null && x.clientId == m.clientId));
      if (i >= 0) {
        _messages[i] = m;
      } else {
        _messages.insert(0, m);
        _messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      }
      if (m.senderId != null) _typing.remove(m.senderId)?.cancel();
    });
    _saveCache();
    if (m.senderId != myId) {
      _readDebounce?.cancel();
      _readDebounce = Timer(const Duration(milliseconds: 600), () => _repo.markRead(_id).catchError((_) {}));
    }
  }

  // ------------------------------------------------------------------ helpers

  Member? get _other {
    for (final m in _members) {
      if (m.userId != myId) return m;
    }
    return null;
  }

  Profile? _profileOf(String? uid) {
    for (final m in _members) {
      if (m.userId == uid) return m.profile;
    }
    return null;
  }

  Member? get _me {
    for (final m in _members) {
      if (m.userId == myId) return m;
    }
    return null;
  }

  bool get _isGroupAdmin => _me?.role == 'owner' || _me?.role == 'admin';

  ReceiptState _receipt(Message m) {
    if (m.senderId != myId) return ReceiptState.none;
    if (m.state == SendState.pending) return ReceiptState.pending;
    if (m.state == SendState.failed) return ReceiptState.failed;
    final others = _members.where((x) => x.userId != myId).toList();
    if (others.isEmpty) return ReceiptState.sent;
    if (others.every((o) => !o.lastReadAt.isBefore(m.createdAt))) return ReceiptState.read;
    if (others.every((o) => !o.lastDeliveredAt.isBefore(m.createdAt))) return ReceiptState.delivered;
    return ReceiptState.sent;
  }

  Message? _find(String? id) {
    if (id == null) return null;
    for (final m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  String _statusLine(ChatHub hub) {
    if (_typing.isNotEmpty) {
      if (_conv?.isGroup ?? false) {
        final names = _typing.keys.map((u) => _profileOf(u)?.displayName ?? '').where((n) => n.isNotEmpty);
        return '${names.join('، ')} يكتب الآن...';
      }
      return 'يكتب الآن...';
    }
    final c = _conv;
    if (c == null) return '';
    if (c.isGroup) {
      final online = _members.where((m) => m.userId != myId && hub.isOnline(m.userId)).length;
      return '${_members.length} أعضاء${online > 0 ? ' · $online متصل' : ''}';
    }
    if (hub.isOnline(c.otherUserId)) return 'متصل الآن';
    return Fmt.lastSeen(_other?.profile?.lastSeen ?? c.otherLastSeen);
  }

  // ------------------------------------------------------------------ sending

  void _sendTyping() {
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inSeconds < 2 || _channel == null) return;
    _lastTypingSent = now;
    _channel!.sendBroadcastMessage(event: 'typing', payload: {'user_id': myId});
  }

  Future<void> _sendText() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    if (_editing != null) {
      final m = _editing!;
      _text.clear();
      setState(() => _editing = null);
      try {
        await _repo.edit(m.id, text);
      } catch (e) {
        if (mounted) showSnack(context, friendlyError(e), error: true);
      }
      return;
    }
    final clientId = _repo.newClientId();
    final reply = _replyTo;
    final local = Message(
      id: 'local-$clientId',
      clientId: clientId,
      conversationId: _id,
      senderId: myId,
      content: text,
      replyTo: reply?.id,
      createdAt: DateTime.now(),
      state: SendState.pending,
    );
    _text.clear();
    setState(() {
      _replyTo = null;
      _messages.insert(0, local);
    });
    _jumpToBottom();
    await _deliver(local);
  }

  Future<void> _deliver(Message local) async {
    try {
      final sent = await _repo.send(
        conversationId: _id,
        clientId: local.clientId!,
        type: local.type,
        content: local.content,
        fileName: local.type == 'sticker' ? local.fileName : null,
        replyTo: local.replyTo,
      );
      await Outbox.remove(local.clientId!);
      SoundService.messageSent();
      _upsert(sent);
    } catch (e) {
      final offline = local.type == 'text' && (!_hub.connectivity.online || friendlyError(e).contains('اتصال'));
      if (offline) {
        await Outbox.add({
          'conversation_id': _id,
          'client_id': local.clientId,
          'content': local.content,
          'reply_to': local.replyTo,
          'created_at': local.createdAt.toIso8601String(),
        });
      } else if (mounted) {
        showSnack(context, friendlyError(e), error: true);
      }
      _replace(local.copyWith(state: offline ? SendState.pending : SendState.failed));
    }
  }

  void _replace(Message m) {
    if (!mounted) return;
    setState(() {
      final i = _messages.indexWhere((x) => x.id == m.id);
      if (i >= 0) _messages[i] = m;
    });
  }

  bool get _meVerified {
    final me = context.read<SessionProvider>().profile;
    return (me?.verified ?? false) || (me?.isAdmin ?? false);
  }

  Future<void> _stickers() async {
    FocusScope.of(context).unfocus();
    final s = await showStickerSheet(context, verified: _meVerified);
    if (s == null || !mounted) return;
    final clientId = _repo.newClientId();
    final reply = _replyTo;
    final local = Message(
      id: 'local-$clientId',
      clientId: clientId,
      conversationId: _id,
      senderId: myId,
      type: 'sticker',
      content: s.emoji,
      fileName: s.url,
      replyTo: reply?.id,
      createdAt: DateTime.now(),
      state: SendState.pending,
    );
    setState(() {
      _replyTo = null;
      _messages.insert(0, local);
    });
    _jumpToBottom();
    try {
      final sent = await _repo.send(
        conversationId: _id,
        clientId: clientId,
        type: 'sticker',
        content: s.emoji,
        fileName: s.url,
        replyTo: reply?.id,
      );
      SoundService.messageSent();
      _upsert(sent);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
      _replace(local.copyWith(state: SendState.failed));
    }
  }

  Future<void> _sendMedia(PickedMedia? media) async {
    if (media == null) return;
    setState(() => _uploading++);
    try {
      final path = await MediaService.uploadChatFile(_id, media.file, media.fileName, media.type);
      final sent = await _repo.send(
        conversationId: _id,
        clientId: _repo.newClientId(),
        type: media.type,
        mediaPath: path,
        fileName: media.fileName,
        fileSize: media.size,
        replyTo: _replyTo?.id,
      );
      SoundService.messageSent();
      if (!mounted) return;
      setState(() => _replyTo = null);
      _upsert(sent);
      _jumpToBottom();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading--);
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      _recordTicker?.cancel();
      final path = await _recorder.stop();
      final dur = DateTime.now().difference(_recordStart ?? DateTime.now());
      setState(() => _recording = false);
      if (path == null || dur.inMilliseconds < 800) return;
      final f = File(path);
      await _sendMedia(PickedMedia(f, 'audio', 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a', await f.length()));
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) showSnack(context, 'يرجى السماح باستخدام الميكروفون', error: true);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 22050), path: path);
      setState(() {
        _recording = true;
        _recordStart = DateTime.now();
      });
      _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _cancelRecording() async {
    _recordTicker?.cancel();
    await _recorder.cancel();
    if (mounted) setState(() => _recording = false);
  }

  void _jumpToBottom() {
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  // ------------------------------------------------------------------ actions

  void _attachSheet() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            alignment: WrapAlignment.spaceAround,
            spacing: 12,
            runSpacing: 12,
            children: [
              _attachItem(c, Icons.photo_library_rounded, 'صورة', AppColors.violet, () => MediaService.pickImage()),
              _attachItem(c, Icons.photo_camera_rounded, 'كاميرا', AppColors.pink, () => MediaService.pickImage(camera: true)),
              _attachItem(c, Icons.videocam_rounded, 'فيديو', Colors.orange, MediaService.pickVideo),
              _attachItem(c, Icons.attach_file_rounded, 'ملف', AppColors.cyan, MediaService.pickFile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachItem(BuildContext sheet, IconData icon, String label, Color color, Future<PickedMedia?> Function() pick) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        Navigator.pop(sheet);
        try {
          await _sendMedia(await pick());
        } catch (e) {
          if (mounted) showSnack(context, friendlyError(e), error: true);
        }
      },
      child: SizedBox(
        width: 72,
        child: Column(children: [
          CircleAvatar(radius: 28, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color)),
          const SizedBox(height: 6),
          Text(label),
        ]),
      ),
    );
  }

  void _messageMenu(Message m) {
    final mine = m.senderId == myId;
    final canDelete = mine || _isGroupAdmin;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('رد'),
                onTap: () {
                  Navigator.pop(c);
                  setState(() {
                    _replyTo = m;
                    _editing = null;
                  });
                },
              ),
              if (m.type == 'text')
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('نسخ'),
                  onTap: () {
                    Navigator.pop(c);
                    Clipboard.setData(ClipboardData(text: m.content ?? ''));
                    showSnack(context, 'تم النسخ');
                  },
                ),
              ListTile(
                leading: const Icon(Icons.shortcut_rounded),
                title: const Text('إعادة توجيه'),
                onTap: () {
                  Navigator.pop(c);
                  _forward(m);
                },
              ),
              ListTile(
                leading: Icon(m.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
                title: Text(m.pinned ? 'إلغاء التثبيت' : 'تثبيت'),
                onTap: () async {
                  Navigator.pop(c);
                  try {
                    await _repo.togglePin(m.id);
                  } catch (e) {
                    if (mounted) showSnack(context, friendlyError(e), error: true);
                  }
                },
              ),
              if (mine && m.type == 'text')
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('تعديل'),
                  onTap: () {
                    Navigator.pop(c);
                    setState(() {
                      _editing = m;
                      _replyTo = null;
                      _text.text = m.content ?? '';
                    });
                  },
                ),
              if (canDelete)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  title: const Text('حذف للجميع', style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(c);
                    if (!await confirmDialog(context, 'حذف الرسالة', 'سيتم حذف الرسالة للجميع.', ok: 'حذف', danger: true)) return;
                    try {
                      await _repo.delete(m.id);
                    } catch (e) {
                      if (mounted) showSnack(context, friendlyError(e), error: true);
                    }
                  },
                ),
              if (!mine)
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: Colors.orange),
                  title: const Text('إبلاغ عن الرسالة'),
                  onTap: () {
                    Navigator.pop(c);
                    _report(userId: m.senderId, messageId: m.id);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _forward(Message m) async {
    final targets = _hub.conversations.where((c) => c.id != _id).toList();
    final target = await showModalBottomSheet<ConversationSummary>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, sc) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('إعادة التوجيه إلى', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            Expanded(
              child: targets.isEmpty
                  ? const Center(child: Text('لا توجد محادثات أخرى'))
                  : ListView.builder(
                      controller: sc,
                      itemCount: targets.length,
                      itemBuilder: (_, i) => ListTile(
                        leading: Avatar(url: targets[i].avatar, name: targets[i].title, group: targets[i].isGroup),
                        title: Text(targets[i].title),
                        onTap: () => Navigator.pop(c, targets[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
    if (target == null) return;
    try {
      String? path;
      if (m.hasMedia) path = await MediaService.copyToConversation(m.mediaPath!, target.id);
      await _repo.send(
        conversationId: target.id,
        clientId: _repo.newClientId(),
        type: m.type,
        content: m.content,
        mediaPath: path,
        fileName: m.fileName,
        fileSize: m.fileSize,
        forwarded: true,
      );
      if (mounted) showSnack(context, 'تمت إعادة التوجيه إلى ${target.title}');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _report({String? userId, String? messageId}) async {
    final reason = await promptText(context, 'سبب الإبلاغ', hint: 'اكتب سبب الإبلاغ', maxLines: 3, ok: 'إرسال');
    if (reason == null) return;
    try {
      await _profiles.report(reason: reason, userId: userId, messageId: messageId, conversationId: _id);
      if (mounted) showSnack(context, 'تم إرسال البلاغ للإدارة، شكرًا لك');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _toggleBlock() async {
    final other = _conv?.otherUserId;
    if (other == null) return;
    try {
      if (_blockedByMe) {
        await _profiles.unblock(other);
      } else {
        if (!await confirmDialog(context, 'حظر المستخدم', 'لن يتمكن من مراسلتك أو إرسال طلبات تواصل.', ok: 'حظر', danger: true)) {
          return;
        }
        await _profiles.block(other);
      }
      setState(() => _blockedByMe = !_blockedByMe);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  void _openInfo() {
    final c = _conv;
    if (c == null) return;
    if (c.isGroup) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => GroupInfoScreen(conversationId: _id)))
          .then((_) => _load());
    } else if (c.otherUserId != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: c.otherUserId!)));
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<ChatHub>();
    final online = context.watch<ConnectivityService>().online;
    final c = _conv;
    final title = c?.title ?? '...';
    final isGroup = c?.isGroup ?? false;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: _openInfo,
          child: Row(
            children: [
              Avatar(
                url: c?.avatar,
                name: title,
                size: 40,
                group: isGroup,
                online: !isGroup && hub.isOnline(c?.otherUserId),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NameWithBadge(title, verified: !isGroup && (c?.otherVerified ?? false), style: const TextStyle(fontSize: 17)),
                    Text(
                      _statusLine(hub),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _typing.isNotEmpty || hub.isOnline(c?.otherUserId)
                            ? AppColors.green
                            : Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!isGroup && c?.otherUserId != null && !_blockedByMe) ...[
            IconButton(
              tooltip: 'مكالمة صوتية',
              icon: const Icon(Icons.call_rounded),
              onPressed: () => CallService.instance.startCall(context,
                  peerId: c!.otherUserId!, peerName: title, peerAvatar: c.avatar, video: false),
            ),
            IconButton(
              tooltip: 'مكالمة فيديو',
              icon: const Icon(Icons.videocam_rounded),
              onPressed: () => CallService.instance.startCall(context,
                  peerId: c!.otherUserId!, peerName: title, peerAvatar: c.avatar, video: true),
            ),
          ],
          PopupMenuButton<String>(
            onSelected: (v) async {
              try {
              switch (v) {
                case 'search':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatSearchScreen(conversationId: _id, members: _members)),
                  );
                case 'info':
                  _openInfo();
                case 'mute':
                  await _repo.setFlags(_id, muted: !(c?.muted ?? false));
                  await _hub.refresh();
                  _refreshConv();
                case 'archive':
                  await _repo.setFlags(_id, archived: !(c?.archived ?? false));
                  await _hub.refresh();
                  _refreshConv();
                case 'block':
                  await _toggleBlock();
                case 'report':
                  await _report(userId: c?.otherUserId);
              }
              } catch (e) {
                if (mounted) showSnack(context, friendlyError(e), error: true);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'search', child: Text('بحث في المحادثة')),
              PopupMenuItem(value: 'info', child: Text(isGroup ? 'معلومات المجموعة' : 'الملف الشخصي')),
              PopupMenuItem(value: 'mute', child: Text((c?.muted ?? false) ? 'إلغاء الكتم' : 'كتم الإشعارات')),
              PopupMenuItem(value: 'archive', child: Text((c?.archived ?? false) ? 'إلغاء الأرشفة' : 'أرشفة المحادثة')),
              if (!isGroup) PopupMenuItem(value: 'block', child: Text(_blockedByMe ? 'إلغاء الحظر' : 'حظر المستخدم')),
              const PopupMenuItem(value: 'report', child: Text('إبلاغ')),
            ],
          ),
        ],
        bottom: _uploading > 0
            ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3))
            : null,
      ),
      body: Column(
        children: [
          if (!online) const OfflineBanner(),
          if (_pinned.isNotEmpty) _pinnedBar(),
          Expanded(child: _list(isGroup)),
          if (_blockedByMe) _blockedBar() else _composer(),
        ],
      ),
    );
  }

  void _refreshConv() {
    for (final x in _hub.conversations) {
      if (x.id == _id) setState(() => _conv = x);
    }
  }

  Widget _pinnedBar() {
    final p = _pinned.first;
    return Material(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      child: InkWell(
        onTap: () => showModalBottomSheet(
          context: context,
          showDragHandle: true,
          builder: (c) => ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('الرسائل المثبتة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              for (final m in _pinned)
                ListTile(
                  leading: const Icon(Icons.push_pin),
                  title: Text(m.previewText, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(Fmt.chatListTime(m.createdAt)),
                ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.push_pin_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(p.previewText, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (_pinned.length > 1) Text('+${_pinned.length - 1}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(bool isGroup) {
    if (_loading && _messages.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_messages.isEmpty) {
      return const EmptyState(icon: Icons.waving_hand_rounded, title: 'قل مرحبًا 👋', subtitle: 'ابدأ المحادثة الآن');
    }
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemCount: _messages.length + (_loadingMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final m = _messages[i];
        final older = i + 1 < _messages.length ? _messages[i + 1] : null;
        final newDay = older == null ||
            older.createdAt.toLocal().day != m.createdAt.toLocal().day ||
            older.createdAt.toLocal().month != m.createdAt.toLocal().month;
        final showSender = isGroup && (older == null || older.senderId != m.senderId || older.isSystem || newDay);
        final replied = _find(m.replyTo);
        return Column(
          children: [
            if (newDay) _dayChip(m.createdAt),
            MessageBubble(
              key: ValueKey(m.id),
              message: m,
              mine: m.senderId == myId,
              premium: (_profileOf(m.senderId)?.verified ?? false) ||
                  (m.senderId == myId && _meVerified) ||
                  (!(_conv?.isGroup ?? true) && m.senderId != myId && (_conv?.otherVerified ?? false)),
              showSender: showSender,
              senderName: _profileOf(m.senderId)?.displayName,
              repliedTo: replied,
              repliedSenderName: replied == null
                  ? null
                  : (replied.senderId == myId ? 'أنت' : _profileOf(replied.senderId)?.displayName),
              receipt: _receipt(m),
              onLongPress: m.state == SendState.sent ? () => _messageMenu(m) : null,
              onSwipeReply: m.state == SendState.sent ? () => setState(() => _replyTo = m) : null,
              onRetry: () {
                _replace(m.copyWith(state: SendState.pending));
                _deliver(m);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _dayChip(DateTime t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(Fmt.dayHeader(t), style: const TextStyle(fontSize: 12)),
          ),
        ),
      );

  Widget _blockedBar() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(child: Text('لقد حظرت هذا المستخدم.')),
              TextButton(onPressed: _toggleBlock, child: const Text('إلغاء الحظر')),
            ],
          ),
        ),
      );

  Widget _composer() {
    final scheme = Theme.of(context).colorScheme;
    final hasText = _text.text.trim().isNotEmpty;
    final banner = _editing != null || _replyTo != null;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (banner)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(_editing != null ? Icons.edit : Icons.reply, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _editing != null ? 'تعديل: ${_editing!.content ?? ''}' : 'رد على: ${_replyTo!.previewText}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() {
                        if (_editing != null) _text.clear();
                        _editing = null;
                        _replyTo = null;
                      }),
                    ),
                  ],
                ),
              ),
            if (_recording)
              Row(
                children: [
                  IconButton(onPressed: _cancelRecording, icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
                  const Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('جارٍ التسجيل ${Fmt.duration(DateTime.now().difference(_recordStart ?? DateTime.now()))}'),
                  ),
                  IconButton.filled(onPressed: _toggleRecording, icon: const Icon(Icons.send_rounded)),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(onPressed: _attachSheet, icon: Icon(Icons.add_circle_rounded, color: scheme.primary, size: 28)),
                  IconButton(
                    tooltip: 'ملصقات',
                    onPressed: _stickers,
                    icon: Icon(Icons.emoji_emotions_rounded, color: scheme.primary, size: 26),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 4000,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      onChanged: (_) => _sendTyping(),
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالة... 😊',
                        counterText: '',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        enabledBorder:
                            OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        focusedBorder:
                            OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                    child: hasText || _editing != null
                        ? IconButton.filled(
                            key: const ValueKey('send'),
                            onPressed: _sendText,
                            icon: Icon(_editing != null ? Icons.check_rounded : Icons.send_rounded),
                          )
                        : IconButton.filledTonal(
                            key: const ValueKey('mic'),
                            onPressed: _toggleRecording,
                            icon: const Icon(Icons.mic_rounded),
                          ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// البحث داخل المحادثة.
class ChatSearchScreen extends StatefulWidget {
  final String conversationId;
  final List<Member> members;
  const ChatSearchScreen({super.key, required this.conversationId, required this.members});
  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _repo = ChatRepository();
  List<Message> _results = [];
  bool _busy = false;
  Timer? _debounce;

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _busy = true);
      try {
        final r = await _repo.searchIn(widget.conversationId, q);
        if (mounted) setState(() => _results = r);
      } catch (e) {
        if (mounted) showSnack(context, friendlyError(e), error: true);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    });
  }

  String _name(String? uid) {
    if (uid == myId) return 'أنت';
    for (final m in widget.members) {
      if (m.userId == uid) return m.profile?.displayName ?? '';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ابحث في المحادثة', border: InputBorder.none, filled: false),
          onChanged: _search,
        ),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: _results.isEmpty
          ? const EmptyState(icon: Icons.manage_search_rounded, title: 'اكتب كلمة للبحث')
          : ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = _results[i];
                return ListTile(
                  title: Text(m.content ?? ''),
                  subtitle: Text('${_name(m.senderId)} · ${Fmt.chatListTime(m.createdAt)}'),
                );
              },
            ),
    );
  }
}
