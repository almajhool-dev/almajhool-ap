import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/post_repository.dart';
import '../../repositories/social_repositories.dart';
import '../../repositories/user_repositories.dart';
import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../admin/admin_screen.dart';
import '../profile/profile_screens.dart';
import 'image_editor.dart';
import 'stories.dart';

/// قائمة منشورات قابلة لإعادة الاستخدام (الصفحة الرئيسية + ملف المستخدم).
class PostsController extends ChangeNotifier {
  final PostRepository repo = PostRepository();
  final String? authorId;
  List<Post> posts = [];
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = true;
  String? error;

  PostsController({this.authorId}) {
    if (authorId == null) {
      posts = repo.cachedFeed();
      if (posts.isNotEmpty) loading = false;
    }
    refresh();
  }

  /// متحكم محلي بدون تحميل تلقائي (لشاشة منشور واحد).
  PostsController.local() : authorId = null {
    loading = false;
  }

  Future<void> refresh() async {
    try {
      posts = await repo.feed(authorId: authorId);
      hasMore = posts.length >= PostRepository.pageSize;
      error = null;
    } catch (e) {
      error = friendlyError(e);
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (loadingMore || !hasMore || posts.isEmpty) return;
    loadingMore = true;
    notifyListeners();
    try {
      final more = await repo.feed(authorId: authorId, before: posts.last.createdAt);
      posts.addAll(more.where((m) => !posts.any((p) => p.id == m.id)));
      hasMore = more.length >= PostRepository.pageSize;
    } catch (_) {}
    loadingMore = false;
    notifyListeners();
  }

  void replace(Post p) {
    final i = posts.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      posts[i] = p;
      notifyListeners();
    }
  }

  void remove(String id) {
    posts.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> toggleLike(Post p) async {
    final liked = !p.likedByMe;
    replace(p.copyWith(likedByMe: liked, likeCount: p.likeCount + (liked ? 1 : -1)));
    try {
      liked ? await repo.like(p.id) : await repo.unlike(p.id);
    } catch (_) {
      replace(p); // إرجاع الحالة عند الفشل
    }
  }
}

class FeedTab extends StatefulWidget {
  const FeedTab({super.key});
  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  final _ctrl = PostsController();
  final _scroll = ScrollController();
  final _stories = GlobalKey<StoryBarState>();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _ctrl.loadMore();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _compose() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ComposePostScreen()));
    if (ok == true) {
      await _ctrl.refresh();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionProvider>().profile;
    return SafeArea(
      child: ListenableBuilder(
        listenable: _ctrl,
        builder: (context, _) => RefreshIndicator(
          onRefresh: () async {
            _stories.currentState?.reload();
            await _ctrl.refresh();
          },
          child: CustomScrollView(
            controller: _scroll,
            cacheExtent: 1200,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      ShaderMask(
                        shaderCallback: (r) => AppColors.brandGradient.createShader(r),
                        child: const Text('المبرمج المجهول',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                      const Spacer(),
                      if (me != null) LevelChip(me.level),
                      if (me?.isAdmin ?? false)
                        IconButton(
                          tooltip: 'لوحة التحكم',
                          icon: const Icon(Icons.admin_panel_settings_rounded),
                          onPressed: () =>
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminScreen())),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: StoryBar(key: _stories)),
              SliverToBoxAdapter(
                child: Card(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _compose,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Avatar(url: me?.avatarUrl, name: me?.displayName ?? '', size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('بماذا تفكر يا ${me?.displayName ?? ''}؟',
                                style: TextStyle(color: Theme.of(context).hintColor)),
                          ),
                          Icon(Icons.photo_library_rounded, color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_ctrl.loading)
                const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              else if (_ctrl.posts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.dynamic_feed_rounded,
                    title: _ctrl.error ?? 'لا توجد منشورات بعد',
                    subtitle: _ctrl.error == null ? 'كن أول من ينشر واكسب 10 نقاط ⭐' : null,
                  ),
                )
              else
                SliverList.builder(
                  itemCount: _ctrl.posts.length + 1,
                  itemBuilder: (_, i) {
                    if (i == _ctrl.posts.length) {
                      return _ctrl.loadingMore
                          ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                          : const SizedBox(height: 24);
                    }
                    return PostCard(key: ValueKey(_ctrl.posts[i].id), post: _ctrl.posts[i], controller: _ctrl);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PostCard extends StatelessWidget {
  final Post post;
  final PostsController controller;
  const PostCard({super.key, required this.post, required this.controller});

  @override
  Widget build(BuildContext context) {
    final a = post.author;
    final isAdmin = context.read<SessionProvider>().isAdmin;
    final mine = post.authorId == myId;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            leading: GestureDetector(
              onTap: () => _openProfile(context),
              child: Avatar(url: a?.avatarUrl, name: a?.displayName ?? '', size: 42),
            ),
            title: GestureDetector(
              onTap: () => _openProfile(context),
              child: Row(
                children: [
                  Flexible(
                    child: NameWithBadge(a?.displayName ?? '',
                        verified: a?.verified ?? false, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 6),
                  if (a?.isOwner ?? false) const OwnerChip() else if (a != null) LevelChip(a.level),
                ],
              ),
            ),
            subtitle: Row(children: [
              Text('${Fmt.chatListTime(post.createdAt)}${post.editedAt != null ? ' · معدّل' : ''} · ',
                  style: const TextStyle(fontSize: 12)),
              Icon(kVisibility[post.visibility]?.$1 ?? Icons.public_rounded, size: 13),
            ]),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              onSelected: (v) => _menu(context, v),
              itemBuilder: (_) => [
                if (mine) const PopupMenuItem(value: 'edit', child: Text('تعديل المنشور')),
                if (mine || isAdmin) const PopupMenuItem(value: 'delete', child: Text('حذف المنشور')),
                if (!mine) const PopupMenuItem(value: 'report', child: Text('الإبلاغ عن المنشور')),
              ],
            ),
          ),
          if (post.content.isNotEmpty && post.bgColor != null && post.imageUrl == null)
            Container(
              constraints: const BoxConstraints(minHeight: 220),
              margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              padding: const EdgeInsets.all(22),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Color(post.bgColor!), borderRadius: BorderRadius.circular(14)),
              child: Text.rich(
                _mentions(post.content),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: post.content.length > 120 ? 18 : 24,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                  color: post.textColor != null ? Color(post.textColor!) : Colors.white,
                ),
              ),
            )
          else if (post.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Text.rich(_mentions(post.content),
                  style: TextStyle(
                      fontSize: 15.5,
                      height: 1.5,
                      color: post.textColor != null ? Color(post.textColor!) : null)),
            ),
          if (post.imageUrl != null)
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _NetImageViewer(url: post.imageUrl!))),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: CachedNetworkImage(
                  imageUrl: post.imageUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  memCacheWidth: 1080,
                  placeholder: (_, __) => Container(height: 260, color: Colors.black12),
                  errorWidget: (_, __, ___) => const SizedBox(height: 80, child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => controller.toggleLike(post),
                  icon: Icon(post.likedByMe ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: post.likedByMe ? AppColors.pink : null),
                  label: Text('${post.likeCount}'),
                ),
                TextButton.icon(
                  onPressed: () => openPost(context, post.id, controller: controller),
                  icon: const Icon(Icons.mode_comment_outlined),
                  label: Text('${post.commentCount}'),
                ),
                const Spacer(),
                Text('${post.likeCount} إعجاب', style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5))),
                const SizedBox(width: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static TextSpan _mentions(String text) {
    final spans = <TextSpan>[];
    final re = RegExp(r'@[A-Za-z0-9_.]{3,24}');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(0), style: const TextStyle(color: Color(0xFF1D9BF0), fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(children: spans);
  }

  Future<void> _menu(BuildContext context, String v) async {
    try {
      switch (v) {
        case 'edit':
          final ok = await Navigator.push<bool>(
              context, MaterialPageRoute(builder: (_) => ComposePostScreen(editing: post)));
          if (ok != true) return;
          final fresh = await controller.repo.one(post.id);
          if (fresh != null) controller.replace(fresh);
        case 'delete':
          if (!await confirmDialog(context, 'حذف المنشور', 'هل تريد حذف هذا المنشور؟', ok: 'حذف', danger: true)) return;
          await controller.repo.delete(post.id);
          controller.remove(post.id);
        case 'report':
          final reason = await promptText(context, 'سبب الإبلاغ', hint: 'مثلاً: محتوى مسيء، احتيال...', maxLines: 3, ok: 'إرسال');
          if (reason == null) return;
          await ProfileRepository().report(reason: reason, userId: post.authorId, postId: post.id);
          if (context.mounted) showSnack(context, 'تم إرسال البلاغ للإدارة، شكرًا لك');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  void _openProfile(BuildContext context) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: post.authorId)));
}

Future<void> openPost(BuildContext context, String postId, {PostsController? controller}) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PostScreen(postId: postId, controller: controller)),
  );
}

class _NetImageViewer extends StatelessWidget {
  final String url;
  const _NetImageViewer({required this.url});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(child: InteractiveViewer(maxScale: 5, child: CachedNetworkImage(imageUrl: url))),
      );
}

/// ألوان الكتابة والخلفية المتاحة للمنشورات.
const kPostTextColors = <int>[
  0xFFFFFFFF, 0xFF111111, 0xFFE53935, 0xFFFF9800, 0xFFFFEB3B,
  0xFF43A047, 0xFF1E88E5, 0xFF8E24AA, 0xFFEC407A, 0xFF00BCD4,
];
const kPostBgColors = <int>[
  0xFF7C4DFF, 0xFF1565C0, 0xFF00897B, 0xFFD81B60, 0xFFF4511E,
  0xFF2E7D32, 0xFF212121, 0xFF6D4C41, 0xFFFFB300, 0xFF5E35B1,
];

const kVisibility = <String, (IconData, String)>{
  'public': (Icons.public_rounded, 'عام'),
  'friends': (Icons.group_rounded, 'الأصدقاء'),
  'private': (Icons.lock_rounded, 'أنا فقط'),
  'custom': (Icons.tune_rounded, 'مخصص'),
};

/// إنشاء منشور أو تعديله: نص بلون، خلفية ملونة، صورة (تبديل/قص/تدوير)، وخصوصية.
class ComposePostScreen extends StatefulWidget {
  final Post? editing;
  const ComposePostScreen({super.key, this.editing});
  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  late final _text = TextEditingController(text: widget.editing?.content ?? '');
  Uint8List? _newImage; // صورة جديدة (بعد الضغط/التعديل)
  late String? _imageUrl = widget.editing?.imageUrl; // الصورة الحالية للمنشور
  late int? _textColor = widget.editing?.textColor;
  late int? _bgColor = widget.editing?.bgColor;
  late String _visibility = widget.editing?.visibility ?? 'public';
  List<String> _audience = [];
  bool _busy = false;

  bool get _hasImage => _newImage != null || _imageUrl != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null && e.visibility == 'custom') {
      PostRepository().audience(e.id).then((a) {
        if (mounted) setState(() => _audience = a);
      }).catchError((_) {});
    }
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final raw = await x.readAsBytes();
    final c = await compressImage(raw);
    if (mounted) {
      setState(() {
        _newImage = c;
        _bgColor = null;
      });
    }
  }

  Future<void> _editImage() async {
    Uint8List? src = _newImage;
    if (src == null && _imageUrl != null) {
      setState(() => _busy = true);
      try {
        final r = await http.get(Uri.parse(_imageUrl!));
        src = r.bodyBytes;
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
    if (src == null || !mounted) return;
    final out = await ImageEditorScreen.open(context, src);
    if (out != null && mounted) setState(() => _newImage = out);
  }

  Future<void> _chooseAudience() async {
    final res = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => _AudiencePicker(selected: _audience)),
    );
    if (res != null && mounted) {
      setState(() {
        _audience = res;
        _visibility = res.isEmpty ? _visibility : 'custom';
      });
    }
  }

  Future<void> _publish() async {
    if (_text.text.trim().isEmpty && !_hasImage) return;
    if (_visibility == 'custom' && _audience.isEmpty) {
      showSnack(context, 'اختر الأشخاص الذين يرون المنشور', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await PostRepository().save(
        id: widget.editing?.id,
        content: _text.text,
        newImage: _newImage,
        keepImageUrl: _newImage == null ? _imageUrl : null,
        textColor: _textColor,
        bgColor: _hasImage ? null : _bgColor,
        visibility: _visibility,
        audience: _audience,
      );
      if (mounted) {
        context.read<SessionProvider>().refresh();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _colorRow(List<int> colors, int? selected, ValueChanged<int?> onPick, {bool allowNone = true}) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (allowNone)
            _dot(null, selected == null, () => onPick(null)),
          for (final c in colors) _dot(c, selected == c, () => onPick(c)),
        ],
      ),
    );
  }

  Widget _dot(int? c, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c == null ? Colors.transparent : Color(c),
              border: Border.all(
                  color: sel ? Theme.of(context).colorScheme.primary : Colors.grey.withValues(alpha: 0.5),
                  width: sel ? 3 : 1.2),
            ),
            child: c == null ? const Icon(Icons.format_color_reset_rounded, size: 18) : null,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionProvider>().profile;
    final editing = widget.editing != null;
    final bg = !_hasImage && _bgColor != null ? Color(_bgColor!) : null;
    final txtColor = _textColor != null ? Color(_textColor!) : (bg != null ? Colors.white : null);
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'تعديل المنشور' : 'منشور جديد'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: _busy ? null : _publish,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(editing ? 'حفظ' : 'نشر'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Avatar(url: me?.avatarUrl, name: me?.displayName ?? '', size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NameWithBadge(me?.displayName ?? '', verified: me?.verified ?? false,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'custom') {
                        _chooseAudience();
                      } else {
                        setState(() => _visibility = v);
                      }
                    },
                    itemBuilder: (_) => [
                      for (final e in kVisibility.entries)
                        PopupMenuItem(
                          value: e.key,
                          child: Row(children: [Icon(e.value.$1, size: 20), const SizedBox(width: 10), Text(e.value.$2)]),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(kVisibility[_visibility]!.$1, size: 16),
                        const SizedBox(width: 6),
                        Text(_visibility == 'custom'
                            ? 'مخصص (${_audience.length})'
                            : kVisibility[_visibility]!.$2),
                        const Icon(Icons.arrow_drop_down, size: 18),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            decoration: bg == null ? null : BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
            constraints: BoxConstraints(minHeight: bg == null ? 0 : 220),
            alignment: Alignment.center,
            padding: bg == null ? EdgeInsets.zero : const EdgeInsets.all(18),
            child: TextField(
              controller: _text,
              autofocus: !editing,
              maxLines: null,
              minLines: bg == null ? 5 : 2,
              maxLength: 3000,
              textAlign: bg == null ? TextAlign.start : TextAlign.center,
              style: TextStyle(
                color: txtColor,
                fontSize: bg == null ? 16 : 24,
                fontWeight: bg == null ? FontWeight.normal : FontWeight.w800,
              ),
              decoration: InputDecoration(
                hintText: 'اكتب شيئًا... ولإشارة شخص اكتب @ ثم اسم المستخدم',
                hintStyle: TextStyle(color: bg != null ? Colors.white70 : null),
                border: InputBorder.none,
                filled: false,
                counterText: bg != null ? '' : null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('لون الكتابة', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          _colorRow(kPostTextColors, _textColor, (c) => setState(() => _textColor = c)),
          if (!_hasImage) ...[
            const SizedBox(height: 12),
            const Text('خلفية ملونة (للمنشور النصي)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _colorRow(kPostBgColors, _bgColor, (c) => setState(() => _bgColor = c)),
          ],
          const SizedBox(height: 14),
          if (_hasImage)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _newImage != null
                      ? Image.memory(_newImage!)
                      : CachedNetworkImage(imageUrl: _imageUrl!),
                ),
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: IconButton.filled(
                    tooltip: 'إزالة الصورة',
                    onPressed: () => setState(() {
                      _newImage = null;
                      _imageUrl = null;
                    }),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.photo_library_rounded),
                label: Text(_hasImage ? 'تبديل الصورة' : 'إضافة صورة'),
              ),
              if (_hasImage)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _editImage,
                  icon: const Icon(Icons.crop_rotate_rounded),
                  label: const Text('قص وتعديل'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// اختيار الأصدقاء الذين يرون المنشور (خصوصية «مخصص»).
class _AudiencePicker extends StatefulWidget {
  final List<String> selected;
  const _AudiencePicker({required this.selected});
  @override
  State<_AudiencePicker> createState() => _AudiencePickerState();
}

class _AudiencePickerState extends State<_AudiencePicker> {
  late final Set<String> _sel = {...widget.selected};
  List<Profile> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ContactRepository().load().then((r) {
      if (mounted) setState(() => _friends = r.contacts);
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('من يرى المنشور؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, _sel.toList()), child: Text('تم (${_sel.length})')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? const EmptyState(icon: Icons.group_off_rounded, title: 'لا يوجد أصدقاء بعد')
              : ListView(
                  children: [
                    for (final f in _friends)
                      CheckboxListTile(
                        value: _sel.contains(f.id),
                        onChanged: (v) => setState(() => v == true ? _sel.add(f.id) : _sel.remove(f.id)),
                        secondary: Avatar(url: f.avatarUrl, name: f.displayName),
                        title: Text(f.displayName),
                        subtitle: Text('@${f.username}'),
                      ),
                  ],
                ),
    );
  }
}

class PostScreen extends StatefulWidget {
  final String postId;
  final PostsController? controller;
  const PostScreen({super.key, required this.postId, this.controller});
  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  final _repo = PostRepository();
  final _text = TextEditingController();
  Post? _post;
  List<PostComment> _comments = [];
  bool _loading = true;
  bool _sending = false;
  late final PostsController _ctrl = widget.controller ?? PostsController.local();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _repo.one(widget.postId);
      final c = await _repo.comments(widget.postId);
      if (mounted) {
        setState(() {
          _post = p;
          _comments = c;
          _loading = false;
        });
      }
      if (p != null) {
        if (_ctrl.posts.any((x) => x.id == p.id)) {
          _ctrl.replace(p);
        } else {
          _ctrl.posts.insert(0, p);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showSnack(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _repo.comment(widget.postId, t);
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.read<SessionProvider>().isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('المنشور')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _post == null
              ? const EmptyState(icon: Icons.hide_source_rounded, title: 'المنشور غير متاح')
              : Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          children: [
                            ListenableBuilder(
                              listenable: _ctrl,
                              builder: (_, __) {
                                final p = _ctrl.posts.firstWhere((x) => x.id == _post!.id, orElse: () => _post!);
                                return PostCard(post: p, controller: _ctrl);
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                              child: Text('التعليقات (${_comments.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            if (_comments.isEmpty)
                              const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد تعليقات بعد. كن أول من يعلّق!')),
                            for (final c in _comments)
                              ListTile(
                                leading: Avatar(url: c.author?.avatarUrl, name: c.author?.displayName ?? '', size: 38),
                                title: NameWithBadge(c.author?.displayName ?? '',
                                    verified: c.author?.verified ?? false,
                                    badgeSize: 14,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                subtitle: Text(c.content, style: const TextStyle(fontSize: 14.5)),
                                trailing: Text(Fmt.chatListTime(c.createdAt), style: const TextStyle(fontSize: 11)),
                                onLongPress: (c.authorId == myId || _post!.authorId == myId || isAdmin)
                                    ? () async {
                                        if (!await confirmDialog(context, 'حذف التعليق', 'حذف هذا التعليق؟', ok: 'حذف', danger: true)) {
                                          return;
                                        }
                                        try {
                                          await _repo.deleteComment(c.id);
                                          await _load();
                                        } catch (e) {
                                          if (context.mounted) showSnack(context, friendlyError(e), error: true);
                                        }
                                      }
                                    : null,
                              ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _text,
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 1000,
                                decoration: const InputDecoration(hintText: 'اكتب تعليقًا...', counterText: '', isDense: true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _sending ? null : _send,
                              icon: _sending
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.send_rounded),
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
