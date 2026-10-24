import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/core_services.dart';
import '../../services/wallet_service.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';

const _gold1 = Color(0xFFFFD54F);
const _gold2 = Color(0xFFFF8F00);

const _kindText = {
  'topup': 'شحن عملات',
  'gift_sent': 'هدية أرسلتها',
  'gift_recv': 'هدية وصلتك',
  'withdraw_req': 'طلب سحب',
  'withdraw_back': 'رجوع مبلغ سحب مرفوض',
  'owner_grant': 'عملات من الإدارة',
};

class CoinIcon extends StatelessWidget {
  final double size;
  const CoinIcon({super.key, this.size = 20});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [_gold1, _gold2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Text('م', style: TextStyle(fontSize: size * 0.55, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
      );
}

// ======================= المحفظة =======================
class WalletScreen extends StatefulWidget {
  final int initialTab;
  const WalletScreen({super.key, this.initialTab = 0});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Map<String, dynamic>? _w;
  List<TopupPackage>? _pk;
  List<Map<String, dynamic>>? _hist;
  List<Map<String, dynamic>>? _wd;
  List<Map<String, dynamic>> _methods = const [];
  List<Map<String, dynamic>> _manual = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadManual() async {
    try {
      final r = await Future.wait([WalletService.topupMethods(), WalletService.manualMine()]);
      if (!mounted) return;
      setState(() {
        _methods = r[0];
        _manual = r[1];
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    _loadManual();
    try {
      final r = await Future.wait([
        WalletService.me(),
        WalletService.packages(),
        WalletService.history(),
        WalletService.myWithdrawals(),
      ]);
      if (!mounted) return;
      setState(() {
        _w = r[0] as Map<String, dynamic>;
        _pk = r[1] as List<TopupPackage>;
        _hist = r[2] as List<Map<String, dynamic>>;
        _wd = r[3] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  int _i(String k) => ((_w?[k] ?? 0) as num).toInt();

  Future<void> _buy(TopupPackage p) async {
    if (_w?['topup_ready'] != true) {
      if (_methods.isNotEmpty) {
        await _manualBuy(p);
      } else {
        showSnack(context, 'الشحن يتفعّل قريبًا إن شاء الله');
      }
      return;
    }
    try {
      final r = await WalletService.topupStart(p.id);
      if (!mounted) return;
      final status = await Navigator.push<String>(
          context, MaterialPageRoute(builder: (_) => _PayScreen(url: r['url'] as String, intent: r['intent'] as String)));
      if (!mounted) return;
      if (status == 'paid') {
        HapticFeedback.heavyImpact();
        showSnack(context, '🪙 تم شحن ${fmtNum(p.coins)} عملة');
      } else if (status == 'failed') {
        showSnack(context, 'ما تمت عملية الدفع', error: true);
      } else {
        showSnack(context, 'إذا دفعت، العملات راح تنضاف تلقائيًا خلال دقيقة');
      }
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  /// الشحن بالتحويل: يختار المحفظة، يحوّل لرقم المالك، ويكتب رقم العملية
  Future<void> _manualBuy(TopupPackage p) async {
    Map<String, dynamic> m;
    try {
      m = await WalletService.revealMethod('${_methods.first['id']}');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    final sender = TextEditingController();
    final ref = TextEditingController();
    var busy = false;
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(c).bottom + 16),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const CoinIcon(size: 28),
                const SizedBox(width: 8),
                Text('${fmtNum(p.coins)} عملة', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const Spacer(),
                Text(fmtIqd(p.price), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 12),
              const Text('١. اختار المحفظة اللي تحوّل منها:', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in _methods)
                  ChoiceChip(
                    label: Text('${x['emoji'] ?? ''} ${x['name']}'),
                    selected: x['id'] == m['id'],
                    onSelected: (_) async {
                      try {
                        final r = await WalletService.revealMethod('${x['id']}');
                        set(() => m = r);
                      } catch (e) {
                        if (c.mounted) showSnack(c, friendlyError(e), error: true);
                      }
                    },
                  ),
              ]),
              const SizedBox(height: 12),
              Text('٢. حوّل ${fmtIqd(p.price)} بالضبط إلى:', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Card(
                child: ListTile(
                  title: SelectableText('${m['destination']}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1)),
                  subtitle: Text([
                    '${m['name']}',
                    if ('${m['holder'] ?? ''}'.isNotEmpty) 'باسم: ${m['holder']}',
                    if ('${m['note'] ?? ''}'.isNotEmpty) '${m['note']}',
                  ].join('\n')),
                  trailing: IconButton(
                    tooltip: 'نسخ',
                    icon: const Icon(Icons.copy_rounded),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '${m['destination']}'));
                      showSnack(c, 'انسخ الرقم ✅');
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text('٣. بعد التحويل اكتب:', style: TextStyle(fontWeight: FontWeight.w800)),
              TextField(
                controller: sender,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقمك اللي حوّلت منه', hintText: '07801234567'),
              ),
              TextField(
                controller: ref,
                decoration: const InputDecoration(
                    labelText: 'رقم عملية التحويل', helperText: 'يطلعلك برسالة أو إشعار المحفظة بعد التحويل'),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (ref.text.trim().length < 4) {
                          showSnack(c, 'اكتب رقم عملية التحويل', error: true);
                          return;
                        }
                        set(() => busy = true);
                        try {
                          await WalletService.manualTopup(
                              package: p.id, method: '${m['id']}', sender: sender.text.trim(), reference: ref.text.trim());
                          if (c.mounted) Navigator.pop(c, true);
                        } catch (e) {
                          set(() => busy = false);
                          if (c.mounted) showSnack(c, friendlyError(e), error: true);
                        }
                      },
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
                label: const Text('حوّلت — أرسل الطلب'),
              ),
              const SizedBox(height: 8),
              const Text('🔒 العملات تنضاف بعد ما يتأكد الاستلام. رقم العملية ينستخدم مرة وحدة بس.',
                  style: TextStyle(fontSize: 12), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
    if (done == true && mounted) {
      HapticFeedback.mediumImpact();
      showSnack(context, 'وصل طلبك ✅ راح يوصلك إشعار أول ما تنضاف العملات');
      _loadManual();
    }
  }

  Future<void> _withdraw() async {
    final amount = TextEditingController(text: '${_i('earn_available')}');
    final wallet = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('سحب الأرباح'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('المتاح: ${fmtIqd(_i('earn_available'))}\nأقل مبلغ: ${fmtIqd(_i('min_withdraw'))}',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'المبلغ (دينار)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: wallet,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'رقم محفظتك بزين كاش', hintText: '07801234567'),
          ),
          const SizedBox(height: 6),
          const Text('يراجع مالك التطبيق الطلب ويحوّل المبلغ لمحفظتك.', style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('اطلب السحب')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await WalletService.requestWithdrawal(int.tryParse(amount.text) ?? 0, wallet.text);
      if (mounted) showSnack(context, 'وصل طلبك ✅ راح يوصلك إشعار بعد التحويل');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحفظة والأرباح'),
          bottom: const TabBar(tabs: [Tab(text: 'شحن العملات'), Tab(text: 'أرباحي'), Tab(text: 'السجل')]),
        ),
        body: w == null
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(children: [_topupTab(), _earningsTab(), _historyTab()]),
      ),
    );
  }

  Widget _balanceCard() => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xFF3A1C71), Color(0xFFD76D77), Color(0xFFFFAF7B)]),
          boxShadow: [BoxShadow(color: _gold2.withValues(alpha: 0.35), blurRadius: 18)],
        ),
        child: Row(children: [
          const CoinIcon(size: 46),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('رصيد العملات', style: TextStyle(color: Colors.white70)),
              Text(fmtNum(_i('coins')),
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
            ]),
          ),
        ]),
      );

  Widget _topupTab() {
    final ready = _w?['topup_ready'] == true;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        _balanceCard(),
        if (!ready && _methods.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_wallet_rounded, color: Colors.green),
                title: const Text('اشحن بأي محفظة 💳'),
                subtitle: Text(_methods.map((m) => '${m['emoji'] ?? ''} ${m['name']}').join(' · ')),
              ),
            ),
          ),
        if (!ready && _methods.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: ListTile(
                leading: Icon(Icons.schedule_rounded, color: Colors.orange),
                title: Text('الشحن بزين كاش يتفعّل قريبًا'),
                subtitle: Text('الباقات جاهزة، وراح تتفعّل أول ما يكتمل ربط الدفع الرسمي.'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.85,
            children: [
              for (final p in _pk ?? const <TopupPackage>[])
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _buy(p),
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _gold2.withValues(alpha: 0.5)),
                      color: _gold1.withValues(alpha: 0.08),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const CoinIcon(size: 30),
                      const SizedBox(height: 6),
                      Text(fmtNum(p.coins), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text(fmtIqd(p.price), style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
            ],
          ),
        ),
        if (_manual.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('طلبات الشحن مالتك', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          for (final x in _manual.take(10))
            ListTile(
              dense: true,
              leading: Icon(
                x['status'] == 'approved'
                    ? Icons.check_circle_rounded
                    : x['status'] == 'rejected'
                        ? Icons.cancel_rounded
                        : Icons.hourglass_top_rounded,
                color: x['status'] == 'approved'
                    ? Colors.green
                    : x['status'] == 'rejected'
                        ? Colors.red
                        : Colors.orange,
              ),
              title: Text('${fmtNum((x['coins'] as num?) ?? 0)} عملة · ${fmtIqd((x['amount'] as num?) ?? 0)}'),
              subtitle: Text('${x['status'] == 'approved' ? 'انضافت ✅' : x['status'] == 'rejected' ? 'مرفوض' : 'قيد التأكيد'}'
                  ' · رقم العملية ${x['reference']}${'${x['note'] ?? ''}'.isNotEmpty ? '\n${x['note']}' : ''}'),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Text(
            '${ready ? '• الدفع عن طريق زين كاش الرسمي، والعملات تنضاف بس بعد ما زين كاش يأكد الدفع.' : '• تحوّل المبلغ لرقم التطبيق بأي محفظة، وتكتب رقم العملية، والعملات تنضاف بعد التأكد من الاستلام.'}\n'
            '• العملات تستخدمها لإرسال الهدايا بالبث المباشر.\n'
            '• قيمة الهدية تنقسم: 50% لصانع المحتوى و50% للتطبيق.',
            style: TextStyle(fontSize: 12.5, height: 1.7),
          ),
        ),
      ]),
    );
  }

  Widget _stat(String t, String v, IconData i, Color c) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(i, color: c),
              const SizedBox(height: 6),
              Text(v, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              Text(t, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _earningsTab() {
    final wd = _wd ?? const [];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(colors: [Color(0xFF0F9B0F), Color(0xFF00C9A7)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('المتاح للسحب', style: TextStyle(color: Colors.white70)),
            Text(fmtIqd(_i('earn_available')),
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0F9B0F)),
              onPressed: _i('earn_available') >= _i('min_withdraw') ? _withdraw : null,
              icon: const Icon(Icons.account_balance_wallet_rounded),
              label: Text(_i('earn_available') >= _i('min_withdraw')
                  ? 'سحب الأرباح'
                  : 'السحب من ${fmtIqd(_i('min_withdraw'))}'),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _stat('إجمالي الأرباح', fmtIqd(_i('earn_total')), Icons.trending_up_rounded, Colors.green),
          _stat('أرباح اليوم', fmtIqd(_i('today')), Icons.today_rounded, Colors.blue),
        ]),
        Row(children: [
          _stat('أرباح الشهر', fmtIqd(_i('month')), Icons.calendar_month_rounded, Colors.purple),
          _stat('معلّقة (72 ساعة)', fmtIqd(_i('earn_pending')), Icons.hourglass_top_rounded, Colors.orange),
        ]),
        Row(children: [
          _stat('الهدايا المستلمة', fmtNum(_i('gifts_received')), Icons.card_giftcard_rounded, Colors.pink),
          _stat('تم سحبه', fmtIqd(_i('withdrawn')), Icons.check_circle_rounded, Colors.teal),
        ]),
        const SizedBox(height: 6),
        const Text('الأرباح تجي من الهدايا اللي توصلك بالبث: نص قيمة كل هدية إلك. '
            'تبقى معلّقة 72 ساعة (حماية من الاحتيال) وبعدين تصير متاحة للسحب.',
            style: TextStyle(fontSize: 12.5, height: 1.6)),
        if (wd.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('طلبات السحب', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final x in wd)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                x['status'] == 'paid'
                    ? Icons.check_circle_rounded
                    : x['status'] == 'rejected'
                        ? Icons.cancel_rounded
                        : Icons.hourglass_top_rounded,
                color: x['status'] == 'paid' ? Colors.green : x['status'] == 'rejected' ? Colors.red : Colors.orange,
              ),
              title: Text(fmtIqd((x['amount'] as num?) ?? 0)),
              subtitle: Text('${x['status'] == 'paid' ? 'تم التحويل' : x['status'] == 'rejected' ? 'مرفوض' : 'قيد المراجعة'}'
                  ' · ${x['destination']}${(x['note'] ?? '') != '' ? '\n${x['note']}' : ''}'),
            ),
        ],
      ]),
    );
  }

  Widget _historyTab() {
    final h = _hist ?? const [];
    if (h.isEmpty) return const Center(child: Text('ماكو حركات بعد'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: h.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final x = h[i];
          final d = (x['delta'] as num).toInt();
          final coins = x['account'] == 'coins';
          final at = DateTime.tryParse('${x['at']}')?.toLocal();
          return ListTile(
            leading: coins
                ? const CoinIcon(size: 30)
                : const CircleAvatar(radius: 15, backgroundColor: Colors.green, child: Icon(Icons.payments_rounded, size: 16, color: Colors.white)),
            title: Text(_kindText[x['kind']] ?? '${x['kind']}'),
            subtitle: Text('${x['note'] ?? ''}${at != null ? '\n${Fmt.chatListTime(at)}' : ''}'),
            isThreeLine: true,
            trailing: Text('${d > 0 ? '+' : ''}${coins ? fmtNum(d) : fmtIqd(d)}',
                style: TextStyle(fontWeight: FontWeight.w900, color: d >= 0 ? Colors.green : Colors.redAccent)),
          );
        },
      ),
    );
  }
}

/// صفحة الدفع الرسمية من زين كاش داخل التطبيق. ترجع: paid / failed / pending
class _PayScreen extends StatefulWidget {
  final String url;
  final String intent;
  const _PayScreen({required this.url, required this.intent});
  @override
  State<_PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends State<_PayScreen> {
  late final WebViewController _web;
  bool _checking = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onNavigationRequest: (r) {
          // زين كاش يرجّعنا لهذا الرابط بعد الدفع — ما نفتحه، نتأكد من الخادم مباشرة
          if (r.url.startsWith('https://almajhool.app/pay/')) {
            _finish();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _finish() async {
    if (_checking) return;
    setState(() => _checking = true);
    var s = 'pending';
    for (var i = 0; i < 12 && s == 'pending'; i++) {
      try {
        s = await WalletService.topupCheck(widget.intent);
      } catch (_) {}
      if (s == 'pending') await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (mounted) Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الدفع بزين كاش 🔒'),
        actions: [TextButton(onPressed: _finish, child: const Text('دفعت'))],
        bottom: _progress < 100
            ? PreferredSize(preferredSize: const Size.fromHeight(2), child: LinearProgressIndicator(value: _progress / 100))
            : null,
      ),
      body: _checking
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('نتأكد من الدفع ويّا زين كاش...'),
            ]))
          : WebViewWidget(controller: _web),
    );
  }
}

// ======================= لوحة الهدايا (بالبث) =======================
Future<Map<String, dynamic>?> showGiftSheet(BuildContext context, {required String toUser, required String toName, String? liveId}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    backgroundColor: const Color(0xFF16112B),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _GiftSheet(toUser: toUser, toName: toName, liveId: liveId),
  );
}

class _GiftSheet extends StatefulWidget {
  final String toUser;
  final String toName;
  final String? liveId;
  const _GiftSheet({required this.toUser, required this.toName, this.liveId});
  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  List<Gift>? _gifts;
  Gift? _sel;
  int _qty = 1;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([WalletService.gifts(), WalletService.me()]);
      if (mounted) setState(() => _gifts = r[0] as List<Gift>);
    } catch (e) {
      if (mounted) setState(() => _gifts = []);
    }
  }

  Future<void> _send() async {
    final g = _sel;
    if (g == null) return;
    setState(() => _sending = true);
    try {
      final r = await WalletService.sendGift(to: widget.toUser, giftId: g.id, liveId: widget.liveId, qty: _qty);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, {...r, 'gift': g.id, 'qty': _qty});
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyError(e);
      showSnack(context, msg, error: true);
      if (msg.contains('رصيدك')) {
        final nav = Navigator.of(context);
        nav.pop();
        nav.push(MaterialPageRoute(builder: (_) => const WalletScreen()));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gifts = _gifts;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Colors.white),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text('🎁 هدية إلى ${widget.toName}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const Spacer(),
              ValueListenableBuilder<int?>(
                valueListenable: WalletService.coins,
                builder: (_, c, __) => InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const CoinIcon(size: 18),
                      const SizedBox(width: 6),
                      Text(c == null ? '...' : fmtNum(c), style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 4),
                      const Icon(Icons.add_circle_rounded, size: 18, color: _gold1),
                    ]),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            if (gifts == null)
              const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator())
            else
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.8,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final g in gifts)
                    GestureDetector(
                      onTap: () => setState(() => _sel = g),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: _sel?.id == g.id ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
                          border: Border.all(color: _sel?.id == g.id ? _gold1 : Colors.white12),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          AnimatedScale(
                            scale: _sel?.id == g.id ? 1.25 : 1,
                            duration: const Duration(milliseconds: 180),
                            child: Text(g.emoji, style: const TextStyle(fontSize: 32)),
                          ),
                          const SizedBox(height: 4),
                          Text(g.name, style: const TextStyle(fontSize: 11.5)),
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            const CoinIcon(size: 12),
                            const SizedBox(width: 3),
                            Text(fmtNum(g.coins), style: const TextStyle(fontSize: 11, color: _gold1)),
                          ]),
                        ]),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            Row(children: [
              for (final q in const [1, 5, 10, 99])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text('×$q'),
                    selected: _qty == q,
                    onSelected: (_) => setState(() => _qty = q),
                  ),
                ),
              const Spacer(),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF2D87), foregroundColor: Colors.white),
                onPressed: _sel == null || _sending ? null : _send,
                child: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_sel == null ? 'اختار هدية' : 'إرسال (${fmtNum(_sel!.coins * _qty)})'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ======================= حركة الهدية على الشاشة =======================
class GiftBurst extends StatefulWidget {
  final String emoji;
  final String text;
  final int tier;
  final VoidCallback onDone;
  const GiftBurst({super.key, required this.emoji, required this.text, required this.tier, required this.onDone});
  @override
  State<GiftBurst> createState() => _GiftBurstState();
}

class _GiftBurstState extends State<GiftBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: 1600 + widget.tier * 500))
        ..forward().whenComplete(widget.onDone);
  final _rnd = math.Random();
  late final List<(double, double, double, String)> _parts = List.generate(
      10 + widget.tier * 6,
      (_) => (
            _rnd.nextDouble() * 2 * math.pi,
            0.5 + _rnd.nextDouble(),
            0.6 + _rnd.nextDouble() * 0.8,
            ['✨', '💫', '⭐', widget.emoji, '🎉'][_rnd.nextInt(5)],
          ));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final big = 70.0 + widget.tier * 22;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final pop = Curves.elasticOut.transform((t * 2.2).clamp(0.0, 1.0));
          final fade = t > 0.8 ? (1 - (t - 0.8) / 0.2) : 1.0;
          return Opacity(
            opacity: fade.clamp(0.0, 1.0),
            child: Stack(children: [
              // جزيئات تنفجر حول الهدية
              for (final p in _parts)
                Positioned(
                  left: size.width / 2 + math.cos(p.$1) * size.width * 0.42 * t * p.$2 - 12,
                  top: size.height * 0.4 + math.sin(p.$1) * size.height * 0.28 * t * p.$2 - 12,
                  child: Transform.rotate(
                    angle: t * 6 * p.$3,
                    child: Text(p.$4, style: TextStyle(fontSize: 16 + 12 * p.$3)),
                  ),
                ),
              Positioned.fill(
                child: Align(
                  alignment: const Alignment(0, -0.2),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.002)
                        ..rotateY(math.sin(t * math.pi * 2) * 0.6)
                        ..scale(0.2 + pop * 0.8),
                      child: Text(widget.emoji,
                          style: TextStyle(fontSize: big, shadows: const [Shadow(color: _gold1, blurRadius: 30)])),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(colors: [Color(0xFFFF2D87), _gold2]),
                      ),
                      child: Text(widget.text,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                    ),
                  ]),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

// ======================= اللوحة المالية للمالك =======================
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});
  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  Map<String, dynamic>? _s;
  List<Map<String, dynamic>>? _wd;
  String _wdFilter = 'pending';
  List<Map<String, dynamic>> _mt = const [];
  List<Map<String, dynamic>> _methods = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadManual() async {
    try {
      final r = await Future.wait([supa.rpc('finance_manual_list', params: {'p_status': 'pending'}), supa.rpc('finance_methods')]);
      if (!mounted) return;
      setState(() {
        _mt = [for (final e in r[0] as List) (e as Map).cast<String, dynamic>()];
        _methods = [for (final e in r[1] as List) (e as Map).cast<String, dynamic>()];
      });
    } catch (_) {}
  }

  /// أرقام استلام المحافظ: المالك يكتب رقمه بكل محفظة ويفعّلها
  Future<void> _editMethods() async {
    final ctl = {for (final m in _methods) '${m['id']}': TextEditingController(text: '${m['destination'] ?? ''}')};
    final holder = {for (final m in _methods) '${m['id']}': TextEditingController(text: '${m['holder'] ?? ''}')};
    final on = {for (final m in _methods) '${m['id']}': m['enabled'] == true};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('محافظ الاستلام 💳'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('اكتب رقمك بكل محفظة عندك وفعّلها. المستخدمين يشوفون الرقم ويحوّلون عليه.',
                  style: TextStyle(fontSize: 12)),
              for (final m in _methods) ...[
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${m['emoji'] ?? ''} ${m['name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  value: on['${m['id']}']!,
                  onChanged: (v) => set(() => on['${m['id']}'] = v),
                ),
                TextField(
                  controller: ctl['${m['id']}'],
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'رقم/حساب الاستلام', isDense: true),
                ),
                TextField(
                  controller: holder['${m['id']}'],
                  decoration: const InputDecoration(labelText: 'الاسم اللي يطلع للمحوّل (اختياري)', isDense: true),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      for (final m in _methods) {
        final id = '${m['id']}';
        final dest = ctl[id]!.text.trim();
        if (on[id]! && dest.isEmpty) throw Exception('اكتب رقم ${m['name']} قبل لا تفعّلها');
        await supa.rpc('finance_set_method',
            params: {'p_id': id, 'p_destination': dest, 'p_holder': holder[id]!.text.trim(), 'p_enabled': on[id]});
      }
      if (mounted) showSnack(context, 'تم الحفظ ✅');
      _loadManual();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _processManual(Map<String, dynamic> x, bool ok) async {
    String note = '';
    if (!ok) {
      final r = await promptText(context, 'سبب الرفض', hint: 'مثلاً: ما وصلني التحويل', ok: 'رفض');
      if (r == null) return;
      note = r;
    }
    try {
      await supa.rpc('finance_manual_process', params: {'p_id': x['id'], 'p_approve': ok, 'p_note': note});
      if (mounted) showSnack(context, ok ? 'انضافت العملات ✅' : 'انرفض الطلب');
      _loadManual();
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _load() async {
    _loadManual();
    try {
      final s = ((await supa.rpc('finance_summary')) as Map).cast<String, dynamic>();
      final w = [
        for (final e in (await supa.rpc('finance_withdrawals', params: {'p_status': _wdFilter})) as List)
          (e as Map).cast<String, dynamic>()
      ];
      if (mounted) {
        setState(() {
          _s = s;
          _wd = w;
        });
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  int _i(String k) => ((_s?[k] ?? 0) as num).toInt();

  Future<void> _zaincash() async {
    final zc = (_s?['zc'] as Map?)?.cast<String, dynamic>() ?? {};
    final id = TextEditingController();
    final sec = TextEditingController();
    final wal = TextEditingController();
    var live = zc['live'] == true;
    var enabled = zc['enabled'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('ربط زين كاش 🔒'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('البيانات تنحفظ بالخادم بس وما ترجع تظهر لأي أحد. اترك الخانة فاضية إذا ما تريد تغيّرها.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                  controller: id,
                  decoration: InputDecoration(labelText: 'Client ID', helperText: zc['client_set'] == true ? 'محفوظ ✓' : null)),
              TextField(
                  controller: sec,
                  obscureText: true,
                  decoration:
                      InputDecoration(labelText: 'Client Secret', helperText: zc['secret_set'] == true ? 'محفوظ ✓' : null)),
              TextField(
                  controller: wal,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                      labelText: 'محفظة الاستلام (ZAINCASH_SETTLEMENT_WALLET)',
                      helperText: zc['wallet_set'] == true ? 'محفوظة ✓ (مخفية)' : null)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('وضع حقيقي (Live)'),
                subtitle: const Text('مطفي = تجريبي (UAT) للاختبار'),
                value: live,
                onChanged: (v) => set(() => live = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تفعيل الشحن للمستخدمين'),
                value: enabled,
                onChanged: (v) => set(() => enabled = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await supa.rpc('finance_set_zaincash', params: {
        'p_client_id': id.text.trim(),
        'p_client_secret': sec.text.trim(),
        'p_wallet': wal.text.trim(),
        'p_live': live,
        'p_enabled': enabled,
      });
      if (mounted) showSnack(context, 'تم الحفظ 🔒');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _grant() async {
    final user = TextEditingController();
    final coins = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إضافة عملات لحساب'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: user, decoration: const InputDecoration(labelText: 'اسم المستخدم (بدون @)')),
          TextField(
              controller: coins,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'عدد العملات (سالب للخصم)')),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'السبب')),
          const SizedBox(height: 6),
          const Text('تنبيه: العملات المجانية إذا انرسلت كهدايا تتحول لأرباح حقيقية لصناع المحتوى.',
              style: TextStyle(fontSize: 12, color: Colors.orange)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await supa
          .from('profiles')
          .select('id')
          .eq('username', user.text.trim().toLowerCase().replaceAll('@', ''))
          .maybeSingle();
      if (r == null) throw Exception('المستخدم غير موجود');
      await supa.rpc('finance_grant_coins',
          params: {'p_user': r['id'], 'p_coins': int.tryParse(coins.text.trim()) ?? 0, 'p_reason': reason.text.trim()});
      if (mounted) showSnack(context, 'تمت ✅');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _process(Map<String, dynamic> w, bool paid) async {
    final note = await promptText(context, paid ? 'ملاحظة (اختياري) — مثلاً رقم التحويل' : 'سبب الرفض',
        hint: paid ? 'رقم عملية زين كاش' : 'السبب', ok: paid ? 'تم التحويل' : 'رفض');
    if (note == null) return;
    try {
      await supa.rpc('finance_process_withdrawal', params: {'p_id': w['id'], 'p_paid': paid, 'p_note': note});
      if (mounted) showSnack(context, paid ? 'تم ✅ ووصل إشعار للمستخدم' : 'انرفض ورجعت الأرباح لصاحبها');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Widget _card(String t, String v, Color c, IconData i) => Card(
        child: ListTile(
          leading: CircleAvatar(backgroundColor: c.withValues(alpha: 0.15), child: Icon(i, color: c)),
          title: Text(v, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          subtitle: Text(t),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final zc = (s?['zc'] as Map?)?.cast<String, dynamic>() ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('اللوحة المالية 💰'), actions: [
        IconButton(onPressed: _grant, tooltip: 'إضافة عملات', icon: const Icon(Icons.add_card_rounded)),
      ]),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                Card(
                  color: (zc['enabled'] == true ? Colors.green : Colors.orange).withValues(alpha: 0.12),
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_rounded),
                    title: Text(zc['enabled'] == true
                        ? 'الشحن بزين كاش مفعّل ${zc['live'] == true ? '(حقيقي)' : '(تجريبي)'}'
                        : 'الشحن بزين كاش غير مفعّل'),
                    subtitle: Text('Client: ${zc['client_set'] == true ? '✓' : '✗'} · Secret: ${zc['secret_set'] == true ? '✓' : '✗'}'
                        ' · المحفظة: ${zc['wallet_set'] == true ? '✓' : '✗'}'),
                    trailing: const Icon(Icons.settings_rounded),
                    onTap: _zaincash,
                  ),
                ),
                Card(
                  color: (_methods.any((m) => m['enabled'] == true) ? Colors.green : Colors.orange).withValues(alpha: 0.12),
                  child: ListTile(
                    leading: const Icon(Icons.account_balance_wallet_rounded),
                    title: Text(_methods.any((m) => m['enabled'] == true)
                        ? 'الشحن بالتحويل مفعّل: ${_methods.where((m) => m['enabled'] == true).map((m) => m['name']).join('، ')}'
                        : 'الشحن بالتحويل (كل المحافظ) غير مفعّل'),
                    subtitle: const Text('اضغط حتى تكتب أرقامك وتفعّل المحافظ'),
                    trailing: const Icon(Icons.settings_rounded),
                    onTap: _methods.isEmpty ? null : _editMethods,
                  ),
                ),
                if (_mt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('طلبات شحن تنتظر تأكيدك (${_mt.length})',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const Text('افتح تطبيق المحفظة وتأكد إن المبلغ وصلك برقم العملية قبل لا توافق.',
                      style: TextStyle(fontSize: 12)),
                  for (final x in _mt)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Avatar(
                                url: (x['user'] as Map?)?['avatar_url'] as String?,
                                name: '${(x['user'] as Map?)?['display_name'] ?? ''}',
                                size: 34),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('${(x['user'] as Map?)?['display_name'] ?? ''} @${(x['user'] as Map?)?['username'] ?? ''}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                            ),
                            Text(fmtIqd((x['amount'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w900)),
                          ]),
                          const SizedBox(height: 6),
                          Text('${_methods.firstWhere((m) => m['id'] == x['method'], orElse: () => {'name': x['method']})['name']}'
                              ' · ${fmtNum((x['coins'] as num?) ?? 0)} عملة'),
                          SelectableText('رقم العملية: ${x['reference']}', textDirection: TextDirection.ltr),
                          if ('${x['sender'] ?? ''}'.isNotEmpty)
                            SelectableText('من الرقم: ${x['sender']}', textDirection: TextDirection.ltr),
                          const SizedBox(height: 6),
                          Row(children: [
                            FilledButton.icon(
                                onPressed: () => _processManual(x, true),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('وصلني — أضف العملات')),
                            const SizedBox(width: 8),
                            TextButton(onPressed: () => _processManual(x, false), child: const Text('رفض')),
                          ]),
                        ]),
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
                _card('حصتك (50% من الهدايا)', fmtIqd(_i('platform_iqd')), Colors.green, Icons.savings_rounded),
                _card('إجمالي الشحن المدفوع (${fmtNum(_i('topups_count'))} عملية)', fmtIqd(_i('topups_iqd')), Colors.blue,
                    Icons.payments_rounded),
                _card('قيمة الهدايا (${fmtNum(_i('gifts_count'))} هدية)', fmtIqd(_i('gifts_value_iqd')), Colors.pink,
                    Icons.card_giftcard_rounded),
                _card('هدايا اليوم', fmtIqd(_i('today_gifts_iqd')), Colors.purple, Icons.today_rounded),
                _card('مستحقات صناع المحتوى (غير مسحوبة)', fmtIqd(_i('creators_owed_iqd')), Colors.orange,
                    Icons.groups_rounded),
                _card('سحوبات قيد المراجعة', fmtIqd(_i('withdraw_pending_iqd')), Colors.amber, Icons.hourglass_top_rounded),
                _card('سحوبات محوّلة', fmtIqd(_i('withdraw_paid_iqd')), Colors.teal, Icons.check_circle_rounded),
                _card('عملات بأيدي المستخدمين', fmtNum(_i('coins_outstanding')), Colors.brown, Icons.toll_rounded),
                _card('عمليات دفع فاشلة', fmtNum(_i('topups_failed')), Colors.red, Icons.error_outline_rounded),
                const SizedBox(height: 10),
                Row(children: [
                  const Text('طلبات السحب', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  const Spacer(),
                  DropdownButton<String>(
                    value: _wdFilter,
                    items: const [
                      DropdownMenuItem(value: 'pending', child: Text('قيد المراجعة')),
                      DropdownMenuItem(value: 'paid', child: Text('محوّلة')),
                      DropdownMenuItem(value: 'rejected', child: Text('مرفوضة')),
                    ],
                    onChanged: (v) {
                      setState(() => _wdFilter = v ?? 'pending');
                      _load();
                    },
                  ),
                ]),
                if ((_wd ?? const []).isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('ماكو طلبات'))),
                for (final w in _wd ?? const <Map<String, dynamic>>[])
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Avatar(
                              url: (w['user'] as Map?)?['avatar_url'] as String?,
                              name: '${(w['user'] as Map?)?['display_name'] ?? ''}',
                              size: 34),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${(w['user'] as Map?)?['display_name'] ?? ''} @${(w['user'] as Map?)?['username'] ?? ''}',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          Text(fmtIqd((w['amount'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w900)),
                        ]),
                        const SizedBox(height: 6),
                        SelectableText('زين كاش: ${w['destination']}', textDirection: TextDirection.ltr),
                        if ((w['note'] ?? '') != '') Text('${w['note']}', style: const TextStyle(fontSize: 12)),
                        if (w['status'] == 'pending')
                          Row(children: [
                            FilledButton.icon(
                                onPressed: () => _process(w, true),
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('حوّلت المبلغ')),
                            const SizedBox(width: 8),
                            TextButton(onPressed: () => _process(w, false), child: const Text('رفض')),
                          ]),
                      ]),
                    ),
                  ),
              ]),
            ),
    );
  }
}
