import 'dart:typed_data';

import 'package:almajhool_app/services/secure_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AES-GCM round trip + tamper detection', () {
    SecureVault.debugSetKey(Uint8List.fromList(List<int>.generate(32, (i) => i)));
    const msg = '[{"id":"1","content":"سر بيننا 🔐"}]';
    final enc = SecureVault.encrypt(msg)!;
    expect(enc.startsWith('VYF1:'), true);
    expect(enc.contains('سر'), false);
    expect(SecureVault.decrypt(enc), msg);
    // نفس النص يطلع مختلف كل مرة (رقم عشوائي جديد)
    expect(SecureVault.encrypt(msg) != enc, true);
    // أي تعديل بالملف ينكشف
    final bad = '${enc.substring(0, enc.length - 6)}AAAAAA';
    expect(SecureVault.decrypt(bad), null);
    // مفتاح ثاني ما يفك
    SecureVault.debugSetKey(Uint8List.fromList(List<int>.generate(32, (i) => 255 - i)));
    expect(SecureVault.decrypt(enc), null);
  });

  test('session migrates from plain storage and stays logged in', () async {
    SharedPreferences.setMockInitialValues({'sb-abc-auth-token': '{"access_token":"t1"}'});
    SecureVault.debugSetKey(Uint8List.fromList(List<int>.generate(32, (i) => i * 3 % 256)));
    final s = SecureSessionStorage('sb-abc-auth-token');
    await s.initialize();
    expect(await s.hasAccessToken(), true);
    expect(await s.accessToken(), '{"access_token":"t1"}');
    final p = await SharedPreferences.getInstance();
    expect(p.getString('sb-abc-auth-token'), null);
    expect(p.getString('vyfri_session_v1')!.startsWith('VYF1:'), true);
    // تشغيل ثاني: يقرا النسخة المشفّرة
    final s2 = SecureSessionStorage('sb-abc-auth-token');
    await s2.initialize();
    expect(await s2.accessToken(), '{"access_token":"t1"}');
    await s2.persistSession('{"access_token":"t2"}');
    expect(p.getString('vyfri_session_v1')!.contains('t2'), false);
    await s2.removePersistedSession();
    expect(await s2.hasAccessToken(), false);
    expect(p.getString('vyfri_session_v1'), null);
  });

  test('no vault on device -> falls back to plain (never locks the user out)', () async {
    SharedPreferences.setMockInitialValues({});
    SecureVault.debugSetKey(null);
    final s = SecureSessionStorage('sb-abc-auth-token');
    await s.persistSession('{"access_token":"t3"}');
    final p = await SharedPreferences.getInstance();
    expect(p.getString('sb-abc-auth-token'), '{"access_token":"t3"}');
  });
}
