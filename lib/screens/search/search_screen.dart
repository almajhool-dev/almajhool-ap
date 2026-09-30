import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/user_repositories.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../home/home_shell.dart';
import '../profile/profile_screens.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _profiles = ProfileRepository();
  final _chats = ChatRepository();
  Timer? _debounce;
  String _q = '';
  List<Profile> _people = [];
  List<GroupSearchResult> _groups = [];
  bool _busy = false;

  void _onChanged(String q) {
    _debounce?.cancel();
    _q = q;
    if (q.trim().isEmpty) {
      setState(() {
        _people = [];
        _groups = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() => _busy = true);
    try {
      final r = await Future.wait([_profiles.search(q), _chats.searchGroups(q)]);
      if (!mounted || q != _q) return;
      setState(() {
        _people = r[0] as List<Profile>;
        _groups = r[1] as List<GroupSearchResult>;
      });
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openGroup(GroupSearchResult g) async {
    final hub = context.read<ChatHub>();
    final member = hub.conversations.any((c) => c.id == g.id);
    try {
      if (!member) {
        final ok = await confirmDialog(context, 'الانضمام', 'هل تريد الانضمام إلى «${g.name}»؟', ok: 'انضمام');
        if (!ok) return;
        await _chats.joinPublic(g.id);
        await hub.refresh();
      }
      if (mounted) await openChat(context, g.id);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<ChatHub>();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'اسم، username، أو مجموعة',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
          onChanged: _onChanged,
        ),
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2)) : null,
      ),
      body: _q.trim().isEmpty
          ? const EmptyState(icon: Icons.travel_explore_rounded, title: 'ابحث عن الأشخاص والمجموعات', subtitle: 'النتائج تظهر فورًا أثناء الكتابة')
          : (_people.isEmpty && _groups.isEmpty && !_busy)
              ? const EmptyState(icon: Icons.search_off_rounded, title: 'لا توجد نتائج')
              : ListView(
                  children: [
                    if (_people.isNotEmpty) _header('الأشخاص'),
                    for (final p in _people)
                      ListTile(
                        leading: Avatar(url: p.avatarUrl, name: p.displayName, online: hub.isOnline(p.id)),
                        title: Text(p.displayName),
                        subtitle: Text('@${p.username}'),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: p.id))),
                      ),
                    if (_groups.isNotEmpty) _header('المجموعات'),
                    for (final g in _groups)
                      ListTile(
                        leading: Avatar(url: g.avatarUrl, name: g.name, group: true),
                        title: Text(g.name),
                        subtitle: Text(g.description.isEmpty ? 'مجموعة' : g.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _openGroup(g),
                      ),
                  ],
                ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
      );
}
