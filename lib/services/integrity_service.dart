import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// فحص سلامة التطبيق: هل هذه النسخة موقّعة بمفتاحنا الرسمي؟
/// أي نسخة يتم تفكيكها وتعديلها وإعادة توقيعها بمفتاح آخر تُرفض وتتوقف.
class IntegrityService {
  IntegrityService._();
  static const _ch = MethodChannel('almajhool/integrity');

  // بصمة شهادة التوقيع الرسمية (SHA-256)
  static const _official = '17D4601EF46777344D7F96E4A0BDE739125B2B024CBFF483160A2184FC523524';
  // المفتاح الجديد السري (من الإصدار 53). أندرويد 9 فما فوق يشوفه، فنشترطه هناك.
  static const _official2 = '22241941F8C8FA757AD6F545D21B1376EC4D75800C764B58846DB017270813AD';

  static bool tampered = false;
  static bool v2Missing = false;

  static Future<void> check() async {
    if (!kReleaseMode || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final r = await _ch.invokeMethod<List<dynamic>>('sig').timeout(const Duration(seconds: 5));
      final sigs = (r ?? const []).map((e) => '$e'.toUpperCase()).toList();
      // لا نحكم إلا إذا قرأنا التوقيع فعلًا (تجنبًا لأي خطأ على أجهزة نادرة)
      if (sigs.isNotEmpty && !sigs.contains(_official)) tampered = true;
      // نسخة موقّعة بالمفتاح القديم وحده (مزوّرة) على أندرويد 9+: لازم يكون المفتاح الجديد موجود
      if (sigs.isNotEmpty && !tampered) {
        int sdk = 0;
        try {
          sdk = await _ch.invokeMethod<int>('sdk') ?? 0;
        } catch (_) {}
        // مرحلة أولى: تبليغ فقط (حتى نتأكد ما يصير حظر غلط على أي جهاز)
        if (sdk >= 28 && !sigs.contains(_official2)) v2Missing = true;
      }
    } catch (_) {}
  }
}
