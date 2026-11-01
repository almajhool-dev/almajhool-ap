// قياس: كم ياخذ بناء أول شاشة محادثة (60 رسالة متنوعة) — قبل وبعد التحسين.
import 'package:almajhool_app/models/models.dart';
import 'package:almajhool_app/services/core_services.dart';
import 'package:almajhool_app/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Message> _msgs() {
  final now = DateTime(2026, 11, 1, 18);
  const long = 'الشكر لله تم الك يا غالي، وتحياتك واصلة للمجهول ولكل فريق العمل بالتطبيق، وهم يفتخرون بوجود ناس متفاعلين ومحترفين مثلك. '
      'بالتوفيق بمتجرك وإن شاء الله دائمًا تشوف الأفضل ويانا في تطبيق VYFRI، وإذا احتجت أي شي بالمستقبل فأنا بالخدمة دائمًا.';
  final out = <Message>[];
  for (var i = 0; i < 60; i++) {
    final k = i % 6;
    out.add(Message(
      id: 'm$i',
      conversationId: 'c',
      senderId: i.isEven ? 'me' : 'other',
      type: k == 4 ? 'audio' : 'text',
      content: switch (k) {
        0 => 'هلا حبيبي شلونك؟ @ali_99',
        1 => long,
        2 => 'شوف هذا الموقع https://lumacraft-ew79.whacka.app يعني قصدي نفس هاي التفاصيل',
        3 => 'اوكي لا تصدق حبيت اساعدك 😂😂',
        _ => 'تمام',
      },
      mediaPath: k == 4 ? 'c/voice$i.m4a' : null,
      createdAt: now.subtract(Duration(minutes: i)),
    ));
  }
  return out;
}

Widget _chat(List<Message> ms) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ListView.builder(
            reverse: true,
            itemCount: ms.length,
            itemBuilder: (_, i) => MessageBubble(key: ValueKey(ms[i].id), message: ms[i], mine: ms[i].senderId == 'me'),
          ),
        ),
      ),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
    await initializeDateFormatting('ar');
  });

  testWidgets('قياس بناء أول شاشة محادثة', (tester) async {
    tester.view.physicalSize = const Size(1080, 2412);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final ms = _msgs();
    // تسخين (أول مرة فيها تحميل خطوط وغيره)
    await tester.pumpWidget(_chat(ms));
    await tester.pumpWidget(const SizedBox());
    final times = <int>[];
    for (var r = 0; r < 8; r++) {
      final sw = Stopwatch()..start();
      await tester.pumpWidget(_chat(ms));
      sw.stop();
      times.add(sw.elapsedMicroseconds);
      await tester.pumpWidget(const SizedBox());
    }
    times.sort();
    // ignore: avoid_print
    print('CHAT_FIRST_BUILD_MEDIAN_US=${times[times.length ~/ 2]} MIN_US=${times.first}');
  });
}
