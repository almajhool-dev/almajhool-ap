import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// حماية الشاشة: تصوير وتسجيل الشاشة ممنوع لكل المستخدمين، ومسموح لمالك التطبيق بس.
class ScreenGuard {
  ScreenGuard._();
  static const _ch = MethodChannel('almajhool/screen');
  static bool? _last;

  static Future<void> allowCapture(bool on) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_last == on) return;
    _last = on;
    try {
      await _ch.invokeMethod('allowCapture', {'on': on});
    } catch (_) {
      _last = null;
    }
  }
}
