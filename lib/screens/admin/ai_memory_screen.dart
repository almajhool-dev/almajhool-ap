import 'package:flutter/material.dart';

import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../profile/profile_screens.dart';

/// لوحة المالك: ذاكرة المساعد 🧠 — الأشخاص اللي يتذكرهم مساعد حسابك من الرسائل الخاصة.
/// الملاحظات تنكتب تلقائيًا بعد كل محادثة (بدون أرقام ولا بيانات حساسة)، وتكدر تعدّلها أو تمسحها.
class AiMemoryScreen extends StatefulWidget {
  const AiMemoryScreen({super.key});
  @override
  State<AiMemoryScreen> createState() => _AiMemoryScreenState();
}

class _AiMemoryScreenState extends State<AiMemoryScreen> {
  List<Map<String, dynamic>>? _list;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('ai_people_list', params: {'p_q': _q});
      if (!mounted) return;
      setState(() => _list = [for (final e in (r as List? ?? const [])) (e as Map).cast<String, dynamic>()]);
    } catch (e) {
      if (mounted) {
        setState(() => _list ??= []);
        showSnack(context, friendlyError(e), error: true);
      }
    }
  }

  String _ago(String? iso) {
    final t = DateTime.tryParse(iso ?? '');
    if (t == null) return '';
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'هسه';
    if (d.inMinutes < 60) return 'قبل ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'قبل ${d.inHours} ساعة';
    return 'قبل ${d.inDays} يوم';
  }

  Future<void> _edit(Map<String, dynamic> p) async {
    final ownerC = TextEditingController(text: '${p['owner_note'] ?? ''}');
    final notesC = TextEditingController(text: '${p['notes'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${p['display_name'] ?? ''}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ownerC,
              minLines: 2,
              maxLines: 4,
              maxLength: 600,
              decoration: const InputDecoration(
                labelText: 'شنو تريد المساعد يعرف عنه (منك)',
                hintText: 'مثلاً: صديقي من الجامعة، احچي وياه بالعراقي',
              ),
            ),
            TextField(
              controller: notesC,
              minLines: 3,
              maxLines: 8,
              maxLength: 1400,
              decoration: const InputDecoration(labelText: 'اللي يتذكره المساعد من محادثاته'),
            ),
            const Text('الأرقام والإيميلات تنشال تلقائيًا من الذاكرة.', style: TextStyle(fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supa.rpc('ai_person_set', params: {
        'p_user': p['user_id'],
        'p_owner_note': ownerC.text.trim(),
        'p_notes': notesC.text.trim(),
      });
      if (mounted) showSnack(context, 'تم الحفظ ✅');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _forget(Map<String, dynamic> p) async {
    if (!await confirmDialog(context, 'ينسى ${p['display_name'] ?? ''}؟', 'تنمسح كل الملاحظات اللي يتذكرها المساعد عن هذا الشخص.',
        ok: 'امسح', danger: true)) {
      return;
    }
    try {
      await supa.rpc('ai_person_forget', params: {'p_user': p['user_id']});
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: Text('ذاكرة المساعد 🧠 ${list == null ? '' : '(${list.length})'}')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Text(
                    'المساعد يقرا حساب كل شخص يراسلك (البايو ومنشوراته العامة وتعليقاته)، ويكتب ملاحظات قصيرة بعد كل محادثة '
                    'حتى يتذكره ويكمل وياه من وين وكفوا. الملاحظات خاصة بالرسائل بس، وما تطلع بالتعليقات العامة أبدًا.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'دوّر بالاسم'),
                  onSubmitted: (v) {
                    _q = v.trim();
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(child: Text('بعد ما أحد يراسلك والمساعد يرد عليه، يطلع هنا.')),
                  ),
                for (final p in list)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          GestureDetector(
                            onTap: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: '${p['user_id']}'))),
                            child: Avatar(url: p['avatar_url'] as String?, name: '${p['display_name'] ?? ''}', size: 42),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${p['display_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('@${p['username'] ?? ''} · ${p['chats'] ?? 0} رد · ${_ago(p['last_chat_at'] as String?)}',
                                  style: const TextStyle(fontSize: 12)),
                            ]),
                          ),
                          IconButton(
                              tooltip: 'تعديل', icon: const Icon(Icons.edit_note_rounded), onPressed: () => _edit(p)),
                          IconButton(
                            tooltip: 'ينسى',
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                            onPressed: () => _forget(p),
                          ),
                        ]),
                        if ('${p['owner_note'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('📝 منك: ${p['owner_note']}', style: const TextStyle(fontSize: 13)),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          '${p['notes'] ?? ''}'.isEmpty ? 'بعده ما كتب ملاحظات (تنكتب بعد ما تهدأ المحادثة).' : '${p['notes']}',
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
    );
  }
}
