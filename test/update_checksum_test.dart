import 'dart:io';

import 'package:almajhool_app/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('بصمة SHA-256 تطابق أداة النظام (ملف أكبر من جزء واحد)', () async {
    final dir = await Directory.systemTemp.createTemp('vyf');
    try {
      final f = File('${dir.path}/a.apk');
      // 3.5 ميگا حتى تنقرا على أكثر من جزء (كل جزء 1 ميگا)
      await f.writeAsBytes(List<int>.generate(3 * 1024 * 1024 + 512 * 1024, (i) => (i * 31 + 7) & 0xff));
      final r = await Process.run('sha256sum', [f.path]);
      expect(sha256OfFile(f.path), (r.stdout as String).split(' ').first);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('ملف فارغ', () async {
    final dir = await Directory.systemTemp.createTemp('vyf');
    try {
      final f = File('${dir.path}/e.apk');
      await f.writeAsBytes(const []);
      expect(sha256OfFile(f.path), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('أي تغيير ببايت واحد يغيّر البصمة (الملف المعدّل ينرفض)', () async {
    final dir = await Directory.systemTemp.createTemp('vyf');
    try {
      final f = File('${dir.path}/b.apk');
      final data = List<int>.generate(200000, (i) => i & 0xff);
      await f.writeAsBytes(data);
      final good = sha256OfFile(f.path);
      data[123456] ^= 1;
      await f.writeAsBytes(data);
      expect(sha256OfFile(f.path) == good, false);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
