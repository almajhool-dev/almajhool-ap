import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../live/live_screens.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../feed/feed_screens.dart';
import '../home/home_shell.dart';
import '../profile/profile_screens.dart';

class NotificationsTab extends StatefulWidget {
  const NotificationsTab({super.key});
  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  List<AppNotification> _items = [];
  bool _loading = true;
  int _lastCount = -1;

  Future<void> _load() async {
    final hub = context.read<ChatHub>();
    try {
      final r = await hub.notifs.list();
      if (!mounted) return;
      setState(() {
        _items = r;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAll() async {
    final hub = context.read<ChatHub>();
    try {
      await hub.notifs.markAllRead();
      hub.unreadNotifications = 0;
      await hub.refresh();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  IconData _icon(String type) => switch (type) {
        'contact_request' => Icons.person_add_alt_1_rounded,
        'contact_accepted' => Icons.how_to_reg_rounded,
        'group_added' => Icons.group_add_rounded,
        'mention' => Icons.alternate_email_rounded,
        'broadcast' => Icons.campaign_rounded,
        'post_like' => Icons.favorite_rounded,
        'warning' => Icons.warning_amber_rounded,
        'post_comment' => Icons.mode_comment_rounded,
        'live' => Icons.live_tv_rounded,
        'follow' => Icons.person_add_rounded,
        'live_penalty' => Icons.gpp_maybe_rounded,
        _ => Icons.notifications_rounded,
      };

  void _open(AppNotification n) {
    final live = n.data['live_id'] as String?;
    if (live != null) {
      openLive(context, live);
      return;
    }
    final post = n.data['post_id'] as String?;
    if (post != null) {
      openPost(context, post);
      return;
    }
    final conv = n.data['conversation_id'] as String?;
    final user = n.data['user_id'] as String?;
    if (conv != null) {
      openChat(context, conv);
    } else if (user != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: user)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<ChatHub>();
    if (_lastCount != hub.unreadNotifications) {
      _lastCount = hub.unreadNotifications;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('الإشعارات', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                ),
                TextButton.icon(
                  onPressed: _items.any((n) => !n.read) ? _markAll : null,
                  icon: const Icon(Icons.done_all),
                  label: const Text('قراءة الكل'),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          EmptyState(icon: Icons.notifications_off_outlined, title: 'لا توجد إشعارات'),
                        ])
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final n = _items[i];
                            return Container(
                              color: n.read ? null : scheme.primary.withValues(alpha: 0.06),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: scheme.primary.withValues(alpha: 0.15),
                                  child: Icon(_icon(n.type), color: scheme.primary),
                                ),
                                title: Text(n.title, style: TextStyle(fontWeight: n.read ? FontWeight.w500 : FontWeight.w800)),
                                subtitle: Text(n.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                                trailing: Text(Fmt.chatListTime(n.createdAt), style: const TextStyle(fontSize: 11.5)),
                                onTap: () => _open(n),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
