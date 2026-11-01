// الخلفية المخبوزة (صورة وحدة) لازم تطلع نفس الرسم الأصلي بالضبط تقريبًا — بشاشة كثافتها 3 مثل الهاتف.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:almajhool_app/services/core_services.dart';
import 'package:almajhool_app/services/fx_settings.dart';
import 'package:almajhool_app/widgets/fx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// نفس الرسم الأصلي (قبل الخبز) — مرجع للمقارنة
class _Reference extends CustomPainter {
  final List<Color> c;
  _Reference(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF0A0E17));
    const alpha = 0.24;
    const blobs = [(0, 0.25, 0.34, 0.62), (1, 0.93, 0.38, 0.70), (2, 0.635, 0.93, 0.58)];
    final m = math.max(s.width, s.height);
    for (final b in blobs) {
      final col = c[b.$1];
      final o = Offset(b.$2 * s.width, b.$3 * s.height);
      final r = b.$4 * m * 0.6;
      canvas.drawCircle(o, r, Paint()
        ..shader = RadialGradient(colors: [col.withValues(alpha: alpha), col.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: o, radius: r)));
    }
  }

  @override
  bool shouldRepaint(_Reference o) => false;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'anon::fx_enabled': '0'});
    await CacheService.init();
  });

  testWidgets('الخلفية المخبوزة نفس شكل الأصلية', (tester) async {
    tester.view.physicalSize = const Size(1080, 2412);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    FxSettings.instance.load();
    final colors = FxSettings.instance.current.colors;

    final kBaked = GlobalKey(), kRef = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Stack(children: [
        RepaintBoundary(key: kBaked, child: const FxBackground(child: SizedBox.expand())),
        Offstage(child: RepaintBoundary(key: kRef, child: CustomPaint(painter: _Reference(colors), size: const Size(360, 804)))),
      ]),
    ));
    await tester.pump();

    Future<ByteData> grab(GlobalKey k) async {
      final rb = k.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await rb.toImage(pixelRatio: 3);
      return (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    }

    // الطبقة الثابتة بس (أول RepaintBoundary داخل الخلفية) — بدون طبقة النجوم
    Future<ByteData> grabBase() async {
      final rb = tester.renderObject<RenderRepaintBoundary>(
          find.descendant(of: find.byType(FxBackground), matching: find.byType(RepaintBoundary)).at(0));
      final img = await rb.toImage(pixelRatio: 3);
      return (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    }

    late ByteData a, b;
    await tester.runAsync(() async {
      a = await grabBase();
    });
    // المرجع مخفي (Offstage) — نرسمه لوحده
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(key: kRef, child: CustomPaint(painter: _Reference(colors), child: const SizedBox.expand())),
    ));
    await tester.runAsync(() async {
      b = await grab(kRef);
    });

    // نقارن نقاط على كل الشاشة (الطبقة الثابتة بس)
    var worst = 0;
    const w = 1080;
    for (var y = 40; y < 2412; y += 97) {
      for (var x = 40; x < 1080; x += 89) {
        final i = (y * w + x) * 4;
        var d = 0;
        for (var ch = 0; ch < 3; ch++) {
          d = math.max(d, (a.getUint8(i + ch) - b.getUint8(i + ch)).abs());
        }
        worst = math.max(worst, d);
      }
    }
    // ignore: avoid_print
    print('BAKED_VS_ORIGINAL_MAX_DIFF=$worst/255');
    expect(worst, lessThanOrEqualTo(8), reason: 'الفرق لازم ما يبيّن بالعين');
  });
}
