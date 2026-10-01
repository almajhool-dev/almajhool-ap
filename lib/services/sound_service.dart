import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'background_service.dart';
import 'call_service.dart';
import 'core_services.dart';

/// نغمة رنين قابلة للاختيار.
class Ringtone {
  final String id;
  final String name;
  const Ringtone(this.id, this.name);
}

/// أصوات التطبيق: نغمة الرنين، نغمة الانتظار للمتصل، وأصوات الرسائل.
/// كلها مفعّلة تلقائيًا بعد التثبيت ويمكن تغييرها من الإعدادات.
class SoundService {
  SoundService._();

  static const ringtones = [
    Ringtone('ring_naseem', 'نسيم'),
    Ringtone('ring_amal', 'أمل'),
    Ringtone('ring_hadi', 'هادئ'),
    Ringtone('ring_classic', 'كلاسيكي'),
    Ringtone('ring_nabd', 'نبض'),
  ];

  static const _kRingtone = 'sound_ringtone';
  static const _kCallSounds = 'sound_calls_on';
  static const _kMsgSounds = 'sound_messages_on';

  static String get ringtoneId {
    final id = CacheService.getString(_kRingtone);
    return ringtones.any((r) => r.id == id) ? id! : ringtones.first.id;
  }

  static String get ringtoneName => ringtones.firstWhere((r) => r.id == ringtoneId).name;
  static Future<void> setRingtone(String id) => CacheService.setString(_kRingtone, id);

  static bool get callSounds => CacheService.getBool(_kCallSounds) ?? true;
  static Future<void> setCallSounds(bool v) => CacheService.setBool(_kCallSounds, v);

  static bool get messageSounds => CacheService.getBool(_kMsgSounds) ?? true;
  static Future<void> setMessageSounds(bool v) => CacheService.setBool(_kMsgSounds, v);

  static AudioPlayer? _ring;
  static AudioPlayer? _back;
  static AudioPlayer? _msg;
  static AudioPlayer? _preview;
  static DateTime _lastMsg = DateTime(2000);

  static AudioPlayer _ringPlayer() => _ring ??= AudioPlayer()
    ..setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notificationRingtone,
        audioFocus: AndroidAudioFocus.gainTransient,
        stayAwake: true,
      ),
    ));

  static AudioPlayer _msgPlayer() => _msg ??= AudioPlayer()
    ..setPlayerMode(PlayerMode.lowLatency)
    ..setAudioContext(AudioContext(
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    ));

  /// نغمة الرنين للمكالمة الواردة (تتكرر حتى الإيقاف).
  static bool _ringOn = false;

  static Future<void> startRingtone() async {
    if (!callSounds || _ringOn) return;
    // التطبيق بالخلفية: خدمة الخلفية هي التي ترن (حتى لا يتكرر الصوت)
    if (BackgroundBridge.active && !BackgroundBridge.appVisible) return;
    _ringOn = true;
    try {
      final p = _ringPlayer();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.play(AssetSource('sounds/$ringtoneId.wav'), volume: 1.0);
    } catch (e) {
      debugPrint('ringtone failed: $e');
    }
  }

  static Future<void> stopRingtone() async {
    _ringOn = false;
    try {
      await _ring?.stop();
    } catch (_) {}
  }

  /// نغمة الانتظار التي يسمعها المتصل حتى يرد الطرف الآخر.
  static Future<void> startRingback({required bool speaker}) async {
    if (!callSounds) return;
    try {
      _back ??= AudioPlayer();
      await _back!.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: speaker,
          audioMode: AndroidAudioMode.inCommunication,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.voiceCommunicationSignalling,
          audioFocus: AndroidAudioFocus.none,
        ),
      ));
      await _back!.setReleaseMode(ReleaseMode.loop);
      await _back!.play(AssetSource('sounds/ringback.wav'), volume: 0.8);
    } catch (e) {
      debugPrint('ringback failed: $e');
    }
  }

  static Future<void> stopRingback() async {
    try {
      await _back?.stop();
    } catch (_) {}
  }

  static Future<void> _playMsg(String file) async {
    if (!messageSounds || CallService.instance.inCall) return;
    if (!BackgroundBridge.appVisible) return;
    final now = DateTime.now();
    if (now.difference(_lastMsg).inMilliseconds < 700) return; // لا تكرار مزعج عند وصول عدة رسائل
    _lastMsg = now;
    try {
      final p = _msgPlayer();
      await p.stop();
      await p.play(AssetSource('sounds/$file.wav'), volume: 0.9);
    } catch (e) {
      debugPrint('message sound failed: $e');
    }
  }

  /// صوت عند إرسال رسالة/بصمة/صورة.
  static Future<void> messageSent() => _playMsg('msg_sent');

  /// صوت عند وصول رسالة.
  static Future<void> messageReceived() => _playMsg('msg_in');

  /// تجربة نغمة من الإعدادات (مرة واحدة).
  static Future<void> preview(String id) async {
    try {
      _preview ??= AudioPlayer();
      await _preview!.stop();
      await _preview!.setReleaseMode(ReleaseMode.release);
      await _preview!.play(AssetSource('sounds/$id.wav'));
    } catch (_) {}
  }

  static Future<void> stopPreview() async {
    try {
      await _preview?.stop();
    } catch (_) {}
  }
}
