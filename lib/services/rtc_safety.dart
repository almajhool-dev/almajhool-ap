import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:shared_preferences/shared_preferences.dart';

/// حماية تلقائية لبعض الأجهزة اللي ينهار عليها فك الفيديو (مثل بعض أجهزة MediaTek/TECNO):
/// إذا انهار التطبيق وهو داخل بث، المرة الجاية يشتغل البث بمفكّك برمجي آمن بدل مفكّك العتاد.
class RtcSafety {
  RtcSafety._();
  static const _kActive = 'rtc_active';
  static const _kLevel = 'rtc_safe_level';
  static String? pendingExit;
  static int level = 0;
  static SharedPreferences? _p;

  static Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
      pendingExit = await const MethodChannel('almajhool/integrity').invokeMethod<String>('lastExit');
      level = _p!.getInt(_kLevel) ?? 0;
      // أول تشغيل لهذه الحماية: إذا الجهاز انهار أكثر من مرة اليوم نفعّل الوضع الآمن مباشرة
      if (!(_p!.getBool('rtc_seeded') ?? false)) {
        await _p!.setBool('rtc_seeded', true);
        final n = await const MethodChannel('almajhool/integrity').invokeMethod<int>('recentNativeCrashes') ?? 0;
        if (n >= 2 && level < 1) {
          level = 1;
          await _p!.setInt(_kLevel, 1);
        }
      }
      final wasInRtc = _p!.getBool(_kActive) ?? false;
      final crashed = pendingExit != null &&
          (pendingExit!.contains('reason=5') || pendingExit!.contains('reason=4') || pendingExit!.contains('reason=6'));
      if (wasInRtc && crashed && level < 3) {
        // انهيار برسم الفيديو نفسه (libflutter) ما ينحل بتغيير المفكك → صوت فقط مباشرة
        level = pendingExit!.contains('libflutter') ? 3 : level + 1;
        await _p!.setInt(_kLevel, level);
      }
      // أجهزة انهارت حتى بالمفكك البرمجي: ننقلها للوضع الآمن الكامل
      if (level == 2 && !(_p!.getBool('rtc_seed3') ?? false)) {
        await _p!.setBool('rtc_seed3', true);
        final n = await const MethodChannel('almajhool/integrity').invokeMethod<int>('recentNativeCrashes') ?? 0;
        if (n >= 1) {
          level = 3;
          await _p!.setInt(_kLevel, 3);
        }
      }
      await _p!.setBool(_kActive, false);
      if (level >= 2) {
        await rtc.WebRTC.initialize(options: {'forceSWCodec': true});
      } else if (level == 1) {
        await rtc.WebRTC.initialize(options: {
          'forceSWCodecList': ['VP8', 'VP9', 'AV1'],
        });
      }
    } catch (_) {}
  }

  /// تُستدعى عند الدخول/الخروج من بث (لمعرفة إن كان الانهيار بسبب البث).
  static void active(bool v) {
    try {
      _p?.setBool(_kActive, v);
    } catch (_) {}
  }

  /// المستوى 3 (أجهزة ينهار عليها عرض الفيديو): البث يشتغل بالصوت فقط بدون فك أو رسم فيديو،
  /// فما يطلع المستخدم من التطبيق أبدًا. المعاينة بالرئيسية تبقى بالصوت والصورة الثابتة.
  static bool get audioOnly => level >= 3;
  static bool get previewAllowed => true;
}
