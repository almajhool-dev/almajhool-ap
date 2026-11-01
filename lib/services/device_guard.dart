import 'package:flutter/services.dart';

import 'core_services.dart';

// =====================================================================
//  حظر الجهاز: رقم الجهاز يثبت حتى لو انحذف التطبيق أو تغيّر الحساب أو الـ VPN
// =====================================================================
class DeviceGuard {
  DeviceGuard._();
  static const _ch = MethodChannel('almajhool/device');
  static String? _id;
  static DateTime? _last;

  static Future<String?> id() async {
    if (_id != null) return _id;
    try {
      _id = await _ch.invokeMethod<String>('id');
    } catch (_) {}
    return _id;
  }

  /// هل هذا الجهاز محظور؟ يشتغل حتى بدون تسجيل دخول (قبل شاشة الدخول وإنشاء الحساب).
  /// أي خطأ (بدون إنترنت أو خادم قديم) = مو محظور — ما نقفل التطبيق على مستخدم حقيقي بالغلط.
  static Future<bool> isBanned() async {
    final d = await id();
    if (d == null || d.isEmpty) return false;
    try {
      final r = await supa.rpc('device_status', params: {'p_device': d}).timeout(const Duration(seconds: 8));
      return r == true;
    } catch (_) {
      return false;
    }
  }

  /// يرجع true إذا الجهاز محظور.
  static Future<bool> checkin() async {
    if (supa.auth.currentUser == null) return false;
    if (_last != null && DateTime.now().difference(_last!) < const Duration(minutes: 10)) return false;
    final d = await id();
    if (d == null || d.isEmpty) return false;
    try {
      final r = await supa.rpc('device_checkin', params: {'p_device': d});
      _last = DateTime.now();
      return r is Map && r['banned'] == true;
    } catch (_) {
      return false;
    }
  }
}

