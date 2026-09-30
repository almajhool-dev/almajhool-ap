import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/user_repositories.dart';
import '../../services/local_notifications.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../admin/admin_screen.dart';
import '../profile/profile_screens.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _localNotifs = LocalNotifications.enabled;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final theme = context.watch<ThemeProvider>();
    final p = session.profile;
    return SafeArea(
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('الإعدادات', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          if (p != null)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                leading: Avatar(url: p.avatarUrl, name: p.displayName, size: 58),
                title: Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                subtitle: Text('@${p.username}${p.isAdmin ? ' · مدير' : ''}'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: p.id))),
              ),
            ),
          if (session.isAdmin)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings_rounded, size: 30),
                title: const Text('لوحة التحكم', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('تشغيل/إيقاف التطبيق، المستخدمون، البلاغات'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
              ),
            ),
          _section('الحساب'),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('تعديل الملف الشخصي'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: const Text('تغيير كلمة المرور'),
            onTap: _changePassword,
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('المستخدمون المحظورون'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedUsersScreen())),
          ),
          _section('المظهر'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('داكن')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('فاتح')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android), label: Text('النظام')),
              ],
              selected: {theme.mode},
              onSelectionChanged: (s) => theme.set(s.first),
            ),
          ),
          _section('الإشعارات'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('إشعارات الجهاز'),
            subtitle: const Text('تنبيه بالرسائل الجديدة على هذا الهاتف'),
            value: _localNotifs,
            onChanged: (v) async {
              await LocalNotifications.setEnabled(v);
              setState(() => _localNotifs = v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.campaign_outlined),
            title: const Text('إشعارات الحساب'),
            subtitle: const Text('طلبات التواصل، الإضافة للمجموعات، الإشارات'),
            value: p?.notificationsEnabled ?? true,
            onChanged: (v) async {
              try {
                await ProfileRepository().update(notifications: v);
                await session.refresh();
              } catch (e) {
                if (context.mounted) showSnack(context, friendlyError(e), error: true);
              }
            },
          ),
          _section('حول'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('عن التطبيق'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: '1.0.0',
              applicationIcon: const BrandLogo(size: 48, showName: false),
              children: const [Text('تطبيق تواصل ومراسلة آمن وسريع.\n\nصُنع بواسطة المبرمج المجهول')],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('تسجيل الخروج', style: TextStyle(color: Colors.redAccent)),
            onTap: () async {
              if (await confirmDialog(context, 'تسجيل الخروج', 'هل تريد تسجيل الخروج؟', ok: 'خروج', danger: true)) {
                await AuthRepository().signOut();
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('صُنع بواسطة المبرمج المجهول', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
      );

  Future<void> _changePassword() async {
    final pw = await promptText(context, 'كلمة المرور الجديدة', hint: '8 أحرف على الأقل');
    if (pw == null) return;
    final err = Validators.password(pw);
    if (err != null) {
      if (mounted) showSnack(context, err, error: true);
      return;
    }
    try {
      await AuthRepository().changePassword(pw);
      if (mounted) showSnack(context, 'تم تغيير كلمة المرور');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }
}

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});
  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final _repo = ProfileRepository();
  List<Profile> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await _repo.blockedProfiles();
      if (mounted) setState(() => _list = l);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المحظورون')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? const EmptyState(icon: Icons.verified_user_outlined, title: 'لا يوجد مستخدمون محظورون')
              : ListView(
                  children: [
                    for (final p in _list)
                      ListTile(
                        leading: Avatar(url: p.avatarUrl, name: p.displayName),
                        title: Text(p.displayName),
                        subtitle: Text('@${p.username}'),
                        trailing: TextButton(
                          onPressed: () async {
                            await _repo.unblock(p.id);
                            _load();
                          },
                          child: const Text('إلغاء الحظر'),
                        ),
                      ),
                  ],
                ),
    );
  }
}
