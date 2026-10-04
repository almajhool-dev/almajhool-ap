import 'dart:convert';
import 'dart:io';

import 'core_services.dart';

/// تسجيلات البث المحفوظة على هذا الجهاز (لصاحب البث).
class LiveRecording {
  final String liveId;
  final String title;
  final String path;
  final DateTime at;
  LiveRecording(this.liveId, this.title, this.path, this.at);

  Map<String, dynamic> toMap() => {'live': liveId, 'title': title, 'path': path, 'at': at.toIso8601String()};
  factory LiveRecording.fromMap(Map<String, dynamic> m) => LiveRecording(
        (m['live'] ?? '') as String,
        (m['title'] ?? '') as String,
        (m['path'] ?? '') as String,
        DateTime.tryParse('${m['at']}') ?? DateTime.now(),
      );
}

class LiveRecordings {
  LiveRecordings._();
  static const _key = 'live_recordings';

  static List<LiveRecording> all() {
    final raw = CacheService.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => LiveRecording.fromMap(Map<String, dynamic>.from(e as Map)))
          .where((r) => File(r.path).existsSync())
          .toList()
        ..sort((a, b) => b.at.compareTo(a.at));
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(LiveRecording r) async {
    final l = all()..add(r);
    await CacheService.setString(_key, jsonEncode(l.map((e) => e.toMap()).toList()));
  }

  static Future<void> remove(LiveRecording r) async {
    try {
      final f = File(r.path);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
    final l = all().where((e) => e.path != r.path).toList();
    await CacheService.setString(_key, jsonEncode(l.map((e) => e.toMap()).toList()));
  }
}
