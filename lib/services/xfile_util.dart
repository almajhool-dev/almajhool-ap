import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

import 'core_services.dart';

/// رفع ملف مختار يشتغل على أندرويد وعلى نسخة الويب (الآيفون) بنفس الكود.
Future<void> uploadXFile(String bucket, String path, XFile x, String contentType) async {
  if (kIsWeb) {
    await supa.storage.from(bucket).uploadBinary(path, await x.readAsBytes(),
        fileOptions: FileOptions(contentType: contentType, upsert: false));
  } else {
    await supa.storage.from(bucket).upload(path, File(x.path),
        fileOptions: FileOptions(contentType: contentType, upsert: false));
  }
}

/// مشغّل فيديو لملف مختار (على الويب الملف رابط blob).
VideoPlayerController videoFromXFile(XFile x) =>
    kIsWeb ? VideoPlayerController.networkUrl(Uri.parse(x.path)) : VideoPlayerController.file(File(x.path));
