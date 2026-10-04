import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'core_services.dart';
import 'update_service.dart';

/// يرسل أسباب الأعطال للمطوّر (بدون أي بيانات شخصية) حتى تُصلح بسرعة.
class CrashReporter {
  CrashReporter._();
  static int _sent = 0;

  static void install() {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      _send('flutter: ${d.exceptionAsString()} | ${d.stack.toString().split('\n').take(6).join(' / ')}');
      prev?.call(d);
    };
    PlatformDispatcher.instance.onError = (e, st) {
      _send('dart: $e | ${st.toString().split('\n').take(6).join(' / ')}');
      return false;
    };
  }

  /// انهيار من الجزء الأصلي (Android) حُفظ قبل إغلاق التطبيق.
  static Future<void> sendPendingNativeCrash() async {
    try {
      final exit = await const MethodChannel('almajhool/integrity').invokeMethod<String>('lastExit');
      if (exit != null && exit.isNotEmpty) _send('exit: $exit');
    } catch (_) {}
    final c = CacheService.getString('last_crash');
    if (c == null || c.isEmpty) return;
    await CacheService.setString('last_crash', '');
    _send('native: $c');
  }

  static void _send(String info) {
    if (_sent++ > 20) return;
    try {
      final t = 'b${UpdateService.currentBuild} $info';
      supa.rpc('client_log', params: {'p_info': t.length > 590 ? t.substring(0, 590) : t}).catchError((_) => null);
    } catch (_) {}
  }
}
