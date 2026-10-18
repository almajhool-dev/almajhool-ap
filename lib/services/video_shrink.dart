import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

/// الخادم يقبل لحد 50 ميغا للملف الواحد. الفيديو الأكبر نضغطه بالهاتف نفسه
/// (نختار الجودة حسب طول المقطع حتى يكون الضغط مرة وحدة وسريع).
class VideoShrink {
  VideoShrink._();
  static const maxBytes = 48 * 1024 * 1024;

  /// ضغط بدون نوافذ (للنشر بالخلفية). onProgress من 0 إلى 1.
  static Future<XFile> compress(XFile x, {void Function(double)? onProgress}) async {
    if (kIsWeb || await x.length() <= maxBytes) return x;
    final sub = VideoCompress.compressProgress$.subscribe((p) => onProgress?.call((p / 100).clamp(0.0, 1.0)));
    try {
      var secs = 60.0;
      try {
        final info = await VideoCompress.getMediaInfo(x.path);
        secs = ((info.duration ?? 60000) / 1000).clamp(1, 36000).toDouble();
      } catch (_) {}
      // البت ريت اللي يخلي الملف أقل من الحد
      final bps = maxBytes * 8 * 0.9 / secs;
      final order = <VideoQuality>[
        if (bps >= 7e6) VideoQuality.Res1920x1080Quality,
        if (bps >= 3.5e6) VideoQuality.Res1280x720Quality,
        if (bps >= 2e6) VideoQuality.Res960x540Quality,
        VideoQuality.Res640x480Quality,
        VideoQuality.LowQuality,
      ];
      for (final q in order) {
        final info = await VideoCompress.compressVideo(x.path, quality: q, deleteOrigin: false, includeAudio: true);
        final f = info?.file;
        if (f != null && await f.length() <= maxBytes) return XFile(f.path, name: 'video.mp4', mimeType: 'video/mp4');
      }
      throw Exception('المقطع طويل جدًا على حد الخادم المجاني (50 ميغا) حتى بعد الضغط — قصّه لأجزاء وانشرها');
    } finally {
      sub.unsubscribe();
    }
  }

  /// ضغط مع نافذة تقدّم (للستوري والمحادثات)
  static Future<XFile> fit(BuildContext context, XFile x) async {
    if (kIsWeb || await x.length() <= maxBytes) return x;
    final progress = ValueNotifier<double>(0);
    var open = true;
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('نجهّز الفيديو 🎬'),
            content: ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('الفيديو كبير، دا نضغطه بجودة عالية حتى ينرفع بسرعة...'),
                const SizedBox(height: 14),
                LinearProgressIndicator(value: v <= 0 ? null : v),
                const SizedBox(height: 6),
                Text('${(v * 100).clamp(0, 100).toStringAsFixed(0)}%'),
              ]),
            ),
          ),
        ),
      ).then((_) => open = false);
    }
    try {
      return await compress(x, onProgress: (v) => progress.value = v);
    } finally {
      if (open && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
