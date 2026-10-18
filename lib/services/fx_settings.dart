import 'dart:convert';

import 'package:flutter/material.dart';

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

  const FxTheme({
    required this.id,
    required this.name,
    required this.base,
    required this.colors,
    this.words = '',
    this.builtin = false,
    this.published = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'base': base,
        'colors': [for (final c in colors) c.toARGB32()],
        'words': words,
      };

  static FxTheme fromJson(Map m, {bool published = false}) {
    final cs = <Color>[];
    for (final v in (m['colors'] as List? ?? const [])) {
      cs.add(Color((v as num).toInt()));
    }
    while (cs.length < 3) {
      cs.add(const [Color(0xFF00E5FF), Color(0xFF7C4DFF), Color(0xFFFF4D9D)][cs.length]);
    }
    final b = '${m['base'] ?? 'aurora'}';
    return FxTheme(
      id: '${m['id']}',
      name: '${m['name'] ?? 'سمة'}',
      base: FxSettings.bases.contains(b) ? b : 'aurora',
      colors: cs.take(3).toList(),
      words: '${m['words'] ?? ''}',
      published: published,
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

/// إعدادات الخلفيات المتحركة (تشغيل/إيقاف + السمة المختارة + سمات المستخدم + سمات المالك المنشورة).
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

  bool _loaded = false;
  bool enabled = true;
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

  void load() {
    if (_loaded) return;
    _loaded = true;
    try {
      enabled = CacheService.getString('fx_enabled') != '0';
      themeId = CacheService.getString('fx_theme') ?? 'aurora';
      final raw = CacheService.getString('fx_custom');
      if (raw != null && raw.isNotEmpty) {
        custom = [for (final m in jsonDecode(raw) as List) FxTheme.fromJson(m as Map)];
      }
      final pub = CacheService.getString('fx_published');
      if (pub != null && pub.isNotEmpty) {
        published = [for (final m in jsonDecode(pub) as List) FxTheme.fromJson(m as Map, published: true)];
      }
    } catch (_) {}
  }

  void setEnabled(bool v) {
    enabled = v;
    CacheService.setString('fx_enabled', v ? '1' : '0');
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
    custom = custom.where((e) => e.id != id).toList();
    _saveCustom();
    if (themeId == id) themeId = 'aurora';
    notifyListeners();
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
