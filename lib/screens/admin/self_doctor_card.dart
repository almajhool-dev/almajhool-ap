import 'package:flutter/material.dart';

import '../../services/core_services.dart';
import '../../utils/helpers.dart';

typedef DoctorCall = Future<Map<String, dynamic>> Function();

/// أدوات مشتركة بين بطاقة الطبيب وشاشته
class _D {
  static int i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static Map<String, dynamic> m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static List<Map<String, dynamic>> l(dynamic v) => v is List ? v.map(m).toList() : <Map<String, dynamic>>[];

  static String ago(dynamic iso) {
    final t = DateTime.tryParse('${iso ?? ''}');
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'هسه';
    if (d.inMinutes < 60) return 'قبل ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'قبل ${d.inHours} ساعة';
    return 'قبل ${d.inDays} يوم';
  }

  // شكل كل حالة: سليم، صلّح لحاله، ينراد انتباه، يحتاجك، معلومة
  static (IconData, Color) look(String s) => switch (s) {
        'ok' => (Icons.check_circle_rounded, Colors.green),
        'fixed' => (Icons.build_circle_rounded, Colors.teal),
        'warn' => (Icons.error_rounded, Colors.orange),
        'alert' => (Icons.report_rounded, Colors.red),
        _ => (Icons.info_rounded, Colors.blueGrey),
      };

  static Future<Map<String, dynamic>> load(DoctorCall? f) async => f != null ? f() : m(await supa.rpc('doctor_report'));

  /// «افحص وصلّح هسه»: يشغّل الفحص الكامل ويطلع النتيجة برسالة
  static Future<void> runNow(BuildContext context, DoctorCall? f) async {
    final r = f != null ? await f() : m(await supa.rpc('doctor_run_now'));
    if (!context.mounted) return;
    final fixed = i(r['fixed']), alerts = i(r['alerts']);
    if (r['error'] != null) {
      showSnack(context, 'ما كمل الفحص: ${r['error']}', error: true);
    } else if (fixed == 0 && alerts == 0) {
      showSnack(context, 'فحصت كلشي: سليم ✅');
    } else {
      showSnack(context, 'خلص الفحص: صلّح $fixed، ويحتاجك $alerts');
    }
  }

  // سطر فحص: الحالة، الاسم (وتحته شرح قصير)، والقيمة
  static Widget row(BuildContext context, Map<String, dynamic> e) {
    final s = '${e['s'] ?? ''}';
    final (icon, color) = look(s);
    final hint = '${e['h'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['n'] ?? ''}', style: const TextStyle(fontSize: 13)),
            if (hint.isNotEmpty) Text(hint, style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          ]),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text('${e['v'] ?? ''}',
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w700, color: s == 'ok' || s == 'info' ? null : color)),
        ),
      ]),
    );
  }

  static Widget logEntry(BuildContext context, Map<String, dynamic> e) {
    final alert = e['action'] == 'alert';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(alert ? Icons.warning_amber_rounded : Icons.build_circle_rounded,
            size: 18, color: alert ? Colors.orange : Colors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e['detail'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
            Text('${alert ? 'يحتاجك' : 'صلّحها لحاله'} · ${ago(e['at'])}',
                style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          ]),
        ),
      ]),
    );
  }

  // حالة الطبيب الكلية (الأسوأ بآخر فحص)
  static (String, Color) status(Map<String, dynamic>? r) {
    if (r == null) return ('...', Colors.grey);
    final last = m(r['last']);
    if (last.isEmpty) return ('بعده ما فحص', Colors.grey);
    final alerts = i(last['alerts']);
    return switch ('${last['worst'] ?? ''}') {
      'alert' => ('يحتاجك ($alerts)', Colors.red),
      'warn' => ('ينراد انتباه', Colors.orange),
      'fixed' => ('صلّح لحاله ✓', Colors.teal),
      'ok' => ('كلشي سليم ✓', Colors.green),
      _ => alerts > 0 ? ('يحتاجك ($alerts)', Colors.orange) : ('كلشي سليم ✓', Colors.green),
    };
  }
}

/// «الطبيب الذاتي» (للمالك بس): الخادم يفحص كل شي بالتطبيق كل 5 دقايق على طول عمره ويصلّح لحاله
/// (مهام الخادم، الحماية، الصلاحيات، الأسرار، الملفات الخاصة)، واللي يحتاج تعديل كود يبلّغك بيه.
/// البطاقة تبين المشاكل بس، و«كل الفحوصات» تفتح الشاشة الكاملة.
class SelfDoctorCard extends StatefulWidget {
  /// للاختبار: بدل طلبات الخادم
  final DoctorCall? load;
  final DoctorCall? run;
  const SelfDoctorCard({super.key, this.load, this.run});

  @override
  State<SelfDoctorCard> createState() => _SelfDoctorCardState();
}

class _SelfDoctorCardState extends State<SelfDoctorCard> {
  Map<String, dynamic>? _report;
  String? _error;
  bool _busy = false;
  bool _showLog = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final r = await _D.load(widget.load);
      if (!mounted) return;
      setState(() {
        _report = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _runNow() async {
    setState(() => _busy = true);
    try {
      await _D.runNow(context, widget.run);
      await _reload();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // للتوافق مع الخادم القديم (قبل قائمة الفحوصات)
  List<Widget> _legacyChecks(Map<String, dynamic> c) {
    Widget row(String n, String v, bool ok) => _D.row(context, {'n': n, 'v': v, 's': ok ? 'ok' : 'warn'});
    final jobsOk = _D.i(c['jobs_ok']), jobsTotal = _D.i(c['jobs_total']);
    final upd = '${c['update'] ?? 'unknown'}';
    final guarded = _D.i(c['rls_fixed']) + _D.i(c['views_fixed']) + _D.i(c['perms_fixed']);
    final storage = '${c['storage'] ?? 'unknown'}';
    final failing = _D.i(c['cron_failing']), crashes = _D.i(c['crashes_1h']);
    return [
      row('مهام الخادم الأساسية', '$jobsOk/$jobsTotal شغّالة', jobsOk >= jobsTotal),
      row(
          'التحديث التلقائي للخادم',
          switch (upd) {
            'ok' => 'شغّال',
            'fail' => 'واگف بسبب خطأ',
            'paused' => 'موقوف منك',
            _ => 'بعده ما معروف',
          },
          upd != 'fail'),
      row('حماية الجداول والصلاحيات', guarded == 0 ? 'مضبوطة' : 'صلّح $guarded', true),
      row('ملفات المحادثات الخاصة', storage == 'fixed' ? 'رجّعها خاصة' : storage == 'ok' ? 'خاصة' : 'ما معروف',
          storage != 'unknown'),
      row('مهام تفشل بشكل متكرر', failing == 0 ? 'ماكو' : '$failing', failing == 0),
      row('انهيارات عند المستخدمين (آخر ساعة)', '$crashes', crashes < 5),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final last = _D.m(r?['last']);
    final hasRun = last.isNotEmpty;
    final list = _D.l(last['list']);
    final log = _D.l(r?['log']);
    final (status, color) = _D.status(r);
    int count(String s) => list.where((e) => e['s'] == s).length;
    final problems = list.where((e) => e['s'] == 'alert' || e['s'] == 'warn' || e['s'] == 'fixed').toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.health_and_safety_rounded, color: color),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('الطبيب الذاتي 🩺', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Chip(
              label: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 6),
          const Text(
              'الخادم يفحص كل شي بالتطبيق كل 5 دقايق، على طول، ويصلّح لحاله: مهام الخادم، الحماية، الصلاحيات، '
              'الأسرار والملفات الخاصة. واللي يحتاج تعديل بالكود يوصلك عنه إشعار.',
              style: TextStyle(fontSize: 12.5)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
            ),
          if (hasRun) ...[
            const SizedBox(height: 8),
            Text(
                'آخر فحص: ${_D.ago(last['at'])} · آخر 24 ساعة: صلّح ${_D.i(r?['fixed_24h'])}، ونبّهك ${_D.i(r?['alerts_24h'])}',
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            if (list.isEmpty)
              ..._legacyChecks(_D.m(last['checks']))
            else ...[
              Text(
                  '${list.length} فحص: ${count('ok')} سليم · ${count('fixed')} صلّحها · ${count('warn')} ينراد انتباه · '
                  '${count('alert')} يحتاجك',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              if (problems.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('ماكو أي مشكلة هسه ✓', style: TextStyle(fontSize: 13, color: Colors.green)),
                )
              else
                ...problems.take(6).map((e) => _D.row(context, e)),
            ],
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _runNow,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.health_and_safety_rounded),
            label: const Text('افحص وصلّح هسه'),
          ),
          if (list.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => SelfDoctorScreen(load: widget.load, run: widget.run)));
                _reload();
              },
              icon: const Icon(Icons.fact_check_rounded),
              label: Text('كل الفحوصات (${list.length})'),
            )
          else if (log.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => setState(() => _showLog = !_showLog),
              icon: Icon(_showLog ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text(_showLog ? 'إخفاء السجل' : 'السجل (${log.length})'),
            ),
            if (_showLog) ...log.map((e) => _D.logEntry(context, e)),
          ],
        ]),
      ),
    );
  }
}

/// الشاشة الكاملة: كل الفحوصات مجموعات (الخادم، الأمان، الإشعارات، التطبيق عند المستخدمين، البيانات والفلوس،
/// الطوابير)، صحة التطبيق يوم بيوم، والسجل — كلها بالعربي ومثل ما يرسلها الخادم (أي فحص جديد يطلع لحاله).
class SelfDoctorScreen extends StatefulWidget {
  final DoctorCall? load;
  final DoctorCall? run;
  const SelfDoctorScreen({super.key, this.load, this.run});

  @override
  State<SelfDoctorScreen> createState() => _SelfDoctorScreenState();
}

class _SelfDoctorScreenState extends State<SelfDoctorScreen> {
  Map<String, dynamic>? _r;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final r = await _D.load(widget.load);
      if (!mounted) return;
      setState(() {
        _r = r;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _runNow() async {
    setState(() => _busy = true);
    try {
      await _D.runNow(context, widget.run);
      await _reload();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );

  Widget _box(List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );

  // سطر يوم: أسوأ حالة باليوم + الأرقام
  Widget _day(Map<String, dynamic> d) {
    final worst = '${d['worst'] ?? 'ok'}';
    final (icon, color) = _D.look(worst);
    final t = DateTime.tryParse('${d['d'] ?? ''}');
    final label = switch (worst) { 'alert' => 'تنبيه', 'warn' => 'انتباه', 'fixed' => 'صلّح لحاله', _ => 'سليم' };
    final parts = <String>[
      label,
      'صلّح ${_D.i(d['fixed'])}',
      'تنبيهات ${_D.i(d['alerts'])}',
      'أكثر انهيارات بساعة ${_D.i(d['crashes'])}',
      'أجهزة ${_D.i(d['devices'])}',
      if (d['db_mb'] != null) '${_D.i(d['db_mb'])} ميگا',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        SizedBox(
            width: 48,
            child: Text(t == null ? '' : '${t.day}/${t.month}', style: const TextStyle(fontWeight: FontWeight.w700))),
        Expanded(child: Text(parts.join(' · '), style: const TextStyle(fontSize: 12))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الطبيب الذاتي 🩺'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), tooltip: 'تحديث')],
      ),
      body: r == null
          ? Center(child: _error != null ? Text(_error!, style: const TextStyle(color: Colors.red)) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: Builder(builder: (context) {
                final last = _D.m(r['last']);
                final list = _D.l(last['list']);
                final days = _D.l(r['days']);
                final log = _D.l(r['log']);
                final (status, color) = _D.status(r);
                final groups = <String, List<Map<String, dynamic>>>{};
                for (final e in list) {
                  groups.putIfAbsent('${e['g'] ?? 'أخرى'}', () => []).add(e);
                }
                final since = DateTime.tryParse('${r['since'] ?? ''}');
                return ListView(padding: const EdgeInsets.all(12), children: [
                  _box([
                    Row(children: [
                      Icon(Icons.health_and_safety_rounded, color: color, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(status, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: color))),
                    ]),
                    const SizedBox(height: 6),
                    Text('آخر فحص: ${_D.ago(last['at'])} · ${list.length} فحص · يفحص كل 5 دقايق على طول',
                        style: const TextStyle(fontSize: 12.5)),
                    if (since != null)
                      Text('يراقب صحة التطبيق من ${since.day}/${since.month}/${since.year}',
                          style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy ? null : _runNow,
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.health_and_safety_rounded),
                      label: const Text('افحص وصلّح هسه'),
                    ),
                  ]),
                  for (final g in groups.entries) ...[
                    _title(g.key),
                    _box(g.value.map((e) => _D.row(context, e)).toList()),
                  ],
                  if (days.isNotEmpty) ...[
                    _title('صحة التطبيق آخر ${days.length} يوم'),
                    _box(days.map(_day).toList()),
                  ],
                  if (log.isNotEmpty) ...[
                    _title('السجل (التصليحات والتنبيهات)'),
                    _box(log.map((e) => _D.logEntry(context, e)).toList()),
                  ],
                  const SizedBox(height: 24),
                ]);
              }),
            ),
    );
  }
}
