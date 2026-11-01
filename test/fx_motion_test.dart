// حركة الخلفيات بيد المالك بس، وخلفيات المستخدمين (ألوان أو صورة) ثابتة دائمًا.
import 'package:almajhool_app/screens/settings/themes_screen.dart';
import 'package:almajhool_app/services/core_services.dart';
import 'package:almajhool_app/services/fx_settings.dart';
import 'package:almajhool_app/widgets/fx.dart';
import 'package:almajhool_app/widgets/fx_motion_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final fx = FxSettings.instance;

// كم مرة انرسمت طبقة الحركة (الطبقة الثانية) من الخلفية
int movingPaints(WidgetTester t, {int which = 0}) {
  final rb = t.renderObject<RenderRepaintBoundary>(find
      .descendant(of: find.byType(FxBackground).at(which), matching: find.byType(RepaintBoundary))
      .at(1));
  return rb.debugSymmetricPaintCount + rb.debugAsymmetricPaintCount;
}

// ~ثانية من الحركة. ساعة الخلفية تمشي بالوقت الحقيقي، فنخلي وقت حقيقي صغير يعبر بين الإطارات
Future<void> second(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 3)));
    await t.pump(const Duration(milliseconds: 80));
  }
}

class _Probe extends StatefulWidget {
  const _Probe();
  static int mounts = 0;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.mounts++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
    fx.load();
    fx.setMotion(true);
    fx.select('aurora');
    for (final t in [...fx.custom]) {
      fx.removeCustom(t.id);
    }
  });

  group('حفظ الخلفيات', () {
    test('خلفيات المستخدم القديمة (قبل التحديث) تصير ثابتة', () {
      final t = FxTheme.fromJson({'id': 'my_1', 'name': 'سمتي', 'base': 'matrix', 'colors': []}, custom: true);
      expect(t.still, isTrue);
      expect(t.base, 'matrix');
    });

    test('سمة المالك المتحركة تبقى متحركة', () {
      final t = FxTheme.fromJson({'id': 'my_2', 'base': 'waves', 'still': false}, custom: true);
      expect(t.still, isFalse);
    });

    test('سمات المالك المنشورة تتحرك (وما تقبل مسار صورة)', () {
      final t = FxTheme.fromJson({'id': 'pub_1', 'base': 'photo', 'path': '/x.jpg'}, published: true);
      expect(t.still, isFalse);
      expect(t.isPhoto, isFalse);
      expect(t.path, isNull);
    });

    test('خلفية الصورة تنحفظ وترجع بنفس المسار', () {
      const t = FxTheme(id: 'photo_1', name: 'صورة', base: 'photo', colors: [], still: true, path: '/data/bg.img');
      final back = FxTheme.fromJson(t.toJson(), custom: true);
      expect(back.isPhoto, isTrue);
      expect(back.path, '/data/bg.img');
      expect(back.still, isTrue);
    });

    test('صورة بدون مسار ترجع خلفية عادية', () {
      final t = FxTheme.fromJson({'id': 'x', 'base': 'photo'}, custom: true);
      expect(t.isPhoto, isFalse);
      expect(t.base, 'aurora');
    });
  });

  group('منو يتحرك', () {
    test('الحركة بيد المالك: يطفيها ← ولا خلفية تتحرك', () {
      final builtin = FxSettings.builtins.first;
      const still = FxTheme(id: 'm', name: 'm', base: 'waves', colors: [], still: true);
      const photo = FxTheme(id: 'p', name: 'p', base: 'photo', colors: [], still: true, path: '/a');
      expect(fx.animates(builtin), isTrue);
      expect(fx.animates(still), isFalse, reason: 'خلفية المستخدم ثابتة دائمًا');
      expect(fx.animates(photo), isFalse);
      fx.setMotion(false);
      expect(fx.animates(builtin), isFalse);
    });

    test('آخر حالة من الخادم تنحفظ بالجهاز', () {
      fx.setMotion(false);
      expect(CacheService.getString('fx_motion'), '0');
      fx.setMotion(true);
      expect(CacheService.getString('fx_motion'), '1');
    });

    testWidgets('المالك يطفي الحركة ← الخلفية توكف فورًا، ويشغّلها ← ترجع', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: FxBackground(child: SizedBox.expand())));
      await tester.pump(const Duration(milliseconds: 100));
      var p0 = movingPaints(tester);
      await second(tester);
      expect(movingPaints(tester) - p0, greaterThanOrEqualTo(8), reason: 'شغّالة');

      fx.setMotion(false); // مثل ما يوصل من الخادم
      await tester.pump();
      p0 = movingPaints(tester);
      await second(tester);
      expect(movingPaints(tester) - p0, 0, reason: 'واكفة عند الكل');

      fx.setMotion(true);
      await tester.pump();
      p0 = movingPaints(tester);
      await second(tester);
      expect(movingPaints(tester) - p0, greaterThanOrEqualTo(8), reason: 'رجعت');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('خلفية المستخدم الثابتة ما تتحرك حتى والحركة شغّالة', (tester) async {
      const mine = FxTheme(
          id: 'my_s', name: 'خلفيتي', base: 'matrix', colors: [Colors.red, Colors.green, Colors.blue], still: true);
      await tester.pumpWidget(const MaterialApp(home: FxBackground(theme: mine, child: SizedBox.expand())));
      await tester.pump(const Duration(milliseconds: 100));
      final p0 = movingPaints(tester);
      await second(tester);
      expect(movingPaints(tester) - p0, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('معاينة المالك وهو يصمم سمة متحركة تتحرك حتى والحركة طافية', (tester) async {
      fx.setMotion(false);
      await tester.pumpWidget(const MaterialApp(home: FxBackground(forceOn: true, child: SizedBox.expand())));
      await tester.pump(const Duration(milliseconds: 100));
      final p0 = movingPaints(tester);
      await second(tester);
      expect(movingPaints(tester) - p0, greaterThanOrEqualTo(8));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('خلفية صورة', () {
    testWidgets('تطلع الصورة (مع تعتيم)، وتبديل الخلفية ما يعيد بناء شاشات التطبيق', (tester) async {
      _Probe.mounts = 0;
      await tester.pumpWidget(const MaterialApp(home: FxBackground(child: _Probe())));
      expect(_Probe.mounts, 1);

      fx.addCustom(const FxTheme(
          id: 'photo_t', name: 'صورة من معرضي', base: 'photo', colors: [], still: true, path: '/no/such/bg.img'));
      await tester.pump();

      final boxes = tester.widgetList<DecoratedBox>(
          find.descendant(of: find.byType(FxBackground), matching: find.byType(DecoratedBox)));
      final img = boxes
          .map((b) => b.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.image)
          .whereType<DecorationImage>()
          .toList();
      expect(img, hasLength(1));
      expect((img.single.image as FileImage).file.path, '/no/such/bg.img');
      expect(img.single.colorFilter, isNotNull, reason: 'تعتيم حتى الكتابة تبقى واضحة');
      expect(_Probe.mounts, 1, reason: 'الشاشات نفسها ما انبنت من جديد');

      // ترجع للسمة العادية: نفس الشي
      fx.select('aurora');
      await tester.pump();
      expect(_Probe.mounts, 1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('زر المالك', () {
    testWidgets('يطفي الحركة للكل (يحفظ بالخادم)', (tester) async {
      final saved = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FxMotionSwitch(save: (on) async => saved.add(on))),
      ));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(saved, [false]);
      expect(fx.motion, isFalse);
      expect(find.text('وقفت حركة الخلفيات عند كل المستخدمين'), findsOneWidget);
    });

    testWidgets('إذا الحفظ فشل ترجع مثل ما چانت', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: FxMotionSwitch(save: (on) async => throw Exception('للمالك فقط'))),
      ));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(fx.motion, isTrue);
      expect(find.text('للمالك فقط'), findsOneWidget);
    });
  });

  group('شاشة الخلفيات', () {
    Future<void> open(WidgetTester tester, {required bool owner}) async {
      fx.setMotion(false); // بدون مؤقتات حركة بالاختبار
      await tester.pumpWidget(MaterialApp(home: ThemesScreen(owner: owner)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> openAddSheet(WidgetTester tester) async {
      await tester.tap(find.text('خلفية جديدة'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('المستخدم: ماكو زر حركة، ويضيف بس خلفيات ثابتة', (tester) async {
      await open(tester, owner: false);
      expect(find.byType(FxMotionSwitch), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('يتحكم بيها مالك التطبيق'), findsOneWidget);
      await openAddSheet(tester);
      expect(find.text('صورة من معرضك 🖼️'), findsOneWidget);
      expect(find.text('ألوان ونقوش 🎨'), findsOneWidget);
      expect(find.text('سمة متحركة ✨'), findsNothing);
    });

    testWidgets('المالك: زر الحركة للكل، ويكدر يسوّي سمة متحركة', (tester) async {
      await open(tester, owner: true);
      expect(find.byType(FxMotionSwitch), findsOneWidget);
      await openAddSheet(tester);
      expect(find.text('سمة متحركة ✨'), findsOneWidget);
    });

    testWidgets('خلفية الألوان اللي يسويها المستخدم تنحفظ ثابتة', (tester) async {
      await open(tester, owner: false);
      await openAddSheet(tester);
      await tester.tap(find.text('ألوان ونقوش 🎨'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('خلفية ثابتة جديدة 🎨'), findsOneWidget);
      expect(find.text('النقشة:'), findsOneWidget);
      await tester.tap(find.text('حفظ وتطبيق'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fx.custom, hasLength(1));
      expect(fx.custom.single.still, isTrue);
      expect(fx.current.id, fx.custom.single.id, reason: 'تطبّقت');
    });
  });
}
