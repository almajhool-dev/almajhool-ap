import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Fmt {
  Fmt._();

  static String time(DateTime t) => DateFormat('h:mm a', 'ar').format(t.toLocal());

  static String chatListTime(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(local.year, local.month, local.day))
        .inDays;
    if (diff == 0) return time(local);
    if (diff == 1) return 'أمس';
    if (diff < 7) return DateFormat('EEEE', 'ar').format(local);
    return DateFormat('d/M/yyyy', 'ar').format(local);
  }

  static String dayHeader(DateTime t) {
    final local = t.toLocal();
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(local.year, local.month, local.day))
        .inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    return DateFormat('EEEE d MMMM yyyy', 'ar').format(local);
  }

  static String lastSeen(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'آخر ظهور الآن';
    if (d.inMinutes < 60) return 'آخر ظهور منذ ${d.inMinutes} دقيقة';
    if (d.inHours < 24) return 'آخر ظهور منذ ${d.inHours} ساعة';
    return 'آخر ظهور ${chatListTime(t)}';
  }

  static String fileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String duration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class Validators {
  Validators._();
  static final _username = RegExp(r'^[a-z0-9_.]{3,24}$');
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'أدخل البريد الإلكتروني';
    if (!_email.hasMatch(v.trim())) return 'البريد الإلكتروني غير صالح';
    return null;
  }

  static String? password(String? v) {
    if (v == null || v.length < 8) return 'كلمة المرور 8 أحرف على الأقل';
    return null;
  }

  static String? username(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (!_username.hasMatch(s)) {
      return 'من 3 إلى 24 حرفًا: أحرف إنجليزية صغيرة، أرقام، _ أو .';
    }
    return null;
  }

  static String? displayName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'أدخل الاسم';
    if (s.length > 50) return 'الاسم طويل جدًا';
    return null;
  }
}

/// تحويل الأخطاء إلى رسائل عربية مفهومة.
String friendlyError(Object e) {
  final raw = e.toString();
  if (raw.contains('Bearer') || raw.contains('Invalid API key') || raw.contains('No API key')) {
    return 'مفتاح الخادم غير صحيح. اضغط «تغيير إعدادات الخادم» وأدخل anon public key الصحيح';
  }
  if (raw.contains('relation') && raw.contains('does not exist') || raw.contains('PGRST202') || raw.contains('Could not find the function')) {
    return 'قاعدة البيانات غير مهيأة. شغّل ملف schema.sql في Supabase → SQL Editor';
  }
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login')) return 'البريد أو كلمة المرور غير صحيحة';
    if (m.contains('email not confirmed')) return 'يرجى تأكيد بريدك الإلكتروني أولًا';
    if (m.contains('already registered')) return 'هذا البريد مسجّل مسبقًا';
    if (m.contains('rate limit') || m.contains('security purposes')) {
      return 'محاولات كثيرة، حاول بعد قليل';
    }
    if (m.contains('token') && m.contains('expired')) return 'الرمز منتهي أو غير صحيح';
    return e.message;
  }
  if (e is PostgrestException) {
    final m = e.message;
    if (m.contains('rate_limited')) return 'أرسلت رسائل كثيرة بسرعة، انتظر قليلًا';
    if (e.code == '23505') return 'القيمة مستخدمة مسبقًا';
    if (e.code == '42501' || m.contains('row-level security')) return 'ليست لديك صلاحية لهذا الإجراء';
    return m;
  }
  if (e is StorageException) return 'فشل رفع الملف: ${e.message}';
  final s = raw;
  if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) {
    return 'لا يوجد اتصال بالإنترنت أو رابط الخادم غير صحيح';
  }
  final clean = s.replaceFirst('Exception: ', '');
  return clean.length > 180 ? '${clean.substring(0, 180)}…' : clean;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
}

Future<bool> confirmDialog(BuildContext context, String title, String body,
    {String ok = 'تأكيد', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size(80, 40)) : FilledButton.styleFrom(minimumSize: const Size(80, 40)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, String title,
    {String hint = '', String initial = '', int maxLines = 1, String ok = 'حفظ'}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
          onPressed: () => Navigator.pop(c, ctrl.text.trim()),
          child: Text(ok),
        ),
      ],
    ),
  );
  return (r == null || r.isEmpty) ? null : r;
}
