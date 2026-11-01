import 'package:flutter/material.dart';

import '../services/core_services.dart';

/// لون الستريك 🔥 (برتقالي ناري — واضح على الفاتح والغامق)
const kStreakColor = Color(0xFFFF7A00);

/// 🔥 الستريك (مثل سناب): كم يوم ورا بعض تراسلتوا، و⏳ إذا راح ينتهي الليلة، و💯 بكل 100 يوم.
class StreakBadge extends StatelessWidget {
  final int streak;
  final bool expiring;
  final double fontSize;
  final VoidCallback? onTap;
  const StreakBadge({super.key, required this.streak, this.expiring = false, this.fontSize = 13, this.onTap});

  /// النص نفسه: الرقم بعده 🔥 (وبعدها 💯 و⏳ إذا لازم) — بالعربي يتقرا «12🔥»
  static String label(int streak, {bool expiring = false}) =>
      '$streak🔥${streak % 100 == 0 ? '💯' : ''}${expiring ? '⏳' : ''}';

  @override
  Widget build(BuildContext context) {
    if (streak <= 0) return const SizedBox.shrink();
    Widget t = Text(
      label(streak, expiring: expiring),
      maxLines: 1,
      softWrap: false,
      textDirection: TextDirection.rtl,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: kStreakColor, height: 1.15),
    );
    t = Semantics(label: 'ستريك $streak يوم${expiring ? '، راح ينتهي الليلة' : ''}', excludeSemantics: true, child: t);
    if (onTap == null) return t;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // حشوة جانبية بس (مساحة ضغط أوسع) — بدون ما تزيد ارتفاع سطر الاسم بالعنوان
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), child: t),
    );
  }
}

/// شرح الستريك + تفاصيله (أطول ستريك، منو أرسل اليوم، وكم ساعة باقية) — يفتح من 🔥 داخل المحادثة.
Future<void> showStreakSheet(BuildContext context,
    {required String conversationId, required String name, required int streak, bool expiring = false}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => StreakSheet(conversationId: conversationId, name: name, streak: streak, expiring: expiring),
  );
}

class StreakSheet extends StatefulWidget {
  final String conversationId;
  final String name;
  final int streak;
  final bool expiring;

  /// للاختبار: بدل طلب الخادم
  final Future<Map<String, dynamic>> Function(String conversationId)? loader;

  const StreakSheet({
    super.key,
    required this.conversationId,
    required this.name,
    required this.streak,
    this.expiring = false,
    this.loader,
  });

  @override
  State<StreakSheet> createState() => _StreakSheetState();
}

class _StreakSheetState extends State<StreakSheet> {
  Map<String, dynamic>? _info;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final load = widget.loader ??
          (String id) async =>
              Map<String, dynamic>.from(await supa.rpc('get_streak_info', params: {'p_conv': id}) as Map);
      final info = await load(widget.conversationId);
      if (mounted) setState(() => _info = info);
    } catch (_) {
      if (mounted) setState(() => _failed = true); // بدون نت: نعرض الشرح بس
    }
  }

  int get _streak => ((_info?['streak'] ?? widget.streak) as num).toInt();
  bool get _expiring => (_info?['expiring'] ?? widget.expiring) as bool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.65);
    final info = _info;
    final hours = (info?['hours_left'] as num?)?.toDouble();

    Widget todayRow(bool done, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(done ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded,
                size: 20, color: done ? Colors.green : kStreakColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
        );

    Widget rule(String emoji, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 26, child: Text(emoji, style: const TextStyle(fontSize: 15))),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13.5, color: muted, height: 1.35))),
          ]),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 54)),
            Text(_streak > 0 ? '$_streak يوم' : 'ماكو ستريك هسه',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kStreakColor)),
            const SizedBox(height: 2),
            Text('الستريك ويا ${widget.name}${_streak > 0 && _streak % 100 == 0 ? ' 💯' : ''}',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            if (_expiring) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: kStreakColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  hours != null && hours > 0
                      ? '⏳ الستريك راح ينتهي بعد ${_hoursText(hours)} — لازم انتو الثنين ترسلون اليوم'
                      : '⏳ الستريك راح ينتهي الليلة — لازم انتو الثنين ترسلون اليوم',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (info != null) ...[
              todayRow(info['me_today'] == true,
                  info['me_today'] == true ? 'انت أرسلت اليوم' : 'انت بعدك ما أرسلت اليوم'),
              todayRow(info['other_today'] == true,
                  info['other_today'] == true ? '${widget.name} أرسل اليوم' : '${widget.name} بعده ما أرسل اليوم'),
              if (((info['best'] ?? 0) as num) > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    const Icon(Icons.emoji_events_rounded, size: 20, color: Colors.amber),
                    const SizedBox(width: 8),
                    Text('أطول ستريك وصلتوله: ${(info['best'] as num).toInt()} يوم',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              const Divider(height: 22),
            ] else if (!_failed)
              const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('شلون يشتغل الستريك؟', style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
            ),
            const SizedBox(height: 4),
            rule('🔥', 'كل يوم ترسلون لبعض — انتو الثنين، ولو رسالة وحدة — يزيد الستريك يوم'),
            rule('📅', 'يبين الـ🔥 من تكملون ${((info?['min'] ?? 3) as num).toInt()} أيام ورا بعض'),
            rule('💔', 'إذا عبر يوم كامل بدون ما ترسلون الثنين، يرجع من الصفر'),
            rule('⏳', 'اليوم يخلص الساعة 12 بالليل (توقيت بغداد)، والساعة 8 بالليل توصلك تذكرة إذا بعدك ما أرسلت'),
            rule('💯', 'بكل 100 يوم يطلع 💯 يم الستريك'),
          ],
        ),
      ),
    );
  }

  static String _hoursText(double h) {
    if (h < 1) return 'أقل من ساعة';
    final n = h.floor();
    if (n == 1) return 'ساعة';
    if (n == 2) return 'ساعتين';
    return n <= 10 ? '$n ساعات' : '$n ساعة';
  }
}
