import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

import 'core_services.dart';

/// شبكة توصيل مجانية (wsrv.nl فوق Cloudflare، مئات السيرفرات حول العالم، بدون حساب ولا فلوس):
/// تصغّر الصورة لحجم الشاشة وتحوّلها WebP وتخزّنها بأقرب سيرفر للمستخدم.
/// الأصل يبقى على السيرفر الأصلي، وإذا فشلت الشبكة نرجع للأصل تلقائيًا.
class Cdn {
  static bool enabled = true;

  /// نمرر بس الصور العامة (المنشورات، الصور الشخصية، السوق)؛ الخاصة (الدردشة الموقّعة) تبقى مباشرة.
  static bool eligible(String url) =>
      enabled &&
      url.startsWith('https://') &&
      url.contains('/storage/v1/object/public/') &&
      !url.toLowerCase().contains('.gif');

  static String image(String url, {int width = 1080, int quality = 78}) {
    if (!eligible(url)) return url;
    return wsrv(url, width: width, quality: quality);
  }

  /// الشبكة الأولى: wsrv.nl فوق Cloudflare
  static String wsrv(String url, {int width = 1080, int quality = 78}) {
    final w = width.clamp(48, 1600);
    return 'https://wsrv.nl/?url=${Uri.encodeComponent(url)}&w=$w&we&output=webp&q=$quality';
  }

  /// الشبكة الثانية: Photon من WordPress (شبكة عالمية مجانية بدون حساب، 3 مداخل i0/i1/i2)
  static String photon(String url, {int width = 1080}) {
    final w = width.clamp(48, 1600);
    final host = 'i${url.hashCode.abs() % 3}.wp.com';
    return 'https://$host/${url.replaceFirst('https://', '')}?w=$w&quality=78&strip=all';
  }

  /// الشبكة الثالثة: imagecdn.app (مجانية بدون حساب)
  static String imagecdn(String url, {int width = 1080}) {
    final w = width.clamp(48, 1600);
    return 'https://imagecdn.app/v2/image/${Uri.encodeComponent(url)}?width=$w&format=webp&quality=78';
  }

  /// الشبكة الرابعة: المدخل الثاني لنفس شبكة wsrv (اسم نطاق ثاني إذا انحجب الأول)
  static String weserv(String url, {int width = 1080}) {
    final w = width.clamp(48, 1600);
    return 'https://images.weserv.nl/?url=${Uri.encodeComponent(url)}&w=$w&we&output=webp&q=78';
  }

  static final Map<String, String Function(String, {int width})> _nets = {
    'wsrv': (u, {int width = 1080}) => wsrv(u, width: width),
    'photon': photon,
    'imagecdn': imagecdn,
    'weserv': weserv,
  };

  /// ترتيب الشبكات (الأسرع أولًا). يتحدّث تلقائيًا كل ما يفتح التطبيق.
  static List<String> order = ['wsrv', 'photon', 'imagecdn', 'weserv'];

  /// كل المصادر بالترتيب: أسرع شبكة ← اللي بعدها ← ... ← السيرفر الأصلي
  static List<String> chain(String url, {int width = 1080}) {
    if (!eligible(url)) return [url];
    return [for (final n in order) _nets[n]!(url, width: width), url];
  }

  /// يقيس سرعة كل شبكة من جهاز المستخدم ويرتّبها تلقائيًا (بدون أي تدخل)
  static Future<void> rank() async {
    const probe = 'https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg';
    final times = <String, int>{};
    await Future.wait(_nets.entries.map((e) async {
      final sw = Stopwatch()..start();
      try {
        final r = await http.get(Uri.parse(e.value(probe, width: 48))).timeout(const Duration(seconds: 6));
        times[e.key] = r.statusCode == 200 ? sw.elapsedMilliseconds : 99999;
      } catch (_) {
        times[e.key] = 99999;
      }
    }));
    final sorted = times.keys.toList()..sort((a, b) => times[a]!.compareTo(times[b]!));
    if (sorted.isNotEmpty && times[sorted.first]! < 99999) {
      order = sorted;
      CacheService.setString('cdn_order', sorted.join(','));
    }
  }

  /// نرجّع آخر ترتيب محفوظ فورًا، وبعدين نقيس من جديد بالخلفية
  static void init() {
    try {
      final saved = CacheService.getString('cdn_order');
      if (saved != null && saved.isNotEmpty) {
        final o = saved.split(',').where(_nets.containsKey).toList();
        for (final n in _nets.keys) {
          if (!o.contains(n)) o.add(n);
        }
        order = o;
      }
    } catch (_) {}
    Future.delayed(const Duration(seconds: 3), rank);
  }

  /// تحميل مسبق لصور المنشورات الجاية حتى تطلع فورًا لما توصلها
  static void prefetch(Iterable<String?> urls, {int width = 1080}) {
    for (final u in urls) {
      if (u == null || u.isEmpty) continue;
      final c = chain(u, width: width);
      Future<void> go(int i) async {
        try {
          await DefaultCacheManager().getSingleFile(c[i], key: c[i]);
        } catch (_) {
          if (i + 1 < c.length) await go(i + 1);
        }
      }

      go(0);
    }
  }
}

/// صورة سريعة: من الشبكة المجانية، وإذا ما اشتغلت تنعرض من الأصل.
class FastImage extends StatelessWidget {
  final String url;
  final int width;
  final double? w;
  final double? h;
  final BoxFit fit;
  final int? memCacheWidth;
  final Duration fadeIn;
  final Widget Function(BuildContext)? placeholder;
  final Widget Function(BuildContext)? error;

  const FastImage(
    this.url, {
    super.key,
    this.width = 1080,
    this.w,
    this.h,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
    this.fadeIn = const Duration(milliseconds: 90),
    this.placeholder,
    this.error,
  });

  Widget _at(BuildContext context, List<String> urls, int i) {
    final u = urls[i];
    final last = i == urls.length - 1;
    return CachedNetworkImage(
      imageUrl: u,
      cacheKey: u,
      width: w,
      height: h,
      fit: fit,
      memCacheWidth: memCacheWidth,
      fadeInDuration: fadeIn,
      fadeOutDuration: Duration.zero,
      placeholder: placeholder == null ? null : (c, _) => placeholder!(c),
      errorWidget: (c, _, __) => last ? (error?.call(c) ?? const SizedBox.shrink()) : _at(c, urls, i + 1),
    );
  }

  @override
  Widget build(BuildContext context) => _at(context, Cdn.chain(url, width: width), 0);
}
