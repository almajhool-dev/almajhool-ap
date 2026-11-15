import 'package:flutter/material.dart';

import '../../services/core_services.dart';
import '../../utils/helpers.dart';

/// «الطبيب الذاتي» (للمالك بس): الخادم يفحص نفسه كل 5 دقايق ويصلّح لحاله
/// (مهام الخادم، حماية الجداول، الصلاحيات، الملفات الخاصة)، واللي يحتاج تعديل كود يبلّغك بيه.
/// هنا تشوف آخر فحص وشنو صلّح وشنو يحتاجك، وتگدر تفحص هسه.
class SelfDoctorCard extends StatefulWidget {
  /// للاختبار: بدل طلبات الخادم
  final Future<Map<String, dynamic>> Function()? load;
  final Future<Map<String, dynamic>> Function()? run;
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

  static int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static String _ago(dynamic iso) {
    final t = DateTime.tryParse('${iso ?? ''}');
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'هسه';
    if (d.inMinutes < 60) return 'قبل ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'قبل ${d.inHours} ساعة';
    return 'قبل ${d.inDays} يوم';
  }

  Future<void> _reload() async {
    try {
      final load = widget.load ?? () async => _map(await supa.rpc('doctor_report'));
      final r = await load();
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
      final run = widget.run ?? () async => _map(await supa.rpc('doctor_run_now'));
      final r = await run();
      if (!mounted) return;
      final fixed = _int(r['fixed']), alerts = _int(r['alerts']);
      if (r['error'] != null) {
        showSnack(context, 'ما كمل الفحص: ${r['error']}', error: true);
      } else if (fixed == 0 && alerts == 0) {
        showSnack(context, 'فحصت كلشي: سليم ✅');
      } else {
        showSnack(context, 'خلص الفحص: صلّح $fixed، ويحتاجك $alerts');
      }
      await _reload();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // سطر بحالة كل فحص: ✓ سليم أو ⚠️ يحتاج انتباه
  Widget _row(String title, String value, {required bool ok}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded, size: 18, color: ok ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
          Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: ok ? null : Colors.orange)),
        ]),
      );

  List<Widget> _checks(Map<String, dynamic> c) {
    final jobsOk = _int(c['jobs_ok']), jobsTotal = _int(c['jobs_total']);
    final upd = '${c['update'] ?? 'unknown'}';
    final guarded = _int(c['rls_fixed']) + _int(c['views_fixed']) + _int(c['perms_fixed']);
    final storage = '${c['storage'] ?? 'unknown'}';
    final failing = _int(c['cron_failing']), crashes = _int(c['crashes_1h']);
    return [
      _row('مهام الخادم الأساسية', '$jobsOk/$jobsTotal شغّالة', ok: jobsOk >= jobsTotal),
      _row(
          'التحديث التلقائي للخادم',
          switch (upd) {
            'ok' => 'شغّال',
            'fail' => 'واگف بسبب خطأ',
            'paused' => 'موقوف منك',
            _ => 'بعده ما معروف',
          },
          ok: upd != 'fail'),
      _row('حماية الجداول والصلاحيات', guarded == 0 ? 'مضبوطة' : 'صلّح $guarded', ok: true),
      _row('ملفات المحادثات الخاصة', storage == 'fixed' ? 'رجّعها خاصة' : storage == 'ok' ? 'خاصة' : 'ما معروف',
          ok: storage != 'unknown'),
      _row('مهام تفشل بشكل متكرر', failing == 0 ? 'ماكو' : '$failing', ok: failing == 0),
      _row('انهيارات عند المستخدمين (آخر ساعة)', '$crashes', ok: crashes < 5),
    ];
  }

  Widget _logEntry(Map<String, dynamic> e) {
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
            Text('${alert ? 'يحتاجك' : 'صلّحها لحاله'} · ${_ago(e['at'])}',
                style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final last = _map(r?['last']);
    final hasRun = last.isNotEmpty;
    final alerts = _int(last['alerts']);
    final log = (r?['log'] is List ? r!['log'] as List : const []).map(_map).toList();
    final Color color = !hasRun ? Colors.grey : alerts > 0 ? Colors.orange : Colors.green;
    final String status = r == null
        ? '...'
        : !hasRun
            ? 'بعده ما فحص'
            : alerts > 0
                ? 'يحتاجك ($alerts)'
                : 'كلشي سليم ✓';
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
              'الخادم يفحص نفسه كل 5 دقايق ويصلّح لحاله: مهام الخادم، حماية الجداول، الصلاحيات والملفات الخاصة. '
              'واللي يحتاج تعديل بالكود (مثل انهيار جديد) يوصلك عنه إشعار.',
              style: TextStyle(fontSize: 12.5)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
            ),
          if (hasRun) ...[
            const SizedBox(height: 8),
            Text(
                'آخر فحص: ${_ago(last['at'])} · آخر 24 ساعة: صلّح ${_int(r?['fixed_24h'])}، ونبّهك ${_int(r?['alerts_24h'])}',
                style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            ..._checks(_map(last['checks'])),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _busy ? null : _runNow,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.health_and_safety_rounded),
            label: const Text('افحص وصلّح هسه'),
          ),
          if (log.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => setState(() => _showLog = !_showLog),
              icon: Icon(_showLog ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text(_showLog ? 'إخفاء السجل' : 'السجل (${log.length})'),
            ),
            if (_showLog) ...log.map(_logEntry),
          ],
        ]),
      ),
    );
  }
}
