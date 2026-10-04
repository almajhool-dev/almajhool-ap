import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// فحص سلامة التطبيق: هل هذه النسخة موقّعة بمفتاحنا الرسمي؟
/// أي نسخة يتم تفكيكها وتعديلها وإعادة توقيعها بمفتاح آخر تُرفض وتتوقف.
class IntegrityService {
  IntegrityService._();
  static const _ch = MethodChannel('almajhool/integrity');

  // بصمة شهادة التوقيع الرسمية (SHA-256)
  static const _official = '17D4601EF46777344D7F96E4A0BDE739125B2B024CBFF483160A2184FC523524';

  static bool tampered = false;

  static Future<void> check() async {
    if (!kReleaseMode || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final r = await _ch.invokeMethod<List<dynamic>>('sig').timeout(const Duration(seconds: 5));
      final sigs = (r ?? const []).map((e) => '$e'.toUpperCase()).toList();
      // لا نحكم إلا إذا قرأنا التوقيع فعلًا (تجنبًا لأي خطأ على أجهزة نادرة)
      if (sigs.isNotEmpty && !sigs.contains(_official)) tampered = true;
    } catch (_) {}
  }
}
