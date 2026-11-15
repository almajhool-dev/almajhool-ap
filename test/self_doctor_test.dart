import 'package:almajhool_app/screens/admin/self_doctor_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// تقرير مثل اللي يرجّعه doctor_report بالخادم
Map<String, dynamic> report({int alerts = 0, int fixed = 0, String update = 'ok', List<Map<String, dynamic>> log = const []}) => {
      'last': {
        'at': DateTime.now().subtract(const Duration(minutes: 3)).toUtc().toIso8601String(),
        'fixed': fixed,
        'alerts': alerts,
        'checks': {
          'jobs_ok': 15,
          'jobs_total': 15,
          'update': update,
          'rls_fixed': 0,
          'views_fixed': 0,
          'perms_fixed': fixed,
          'storage': 'ok',
          'cron_failing': 0,
          'crashes_1h': alerts > 0 ? 6 : 0,
        },
      },
      'fixed_24h': fixed,
      'alerts_24h': alerts,
      'log': log,
    };

Future<void> open(WidgetTester tester, SelfDoctorCard card) async {
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('خادم سليم: كلشي سليم وكل الفحوصات بعلامة صح', (tester) async {
    await open(tester, SelfDoctorCard(load: () async => report()));
    expect(find.text('الطبيب الذاتي 🩺'), findsOneWidget);
    expect(find.text('كلشي سليم ✓'), findsOneWidget);
    expect(find.text('15/15 شغّالة'), findsOneWidget);
    expect(find.text('شغّال'), findsOneWidget);
    expect(find.textContaining('آخر فحص: قبل 3 دقيقة'), findsOneWidget);
    expect(find.byIcon(Icons.error_rounded), findsNothing);
    expect(find.text('افحص وصلّح هسه'), findsOneWidget);
  });

  testWidgets('مشاكل تحتاج المالك: يبين العدد، والسجل ينفتح', (tester) async {
    await open(
        tester,
        SelfDoctorCard(
          load: () async => report(alerts: 2, update: 'fail', log: [
            {'at': DateTime.now().toUtc().toIso8601String(), 'kind': 'update', 'action': 'alert', 'detail': 'التحديث التلقائي للخادم واگف'},
            {'at': DateTime.now().toUtc().toIso8601String(), 'kind': 'rls', 'action': 'fixed', 'detail': 'جدول «posts» رجعت حمايته'},
          ]),
        ));
    expect(find.text('يحتاجك (2)'), findsOneWidget);
    expect(find.text('واگف بسبب خطأ'), findsOneWidget);
    expect(find.byIcon(Icons.error_rounded), findsNWidgets(2)); // التحديث + الانهيارات
    expect(find.text('التحديث التلقائي للخادم واگف'), findsNothing);
    await tester.tap(find.text('السجل (2)'));
    await tester.pump();
    expect(find.text('التحديث التلقائي للخادم واگف'), findsOneWidget);
    expect(find.text('جدول «posts» رجعت حمايته'), findsOneWidget);
    expect(find.textContaining('يحتاجك · هسه'), findsOneWidget);
    expect(find.textContaining('صلّحها لحاله · هسه'), findsOneWidget);
  });

  testWidgets('«افحص وصلّح هسه» يشغّل الفحص ويحدّث التقرير', (tester) async {
    var loads = 0, runs = 0;
    await open(
        tester,
        SelfDoctorCard(
          load: () async {
            loads++;
            return report(fixed: loads > 1 ? 1 : 0);
          },
          run: () async {
            runs++;
            return {'fixed': 1, 'alerts': 0, 'items': []};
          },
        ));
    expect(loads, 1);
    await tester.tap(find.text('افحص وصلّح هسه'));
    await tester.pump();
    await tester.pump();
    expect(runs, 1);
    expect(loads, 2);
    expect(find.text('خلص الفحص: صلّح 1، ويحتاجك 0'), findsOneWidget);
    expect(find.text('صلّح 1'), findsOneWidget); // حماية الجداول والصلاحيات بعد التحديث
  });

  testWidgets('فحص سليم يدوي يگول سليم، والرفض يطلع رسالته', (tester) async {
    var first = true;
    await open(
        tester,
        SelfDoctorCard(
          load: () async => report(),
          run: () async {
            if (first) {
              first = false;
              return {'fixed': 0, 'alerts': 0};
            }
            throw Exception('انتظر ثواني وجرّب مرة ثانية');
          },
        ));
    await tester.tap(find.text('افحص وصلّح هسه'));
    await tester.pump();
    await tester.pump();
    expect(find.text('فحصت كلشي: سليم ✅'), findsOneWidget);
    await tester.tap(find.text('افحص وصلّح هسه'));
    await tester.pump();
    await tester.pump();
    expect(find.text('انتظر ثواني وجرّب مرة ثانية'), findsOneWidget);
  });

  testWidgets('قبل أول فحص، وإذا التقرير مرفوض (مو المالك)', (tester) async {
    await open(tester, SelfDoctorCard(load: () async => {'last': null, 'fixed_24h': 0, 'alerts_24h': 0, 'log': []}));
    expect(find.text('بعده ما فحص'), findsOneWidget);
    expect(find.textContaining('آخر فحص'), findsNothing);

    await open(tester, SelfDoctorCard(key: UniqueKey(), load: () async => throw Exception('للمالك فقط')));
    expect(find.text('للمالك فقط'), findsOneWidget);
  });

  // ===== قائمة الفحوصات الكاملة (الخادم يرسلها جاهزة بالعربي) =====
  Map<String, dynamic> fullReport() => {
        'last': {
          'at': DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String(),
          'fixed': 1,
          'alerts': 1,
          'worst': 'alert',
          'list': [
            {'g': 'الخادم', 'n': 'مهام الخادم الأساسية', 's': 'ok', 'v': '15/15 شغّالة', 'h': ''},
            {'g': 'الخادم', 'n': 'حجم قاعدة البيانات', 's': 'info', 'v': '120 ميگا', 'h': ''},
            {'g': 'الأمان', 'n': 'خزنة الأسرار والمحافظ', 's': 'fixed', 'v': 'رجّع قفل 1 جدول', 'h': ''},
            {'g': 'الإشعارات', 'n': 'إشعارات Google', 's': 'ok', 'v': 'جاهزة', 'h': 'شرح الإشعارات'},
            {'g': 'التطبيق عند المستخدمين', 'n': 'أخطاء يشوفها المستخدمين (آخر ساعة)', 's': 'alert', 'v': '12', 'h': ''},
            {'g': 'البيانات والفلوس', 'n': 'طلبات السحب المعلقة', 's': 'warn', 'v': '2 تنتظرك', 'h': ''},
          ],
        },
        'fixed_24h': 1,
        'alerts_24h': 1,
        'since': '2026-11-15',
        'days': [
          {'d': '2026-11-15', 'worst': 'alert', 'fixed': 1, 'alerts': 1, 'crashes': 0, 'devices': 40, 'db_mb': 120},
          {'d': '2026-11-14', 'worst': 'ok', 'fixed': 0, 'alerts': 0, 'crashes': 0, 'devices': 38},
        ],
        'log': [
          {'at': DateTime.now().toUtc().toIso8601String(), 'action': 'alert', 'detail': 'خطأ يتكرر عند المستخدمين ⟵ يعني: صلاحية ناقصة'},
        ],
      };

  testWidgets('البطاقة بالقائمة الكاملة: تبين المشاكل بس + عدد كل الفحوصات', (tester) async {
    await open(tester, SelfDoctorCard(load: () async => fullReport()));
    expect(find.text('يحتاجك (1)'), findsOneWidget);
    expect(find.textContaining('6 فحص: 2 سليم · 1 صلّحها · 1 ينراد انتباه · 1 يحتاجك'), findsOneWidget);
    // المشاكل تطلع، والسليم لا
    expect(find.text('أخطاء يشوفها المستخدمين (آخر ساعة)'), findsOneWidget);
    expect(find.text('طلبات السحب المعلقة'), findsOneWidget);
    expect(find.text('خزنة الأسرار والمحافظ'), findsOneWidget);
    expect(find.text('مهام الخادم الأساسية'), findsNothing);
    expect(find.text('كل الفحوصات (6)'), findsOneWidget);
  });

  testWidgets('الشاشة الكاملة: كل المجموعات والفحوصات وصحة الأيام والسجل بالعربي', (tester) async {
    tester.view.physicalSize = const Size(900, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var runs = 0;
    await open(
        tester,
        SelfDoctorCard(
          load: () async => fullReport(),
          run: () async {
            runs++;
            return {'fixed': 0, 'alerts': 1};
          },
        ));
    await tester.tap(find.text('كل الفحوصات (6)'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (final g in ['الخادم', 'الأمان', 'الإشعارات', 'التطبيق عند المستخدمين', 'البيانات والفلوس']) {
      expect(find.text(g), findsOneWidget, reason: g);
    }
    expect(find.text('مهام الخادم الأساسية'), findsOneWidget);
    expect(find.text('120 ميگا'), findsOneWidget);
    expect(find.text('شرح الإشعارات'), findsOneWidget);
    expect(find.text('صحة التطبيق آخر 2 يوم'), findsOneWidget);
    expect(find.text('15/11'), findsOneWidget);
    expect(find.textContaining('أجهزة 40 · 120 ميگا'), findsOneWidget);
    expect(find.textContaining('يراقب صحة التطبيق من 15/11/2026'), findsOneWidget);
    expect(find.text('خطأ يتكرر عند المستخدمين ⟵ يعني: صلاحية ناقصة'), findsOneWidget);
    // الزر اللي بالشاشة (البطاقة بعدها موجودة تحتها)
    await tester.tap(find.descendant(of: find.byType(SelfDoctorScreen), matching: find.text('افحص وصلّح هسه')));
    await tester.pump();
    await tester.pump();
    expect(runs, 1);
    expect(find.descendant(of: find.byType(SelfDoctorScreen), matching: find.text('خلص الفحص: صلّح 0، ويحتاجك 1')),
        findsOneWidget);
  });
}
