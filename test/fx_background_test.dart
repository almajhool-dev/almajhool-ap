import 'package:almajhool_app/services/core_services.dart';
import 'package:almajhool_app/widgets/fx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
  });

  // كم مرة انرسمت كل طبقة من الخلفية
  int paints(WidgetTester t, int layer) {
    final rb = t.renderObject<RenderRepaintBoundary>(
        find.descendant(of: find.byType(FxBackground), matching: find.byType(RepaintBoundary)).at(layer));
    return rb.debugSymmetricPaintCount + rb.debugAsymmetricPaintCount;
  }

  // ساعة الخلفية تمشي بالوقت الحقيقي: نخلي وقت حقيقي صغير يعبر بين الإطارات
  // (بدونه العدّ يعتمد على سرعة الجهاز والاختبار يفشل أحيانًا)
  Future<void> run(WidgetTester t, int frames) async {
    for (var i = 0; i < frames; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 3)));
      await t.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets('الطبقة الثقيلة تنرسم مرة وحدة، والحركة خفيفة وتوكف عند اللمس', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FxBackground(forceOn: true, child: SizedBox.expand()),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    final base0 = paints(tester, 0), dyn0 = paints(tester, 1);
    await run(tester, 12); // ~ثانية وحدة
    final base1 = paints(tester, 0), dyn1 = paints(tester, 1);

    // الأضواء الكبيرة (الأثقل) ما تنعاد أبدًا — چانت تنرسم 30 مرة بالثانية
    expect(base1 - base0, 0, reason: 'الطبقة الثقيلة لازم ما تنعاد');
    // النجوم تتحرك (~12 مرة بالثانية)
    expect(dyn1 - dyn0, greaterThanOrEqualTo(8), reason: 'الحركة الخفيفة شغّالة');

    // لمس (مثل فتح محادثة): الحركة توكف
    final g = await tester.startGesture(const Offset(100, 100));
    await tester.pump(const Duration(milliseconds: 80));
    final dyn2 = paints(tester, 1);
    await run(tester, 10);
    expect(paints(tester, 1) - dyn2, 0, reason: 'أثناء اللمس: ماكو رسم أبدًا');

    // بعد اللمس والانتقال: ترجع
    await g.up();
    await tester.pump(const Duration(milliseconds: 1000));
    final dyn3 = paints(tester, 1);
    await run(tester, 8);
    expect(paints(tester, 1) - dyn3, greaterThanOrEqualTo(5), reason: 'بعد اللمس: الحركة رجعت');
    expect(paints(tester, 0) - base0, 0, reason: 'والطبقة الثقيلة بعدها ما انعادت');

    await tester.pumpWidget(const SizedBox());
  });
}
