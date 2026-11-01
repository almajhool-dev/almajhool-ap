import 'package:almajhool_app/utils/phishing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('رسائل التصيّد يطلع تحتها تنبيه', () {
    for (final t in [
      'هلا حبيبي دزلي الكود اللي وصلك برسالة ضروري',
      'انا من الدعم الفني، ارسل رمز التحقق حتى نوثق حسابك',
      'اعطيني كلمة السر مال حسابك حتى اصلحه',
      'مبروك ربحت 5000 كوينز! استلمها من هنا https://vyfri-gift.xyz',
      'حسابك راح ينحذف خلال 24 ساعة، أكد معلوماتك: www.vyfri-verify.com',
      'Send me the OTP code please',
    ]) {
      expect(PhishingHint.of(t), isNotNull, reason: t);
    }
  });

  test('الرسائل العادية ما يطلع تحتها شي', () {
    for (final t in [
      'شلونك حبيبي، شكو ماكو؟',
      'عيد مبارك وكل عام وانتم بخير',
      'شوف هذا الفيديو https://youtube.com/watch?v=abc',
      'الكود مال المشروع على GitHub، شوفه وكلي رأيك',
      'ربحت المباراة اليوم 3-1 😂',
      'نسيت كلمة السر مال الواي فاي',
      null,
      'هلا',
    ]) {
      expect(PhishingHint.of(t), isNull, reason: t);
    }
  });
}
