import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'core_services.dart';

/// سمة خلفية متحركة.
class FxTheme {
  final String id;
  final String name;

  /// نوع الحركة: aurora (أضواء) · matrix (شيفرة تنزل) · network (شبكة نقاط مترابطة) · waves (أمواج)
  final String base;
  final List<Color> colors;
  final String words;
  final bool builtin;
  final bool published;

  /// خلفية ثابتة (ما تتحرك أبدًا حتى لو الحركة شغّالة): خلفيات المستخدمين كلها ثابتة
  final bool still;

  /// خلفية صورة من معرض المستخدم (base = 'photo'): مسار الصورة بالجهاز
  final String? path;

  const FxTheme({
    required this.id,
    required this.name,
    required this.base,
    required this.colors,
    this.words = '',
    this.builtin = false,
    this.published = false,
    this.still = false,
    this.path,
  });

  bool get isPhoto => base == 'photo';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'base': base,
        'colors': [for (final c in colors) c.toARGB32()],
        'words': words,
        'still': still,
        if (path != null) 'path': path,
      };

  /// [custom]: خلفية سوّاها المستخدم بجهازه — ثابتة إلا إذا انحفظت متحركة صراحةً (من المالك)
  static FxTheme fromJson(Map m, {bool published = false, bool custom = false}) {
    final cs = <Color>[];
    for (final v in (m['colors'] as List? ?? const [])) {
      cs.add(Color((v as num).toInt()));
    }
    while (cs.length < 3) {
      cs.add(const [Color(0xFF00E5FF), Color(0xFF7C4DFF), Color(0xFFFF4D9D)][cs.length]);
    }
    final b = '${m['base'] ?? 'aurora'}';
    final path = m['path'] is String && custom ? m['path'] as String : null;
    final photo = b == 'photo' && path != null;
    return FxTheme(
      id: '${m['id']}',
      name: '${m['name'] ?? 'سمة'}',
      base: photo ? 'photo' : (FxSettings.bases.contains(b) ? b : 'aurora'),
      colors: cs.take(3).toList(),
      words: '${m['words'] ?? ''}',
      published: published,
      still: photo || (custom && m['still'] != false),
      path: photo ? path : null,
    );
  }

  /// كلمات/رموز السمة (للشيفرة والشبكة)
  List<String> get tokens {
    final w = words.split(RegExp(r'[\s,،]+')).where((e) => e.trim().isNotEmpty).toList();
    if (w.isNotEmpty) return w.take(40).toList();
    switch (base) {
      case 'matrix':
        return const ['0', '1', 'AES', 'RSA', 'SHA', '🔒', 'TLS', '⊕', '2FA'];
      case 'network':
        return const ['❤', '💬', '👍', '⭐', '🔁', '🔔'];
      default:
        return const [];
    }
  }
}

/// إعدادات الخلفيات: الحركة (يتحكم بيها المالك لكل المستخدمين) + الخلفية المختارة
/// + خلفيات المستخدم الثابتة (ألوان/نقوش أو صورة) + سمات المالك المنشورة.
class FxSettings extends ChangeNotifier {
  FxSettings._();
  static final instance = FxSettings._();

  static const bases = ['aurora', 'matrix', 'network', 'waves'];
  static const baseNames = {
    'aurora': 'أضواء شفق',
    'matrix': 'شيفرة تنزل',
    'network': 'شبكة مترابطة',
    'waves': 'أمواج',
  };

  static const builtins = [
    FxTheme(
      id: 'aurora',
      name: 'شفق VYFRI',
      base: 'aurora',
      colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF), Color(0xFFFF4D9D)],
      builtin: true,
    ),
    FxTheme(
      id: 'cyber',
      name: 'خوارزميات الأمن السيبراني',
      base: 'matrix',
      colors: [Color(0xFF00FF9C), Color(0xFF00E5FF), Color(0xFF7C4DFF)],
      words: '0 1 AES-256 RSA SHA-256 HMAC TLS1.3 ECDH 2FA 🔒 🛡 ⊕ 0x7F hash salt',
      builtin: true,
    ),
    FxTheme(
      id: 'social',
      name: 'خوارزميات التواصل الاجتماعي',
      base: 'network',
      colors: [Color(0xFFFF4D9D), Color(0xFF00E5FF), Color(0xFF7C4DFF)],
      words: '❤ 💬 👍 🔁 ⭐ 🔔 👥 📈 #',
      builtin: true,
    ),
    FxTheme(
      id: 'waves',
      name: 'أمواج هادئة',
      base: 'waves',
      colors: [Color(0xFF2979FF), Color(0xFF00E5FF), Color(0xFF7C4DFF)],
      builtin: true,
    ),
  ];

  /// أقصى عدد خلفيات صور بالجهاز
  static const maxPhotos = 6;

  bool _loaded = false;

  /// حركة الخلفيات لكل المستخدمين — يقررها المالك من الخادم (app_settings.fx_motion)
  bool motion = true;
  String themeId = 'aurora';
  List<FxTheme> custom = [];
  List<FxTheme> published = [];

  List<FxTheme> get all => [...builtins, ...published, ...custom];

  FxTheme get current {
    for (final t in all) {
      if (t.id == themeId) return t;
    }
    return builtins.first;
  }

  /// هل هالخلفية تتحرك هسه؟ (الحركة شغّالة من المالك، والخلفية مو ثابتة ولا صورة)
  bool animates(FxTheme t) => motion && !t.still && !t.isPhoto;

  void load() {
    if (_loaded) return;
    _loaded = true;
    try {
      // آخر حالة وصلت من الخادم (حتى أول ما يفتح التطبيق بدون نت تبقى نفسها)
      motion = CacheService.getString('fx_motion') != '0';
      themeId = CacheService.getString('fx_theme') ?? 'aurora';
      final raw = CacheService.getString('fx_custom');
      if (raw != null && raw.isNotEmpty) {
        custom = [for (final m in jsonDecode(raw) as List) FxTheme.fromJson(m as Map, custom: true)];
      }
      final pub = CacheService.getString('fx_published');
      if (pub != null && pub.isNotEmpty) {
        published = [for (final m in jsonDecode(pub) as List) FxTheme.fromJson(m as Map, published: true)];
      }
    } catch (_) {}
  }

  /// من الخادم (أو من زر المالك): تشغيل/إيقاف الحركة عند الكل
  void setMotion(bool v) {
    if (_loaded && motion == v) return;
    load();
    motion = v;
    CacheService.setString('fx_motion', v ? '1' : '0');
    notifyListeners();
  }

  void select(String id) {
    themeId = id;
    CacheService.setString('fx_theme', id);
    notifyListeners();
  }

  void _saveCustom() => CacheService.setString('fx_custom', jsonEncode([for (final t in custom) t.toJson()]));

  void addCustom(FxTheme t) {
    custom = [...custom.where((e) => e.id != t.id), t];
    _saveCustom();
    select(t.id);
  }

  void removeCustom(String id) {
    for (final t in custom) {
      if (t.id == id && t.path != null) {
        try {
          File(t.path!).deleteSync();
        } catch (_) {}
      }
    }
    custom = custom.where((e) => e.id != id).toList();
    _saveCustom();
    if (themeId == id) {
      themeId = 'aurora';
      CacheService.setString('fx_theme', themeId);
    }
    notifyListeners();
  }

  int get photoCount => custom.where((t) => t.isPhoto).length;

  /// خلفية ثابتة من صورة بمعرض المستخدم. تنحفظ بالجهاز بس (ما تنرفع لأي مكان).
  /// ترجع null إذا ما اختار صورة.
  Future<FxTheme?> addPhoto() async {
    if (photoCount >= maxPhotos) {
      throw Exception('وصلت حد الصور ($maxPhotos)، احذف وحدة قديمة');
    }
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048, // كافي لشاشة أي تلفون، وتبقى خفيفة بالذاكرة
      maxHeight: 2048,
      imageQuality: 88,
    );
    if (x == null) return null;
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/fx_backgrounds');
    await dir.create(recursive: true);
    final id = 'photo_${DateTime.now().millisecondsSinceEpoch}';
    final dest = '${dir.path}/$id.img';
    await File(x.path).copy(dest);
    final t = FxTheme(
      id: id,
      name: 'صورة من معرضي',
      base: 'photo',
      colors: builtins.first.colors,
      still: true,
      path: dest,
    );
    addCustom(t);
    return t;
  }

  /// سمات نشرها المالك لكل المستخدمين
  Future<void> refreshPublished() async {
    try {
      final r = await supa.from('app_themes').select().order('created_at', ascending: false).limit(50);
      published = [for (final m in r) FxTheme.fromJson({...m, 'id': 'pub_${m['id']}'}, published: true)];
      CacheService.setString('fx_published', jsonEncode([for (final t in published) t.toJson()]));
      notifyListeners();
    } catch (_) {}
  }
}
