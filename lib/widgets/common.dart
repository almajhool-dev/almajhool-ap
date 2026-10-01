import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../services/media_service.dart';

class Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final bool online;
  final bool group;

  const Avatar({super.key, this.url, required this.name, this.size = 48, this.online = false, this.group = false});

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final placeholder = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
      alignment: Alignment.center,
      child: group
          ? Icon(Icons.groups_rounded, color: Colors.white, size: size * 0.5)
          : Text(letter,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.4)),
    );
    final img = (url == null || url!.isEmpty)
        ? placeholder
        : ClipOval(
            child: CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              memCacheWidth: (size * 3).round(),
              placeholder: (_, __) => placeholder,
              errorWidget: (_, __, ___) => placeholder,
            ),
          );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          img,
          if (online)
            Positioned(
              bottom: 0,
              left: 0,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// صورة من bucket خاص عبر رابط موقّع + Cache.
class SignedImage extends StatefulWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  const SignedImage({super.key, required this.path, this.width, this.height, this.fit = BoxFit.cover});

  @override
  State<SignedImage> createState() => _SignedImageState();
}

class _SignedImageState extends State<SignedImage> {
  late Future<String> _future = MediaService.signedUrl(widget.path);

  @override
  void didUpdateWidget(covariant SignedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _future = MediaService.signedUrl(widget.path);
  }

  String get path => widget.path;
  double? get width => widget.width;
  double? get height => widget.height;
  BoxFit get fit => widget.fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            width: width,
            height: height,
            color: Colors.black12,
            alignment: Alignment.center,
            child: snap.hasError
                ? const Icon(Icons.broken_image_outlined)
                : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return CachedNetworkImage(
          imageUrl: snap.data!,
          cacheKey: path,
          width: width,
          height: height,
          fit: fit,
          placeholder: (_, __) => Container(width: width, height: height, color: Colors.black12),
          errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined),
        );
      },
    );
  }
}

class BrandLogo extends StatelessWidget {
  final double size;
  final bool showName;
  const BrandLogo({super.key, this.size = 96, this.showName = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppColors.cyan.withValues(alpha: 0.35), blurRadius: size * 0.35)],
          ),
          child: ClipOval(child: Image.asset('assets/branding/logo.png', fit: BoxFit.cover)),
        ),
        if (showName) ...[
          SizedBox(height: size * 0.22),
          ShaderMask(
            shaderCallback: (r) => AppColors.brandGradient.createShader(r),
            child: Text(
              AppConfig.appName,
              style: TextStyle(
                fontSize: size * 0.3,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: c.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: c.onSurface.withValues(alpha: 0.6))),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade800,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, size: 16, color: Colors.white),
          SizedBox(width: 8),
          Text('غير متصل — ستُرسل الرسائل عند عودة الإنترنت',
              style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class Badge2 extends StatelessWidget {
  final int count;
  const Badge2(this.count, {super.key});
  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      constraints: const BoxConstraints(minWidth: 22),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// علامة التوثيق الزرقاء.
class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 16});
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.verified_rounded, size: size, color: const Color(0xFF1D9BF0));
}

/// اسم المستخدم مع علامة التوثيق.
class NameWithBadge extends StatelessWidget {
  final String name;
  final bool verified;
  final TextStyle? style;
  final double badgeSize;
  const NameWithBadge(this.name, {super.key, this.verified = false, this.style, this.badgeSize = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
        if (verified) ...[const SizedBox(width: 4), VerifiedBadge(size: badgeSize)],
      ],
    );
  }
}

class LevelChip extends StatelessWidget {
  final int level;
  const LevelChip(this.level, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('Lv $level',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}
