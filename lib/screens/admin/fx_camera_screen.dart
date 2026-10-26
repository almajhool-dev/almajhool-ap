import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../providers/providers.dart';

/// مؤثرات الكاميرا (للمالك بس): وضع الشبح 👻 والوجه النيون 🧬.
/// الصفحة نفسها (assets/fx/fx.html) تشتغل بالهاتف بذكاء MediaPipe، والتطبيق يحفظ الصور والفيديوهات بالاستوديو.
class FxCameraScreen extends StatefulWidget {
  final String mode; // ghost | neon
  const FxCameraScreen({super.key, this.mode = 'ghost'});
  @override
  State<FxCameraScreen> createState() => _FxCameraScreenState();
}

class _Incoming {
  final String kind, ext;
  final int n;
  final Map<int, Uint8List> parts = {};
  _Incoming(this.kind, this.ext, this.n);
}

class _FxCameraScreenState extends State<FxCameraScreen> with WidgetsBindingObserver {
  static const _base = 'https://appassets.androidplatform.net/fx/';
  WebViewController? _web;
  String? _error;
  final Map<String, _Incoming> _incoming = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // الكاميرا تتطفّى أول ما يطلع من التطبيق، وترجع لما يرجع
    final w = _web;
    if (w == null) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      w.runJavaScript('window.fxPause && fxPause()').catchError((_) {});
    } else if (state == AppLifecycleState.resumed) {
      w.runJavaScript('window.fxResume && fxResume()').catchError((_) {});
    }
  }

  Future<void> _start() async {
    final me = context.read<SessionProvider>().profile;
    if (!(me?.isOwner ?? false)) {
      setState(() => _error = 'هذي الميزة لمالك التطبيق بس');
      return;
    }
    final cam = await Permission.camera.request();
    await Permission.microphone.request();
    if (!cam.isGranted) {
      if (mounted) setState(() => _error = 'اسمح للتطبيق يستخدم الكاميرا من الإعدادات وارجع جرّب');
      return;
    }
    final html = (await rootBundle.loadString('assets/fx/fx.html')).replaceAll('__FX_MODE__', widget.mode);
    final web = WebViewController(onPermissionRequest: (r) => r.grant())
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('VYFRI', onMessageReceived: (m) => _onMessage(m.message))
      ..setNavigationDelegate(NavigationDelegate(
        // الصفحة ما تطلع لأي مكان ثاني
        onNavigationRequest: (r) =>
            r.url.startsWith(_base) || r.url.startsWith('about:') ? NavigationDecision.navigate : NavigationDecision.prevent,
      ));
    final pl = web.platform;
    if (pl is AndroidWebViewController) await pl.setMediaPlaybackRequiresUserGesture(false);
    await web.loadHtmlString(html, baseUrl: _base);
    if (mounted) setState(() => _web = web);
  }

  void _toast(String t) {
    final w = _web;
    if (w == null) return;
    w.runJavaScript('window.fxToast && fxToast(${jsonEncode(t)}, 2600)').catchError((_) {});
  }

  void _onMessage(String raw) {
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (m['t']) {
      case 'close':
        if (mounted) Navigator.maybePop(context);
      case 'begin':
        final n = (m['n'] as num?)?.toInt() ?? 0;
        if (n <= 0 || n > 2000 || _incoming.length > 4) return;
        _incoming['${m['id']}'] = _Incoming('${m['kind']}', '${m['ext']}', n);
      case 'part':
        final f = _incoming['${m['id']}'];
        final i = (m['i'] as num?)?.toInt() ?? -1;
        if (f == null || i < 0 || i >= f.n) return;
        try {
          f.parts[i] = base64Decode('${m['d']}');
        } catch (_) {}
      case 'end':
        final f = _incoming.remove('${m['id']}');
        if (f != null) _save(f);
    }
  }

  Future<void> _save(_Incoming f) async {
    try {
      if (f.parts.length != f.n) throw Exception('incomplete');
      final b = BytesBuilder(copy: false);
      for (var i = 0; i < f.n; i++) {
        b.add(f.parts[i]!);
      }
      final bytes = b.takeBytes();
      if (!await Gal.hasAccess(toAlbum: true)) await Gal.requestAccess(toAlbum: true);
      final name = 'vyfri_fx_${DateTime.now().millisecondsSinceEpoch}';
      if (f.kind == 'photo') {
        await Gal.putImageBytes(bytes, album: 'VYFRI', name: name);
        _toast('✅ انحفظت الصورة بالاستوديو');
      } else {
        final ext = RegExp(r'^(mp4|webm)$').hasMatch(f.ext) ? f.ext : 'mp4';
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$name.$ext');
        await file.writeAsBytes(bytes, flush: true);
        await Gal.putVideo(file.path, album: 'VYFRI');
        try {
          await file.delete();
        } catch (_) {}
        _toast('✅ انحفظ الفيديو بالاستوديو — تكدر تنشره ريلز من التطبيق');
      }
    } catch (e) {
      _toast('ما گدرنا نحفظ — اسمح للتطبيق يحفظ بالصور وجرّب مرة ثانية');
    }
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 48),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => Navigator.maybePop(context), child: const Text('رجوع')),
                  ]),
                ),
              )
            : web == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: web),
      ),
    );
  }
}
