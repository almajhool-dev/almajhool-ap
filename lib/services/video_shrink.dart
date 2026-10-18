import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

/// الخادم يقبل لحد 50 ميغا للملف الواحد. الفيديو الأكبر نضغطه بالهاتف نفسه
/// (بجودة عالية تبقى واضحة) حتى ينرفع أي فيديو مهما كان حجمه.
class VideoShrink {
  VideoShrink._();
  static const maxBytes = 48 * 1024 * 1024;

  static Future<XFile> fit(BuildContext context, XFile x) async {
    if (kIsWeb || await x.length() <= maxBytes) return x;
    final progress = ValueNotifier<double>(0);
    final sub = VideoCompress.compressProgress$.subscribe((p) => progress.value = p / 100);
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
      for (final q in [VideoQuality.Res1920x1080Quality, VideoQuality.Res1280x720Quality, VideoQuality.Res960x540Quality, VideoQuality.Res640x480Quality]) {
        progress.value = 0;
        final info = await VideoCompress.compressVideo(x.path, quality: q, deleteOrigin: false, includeAudio: true);
        final f = info?.file;
        if (f != null && await f.length() <= maxBytes) return XFile(f.path, name: 'video.mp4', mimeType: 'video/mp4');
      }
      throw Exception('الفيديو طويل جدًا حتى بعد الضغط، قصّه لجزئين وانشره');
    } finally {
      sub.unsubscribe();
      if (open && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
