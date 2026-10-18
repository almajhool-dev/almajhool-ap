import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../feed/community.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/user_repositories.dart';
import '../../services/background_service.dart';
import '../../services/local_notifications.dart';
import '../../services/sound_service.dart';
import '../../services/push_service.dart';
import '../../services/update_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../../widgets/fx.dart';
import '../../services/fx_settings.dart';
import 'themes_screen.dart';
import '../admin/admin_screen.dart';
import '../../services/couple_service.dart';
import '../../services/core_services.dart';
import '../../services/privacy_service.dart';
import '../couple/couple_screens.dart';
import 'suggestions_screen.dart';
import '../wallet/wallet_screens.dart';
import '../../repositories/post_repository.dart';
import '../contacts/contacts_tab.dart';
import '../profile/profile_screens.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});
  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _localNotifs = LocalNotifications.enabled;

  @override
  void initState() {
    super.initState();
    PrivacyService.load();
  }

  Future<void> _loginOptions() async {
    final st = context.read<AppStatusProvider>();
    final g = TextEditingController(text: st.googleClientId ?? '');
    var phone = st.phoneLogin;
    final sid = TextEditingController(), tok = TextEditingController(), svc = TextEditingController();
    final gu = TextEditingController(), gp = TextEditingController(), tg = TextEditingController();
    Map<String, dynamic> sms = const {};
    try {
      sms = ((await supa.rpc('sms_status')) as Map).cast<String, dynamic>();
    } catch (_) {}
    if (!mounted) return;
    final gate = sms['gate'] == true;
    final tgBot = st.tgBot;
    final linked = tgBot != null || gate || (sms['sid'] == true && sms['token'] == true && sms['service'] == true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('خيارات تسجيل الدخول'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Google: الصق «Web client ID» من Google Cloud (نوعه Web مو Android). '
                  'اتركه فاضي حتى تخفي زر Google.', style: TextStyle(fontSize: 12.5)),
              TextField(
                controller: g,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(hintText: '1234-abc.apps.googleusercontent.com'),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('الدخول برقم الهاتف'),
                subtitle: Text(linked
                    ? 'خدمة الرسائل مربوطة ✅ (رسائل آخر 24 ساعة: ${sms['sent_today'] ?? 0})'
                    : 'اربط بوت تيليكرام بالخانة الجوه أول، بعدين فعّله'),
                value: phone,
                onChanged: (v) => set(() => phone = v),
              ),
              const SizedBox(height: 6),
              Text(tgBot != null
                  ? 'التحقق المجاني عبر تيليكرام شغال ✅ بالبوت @$tgBot (الصق توكن جديد بس إذا تريد تغيّره):'
                  : 'التحقق المجاني عبر تيليكرام (موصى به): الصق توكن البوت من @BotFather',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              TextField(
                controller: tg,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: 'Bot token', hintText: tgBot != null ? 'محفوظ ✅' : '123456789:AAH...'),
              ),
              const SizedBox(height: 14),
              Text(gate
                  ? 'هاتف الرسائل المجاني مربوط ✅ (اتركها فاضية إذا ما تريد تغيّرها):'
                  : 'هاتف الرسائل المجاني (من تطبيق SMS Gateway ← Cloud server):',
                  style: const TextStyle(fontSize: 12.5)),
              TextField(
                controller: gu,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: 'Username', hintText: gate ? 'محفوظ ✅' : ''),
              ),
              TextField(
                controller: gp,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: 'Password', hintText: gate ? 'محفوظ ✅' : ''),
              ),
              const SizedBox(height: 10),
              Text(linked ? 'أو مفاتيح Twilio المدفوعة (اختياري):' : 'أو مفاتيح Twilio المدفوعة (اختياري):',
                  style: const TextStyle(fontSize: 12.5)),
              TextField(
                controller: sid,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: 'Account SID', hintText: linked ? 'محفوظ ✅' : 'AC...'),
              ),
              TextField(
                controller: tok,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: 'Auth Token', hintText: linked ? 'محفوظ ✅' : '32 حرف'),
              ),
              TextField(
                controller: svc,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: 'Verify Service SID', hintText: linked ? 'محفوظ ✅' : 'VA...'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      if (tg.text.trim().isNotEmpty) {
        final r = ((await supa.rpc('set_tg_login', params: {'p_token': tg.text.trim()})) as Map);
        if (mounted) showSnack(context, 'انربط البوت @${r['bot']} ✅');
      }
      if (gu.text.trim().isNotEmpty || gp.text.trim().isNotEmpty) {
        await supa.rpc('set_sms_gate', params: {'p_user': gu.text.trim(), 'p_pass': gp.text.trim()});
      }
      if (sid.text.trim().isNotEmpty || tok.text.trim().isNotEmpty || svc.text.trim().isNotEmpty) {
        await supa.rpc('set_sms_provider',
            params: {'p_sid': sid.text.trim(), 'p_token': tok.text.trim(), 'p_service': svc.text.trim()});
      }
      await supa.rpc('set_login_options', params: {'p_google_client': g.text.trim(), 'p_phone': phone});
      await st.load();
      if (mounted) showSnack(context, 'تم الحفظ ✅');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final theme = context.watch<ThemeProvider>();
    final p = session.profile;
    return SafeArea(
      child: ListView(
        children: fxList([
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
                title: NameWithBadge(p.displayName, verified: p.verified, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                subtitle: Text('@${p.username} · المستوى ${p.level}${p.isOwner ? ' · المالك' : p.isAdmin ? ' · مدير' : ''}'),
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
            leading: const Icon(Icons.key_rounded, color: Colors.amber),
            title: const Text('رمز الاسترداد'),
            subtitle: const Text('يُرجع حسابك إذا نسيت كلمة المرور — بدون إيميل'),
            onTap: _recoveryCode,
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('المستخدمون المحظورون'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedUsersScreen())),
          ),
          const PrivateAccountTiles(),
          ValueListenableBuilder<bool>(
            valueListenable: PrivacyService.storyGhost,
            builder: (context, ghost, _) => SwitchListTile(
              secondary: Icon(ghost ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              title: const Text('مشاهدة الستوري بشكل مخفي 👻'),
              subtitle: const Text('صاحب الستوري ما يشوف اسمك بقائمة المشاهدين'),
              value: ghost,
              onChanged: (v) async {
                try {
                  await PrivacyService.setStoryGhost(v);
                } catch (e) {
                  if (context.mounted) showSnack(context, friendlyError(e), error: true);
                }
              },
            ),
          ),
          ListTile(
            leading: const CoinIcon(size: 26),
            title: const Text('المحفظة والأرباح 🪙'),
            subtitle: const Text('شحن العملات، الهدايا، وأرباحك من البث'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
          ),
          if (p?.isOwner ?? false)
            ListTile(
              leading: const Icon(Icons.account_balance_rounded, color: Colors.green),
              title: const Text('اللوحة المالية 💰'),
              subtitle: const Text('حصتك، الشحن، الهدايا، طلبات السحب، وربط زين كاش'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinanceScreen())),
            ),
          if (p?.isOwner ?? false)
            ListTile(
              leading: const Icon(Icons.login_rounded, color: Colors.blue),
              title: const Text('خيارات تسجيل الدخول'),
              subtitle: const Text('تفعيل الدخول بحساب Google ورقم الهاتف'),
              trailing: const Icon(Icons.chevron_left),
              onTap: _loginOptions,
            ),
          ListTile(
            leading: const Icon(Icons.lightbulb_rounded, color: Colors.amber),
            title: Text((p?.isOwner ?? false) ? 'اقتراحات المستخدمين 💡' : 'اقترح ميزة للتطبيق 💡'),
            subtitle: Text((p?.isOwner ?? false) ? 'الميزات اللي يريدها المستخدمين' : 'اكتب الميزة اللي تريدها وتوصل لمالك التطبيق'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuggestionsScreen())),
          ),
          _section('مساحة الشريك 💞'),
          ValueListenableBuilder<bool>(
            valueListenable: CoupleService.enabled,
            builder: (context, on, _) => Column(children: [
              SwitchListTile(
                secondary: const Icon(Icons.favorite_rounded, color: Color(0xFFFF4FD8)),
                title: const Text('تفعيل مساحة الشريك'),
                subtitle: Text(on
                    ? 'اربط حسابك بشريكك: رحلتكم، سهرة يوتيوب سوا، ذكرياتكم وسؤال اليوم'
                    : 'مطفية — التطبيق يبقى بنسخته الأصلية'),
                value: on,
                onChanged: (v) => CoupleService.setEnabled(v),
              ),
              if (on) const CouplePairCard(),
            ]),
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
          ListenableBuilder(
            listenable: FxSettings.instance,
            builder: (context, _) => SwitchListTile(
              secondary: const Icon(Icons.auto_awesome_rounded),
              title: const Text('خلفيات متحركة ✨'),
              subtitle: const Text('طفّيها إذا تريد خلفية ثابتة وتوفير بطارية'),
              value: FxSettings.instance.enabled,
              onChanged: FxSettings.instance.setEnabled,
            ),
          ),
          ListenableBuilder(
            listenable: FxSettings.instance,
            builder: (context, _) => ListTile(
              leading: const Icon(Icons.palette_rounded),
              title: const Text('السمات المتحركة 🎨'),
              subtitle: Text('الحالية: ${FxSettings.instance.current.name}'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ThemesScreen())),
            ),
          ),
          _section('الأصوات'),
          ListTile(
            leading: const Icon(Icons.music_note_rounded),
            title: const Text('نغمة الرنين'),
            subtitle: Text(SoundService.ringtoneName),
            trailing: const Icon(Icons.chevron_left),
            onTap: _pickRingtone,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.ring_volume_rounded),
            title: const Text('أصوات المكالمات'),
            subtitle: const Text('نغمة الرنين ونغمة الانتظار عند الاتصال'),
            value: SoundService.callSounds,
            onChanged: (v) async {
              await SoundService.setCallSounds(v);
              setState(() {});
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_up_rounded),
            title: const Text('أصوات الرسائل'),
            subtitle: const Text('صوت عند إرسال واستلام الرسائل والبصمات والصور'),
            value: SoundService.messageSounds,
            onChanged: (v) async {
              await SoundService.setMessageSounds(v);
              setState(() {});
              if (v) SoundService.messageReceived();
            },
          ),
          _section('الإشعارات'),
          ListTile(
            leading: const Icon(Icons.health_and_safety_outlined, color: Colors.green),
            title: const Text('فحص الإشعارات والمكالمات'),
            subtitle: const Text('تأكد أن الرنين والإشعارات تصلك والتطبيق مغلق'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCheckScreen())),
          ),
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
          if (!(p?.isOwner ?? false))
            ListTile(
              leading: const Icon(Icons.support_agent_rounded),
              title: const Text('مراسلة الإدارة'),
              subtitle: const Text('اقتراح، مشكلة، أو طلب توثيق'),
              onTap: () async {
                try {
                  final owner = await PostRepository().ownerId();
                  if (owner == null) throw Exception('لا يوجد مالك للتطبيق بعد');
                  if (context.mounted) await startDirectChat(context, owner);
                } catch (e) {
                  if (context.mounted) showSnack(context, friendlyError(e), error: true);
                }
              },
            ),
          _section('حول'),
          ListTile(
            leading: const Icon(Icons.system_update_rounded, color: Colors.blue),
            title: const Text('التحقق من التحديثات'),
            subtitle: Text('الإصدار الحالي ${UpdateService.currentVersion}'),
            onTap: () => UpdateService.manualCheck(context),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('عن التطبيق'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: AppConfig.appName,
              applicationVersion: UpdateService.currentVersion,
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
        ]),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
      );

  Future<void> _pickRingtone() async {
    var selected = SoundService.ringtoneId;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('اختر نغمة الرنين'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final t in SoundService.ringtones)
                RadioListTile<String>(
                  value: t.id,
                  groupValue: selected,
                  title: Text(t.name),
                  secondary: const Icon(Icons.play_circle_outline_rounded),
                  onChanged: (v) {
                    set(() => selected = v!);
                    SoundService.preview(v!);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: () => Navigator.pop(c, selected),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    await SoundService.stopPreview();
    if (r == null) return;
    await SoundService.setRingtone(r);
    if (mounted) {
      setState(() {});
      showSnack(context, 'تم اختيار نغمة «${SoundService.ringtoneName}»');
    }
  }

  Future<void> _recoveryCode() async {
    final repo = AuthRepository();
    bool has = false;
    try {
      has = await repo.hasRecoveryCode();
    } catch (_) {}
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      'رمز الاسترداد',
      has
          ? 'لديك رمز محفوظ مسبقًا. إنشاء رمز جديد يُلغي القديم. هل تريد المتابعة؟'
          : 'سننشئ لك رمزًا سريًا. احفظه في مكان آمن (صورة أو ورقة). إذا نسيت كلمة المرور تستطيع استعادة حسابك به بدون إيميل.',
      ok: 'إنشاء رمز',
    );
    if (!ok) return;
    try {
      final code = await repo.createRecoveryCode();
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('احفظ هذا الرمز 🔑'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(code,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 2)),
              const SizedBox(height: 12),
              const Text('لن يظهر مرة أخرى. يُستخدم مرة واحدة فقط، وبعدها أنشئ رمزًا جديدًا.',
                  textAlign: TextAlign.center),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                showSnack(c, 'تم النسخ');
              },
              child: const Text('نسخ'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
              onPressed: () => Navigator.pop(c),
              child: const Text('حفظته'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

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


/// شاشة فحص: هل خدمة الخلفية شغالة؟ هل الصلاحيات مفعّلة؟ مع زر إشعار تجريبي.
class NotificationCheckScreen extends StatefulWidget {
  const NotificationCheckScreen({super.key});
  @override
  State<NotificationCheckScreen> createState() => _NotificationCheckScreenState();
}

class _NotificationCheckScreenState extends State<NotificationCheckScreen> {
  Map<String, bool?> _s = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await BackgroundBridge.status();
    if (mounted) {
      setState(() {
        _s = s;
        _loading = false;
      });
    }
  }

  Widget _row(String title, bool? ok, {String? fix, VoidCallback? onFix}) {
    return ListTile(
      leading: Icon(
        ok == true ? Icons.check_circle_rounded : ok == false ? Icons.cancel_rounded : Icons.help_outline_rounded,
        color: ok == true ? Colors.green : ok == false ? Colors.redAccent : Colors.grey,
      ),
      title: Text(title),
      trailing: ok == false && onFix != null
          ? FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(70, 36)),
              onPressed: () async {
                onFix();
                await Future<void>.delayed(const Duration(seconds: 2));
                _load();
              },
              child: Text(fix ?? 'إصلاح'),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final err = BackgroundBridge.lastError;
    final poll = BackgroundBridge.lastPoll;
    return Scaffold(
      appBar: AppBar(
        title: const Text('فحص الإشعارات'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _row('إشعارات Google (تعمل والتطبيق مغلق)', _s['push'], fix: 'إعادة', onFix: () async {
                  showSnack(context, 'جاري الربط مع Google… انتظر لحد دقيقة');
                  await PushService.retryNow();
                  if (mounted) _load();
                }),
                if (_s['push'] != true && PushService.lastError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('سبب التوقف: ${PushService.lastError}\nإذا بقى: حدّث «خدمات Google Play» من المتجر وتأكد إن الوقت والتاريخ تلقائي.',
                        style: const TextStyle(fontSize: 11.5, color: Colors.orange)),
                  ),
                if (_s['push'] == true)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('ممتاز: هذا الجهاز يستقبل عبر Google، ولا يحتاج خدمة الخلفية.',
                        style: TextStyle(fontSize: 12, color: Colors.green)),
                  ),
                _row('السماح بالإشعارات', _s['notifications'],
                    fix: 'سماح', onFix: BackgroundBridge.requestNotifications),
                _row('استثناء من توفير البطارية', _s['battery'],
                    fix: 'سماح', onFix: BackgroundBridge.requestBattery),
                _row('تسجيل الجهاز في الخادم', _s['registered'],
                    fix: 'إعادة', onFix: BackgroundBridge.restart),
                _row('خدمة الخلفية تعمل', _s['running'],
                    fix: 'تشغيل', onFix: BackgroundBridge.restart),
                _row('الخدمة متصلة بالخادم', _s['alive'],
                    fix: 'إعادة', onFix: BackgroundBridge.restart),
                if (poll != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('آخر اتصال للخدمة: ${Fmt.time(poll)}', style: const TextStyle(fontSize: 12)),
                  ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText('آخر خطأ: $err',
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                  ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.notifications_active_rounded),
                    label: const Text('إرسال إشعار تجريبي'),
                    onPressed: () {
                      BackgroundBridge.test();
                      showSnack(context, 'اخرج من التطبيق الآن، سيصلك إشعار خلال 6 ثوانٍ');
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'بهواتف شاومي/ريدمي/أوبو/فيفو/هواوي: من إعدادات الهاتف ← التطبيقات ← «المبرمج المجهول» '
                    'فعّل «التشغيل التلقائي» واجعل البطارية «بلا قيود»، وإلا يطفئ النظام التطبيق بعد غلقه.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.settings_applications_rounded),
                    label: const Text('فتح إعدادات التطبيق في الهاتف'),
                    onPressed: () => BackgroundBridge.openAppSettings(),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
