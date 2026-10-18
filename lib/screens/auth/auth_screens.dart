import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/core_services.dart';
import '../../repositories/user_repositories.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../../widgets/fx.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onBack;
  final bool adminMode;
  const LoginScreen({super.key, this.onBack, this.adminMode = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repo = AuthRepository();
  bool _busy = false;
  bool _obscure = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _repo.signIn(_email.text, _password.text);
      final p = await ProfileRepository().get(supa.auth.currentUser!.id);
      if (p?.isBanned ?? false) {
        await _repo.signOut();
        throw Exception('هذا الحساب محظور نهائيًا من قبل الإدارة');
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google(String clientId) async {
    setState(() => _busy = true);
    try {
      final ok = await _repo.signInWithGoogle(clientId);
      if (!ok) return;
      final p = await ProfileRepository().get(supa.auth.currentUser!.id);
      if (p?.isBanned ?? false) {
        await _repo.signOut();
        throw Exception('هذا الحساب محظور نهائيًا من قبل الإدارة');
      }
    } catch (e) {
      final t = e.toString();
      String msg;
      if (t.contains('sign_in_failed') && RegExp(r'\b10\b').hasMatch(t)) {
        msg = 'إعداد Google ناقص (10): المفتاح الملصوق لازم يكون نوعه Web، ومفتاح Android لازم يكون بنفس المشروع';
      } else if (t.contains('sign_in_failed') && t.contains('12500')) {
        msg = 'Google رفض الدخول (12500): كمّل معلومات صفحة Branding بكوكل وحاول مرة ثانية';
      } else if (t.contains('network_error') || t.contains(': 7:')) {
        msg = 'ماكو اتصال بـ Google، تأكد من الإنترنت';
      } else {
        msg = friendlyError(e);
      }
      supa.rpc('client_log', params: {'p_info': 'google_login: ${t.length > 300 ? t.substring(0, 300) : t}'}).catchError((_) => null);
      if (mounted) showSnack(context, msg, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetServer() async {
    if (!await confirmDialog(context, 'تغيير إعدادات الخادم',
        'سيتم مسح رابط ومفتاح Supabase المحفوظين. بعدها أغلق التطبيق وافتحه من جديد لإدخالهما.')) {
      return;
    }
    await AppConfig.clear();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تم المسح'),
        content: const Text('أغلق التطبيق نهائيًا (من قائمة التطبيقات المفتوحة) ثم افتحه من جديد.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('حسنًا'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuroraScaffold(
      appBar: widget.onBack == null
          ? null
          : AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // دخول الشعار بحركة ثلاثية الأبعاد
                    Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 1100),
                        curve: Curves.easeOutBack,
                        builder: (_, t, child) => Opacity(
                          opacity: t.clamp(0.0, 1.0),
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0015)
                              ..rotateY((1 - t) * 1.6)
                              ..rotateX((1 - t) * 0.5),
                            child: child,
                          ),
                        ),
                        child: const FloatingLogo3D(child: BrandLogo(size: 92)),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(widget.adminMode ? 'دخول المدير' : 'تسجيل الدخول',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text('أهلًا بك من جديد 👋', style: TextStyle(color: Theme.of(context).hintColor)),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.alternate_email)),
                      validator: Validators.email,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => (v == null || v.isEmpty) ? 'أدخل كلمة المرور' : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => ForgotPasswordScreen(email: _email.text))),
                        child: const Text('نسيت كلمة المرور؟'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GlowButton(
                      filled: true,
                      busy: _busy,
                      onPressed: _submit,
                      colors: const [AppColors.cyan, AppColors.violet, AppColors.pink, AppColors.cyan],
                      label: const Text('دخول'),
                    ),
                    if (!widget.adminMode) ...[
                      Builder(builder: (context) {
                        final st = context.watch<AppStatusProvider>();
                        if (st.googleClientId == null && !st.phoneLogin) return const SizedBox.shrink();
                        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const SizedBox(height: 18),
                          Row(children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text('أو', style: TextStyle(color: Theme.of(context).hintColor)),
                            ),
                            const Expanded(child: Divider()),
                          ]),
                          const SizedBox(height: 12),
                          if (st.googleClientId != null)
                            GlowButton(
                              onPressed: _busy ? null : () => _google(st.googleClientId!),
                              colors: const [
                                Color(0xFF4285F4),
                                Color(0xFFEA4335),
                                Color(0xFFFBBC05),
                                Color(0xFF34A853),
                                Color(0xFF4285F4),
                              ],
                              icon: const Text('G',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF4285F4))),
                              label: const Text('متابعة بحساب Google'),
                            ),
                          if (st.phoneLogin) ...[
                            const SizedBox(height: 10),
                            GlowButton(
                              colors: const [AppColors.green, AppColors.cyan, Color(0xFF29B6F6), AppColors.green],
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              st.tgBot != null ? const TelegramPhoneScreen() : const PhoneLoginScreen())),
                              icon: const Icon(Icons.phone_iphone_rounded, color: AppColors.green),
                              label: const Text('الدخول برقم الهاتف'),
                            ),
                          ],
                        ]);
                      }),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('ليس لديك حساب؟'),
                          TextButton(
                            onPressed: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                            child: const Text('إنشاء حساب'),
                          ),
                        ],
                      ),
                    ],
                    if (!AppConfig.isBaked)
                      TextButton.icon(
                        onPressed: _resetServer,
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: const Text('تغيير إعدادات الخادم'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _repo = AuthRepository();
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final signedIn = await _repo.signUp(
        email: _email.text,
        password: _password.text,
        username: _username.text,
        displayName: _name.text,
      );
      if (!mounted) return;
      if (signedIn) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => VerifyCodeScreen(email: _email.text.trim())),
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuroraScaffold(
      appBar: AppBar(title: const Text('إنشاء حساب')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Center(child: BrandLogo(size: 70, showName: false)),
              const SizedBox(height: 24),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'اسم العرض', prefixIcon: Icon(Icons.badge_outlined)),
                validator: Validators.displayName,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _username,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'اسم المستخدم (أحرف إنجليزية)', prefixIcon: Icon(Icons.alternate_email), hintText: 'anonymous_dev'),
                validator: Validators.username,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)),
                validator: Validators.email,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'كلمة المرور', prefixIcon: Icon(Icons.lock_outline)),
                validator: Validators.password,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور', prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) => v == _password.text ? null : 'كلمتا المرور غير متطابقتين',
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('إنشاء الحساب'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ForgotPasswordScreen extends StatefulWidget {
  final String email;
  const ForgotPasswordScreen({super.key, this.email = ''});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _repo = AuthRepository();
  // رمز الاسترداد
  final _username = TextEditingController();
  final _recovery = TextEditingController();
  final _newPass1 = TextEditingController();
  // البريد
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _newPass2 = TextEditingController();
  bool _sent = false;
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    showSnack(context, 'تم تغيير كلمة المرور وتسجيل دخولك ✅');
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Widget _button(String label, VoidCallback onTap) => FilledButton(
        onPressed: _busy ? null : onTap,
        child: _busy
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
      );

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('استعادة كلمة المرور'),
          bottom: const TabBar(tabs: [Tab(text: 'رمز الاسترداد'), Tab(text: 'عبر البريد')]),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text('أدخل اسم المستخدم ورمز الاسترداد الذي حفظته من الإعدادات. لا يحتاج إيميل.'),
                const SizedBox(height: 20),
                TextField(
                  controller: _username,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'اسم المستخدم', prefixText: '@'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _recovery,
                  textDirection: TextDirection.ltr,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'رمز الاسترداد', hintText: 'XXXX-XXXX-XXXX'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _newPass1,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
                ),
                const SizedBox(height: 24),
                _button('تغيير كلمة المرور', () => _run(() async {
                      final err = Validators.password(_newPass1.text);
                      if (err != null) throw Exception(err);
                      await _repo.resetWithRecoveryCode(_username.text, _recovery.text, _newPass1.text);
                      if (mounted) _done();
                    })),
                const SizedBox(height: 16),
                Text(
                  'ليس لديك رمز استرداد؟ راسل الإدارة من حساب آخر أو من أي وسيلة، ويمكن للمدير تعيين كلمة مرور جديدة لك.',
                  style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor),
                ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(_sent ? 'أدخل الرمز المرسل إلى بريدك وكلمة المرور الجديدة.' : 'أدخل بريدك وسنرسل لك رمز استعادة.'),
                const SizedBox(height: 20),
                TextField(
                  controller: _email,
                  enabled: !_sent,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                ),
                if (_sent) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    maxLength: 8,
                    decoration: const InputDecoration(labelText: 'رمز التحقق (6 إلى 8 أرقام)', counterText: ''),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _newPass2,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
                  ),
                ],
                const SizedBox(height: 24),
                _button(_sent ? 'تغيير كلمة المرور' : 'إرسال الرمز', () => _run(() async {
                      if (Validators.email(_email.text) != null) throw Exception('البريد غير صالح');
                      if (!_sent) {
                        await _repo.sendRecovery(_email.text);
                        setState(() => _sent = true);
                      } else {
                        final err = Validators.password(_newPass2.text);
                        if (err != null) throw Exception(err);
                        await _repo.resetWithCode(_email.text, _code.text, _newPass2.text);
                        if (mounted) _done();
                      }
                    })),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// إدخال رمز التأكيد المرسل للبريد (6 إلى 8 أرقام).
class VerifyCodeScreen extends StatefulWidget {
  final String email;
  const VerifyCodeScreen({super.key, required this.email});
  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  final _code = TextEditingController();
  final _repo = AuthRepository();
  bool _busy = false;

  Future<void> _verify() async {
    final c = _code.text.trim();
    if (!RegExp(r'^\d{6,8}$').hasMatch(c)) {
      showSnack(context, 'الرمز من 6 إلى 8 أرقام', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _repo.verifySignup(widget.email, c);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuroraScaffold(
      appBar: AppBar(title: const Text('تأكيد الحساب')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.mark_email_read_rounded, size: 64),
          const SizedBox(height: 16),
          Text('أرسلنا رمز تأكيد إلى\n${widget.email}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.6)),
          const SizedBox(height: 8),
          const Text('افحص البريد الوارد ومجلد الرسائل غير المرغوب فيها (Spam).',
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 8,
            style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w800),
            decoration: const InputDecoration(hintText: '••••••', counterText: ''),
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _verify,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('تأكيد'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _repo.resendConfirmation(widget.email);
                if (context.mounted) showSnack(context, 'تمت إعادة إرسال الرمز');
              } catch (e) {
                if (context.mounted) showSnack(context, friendlyError(e), error: true);
              }
            },
            child: const Text('إعادة إرسال الرمز'),
          ),
        ],
      ),
    );
  }
}


/// الدخول برقم الهاتف: رمز تحقق SMS حقيقي، ويدعم كل مفاتيح الدول (الافتراضي العراق +964).
class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});
  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  static const _codes = [
    ('🇮🇶', 'العراق', '+964'),
    ('🇸🇦', 'السعودية', '+966'),
    ('🇦🇪', 'الإمارات', '+971'),
    ('🇰🇼', 'الكويت', '+965'),
    ('🇯🇴', 'الأردن', '+962'),
    ('🇸🇾', 'سوريا', '+963'),
    ('🇱🇧', 'لبنان', '+961'),
    ('🇪🇬', 'مصر', '+20'),
    ('🇹🇷', 'تركيا', '+90'),
    ('🇮🇷', 'إيران', '+98'),
    ('🇩🇪', 'ألمانيا', '+49'),
    ('🇬🇧', 'بريطانيا', '+44'),
    ('🇺🇸', 'أمريكا', '+1'),
  ];
  final _repo = AuthRepository();
  final _num = TextEditingController();
  final _code = TextEditingController();
  String _cc = '+964';
  String? _sentTo;
  bool _busy = false;
  int _wait = 0;

  String get _phone {
    var n = _num.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (n.startsWith('00')) return '+${n.substring(2)}';
    if (n.startsWith('0')) n = n.substring(1);
    return '$_cc$n';
  }

  Future<void> _send() async {
    final p = _phone;
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(p)) {
      showSnack(context, 'رقم الهاتف غير صحيح', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _repo.sendPhoneCode(p);
      if (!mounted) return;
      setState(() {
        _sentTo = p;
        _wait = 60;
      });
      _tick();
      showSnack(context, 'وصلك رمز التحقق برسالة SMS');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _tick() {
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted || _wait <= 0) return;
      setState(() => _wait--);
      _tick();
    });
  }

  Future<void> _verify() async {
    final to = _sentTo;
    if (to == null || _code.text.trim().length < 4) return;
    setState(() => _busy = true);
    try {
      await _repo.verifyPhoneCode(to, _code.text);
      final p = await ProfileRepository().get(supa.auth.currentUser!.id);
      if (p?.isBanned ?? false) {
        await _repo.signOut();
        throw Exception('هذا الحساب محظور نهائيًا من قبل الإدارة');
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _num.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentTo != null;
    return AuroraScaffold(
      appBar: AppBar(title: const Text('الدخول برقم الهاتف')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Icon(Icons.sms_rounded, size: 64),
        const SizedBox(height: 12),
        Text(sent ? 'دخّل الرمز اللي وصلك على $_sentTo' : 'راح نرسلك رمز تحقق برسالة SMS',
            textAlign: TextAlign.center, textDirection: TextDirection.rtl),
        const SizedBox(height: 20),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: !sent
              ? Row(key: const ValueKey('n'), textDirection: TextDirection.ltr, children: [
                  DropdownButton<String>(
                    value: _cc,
                    items: [
                      for (final c in _codes) DropdownMenuItem(value: c.$3, child: Text('${c.$1} ${c.$3}')),
                    ],
                    onChanged: (v) => setState(() => _cc = v ?? '+964'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _num,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
                      decoration: const InputDecoration(hintText: '780 123 4567'),
                    ),
                  ),
                ])
              : TextField(
                  key: const ValueKey('c'),
                  controller: _code,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 8,
                  style: const TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w800),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(counterText: '', hintText: '••••••'),
                  onChanged: (v) {
                    if (v.length >= 6) _verify();
                  },
                ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: _busy ? null : (sent ? _verify : _send),
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(sent ? 'تأكيد' : 'إرسال الرمز'),
        ),
        if (sent)
          TextButton(
            onPressed: _wait > 0 || _busy ? null : _send,
            child: Text(_wait > 0 ? 'إعادة الإرسال بعد $_wait ثانية' : 'إعادة إرسال الرمز'),
          ),
        if (sent)
          TextButton(
            onPressed: () => setState(() {
              _sentTo = null;
              _code.clear();
            }),
            child: const Text('تغيير الرقم'),
          ),
      ]),
    );
  }
}


/// التحقق المجاني من رقم الهاتف عن طريق بوت تيليكرام (بدون رسائل SMS):
/// المستخدم يفتح البوت ويضغط «مشاركة رقمي»، والتطبيق يدخل تلقائيًا أول ما يتأكد الرقم.
class TelegramPhoneScreen extends StatefulWidget {
  const TelegramPhoneScreen({super.key});
  @override
  State<TelegramPhoneScreen> createState() => _TelegramPhoneScreenState();
}

class _TelegramPhoneScreenState extends State<TelegramPhoneScreen> with WidgetsBindingObserver {
  String? _nonce;
  String? _url;
  bool _busy = false;
  bool _waiting = false;
  bool _done = false;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && _waiting) _check();
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      if (_nonce == null) {
        final r = ((await supa.rpc('phone_tg_start')) as Map).cast<String, dynamic>();
        _nonce = r['nonce'] as String;
        _url = r['url'] as String;
      }
      final ok = await launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication);
      if (!ok && mounted) showSnack(context, 'نصّب تيليكرام أول، وبعدين حاول مرة ثانية', error: true);
      if (!mounted) return;
      setState(() => _waiting = true);
      _polls = 0;
      _loop();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _loop() {
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (!mounted || !_waiting || _done) return;
      await _check();
      if (++_polls < 300) _loop();
    });
  }

  Future<void> _check() async {
    final n = _nonce;
    if (n == null || _done) return;
    try {
      final r = ((await supa.rpc('phone_tg_check', params: {'p_nonce': n})) as Map).cast<String, dynamic>();
      final st = r['status'];
      if (st == 'expired') {
        _nonce = null;
        if (mounted) {
          setState(() => _waiting = false);
          showSnack(context, 'انتهى الوقت، اضغط الزر مرة ثانية', error: true);
        }
        return;
      }
      if (st != 'ok' || _done) return;
      _done = true;
      await supa.auth.signInWithPassword(email: r['email'] as String, password: r['password'] as String);
      final p = await ProfileRepository().get(supa.auth.currentUser!.id);
      if (p?.isBanned ?? false) {
        await AuthRepository().signOut();
        throw Exception('هذا الحساب محظور نهائيًا من قبل الإدارة');
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted && _done) {
        _done = false;
        showSnack(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AuroraScaffold(
      appBar: AppBar(title: const Text('الدخول برقم الهاتف')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 12),
          FloatingLogo3D(child: Icon(Icons.verified_user_rounded, size: 72, color: cs.primary)),
          const SizedBox(height: 16),
          const Text('نأكد رقمك مجانًا عن طريق تيليكرام',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          const Text(
            '١. اضغط الزر الجوه، راح ينفتح بوت التطبيق بتيليكرام\n'
            '٢. اضغط «Start» أو «بدء»\n'
            '٣. اضغط زر «📱 مشاركة رقمي» ووافق\n'
            '٤. ارجع للتطبيق — تدخل لحسابك تلقائيًا',
            style: TextStyle(fontSize: 15, height: 1.9),
          ),
          const SizedBox(height: 24),
          GlowButton(
            filled: true,
            busy: _busy,
            onPressed: _start,
            colors: const [Color(0xFF29B6F6), Color(0xFF0088CC), AppColors.cyan, Color(0xFF29B6F6)],
            icon: const Icon(Icons.send_rounded, color: Colors.white),
            label: Text(_waiting ? 'افتح تيليكرام مرة ثانية' : 'تحقق عبر تيليكرام'),
          ),
          if (_waiting) ...[
            const SizedBox(height: 20),
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('ننتظر تأكيد رقمك من تيليكرام...'),
            ]),
          ],
          const SizedBox(height: 24),
          Text('رقمك ما ينعرض لأي مستخدم، ويستخدم بس لتسجيل دخولك.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
