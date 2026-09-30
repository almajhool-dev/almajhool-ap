import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import 'core_services.dart';

class PickedMedia {
  final File file;
  final String type; // image | video | file | audio
  final String fileName;
  final int size;
  PickedMedia(this.file, this.type, this.fileName, this.size);
}

class MediaService {
  MediaService._();
  static final _picker = ImagePicker();
  static const _uuid = Uuid();
  static const chatBucket = 'chat-media';
  static const avatarBucket = 'avatars';

  // ذاكرة مؤقتة للروابط الموقّعة لتقليل الطلبات
  static final Map<String, (String, DateTime)> _signed = {};

  static Future<PickedMedia?> pickImage({bool camera = false}) async {
    final x = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 72, // ضغط قبل الرفع
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (x == null) return null;
    final f = File(x.path);
    return PickedMedia(f, 'image', x.name, await f.length());
  }

  static Future<PickedMedia?> pickVideo() async {
    final x = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
    if (x == null) return null;
    final f = File(x.path);
    return PickedMedia(f, 'video', x.name, await f.length());
  }

  static Future<PickedMedia?> pickFile() async {
    final r = await FilePicker.platform.pickFiles(withData: false);
    final path = r?.files.single.path;
    if (r == null || path == null) return null;
    final f = File(path);
    return PickedMedia(f, 'file', r.files.single.name, await f.length());
  }

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return 'bin';
    return name.substring(i + 1).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String contentType(String name, String type) {
    final e = _ext(name);
    const map = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp',
      'gif': 'image/gif', 'mp4': 'video/mp4', 'mov': 'video/quicktime', '3gp': 'video/3gpp',
      'm4a': 'audio/mp4', 'aac': 'audio/aac', 'mp3': 'audio/mpeg', 'ogg': 'audio/ogg',
      'pdf': 'application/pdf', 'zip': 'application/zip', 'txt': 'text/plain',
    };
    return map[e] ?? 'application/octet-stream';
  }

  /// رفع ملف لمحادثة. يرجع المسار داخل الـ bucket.
  static Future<String> uploadChatFile(String conversationId, File file, String fileName, String type) async {
    final size = await file.length();
    if (size > AppConfig.maxUploadBytes) {
      throw Exception('الحد الأقصى لحجم الملف 50 ميغابايت');
    }
    final path = '$conversationId/${_uuid.v4()}.${_ext(fileName)}';
    await supa.storage.from(chatBucket).upload(
          path,
          file,
          fileOptions: FileOptions(contentType: contentType(fileName, type), upsert: false),
        );
    return path;
  }

  /// نسخ ملف إلى محادثة أخرى (لإعادة التوجيه).
  static Future<String> copyToConversation(String fromPath, String targetConversationId) async {
    final name = fromPath.split('/').last;
    final to = '$targetConversationId/${_uuid.v4()}_$name';
    await supa.storage.from(chatBucket).copy(fromPath, to);
    return to;
  }

  static Future<String> signedUrl(String path) async {
    final cached = _signed[path];
    if (cached != null && cached.$2.isAfter(DateTime.now())) return cached.$1;
    final url = await supa.storage.from(chatBucket).createSignedUrl(path, 60 * 60 * 6);
    _signed[path] = (url, DateTime.now().add(const Duration(hours: 5)));
    return url;
  }

  /// رفع صورة شخصية أو صورة مجموعة (bucket عام).
  static Future<String> uploadAvatar(File file, {String? groupId}) async {
    final uid = myId!;
    final path = groupId == null
        ? '$uid/${_uuid.v4()}.jpg'
        : 'groups/$groupId/${_uuid.v4()}.jpg';
    await supa.storage.from(avatarBucket).upload(
          path,
          file,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return supa.storage.from(avatarBucket).getPublicUrl(path);
  }

  static Future<File?> pickAvatar() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 512,
      maxHeight: 512,
    );
    return x == null ? null : File(x.path);
  }
}
