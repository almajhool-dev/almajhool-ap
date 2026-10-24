import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'core_services.dart';

class Gift {
  final String id;
  final String name;
  final String emoji;
  final int coins;
  final int tier;
  const Gift(this.id, this.name, this.emoji, this.coins, this.tier);
  static Gift fromMap(Map m) => Gift(m['id'] as String, (m['name'] ?? '') as String, (m['emoji'] ?? '🎁') as String,
      (m['coins'] as num).toInt(), ((m['tier'] ?? 1) as num).toInt());
}

class TopupPackage {
  final String id;
  final int coins;
  final int price;
  const TopupPackage(this.id, this.coins, this.price);
}

/// المحفظة والهدايا والأرباح — كل الأرقام تنحسب بالخادم، هنا عرض وطلبات بس.
class WalletService {
  WalletService._();

  /// رصيد العملات (يتحدث بعد كل شحن/هدية).
  static final coins = ValueNotifier<int?>(null);
  static List<Gift>? _gifts;

  static Future<Map<String, dynamic>> me() async {
    final r = ((await supa.rpc('wallet_me')) as Map).cast<String, dynamic>();
    coins.value = (r['coins'] as num?)?.toInt() ?? 0;
    return r;
  }

  static Future<List<Gift>> gifts() async {
    if (_gifts != null) return _gifts!;
    final r = await supa.from('gift_catalog').select().order('sort');
    _gifts = [for (final m in r) Gift.fromMap(m)];
    return _gifts!;
  }

  static Gift? giftById(String? id) {
    if (id == null) return null;
    for (final g in _gifts ?? const <Gift>[]) {
      if (g.id == id) return g;
    }
    return null;
  }

  static Future<List<TopupPackage>> packages() async {
    final r = await supa.from('topup_packages').select().order('sort');
    return [for (final m in r) TopupPackage(m['id'] as String, (m['coins'] as num).toInt(), (m['price_iqd'] as num).toInt())];
  }

  static Future<Map<String, dynamic>> sendGift({required String to, required String giftId, String? liveId, int qty = 1}) async {
    final r = ((await supa.rpc('send_gift', params: {
      'p_to': to,
      'p_gift': giftId,
      'p_live': liveId,
      'p_qty': qty,
      'p_client_id': const Uuid().v4(),
    })) as Map)
        .cast<String, dynamic>();
    final c = (r['coins'] as num?)?.toInt();
    if (c != null) coins.value = c;
    return r;
  }

  static Future<Map<String, dynamic>> topupStart(String packageId) async =>
      ((await supa.rpc('topup_start', params: {'p_package': packageId})) as Map).cast<String, dynamic>();

  static Future<String> topupCheck(String intent) async {
    final r = ((await supa.rpc('topup_check', params: {'p_intent': intent})) as Map).cast<String, dynamic>();
    final c = (r['coins'] as num?)?.toInt();
    if (c != null) coins.value = c;
    return (r['status'] ?? 'pending') as String;
  }

  // ---- الشحن اليدوي بكل المحافظ ----
  static Future<List<Map<String, dynamic>>> topupMethods() async =>
      [for (final e in (await supa.rpc('topup_methods')) as List) (e as Map).cast<String, dynamic>()];

  /// رقم الاستلام ينكشف بس لحظة الدفع (محمي بالخادم وبحد طلبات)
  static Future<Map<String, dynamic>> revealMethod(String id) async =>
      ((await supa.rpc('topup_method_reveal', params: {'p_method': id})) as Map).cast<String, dynamic>();

  static Future<void> manualTopup({
    required String package,
    required String method,
    required String sender,
    required String reference,
  }) =>
      supa.rpc('manual_topup_submit',
          params: {'p_package': package, 'p_method': method, 'p_sender': sender, 'p_reference': reference});

  static Future<List<Map<String, dynamic>>> manualMine() async =>
      [for (final e in (await supa.rpc('manual_topup_mine')) as List) (e as Map).cast<String, dynamic>()];

  static Future<List<Map<String, dynamic>>> history() async =>
      [for (final e in (await supa.rpc('wallet_history', params: {'p_limit': 100})) as List) (e as Map).cast<String, dynamic>()];

  static Future<List<Map<String, dynamic>>> myWithdrawals() async =>
      [for (final e in (await supa.rpc('my_withdrawals')) as List) (e as Map).cast<String, dynamic>()];

  static Future<void> requestWithdrawal(int amount, String wallet) =>
      supa.rpc('request_withdrawal', params: {'p_amount': amount, 'p_wallet': wallet});

  static Future<List<Map<String, dynamic>>> topGifters(String liveId) async =>
      [for (final e in (await supa.rpc('live_top_gifters', params: {'p_live': liveId})) as List) (e as Map).cast<String, dynamic>()];

  static void reset() {
    coins.value = null;
  }
}

String fmtNum(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

String fmtIqd(num v) => '${fmtNum(v)} د.ع';
