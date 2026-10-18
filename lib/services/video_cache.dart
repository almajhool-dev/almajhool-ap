import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

/// طبقة «السيرفر داخل الموبايل» (مثل كاش فيسبوك):
/// الفيديوهات الجاية بالمنشورات تنحمّل من قبل وتنخزن بالجهاز، فلما توصلها تشتغل فورًا،
/// وإذا رجعتلها تشتغل من الجهاز بدون إنترنت ولا تحميل مرة ثانية.
class VideoCache {
  VideoCache._();

  static final _mgr = CacheManager(Config(
    'vyfri_videos',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 60,
  ));

  /// أكبر حجم ننزله مسبقًا (حتى ما نصرف باقة المستخدم على فيديوهات طويلة ما يشوفها)
  static const _maxPrefetch = 20 * 1024 * 1024;
  static final _busy = <String>{};

  /// يرجع مشغّل من الجهاز إذا الفيديو متخزن، وإلا من النت مباشرة (بدون تحميل مضاعف)
  static Future<VideoPlayerController> controller(String url) async {
    try {
      final f = await _mgr.getFileFromCache(url);
      if (f != null && await f.file.exists()) return VideoPlayerController.file(File(f.file.path));
    } catch (_) {}
    return VideoPlayerController.networkUrl(Uri.parse(url));
  }

  /// تحميل مسبق للفيديوهات الجاية (الصغيرة والمتوسطة)
  static void prefetch(Iterable<String?> urls, {int limit = 3}) {
    var n = 0;
    for (final u in urls) {
      if (u == null || u.isEmpty || n >= limit) continue;
      n++;
      _one(u);
    }
  }

  static Future<void> _one(String url) async {
    if (_busy.contains(url)) return;
    _busy.add(url);
    try {
      final have = await _mgr.getFileFromCache(url);
      if (have != null) return;
      final h = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 8));
      final len = int.tryParse(h.headers['content-length'] ?? '') ?? 0;
      if (h.statusCode != 200 || len <= 0 || len > _maxPrefetch) return;
      await _mgr.downloadFile(url, key: url);
    } catch (_) {
    } finally {
      _busy.remove(url);
    }
  }
}
