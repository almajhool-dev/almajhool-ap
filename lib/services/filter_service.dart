import 'package:flutter/services.dart';

/// فلاتر البث المباشر (تُطبَّق على الكاميرا قبل الإرسال، يراها كل المشاهدين).
class LiveFilter {
  final String id;
  final String name;
  final String emoji;
  const LiveFilter(this.id, this.name, this.emoji);
}

class FilterService {
  FilterService._();
  static const _ch = MethodChannel('almajhool/filters');

  static const filters = [
    LiveFilter('none', 'بدون', '🚫'),
    LiveFilter('beauty', 'جمال', '✨'),
    LiveFilter('bright', 'مشرق', '☀️'),
    LiveFilter('warm', 'دافئ', '🌅'),
    LiveFilter('pink', 'وردي', '🌸'),
    LiveFilter('cool', 'بارد', '❄️'),
    LiveFilter('vivid', 'حيوي', '🌈'),
    LiveFilter('cinema', 'سينمائي', '🎬'),
    LiveFilter('vintage', 'قديم', '📷'),
    LiveFilter('sepia', 'كلاسيكي', '🟤'),
    LiveFilter('bw', 'أبيض وأسود', '🖤'),
  ];

  static Future<bool> apply(String trackId, String filter) async {
    try {
      return await _ch.invokeMethod<bool>('set', {'track': trackId, 'name': filter}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
