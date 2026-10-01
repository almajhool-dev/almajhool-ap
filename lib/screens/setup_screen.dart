import 'package:flutter/material.dart';

import '../core/config.dart';
import '../widgets/common.dart';

/// تظهر فقط إذا لم تُضبط مفاتيح Supabase وقت البناء.
class SetupScreen extends StatefulWidget {
  final String? error;
  final Future<void> Function() onSaved;
  const SetupScreen({super.key, this.error, required this.onSaved});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _url = TextEditingController(text: AppConfig.url);
  final _key = TextEditingController(text: AppConfig.anonKey);
  final _form = GlobalKey<FormState>();
  bool _busy = false;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await AppConfig.save(_url.text, _key.text);
    await widget.onSaved();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              const Center(child: BrandLogo(size: 90)),
              const SizedBox(height: 28),
              const Text('ربط الخادم (مرة واحدة)',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'انسخ Project URL و anon public key من لوحة Supabase → Project Settings → API.',
              ),
              if (widget.error != null) ...[
                const SizedBox(height: 12),
                Text(widget.error!, style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: _url,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'رابط الخادم', hintText: 'https://xxxx.supabase.co'),
                validator: (v) {
                  final u = (v ?? '').trim();
                  return RegExp(r'^https://[A-Za-z0-9.-]+(/)?$').hasMatch(u)
                      ? null
                      : 'الصق Project URL فقط، مثل https://xxxx.supabase.co';
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _key,
                textDirection: TextDirection.ltr,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'مفتاح الخادم العام'),
                validator: (v) {
                  final k = (v ?? '').trim();
                  final ok = (k.startsWith('eyJ') || k.startsWith('sb_publishable_')) &&
                      !k.contains(RegExp(r'\s')) &&
                      k.length > 30;
                  return ok ? null : 'هذا ليس المفتاح. انسخ anon public key (يبدأ بـ eyJ أو sb_publishable_)';
                },
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ ومتابعة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
