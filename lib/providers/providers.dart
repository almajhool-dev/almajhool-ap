import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/background_service.dart';
import '../services/sound_service.dart';
import '../models/models.dart';
import '../repositories/chat_repository.dart';
import '../repositories/social_repositories.dart';
import '../repositories/user_repositories.dart';
import '../services/core_services.dart';
import '../services/local_notifications.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';
  ThemeMode _mode;
  ThemeProvider() : _mode = _read();

  ThemeMode get mode => _mode;

  static ThemeMode _read() {
    switch (CacheService.getString(_key)) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  void set(ThemeMode m) {
    _mode = m;
    CacheService.setString(_key, m.name);
    notifyListeners();
  }
}

enum SessionStatus { loading, signedOut, signedIn }

class SessionProvider extends ChangeNotifier {
  final _profiles = ProfileRepository();
  SessionStatus status = SessionStatus.loading;
  Profile? profile;
  StreamSubscription<AuthState>? _sub;
  RealtimeChannel? _profileChannel;

  SessionProvider() {
    _sub = supa.auth.onAuthStateChange.listen((s) => _handle(s.session));
    _handle(supa.auth.currentSession);
  }

  bool get isAdmin => profile?.isAdmin ?? false;

  Future<void> _handle(Session? session) async {
    if (session == null) {
      profile = null;
      status = SessionStatus.signedOut;
      _unsubscribe();
      notifyListeners();
      return;
    }
    if (status != SessionStatus.signedIn || profile?.id != session.user.id) {
      await refresh();
      status = SessionStatus.signedIn;
      _subscribe(session.user.id);
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final uid = myId;
    if (uid == null) return;
    try {
      profile = await _profiles.get(uid) ?? profile;
    } catch (_) {
      // بدون إنترنت: نبقي آخر نسخة
    }
    notifyListeners();
  }

  void _subscribe(String uid) {
    _unsubscribe();
    _profileChannel = supa
        .channel('profile-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: uid),
          callback: (p) {
            final next = Profile.fromMap(p.newRecord);
            final prev = profile;
            profile = next;
            // لا نعيد بناء الواجهة لتغيّرات صغيرة (آخر ظهور، نقاط داخل نفس المستوى) — أسلس وأخف
            final significant = prev == null ||
                prev.displayName != next.displayName ||
                prev.username != next.username ||
                prev.avatarUrl != next.avatarUrl ||
                prev.bio != next.bio ||
                prev.isAdmin != next.isAdmin ||
                prev.isBanned != next.isBanned ||
                prev.verified != next.verified ||
                prev.notificationsEnabled != next.notificationsEnabled ||
                prev.level != next.level;
            if (significant) notifyListeners();
          },
        )
        .subscribe();
  }

  void _unsubscribe() {
    if (_profileChannel != null) {
      supa.removeChannel(_profileChannel!);
      _profileChannel = null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _unsubscribe();
    super.dispose();
  }
}

/// حالة تشغيل/إيقاف التطبيق من لوحة التحكم.
class AppStatusProvider extends ChangeNotifier {
  bool enabled = true;
  String message = '';
  bool loaded = false;
  int minBuild = 0;
  String updateUrl = 'https://t.me/ikd5n';
  String updateMessage = 'هذه النسخة قديمة ومتوقفة. نزّل النسخة الجديدة من قناتنا على تلكرام.';
  RealtimeChannel? _ch;
  Timer? _poll;

  AppStatusProvider() {
    load();
    _ch = supa
        .channel('app-settings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_settings',
          callback: (p) => _apply(p.newRecord),
        )
        .subscribe();
    _poll = Timer.periodic(const Duration(seconds: 90), (_) => load());
  }

  void _apply(Map<String, dynamic> m) {
    if (m.isEmpty) return;
    // النسخ الحديثة تتبع «service_enabled» (النسخ القديمة تتبع app_enabled فقط)
    enabled = (m['service_enabled'] ?? m['app_enabled'] ?? true) as bool;
    message = (m['maintenance_message'] ?? '') as String;
    minBuild = ((m['min_build'] ?? 0) as num).toInt();
    updateUrl = (m['update_url'] ?? updateUrl) as String;
    updateMessage = (m['update_message'] ?? updateMessage) as String;
    loaded = true;
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final r = await supa.from('app_settings').select().eq('id', 1).maybeSingle();
      if (r != null) _apply(r);
    } catch (_) {
      loaded = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (_ch != null) supa.removeChannel(_ch!);
    super.dispose();
  }
}

/// مركز البيانات الحية: المحادثات، المتصلون، الإشعارات، طلبات التواصل.
class ChatHub extends ChangeNotifier with WidgetsBindingObserver {
  final ChatRepository chats = ChatRepository();
  final NotificationRepository notifs = NotificationRepository();
  final ContactRepository contacts = ContactRepository();
  final ConnectivityService connectivity;

  List<ConversationSummary> conversations = [];
  Set<String> onlineIds = {};
  int unreadNotifications = 0;
  int pendingRequests = 0;
  bool loading = true;
  String? openConversationId;

  RealtimeChannel? _feed;
  RealtimeChannel? _presence;
  Timer? _debounce;
  Timer? _heartbeat;
  StreamSubscription<void>? _reconnectSub;
  bool _started = false;

  ChatHub(this.connectivity);

  int get totalUnread => conversations.where((c) => !c.archived).fold(0, (s, c) => s + c.unread);

  bool isOnline(String? userId) => userId != null && onlineIds.contains(userId);

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final uid = myId;
    if (uid == null) return;
    WidgetsBinding.instance.addObserver(this);
    conversations = chats.cachedConversations();
    notifyListeners();
    await refresh();
    _subscribe(uid);
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) => _touch());
    _reconnectSub = connectivity.onReconnect.listen((_) async {
      await Outbox.flush(chats);
      await refresh();
    });
    unawaited(Outbox.flush(chats));
    unawaited(chats.markAllDelivered().catchError((_) {}));
  }

  Future<void> stop() async {
    _convDebounce?.cancel();
    _contactsDebounce?.cancel();
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeat?.cancel();
    _debounce?.cancel();
    await _reconnectSub?.cancel();
    if (_feed != null) await supa.removeChannel(_feed!);
    if (_presence != null) await supa.removeChannel(_presence!);
    _feed = null;
    _presence = null;
    conversations = [];
    onlineIds = {};
    unreadNotifications = 0;
    pendingRequests = 0;
  }

  Future<void> refresh() async {
    try {
      conversations = await chats.myConversations();
      _prefetch();
      unreadNotifications = await notifs.unreadCount();
      final c = await contacts.load();
      pendingRequests = c.incoming.length;
    } catch (_) {
      // بدون إنترنت: نعرض النسخة المخزنة
    }
    loading = false;
    notifyListeners();
  }

  // تحميل مسبق لرسائل آخر المحادثات (مثل ماسنجر): من تفتح المحادثة تطلع فورًا بآخر الرسائل
  final Map<String, DateTime> _prefetched = {};
  bool _prefetching = false;
  Future<void> _prefetch() async {
    if (_prefetching) return;
    _prefetching = true;
    try {
      final list = [...conversations]..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      for (final c in list.take(12)) {
        if (c.id == openConversationId) continue;
        final last = _prefetched[c.id];
        if (last != null && !c.lastMessageAt.isAfter(last)) continue;
        final cached = CacheService.messages(c.id);
        final newest = cached.isEmpty ? null : DateTime.tryParse('${cached.first['created_at']}');
        if (newest != null && !c.lastMessageAt.isAfter(newest.add(const Duration(seconds: 1)))) {
          _prefetched[c.id] = c.lastMessageAt;
          continue;
        }
        try {
          await chats.fetchMessages(c.id);
          _prefetched[c.id] = c.lastMessageAt;
        } catch (_) {
          break; // بدون إنترنت
        }
      }
    } finally {
      _prefetching = false;
    }
  }

  void refreshSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), refresh);
  }

  /// تحديث خفيف للمحادثات فقط (عند وصول رسالة) — طلب واحد بدل ثلاثة
  Timer? _convDebounce;
  void refreshConversationsSoon() {
    _convDebounce?.cancel();
    _convDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        conversations = await chats.myConversations();
        notifyListeners();
        _prefetch();
      } catch (_) {}
    });
  }

  Timer? _contactsDebounce;
  void refreshContactsSoon() {
    _contactsDebounce?.cancel();
    _contactsDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final c = await contacts.load();
        pendingRequests = c.incoming.length;
        notifyListeners();
      } catch (_) {}
    });
  }

  void _touch() {
    supa.rpc('touch_last_seen').catchError((_) {});
  }

  void _subscribe(String uid) {
    _feed = supa
        .channel('feed-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (p) => _onMessage(Message.fromMap(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversation_members',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (_) => refreshConversationsSoon(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
          callback: (p) {
            unreadNotifications++;
            notifyListeners();
            final n = AppNotification.fromMap(p.newRecord);
            LocalNotifications.show(n.title, n.body);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'contact_requests',
          callback: (_) => refreshContactsSoon(),
        )
        .subscribe();

    final presence = supa.channel('online-users', opts: RealtimeChannelConfig(key: uid));
    presence.onPresenceSync((_) {
      final ids = <String>{};
      for (final s in presence.presenceState()) {
        ids.add(s.key);
      }
      onlineIds = ids;
      notifyListeners();
    }).subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await presence.track({'user_id': uid, 'at': DateTime.now().toIso8601String()});
      }
    });
    _presence = presence;
  }

  void _onMessage(Message m) {
    refreshConversationsSoon();
    // نضيف الرسالة لذاكرة المحادثة فورًا (حتى تطلع من تفتحها بدون انتظار)
    if (m.conversationId != openConversationId) {
      try {
        final cached = CacheService.messages(m.conversationId);
        if (cached.isNotEmpty && !cached.any((x) => x['id'] == m.id)) {
          CacheService.saveMessages(m.conversationId, [m.toMap(), ...cached]).catchError((_) {});
        }
      } catch (_) {}
    }
    if (m.senderId == myId || m.isSystem) return;
    chats.markAllDelivered().catchError((_) {});
    ConversationSummary? conv;
    for (final c in conversations) {
      if (c.id == m.conversationId) conv = c;
    }
    if (conv?.muted ?? false) return;
    SoundService.messageReceived();
    if (m.conversationId == openConversationId) return;
    // التطبيق بالخلفية: خدمة الخلفية تُظهر الإشعار (حتى لا يتكرر)
    if (BackgroundBridge.healthy && !BackgroundBridge.appVisible) return;
    LocalNotifications.showMessage(m.conversationId, conv?.title ?? 'رسالة جديدة', m.previewText);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _touch();
      refresh();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
