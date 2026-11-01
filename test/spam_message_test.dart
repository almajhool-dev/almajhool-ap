import 'package:almajhool_app/services/media_service.dart';
import 'package:almajhool_app/utils/helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('رفض الخادم للسبام يطلع برسالة عربية واضحة', () {
    const e = PostgrestException(
        message: 'blocked_spam: هذا المحتوى ممنوع (سبام) وتم حظر الحساب نهائيًا', code: 'P0001');
    expect(friendlyError(e), 'هذا المحتوى ممنوع (سبام) وتم حظر الحساب نهائيًا');
  });

  test('كل نوع حظر يطلع بسببه الحقيقي', () {
    const e = PostgrestException(message: 'blocked_spam: سبام إباحي ممنوع وتم حظر الحساب نهائيًا', code: 'P0001');
    expect(friendlyError(e), 'سبام إباحي ممنوع وتم حظر الحساب نهائيًا');
  });

  test('المنع (بدون حظر) يطلع بسببه', () {
    const e = PostgrestException(
        message: 'blocked_content: روابط ملفات التطبيقات (APK) ممنوعة حفاظًا على أمانكم', code: 'P0001');
    expect(friendlyError(e), 'روابط ملفات التطبيقات (APK) ممنوعة حفاظًا على أمانكم');
  });

  test('حد السرعة يطلع بسببه، وبدون سبب يطلع النص العام', () {
    const a = PostgrestException(message: 'rate_limited: وصلت حد الرسائل لهالساعة، حاول بعد شوية');
    expect(friendlyError(a), 'وصلت حد الرسائل لهالساعة، حاول بعد شوية');
    const b = PostgrestException(message: 'rate_limited');
    expect(friendlyError(b), 'تمهّل شوية وحاول بعد قليل');
  });

  test('الأخطاء الثانية ما تتأثر', () {
    expect(friendlyError(Exception('something else')).contains('سبام'), false);
  });

  test('ملفات التطبيقات والبرامج تنمنع، والملفات العادية تمر', () {
    for (final n in ['WhatsApp_Gold.apk', 'game.XAPK', 'setup.exe', 'run.bat ', 'tool.jar', 'app.ipa']) {
      expect(MediaService.isBlockedFile(n), true, reason: n);
    }
    for (final n in ['cv.pdf', 'photo.jpg', 'notes.txt', 'archive.zip', 'song.mp3', 'apk_guide.pdf', 'noext']) {
      expect(MediaService.isBlockedFile(n), false, reason: n);
    }
  });
}
