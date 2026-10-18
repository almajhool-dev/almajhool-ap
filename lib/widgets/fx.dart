import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/fx_settings.dart';

/// خلفية التطبيق كله المتحركة (تنرسم مرة وحدة ورا كل الشاشات).
/// السمة والتشغيل/الإيقاف من [FxSettings]. 30 إطار بالثانية وتوقف لما التطبيق بالخلفية.
class FxBackground extends StatefulWidget {
  final Widget child;
  final FxTheme? theme; // لمعاينة سمة معيّنة بدل السمة المختارة
  final bool forceOn;
  const FxBackground({super.key, required this.child, this.theme, this.forceOn = false});

  @override
  State<FxBackground> createState() => _FxBackgroundState();
}

class _FxBackgroundState extends State<FxBackground> with WidgetsBindingObserver {
  final _clock = ValueNotifier<double>(0);
  Timer? _timer;
  final _sw = Stopwatch();

  FxSettings get _fx => FxSettings.instance;
  bool get _on => widget.forceOn || _fx.enabled;

  @override
  void initState() {
    super.initState();
    _fx.load();
    _fx.addListener(_onFx);
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  void _onFx() {
    if (!mounted) return;
    _sync();
    setState(() {});
  }

  void _sync() {
    if (_on && _timer == null) {
      _sw.start();
      _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _clock.value = _sw.elapsedMilliseconds / 1000.0);
    } else if (!_on && _timer != null) {
      _timer?.cancel();
      _timer = null;
      _sw.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _sync();
    } else {
      _timer?.cancel();
      _timer = null;
      _sw.stop();
    }
  }

  @override
  void dispose() {
    _fx.removeListener(_onFx);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final th = widget.theme ?? _fx.current;
    return Stack(fit: StackFit.expand, children: [
      RepaintBoundary(
        child: CustomPaint(painter: _FxPainter(_clock, th, dark, _on)),
      ),
      widget.child,
    ]);
  }
}

/// كانت خلفية خاصة بكل شاشة — هسه الخلفية وحدة للتطبيق كله، فهذا يمرّر الشاشة بس.
class AuroraBackground extends StatelessWidget {
  final Widget child;
  final bool particles;
  const AuroraBackground({super.key, required this.child, this.particles = true});
  @override
  Widget build(BuildContext context) => child;
}

class _FxPainter extends CustomPainter {
  final ValueNotifier<double> clock;
  final FxTheme th;
  final bool dark;
  final bool on;
  _FxPainter(this.clock, this.th, this.dark, this.on) : super(repaint: clock);

  static final _rnd = List.generate(64, (i) {
    final r = math.Random(i * 7919 + 13);
    return [r.nextDouble(), r.nextDouble(), r.nextDouble(), r.nextDouble(), r.nextDouble()];
  });
  static final Map<String, TextPainter> _tp = {};

  TextPainter _text(String s, Color c, double size) {
    final k = '$s|${c.toARGB32()}|$size';
    return _tp.putIfAbsent(k, () {
      if (_tp.length > 400) _tp.clear();
      return TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: c, fontSize: size, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  @override
  void paint(Canvas canvas, Size s) {
    final base = dark ? const Color(0xFF0A0E17) : const Color(0xFFF1F3FA);
    canvas.drawRect(Offset.zero & s, Paint()..color = base);
    final t = on ? clock.value : 0.0;
    final c = th.colors;
    final k = dark ? 1.0 : 0.6; // بالفاتح أخف حتى يبقى المحتوى واضح
    switch (th.base) {
      case 'matrix':
        _glow(canvas, s, t, c, 0.10 * k);
        _matrix(canvas, s, t, c, k);
      case 'network':
        _glow(canvas, s, t, c, 0.14 * k);
        _network(canvas, s, t, c, k);
      case 'waves':
        _glow(canvas, s, t, c, 0.12 * k);
        _waves(canvas, s, t, c, k);
      default:
        _glow(canvas, s, t, c, 0.24 * k);
        _stars(canvas, s, t, k);
    }
  }

  void _glow(Canvas canvas, Size s, double t, List<Color> c, double alpha) {
    final a = t * 2 * math.pi / 24;
    final blobs = [
      (c[0], 0.25 + 0.18 * math.sin(a), 0.22 + 0.12 * math.cos(a * 2), 0.62),
      (c[1], 0.78 + 0.15 * math.cos(a), 0.38 + 0.16 * math.sin(a * 1.5), 0.70),
      (c[2], 0.45 + 0.22 * math.sin(a * 1.3 + 1), 0.85 + 0.08 * math.cos(a), 0.58),
    ];
    final m = math.max(s.width, s.height);
    for (final b in blobs) {
      final o = Offset(b.$2 * s.width, b.$3 * s.height);
      final r = b.$4 * m * 0.6;
      canvas.drawCircle(
          o,
          r,
          Paint()
            ..shader = RadialGradient(colors: [b.$1.withValues(alpha: alpha), b.$1.withValues(alpha: 0)])
                .createShader(Rect.fromCircle(center: o, radius: r)));
    }
  }

  void _stars(Canvas canvas, Size s, double t, double k) {
    final p = Paint();
    for (final r in _rnd.take(46)) {
      final y = (r[1] - t / 24 * (0.3 + r[4] * 0.7)) % 1.0;
      final tw = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * (1 + r[4] * 3) + r[3] * 10));
      p.color = (dark ? Colors.white : const Color(0xFF7C4DFF)).withValues(alpha: 0.5 * tw * k);
      canvas.drawCircle(Offset(r[0] * s.width, y * s.height), 0.6 + r[2] * 1.8, p);
    }
  }

  void _matrix(Canvas canvas, Size s, double t, List<Color> c, double k) {
    final tokens = th.tokens;
    const fs = 13.0;
    final cols = (s.width / 26).ceil();
    for (var i = 0; i < cols; i++) {
      final r = _rnd[i % _rnd.length];
      final speed = 40 + r[4] * 70;
      final len = 6 + (r[2] * 10).floor();
      final head = ((t * speed + r[1] * s.height * 2) % (s.height + len * 20)) - 20;
      final col = c[i % 3];
      for (var j = 0; j < len; j++) {
        final y = head - j * 20;
        if (y < -20 || y > s.height) continue;
        final tok = tokens[(i * 7 + j * 3 + (t * 2).floor()) % tokens.length];
        final fade = 1 - j / len;
        final alpha = ((j == 0 ? 0.9 : 0.45 * fade) * k).clamp(0.0, 1.0);
        final tp = _text(tok, (j == 0 && dark ? Colors.white : col).withValues(alpha: (alpha * 10).round() / 10), fs);
        tp.paint(canvas, Offset(i * 26.0 + 4, y));
      }
    }
  }

  void _network(Canvas canvas, Size s, double t, List<Color> c, double k) {
    final tokens = th.tokens;
    const n = 24;
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      final r = _rnd[i];
      final x = (r[0] + 0.08 * math.sin(t * (0.2 + r[3] * 0.3) + r[4] * 6)) * s.width;
      final y = (r[1] + 0.06 * math.cos(t * (0.15 + r[2] * 0.3) + r[3] * 6)) * s.height;
      pts.add(Offset(x, y));
    }
    final line = Paint()..strokeWidth = 1;
    final maxD = s.shortestSide * 0.32;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final d = (pts[i] - pts[j]).distance;
        if (d > maxD) continue;
        line.color = c[(i + j) % 3].withValues(alpha: 0.35 * (1 - d / maxD) * k);
        canvas.drawLine(pts[i], pts[j], line);
      }
    }
    // نبضة تمشي على الروابط (مثل وصول تفاعل)
    final dot = Paint();
    for (var i = 0; i < n; i++) {
      final r = _rnd[i];
      final pulse = 0.5 + 0.5 * math.sin(t * 2 + r[4] * 8);
      dot.color = c[i % 3].withValues(alpha: (0.55 + 0.35 * pulse) * k);
      canvas.drawCircle(pts[i], 2.5 + 2.5 * pulse, dot);
      if (tokens.isNotEmpty && i % 3 == 0) {
        final tp = _text(tokens[i % tokens.length], c[i % 3].withValues(alpha: 0.8 * k), 15);
        tp.paint(canvas, pts[i] + const Offset(6, -20));
      }
    }
  }

  void _waves(Canvas canvas, Size s, double t, List<Color> c, double k) {
    for (var w = 0; w < 3; w++) {
      final path = Path();
      final baseY = s.height * (0.55 + w * 0.13);
      final amp = 18.0 + w * 10;
      final len = s.width / (1.2 + w * 0.4);
      path.moveTo(0, s.height);
      for (double x = 0; x <= s.width; x += 8) {
        path.lineTo(x, baseY + amp * math.sin(x / len * 2 * math.pi + t * (0.6 + w * 0.25)));
      }
      path.lineTo(s.width, s.height);
      path.close();
      canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c[w].withValues(alpha: 0.28 * k), c[w].withValues(alpha: 0.02)],
            ).createShader(Rect.fromLTWH(0, baseY - amp, s.width, s.height - baseY + amp)));
    }
  }

  @override
  bool shouldRepaint(_FxPainter o) => o.th != th || o.dark != dark || o.on != on;
}

/// عنصر بالقائمة: يدخل بحركة ناعمة (بالتتابع) وينضغط شوية لما تلمسه.
class FxItem extends StatefulWidget {
  final Widget child;
  final int index;
  const FxItem({super.key, required this.child, this.index = 0});
  @override
  State<FxItem> createState() => _FxItemState();
}

class _FxItemState extends State<FxItem> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  bool _down = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 28 * widget.index.clamp(0, 18)), () {
      if (mounted) _in.forward();
    });
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.965 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedBuilder(
          animation: _in,
          builder: (_, child) {
            final v = Curves.easeOutCubic.transform(_in.value);
            return Opacity(
              opacity: v,
              child: Transform(
                alignment: Alignment.centerRight,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..translate(0.0, (1 - v) * 24)
                  ..rotateX((1 - v) * 0.35),
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// يغلّف كل عناصر القائمة بحركة الدخول والضغط.
List<Widget> fxList(List<Widget> items) => [for (var i = 0; i < items.length; i++) FxItem(index: i, child: items[i])];

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
