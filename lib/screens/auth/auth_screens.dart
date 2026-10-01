import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../services/core_services.dart';
import '../../repositories/user_repositories.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';

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
    return Scaffold(
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
                    const Center(child: BrandLogo(size: 92)),
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
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('دخول'),
                    ),
                    if (!widget.adminMode) ...[
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
    return Scaffold(
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
    return Scaffold(
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
