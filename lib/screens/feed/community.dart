import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../services/video_cache.dart';
import '../../services/core_services.dart';
import '../../services/xfile_util.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../profile/profile_screens.dart';
import 'feed_screens.dart';

// =====================================================================
//  الترجمة: تترجم للغة جهاز المستخدم (حسب دولته)، والنتيجة تنحفظ بالخادم
// =====================================================================
class Translator {
  Translator._();
  static final Map<String, String> _cache = {};

  static String get targetLang {
    final l = WidgetsBinding.instance.platformDispatcher.locale.languageCode.toLowerCase();
    return RegExp(r'^[a-z]{2,3}$').hasMatch(l) ? l : 'ar';
  }

  /// هل النص مكتوب بلغة غير لغة المستخدم؟ (حسب نوع الحروف)
  static bool needsTranslation(String text) {
    final letters = text.replaceAll(RegExp(r'https?://\S+|@\S+|#\S+|[\s\d\p{P}\p{S}]', unicode: true), '');
    if (letters.length < 3) return false;
    final arabicScript = RegExp(r'[؀-ۿݐ-ݿࢠ-ࣿ]').allMatches(letters).length;
    final ratio = arabicScript / letters.length;
    final t = targetLang;
    if (t == 'ar' || t == 'fa' || t == 'ur' || t == 'ku' || t == 'ckb') return ratio < 0.5;
    return ratio > 0.3 || RegExp(r'[^\x00-\x7F]').hasMatch(letters) && t == 'en';
  }

  static Future<String> translate(String text) async {
    final lang = targetLang;
    final ck = '$lang:$text';
    final c = _cache[ck];
    if (c != null) return c;
    var r = Map<String, dynamic>.from(await supa.rpc('translate_request', params: {'p_text': text, 'p_lang': lang}) as Map);
    final key = r['key'] as String?;
    final until = DateTime.now().add(const Duration(seconds: 60));
    while (r['status'] == 'pending' && key != null && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      r = Map<String, dynamic>.from(await supa.rpc('translate_result', params: {'p_key': key}) as Map);
    }
    if (r['status'] != 'done') throw Exception('الترجمة ما اشتغلت هسه، جرّب بعد شوية');
    final out = (r['text'] ?? '') as String;
    _cache[ck] = out;
    return out;
  }
}

/// نص منشور أو تعليق: «عرض المزيد» للطويل + زر ترجمة إذا اللغة غير لغة المستخدم.
class RichPostText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextSpan Function(String text) spanBuilder;
  final int trimChars;
  final int trimLines;
  final TextAlign textAlign;
  final bool allowTranslate;
  const RichPostText({
    super.key,
    required this.text,
    required this.spanBuilder,
    this.style,
    this.trimChars = 320,
    this.trimLines = 6,
    this.textAlign = TextAlign.start,
    this.allowTranslate = true,
  });

  @override
  State<RichPostText> createState() => _RichPostTextState();
}

class _RichPostTextState extends State<RichPostText> {
  bool _expanded = false;
  String? _translated;
  bool _showTranslated = false;
  bool _busy = false;

  bool get _long =>
      widget.text.length > widget.trimChars || '\n'.allMatches(widget.text).length >= widget.trimLines;

  String _short(String t) {
    var cut = t;
    final lines = t.split('\n');
    if (lines.length > widget.trimLines) cut = lines.take(widget.trimLines).join('\n');
    if (cut.length > widget.trimChars) {
      cut = cut.substring(0, widget.trimChars);
      final sp = cut.lastIndexOf(' ');
      if (sp > widget.trimChars * 0.7) cut = cut.substring(0, sp);
    }
    return '${cut.trimRight()}…';
  }

  Future<void> _translate() async {
    if (_translated != null) {
      setState(() => _showTranslated = !_showTranslated);
      return;
    }
    setState(() => _busy = true);
    try {
      final t = await Translator.translate(widget.text);
      if (mounted) {
        setState(() {
          _translated = t;
          _showTranslated = true;
        });
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = _showTranslated && _translated != null ? _translated! : widget.text;
    final long = _long;
    final body = long && !_expanded ? _short(shown) : shown;
    final canTranslate = widget.allowTranslate && Translator.needsTranslation(widget.text);
    final link = TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 13.5);
    return Column(
      crossAxisAlignment: widget.textAlign == TextAlign.center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: long && !_expanded ? () => setState(() => _expanded = true) : null,
          child: Text.rich(widget.spanBuilder(body), style: widget.style, textAlign: widget.textAlign),
        ),
        if (long || canTranslate)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 14, children: [
              if (long)
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'عرض أقل' : 'عرض المزيد', style: link),
                ),
              if (canTranslate)
                InkWell(
                  onTap: _busy ? null : _translate,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_busy)
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6))
                    else
                      Icon(Icons.translate_rounded, size: 15, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(_showTranslated ? 'عرض الأصل' : 'ترجمة', style: link),
                  ]),
                ),
            ]),
          ),
      ],
    );
  }
}

// =====================================================================
//  فيديو المنشور + شارة كاب كات
// =====================================================================
class CapCutBadge extends StatelessWidget {
  const CapCutBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.movie_filter_rounded, size: 14, color: Colors.white),
          SizedBox(width: 5),
          Text('مصمم بـ CapCut', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ]),
      );
}

class PostVideo extends StatefulWidget {
  final String? url;
  final XFile? file;
  final bool capcut;
  const PostVideo({super.key, this.url, this.file, this.capcut = false});
  @override
  State<PostVideo> createState() => _PostVideoState();
}

class _PostVideoState extends State<PostVideo> {
  VideoPlayerController? _c;
  bool _failed = false;
  bool _userPaused = false;
  bool _visible = false;
  final _key = UniqueKey();

  /// فيديو واحد يشتغل بالمرة (مثل فيسبوك)
  static _PostVideoState? _playing;

  bool get _auto => widget.file == null; // فيديو المنشورات يشتغل وحده، معاينة النشر لا

  @override
  void initState() {
    super.initState();
    if (!_auto) _init();
  }

  bool _starting = false;

  Future<void> _init() async {
    if (_c != null || _starting) return;
    _starting = true;
    final c = widget.file != null ? videoFromXFile(widget.file!) : await VideoCache.controller(widget.url!);
    if (!mounted) {
      c.dispose();
      return;
    }
    _c = c;
    c.setLooping(true);
    if (_auto) c.setVolume(0); // يبدي بدون صوت، وتضغط السماعة تشغّل الصوت
    c.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      if (_visible && !_userPaused) _play();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    c.addListener(_tick);
  }

  void _play() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (_playing != null && _playing != this) _playing!._c?.pause();
    _playing = this;
    c.play();
  }

  void _onVisible(double f) {
    if (!mounted || !_auto) return;
    _visible = f >= 0.6;
    if (f > 0.05) _init();
    if (_visible && !_userPaused) {
      _play();
    } else if (f < 0.6) {
      _c?.pause();
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_playing == this) _playing = null;
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: _key,
      onVisibilityChanged: (i) => _onVisible(i.visibleFraction),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final c = _c;
    if (c == null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: const AspectRatio(aspectRatio: 9 / 16, child: ColoredBox(color: Colors.black)),
      );
    }
    final ready = c.value.isInitialized;
    final ratio = ready && c.value.aspectRatio > 0 ? c.value.aspectRatio : 9 / 16;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 520),
      child: AspectRatio(
        aspectRatio: ratio.clamp(0.5, 2.0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            if (ready) FittedBox(fit: BoxFit.contain, child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c))),
            if (!ready && !_failed) const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (_failed) const Center(child: Icon(Icons.videocam_off_rounded, color: Colors.white70, size: 40)),
            Positioned.fill(
              child: GestureDetector(
                onTap: !ready
                    ? null
                    : () {
                        if (c.value.isPlaying) {
                          _userPaused = true;
                          c.pause();
                        } else {
                          _userPaused = false;
                          _play();
                        }
                      },
                child: AnimatedOpacity(
                  opacity: ready && !c.value.isPlaying ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 64)),
                ),
              ),
            ),
            if (ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.only(top: 6)),
              ),
            if (ready)
              PositionedDirectional(
                bottom: 10,
                end: 10,
                child: InkWell(
                  onTap: () => c.setVolume(c.value.volume > 0 ? 0 : 1),
                  child: CircleAvatar(
                    radius: 15,
                    backgroundColor: Colors.black54,
                    child: Icon(c.value.volume > 0 ? Icons.volume_up_rounded : Icons.volume_off_rounded, size: 17, color: Colors.white),
                  ),
                ),
              ),
            if (widget.capcut) const PositionedDirectional(top: 10, start: 10, child: CapCutBadge()),
          ],
        ),
      ),
    );
  }
}

/// قوالب كاب كات: يفتح تطبيق CapCut (أو موقعه) على صفحة القوالب.
Future<void> openCapCutTemplates(BuildContext context) async {
  final tries = [
    Uri.parse('capcut://template'),
    Uri.parse('https://www.capcut.com/templates'),
  ];
  for (final u in tries) {
    try {
      if (await launchUrl(u, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
  }
  try {
    await launchUrl(Uri.parse('https://play.google.com/store/apps/details?id=com.lemon.lvoverseas'),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    if (context.mounted) showSnack(context, 'نزّل تطبيق CapCut من متجر Google Play', error: true);
  }
}

// =====================================================================
//  استقبال فيديو مشارك من CapCut (أو أي تطبيق) ← شاشة النشر مباشرة
// =====================================================================
class ShareInbox {
  ShareInbox._();
  static const _ch = MethodChannel('almajhool/share');
  static bool _bound = false;

  static void bind(GlobalKey<NavigatorState> nav) {
    if (_bound) return;
    _bound = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'shared') _open(nav);
    });
    Future<void>.delayed(const Duration(seconds: 2), () => _open(nav));
  }

  static Future<void> _open(GlobalKey<NavigatorState> nav) async {
    try {
      if (supa.auth.currentUser == null) return;
      final r = await _ch.invokeMethod<Map>('take');
      if (r == null) return;
      final path = r['path'] as String?;
      if (path == null || !File(path).existsSync()) return;
      final ctx = nav.currentContext;
      if (ctx == null) return;
      await Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => ComposePostScreen(sharedVideo: XFile(path), sharedCapCut: r['capcut'] == true),
        ),
      );
    } catch (_) {}
  }
}

// =====================================================================
//  المخالفة والطعن (للمستخدم)
// =====================================================================
class ViolationScreen extends StatefulWidget {
  final int violationId;
  const ViolationScreen({super.key, required this.violationId});
  @override
  State<ViolationScreen> createState() => _ViolationScreenState();
}

class _ViolationScreenState extends State<ViolationScreen> {
  Map<String, dynamic>? _v;
  bool _loading = true, _busy = false;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('my_violation', params: {'p_id': widget.violationId});
      if (mounted) setState(() => _v = r is Map ? Map<String, dynamic>.from(r) : null);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _appeal() async {
    final t = _text.text.trim();
    if (t.length < 3) {
      showSnack(context, 'اكتب ليش تشوف الحذف غلط', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await supa.rpc('appeal_submit', params: {'p_id': widget.violationId, 'p_text': t});
      if (mounted) showSnack(context, 'وصل طعنك لصاحب التطبيق، وراح يوصلك الرد بالإشعارات ✅');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final status = v?['appeal_status'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('مخالفة معايير المجتمع')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : v == null
              ? const EmptyState(icon: Icons.gpp_good_rounded, title: 'ما لكينا هذي المخالفة')
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      color: Colors.red.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            const Icon(Icons.gpp_bad_rounded, color: Colors.redAccent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(v['kind'] == 'post' ? 'منشورك ينتهك معايير المجتمع' : 'تعليقك ينتهك معايير المجتمع',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Text('السبب: ${v['reason'] ?? ''}'),
                          if ((v['strike'] ?? 0) != 0) Text('الإنذار رقم ${v['strike']} (بالرابع ينحظر الحساب)'),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('المحتوى اللي انحذف:', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    if ((v['content'] ?? '').toString().isNotEmpty)
                      Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('${v['content']}'))),
                    if (v['image_url'] != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ImageFiltered(
                          imageFilter: _blur,
                          child: CachedNetworkImage(imageUrl: v['image_url'] as String, height: 220, fit: BoxFit.cover),
                        ),
                      ),
                    const SizedBox(height: 18),
                    if (status == null) ...[
                      const Text('تشوف الحذف غلط؟ قدّم طعن وصاحب التطبيق يراجعه بنفسه:',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _text,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 1000,
                        decoration: const InputDecoration(hintText: 'اشرح ليش المحتوى ما بيه مخالفة...'),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _appeal,
                        icon: const Icon(Icons.gavel_rounded),
                        label: const Text('تقديم الطعن'),
                      ),
                    ] else
                      Card(
                        child: ListTile(
                          leading: Icon(
                            status == 'accepted'
                                ? Icons.check_circle_rounded
                                : status == 'rejected'
                                    ? Icons.cancel_rounded
                                    : Icons.hourglass_top_rounded,
                            color: status == 'accepted'
                                ? Colors.green
                                : status == 'rejected'
                                    ? Colors.redAccent
                                    : Colors.orange,
                          ),
                          title: Text(status == 'accepted'
                              ? 'تم قبول طعنك ورجع المحتوى'
                              : status == 'rejected'
                                  ? 'تم رفض الطعن'
                                  : 'طعنك قيد المراجعة'),
                          subtitle: Text('${v['appeal_text'] ?? ''}'),
                        ),
                      ),
                  ],
                ),
    );
  }

  static final _blur = ImageFilter.blur(sigmaX: 22, sigmaY: 22);
}

// =====================================================================
//  مراجعة الطعون والمحتوى المحذوف (للمالك)
// =====================================================================
class AppealsScreen extends StatefulWidget {
  const AppealsScreen({super.key});
  @override
  State<AppealsScreen> createState() => _AppealsScreenState();
}

class _AppealsScreenState extends State<AppealsScreen> {
  String _filter = 'pending';
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  final Set<int> _reveal = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await supa.rpc('mod_list', params: {'p_filter': _filter}) as List;
      _items = r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _decide(Map<String, dynamic> v, bool accept) async {
    final ok = await confirmDialog(
      context,
      accept ? 'قبول الطعن' : 'رفض الطعن',
      accept ? 'يرجع المحتوى وينشال الإنذار من حسابه (وإذا انحظر بسببه يرجع حسابه).' : 'المحتوى يبقى محذوف والإنذار يبقى.',
      ok: accept ? 'قبول' : 'رفض',
      danger: !accept,
    );
    if (!ok) return;
    try {
      await supa.rpc('mod_decide', params: {'p_id': v['id'], 'p_accept': accept});
      if (mounted) showSnack(context, accept ? 'تم القبول ✅' : 'تم الرفض');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الطعون والمحتوى المحذوف')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('طعون تنتظرك'), icon: Icon(Icons.gavel_rounded)),
              ButtonSegment(value: 'all', label: Text('كل المحذوف'), icon: Icon(Icons.history_rounded)),
            ],
            selected: {_filter},
            onSelectionChanged: (s) {
              setState(() => _filter = s.first);
              _load();
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? EmptyState(
                      icon: Icons.verified_user_rounded,
                      title: _filter == 'pending' ? 'ماكو طعون جديدة' : 'ما انحذف شي بعد')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final v = _items[i];
                          final id = (v['id'] as num).toInt();
                          final status = v['appeal_status'] as String?;
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                InkWell(
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => ProfileScreen(userId: v['user_id'] as String))),
                                  child: Row(children: [
                                    Avatar(url: v['avatar_url'] as String?, name: (v['display_name'] ?? '') as String, size: 36),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text('${v['display_name'] ?? ''} · إنذارات: ${v['warnings'] ?? 0}${v['is_banned'] == true ? ' · محظور' : ''}',
                                          style: const TextStyle(fontWeight: FontWeight.w800)),
                                    ),
                                    Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(v['kind'] == 'post' ? 'منشور' : 'تعليق'),
                                    ),
                                  ]),
                                ),
                                const SizedBox(height: 6),
                                Text('سبب الحذف: ${v['reason'] ?? ''}', style: const TextStyle(color: Colors.redAccent)),
                                if ((v['content'] ?? '').toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text('${v['content']}', maxLines: 8, overflow: TextOverflow.ellipsis),
                                  ),
                                if (v['image_url'] != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: GestureDetector(
                                      onTap: () => setState(() => _reveal.contains(id) ? _reveal.remove(id) : _reveal.add(id)),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: ImageFiltered(
                                          imageFilter: _reveal.contains(id)
                                              ? ImageFilter.blur(sigmaX: 0.01, sigmaY: 0.01)
                                              : ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                                          child: CachedNetworkImage(
                                              imageUrl: v['image_url'] as String, height: 200, width: double.infinity, fit: BoxFit.cover),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (v['image_url'] != null)
                                  const Text('اضغط على الصورة حتى تشوفها', style: TextStyle(fontSize: 11.5)),
                                if (v['appeal_text'] != null) ...[
                                  const Divider(),
                                  Text('طعنه: ${v['appeal_text']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                ],
                                const SizedBox(height: 8),
                                if (status == 'pending' || status == null)
                                  Row(children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(backgroundColor: Colors.green),
                                        onPressed: () => _decide(v, true),
                                        icon: const Icon(Icons.check_rounded),
                                        label: Text(status == null ? 'إرجاع المحتوى' : 'قبول الطعن'),
                                      ),
                                    ),
                                    if (status == 'pending') ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _decide(v, false),
                                          icon: const Icon(Icons.close_rounded),
                                          label: const Text('رفض'),
                                        ),
                                      ),
                                    ],
                                  ])
                                else
                                  Text(status == 'accepted' ? '✅ مقبول' : '❌ مرفوض',
                                      style: const TextStyle(fontWeight: FontWeight.w800)),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}

// =====================================================================
//  طلبات المتابعة (الحساب الخاص)
// =====================================================================
class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});
  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('follow_requests_list') as List;
      _items = r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _decide(String id, bool accept) async {
    try {
      await supa.rpc('follow_request_decide', params: {'p_requester': id, 'p_accept': accept});
      setState(() => _items.removeWhere((e) => e['id'] == id));
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات المتابعة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const EmptyState(icon: Icons.person_add_disabled_rounded, title: 'ماكو طلبات متابعة')
              : ListView(
                  children: [
                    for (final u in _items)
                      ListTile(
                        leading: Avatar(url: u['avatar_url'] as String?, name: (u['display_name'] ?? '') as String),
                        title: Text((u['display_name'] ?? '') as String),
                        subtitle: Text('@${u['username'] ?? ''}'),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: u['id'] as String))),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton.filled(
                            tooltip: 'قبول',
                            onPressed: () => _decide(u['id'] as String, true),
                            icon: const Icon(Icons.check_rounded),
                          ),
                          IconButton(
                            tooltip: 'رفض',
                            onPressed: () => _decide(u['id'] as String, false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ]),
                      ),
                  ],
                ),
    );
  }
}

// =====================================================================
//  إعداد «حساب خاص» + طلبات المتابعة (بالإعدادات)
// =====================================================================
class PrivateAccountTiles extends StatefulWidget {
  const PrivateAccountTiles({super.key});
  @override
  State<PrivateAccountTiles> createState() => _PrivateAccountTilesState();
}

class _PrivateAccountTilesState extends State<PrivateAccountTiles> {
  bool? _private;
  int _requests = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = myId;
    if (id == null) return;
    try {
      final r = Map<String, dynamic>.from(await supa.rpc('profile_counts', params: {'uid': id}) as Map);
      if (mounted) {
        setState(() {
          _private = r['is_private'] == true;
          _requests = (r['requests'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _private ??= false);
    }
  }

  Future<void> _set(bool v) async {
    setState(() {
      _busy = true;
      _private = v;
    });
    try {
      await supa.rpc('set_account_private', params: {'p_private': v});
      if (mounted) {
        showSnack(context, v ? 'حسابك صار خاص 🔒 — بس المتابعين اللي تقبلهم يشوفون منشوراتك وقصصك' : 'حسابك صار عام 🌍');
      }
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _private = !v);
        showSnack(context, friendlyError(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SwitchListTile(
        secondary: Icon(_private == true ? Icons.lock_rounded : Icons.public_rounded),
        title: const Text('حساب خاص 🔒'),
        subtitle: const Text('الناس يشوفون صورتك واسمك بس، ومنشوراتك وقصصك للمتابعين اللي تقبلهم'),
        value: _private ?? false,
        onChanged: _private == null || _busy ? null : _set,
      ),
      if (_private == true || _requests > 0)
        ListTile(
          leading: const Icon(Icons.person_add_alt_rounded),
          title: const Text('طلبات المتابعة'),
          trailing: _requests > 0
              ? CircleAvatar(radius: 12, child: Text('$_requests', style: const TextStyle(fontSize: 12)))
              : const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FollowRequestsScreen()))
              .then((_) => _load()),
        ),
    ]);
  }
}
