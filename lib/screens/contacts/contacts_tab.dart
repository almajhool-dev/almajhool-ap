import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/social_repositories.dart';
import '../../repositories/user_repositories.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../home/home_shell.dart';
import '../profile/profile_screens.dart';
import '../search/search_screen.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});
  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  final _repo = ContactRepository();
  List<ContactRequest> _incoming = [];
  List<ContactRequest> _outgoing = [];
  List<Profile> _contacts = [];
  List<Profile> _suggestions = [];
  bool _loading = true;
  int _lastPending = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _repo.load();
      final s = await ProfileRepository().suggestions();
      if (!mounted) return;
      setState(() {
        _incoming = r.incoming;
        _outgoing = r.outgoing;
        _contacts = r.contacts;
        _suggestions = s;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (mounted) showSnack(context, ok);
      await _load();
      if (mounted) context.read<ChatHub>().refreshSoon();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<ChatHub>();
    if (_lastPending != hub.pendingRequests) {
      _lastPending = hub.pendingRequests;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final onlineContacts = _contacts.where((p) => hub.isOnline(p.id)).toList();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('جهات الاتصال', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_search_rounded),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
                  ),
                ],
              ),
            ),
            if (_loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
            if (_incoming.isNotEmpty) ...[
              _header('طلبات التواصل (${_incoming.length})'),
              for (final r in _incoming)
                ListTile(
                  leading: Avatar(url: r.other?.avatarUrl, name: r.other?.displayName ?? ''),
                  title: Text(r.other?.displayName ?? ''),
                  subtitle: Text('@${r.other?.username ?? ''}'),
                  onTap: () => _openProfile(r.other?.id),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.filled(
                        tooltip: 'قبول',
                        onPressed: () => _act(() => _repo.respond(r.id, true), 'تم القبول'),
                        icon: const Icon(Icons.check),
                      ),
                      IconButton(
                        tooltip: 'رفض',
                        onPressed: () => _act(() => _repo.respond(r.id, false), 'تم الرفض'),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
            ],
            if (onlineContacts.isNotEmpty) ...[
              _header('المتصلون الآن (${onlineContacts.length})'),
              for (final p in onlineContacts) _contactTile(p, true),
            ],
            _header('جهات الاتصال (${_contacts.length})'),
            if (!_loading && _contacts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('لا توجد جهات اتصال بعد. أرسل طلب تواصل لأصدقائك.'),
              ),
            for (final p in _contacts) _contactTile(p, hub.isOnline(p.id)),
            if (_outgoing.isNotEmpty) ...[
              _header('طلبات مرسلة'),
              for (final r in _outgoing)
                ListTile(
                  leading: Avatar(url: r.other?.avatarUrl, name: r.other?.displayName ?? ''),
                  title: Text(r.other?.displayName ?? ''),
                  subtitle: const Text('بانتظار القبول'),
                  onTap: () => _openProfile(r.other?.id),
                  trailing: TextButton(
                    onPressed: () => _act(() => _repo.remove(r.receiverId), 'تم إلغاء الطلب'),
                    child: const Text('إلغاء'),
                  ),
                ),
            ],
            if (_suggestions.isNotEmpty) ...[
              _header('أشخاص قد تعرفهم'),
              for (final p in _suggestions)
                ListTile(
                  leading: Avatar(url: p.avatarUrl, name: p.displayName, online: hub.isOnline(p.id)),
                  title: Text(p.displayName),
                  subtitle: Text('@${p.username}'),
                  onTap: () => _openProfile(p.id),
                  trailing: IconButton.filledTonal(
                    tooltip: 'إرسال طلب تواصل',
                    onPressed: () => _act(() => _repo.send(p.id), 'تم إرسال الطلب'),
                    icon: const Icon(Icons.person_add_alt_1),
                  ),
                ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
      );

  Widget _contactTile(Profile p, bool online) => ListTile(
        leading: Avatar(url: p.avatarUrl, name: p.displayName, online: online),
        title: Text(p.displayName),
        subtitle: Text(online ? 'متصل الآن' : Fmt.lastSeen(p.lastSeen)),
        onTap: () => _openProfile(p.id),
        trailing: IconButton(
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          onPressed: () => startDirectChat(context, p.id),
        ),
      );

  void _openProfile(String? id) {
    if (id == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: id))).then((_) => _load());
  }
}

Future<void> startDirectChat(BuildContext context, String userId) async {
  try {
    final id = await context.read<ChatHub>().chats.openDirect(userId);
    if (context.mounted) {
      context.read<ChatHub>().refreshSoon();
      await openChat(context, id);
    }
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e), error: true);
  }
}
