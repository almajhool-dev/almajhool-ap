import 'package:flutter/material.dart';

/// نشر بالخلفية مثل فيسبوك: تضغط «نشر» وترجع فورًا، والفيديو يتجهّز وينرفع وانت تتصفح.
class UploadJob {
  final String id;
  final String label;
  double progress; // -1 = غير معروف
  String stage;
  String? error;
  UploadJob(this.id, this.label) : progress = 0, stage = 'نجهّز...';
}

class PostUploader {
  PostUploader._();
  static final jobs = ValueNotifier<List<UploadJob>>([]);
  static VoidCallback? onPublished;
  static void Function(String msg, {bool error})? notify;

  static void _changed() => jobs.value = [...jobs.value];

  static void start(String label, Future<void> Function(void Function(double p, String stage) report) work) {
    final j = UploadJob(DateTime.now().microsecondsSinceEpoch.toString(), label);
    jobs.value = [...jobs.value, j];
    () async {
      try {
        await work((p, s) {
          j.progress = p;
          j.stage = s;
          _changed();
        });
        jobs.value = jobs.value.where((e) => e.id != j.id).toList();
        onPublished?.call();
        notify?.call('انتشر منشورك ✅');
      } catch (e) {
        j.error = '$e'.replaceFirst('Exception: ', '');
        _changed();
        notify?.call('ما انتشر المنشور: ${j.error}', error: true);
        Future.delayed(const Duration(seconds: 12), () {
          jobs.value = jobs.value.where((x) => x.id != j.id).toList();
        });
      }
    }();
  }
}
