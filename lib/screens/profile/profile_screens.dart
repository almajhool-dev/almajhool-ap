import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/social_repositories.dart';
import '../../repositories/user_repositories.dart';
import '../../services/core_services.dart';
import '../../services/media_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../contacts/contacts_tab.dart';
import '../home/home_shell.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  const ProfileScreen({super.key, required this.userId});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profiles = ProfileRepository();
  final _contacts = ContactRepository();
  Profile? _p;
  String _relation = 'none';
  String? _requestId;
  bool _blocked = false;
  List<GroupSearchResult> _common = [];
  bool _loading = true;

  bool get _isMe => widget.userId == myId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _profiles.get(widget.userId);
      if (!_isMe) {
        final rel = await _contacts.statusWith(widget.userId);
        final blocks = await _profiles.myBlocks();
        final common = await _profiles.commonGroups(widget.userId);
        _relation = rel.$1;
        _requestId = rel.$2;
        _blocked = blocks.contains(widget.userId);
        _common = common;
      }
      if (mounted) {
        setState(() {
          _p = p;
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

  Future<void> _act(Future<void> Function() f, [String? ok]) async {
    try {
      await f();
      if (ok != null && mounted) showSnack(context, ok);
      await _load();
      if (mounted) context.read<ChatHub>().refreshSoon();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Widget _relationButton() {
    switch (_relation) {
      case 'accepted':
        return OutlinedButton.icon(
          onPressed: () async {
            if (await confirmDialog(context, 'حذف جهة الاتصال', 'هل تريد إزالة ${_p!.displayName} من جهات اتصالك؟', danger: true)) {
              await _act(() => _contacts.remove(widget.userId), 'تمت الإزالة');
            }
          },
          icon: const Icon(Icons.how_to_reg),
          label: const Text('جهة اتصال'),
        );
      case 'pending_out':
        return OutlinedButton.icon(
          onPressed: () => _act(() => _contacts.remove(widget.userId), 'تم إلغاء الطلب'),
          icon: const Icon(Icons.schedule),
          label: const Text('تم إرسال الطلب'),
        );
      case 'pending_in':
        return FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => _act(() => _contacts.respond(_requestId!, true), 'تم القبول'),
          icon: const Icon(Icons.check),
          label: const Text('قبول الطلب'),
        );
      default:
        return FilledButton.tonalIcon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _blocked ? null : () => _act(() => _contacts.send(widget.userId), 'تم إرسال طلب التواصل'),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('إضافة'),
        );
    }
  }

  Future<void> _report() async {
    final reason = await promptText(context, 'سبب الإبلاغ', maxLines: 3, ok: 'إرسال');
    if (reason == null) return;
    await _act(() => _profiles.report(reason: reason, userId: widget.userId), 'تم إرسال البلاغ');
  }

  @override
  Widget build(BuildContext context) {
    final hub = context.watch<ChatHub>();
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final p = _p;
    if (p == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.person_off, title: 'المستخدم غير موجود'));
    }
    final online = hub.isOnline(p.id);
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (_isMe)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()))
                  .then((_) => _load()),
            )
          else
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'block') {
                  if (_blocked) {
                    await _act(() => _profiles.unblock(p.id), 'تم إلغاء الحظر');
                  } else if (await confirmDialog(context, 'حظر ${p.displayName}', 'لن يتمكن من مراسلتك أو إضافتك.', ok: 'حظر', danger: true)) {
                    await _act(() => _profiles.block(p.id), 'تم الحظر');
                  }
                } else if (v == 'report') {
                  await _report();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'block', child: Text(_blocked ? 'إلغاء الحظر' : 'حظر')),
                const PopupMenuItem(value: 'report', child: Text('إبلاغ')),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            Center(child: Avatar(url: p.avatarUrl, name: p.displayName, size: 116, online: online)),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(p.displayName,
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                ),
                if (p.isAdmin) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified_rounded, color: Color(0xFF00E5FF), size: 22),
                ],
              ],
            ),
            Text('@${p.username}', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            Text(
              p.isBanned ? 'حساب موقوف' : (online ? 'متصل الآن' : Fmt.lastSeen(p.lastSeen)),
              textAlign: TextAlign.center,
              style: TextStyle(color: p.isBanned ? Colors.redAccent : (online ? Colors.green : Theme.of(context).hintColor)),
            ),
            if (p.bio.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(p.bio, textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (!_isMe)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: _blocked ? null : () => startDirectChat(context, p.id),
                      icon: const Icon(Icons.chat_bubble_rounded),
                      label: const Text('مراسلة'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _relationButton()),
                ],
              ),
            if (_blocked)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('لقد حظرت هذا المستخدم', textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent)),
              ),
            if (_common.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('المجموعات المشتركة (${_common.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
              for (final g in _common)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(url: g.avatarUrl, name: g.name, group: true),
                  title: Text(g.name),
                  onTap: () => openChat(context, g.id),
                ),
            ],
            if (p.createdAt != null) ...[
              const SizedBox(height: 24),
              Text('انضم ${Fmt.chatListTime(p.createdAt!)}',
                  textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _repo = ProfileRepository();
  late final TextEditingController _name;
  late final TextEditingController _username;
  late final TextEditingController _bio;
  File? _avatar;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<SessionProvider>().profile;
    _name = TextEditingController(text: p?.displayName ?? '');
    _username = TextEditingController(text: p?.username ?? '');
    _bio = TextEditingController(text: p?.bio ?? '');
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final session = context.read<SessionProvider>();
    setState(() => _busy = true);
    try {
      final current = session.profile;
      final newUsername = _username.text.trim().toLowerCase();
      if (newUsername != current?.username && !await AuthRepository().usernameAvailable(newUsername)) {
        throw Exception('اسم المستخدم محجوز');
      }
      String? avatarUrl;
      if (_avatar != null) avatarUrl = await MediaService.uploadAvatar(_avatar!);
      await _repo.update(
        displayName: _name.text,
        username: newUsername,
        bio: _bio.text,
        avatarUrl: avatarUrl,
      );
      await session.refresh();
      if (mounted) {
        showSnack(context, 'تم حفظ التغييرات');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<SessionProvider>().profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل الملف الشخصي'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('حفظ', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: GestureDetector(
                onTap: () async {
                  final f = await MediaService.pickAvatar();
                  if (f != null) setState(() => _avatar = f);
                },
                child: Stack(
                  children: [
                    _avatar != null
                        ? CircleAvatar(radius: 56, backgroundImage: FileImage(_avatar!))
                        : Avatar(url: p?.avatarUrl, name: p?.displayName ?? '', size: 112),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Icon(Icons.camera_alt, size: 18, color: Theme.of(context).colorScheme.onPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم العرض'),
              validator: Validators.displayName,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _username,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixText: '@'),
              validator: Validators.username,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _bio,
              maxLines: 4,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'نبذة عنك'),
            ),
          ],
        ),
      ),
    );
  }
}
