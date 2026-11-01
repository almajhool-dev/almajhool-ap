// الستريك 🔥 (مثل سناب): الموديل، الشارة، قائمة المحادثات، وورقة الشرح.
import 'package:almajhool_app/models/models.dart';
import 'package:almajhool_app/providers/providers.dart';
import 'package:almajhool_app/screens/home/home_shell.dart';
import 'package:almajhool_app/services/core_services.dart';
import 'package:almajhool_app/widgets/streak.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _row({int? streak, bool? expiring}) => {
      'id': 'c1',
      'type': 'direct',
      'last_message_at': '2026-11-01T17:00:00Z',
      'last_message_preview': 'هلا',
      'other_user_id': 'u2',
      'other_username': 'zahraa',
      'other_display_name': 'زهراء',
      if (streak != null) 'streak': streak,
      if (expiring != null) 'streak_expiring': expiring,
    };

Widget _rtl(Widget child) => MaterialApp(
      home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: child)),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
    await initializeDateFormatting('ar');
  });

  group('الموديل', () {
    test('يقرا الستريك من الخادم ويرجّعه بالكاش', () {
      final c = ConversationSummary.fromMap(_row(streak: 12, expiring: true));
      expect(c.streak, 12);
      expect(c.streakExpiring, isTrue);
      final back = ConversationSummary.fromMap(c.toMap());
      expect(back.streak, 12);
      expect(back.streakExpiring, isTrue);
    });

    test('كاش قديم (قبل الستريك) ما يكسر: صفر وبدون ⏳', () {
      final c = ConversationSummary.fromMap(_row());
      expect(c.streak, 0);
      expect(c.streakExpiring, isFalse);
    });
  });

  group('الشارة', () {
    test('النص: الرقم و🔥، و💯 بكل 100، و⏳ إذا راح ينتهي', () {
      expect(StreakBadge.label(7), '7🔥');
      expect(StreakBadge.label(7, expiring: true), '7🔥⏳');
      expect(StreakBadge.label(100), '100🔥💯');
      expect(StreakBadge.label(200, expiring: true), '200🔥💯⏳');
      expect(StreakBadge.label(101), '101🔥');
    });

    testWidgets('صفر = ماكو شي ينرسم', (tester) async {
      await tester.pumpWidget(_rtl(const StreakBadge(streak: 0)));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('الضغط عليها يشتغل', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_rtl(Center(child: StreakBadge(streak: 5, onTap: () => taps++))));
      await tester.tap(find.text('5🔥'));
      expect(taps, 1);
    });
  });

  group('قائمة المحادثات', () {
    late ChatHub hub;
    setUp(() {
      // ConnectivityService يسأل النظام عن النت — نجاوبه بالاختبار
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/connectivity'), (c) async => ['wifi']);
      m.setMockStreamHandler(const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
          MockStreamHandler.inline(onListen: (_, __) {}));
      hub = ChatHub(ConnectivityService());
    });

    Future<void> pumpTile(WidgetTester tester, ConversationSummary c) => tester.pumpWidget(
          ChangeNotifierProvider<ChatHub>.value(value: hub, child: _rtl(ConversationTile(conv: c))),
        );

    testWidgets('يطلع 🔥 يم اسم الصديق', (tester) async {
      await pumpTile(tester, ConversationSummary.fromMap(_row(streak: 12)));
      expect(find.text('زهراء'), findsOneWidget);
      expect(find.text('12🔥'), findsOneWidget);
      // الشارة يسار الاسم (بالعربي تجي بعده)
      expect(tester.getCenter(find.text('12🔥')).dx, lessThan(tester.getCenter(find.text('زهراء')).dx));
    });

    testWidgets('⏳ إذا راح ينتهي الليلة', (tester) async {
      await pumpTile(tester, ConversationSummary.fromMap(_row(streak: 4, expiring: true)));
      expect(find.text('4🔥⏳'), findsOneWidget);
    });

    testWidgets('بدون ستريك: ماكو 🔥 أبد', (tester) async {
      await pumpTile(tester, ConversationSummary.fromMap(_row()));
      expect(find.textContaining('🔥'), findsNothing);
    });

    testWidgets('اسم طويل جدًا ما يخرب السطر (ماكو overflow)', (tester) async {
      final long = _row(streak: 365)..['other_display_name'] = 'اسم طويل كلش كلش كلش حتى نشوف شلون يتقص بالنص';
      await pumpTile(tester, ConversationSummary.fromMap(long));
      expect(tester.takeException(), isNull);
      expect(find.text('365🔥'), findsOneWidget);
    });
  });

  group('ورقة الشرح', () {
    testWidgets('تعرض الستريك ومنو أرسل اليوم وأطول ستريك والوقت الباقي', (tester) async {
      await tester.pumpWidget(_rtl(StreakSheet(
        conversationId: 'c1',
        name: 'زهراء',
        streak: 6,
        expiring: true,
        loader: (_) async => {
          'streak': 6,
          'expiring': true,
          'best': 9,
          'me_today': true,
          'other_today': false,
          'hours_left': 3.4,
          'min': 3,
        },
      )));
      await tester.pumpAndSettle();
      expect(find.text('6 يوم'), findsOneWidget);
      expect(find.text('الستريك ويا زهراء'), findsOneWidget);
      expect(find.textContaining('بعد 3 ساعات'), findsOneWidget);
      expect(find.text('انت أرسلت اليوم'), findsOneWidget);
      expect(find.text('زهراء بعده ما أرسل اليوم'), findsOneWidget);
      expect(find.text('أطول ستريك وصلتوله: 9 يوم'), findsOneWidget);
      expect(find.textContaining('من تكملون 3 أيام'), findsOneWidget);
    });

    testWidgets('بدون نت: تعرض الشرح بس (بدون تعليق على التحميل)', (tester) async {
      await tester.pumpWidget(_rtl(StreakSheet(
        conversationId: 'c1',
        name: 'علي',
        streak: 100,
        loader: (_) async => throw Exception('offline'),
      )));
      await tester.pumpAndSettle();
      expect(find.text('100 يوم'), findsOneWidget);
      expect(find.text('الستريك ويا علي 💯'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('شلون يشتغل الستريك؟'), findsOneWidget);
    });
  });
}
