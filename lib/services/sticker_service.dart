import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'core_services.dart';

/// ملصق: رابط الصورة (متحركة أو ثابتة) + إيموجي احتياطي.
class Sticker {
  final String url;
  final String emoji;
  final String? id; // لملصقاتي الخاصة
  const Sticker(this.url, this.emoji, {this.id});
}

class StickerPack {
  final String name;
  final String icon;
  final List<Sticker> stickers;
  const StickerPack(this.name, this.icon, this.stickers);
}

/// ملصقات متحركة (Noto Animated Emoji من Google) + ملصقات المستخدم الموثّق الخاصة.
class StickerService {
  StickerService._();

  static String _url(String code) => 'https://fonts.gstatic.com/s/e/notoemoji/latest/$code/512.webp';

  static String _char(String code) =>
      String.fromCharCodes(code.split('_').map((h) => int.parse(h, radix: 16)));

  static StickerPack _pack(String name, String icon, List<String> codes) =>
      StickerPack(name, icon, [for (final c in codes) Sticker(_url(c), _char(c))]);

  static final packs = <StickerPack>[
    _pack('وجوه', '😂', [
      '1f602', '1f923', '1f60d', '1f970', '1f618', '1f60e', '1f929', '1f973', '1f607', '1f60a',
      '1f601', '1f606', '1f605', '1f61c', '1f92a', '1f60f', '1f644', '1f62c', '1f914', '1f92b',
      '1f971', '1f634', '1f62d', '1f97a', '1f979', '1f621', '1f92c', '1f631', '1f633', '1f608',
      '1f480', '1f921', '1f47b', '1f916', '1f47d', '1f4a9',
    ]),
    _pack('قلوب', '❤️', [
      '2764_fe0f', '1f9e1', '1f49b', '1f49a', '1f499', '1f49c', '1f5a4', '1f494', '2764_fe0f_200d_1f525',
      '1f496', '1f497', '1f498', '1f49d', '1f48b',
    ]),
    _pack('إيدين', '👍', [
      '1f44d', '1f44e', '1f44f', '1f64c', '1f64f', '1f4aa', '1f44b', '1f91d', '270c_fe0f', '1f91e', '1f44c',
      '1f918', '1f919', '1f449',
    ]),
    _pack('حيوانات', '🐱', [
      '1f436', '1f431', '1f981', '1f42f', '1f435', '1f648', '1f649', '1f64a', '1f984', '1f40d', '1f422',
      '1f419', '1f42c', '1f433', '1f98b', '1f41d', '1f40c', '1f414', '1f427', '1f989',
    ]),
    _pack('احتفال', '🎉', [
      '1f389', '1f38a', '1f382', '1f381', '1f388', '1f525', '2728', '1f4af', '1f31f', '1f4a5', '1f3c6',
      '1f947', '1f451', '1f48e', '1f680', '1f308', '26a1', '1f4b8', '1f4b0', '1f3b6',
    ]),
  ];

  /// ملصقاتي (المرفوعة من صوري).
  static Future<List<Sticker>> mine() async {
    final r = await supa.from('user_stickers').select().eq('user_id', myId!).order('created_at', ascending: false);
    return [for (final m in r) Sticker(m['url'] as String, '🎨', id: m['id'] as String)];
  }

  static Future<void> remove(String id) => supa.from('user_stickers').delete().eq('id', id);

  /// يختار صورة/GIF من المعرض ويحولها لملصق (512px، يحافظ على الشفافية والحركة).
  static Future<Sticker?> createFromGallery() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    final isGif = bytes.length > 3 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
    if (isGif && bytes.length > 3 * 1024 * 1024) {
      throw Exception('الملصق المتحرك لازم يكون أصغر من 3 ميگا');
    }
    final data = isGif ? bytes : await compute(_toStickerPng, bytes);
    final path = '${myId!}/stickers/${const Uuid().v4()}.${isGif ? 'gif' : 'png'}';
    await supa.storage.from('posts').uploadBinary(path, data,
        fileOptions: FileOptions(contentType: isGif ? 'image/gif' : 'image/png', upsert: false));
    final url = supa.storage.from('posts').getPublicUrl(path);
    final row = await supa
        .from('user_stickers')
        .insert({'user_id': myId, 'url': url, 'animated': isGif})
        .select()
        .single();
    return Sticker(url, '🎨', id: row['id'] as String);
  }
}

Uint8List _toStickerPng(Uint8List bytes) {
  var im = img.decodeImage(bytes);
  if (im == null) throw Exception('صورة غير صالحة');
  im = img.bakeOrientation(im);
  if (im.width > 512 || im.height > 512) {
    im = im.width >= im.height ? img.copyResize(im, width: 512) : img.copyResize(im, height: 512);
  }
  return Uint8List.fromList(img.encodePng(im, level: 6));
}
