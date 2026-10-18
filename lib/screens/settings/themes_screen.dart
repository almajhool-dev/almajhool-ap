import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../../services/core_services.dart';
import '../../services/fx_settings.dart';
import '../../utils/helpers.dart';
import '../../widgets/fx.dart';

/// السمات المتحركة: معاينة حيّة لكل سمة، اختيار، إنشاء سمة خاصة، والمالك ينشرها لكل المستخدمين.
class ThemesScreen extends StatefulWidget {
  const ThemesScreen({super.key});
  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  final fx = FxSettings.instance;

  static const palette = [
    Color(0xFF00E5FF), Color(0xFF7C4DFF), Color(0xFFFF4D9D), Color(0xFF00FF9C),
    Color(0xFF2979FF), Color(0xFFFFC400), Color(0xFFFF6D00), Color(0xFFFF1744),
    Color(0xFF00BFA5), Color(0xFFE040FB), Color(0xFF76FF03), Color(0xFFFFFFFF),
  ];

  bool get _owner => context.read<SessionProvider>().profile?.isOwner ?? false;

  @override
  void initState() {
    super.initState();
    fx.refreshPublished();
  }

  Future<void> _create([FxTheme? edit]) async {
    final name = TextEditingController(text: edit?.name ?? '');
    final words = TextEditingController(text: edit?.words ?? '');
    var base = edit?.base ?? 'aurora';
    var colors = [...(edit?.colors ?? FxSettings.builtins.first.colors)];
    var slot = 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final preview = FxTheme(id: 'preview', name: name.text, base: base, colors: colors, words: words.text);
          return AlertDialog(
            title: Text(edit == null ? 'سمة جديدة 🎨' : 'تعديل السمة'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(height: 130, child: FxBackground(theme: preview, forceOn: true, child: const SizedBox())),
                ),
                const SizedBox(height: 10),
                TextField(controller: name, maxLength: 30, decoration: const InputDecoration(labelText: 'اسم السمة')),
                const Text('نوع الحركة:', style: TextStyle(fontWeight: FontWeight.w700)),
                Wrap(spacing: 6, children: [
                  for (final b in FxSettings.bases)
                    ChoiceChip(
                      label: Text(FxSettings.baseNames[b]!),
                      selected: base == b,
                      onSelected: (_) => set(() => base = b),
                    ),
                ]),
                const SizedBox(height: 8),
                const Text('الألوان (اختار مربع وبعدين لون):', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Row(children: [
                  for (var i = 0; i < 3; i++)
                    GestureDetector(
                      onTap: () => set(() => slot = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsetsDirectional.only(end: 8),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors[i],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: slot == i ? Colors.white : Colors.transparent, width: 3),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final p in palette)
                    GestureDetector(
                      onTap: () => set(() => colors[slot] = p),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(color: p, shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                      ),
                    ),
                ]),
                if (base == 'matrix' || base == 'network') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: words,
                    maxLength: 200,
                    onChanged: (_) => set(() {}),
                    decoration: InputDecoration(
                      labelText: base == 'matrix' ? 'الكلمات/الرموز اللي تنزل' : 'الرموز اللي تطلع بالشبكة',
                      hintText: base == 'matrix' ? 'مثلاً: AES RSA 🔒 0 1' : 'مثلاً: ❤ 💬 👍',
                    ),
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ وتطبيق')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final n = name.text.trim().isEmpty ? 'سمتي' : name.text.trim();
    fx.addCustom(FxTheme(
      id: edit?.id ?? 'my_${DateTime.now().millisecondsSinceEpoch}',
      name: n,
      base: base,
      colors: colors,
      words: words.text.trim(),
    ));
    if (mounted) showSnack(context, 'انحفظت السمة وتطبّقت ✨');
  }

  Future<void> _options(FxTheme t) async {
    final owner = _owner;
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!t.builtin && !t.published)
            ListTile(leading: const Icon(Icons.edit), title: const Text('تعديل'), onTap: () => Navigator.pop(c, 'edit')),
          if (owner && !t.published)
            ListTile(
                leading: const Icon(Icons.public),
                title: const Text('انشرها لكل المستخدمين'),
                onTap: () => Navigator.pop(c, 'publish')),
          if (owner && t.published)
            ListTile(
                leading: const Icon(Icons.public_off),
                title: const Text('شيلها من سمات المستخدمين'),
                onTap: () => Navigator.pop(c, 'unpublish')),
          if (!t.builtin && !t.published)
            ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
                onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    try {
      switch (a) {
        case 'edit':
          await _create(t);
        case 'delete':
          fx.removeCustom(t.id);
        case 'publish':
          await supa.rpc('theme_publish', params: {
            'p_name': t.name,
            'p_base': t.base,
            'p_colors': [for (final c in t.colors) c.toARGB32()],
            'p_words': t.words,
          });
          await fx.refreshPublished();
          if (mounted) showSnack(context, 'صارت السمة متاحة لكل المستخدمين 🎉');
        case 'unpublish':
          await supa.rpc('theme_unpublish', params: {'p_id': t.id.replaceFirst('pub_', '')});
          await fx.refreshPublished();
          if (mounted) showSnack(context, 'انشالت السمة');
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: fx,
      builder: (context, _) {
        final list = fx.all;
        return Scaffold(
          appBar: AppBar(title: const Text('السمات المتحركة 🎨')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('سمة جديدة'),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 90), children: fxList([
            SwitchListTile(
              title: const Text('خلفيات متحركة ✨', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('إذا طفيتها ترجع الخلفية ثابتة وعادية'),
              value: fx.enabled,
              onChanged: fx.setEnabled,
            ),
            const SizedBox(height: 6),
            for (final t in list) _card(t),
          ])),
        );
      },
    );
  }

  Widget _card(FxTheme t) {
    final sel = fx.themeId == t.id;
    final tag = t.builtin ? 'من التطبيق' : t.published ? 'من المالك' : 'سمتي';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => fx.select(t.id),
        onLongPress: () => _options(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? t.colors[0] : Colors.white12, width: sel ? 2.5 : 1),
            boxShadow: sel ? [BoxShadow(color: t.colors[1].withValues(alpha: 0.4), blurRadius: 18)] : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 120,
              child: FxBackground(
                theme: t,
                forceOn: true,
                child: Container(
                  alignment: AlignmentDirectional.bottomStart,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                    ),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('${FxSettings.baseNames[t.base]} · $tag',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                    if (sel) const Icon(Icons.check_circle, color: Colors.white),
                    IconButton(
                      onPressed: () => _options(t),
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
