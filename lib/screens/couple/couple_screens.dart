import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../repositories/chat_repository.dart';
import '../../services/core_services.dart';
import '../../services/couple_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../chat/chat_screen.dart';

// ======================= الألوان والخلفية المجرّية =======================
class _G {
  static const bgTop = Color(0xFF0A0726);
  static const bgMid = Color(0xFF1E0F52);
  static const bgBottom = Color(0xFF34105C);
  static const pink = Color(0xFFFF4FD8);
  static const rose = Color(0xFFFF7AB6);
  static const cyan = Color(0xFF3DE0FF);
  static const violet = Color(0xFF8B5CF6);
  static const card = Color(0x33FFFFFF);
}

const _months = ['', 'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول'];
String _d(DateTime d) => '${d.day}/${d.month}/${d.year}';
String _dLong(DateTime d) => '${d.day} ${_months[d.month]} ${d.year}';

/// خلفية مجرّة: تدرّج بنفسجي + نجوم تلمع.
class GalaxyBackground extends StatefulWidget {
  final Widget child;
  const GalaxyBackground({super.key, required this.child});
  @override
  State<GalaxyBackground> createState() => _GalaxyBackgroundState();
}

class _GalaxyBackgroundState extends State<GalaxyBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final List<_Star> _stars = () {
    final r = math.Random(7);
    return List.generate(90, (_) => _Star(r.nextDouble(), r.nextDouble(), 0.5 + r.nextDouble() * 1.6, r.nextDouble()));
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_G.bgTop, _G.bgMid, _G.bgBottom],
        ),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(painter: _StarsPainter(_stars, _c.value)),
            ),
          ),
        ),
        widget.child,
      ]),
    );
  }
}

class _Star {
  final double x, y, r, phase;
  _Star(this.x, this.y, this.r, this.phase);
}

class _StarsPainter extends CustomPainter {
  final List<_Star> stars;
  final double t;
  _StarsPainter(this.stars, this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final s in stars) {
      final a = 0.25 + 0.75 * (0.5 + 0.5 * math.sin((t + s.phase) * 2 * math.pi));
      p.color = Colors.white.withValues(alpha: a * 0.85);
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), s.r, p);
    }
    // سديم وردي خفيف
    final neb = Paint()
      ..shader = RadialGradient(colors: [_G.pink.withValues(alpha: 0.16), Colors.transparent])
          .createShader(Rect.fromCircle(center: Offset(size.width * 0.8, size.height * 0.25), radius: size.width * 0.6));
    canvas.drawCircle(Offset(size.width * 0.8, size.height * 0.25), size.width * 0.6, neb);
    final neb2 = Paint()
      ..shader = RadialGradient(colors: [_G.cyan.withValues(alpha: 0.10), Colors.transparent])
          .createShader(Rect.fromCircle(center: Offset(size.width * 0.15, size.height * 0.7), radius: size.width * 0.55));
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.7), size.width * 0.55, neb2);
  }

  @override
  bool shouldRepaint(_StarsPainter o) => o.t != t;
}

/// زر نيون دائري مثل اللي بالفيديو.
class _NeonCircle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;
  const _NeonCircle({required this.icon, required this.color, this.size = 54, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2.4),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 14)],
            color: Colors.black.withValues(alpha: 0.15),
          ),
          child: Icon(icon, color: color, size: size * 0.45),
        ),
      );
}

/// كوكب ذكرى متوهج.
class _Planet extends StatelessWidget {
  final double size;
  final int seed;
  final String? image;
  const _Planet({required this.size, required this.seed, this.image});
  @override
  Widget build(BuildContext context) {
    final r = math.Random(seed);
    final c1 = [_G.pink, _G.rose, const Color(0xFFFF6FA5), const Color(0xFFE94BFF)][r.nextInt(4)];
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [Colors.white, c1, const Color(0xFF7A1C8C)],
          stops: const [0.0, 0.45, 1.0],
        ),
        boxShadow: [
          BoxShadow(color: c1.withValues(alpha: 0.75), blurRadius: size * 0.45, spreadRadius: 1),
        ],
      ),
      child: image == null
          ? CustomPaint(painter: _PlanetDots(seed))
          : ClipOval(
              child: Opacity(
                opacity: 0.85,
                child: CachedNetworkImage(imageUrl: image!, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox()),
              ),
            ),
    );
  }
}

class _PlanetDots extends CustomPainter {
  final int seed;
  _PlanetDots(this.seed);
  @override
  void paint(Canvas canvas, Size s) {
    final r = math.Random(seed + 3);
    final p = Paint();
    for (var i = 0; i < 14; i++) {
      final a = r.nextDouble() * 2 * math.pi, d = r.nextDouble() * s.width * 0.42;
      p.color = Colors.white.withValues(alpha: 0.25 + r.nextDouble() * 0.5);
      canvas.drawCircle(Offset(s.width / 2 + math.cos(a) * d, s.height / 2 + math.sin(a) * d), 1 + r.nextDouble() * 2.6, p);
    }
  }

  @override
  bool shouldRepaint(_PlanetDots o) => false;
}

// ======================= بطاقة الربط (بالإعدادات) =======================
class CouplePairCard extends StatefulWidget {
  const CouplePairCard({super.key});
  @override
  State<CouplePairCard> createState() => _CouplePairCardState();
}

class _CouplePairCardState extends State<CouplePairCard> {
  String? _code;
  DateTime? _expires;
  Timer? _tick;
  bool _busy = false;
  bool _loading = true;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final s = await CoupleService.refresh();
      if (!s.linked) await _newCode();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final e = _expires;
      if (e != null && e.isBefore(DateTime.now()) && CoupleService.status.value?.linked != true) {
        _expires = null;
        _newCode();
      }
      setState(() {});
    });
  }

  Future<void> _newCode() async {
    try {
      final r = await CoupleService.myCode();
      if (mounted) setState(() {
        _code = r.code;
        _expires = r.expires;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _tick?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final c = _input.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(c)) {
      showSnack(context, 'الرمز لازم يكون 6 أرقام', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await CoupleService.link(c);
      if (!mounted) return;
      if (ok) {
        HapticFeedback.mediumImpact();
        _input.clear();
        showSnack(context, 'تم الربط 💞 صرتوا شركاء');
      } else {
        showSnack(context, 'الرمز غلط أو منتهي، اطلب من شريكك رمز جديد', error: true);
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlink() async {
    final ok = await confirmDialog(context, 'فك الربط؟',
        'راح تنحذف مساحتكم المشتركة وكل الذكريات اللي بيها، وما تكدر ترجعها.', ok: 'فك الربط', danger: true);
    if (!ok) return;
    try {
      await CoupleService.unlink();
      await _newCode();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _G.pink.withValues(alpha: 0.7), width: 1.4),
        boxShadow: [BoxShadow(color: _G.pink.withValues(alpha: 0.25), blurRadius: 18)],
      ),
      child: GalaxyBackground(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: _loading
                ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: _G.pink)))
                : ValueListenableBuilder<CoupleStatus?>(
                    valueListenable: CoupleService.status,
                    builder: (_, s, __) => s?.linked == true ? _linked(s!) : _pair(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _linked(CoupleStatus s) {
    final p = s.partner!;
    return Column(children: [
      Row(children: [
        Avatar(url: p.avatar, name: p.name, size: 52),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('شريكك 💞', style: TextStyle(color: _G.rose, fontSize: 12.5, fontWeight: FontWeight.w700)),
            Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            if (s.days != null) Text('سوا من ${s.days} يوم', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _G.pink, foregroundColor: Colors.white),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoupleHomeScreen())),
          icon: const Icon(Icons.favorite_rounded),
          label: const Text('افتح مساحتنا', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ),
      TextButton(
        onPressed: _unlink,
        child: const Text('فك الربط', style: TextStyle(color: Colors.white60)),
      ),
    ]);
  }

  Widget _pair() {
    final left = _expires == null ? null : _expires!.difference(DateTime.now());
    final mm = left == null || left.isNegative ? '--' : left.inMinutes.toString().padLeft(2, '0');
    final ss = left == null || left.isNegative ? '--' : (left.inSeconds % 60).toString().padLeft(2, '0');
    return Column(children: [
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.link_rounded, color: _G.pink, size: 20),
        SizedBox(width: 6),
        Text('اربط حسابك بشريكك', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      ]),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          const Text('رمزك', style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_code ?? '······',
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 8)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.timer_outlined, size: 14, color: _G.cyan),
            const SizedBox(width: 4),
            Text('صالح لمدة $mm:$ss', textDirection: TextDirection.rtl, style: const TextStyle(color: _G.cyan, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              shape: const StadiumBorder(),
            ),
            onPressed: _code == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _code!));
                    showSnack(context, 'تم نسخ الرمز، دزه لشريكك');
                  },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('نسخ الرمز'),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _input,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 6,
        style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.w800),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: '',
          hintText: 'رمز شريكك',
          hintStyle: const TextStyle(color: Colors.white38, fontSize: 15, letterSpacing: 0, fontWeight: FontWeight.w500),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.25),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [_G.pink, Color(0xFFFF6FA5)]),
            boxShadow: [BoxShadow(color: _G.pink.withValues(alpha: 0.5), blurRadius: 14)],
          ),
          child: TextButton(
            onPressed: _busy ? null : _link,
            style: TextButton.styleFrom(foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('ربط الحساب 💞', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
        ),
      ),
      const SizedBox(height: 6),
      const Text('انطي رمزك لشريكك يدخله عنده، أو دخّل رمزه هنا.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 11.5)),
    ]);
  }
}

// ======================= رحلتنا (الشاشة الرئيسية) =======================
class CoupleHomeScreen extends StatefulWidget {
  const CoupleHomeScreen({super.key});
  @override
  State<CoupleHomeScreen> createState() => _CoupleHomeScreenState();
}

class _CoupleHomeScreenState extends State<CoupleHomeScreen> with TickerProviderStateMixin {
  late final AnimationController _orbit = AnimationController(vsync: this, duration: const Duration(seconds: 90))..repeat();
  late final AnimationController _beat =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  List<CoupleMemory> _mem = [];
  bool _loading = true;
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await CoupleService.refresh();
      if (s.linked) {
        final m = await CoupleService.memories();
        _mem = m;
        _ch ??= CoupleService.memoriesChannel(() async {
          final m2 = await CoupleService.memories();
          if (mounted) setState(() => _mem = m2);
        });
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _orbit.dispose();
    _beat.dispose();
    if (_ch != null) supa.removeChannel(_ch!);
    super.dispose();
  }

  Future<String?> _conv() async {
    final p = CoupleService.status.value?.partner;
    if (p == null) return null;
    return ChatRepository().openDirect(p.id);
  }

  Future<void> _openChat() async {
    try {
      final id = await _conv();
      if (id != null && mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(conversationId: id)));
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _pulse() async {
    HapticFeedback.heavyImpact();
    try {
      final id = await _conv();
      if (id == null) return;
      await ChatRepository().send(conversationId: id, clientId: const Uuid().v4(), content: '💗 نبضة حب');
      if (mounted) showSnack(context, 'وصلت نبضتك 💗');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _setSince() async {
    final s = CoupleService.status.value;
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: s?.since ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
      helpText: 'من يا يوم صرتوا سوا؟',
    );
    if (d == null) return;
    try {
      await CoupleService.setSince(d);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _add() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _G.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _AddMemorySheet(),
    );
    if (ok == true) {
      final m = await CoupleService.memories();
      if (mounted) setState(() => _mem = m);
    }
  }

  void _openMemory(CoupleMemory m) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _G.bgMid,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _MemorySheet(
        m: m,
        onDeleted: () => setState(() => _mem.removeWhere((x) => x.id == m.id)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _G.bgTop,
      body: GalaxyBackground(
        child: SafeArea(
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _G.pink))
                : ValueListenableBuilder<CoupleStatus?>(
                    valueListenable: CoupleService.status,
                    builder: (_, s, __) => s?.linked == true ? _journey(s!) : _notLinked(),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
        child: Row(children: [
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, shadows: [Shadow(color: _G.pink, blurRadius: 12)])),
          ),
          const SizedBox(width: 48),
        ]),
      );

  Widget _notLinked() => Column(children: [
        _topBar('مساحة الشريك'),
        const Expanded(child: Center(child: SingleChildScrollView(child: CouplePairCard()))),
      ]);

  Widget _journey(CoupleStatus s) {
    final days = s.days;
    return Column(children: [
      _topBar('رحلتنا'),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(children: [
            _NeonCircle(icon: Icons.favorite_border_rounded, color: _G.pink, onTap: _pulse),
            const SizedBox(height: 4),
            const Text('نبضة', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ),
        const SizedBox(width: 22),
        GestureDetector(
          onTap: _setSince,
          child: Column(children: [
            ScaleTransition(
              scale: Tween(begin: 0.94, end: 1.06).animate(CurvedAnimation(parent: _beat, curve: Curves.easeInOut)),
              child: SizedBox(
                width: 92,
                height: 84,
                child: Stack(alignment: Alignment.center, children: [
                  Icon(Icons.favorite_rounded, size: 92, color: _G.pink, shadows: [Shadow(color: _G.pink.withValues(alpha: 0.9), blurRadius: 24)]),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: days == null
                        ? const Icon(Icons.touch_app_rounded, color: Colors.white, size: 28)
                        : Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('$days', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1)),
                            const Text('يوم', style: TextStyle(fontSize: 11, height: 1.1)),
                          ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 2),
            Text(days == null ? 'حدّدا تاريخكما' : 'من ${_dLong(s.since!)}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 22),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(children: [
            _NeonCircle(icon: Icons.chat_bubble_outline_rounded, color: _G.cyan, onTap: _openChat),
            const SizedBox(height: 4),
            const Text('محادثتنا', style: TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ),
      ]),
      Expanded(child: _orbitView(s)),
      _bottomBar(),
      const SizedBox(height: 10),
    ]);
  }

  Widget _orbitView(CoupleStatus s) {
    final shown = _mem.length > 8 ? _mem.sublist(_mem.length - 8) : _mem;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final radius = math.min(w * 0.36, h * 0.38);
      final center = Offset(w / 2, h / 2);
      final planet = shown.length <= 4 ? 64.0 : 54.0;
      return Stack(clipBehavior: Clip.none, children: [
        // المدار
        Positioned.fill(child: CustomPaint(painter: _OrbitPainter(center, radius))),
        // المنتصف: صورتكم
        Positioned(
          left: center.dx - 52,
          top: center.dy - 30,
          width: 104,
          child: Column(children: [
            SizedBox(
              height: 44,
              child: Stack(alignment: Alignment.center, children: [
                Positioned(right: 18, child: _ringAvatar(null, s)),
                Positioned(left: 18, child: _ringAvatar(s.partner, s)),
                const Icon(Icons.favorite_rounded, color: _G.pink, size: 18),
              ]),
            ),
            const SizedBox(height: 4),
            Text('${_mem.length} ذكرى', style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ]),
        ),
        if (shown.isEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: center.dy + radius + 8,
            child: const Text('ضيفوا أول ذكرى إلكم من زر ➕',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
        AnimatedBuilder(
          animation: _orbit,
          builder: (_, __) => Stack(clipBehavior: Clip.none, children: [
            for (var i = 0; i < shown.length; i++)
              () {
                final a = _orbit.value * 2 * math.pi + i * 2 * math.pi / shown.length - math.pi / 2;
                final x = center.dx + math.cos(a) * radius, y = center.dy + math.sin(a) * radius;
                final m = shown[i];
                return Positioned(
                  left: x - 46,
                  top: y - planet / 2,
                  width: 92,
                  child: GestureDetector(
                    onTap: () => _openMemory(m),
                    child: Column(children: [
                      _Planet(size: planet, seed: m.id.hashCode, image: m.image),
                      const SizedBox(height: 4),
                      Text(m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      Text(_d(m.day), style: const TextStyle(fontSize: 10, color: Colors.white60)),
                    ]),
                  ),
                );
              }(),
          ]),
        ),
        Positioned(
          top: 4,
          left: 14,
          child: GestureDetector(
            onTap: _add,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _G.pink.withValues(alpha: 0.2),
                boxShadow: [BoxShadow(color: _G.pink.withValues(alpha: 0.6), blurRadius: 12)],
              ),
              child: const Icon(Icons.add_rounded, color: _G.pink, size: 30),
            ),
          ),
        ),
      ]);
    });
  }

  Widget _ringAvatar(CouplePartner? p, CoupleStatus s) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p == null ? _G.cyan : _G.pink, width: 2)),
        child: p == null
            ? const CircleAvatar(radius: 17, backgroundColor: _G.violet, child: Icon(Icons.person, size: 18, color: Colors.white))
            : Avatar(url: p.avatar, name: p.name, size: 34),
      );

  Widget _bottomBar() {
    Widget btn(IconData i, String t, List<Color> g, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(colors: g, begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [BoxShadow(color: g.first.withValues(alpha: 0.55), blurRadius: 12)],
                border: Border.all(color: Colors.white24),
              ),
              child: Column(children: [
                Icon(i, color: Colors.white, size: 24),
                const SizedBox(height: 3),
                Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white)),
              ]),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(children: [
        btn(Icons.nightlife_rounded, 'سهرتنا', [_G.pink, const Color(0xFFB0309A)], () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const WatchTogetherScreen()));
        }),
        btn(Icons.photo_library_rounded, 'جدار الذكريات', [const Color(0xFF2B7BFF), _G.violet], () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoriesWallScreen()));
        }),
        btn(Icons.quiz_rounded, 'سؤال اليوم', [const Color(0xFF14B8C9), const Color(0xFF2B7BFF)], () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: _G.bgMid,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            builder: (_) => const _QuestionSheet(),
          );
        }),
      ]),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  final Offset c;
  final double r;
  _OrbitPainter(this.c, this.r);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = const Color(0xFF9AA8FF).withValues(alpha: 0.45));
    canvas.drawCircle(
        c,
        r * 0.55,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _G.pink.withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(_OrbitPainter o) => o.c != c || o.r != r;
}

// ======================= إضافة / عرض ذكرى =======================
class _AddMemorySheet extends StatefulWidget {
  const _AddMemorySheet();
  @override
  State<_AddMemorySheet> createState() => _AddMemorySheetState();
}

class _AddMemorySheetState extends State<_AddMemorySheet> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  DateTime _day = DateTime.now();
  Uint8List? _img;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  InputDecoration _dec(String h) => InputDecoration(
        hintText: h,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.25),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showSnack(context, 'اكتب عنوان للذكرى', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await CoupleService.addMemory(title: _title.text, note: _note.text, day: _day, image: _img);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('ذكرى جديدة 🪐', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            TextField(controller: _title, maxLength: 60, style: const TextStyle(color: Colors.white), decoration: _dec('العنوان (مثلاً: أول لقاء)')),
            TextField(
                controller: _note,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                style: const TextStyle(color: Colors.white),
                decoration: _dec('اكتب شنو صار بهاليوم… (اختياري)')),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30)),
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(1950), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (d != null) setState(() => _day = d);
                  },
                  icon: const Icon(Icons.event_rounded),
                  label: Text(_d(_day)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white30)),
                  onPressed: () async {
                    final b = await CoupleService.pickPhoto();
                    if (b != null) setState(() => _img = b);
                  },
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: Text(_img == null ? 'صورة' : 'تغيير الصورة'),
                ),
              ),
            ]),
            if (_img != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(_img!, height: 140, fit: BoxFit.cover)),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _G.pink, foregroundColor: Colors.white),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('حفظ الذكرى', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MemorySheet extends StatelessWidget {
  final CoupleMemory m;
  final VoidCallback onDeleted;
  const _MemorySheet({required this.m, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (m.image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: CachedNetworkImage(imageUrl: m.image!, fit: BoxFit.cover, width: double.infinity, height: 260),
              )
            else
              _Planet(size: 110, seed: m.id.hashCode),
            const SizedBox(height: 14),
            Text(m.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            Text(_dLong(m.day), style: const TextStyle(color: _G.rose, fontWeight: FontWeight.w700)),
            if (m.note.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(m.note, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.6)),
            ],
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () async {
                final ok = await confirmDialog(context, 'حذف الذكرى؟', 'راح تنحذف عندكم انتو الاثنين.', ok: 'حذف', danger: true);
                if (!ok) return;
                try {
                  await CoupleService.deleteMemory(m.id);
                  onDeleted();
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) showSnack(context, friendlyError(e), error: true);
                }
              },
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54),
              label: const Text('حذف', style: TextStyle(color: Colors.white54)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ======================= جدار الذكريات =======================
class MemoriesWallScreen extends StatefulWidget {
  const MemoriesWallScreen({super.key});
  @override
  State<MemoriesWallScreen> createState() => _MemoriesWallScreenState();
}

class _MemoriesWallScreenState extends State<MemoriesWallScreen> {
  List<CoupleMemory>? _m;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await CoupleService.memories();
      if (mounted) setState(() => _m = m.reversed.toList());
    } catch (e) {
      if (mounted) {
        setState(() => _m = []);
        showSnack(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _m;
    return Scaffold(
      backgroundColor: _G.bgTop,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('جدار الذكريات', style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
      ),
      extendBodyBehindAppBar: true,
      body: GalaxyBackground(
        child: SafeArea(
          child: list == null
              ? const Center(child: CircularProgressIndicator(color: _G.pink))
              : list.isEmpty
                  ? const Center(child: Text('بعد ماكو ذكريات 🪐', style: TextStyle(color: Colors.white70)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final m = list[i];
                          return GestureDetector(
                            onTap: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: _G.bgMid,
                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                              builder: (_) => _MemorySheet(m: m, onDeleted: () => setState(() => _m?.removeWhere((x) => x.id == m.id))),
                            ),
                            child: Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: _G.card,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: _G.pink.withValues(alpha: 0.35)),
                              ),
                              child: Column(children: [
                                Expanded(
                                  child: m.image != null
                                      ? CachedNetworkImage(imageUrl: m.image!, fit: BoxFit.cover, width: double.infinity)
                                      : Center(child: _Planet(size: 70, seed: m.id.hashCode)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(children: [
                                    Text(m.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                    Text(_d(m.day), style: const TextStyle(color: Colors.white60, fontSize: 11)),
                                  ]),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ),
    );
  }
}

// ======================= سؤال اليوم =======================
class _QuestionSheet extends StatefulWidget {
  const _QuestionSheet();
  @override
  State<_QuestionSheet> createState() => _QuestionSheetState();
}

class _QuestionSheetState extends State<_QuestionSheet> {
  Map<String, dynamic>? _q;
  final _a = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  Future<void> _load([String? answer]) async {
    setState(() => _busy = true);
    try {
      final r = await CoupleService.question(answer);
      if (mounted) setState(() => _q = r);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    final idx = ((q?['day_index'] as num?)?.toInt() ?? 0) % CoupleService.questions.length;
    final mine = q?['mine'] as String?;
    final theirs = q?['theirs'] as String?;
    final partnerDone = q?['partner_answered'] == true;
    final name = CoupleService.status.value?.partner?.name ?? 'شريكك';
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: q == null
            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(color: _G.pink)))
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('سؤال اليوم 💭', style: TextStyle(color: _G.cyan, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Text(CoupleService.questions[idx],
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.5)),
                  const SizedBox(height: 16),
                  if (mine == null) ...[
                    TextField(
                      controller: _a,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 5,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'جوابك… (جواب $name يبين بعد ما تجاوب)',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.black.withValues(alpha: 0.25),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _G.pink, foregroundColor: Colors.white),
                        onPressed: _busy
                            ? null
                            : () {
                                if (_a.text.trim().isEmpty) return;
                                _load(_a.text.trim());
                              },
                        child: const Text('جاوب', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(partnerDone ? '$name جاوب ✅ جاوب حتى تشوف جوابه' : '$name بعد ما جاوب',
                        style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
                  ] else ...[
                    _bubble('جوابك', mine, _G.cyan),
                    const SizedBox(height: 10),
                    theirs == null
                        ? _bubble(name, 'بعد ما جاوب… نذكّره؟ 😉', Colors.white38)
                        : _bubble(name, theirs, _G.pink),
                    const SizedBox(height: 8),
                    TextButton(onPressed: _busy ? null : () => _load(), child: const Text('تحديث', style: TextStyle(color: Colors.white70))),
                  ],
                ]),
              ),
      ),
    );
  }

  Widget _bubble(String who, String text, Color c) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withValues(alpha: 0.6)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(who, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12.5)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(fontSize: 15, height: 1.5)),
        ]),
      );
}

// ======================= سهرتنا: يوتيوب سوا + محادثة =======================
class WatchTogetherScreen extends StatefulWidget {
  const WatchTogetherScreen({super.key});
  @override
  State<WatchTogetherScreen> createState() => _WatchTogetherScreenState();
}

class _WatchTogetherScreenState extends State<WatchTogetherScreen> {
  static const _origin = 'https://almajhool-dev.github.io';
  late final WebViewController _web;
  RealtimeChannel? _ch;
  String? _videoId;
  String? _convId;
  bool _ready = false;
  bool _error = false;
  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastT = 0;
  DateTime _lastTickAt = DateTime.now();
  int _lastState = -1;
  Map<String, dynamic>? _pending;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Bridge', onMessageReceived: (m) => _onJs(m.message))
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (r) {
        // أي رابط يطلع برا المشغل يفتح بيوتيوب نفسه
        if (r.url.startsWith(_origin) || r.url.contains('youtube.com/embed') || r.url.startsWith('about:')) {
          return NavigationDecision.navigate;
        }
        if (r.isMainFrame) {
          launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      }));
    final pl = _web.platform;
    if (pl is AndroidWebViewController) pl.setMediaPlaybackRequiresUserGesture(false);
    _web.loadHtmlString(_html, baseUrl: '$_origin/');
    _init();
  }

  Future<void> _init() async {
    try {
      final s = CoupleService.status.value ?? await CoupleService.refresh();
      if (!s.linked) return;
      _convId = await ChatRepository().openDirect(s.partner!.id);
      if (mounted) setState(() {});
      _ch = CoupleService.watchChannel(_applyRemote);
      final st = await CoupleService.watchState();
      if (st != null && st['video_id'] != null) {
        if (_ready) {
          _applyRemote(st, force: true);
        } else {
          _pending = st;
        }
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  void dispose() {
    if (_ch != null) supa.removeChannel(_ch!);
    super.dispose();
  }

  bool get _suppressed => DateTime.now().isBefore(_suppressUntil);

  void _js(String code) => _web.runJavaScript(code).catchError((_) {});

  void _onJs(String raw) {
    Map<String, dynamic> m;
    try {
      m = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    final e = m['e'];
    final t = (m['t'] as num?)?.toDouble() ?? 0;
    if (e == 'ready') {
      setState(() => _ready = true);
      final p = _pending;
      _pending = null;
      if (p != null) _applyRemote(p, force: true);
      return;
    }
    if (e == 'error') {
      setState(() => _error = true);
      return;
    }
    final s = (m['s'] as num?)?.toInt() ?? -1;
    if (e == 'state') {
      if (_error && s == 1) setState(() => _error = false);
      if (!_suppressed && _videoId != null && (s == 1 || s == 2 || s == 0) && s != _lastState) {
        CoupleService.pushWatch(playing: s == 1, position: t);
      }
      _lastState = s;
      _lastT = t;
      _lastTickAt = DateTime.now();
    } else if (e == 'tick') {
      // كشف التقديم/الترجيع اليدوي
      final now = DateTime.now();
      final expected = _lastT + (_lastState == 1 ? now.difference(_lastTickAt).inMilliseconds / 1000 : 0);
      if (!_suppressed && _videoId != null && (t - expected).abs() > 2.5 && (s == 1 || s == 2)) {
        CoupleService.pushWatch(playing: s == 1, position: t);
      }
      _lastT = t;
      _lastTickAt = now;
      _lastState = s;
    }
  }

  void _applyRemote(Map<String, dynamic> r, {bool force = false}) {
    if (!force && r['updated_by'] == myId) return;
    final vid = r['video_id'] as String?;
    if (vid == null) return;
    final playing = r['playing'] == true;
    var pos = (r['position'] as num?)?.toDouble() ?? 0;
    final at = DateTime.tryParse((r['updated_at'] ?? '') as String);
    if (playing && at != null) {
      final lag = DateTime.now().toUtc().difference(at.toUtc()).inMilliseconds / 1000;
      if (lag > 0 && lag < 15) pos += lag;
    }
    if (!_ready) {
      _pending = r;
      return;
    }
    _suppressUntil = DateTime.now().add(const Duration(milliseconds: 2500));
    if (vid != _videoId) {
      setState(() {
        _videoId = vid;
        _error = false;
      });
      _js('load(${jsonEncode(vid)}, $pos, $playing)');
    } else {
      _js('ctl($playing, $pos)');
    }
    _lastT = pos;
    _lastTickAt = DateTime.now();
    _lastState = playing ? 1 : 2;
  }

  Future<void> _pickVideo() async {
    final c = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _G.bgMid,
        title: const Text('ابدأ سهرتكما 🍿', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: c,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'الصق رابط فيديو يوتيوب', hintStyle: TextStyle(color: Colors.white38)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final d = await Clipboard.getData('text/plain');
              if (d?.text != null) c.text = d!.text!;
            },
            child: const Text('لصق'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _G.pink),
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('تشغيل'),
          ),
        ],
      ),
    );
    c.dispose();
    if (link == null || link.trim().isEmpty) return;
    final id = CoupleService.youtubeId(link);
    if (id == null) {
      if (mounted) showSnack(context, 'هذا مو رابط يوتيوب صحيح', error: true);
      return;
    }
    _suppressUntil = DateTime.now().add(const Duration(milliseconds: 2500));
    setState(() {
      _videoId = id;
      _error = false;
    });
    _js('load(${jsonEncode(id)}, 0, true)');
    try {
      await CoupleService.pushWatch(videoId: id, playing: true, position: 0);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _syncNow() async {
    final st = await CoupleService.watchState();
    if (st != null) _applyRemote(st, force: true);
    if (mounted) showSnack(context, 'تمت المزامنة ✅');
  }

  @override
  Widget build(BuildContext context) {
    final partner = CoupleService.status.value?.partner;
    return Scaffold(
      backgroundColor: _G.bgTop,
      resizeToAvoidBottomInset: false,
      body: GalaxyBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
              child: Row(children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                ),
                const Expanded(
                  child: Text('سهرتنا 🍿',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, shadows: [Shadow(color: _G.pink, blurRadius: 10)])),
                ),
                if (_videoId != null)
                  IconButton(
                    tooltip: 'مزامنة',
                    onPressed: _syncNow,
                    icon: const Icon(Icons.sync_rounded, color: _G.cyan),
                  ),
                IconButton(
                  tooltip: 'فيديو جديد',
                  onPressed: _pickVideo,
                  icon: const Icon(Icons.add_link_rounded, color: _G.pink),
                ),
              ]),
            ),
            // المشغل بإطار نيون
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _G.cyan, width: 2),
                boxShadow: [
                  BoxShadow(color: _G.cyan.withValues(alpha: 0.5), blurRadius: 16),
                  BoxShadow(color: _G.pink.withValues(alpha: 0.35), blurRadius: 26),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(children: [
                    Positioned.fill(child: WebViewWidget(controller: _web)),
                    if (_videoId == null)
                      Positioned.fill(
                        child: Container(
                          color: _G.bgMid,
                          child: Center(
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.smart_display_rounded, color: _G.pink, size: 46),
                              const SizedBox(height: 6),
                              const Text('ابدأ سهرتكما', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                              const SizedBox(height: 2),
                              Text('شغلوا فيديو يوتيوب ويشتغل عندكم الاثنين بنفس اللحظة',
                                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: _G.pink, foregroundColor: Colors.white),
                                onPressed: _pickVideo,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('حط رابط يوتيوب'),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    if (_error && _videoId != null)
                      Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        child: Material(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            dense: true,
                            textColor: Colors.white,
                            iconColor: Colors.white,
                            leading: const Icon(Icons.info_outline_rounded),
                            title: const Text('هذا الفيديو صاحبه مانع تشغيله داخل التطبيقات'),
                            trailing: TextButton(
                              onPressed: () => launchUrl(Uri.parse('https://youtu.be/$_videoId'), mode: LaunchMode.externalApplication),
                              child: const Text('افتحه'),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (partner != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Row(children: [
                  const Icon(Icons.favorite_rounded, color: _G.pink, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('تتفرجون سوا انت و${partner.name} — أي تشغيل أو إيقاف أو تقديم يصير عند الثاني',
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                  ),
                ]),
              ),
            const SizedBox(height: 4),
            // المحادثة تحت المشغل
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                child: _convId == null
                    ? const Center(child: CircularProgressIndicator(color: _G.pink))
                    : MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: ChatScreen(conversationId: _convId!),
                      ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  static const _html = '''
<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}#p{position:absolute;top:0;left:0;width:100%;height:100%}</style>
</head><body><div id="p"></div>
<script>
var player=null, ready=false;
function send(o){try{Bridge.postMessage(JSON.stringify(o));}catch(e){}}
var tag=document.createElement('script');tag.src='https://www.youtube.com/iframe_api';document.head.appendChild(tag);
function onYouTubeIframeAPIReady(){
  player=new YT.Player('p',{width:'100%',height:'100%',
    playerVars:{playsinline:1,rel:0,modestbranding:1,fs:1,origin:'https://almajhool-dev.github.io',widget_referrer:'https://almajhool-dev.github.io'},
    events:{
      onReady:function(){ready=true;send({e:'ready'});},
      onStateChange:function(ev){send({e:'state',s:ev.data,t:player.getCurrentTime()||0});},
      onError:function(ev){send({e:'error',c:ev.data});}
    }});
}
function load(id,t,play){if(!ready)return;if(play){player.loadVideoById({videoId:id,startSeconds:t});}else{player.cueVideoById({videoId:id,startSeconds:t});}}
function ctl(play,t){if(!ready)return;var c=player.getCurrentTime()||0;if(Math.abs(c-t)>1.5){player.seekTo(t,true);}if(play){player.playVideo();}else{player.pauseVideo();}}
setInterval(function(){if(ready&&player&&player.getPlayerState){send({e:'tick',s:player.getPlayerState(),t:player.getCurrentTime()||0});}},1000);
</script></body></html>
''';
}
