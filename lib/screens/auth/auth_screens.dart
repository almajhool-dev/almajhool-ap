import 'package:flutter/material.dart';

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
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('تحقق من بريدك'),
            content: Text('أرسلنا رابط تأكيد إلى ${_email.text.trim()}.\nافتح الرابط ثم سجّل الدخول.'),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    await _repo.resendConfirmation(_email.text);
                    if (c.mounted) showSnack(c, 'تمت إعادة الإرسال');
                  } catch (e) {
                    if (c.mounted) showSnack(c, friendlyError(e), error: true);
                  }
                },
                child: const Text('إعادة الإرسال'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
                onPressed: () => Navigator.pop(c),
                child: const Text('حسنًا'),
              ),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
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
                    labelText: 'اسم المستخدم (Username)', prefixIcon: Icon(Icons.alternate_email), hintText: 'anonymous_dev'),
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
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _repo = AuthRepository();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة المرور')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _sent
                ? 'أدخل الرمز المرسل إلى بريدك وكلمة المرور الجديدة.'
                : 'أدخل بريدك وسنرسل لك رمز استعادة.',
          ),
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
              decoration: const InputDecoration(labelText: 'رمز التحقق'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة'),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      if (Validators.email(_email.text) != null) throw Exception('البريد غير صالح');
                      if (!_sent) {
                        await _repo.sendRecovery(_email.text);
                        setState(() => _sent = true);
                      } else {
                        final pErr = Validators.password(_password.text);
                        if (pErr != null) throw Exception(pErr);
                        await _repo.resetWithCode(_email.text, _code.text, _password.text);
                        if (mounted) {
                          showSnack(context, 'تم تغيير كلمة المرور');
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        }
                      }
                    }),
            child: Text(_sent ? 'تغيير كلمة المرور' : 'إرسال الرمز'),
          ),
        ],
      ),
    );
  }
}
