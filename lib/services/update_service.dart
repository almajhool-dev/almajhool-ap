import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core_services.dart';

/// تحديث التطبيق من داخل التطبيق: يتحقق من آخر إصدار على GitHub،
/// ينزّله ويفتح شاشة التثبيت مباشرة (بدون متصفح).
class UpdateService {
  UpdateService._();

  /// رقم البناء الحالي (يُحقن أثناء البناء).
  static const currentBuild = int.fromEnvironment('APP_BUILD', defaultValue: 0);
  static String get currentVersion => currentBuild == 0 ? '1.0' : '1.0.$currentBuild';

  static const _api = 'https://api.github.com/repos/almajhool-dev/almajhool-ap/releases/latest';
  static bool _shownThisRun = false;

  /// يرجع (رقم البناء، رابط التحميل، الملاحظات) لآخر إصدار، أو null.
  static Future<({int build, String url, String notes})?> latest() async {
    try {
      final r = await http
          .get(Uri.parse(_api), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '') as String;
      final build = int.tryParse(tag.split('.').last) ?? 0;
      String? url;
      for (final a in (j['assets'] as List? ?? const [])) {
        final name = (a['name'] ?? '') as String;
        if (name.endsWith('.apk')) url = a['browser_download_url'] as String?;
      }
      if (url == null || build == 0) return null;
      return (build: build, url: url, notes: (j['body'] ?? '') as String);
    } catch (_) {
      return null;
    }
  }

  /// فحص تلقائي عند فتح التطبيق (مرة واحدة لكل تشغيل).
  static Future<void> autoCheck(BuildContext? Function() ctx) async {
    if (_shownThisRun || currentBuild == 0) return;
    final l = await latest();
    if (l == null || l.build <= currentBuild) return;
    final c = ctx();
    if (c == null || !c.mounted) return;
    _shownThisRun = true;
    await showUpdateDialog(c, l.url, l.build);
  }

  /// فحص يدوي من الإعدادات.
  static Future<void> manualCheck(BuildContext context) async {
    final l = await latest();
    if (!context.mounted) return;
    if (l == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر التحقق، تأكد من الإنترنت')));
      return;
    }
    if (l.build <= currentBuild) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لديك آخر إصدار ($currentVersion) ✅')));
      return;
    }
    await showUpdateDialog(context, l.url, l.build);
  }

  static Future<void> showUpdateDialog(BuildContext context, String url, int build) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(url: url, build: build),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final String url;
  final int build;
  const _UpdateDialog({required this.url, required this.build});
  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _working = false;
  bool _failed = false;
  int _tries = 0;
  double? _progress;
  String? _msg;

  void _fail(String why) {
    // نعيد المحاولة تلقائيًا مرة وحدة، وبعدها نعرض طرق بديلة للتحميل
    try {
      supa.rpc('client_log', params: {'p_info': 'b${UpdateService.currentBuild} update_fail: $why'}).catchError((_) => null);
    } catch (_) {}
    if (_tries < 2 && mounted) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _start();
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _failed = true;
      _progress = null;
      _msg = 'ما گدرنا ننزّل التحديث داخل التطبيق ($why).\nنزّله من المتصفح أو من قناة التلكرام 👇';
    });
  }

  Future<void> _openExternal(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _start() {
    _tries++;
    setState(() {
      _working = true;
      _failed = false;
      _progress = 0;
      _msg = 'جارٍ التنزيل...';
    });
    try {
      OtaUpdate().execute(widget.url, destinationFilename: 'almajhool-update.apk').listen(
        (e) {
          if (!mounted) return;
          setState(() {
            switch (e.status) {
              case OtaStatus.DOWNLOADING:
                _progress = (double.tryParse(e.value ?? '') ?? 0) / 100;
                _msg = 'جارٍ التنزيل... ${e.value ?? 0}%';
                break;
              case OtaStatus.INSTALLING:
              case OtaStatus.INSTALLATION_DONE:
                _progress = 1;
                _msg = 'اضغط «تثبيت» أو «تحديث» في الشاشة التي ظهرت';
                _working = false;
                break;
              case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                _msg = 'اسمح للتطبيق بتثبيت التحديثات من الإعدادات ثم أعد المحاولة';
                _working = false;
                break;
              default:
                Future.microtask(() => _fail('${e.status.name} ${e.value ?? ''}'.trim()));
            }
          });
        },
        onError: (e) => _fail('$e'.split('\n').first),
      );
    } catch (e) {
      _fail('$e'.split('\n').first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تحديث جديد متوفر 🎉'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('الإصدار 1.0.${widget.build} متوفر الآن (لديك ${UpdateService.currentVersion}).'),
          const SizedBox(height: 6),
          const Text('يتضمن تحسينات وإصلاحات. التحديث سريع ولا تُحذف بياناتك.', style: TextStyle(fontSize: 13)),
          if (_progress != null) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          ],
          if (_msg != null) ...[
            const SizedBox(height: 8),
            Text(_msg!, style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
      actions: [
        if (_failed) ...[
          TextButton.icon(
            onPressed: () => _openExternal(widget.url),
            icon: const Icon(Icons.open_in_browser_rounded),
            label: const Text('من المتصفح'),
          ),
          TextButton.icon(
            onPressed: () => _openExternal('https://t.me/ikd5n'),
            icon: const Icon(Icons.telegram),
            label: const Text('تلكرام'),
          ),
        ],
        if (!_working)
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('لاحقًا')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(110, 40)),
          onPressed: _working ? null : _start,
          child: Text(_msg == null ? 'تحديث الآن' : 'إعادة المحاولة'),
        ),
      ],
    );
  }
}
