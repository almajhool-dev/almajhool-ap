import 'package:almajhool_app/utils/helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('رفض الخادم للسبام يطلع برسالة عربية واضحة', () {
    const e = PostgrestException(
        message: 'blocked_spam: هذا المحتوى ممنوع (سبام) وتم حظر الحساب نهائيًا', code: 'P0001');
    expect(friendlyError(e), 'هذا المحتوى ممنوع (سبام) وتم حظر الحساب نهائيًا');
  });

  test('الأخطاء الثانية ما تتأثر', () {
    expect(friendlyError(Exception('something else')).contains('سبام'), false);
  });
}
