import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import '../contacts/contacts_tab.dart';
import '../groups/group_screens.dart';
import '../notifications/notifications_tab.dart';
import '../search/search_screen.dart';
import '../settings/settings_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<ChatHub>();
    final online = context.watch<ConnectivityService>().online;
    final pages = [
      ChatsTab(onOpenRequests: () => setState(() => _index = 1)),
      const ContactsTab(),
      const NotificationsTab(),
      const SettingsTab(),
    ];
    return Scaffold(
      body: Column(
        children: [
          if (!online) SafeArea(bottom: false, child: const OfflineBanner()),
          Expanded(child: IndexedStack(index: _index, children: pages)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: hub.totalUnread > 0,
              label: Text('${hub.totalUnread}'),
              child: const Icon(Icons.chat_bubble_outline_rounded),
            ),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: 'المحادثات',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: hub.pendingRequests > 0,
              label: Text('${hub.pendingRequests}'),
              child: const Icon(Icons.people_outline_rounded),
            ),
            selectedIcon: const Icon(Icons.people_rounded),
            label: 'جهات الاتصال',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: hub.unreadNotifications > 0,
              label: Text('${hub.unreadNotifications}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            selectedIcon: const Icon(Icons.notifications_rounded),
            label: 'الإشعارات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

enum _Filter { all, unread, groups, archived }

class ChatsTab extends StatefulWidget {
  final VoidCallback onOpenRequests;
  const ChatsTab({super.key, required this.onOpenRequests});
  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  _Filter _filter = _Filter.all;

  List<ConversationSummary> _apply(List<ConversationSummary> all) {
    switch (_filter) {
      case _Filter.all:
        return all.where((c) => !c.archived).toList();
      case _Filter.unread:
        return all.where((c) => !c.archived && c.unread > 0).toList();
      case _Filter.groups:
        return all.where((c) => !c.archived && c.isGroup).toList();
      case _Filter.archived:
        return all.where((c) => c.archived).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<ChatHub>();
    final me = context.watch<SessionProvider>().profile;
    final list = _apply(hub.conversations);
    final onlineDirect = hub.conversations
        .where((c) => !c.isGroup && hub.isOnline(c.otherUserId))
        .toList();
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: hub.refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Avatar(url: me?.avatarUrl, name: me?.displayName ?? '', size: 42, online: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShaderMask(
                            shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)])
                                .createShader(r),
                            child: const Text(AppConfig.appName,
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                          ),
                          Text('مرحبًا ${me?.displayName ?? ''}',
                              style: TextStyle(fontSize: 12.5, color: scheme.onSurface.withValues(alpha: 0.6))),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'مجموعة جديدة',
                      onPressed: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGroupScreen())),
                      icon: const Icon(Icons.group_add_outlined),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                  child: InputDecorator(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث عن أشخاص أو مجموعات'),
                    child: Text('ابحث عن أشخاص أو مجموعات',
                        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5))),
                  ),
                ),
              ),
            ),
            if (onlineDirect.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 96,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: onlineDirect.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, i) {
                      final c = onlineDirect[i];
                      return GestureDetector(
                        onTap: () => openChat(context, c.id),
                        child: SizedBox(
                          width: 62,
                          child: Column(
                            children: [
                              Avatar(url: c.avatar, name: c.title, size: 56, online: true),
                              const SizedBox(height: 6),
                              Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    for (final f in _Filter.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(switch (f) {
                            _Filter.all => 'الكل',
                            _Filter.unread => 'غير مقروءة',
                            _Filter.groups => 'المجموعات',
                            _Filter.archived => 'المؤرشفة',
                          }),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                    if (hub.pendingRequests > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ActionChip(
                          avatar: const Icon(Icons.mark_email_unread_outlined, size: 18),
                          label: Text('طلبات التواصل (${hub.pendingRequests})'),
                          onPressed: widget.onOpenRequests,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (hub.loading && list.isEmpty)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (list.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.forum_outlined,
                  title: _filter == _Filter.archived ? 'لا توجد محادثات مؤرشفة' : 'لا توجد محادثات بعد',
                  subtitle: 'ابحث عن صديق وابدأ أول محادثة',
                  action: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(180, 46)),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                    icon: const Icon(Icons.person_search),
                    label: const Text('ابحث عن أشخاص'),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => ConversationTile(conv: list[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class ConversationTile extends StatelessWidget {
  final ConversationSummary conv;
  const ConversationTile({super.key, required this.conv});

  @override
  Widget build(BuildContext context) {
    final hub = context.read<ChatHub>();
    final online = !conv.isGroup && context.select<ChatHub, bool>((h) => h.isOnline(conv.otherUserId));
    final scheme = Theme.of(context).colorScheme;
    final bold = conv.unread > 0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Avatar(url: conv.avatar, name: conv.title, size: 52, online: online, group: conv.isGroup),
      title: Row(
        children: [
          Expanded(
            child: Text(conv.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ),
          if (conv.muted) Icon(Icons.volume_off_rounded, size: 16, color: scheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(width: 6),
          Text(Fmt.chatListTime(conv.lastMessageAt),
              style: TextStyle(
                  fontSize: 12, color: bold ? scheme.primary : scheme.onSurface.withValues(alpha: 0.5))),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(conv.preview.isEmpty ? (conv.isGroup ? '${conv.memberCount} أعضاء' : 'ابدأ المحادثة') : conv.preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: bold ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                )),
          ),
          Badge2(conv.unread),
        ],
      ),
      onTap: () => openChat(context, conv.id),
      onLongPress: () => _actions(context, hub),
    );
  }

  void _actions(BuildContext context, ChatHub hub) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(conv.muted ? Icons.volume_up : Icons.volume_off),
              title: Text(conv.muted ? 'إلغاء الكتم' : 'كتم المحادثة'),
              onTap: () async {
                Navigator.pop(c);
                await hub.chats.setFlags(conv.id, muted: !conv.muted);
                hub.refresh();
              },
            ),
            ListTile(
              leading: Icon(conv.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(conv.archived ? 'إلغاء الأرشفة' : 'أرشفة'),
              onTap: () async {
                Navigator.pop(c);
                await hub.chats.setFlags(conv.id, archived: !conv.archived);
                hub.refresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('تعليم كمقروءة'),
              onTap: () async {
                Navigator.pop(c);
                await hub.chats.markRead(conv.id);
                hub.refresh();
              },
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openChat(BuildContext context, String conversationId) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ChatScreen(conversationId: conversationId)),
  );
}
