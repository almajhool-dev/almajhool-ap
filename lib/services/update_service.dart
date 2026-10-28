import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core_services.dart';

/// بصمة SHA-256 لملف (تنحسب بخيط منفصل حتى ما تعلّك الواجهة)
String sha256OfFile(String path) {
  final d = SHA256Digest();
  final raf = File(path).openSync();
  try {
    final buf = Uint8List(1 << 20);
    while (true) {
      final n = raf.readIntoSync(buf);
      if (n <= 0) break;
      d.update(buf, 0, n);
    }
  } finally {
    raf.closeSync();
  }
  final out = Uint8List(d.digestSize);
  d.doFinal(out, 0);
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// بصمة صالحة (64 حرف hex) أو null
String? _validSha(Object? v) {
  final s = (v ?? '').toString().trim().toLowerCase();
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(s) ? s : null;
}

/// تحديث التطبيق من داخل التطبيق: يتحقق من آخر إصدار على GitHub،
/// ينزّله ويفتح شاشة التثبيت مباشرة (بدون متصفح).
class UpdateService {
  UpdateService._();

  /// رقم البناء الحالي (يُحقن أثناء البناء).
  static const currentBuild = int.fromEnvironment('APP_BUILD', defaultValue: 0);
  static String get currentVersion => currentBuild == 0 ? '1.0' : '1.0.$currentBuild';

  static const _api = 'https://api.github.com/repos/almajhool-dev/almajhool-ap/releases/latest';
  static bool _shownThisRun = false;

  /// يرجع (رقم البناء، رابط التحميل، الملاحظات، البصمة) لآخر إصدار، أو null.
  /// البصمة بس من سيرفر التطبيق (مربوطة بنفس الرابط بالضبط)؛ الطرق البديلة بدون بصمة.
  static Future<({int build, String url, String notes, String? sha256})?> latest() async {
    // 1) من سيرفر التطبيق (سريع وما يتقيد بعدد الطلبات مثل GitHub)
    try {
      final r = await supa.rpc('latest_release').timeout(const Duration(seconds: 10));
      if (r is Map && r['build'] != null && r['url'] != null) {
        return (
          build: (r['build'] as num).toInt(),
          url: r['url'] as String,
          notes: (r['notes'] ?? '') as String,
          sha256: _validSha(r['sha256']),
        );
      }
    } catch (_) {}
    // 2) من GitHub مباشرة
    try {
      final r = await http
          .get(Uri.parse(_api), headers: {'Accept': 'application/vnd.github+json'})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '') as String;
      final build = int.tryParse(tag.split('.').last) ?? 0;
      // نختار النسخة الأصغر المناسبة لمعالج الجهاز (تنزيل أسرع)، وإلا النسخة الشاملة
      var abis = <String>[];
      try {
        abis = ((await const MethodChannel('almajhool/integrity').invokeMethod<List<dynamic>>('abis')) ?? const [])
            .map((e) => '$e')
            .toList();
      } catch (_) {}
      final want = abis.isEmpty
          ? null
          : abis.first.contains('arm64')
              ? 'almajhool-arm64.apk'
              : abis.first.contains('armeabi')
                  ? 'almajhool-armv7.apk'
                  : null;
      String? url, universal;
      for (final a in (j['assets'] as List? ?? const [])) {
        final name = (a['name'] ?? '') as String;
        final u = a['browser_download_url'] as String?;
        if (name == want) url = u;
        if (name == 'almajhool-app.apk') universal = u;
      }
      url ??= universal;
      if (url == null || build == 0) return null;
      return (build: build, url: url, notes: (j['body'] ?? '') as String, sha256: null);
    } catch (_) {}
    // 3) صفحة آخر إصدار (تحويل) — تشتغل حتى لو API مقيّد
    try {
      final c = http.Client();
      final req = http.Request('GET', Uri.parse('https://github.com/almajhool-dev/almajhool-ap/releases/latest'))
        ..followRedirects = false;
      final res = await c.send(req).timeout(const Duration(seconds: 12));
      final loc = res.headers['location'] ?? '';
      c.close();
      final m = RegExp(r'/tag/v1\.0\.(\d+)').firstMatch(loc);
      if (m != null) {
        final b = int.parse(m.group(1)!);
        return (
          build: b,
          url: 'https://github.com/almajhool-dev/almajhool-ap/releases/download/v1.0.$b/almajhool-app.apk',
          notes: '',
          sha256: null,
        );
      }
    } catch (_) {}
    return null;
  }

  /// فحص تلقائي عند فتح التطبيق (مرة واحدة لكل تشغيل).
  static Future<void> autoCheck(BuildContext? Function() ctx) async {
    if (kIsWeb) return; // نسخة الآيفون (الويب) تتحدث وحدها
    if (_shownThisRun || currentBuild == 0) return;
    final l = await latest();
    if (l == null || l.build <= currentBuild) return;
    final c = ctx();
    if (c == null || !c.mounted) return;
    _shownThisRun = true;
    await showUpdateDialog(c, l.url, l.build, sha256: l.sha256);
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
    await showUpdateDialog(context, l.url, l.build, sha256: l.sha256);
  }

  static Future<void> showUpdateDialog(BuildContext context, String url, int build, {String? sha256}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(url: url, build: build, sha256: sha256),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final String url;
  final int build;

  /// البصمة الرقمية المتوقعة للملف (من السيرفر) — أي ملف ما يطابقها ما ينثبّت
  final String? sha256;
  const _UpdateDialog({required this.url, required this.build, this.sha256});
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

  bool _fastFailed = false;

  void _start() {
    _tries++;
    setState(() {
      _working = true;
      _failed = false;
      _progress = 0;
      _msg = 'جارٍ التنزيل...';
    });
    if (!_fastFailed) {
      _fast();
      return;
    }
    _slow();
  }

  /// تنزيل سريع: نقسم الملف لأجزاء وننزلها بنفس الوقت (أسرع بكثير على النت البعيد)، ثم نثبّت.
  Future<void> _fast() async {
    try {
      final dir = Directory('${(await getApplicationSupportDirectory()).path}/ota_update');
      await dir.create(recursive: true);
      final file = File('${dir.path}/almajhool-fast.apk');
      final sw = Stopwatch()..start();
      await FastDownloader.download(widget.url, file, (got, total) {
        if (!mounted) return;
        final secs = sw.elapsedMilliseconds / 1000;
        final speed = secs > 0 ? got / secs / (1024 * 1024) : 0;
        setState(() {
          _progress = total > 0 ? got / total : null;
          _msg = 'جارٍ التنزيل... ${(got / (1024 * 1024)).toStringAsFixed(1)} / ${(total / (1024 * 1024)).toStringAsFixed(1)} ميگا'
              ' (${speed.toStringAsFixed(1)} ميگا/ثانية)';
        });
      });
      if (!mounted) return;
      // نتأكد من البصمة الرقمية قبل التثبيت: ملف منعدل أو ناقص ينرفض وينحذف
      final want = widget.sha256;
      if (want != null) {
        setState(() => _msg = 'جارٍ التحقق من سلامة التحديث...');
        final got = await compute(sha256OfFile, file.path);
        if (got != want) {
          try {
            await file.delete();
          } catch (_) {}
          throw Exception('checksum mismatch');
        }
        if (!mounted) return;
      }
      setState(() {
        _progress = 1;
        _msg = 'اضغط «تثبيت» أو «تحديث» في الشاشة التي ظهرت';
      });
      final r = await const MethodChannel('almajhool/integrity').invokeMethod<String>('installApk', {'path': file.path});
      if (!mounted) return;
      if (r == 'need_permission') {
        setState(() {
          _working = false;
          _msg = 'اسمح للتطبيق بتثبيت التحديثات من الشاشة اللي انفتحت، ثم ارجع واضغط «إعادة المحاولة»';
        });
      } else if (r != 'ok') {
        throw Exception('install $r');
      } else {
        setState(() => _working = false);
      }
    } catch (e) {
      try {
        final m = 'b${UpdateService.currentBuild} fast_update_fail: ${'$e'.split('\n').first}';
        supa.rpc('client_log', params: {'p_info': m.length > 500 ? m.substring(0, 500) : m}).catchError((_) => null);
      } catch (_) {}
      // نرجع للطريقة العادية
      _fastFailed = true;
      if (mounted) _slow();
    }
  }

  void _slow() {
    try {
      // نفس فحص البصمة بالطريقة العادية (المكتبة ترفض الملف إذا ما طابق)
      OtaUpdate().execute(widget.url, destinationFilename: 'almajhool-update.apk', sha256checksum: widget.sha256).listen(
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


/// تنزيل متوازي بأجزاء (Range requests) مع إعادة المحاولة لكل جزء.
class FastDownloader {
  static const _parts = 10;

  static Future<void> download(String url, File out, void Function(int got, int total) onProgress) async {
    final client = http.Client();
    try {
      // نتبع التحويل يدويًا للرابط النهائي (GitHub يحوّل لخادم التنزيل)
      var u = Uri.parse(url);
      var total = 0;
      for (var i = 0; i < 6; i++) {
        final req = http.Request('GET', u)
          ..followRedirects = false
          ..headers['Range'] = 'bytes=0-0';
        final res = await client.send(req).timeout(const Duration(seconds: 20));
        await res.stream.drain<void>();
        final loc = res.headers['location'];
        if (res.statusCode >= 300 && res.statusCode < 400 && loc != null) {
          u = u.resolve(loc);
          continue;
        }
        if (res.statusCode != 206) throw Exception('probe ${res.statusCode}');
        // Content-Range: bytes 0-0/12345
        total = int.tryParse((res.headers['content-range'] ?? '').split('/').last) ?? 0;
        break;
      }
      if (total < 1024 * 1024) throw Exception('no ranges');

      final raf = await out.open(mode: FileMode.write);
      await raf.truncate(total);
      final got = List<int>.filled(_parts, 0);
      final size = (total / _parts).ceil();
      var lock = Future<void>.value();
      // تحديث شريط التقدم 6 مرات بالثانية بس (التحديث مع كل قطعة كان يبطّئ التنزيل نفسه)
      var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
      void report({bool force = false}) {
        final now = DateTime.now();
        if (!force && now.difference(lastReport).inMilliseconds < 160) return;
        lastReport = now;
        onProgress(got.fold(0, (a, b) => a + b), total);
      }

      Future<void> part(int i) async {
        final start = i * size;
        final end = (start + size > total ? total : start + size) - 1;
        if (start > end) return;
        for (var attempt = 0; attempt < 4; attempt++) {
          final from = start + got[i];
          if (from > end) return;
          try {
            final req = http.Request('GET', u)..headers['Range'] = 'bytes=$from-$end';
            final res = await client.send(req).timeout(const Duration(seconds: 30));
            if (res.statusCode != 206) throw Exception('range ${res.statusCode}');
            var pos = from;
            // نجمع القطع الصغيرة ونكتبها دفعات كبيرة (أسرع بكثير على الهاتف)
            var buf = BytesBuilder(copy: false);
            var bufAt = pos;
            void flush() {
              if (buf.isEmpty) return;
              final data = buf.takeBytes();
              final at = bufAt;
              bufAt += data.length;
              // الكتابة بالتسلسل حتى ما تتداخل الأجزاء على نفس الملف
              lock = lock.then((_) async {
                await raf.setPosition(at);
                await raf.writeFrom(data);
              });
            }
            try {
              await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
                pos += chunk.length;
                buf.add(chunk);
                if (buf.length >= 512 * 1024) flush();
                got[i] += chunk.length;
                report();
              }
            } finally {
              flush();
            }
            await lock;
            if (start + got[i] > end) return;
          } catch (_) {
            await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
          }
        }
        throw Exception('part $i failed');
      }

      try {
        await Future.wait([for (var i = 0; i < _parts; i++) part(i)]);
        await lock;
        report(force: true);
      } finally {
        await raf.close();
      }
      if (await out.length() != total || got.fold<int>(0, (a, b) => a + b) < total) {
        throw Exception('incomplete');
      }
    } finally {
      client.close();
    }
  }
}
