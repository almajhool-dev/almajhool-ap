import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/chat_repository.dart';
import '../../repositories/social_repositories.dart';
import '../../repositories/user_repositories.dart';
import '../../services/core_services.dart';
import '../../services/media_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screens.dart';

/// اختيار أشخاص (من جهات الاتصال أو البحث).
class PeoplePicker extends StatefulWidget {
  final Set<String> exclude;
  final ValueChanged<Set<String>> onChanged;
  const PeoplePicker({super.key, this.exclude = const {}, required this.onChanged});
  @override
  State<PeoplePicker> createState() => _PeoplePickerState();
}

class _PeoplePickerState extends State<PeoplePicker> {
  final _selected = <String, Profile>{};
  List<Profile> _contacts = [];
  List<Profile> _results = [];
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    ContactRepository().load().then((r) {
      if (mounted) {
        setState(() {
          _contacts = r.contacts;
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _search(String q) async {
    _q = q;
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    final r = await ProfileRepository().search(q);
    if (mounted && q == _q) setState(() => _results = r);
  }

  @override
  Widget build(BuildContext context) {
    final list = (_q.trim().length >= 2 ? _results : _contacts).where((p) => !widget.exclude.contains(p.id)).toList();
    return Column(
      children: [
        if (_selected.isNotEmpty)
          SizedBox(
            height: 78,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final p in _selected.values)
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: InputChip(
                      avatar: Avatar(url: p.avatarUrl, name: p.displayName, size: 24),
                      label: Text(p.displayName),
                      onDeleted: () {
                        setState(() => _selected.remove(p.id));
                        widget.onChanged(_selected.keys.toSet());
                      },
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث عن اسم أو username'),
            onChanged: _search,
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const EmptyState(icon: Icons.person_search, title: 'لا يوجد أشخاص', subtitle: 'ابحث بالاسم لإضافة أعضاء')
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final p = list[i];
                        final sel = _selected.containsKey(p.id);
                        return CheckboxListTile(
                          value: sel,
                          onChanged: (_) {
                            setState(() => sel ? _selected.remove(p.id) : _selected[p.id] = p);
                            widget.onChanged(_selected.keys.toSet());
                          },
                          secondary: Avatar(url: p.avatarUrl, name: p.displayName),
                          title: Text(p.displayName),
                          subtitle: Text('@${p.username}', textDirection: TextDirection.ltr, textAlign: TextAlign.start),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _repo = ChatRepository();
  Set<String> _members = {};
  File? _avatar;
  bool _public = false;
  bool _busy = false;

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 60) {
      showSnack(context, 'أدخل اسمًا للمجموعة (حتى 60 حرفًا)', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await _repo.createGroup(
        name: name,
        description: _desc.text.trim(),
        isPublic: _public,
        memberIds: _members.toList(),
      );
      if (_avatar != null) {
        final url = await MediaService.uploadAvatar(_avatar!, groupId: id);
        await _repo.updateGroup(id, avatarUrl: url);
      }
      if (!mounted) return;
      context.read<ChatHub>().refresh();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: id)));
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مجموعة جديدة'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('إنشاء', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    final f = await MediaService.pickAvatar();
                    if (f != null) setState(() => _avatar = f);
                  },
                  child: CircleAvatar(
                    radius: 34,
                    backgroundImage: _avatar == null ? null : FileImage(_avatar!),
                    child: _avatar == null ? const Icon(Icons.add_a_photo_outlined) : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      TextField(controller: _name, decoration: const InputDecoration(hintText: 'اسم المجموعة')),
                      const SizedBox(height: 8),
                      TextField(controller: _desc, decoration: const InputDecoration(hintText: 'وصف (اختياري)', isDense: true)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            value: _public,
            onChanged: (v) => setState(() => _public = v),
            title: const Text('مجموعة عامة'),
            subtitle: const Text('يمكن لأي شخص العثور عليها عبر البحث والانضمام'),
          ),
          const Divider(),
          Expanded(child: PeoplePicker(onChanged: (s) => _members = s)),
        ],
      ),
    );
  }
}

class GroupInfoScreen extends StatefulWidget {
  final String conversationId;
  const GroupInfoScreen({super.key, required this.conversationId});
  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final _repo = ChatRepository();
  Map<String, dynamic>? _conv;
  List<Member> _members = [];
  bool _loading = true;

  String get _id => widget.conversationId;

  Member? get _me {
    for (final m in _members) {
      if (m.userId == myId) return m;
    }
    return null;
  }

  bool get _isOwner => _me?.role == 'owner';
  bool get _isAdmin => _isOwner || _me?.role == 'admin';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _repo.conversation(_id);
      final m = await _repo.members(_id);
      if (mounted) {
        setState(() {
          _conv = c;
          _members = m;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showSnack(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    try {
      await f();
      if (ok != null && mounted) showSnack(context, ok);
      await _load();
      if (mounted) context.read<ChatHub>().refreshSoon();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _addMembers() async {
    Set<String> picked = {};
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (c) => Scaffold(
          appBar: AppBar(
            title: const Text('إضافة أعضاء'),
            actions: [TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('إضافة'))],
          ),
          body: PeoplePicker(exclude: _members.map((m) => m.userId).toSet(), onChanged: (s) => picked = s),
        ),
      ),
    );
    if (ok == true && picked.isNotEmpty) {
      await _run(() => _repo.addMembers(_id, picked.toList()), ok: 'تمت الإضافة');
    }
  }

  void _memberMenu(Member m) {
    if (m.userId == myId) return;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('عرض الملف الشخصي'),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: m.userId)));
              },
            ),
            if (_isOwner && m.role != 'owner')
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: Text(m.role == 'admin' ? 'إزالة من المشرفين' : 'تعيين مشرفًا'),
                onTap: () {
                  Navigator.pop(c);
                  _run(() => _repo.setRole(_id, m.userId, m.role == 'admin' ? 'member' : 'admin'));
                },
              ),
            if (_isOwner || (_isAdmin && m.role == 'member'))
              ListTile(
                leading: const Icon(Icons.person_remove_outlined, color: Colors.redAccent),
                title: const Text('إزالة من المجموعة', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(c);
                  _run(() => _repo.removeMember(_id, m.userId), ok: 'تمت الإزالة');
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit() async {
    final name = await promptText(context, 'اسم المجموعة', initial: _conv?['name'] ?? '');
    if (name == null) return;
    await _run(() => _repo.updateGroup(_id, name: name));
  }

  Future<void> _editDescription() async {
    final d = await promptText(context, 'وصف المجموعة', initial: _conv?['description'] ?? '', maxLines: 3);
    if (d == null) return;
    await _run(() => _repo.updateGroup(_id, description: d));
  }

  Future<void> _changeAvatar() async {
    final f = await MediaService.pickAvatar();
    if (f == null) return;
    await _run(() async {
      final url = await MediaService.uploadAvatar(f, groupId: _id);
      await _repo.updateGroup(_id, avatarUrl: url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<ChatHub>();
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final c = _conv;
    if (c == null) return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.group_off, title: 'المجموعة غير موجودة'));
    final name = (c['name'] ?? '') as String;
    final desc = (c['description'] ?? '') as String;
    final isPublic = (c['is_public'] ?? false) as bool;
    return Scaffold(
      appBar: AppBar(
        title: const Text('معلومات المجموعة'),
        actions: [if (_isAdmin) IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined))],
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: _isAdmin ? _changeAvatar : null,
              child: Avatar(url: c['avatar_url'] as String?, name: name, size: 104, group: true),
            ),
          ),
          const SizedBox(height: 12),
          Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text('${_members.length} أعضاء · ${isPublic ? 'عامة' : 'خاصة'}',
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(desc.isEmpty ? 'لا يوجد وصف' : desc),
            trailing: _isAdmin ? const Icon(Icons.edit, size: 18) : null,
            onTap: _isAdmin ? _editDescription : null,
          ),
          if (_isAdmin)
            SwitchListTile(
              value: isPublic,
              onChanged: (v) => _run(() => _repo.updateGroup(_id, isPublic: v)),
              title: const Text('مجموعة عامة'),
              secondary: const Icon(Icons.public),
            ),
          const Divider(),
          if (_isAdmin)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_add_alt_1)),
              title: const Text('إضافة أعضاء'),
              onTap: _addMembers,
            ),
          for (final m in _members)
            ListTile(
              leading: Avatar(
                url: m.profile?.avatarUrl,
                name: m.profile?.displayName ?? '',
                online: hub.isOnline(m.userId),
              ),
              title: Text(m.userId == myId ? 'أنت' : (m.profile?.displayName ?? '')),
              subtitle: Text('@${m.profile?.username ?? ''}'),
              trailing: m.role == 'member'
                  ? null
                  : Chip(label: Text(m.roleLabel), visualDensity: VisualDensity.compact),
              onTap: () => _memberMenu(m),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('مغادرة المجموعة', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              if (!await confirmDialog(context, 'مغادرة المجموعة', 'هل تريد مغادرة «$name»؟', ok: 'مغادرة', danger: true)) return;
              try {
                await _repo.leave(_id);
                if (!mounted) return;
                context.read<ChatHub>().refresh();
                Navigator.of(context).popUntil((r) => r.isFirst);
              } catch (e) {
                if (mounted) showSnack(context, friendlyError(e), error: true);
              }
            },
          ),
          if (_isOwner)
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: const Text('حذف المجموعة', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                if (!await confirmDialog(context, 'حذف المجموعة', 'سيتم حذف المجموعة وجميع رسائلها نهائيًا.', ok: 'حذف', danger: true)) {
                  return;
                }
                try {
                  await _repo.deleteGroup(_id);
                  if (!mounted) return;
                  context.read<ChatHub>().refresh();
                  Navigator.of(context).popUntil((r) => r.isFirst);
                } catch (e) {
                  if (mounted) showSnack(context, friendlyError(e), error: true);
                }
              },
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
