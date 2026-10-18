import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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
    final w = width.clamp(48, 1600);
    return 'https://wsrv.nl/?url=${Uri.encodeComponent(url)}&w=$w&we&output=webp&q=$quality';
  }

  /// الشبكة الاحتياطية الثانية: Photon من WordPress (شبكة عالمية مجانية بدون حساب، 3 مداخل i0/i1/i2)
  static String photon(String url, {int width = 1080}) {
    if (!eligible(url)) return url;
    final w = width.clamp(48, 1600);
    final host = 'i${url.hashCode.abs() % 3}.wp.com';
    return 'https://$host/${url.replaceFirst('https://', '')}?w=$w&quality=78&strip=all';
  }

  /// كل المصادر بالترتيب: شبكة ١ ← شبكة ٢ ← السيرفر الأصلي
  static List<String> chain(String url, {int width = 1080}) {
    if (!eligible(url)) return [url];
    return [image(url, width: width), photon(url, width: width), url];
  }

  /// تحميل مسبق لصور المنشورات الجاية حتى تطلع فورًا لما توصلها
  static void prefetch(Iterable<String?> urls, {int width = 1080}) {
    for (final u in urls) {
      if (u == null || u.isEmpty) continue;
      final f = image(u, width: width);
      DefaultCacheManager()
          .getSingleFile(f, key: f)
          .catchError((_) => DefaultCacheManager().getSingleFile(photon(u, width: width)))
          .catchError((_) => DefaultCacheManager().getSingleFile(u));
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
