import 'package:almajhool_app/services/core_services.dart';
import 'package:almajhool_app/widgets/fx.dart';
import 'package:almajhool_app/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
  });

  Widget app() => MaterialApp(
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.transparent, // مثل التطبيق: الشاشات شفافة
          pageTransitionsTheme: const PageTransitionsTheme(builders: {TargetPlatform.android: FxPageTransition()}),
        ),
        builder: (c, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const Scaffold(body: Text('المحادثة')))),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
      );

  bool opaque(WidgetTester t) {
    final p = find.descendant(of: find.byType(FxOpaqueWhileMoving), matching: find.byType(CustomPaint));
    return p.evaluate().any((e) => (e.widget as CustomPaint).painter != null);
  }

  testWidgets('فتح محادثة: انزلاق بدون تلاشي، وخلفية معتمة أثناء الحركة بس (ماكو تداخل)', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('افتح'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120)); // نص الانتقال

    // ماكو أي تلاشي (شفافية) بالانتقال — هذا اللي چان يثقّل ويداخل الشاشتين
    final route = find.ancestor(of: find.text('المحادثة'), matching: find.byType(FadeTransition));
    expect(route, findsNothing, reason: 'الانتقال لازم يكون انزلاق بدون تلاشي');

    // الشاشة الجديدة معتمة أثناء الحركة: تغطي القائمة اللي تحتها
    expect(opaque(tester), isTrue, reason: 'أثناء الانتقال: خلفية معتمة');

    // بالعربي تجي من اليسار: بنص الحركة بعدها مزاحة لليسار
    final x = tester.getTopLeft(find.text('المحادثة')).dx;
    await tester.pumpAndSettle();
    final xEnd = tester.getTopLeft(find.text('المحادثة')).dx;
    expect(x, lessThan(xEnd), reason: 'تنزلق من اليسار (عربي)');

    // بعد ما يخلص: ترجع شفافة حتى تبين الخلفية المتحركة
    expect(opaque(tester), isFalse, reason: 'بعد الانتقال: شفافة مثل قبل');
  });

  testWidgets('الرسالة الصوتية ما تخلق مشغّل صوت أصلي إلا لما تضغط تشغيل', (tester) async {
    // چان المشغّل الأصلي ينخلق لكل رسالة صوتية أول ما تنعرض (أثناء الانتقال = تعليق).
    // نعدّ الطلبات اللي تروح لمشغّل الصوت بالنظام: لازم صفر وقت العرض.
    // المكتبة تنادي أول القناة العامة (تهيئة) وبعدها قناة المشغّل (create) — نجاوب الثنتين
    // حتى لو انخلق مشغّل ينحسب فعلًا
    final calls = <String>[];
    const ch = MethodChannel('xyz.luan/audioplayers');
    const global = MethodChannel('xyz.luan/audioplayers.global');
    final m = tester.binding.defaultBinaryMessenger;
    m.setMockMethodCallHandler(global, (c) async => null);
    m.setMockMethodCallHandler(ch, (c) async {
      calls.add(c.method);
      return null;
    });
    addTearDown(() {
      m.setMockMethodCallHandler(ch, null);
      m.setMockMethodCallHandler(global, null);
    });

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          AudioBubble(path: 'conv/v1.m4a', color: Colors.white),
          AudioBubble(path: 'conv/v2.m4a', color: Colors.white),
          AudioBubble(path: 'conv/v3.m4a', color: Colors.white),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    expect(calls.where((m) => m == 'create'), isEmpty, reason: 'عرض 3 رسائل صوتية ما يخلق ولا مشغّل');
    expect(find.byIcon(Icons.play_circle_fill), findsNWidgets(3));
  });
}
