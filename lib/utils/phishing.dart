/// تنبيه تصيّد للرسائل الواصلة: ما يمنع شي، بس ينبّه المستخدم تحت الرسالة إذا شكلها احتيال
/// (طلب كود التحقق أو كلمة السر، جائزة برابط، «حسابك راح ينحذف» برابط).
class PhishingHint {
  PhishingHint._();

  static const warning = '⚠️ انتبه: الإدارة ما تطلب منك كود التحقق أو كلمة السر أبدًا. '
      'لا تنطيها لأحد، ولا تفتح روابط جوائز أو «تحديثات» من ناس ما تعرفهم.';

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[ً-ٰٟـ]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');

  static final _ask = RegExp(
      r'(ارسل|ارسلي|ارسله|دز|دزلي|دزيلي|دزه|انطيني|انطني|اعطيني|عطني|ابعثلي|ابعث|حولي|send me|send the|give me)');
  static final _secret = RegExp(
      r'(كود التحقق|رمز التحقق|الرمز اللي|الكود اللي|الرمز الي|الكود الي|الكود الي وصلك|رمز الاسترداد|كود الاسترداد|'
      r'كلمه السر|كلمه المرور|الباسورد|باسوردك|verification code|\botp\b|password|passcode)');
  static final _prize = RegExp(r'(ربحت|فزت|جائزه|جايزه|you won|winner|free coins|كوينز مجانا|شحن مجاني|رصيد مجاني)');
  static final _threat = RegExp(r'(حسابك|account)[^\n]{0,40}(راح ينحذف|ينحذف|ينحظر|سيتم حذف|سيتم ايقاف|will be deleted|suspended|locked)');
  static final _link = RegExp(r'(https?://|www\.|\b[a-z0-9-]{2,}\.(com|net|org|xyz|top|site|online|live|vip|club|link|info|me|io|app|ru|cn|cc|tk|shop|store)\b)');

  /// يرجّع نص التنبيه إذا الرسالة شكلها تصيّد، وإلا null
  static String? of(String? text) {
    if (text == null || text.length < 8) return null;
    final t = _norm(text);
    if (_ask.hasMatch(t) && _secret.hasMatch(t)) return warning;
    if (_link.hasMatch(t) && (_prize.hasMatch(t) || _threat.hasMatch(t))) return warning;
    return null;
  }
}
