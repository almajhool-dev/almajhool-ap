import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../live/live_screens.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../feed/community.dart';
import '../feed/feed_screens.dart';
import '../home/home_shell.dart';
import '../profile/profile_screens.dart';
import '../couple/couple_screens.dart';
import '../settings/suggestions_screen.dart';
import '../wallet/wallet_screens.dart';
import '../../services/couple_service.dart';

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
        'comment_reply' => Icons.reply_rounded,
        'couple' => Icons.favorite_rounded,
        'suggestion' => Icons.lightbulb_rounded,
        'gift' => Icons.card_giftcard_rounded,
        'withdraw' => Icons.account_balance_wallet_rounded,
        'wallet' => Icons.toll_rounded,
        'live' => Icons.live_tv_rounded,
        'follow' => Icons.person_add_rounded,
        'live_penalty' => Icons.gpp_maybe_rounded,
        'violation' => Icons.gpp_bad_rounded,
        'appeal' => Icons.gavel_rounded,
        'appeal_result' => Icons.balance_rounded,
        'follow_request' => Icons.person_add_alt_rounded,
        _ => Icons.notifications_rounded,
      };

  void _open(AppNotification n) {
    if (n.type == 'gift' || n.type == 'wallet' || n.type == 'withdraw') {
      final owner = context.read<SessionProvider>().profile?.isOwner ?? false;
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => n.type == 'withdraw' && owner && n.title.contains('جديد')
                  ? const FinanceScreen()
                  : WalletScreen(initialTab: n.type == 'wallet' ? 0 : 1)));
      return;
    }
    if (n.type == 'violation' && n.data['violation_id'] != null) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ViolationScreen(violationId: (n.data['violation_id'] as num).toInt())));
      return;
    }
    if (n.type == 'appeal') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AppealsScreen()));
      return;
    }
    if (n.type == 'follow_request') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const FollowRequestsScreen()));
      return;
    }
    if (n.type == 'suggestion') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SuggestionsScreen()));
      return;
    }
    if (n.type == 'couple') {
      CoupleService.setEnabled(true);
      Navigator.push(context, MaterialPageRoute(builder: (_) => const CoupleHomeScreen()));
      return;
    }
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
