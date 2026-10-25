import 'package:flutter/material.dart';

import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../profile/profile_screens.dart';

/// لوحة المالك: الحسابات الذكية 🤖 (شخصيات ذكاء اصطناعي مكشوفة بكل التخصصات)
class AiPersonasScreen extends StatefulWidget {
  const AiPersonasScreen({super.key});
  @override
  State<AiPersonasScreen> createState() => _AiPersonasScreenState();
}

class _AiPersonasScreenState extends State<AiPersonasScreen> {
  Map<String, dynamic>? _d;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = ((await supa.rpc('ai_personas_admin')) as Map).cast<String, dynamic>();
      if (mounted) setState(() => _d = r);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  List<Map<String, dynamic>> get _list =>
      [for (final e in (_d?['list'] as List? ?? const [])) (e as Map).cast<String, dynamic>()];

  String _plainName(Map<String, dynamic> p) {
    final n = '${p['name'] ?? ''}'.replaceAll('🤖', '').trim();
    final i = n.indexOf(' | ');
    return i > 0 ? n.substring(0, i) : n;
  }

  Future<void> _config({bool? enabled, int? gap}) async {
    try {
      final r = ((await supa.rpc('ai_personas_config', params: {'p_enabled': enabled, 'p_gap_min': gap})) as Map)
          .cast<String, dynamic>();
      if (mounted) setState(() => _d = r);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _save(Map<String, dynamic>? p, {bool? enabled}) async {
    String name = p == null ? '' : _plainName(p);
    String spec = '${p?['specialty'] ?? ''}';
    String focus = '${p?['focus'] ?? ''}';
    int perDay = ((p?['per_day'] ?? 2) as num).toInt();
    if (enabled == null) {
      final nameC = TextEditingController(text: name);
      final specC = TextEditingController(text: spec);
      final focusC = TextEditingController(text: focus);
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, set) => AlertDialog(
            title: Text(p == null ? 'حساب ذكي جديد 🤖' : 'تعديل الحساب'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nameC, maxLength: 20, decoration: const InputDecoration(labelText: 'الاسم')),
                TextField(
                    controller: specC,
                    maxLength: 25,
                    decoration: const InputDecoration(labelText: 'التخصص', hintText: 'مثلاً: طبخ عراقي')),
                TextField(
                    controller: focusC,
                    maxLines: 2,
                    maxLength: 200,
                    decoration: const InputDecoration(
                        labelText: 'شنو يركز عليه (اختياري)', hintText: 'مثلاً: أكلات عراقية تقليدية ونصائح طبخ')),
                Row(children: [
                  const Text('منشورات باليوم:'),
                  Expanded(
                    child: Slider(
                      value: perDay.toDouble(),
                      min: 0,
                      max: 12,
                      divisions: 12,
                      label: '$perDay',
                      onChanged: (v) => set(() => perDay = v.round()),
                    ),
                  ),
                  Text('$perDay'),
                ]),
                const Text('العلامة 🤖 تنضاف للاسم تلقائيًا وما تنشال.', style: TextStyle(fontSize: 12)),
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
      name = nameC.text.trim();
      spec = specC.text.trim();
      focus = focusC.text.trim();
    }
    try {
      final r = ((await supa.rpc('ai_persona_save', params: {
        'p_id': p?['id'],
        'p_name': name,
        'p_specialty': spec,
        'p_focus': focus,
        'p_per_day': perDay,
        'p_enabled': enabled ?? (p?['enabled'] ?? true),
      })) as Map)
          .cast<String, dynamic>();
      if (mounted) setState(() => _d = r);
      if (mounted && enabled == null) showSnack(context, 'تم الحفظ ✅');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _postNow(Map<String, dynamic> p) async {
    final topic = await promptText(context, 'انشر هسه — ${_plainName(p)}',
        hint: 'موضوع معيّن (اختياري) — اتركه فارغ حتى يختار بنفسه', ok: 'انشر');
    if (topic == null) return;
    if (!mounted) return;
    showSnack(context, 'دا يكتب المنشور... ⏳');
    try {
      await supa.rpc('ai_persona_post_now', params: {'p_id': p['id'], 'p_topic': topic});
      if (mounted) showSnack(context, 'انتشر ✅');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    if (!await confirmDialog(context, 'حذف ${_plainName(p)}؟', 'ينحذف الحساب ويا كل منشوراته.', ok: 'حذف', danger: true)) {
      return;
    }
    try {
      final r = ((await supa.rpc('ai_persona_delete', params: {'p_id': p['id']})) as Map).cast<String, dynamic>();
      if (mounted) setState(() => _d = r);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  void _menu(Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.send_rounded, color: Colors.blue),
            title: const Text('انشر هسه'),
            onTap: () {
              Navigator.pop(c);
              _postNow(p);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('تعديل'),
            onTap: () {
              Navigator.pop(c);
              _save(p);
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_rounded),
            title: const Text('عرض الحساب'),
            onTap: () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: '${p['id']}')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: const Text('حذف', style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              Navigator.pop(c);
              _delete(p);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final list = _list
        .where((p) => _q.isEmpty || '${p['name']} ${p['specialty']}'.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    final gap = ((d?['gap_min'] ?? 30) as num).toInt();
    const gaps = [10, 20, 30, 60, 120, 240];
    return Scaffold(
      appBar: AppBar(title: Text('الحسابات الذكية 🤖 ${d == null ? '' : '(${_list.length})'}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _save(null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('حساب جديد'),
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 90), children: [
                Card(
                  child: Column(children: [
                    SwitchListTile(
                      title: const Text('تشغيل الحسابات الذكية', style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: const Text('تنشر بتخصصاتها وترد على التعليقات بمنشوراتها'),
                      value: d['enabled'] == true,
                      onChanged: (v) => _config(enabled: v),
                    ),
                    ListTile(
                      title: const Text('منشور جديد كل'),
                      subtitle: const Text('من كل الحسابات سوا — أقل = أكثر استهلاك لحصة الذكاء الاصطناعي'),
                      trailing: DropdownButton<int>(
                        value: gaps.contains(gap) ? gap : 30,
                        items: [for (final g in gaps) DropdownMenuItem(value: g, child: Text(g < 60 ? '$g دقيقة' : '${g ~/ 60} ساعة'))],
                        onChanged: (v) => _config(gap: v),
                      ),
                    ),
                  ]),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text('🤖 كل الحسابات عليها علامة ذكاء اصطناعي ثابتة، وما تستلم هدايا ولا تتابع أحد.',
                      style: TextStyle(fontSize: 12)),
                ),
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'دوّر بالاسم أو التخصص'),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
                const SizedBox(height: 6),
                for (final p in list)
                  Card(
                    child: ListTile(
                      onTap: () => _menu(p),
                      leading: Avatar(url: p['avatar_url'] as String?, name: '${p['name'] ?? ''}', size: 44),
                      title: Text('${p['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${p['per_day']} باليوم · ${p['posts']} منشور · ${p['replies']} رد'
                        '${(p['last_error'] ?? '') != '' ? '\n⚠️ ${p['last_error']}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Switch(value: p['enabled'] == true, onChanged: (v) => _save(p, enabled: v)),
                    ),
                  ),
              ]),
            ),
    );
  }
}
