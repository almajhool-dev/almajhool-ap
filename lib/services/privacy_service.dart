import 'package:flutter/foundation.dart';

import 'core_services.dart';

/// إعدادات الخصوصية الشخصية (محفوظة بالخادم ومحد غيرك يشوفها).
class PrivacyService {
  PrivacyService._();

  /// مشاهدة الستوري بشكل مخفي: صاحب الستوري ما يشوف اسمك بقائمة المشاهدين.
  static final storyGhost = ValueNotifier<bool>(false);
  static bool _loaded = false;

  static Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      storyGhost.value = (await supa.rpc('get_story_ghost')) == true;
      _loaded = true;
    } catch (_) {}
  }

  static Future<void> setStoryGhost(bool on) async {
    final old = storyGhost.value;
    storyGhost.value = on;
    try {
      await supa.rpc('set_story_ghost', params: {'p_on': on});
      _loaded = true;
    } catch (e) {
      storyGhost.value = old;
      rethrow;
    }
  }

  static void reset() {
    _loaded = false;
    storyGhost.value = false;
  }
}
