import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../profile/profile_screens.dart';

const _statusText = {
  'new': ('جديد', Icons.fiber_new_rounded, Colors.blue),
  'accepted': ('مقبول — راح ينضاف', Icons.thumb_up_alt_rounded, Colors.teal),
  'done': ('صار بالتطبيق ✅', Icons.check_circle_rounded, Colors.green),
  'rejected': ('ما راح ينضاف حاليًا', Icons.do_not_disturb_on_rounded, Colors.grey),
};

/// اقتراحات الميزات: المستخدم يكتب اقتراحه ويتابع حالته، والمالك يشوف الكل ويقبل/يرفض.
class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key});
  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  final _text = TextEditingController();
  List<Map<String, dynamic>>? _items;
  String? _filter; // للمالك
  bool _sending = false;

  bool get _owner => context.read<SessionProvider>().profile?.isOwner ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_owner) _filter = 'new';
      _load();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('suggestions_list', params: {'p_status': _owner ? _filter : null});
      final l = (r as List).map((e) => (e as Map).cast<String, dynamic>()).toList();
      if (mounted) setState(() => _items = l);
    } catch (e) {
      if (mounted) {
        setState(() => _items = []);
        showSnack(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.length < 3) {
      showSnack(context, 'اكتب اقتراحك بشكل أوضح', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await supa.rpc('suggest_feature', params: {'p_text': t});
      _text.clear();
      FocusScope.of(context).unfocus();
      if (mounted) showSnack(context, 'وصل اقتراحك لمالك التطبيق 💡 شكرًا إلك');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> s, String status) async {
    String note = '';
    if (status != 'new') {
      final r = await promptText(context, 'ملاحظة لصاحب الاقتراح (اختياري)', hint: 'مثلاً: راح تنضاف بالتحديث الجاي', maxLines: 3, ok: 'تم');
      if (r == null) return;
      note = r;
    }
    try {
      await supa.rpc('suggestion_set_status', params: {'p_id': s['id'], 'p_status': status, 'p_note': note});
      if (mounted) showSnack(context, 'تم، ووصل إشعار لصاحب الاقتراح');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = context.watch<SessionProvider>().profile?.isOwner ?? false;
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(owner ? 'اقتراحات المستخدمين 💡' : 'اقترح ميزة 💡')),
      body: Column(children: [
        if (!owner)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('شنو الميزة اللي تتمنى نضيفها للتطبيق؟ اقتراحك يوصل مباشرة لمالك التطبيق.',
                  style: TextStyle(fontSize: 13.5)),
              const SizedBox(height: 8),
              TextField(
                controller: _text,
                minLines: 3,
                maxLines: 6,
                maxLength: 1000,
                decoration: const InputDecoration(hintText: 'مثلاً: أريد أكدر أثبّت محادثة بالأعلى...'),
              ),
              FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: const Text('إرسال الاقتراح'),
              ),
              const SizedBox(height: 10),
              const Text('اقتراحاتي', style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(children: [
              for (final f in [null, 'new', 'accepted', 'done', 'rejected'])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text(f == null ? 'الكل' : _statusText[f]!.$1.split(' ').first),
                    selected: _filter == f,
                    onSelected: (_) {
                      setState(() {
                        _filter = f;
                        _items = null;
                      });
                      _load();
                    },
                  ),
                ),
            ]),
          ),
        Expanded(
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? Center(child: Text(owner ? 'ماكو اقتراحات هنا' : 'بعدك ما اقترحت شي'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _tile(items[i], owner),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _tile(Map<String, dynamic> s, bool owner) {
    final st = _statusText[s['status']] ?? _statusText['new']!;
    final u = (s['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final at = DateTime.tryParse('${s['created_at']}')?.toLocal();
    final note = (s['owner_note'] ?? '') as String;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (owner)
            InkWell(
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: u['id'] as String))),
              child: Row(children: [
                Avatar(url: u['avatar_url'] as String?, name: (u['display_name'] ?? '') as String, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${u['display_name'] ?? ''}  @${u['username'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          if (owner) const SizedBox(height: 8),
          SelectableText((s['content'] ?? '') as String, style: const TextStyle(fontSize: 15, height: 1.5)),
          const SizedBox(height: 8),
          Row(children: [
            Icon(st.$2, size: 16, color: st.$3),
            const SizedBox(width: 4),
            Text(st.$1, style: TextStyle(color: st.$3, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (at != null) Text(Fmt.chatListTime(at), style: const TextStyle(fontSize: 11.5)),
          ]),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('رد المالك: $note', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
            ),
          if (owner)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                if (s['status'] != 'accepted')
                  OutlinedButton.icon(
                      onPressed: () => _setStatus(s, 'accepted'),
                      icon: const Icon(Icons.thumb_up_alt_rounded, size: 18),
                      label: const Text('قبول')),
                if (s['status'] != 'done')
                  FilledButton.icon(
                      onPressed: () => _setStatus(s, 'done'),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('تمت إضافتها')),
                if (s['status'] != 'rejected')
                  TextButton(onPressed: () => _setStatus(s, 'rejected'), child: const Text('رفض')),
              ]),
            ),
        ]),
      ),
    );
  }
}
