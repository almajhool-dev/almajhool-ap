import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// خلفية «وهج» المتحركة: أضواء ملوّنة تسبح ببطء + نجوم صغيرة تلمع.
/// خفيفة على الهاتف (رسم واحد بإطار، بدون صور).
class AuroraBackground extends StatefulWidget {
  final Widget child;
  final bool particles;
  const AuroraBackground({super.key, required this.child, this.particles = true});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
  static final _stars = List.generate(46, (i) {
    final r = math.Random(i * 7919 + 13);
    return (r.nextDouble(), r.nextDouble(), 0.6 + r.nextDouble() * 1.8, r.nextDouble(), 0.3 + r.nextDouble() * 0.7);
  });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            painter: _AuroraPainter(_c.value, dark, widget.particles ? _stars : const <(double, double, double, double, double)>[]),
          ),
        ),
      ),
      widget.child,
    ]);
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final bool dark;
  final List<(double, double, double, double, double)> stars;
  _AuroraPainter(this.t, this.dark, this.stars);

  @override
  void paint(Canvas canvas, Size s) {
    final base = dark ? AppColors.darkBg : const Color(0xFFF1F3FA);
    canvas.drawRect(Offset.zero & s, Paint()..color = base);
    final a = t * 2 * math.pi;
    final blobs = [
      (AppColors.cyan, 0.25 + 0.18 * math.sin(a), 0.22 + 0.12 * math.cos(a * 2), 0.62),
      (AppColors.violet, 0.78 + 0.15 * math.cos(a), 0.38 + 0.16 * math.sin(a * 1.5), 0.70),
      (AppColors.pink, 0.45 + 0.22 * math.sin(a * 1.3 + 1), 0.85 + 0.08 * math.cos(a), 0.58),
      (const Color(0xFF2979FF), 0.10 + 0.10 * math.cos(a * 0.7 + 2), 0.65 + 0.14 * math.sin(a), 0.50),
    ];
    final m = math.max(s.width, s.height);
    for (final b in blobs) {
      final c = Offset(b.$2 * s.width, b.$3 * s.height);
      final r = b.$4 * m * 0.6;
      final paint = Paint()
        ..shader = RadialGradient(colors: [
          b.$1.withValues(alpha: dark ? 0.32 : 0.20),
          b.$1.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }
    // نجوم تطلع لفوك ببطء وتلمع
    final p = Paint();
    for (final st in stars) {
      final y = (st.$2 - t * st.$5) % 1.0;
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(a * 6 * st.$5 + st.$4 * 10));
      p.color = (dark ? Colors.white : AppColors.violet).withValues(alpha: (dark ? 0.55 : 0.35) * tw);
      canvas.drawCircle(Offset(st.$1 * s.width, y * s.height), st.$3, p);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter o) => o.t != t || o.dark != dark;
}

/// صفحة بخلفية متحركة (بديل Scaffold لشاشات الدخول).
class AuroraScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  const AuroraScaffold({super.key, this.appBar, this.body});

  @override
  Widget build(BuildContext context) {
    final bar = appBar;
    return AuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: bar is AppBar
            ? AppBar(
                title: bar.title,
                leading: bar.leading,
                actions: bar.actions,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
              )
            : bar,
        body: body,
      ),
    );
  }
}

/// زر متحرك: إطار ألوان يدور حوله + لمعة تمشي عليه + ينضغط بحركة ثلاثية الأبعاد.
class GlowButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;
  final List<Color> colors;
  final bool filled;
  final bool busy;
  const GlowButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.colors = const [AppColors.cyan, AppColors.violet, AppColors.pink, AppColors.cyan],
    this.filled = false,
    this.busy = false,
  });

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();
  late final AnimationController _press =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 140), reverseDuration: const Duration(milliseconds: 260));
  Offset _tilt = Offset.zero;

  @override
  void dispose() {
    _spin.dispose();
    _press.dispose();
    super.dispose();
  }

  void _down(TapDownDetails d, Size size) {
    setState(() => _tilt = Offset(
          (d.localPosition.dx / size.width - 0.5) * 2,
          (d.localPosition.dy / size.height - 0.5) * 2,
        ));
    _press.forward();
  }

  void _up() => _press.reverse();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inner = widget.filled
        ? null
        : (dark ? const Color(0xFF111827) : Colors.white).withValues(alpha: 0.92);
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth.isFinite ? box.maxWidth : 300, 54);
      return GestureDetector(
        onTapDown: enabled ? (d) => _down(d, size) : null,
        onTapUp: enabled ? (_) => _up() : null,
        onTapCancel: enabled ? _up : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: enabled || widget.busy ? 1 : 0.5,
          child: AnimatedBuilder(
            animation: Listenable.merge([_spin, _press]),
            builder: (context, child) {
              final p = Curves.easeOut.transform(_press.value);
              final m = Matrix4.identity()
                ..setEntry(3, 2, 0.0022)
                ..rotateX(-_tilt.dy * 0.22 * p)
                ..rotateY(_tilt.dx * 0.22 * p)
                ..scale(1 - 0.045 * p);
              final ang = _spin.value * 2 * math.pi;
              return Transform(
                alignment: Alignment.center,
                transform: m,
                child: Container(
                  height: size.height,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: SweepGradient(colors: widget.colors, transform: GradientRotation(ang)),
                    boxShadow: [
                      BoxShadow(
                        color: widget.colors[1].withValues(alpha: 0.28 + 0.22 * p),
                        blurRadius: 16 + 10 * p,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(fit: StackFit.expand, children: [
                      Container(
                        decoration: BoxDecoration(
                          color: inner,
                          gradient: widget.filled
                              ? LinearGradient(colors: [widget.colors[0], widget.colors[1]])
                              : null,
                        ),
                      ),
                      // لمعة تمشي على الزر
                      Positioned.fill(
                        child: FractionalTranslation(
                          translation: Offset(-1.5 + 3 * ((_spin.value * 1.6) % 1.6) / 1.6, 0),
                          child: Transform.rotate(
                            angle: -0.35,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                                  Colors.white.withValues(alpha: 0),
                                  Colors.white.withValues(alpha: widget.filled ? 0.28 : 0.10),
                                  Colors.white.withValues(alpha: 0),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child!,
                    ]),
                  ),
                ),
              );
            },
            child: Center(
              child: widget.busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: widget.filled ? Colors.white : widget.colors[0]),
                    )
                  : DefaultTextStyle.merge(
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: widget.filled ? Colors.white : (dark ? Colors.white : const Color(0xFF111827)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (widget.icon != null) ...[widget.icon!, const SizedBox(width: 10)],
                        Flexible(child: widget.label),
                      ]),
                    ),
            ),
          ),
        ),
      );
    });
  }
}

/// الشعار بحركة ثلاثية الأبعاد مستمرة: يطفو ويلف شوية ويتوهج.
class FloatingLogo3D extends StatefulWidget {
  final Widget child;
  const FloatingLogo3D({super.key, required this.child});
  @override
  State<FloatingLogo3D> createState() => _FloatingLogo3DState();
}

class _FloatingLogo3DState extends State<FloatingLogo3D> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final a = _c.value * 2 * math.pi;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0016)
            ..translate(0.0, 6 * math.sin(a))
            ..rotateY(0.32 * math.sin(a))
            ..rotateX(0.12 * math.cos(a)),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
