import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/story_repository.dart';
import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../profile/profile_screens.dart';
import 'feed_screens.dart';
import 'image_editor.dart';

/// شريط القصص أعلى الصفحة الرئيسية (مثل فيسبوك).
class StoryBar extends StatefulWidget {
  const StoryBar({super.key});
  @override
  State<StoryBar> createState() => StoryBarState();
}

class StoryBarState extends State<StoryBar> {
  final _repo = StoryRepository();
  List<StoryGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final g = await _repo.active();
      if (mounted) setState(() => _groups = g);
    } catch (_) {}
  }

  Future<void> _add() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('صورة من المعرض'),
              onTap: () => Navigator.pop(c, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: const Text('التقاط صورة'),
              onTap: () => Navigator.pop(c, false),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields_rounded),
              title: const Text('قصة نصية'),
              onTap: () => Navigator.pop(c, null),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    try {
      if (ok == null) {
        final done = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const _TextStoryComposer()));
        if (done == true) await reload();
        return;
      }
      final x = await ImagePicker().pickImage(source: ok ? ImageSource.gallery : ImageSource.camera);
      if (x == null || !mounted) return;
      final raw = await compressImage(await x.readAsBytes());
      if (!mounted) return;
      final edited = await ImageEditorScreen.open(context, raw);
      if (edited == null || !mounted) return;
      showSnack(context, 'جارٍ نشر القصة...');
      await _repo.addImage(edited);
      if (mounted) showSnack(context, 'تم نشر قصتك ✅ (تبقى 24 ساعة)');
      await reload();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _open(int index) async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => StoryViewer(groups: _groups, initialGroup: index),
        transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
      ),
    );
    if (mounted) setState(() {});
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionProvider>().profile;
    final mineIndex = _groups.indexWhere((g) => g.user.id == myId);
    return SizedBox(
      height: 112,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _bubble(
            label: mineIndex >= 0 ? 'قصتك' : 'أضف قصة',
            avatarUrl: me?.avatarUrl,
            name: me?.displayName ?? '',
            ring: mineIndex >= 0 ? (_groups[mineIndex].allSeen ? 0 : 1) : -1,
            plus: true,
            onTap: mineIndex >= 0 ? () => _open(mineIndex) : _add,
            onPlus: _add,
          ),
          for (var i = 0; i < _groups.length; i++)
            if (_groups[i].user.id != myId)
              _bubble(
                label: _groups[i].user.displayName,
                avatarUrl: _groups[i].user.avatarUrl,
                name: _groups[i].user.displayName,
                ring: _groups[i].allSeen ? 0 : 1,
                onTap: () => _open(i),
              ),
        ],
      ),
    );
  }

  /// ring: -1 بدون حلقة، 0 مشاهدة (رمادي)، 1 جديدة (ملونة)
  Widget _bubble({
    required String label,
    required String? avatarUrl,
    required String name,
    required int ring,
    required VoidCallback onTap,
    bool plus = false,
    VoidCallback? onPlus,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 78,
        child: Column(
          children: [
            const SizedBox(height: 6),
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: ring == 1 ? AppColors.brandGradient : null,
                    color: ring == 0 ? Colors.grey.withValues(alpha: 0.5) : null,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor),
                    child: Avatar(url: avatarUrl, name: name, size: 58),
                  ),
                ),
                if (plus)
                  PositionedDirectional(
                    bottom: 0,
                    end: 0,
                    child: GestureDetector(
                      onTap: onPlus,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).colorScheme.primary,
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                        ),
                        child: const Icon(Icons.add, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// عارض القصص بملء الشاشة: يتقدم تلقائيًا، اضغط يمين/يسار للتنقل، اضغط مطولًا للإيقاف.
class StoryViewer extends StatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroup;
  const StoryViewer({super.key, required this.groups, required this.initialGroup});
  @override
  State<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewer> with SingleTickerProviderStateMixin {
  final _repo = StoryRepository();
  late int _g = widget.initialGroup;
  int _s = 0;
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..addStatusListener((st) {
          if (st == AnimationStatus.completed) _next();
        });

  StoryGroup get _group => widget.groups[_g];
  Story get _story => _group.stories[_s];
  bool get _mine => _group.user.id == myId;

  @override
  void initState() {
    super.initState();
    // ابدأ من أول قصة غير مشاهدة
    final firstUnseen = _group.stories.indexWhere((s) => !s.seen);
    _s = firstUnseen < 0 ? 0 : firstUnseen;
    _show();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _show() {
    _anim.forward(from: 0);
    final st = _story;
    if (!st.seen && !_mine) {
      st.seen = true;
      _repo.markSeen(st.id).catchError((_) {});
    }
    if (mounted) setState(() {});
  }

  void _next() {
    if (_s < _group.stories.length - 1) {
      _s++;
      _show();
    } else if (_g < widget.groups.length - 1) {
      _g++;
      _s = 0;
      _show();
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (_s > 0) {
      _s--;
    } else if (_g > 0) {
      _g--;
      _s = widget.groups[_g].stories.length - 1;
    }
    _show();
  }

  Future<void> _viewers() async {
    _anim.stop();
    final list = await _repo.viewers(_story.id).catchError((_) => <Profile>[]);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: 360,
          child: list.isEmpty
              ? const Center(child: Text('لم يشاهدها أحد بعد'))
              : ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('شاهدها ${list.length}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  for (final p in list)
                    ListTile(leading: Avatar(url: p.avatarUrl, name: p.displayName), title: Text(p.displayName)),
                ]),
        ),
      ),
    );
    if (mounted) _anim.forward();
  }

  Future<void> _delete() async {
    _anim.stop();
    if (!await confirmDialog(context, 'حذف القصة', 'هل تريد حذف هذه القصة؟', ok: 'حذف', danger: true)) {
      _anim.forward();
      return;
    }
    try {
      await _repo.delete(_story.id);
      _group.stories.removeAt(_s);
      if (_group.stories.isEmpty) {
        if (mounted) Navigator.pop(context);
        return;
      }
      if (_s >= _group.stories.length) _s = _group.stories.length - 1;
      _show();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
      _anim.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _story;
    final u = _group.user;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => _anim.stop(),
        onLongPressEnd: (_) => _anim.forward(),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context);
        },
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          // واجهة عربية: الضغط على اليسار = التالي
          if (d.globalPosition.dx < w / 2) {
            _next();
          } else {
            _prev();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (st.kind == 'text')
              Container(
                color: Color(st.bgColor ?? 0xFF7C4DFF),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(28),
                child: Text(st.content ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.4)),
              )
            else
              Center(
                child: CachedNetworkImage(
                  imageUrl: st.mediaUrl ?? '',
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: AnimatedBuilder(
                      animation: _anim,
                      builder: (_, __) => Row(
                        children: [
                          for (var i = 0; i < _group.stories.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: LinearProgressIndicator(
                                  value: i < _s ? 1 : (i == _s ? _anim.value : 0),
                                  minHeight: 3,
                                  backgroundColor: Colors.white30,
                                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  ListTile(
                    leading: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: u.id))),
                      child: Avatar(url: u.avatarUrl, name: u.displayName, size: 40),
                    ),
                    title: Row(children: [
                      Flexible(
                        child: NameWithBadge(u.displayName,
                            verified: u.verified,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      ),
                      if (u.isOwner) ...[const SizedBox(width: 6), const OwnerChip()],
                    ]),
                    subtitle: Text(Fmt.chatListTime(st.createdAt), style: const TextStyle(color: Colors.white70)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  if (_mine)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            onPressed: _viewers,
                            icon: const Icon(Icons.visibility_rounded, color: Colors.white),
                            label: const Text('المشاهدات', style: TextStyle(color: Colors.white)),
                          ),
                          IconButton(
                            onPressed: _delete,
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextStoryComposer extends StatefulWidget {
  const _TextStoryComposer();
  @override
  State<_TextStoryComposer> createState() => _TextStoryComposerState();
}

class _TextStoryComposerState extends State<_TextStoryComposer> {
  final _text = TextEditingController();
  int _bg = kPostBgColors.first;
  bool _busy = false;

  Future<void> _publish() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await StoryRepository().addText(_text.text, _bg);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(_bg),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('قصة نصية'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _publish,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('نشر', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  maxLines: null,
                  maxLength: 500,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(
                    hintText: 'اكتب قصتك...',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                    filled: false,
                    counterStyle: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in kPostBgColors)
                    GestureDetector(
                      onTap: () => setState(() => _bg = c),
                      child: Container(
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 9),
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: c == _bg ? 3 : 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
