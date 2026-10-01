import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/social_repositories.dart';
import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../profile/profile_screens.dart';

/// لوحة تحكم المدير داخل التطبيق.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.watch<SessionProvider>().isAdmin) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.lock, title: 'للمدير فقط'));
    }
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة التحكم'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.dashboard_rounded), text: 'الرئيسية'),
              Tab(icon: Icon(Icons.people_alt_rounded), text: 'المستخدمون'),
              Tab(icon: Icon(Icons.dynamic_feed_rounded), text: 'المنشورات'),
              Tab(icon: Icon(Icons.flag_rounded), text: 'البلاغات'),
              Tab(icon: Icon(Icons.groups_rounded), text: 'المجموعات'),
              Tab(icon: Icon(Icons.campaign_rounded), text: 'إشعار عام'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_Overview(), _Users(), _Posts(), _Reports(), _Groups(), _Broadcast()],
        ),
      ),
    );
  }
}

final _admin = AdminRepository();

class _Overview extends StatefulWidget {
  const _Overview();
  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  Map<String, dynamic>? _stats;
  late final TextEditingController _msg;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _msg = TextEditingController(text: context.read<AppStatusProvider>().message);
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await _admin.stats();
      if (mounted) setState(() => _stats = s);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _setApp(bool enabled) async {
    if (!enabled &&
        !await confirmDialog(context, 'إيقاف التطبيق',
            'سيتوقف التطبيق فورًا عند جميع المستخدمين (عدا المدراء) وستظهر لهم رسالة الصيانة.',
            ok: 'إيقاف', danger: true)) {
      return;
    }
    setState(() => _saving = true);
    try {
      await _admin.setApp(enabled, _msg.text);
      if (mounted) {
        await context.read<AppStatusProvider>().load();
        if (mounted) showSnack(context, enabled ? 'تم تشغيل التطبيق ✅' : 'تم إيقاف التطبيق ⛔');
      }
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AppStatusProvider>();
    final s = _stats;
    final on = status.enabled;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: (on ? AppColors.green : AppColors.danger).withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(on ? Icons.power_settings_new : Icons.power_off_rounded,
                          size: 36, color: on ? AppColors.green : AppColors.danger),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('حالة التطبيق', style: TextStyle(fontSize: 13)),
                            Text(on ? 'يعمل الآن' : 'متوقف (وضع الصيانة)',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      _saving
                          ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2))
                          : Transform.scale(
                              scale: 1.25,
                              child: Switch(value: on, onChanged: _setApp, activeTrackColor: AppColors.green),
                            ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _msg,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'رسالة الصيانة التي تظهر للمستخدمين'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _setApp(on),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('حفظ الرسالة'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (s == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: [
                _stat('المستخدمون', s['users'], Icons.people_alt_rounded, AppColors.cyan),
                _stat('نشطون الآن', s['active_5m'], Icons.bolt_rounded, AppColors.green),
                _stat('نشطون 24 ساعة', s['active_24h'], Icons.schedule, AppColors.violet),
                _stat('محظورون', s['banned'], Icons.gpp_bad_rounded, AppColors.danger),
                _stat('موثّقون', s['verified'], Icons.verified_rounded, const Color(0xFF1D9BF0)),
                _stat('المنشورات', s['posts'], Icons.dynamic_feed_rounded, AppColors.violet),
                _stat('منشورات اليوم', s['posts_24h'], Icons.post_add_rounded, AppColors.cyan),
                _stat('الرسائل', s['messages'], Icons.chat_rounded, AppColors.pink),
                _stat('رسائل اليوم', s['messages_24h'], Icons.today_rounded, Colors.orange),
                _stat('المجموعات', s['groups'], Icons.groups_rounded, AppColors.cyan),
                _stat('بلاغات مفتوحة', s['open_reports'], Icons.flag_rounded, AppColors.danger),
              ],
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, dynamic value, IconData icon, Color color) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color),
              Text('${value ?? 0}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              Text(label, style: const TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      );
}

class _Users extends StatefulWidget {
  const _Users();
  @override
  State<_Users> createState() => _UsersState();
}

class _UsersState extends State<_Users> {
  List<Profile> _users = [];
  bool _loading = true;
  Timer? _debounce;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await _admin.users(_q);
      if (mounted) setState(() => _users = u);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _menu(Profile p) {
    if (p.id == myId) return;
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
                Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: p.id)));
              },
            ),
            if (!p.isOwner && !p.isBanned)
              ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                title: Text('إرسال إنذار (${p.warnings + 1} من 3)'),
                subtitle: const Text('الإنذار الرابع = حظر نهائي'),
                onTap: () async {
                  Navigator.pop(c);
                  final reason = await promptText(context, 'سبب الإنذار');
                  if (reason == null) return;
                  await _run(() => _admin.warn(p.id, reason));
                },
              ),
            if (p.warnings > 0)
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('مسح الإنذارات'),
                onTap: () async {
                  Navigator.pop(c);
                  await _run(() => _admin.clearWarnings(p.id));
                },
              ),
            ListTile(
              leading: const Icon(Icons.verified_rounded, color: Color(0xFF1D9BF0)),
              title: Text(p.isVerified ? 'إلغاء التوثيق' : 'توثيق الحساب ✔️'),
              enabled: !p.isOwner,
              onTap: () async {
                Navigator.pop(c);
                await _run(() => _admin.setVerified(p.id, !p.isVerified));
              },
            ),
            if (!p.isOwner)
            ListTile(
              leading: Icon(p.isBanned ? Icons.lock_open : Icons.gpp_bad, color: p.isBanned ? Colors.green : Colors.redAccent),
              title: Text(p.isBanned ? 'إلغاء الحظر' : 'حظر الحساب'),
              onTap: () async {
                Navigator.pop(c);
                await _run(() => _admin.setBan(p.id, !p.isBanned));
              },
            ),
            if (!p.isOwner)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(p.isAdmin ? 'إزالة صلاحية المدير' : 'منح صلاحية المدير'),
              onTap: () async {
                Navigator.pop(c);
                if (await confirmDialog(context, 'تأكيد', p.isAdmin ? 'إزالة صلاحية المدير؟' : 'منح ${p.displayName} صلاحية المدير الكاملة؟')) {
                  await _run(() => _admin.setAdmin(p.id, !p.isAdmin));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run(Future<void> Function() f) async {
    try {
      await f();
      if (mounted) showSnack(context, 'تم');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو username'),
            onChanged: (v) {
              _q = v;
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _load);
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (_, i) {
                      final p = _users[i];
                      return ListTile(
                        leading: Avatar(url: p.avatarUrl, name: p.displayName),
                        title: Row(children: [
                          Flexible(child: NameWithBadge(p.displayName, verified: p.verified)),
                          const SizedBox(width: 6),
                          LevelChip(p.level),
                          if (p.isOwner) const Padding(padding: EdgeInsets.only(right: 6), child: Text('👑')),
                          if (p.isAdmin && !p.isOwner) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.shield, size: 14, color: AppColors.cyan)),
                        ]),
                        subtitle: Text('@${p.username} · ${p.xp} نقطة${p.warnings > 0 ? ' · ⚠️ ${p.warnings}' : ''} · ${Fmt.lastSeen(p.lastSeen)}'),
                        trailing: p.isBanned
                            ? const Chip(label: Text('محظور'), visualDensity: VisualDensity.compact)
                            : null,
                        onTap: () => _menu(p),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _Reports extends StatefulWidget {
  const _Reports();
  @override
  State<_Reports> createState() => _ReportsState();
}

class _ReportsState extends State<_Reports> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _admin.reports();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    try {
      await f();
      if (mounted) showSnack(context, ok);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const EmptyState(icon: Icons.verified_user_rounded, title: 'لا توجد بلاغات');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final r = _items[i];
          final open = r['status'] == 'open';
          final msgId = r['message_id'] as String?;
          final postId = r['post_id'] as String?;
          final reportedId = r['reported_user_id'] as String?;
          final warnings = ((r['reported_warnings'] ?? 0) as num).toInt();
          final banned = (r['reported_banned'] ?? false) as bool;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag, color: open ? AppColors.danger : Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('@${r['reporter_username'] ?? '?'} ← @${r['reported_username'] ?? '-'}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      Chip(label: Text(open ? 'مفتوح' : 'تمت المعالجة'), visualDensity: VisualDensity.compact),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('السبب: ${r['reason']}'),
                  if (reportedId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(banned ? '⛔ الحساب محظور' : '⚠️ إنذارات الحساب: $warnings من 3',
                          style: TextStyle(color: banned ? AppColors.danger : Colors.orange, fontWeight: FontWeight.w700)),
                    ),
                  if (postId != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المنشور: ${(r['post_content'] ?? '').toString().isEmpty ? '(صورة)' : r['post_content']}'),
                          if (r['post_image'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(r['post_image'] as String, height: 140, fit: BoxFit.cover),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (msgId != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('الرسالة: ${r['message_content'] ?? '(${r['message_type'] ?? 'محذوفة'})'}'),
                    ),
                  if (open)
                    Wrap(
                      spacing: 8,
                      children: [
                        if (msgId != null || postId != null)
                          TextButton.icon(
                            onPressed: () => _run(() => _admin.resolveReport(r['id'] as String, deleteMessage: true), 'تم حذف المحتوى'),
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            label: const Text('حذف المحتوى'),
                          ),
                        if (reportedId != null && !banned)
                          TextButton.icon(
                            onPressed: () async {
                              final reason = await promptText(context, 'سبب الإنذار', initial: r['reason'] as String? ?? '');
                              if (reason == null) return;
                              await _run(() async {
                                final n = await _admin.warn(reportedId, reason);
                                await _admin.resolveReport(r['id'] as String, deleteMessage: true);
                                if (n >= 4 && mounted) showSnack(context, 'وصل الإنذار الرابع: تم حظر الحساب نهائيًا');
                              }, 'تم إرسال الإنذار وحذف المحتوى');
                            },
                            icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                            label: Text('إنذار (${warnings + 1})'),
                          ),
                        if (reportedId != null && !banned)
                          TextButton.icon(
                            onPressed: () => _run(() async {
                              await _admin.setBan(reportedId, true);
                              await _admin.resolveReport(r['id'] as String);
                            }, 'تم حظر المستخدم'),
                            icon: const Icon(Icons.gpp_bad, color: Colors.redAccent),
                            label: const Text('حظر نهائي'),
                          ),
                        TextButton.icon(
                          onPressed: () => _run(() => _admin.resolveReport(r['id'] as String), 'تم إغلاق البلاغ'),
                          icon: const Icon(Icons.check),
                          label: const Text('تجاهل'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Groups extends StatefulWidget {
  const _Groups();
  @override
  State<_Groups> createState() => _GroupsState();
}

class _GroupsState extends State<_Groups> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _admin.groups();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const EmptyState(icon: Icons.groups_outlined, title: 'لا توجد مجموعات');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final g = _items[i];
          final name = (g['name'] ?? '') as String;
          return ListTile(
            leading: Avatar(url: g['avatar_url'] as String?, name: name, group: true),
            title: Text(name),
            subtitle: Text('${g['member_count']} عضو · ${g['message_count']} رسالة · ${g['is_public'] == true ? 'عامة' : 'خاصة'}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () async {
                if (!await confirmDialog(context, 'حذف المجموعة', 'حذف «$name» نهائيًا مع كل رسائلها؟', ok: 'حذف', danger: true)) return;
                try {
                  await _admin.deleteGroup(g['id'] as String);
                  await _load();
                } catch (e) {
                  if (context.mounted) showSnack(context, friendlyError(e), error: true);
                }
              },
            ),
          );
        },
      ),
    );
  }
}

class _Broadcast extends StatefulWidget {
  const _Broadcast();
  @override
  State<_Broadcast> createState() => _BroadcastState();
}

class _BroadcastState extends State<_Broadcast> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;

  Future<void> _send() async {
    if (_title.text.trim().isEmpty) {
      showSnack(context, 'أدخل عنوان الإشعار', error: true);
      return;
    }
    if (!await confirmDialog(context, 'إرسال إشعار عام', 'سيصل الإشعار إلى جميع المستخدمين.', ok: 'إرسال')) return;
    setState(() => _busy = true);
    try {
      final n = await _admin.broadcast(_title.text.trim(), _body.text.trim());
      if (mounted) {
        showSnack(context, 'تم الإرسال إلى $n مستخدم');
        _title.clear();
        _body.clear();
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('أرسل إشعارًا يظهر لكل المستخدمين في صفحة الإشعارات وعلى أجهزتهم.'),
        const SizedBox(height: 16),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'العنوان')),
        const SizedBox(height: 12),
        TextField(controller: _body, maxLines: 5, decoration: const InputDecoration(labelText: 'النص')),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy ? null : _send,
          icon: const Icon(Icons.send_rounded),
          label: const Text('إرسال للجميع'),
        ),
      ],
    );
  }
}


class _Posts extends StatefulWidget {
  const _Posts();
  @override
  State<_Posts> createState() => _PostsState();
}

class _PostsState extends State<_Posts> {
  List<Post> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _admin.posts();
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return const EmptyState(icon: Icons.dynamic_feed_outlined, title: 'لا توجد منشورات');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = _items[i];
          return ListTile(
            leading: Avatar(url: p.author?.avatarUrl, name: p.author?.displayName ?? ''),
            title: NameWithBadge(p.author?.displayName ?? '', verified: p.author?.verified ?? false),
            subtitle: Text(
              '${p.content.isEmpty ? '📷 صورة' : p.content}\n❤ ${p.likeCount} · 💬 ${p.commentCount} · ${Fmt.chatListTime(p.createdAt)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () async {
                if (!await confirmDialog(context, 'حذف المنشور', 'حذف هذا المنشور؟', ok: 'حذف', danger: true)) return;
                try {
                  await _admin.deletePost(p.id);
                  await _load();
                } catch (e) {
                  if (context.mounted) showSnack(context, friendlyError(e), error: true);
                }
              },
            ),
          );
        },
      ),
    );
  }
}
