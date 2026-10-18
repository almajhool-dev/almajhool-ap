import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/live_repository.dart';
import '../../repositories/post_repository.dart';
import '../../repositories/social_repositories.dart';
import '../../repositories/user_repositories.dart';
import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../../widgets/reactions.dart';
import '../admin/admin_screen.dart';
import '../profile/profile_screens.dart';
import '../live/live_screens.dart';
import 'community.dart';
import 'image_editor.dart';
import 'stories.dart';
import '../../services/video_shrink.dart';
import '../reels/reels_screen.dart';
import '../market/market_screens.dart';

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

  /// تفاعل (أو null = شيل التفاعل) — يتحدث فورًا وبعدين يتأكد بالخادم
  Future<void> react(Post p, String? r) async {
    if (p.myReaction == r) return;
    replace(p.withReaction(r));
    try {
      r == null ? await repo.unlike(p.id) : await repo.like(p.id, r);
    } catch (_) {
      replace(p);
    }
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

  static VoidCallback? _toTop;

  /// الضغط على «الرئيسية» وانت بيها: يرجع لأول منشور (وإذا انت فوك يحدّث) مثل فيسبوك
  static void scrollToTop() => _toTop?.call();
  @override
  State<FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<FeedTab> {
  final _ctrl = PostsController();
  final _scroll = ScrollController();
  final _stories = GlobalKey<StoryBarState>();
  LiveSummary? _live;
  Timer? _liveTimer;

  Future<void> _loadLive() async {
    try {
      final myId = supa.auth.currentUser?.id;
      final all = await LiveRepository().active();
      final l = all.where((e) => e.host.id != myId).toList();
      if (mounted) setState(() => _live = l.isEmpty ? null : l.first);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadLive();
    _liveTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadLive());
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _ctrl.loadMore();
    });
    FeedTab._toTop = () {
      if (!_scroll.hasClients) return;
      if (_scroll.offset < 40) {
        _ctrl.refresh();
        _stories.currentState?.reload();
      } else {
        _scroll.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      }
    };
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
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
            _loadLive();
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
                        child: const Text('VYFRI',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'ريلز',
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReelsScreen())),
                        icon: const Icon(Icons.slow_motion_video_rounded, color: AppColors.pink),
                      ),
                      IconButton(
                        tooltip: 'السوق',
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketScreen())),
                        icon: const Icon(Icons.storefront_rounded, color: AppColors.cyan),
                      ),
                      IconButton(
                        tooltip: 'البث المباشر',
                        onPressed: () =>
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveListScreen())),
                        icon: const Icon(Icons.live_tv_rounded, color: Colors.redAccent),
                      ),
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
              if (_live != null)
                SliverToBoxAdapter(child: LivePreviewCard(key: ValueKey(_live!.id), live: _live!)),
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
                if (post.content.isNotEmpty)
                  const PopupMenuItem(
                      value: 'copy',
                      child: Row(children: [Icon(Icons.copy_rounded, size: 20), SizedBox(width: 10), Text('نسخ المنشور')])),
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
              child: RichPostText(
                  text: post.content,
                  spanBuilder: _mentions,
                  style: TextStyle(
                      fontSize: 15.5,
                      height: 1.5,
                      color: post.textColor != null ? Color(post.textColor!) : null)),
            ),
          if (post.videoUrl != null)
            PostVideo(key: ValueKey(post.videoUrl), url: post.videoUrl, capcut: post.madeWith == 'capcut')
          else if (post.imageUrl != null)
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _NetImageViewer(url: post.imageUrl!))),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: CachedNetworkImage(
                  imageUrl: post.imageUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  memCacheWidth: 1080,
                  fadeInDuration: const Duration(milliseconds: 90),
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, __) => Container(height: 260, color: Colors.black12),
                  errorWidget: (_, __, ___) => const SizedBox(height: 80, child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          if (post.shared != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              child: SharedPostEmbed(post: post.shared!),
            )
          else if (post.sharedPostId != null)
            Container(
              margin: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12), border: Border.all(color: scheme.outlineVariant)),
              child: const Text('هذا المحتوى غير متاح حاليًا (انحذف أو صاحبه غيّر من يشوفه).'),
            ),
          // ملخص: التفاعلات يمين، والتعليقات والمشاركات يسار (مثل فيسبوك)
          if (post.likeCount > 0 || post.commentCount > 0 || post.shareCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
              child: Row(children: [
                ReactionSummary(post: post),
                const Spacer(),
                if (post.commentCount > 0)
                  InkWell(
                    onTap: () => openPost(context, post.id, controller: controller),
                    child: Text('${post.commentCount} تعليق', style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
                  ),
                if (post.commentCount > 0 && post.shareCount > 0)
                  Text('  ·  ', style: TextStyle(color: Theme.of(context).hintColor)),
                if (post.shareCount > 0)
                  Text('${post.shareCount} مشاركة', style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
              ]),
            ),
          const Divider(height: 10, indent: 12, endIndent: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
            child: Row(children: [
              Expanded(child: ReactionButton(current: post.myReaction, onChanged: (r) => controller.react(post, r))),
              Expanded(
                child: _ActionBtn(
                  icon: Icons.mode_comment_outlined,
                  label: 'تعليق',
                  onTap: () => openPost(context, post.id, controller: controller),
                ),
              ),
              Expanded(
                child: _ActionBtn(
                  icon: Icons.reply_rounded,
                  flip: true,
                  label: 'مشاركة',
                  onTap: () => showSharePost(context, post.shared ?? post, controller: controller),
                ),
              ),
            ]),
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
        case 'copy':
          await Clipboard.setData(ClipboardData(text: post.content));
          if (context.mounted) showSnack(context, 'تم نسخ المنشور 📋');
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

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool flip;
  const _ActionBtn({required this.icon, required this.label, required this.onTap, this.flip = false});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75);
    Widget ic = Icon(icon, size: 21, color: c);
    if (flip) ic = Transform.flip(flipX: true, child: ic);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          ic,
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: c)),
        ]),
      ),
    );
  }
}

/// المنشور الأصلي داخل منشور المشاركة
class SharedPostEmbed extends StatelessWidget {
  final Post post;
  const SharedPostEmbed({super.key, required this.post});
  @override
  Widget build(BuildContext context) {
    final a = post.author;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => openPost(context, post.id),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (post.videoUrl != null)
            PostVideo(key: ValueKey('s${post.videoUrl}'), url: post.videoUrl, capcut: post.madeWith == 'capcut')
          else if (post.imageUrl != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: CachedNetworkImage(
                imageUrl: post.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                memCacheWidth: 1080,
                fadeInDuration: const Duration(milliseconds: 90),
                placeholder: (_, __) => Container(height: 220, color: Colors.black12),
                errorWidget: (_, __, ___) => const SizedBox(height: 60, child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(children: [
              Avatar(url: a?.avatarUrl, name: a?.displayName ?? '', size: 32),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  NameWithBadge(a?.displayName ?? '', verified: a?.verified ?? false, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(Fmt.chatListTime(post.createdAt), style: const TextStyle(fontSize: 11.5)),
                ]),
              ),
            ]),
          ),
          if (post.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: RichPostText(text: post.content, spanBuilder: PostCard._mentions, style: const TextStyle(fontSize: 14.5, height: 1.5)),
            )
          else
            const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

/// مشاركة منشور على صفحتي مع كلام فوقه (مثل فيسبوك)
Future<void> showSharePost(BuildContext context, Post post, {PostsController? controller}) async {
  final text = TextEditingController();
  final me = context.read<SessionProvider>().profile;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(c).bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(url: me?.avatarUrl, name: me?.displayName ?? '', size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(me?.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                const Text('مشاركة على صفحتك · عام 🌐', style: TextStyle(fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: text,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            maxLength: 2000,
            decoration: const InputDecoration(hintText: 'قل شيئًا عن هذا...', border: InputBorder.none, filled: false),
          ),
          SharedPostEmbed(post: post),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('شارك الآن')),
        ]),
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await PostRepository().share(post.id, text.text);
    controller?.replace(post.copyWith(shareCount: post.shareCount + 1));
    controller?.refresh();
    if (context.mounted) showSnack(context, 'تمت مشاركة المنشور على صفحتك ✅');
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e), error: true);
  }
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
  final XFile? sharedVideo; // فيديو مشارك من CapCut أو أي تطبيق
  final bool sharedCapCut;
  const ComposePostScreen({super.key, this.editing, this.sharedVideo, this.sharedCapCut = false});
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
  late XFile? _newVideo = widget.sharedVideo;
  late String? _videoUrl = widget.editing?.videoUrl;
  late bool _capcut = widget.sharedCapCut || widget.editing?.madeWith == 'capcut';

  bool get _hasVideo => _newVideo != null || _videoUrl != null;
  bool get _hasImage => _newImage != null || _imageUrl != null || _hasVideo;

  Future<void> _pickVideo() async {
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    XFile f;
    try {
      f = await VideoShrink.fit(context, x);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
      return;
    }
    if (mounted) {
      setState(() {
        _newVideo = f;
        _newImage = null;
        _imageUrl = null;
        _bgColor = null;
        // CapCut يسمّي ملفاته باسمه غالبًا
        if (x.name.toLowerCase().contains('capcut')) _capcut = true;
      });
    }
  }

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
        _newVideo = null;
        _videoUrl = null;
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
      // فيديو مشارك من CapCut أو غيره وحجمه كبير: ينضغط تلقائيًا
      if (_newVideo != null) _newVideo = await VideoShrink.fit(context, _newVideo!);
      await PostRepository().save(
        id: widget.editing?.id,
        content: _text.text,
        newImage: _hasVideo ? null : _newImage,
        keepImageUrl: _hasVideo || _newImage != null ? null : _imageUrl,
        newVideo: _newVideo,
        keepVideoUrl: _newVideo == null ? _videoUrl : null,
        capcut: _hasVideo && _capcut,
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
                  child: _hasVideo
                      ? PostVideo(
                          key: ValueKey(_newVideo?.path ?? _videoUrl),
                          file: _newVideo,
                          url: _newVideo == null ? _videoUrl : null,
                          capcut: _capcut)
                      : _newImage != null
                          ? Image.memory(_newImage!)
                          : CachedNetworkImage(imageUrl: _imageUrl!),
                ),
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: IconButton.filled(
                    tooltip: 'إزالة',
                    onPressed: () => setState(() {
                      _newImage = null;
                      _imageUrl = null;
                      _newVideo = null;
                      _videoUrl = null;
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
                label: Text(_hasImage && !_hasVideo ? 'تبديل الصورة' : 'إضافة صورة'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickVideo,
                icon: const Icon(Icons.videocam_rounded),
                label: Text(_hasVideo ? 'تبديل الفيديو' : 'إضافة فيديو'),
              ),
              if (_hasImage && !_hasVideo)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _editImage,
                  icon: const Icon(Icons.crop_rotate_rounded),
                  label: const Text('قص وتعديل'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(children: [
                  Icon(Icons.movie_filter_rounded),
                  SizedBox(width: 8),
                  Text('صمّم فيديو بقوالب CapCut', style: TextStyle(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 4),
                const Text('اختار قالب من CapCut وصمّم مقطعك، وبعدها اضغط «مشاركة» واختار VYFRI، أو احفظه وارجع ضيفه من هنا.',
                    style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => openCapCutTemplates(context),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('فتح قوالب CapCut'),
                ),
                if (_hasVideo)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('هذا المقطع مصمم بـ CapCut'),
                    subtitle: const Text('تطلع شارة «مصمم بـ CapCut» على المنشور', style: TextStyle(fontSize: 12)),
                    value: _capcut,
                    onChanged: (v) => setState(() => _capcut = v),
                  ),
              ]),
            ),
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
    }).catchError((_) {}).whenComplete(() {
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
  PostComment? _replyTo; // التعليق اللي ديرد عليه
  final Set<String> _expanded = {}; // تعليقات مفتوحة ردودها
  final _focus = FocusNode();
  late final PostsController _ctrl = widget.controller ?? PostsController.local();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait([_repo.one(widget.postId), _repo.comments(widget.postId)]);
      final p = res[0] as Post?;
      final c = res[1] as List<PostComment>;
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
      final parent = _replyTo;
      await _repo.comment(widget.postId, t, parentId: parent?.parentId ?? parent?.id);
      _text.clear();
      if (parent != null) _expanded.add(parent.parentId ?? parent.id);
      if (mounted) setState(() => _replyTo = null);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _startReply(PostComment c) {
    setState(() => _replyTo = c);
    final u = c.author?.username;
    if (c.parentId != null && u != null && u.isNotEmpty && !_text.text.contains('@$u')) {
      _text.text = '@$u ${_text.text}';
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
    }
    _focus.requestFocus();
  }

  Future<void> _deleteComment(PostComment c) async {
    if (!await confirmDialog(context, 'حذف التعليق', 'حذف هذا التعليق؟', ok: 'حذف', danger: true)) return;
    try {
      await _repo.deleteComment(c.id);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _likeComment(PostComment c) async {
    final liked = !c.likedByMe;
    void put(PostComment x) {
      final i = _comments.indexWhere((e) => e.id == x.id);
      if (i >= 0 && mounted) setState(() => _comments[i] = x);
    }

    put(c.withLike(liked));
    try {
      await PostRepository().likeComment(c.id, liked);
    } catch (e) {
      put(c);
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Widget _commentTile(PostComment c, bool isAdmin, {required bool reply}) {
    final canDelete = c.authorId == myId || _post!.authorId == myId || isAdmin;
    return Padding(
      padding: EdgeInsets.fromLTRB(reply ? 0 : 12, 6, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(url: c.author?.avatarUrl, name: c.author?.displayName ?? '', size: reply ? 30 : 38),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: canDelete ? () => _deleteComment(c) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NameWithBadge(c.author?.displayName ?? '',
                            verified: c.author?.verified ?? false,
                            badgeSize: 13,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                        const SizedBox(height: 2),
                        RichPostText(
                          text: c.content,
                          trimChars: 260,
                          trimLines: 5,
                          spanBuilder: (t) => TextSpan(text: t),
                          style: const TextStyle(fontSize: 14.5),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(children: [
                  const SizedBox(width: 10),
                  Text(Fmt.chatListTime(c.createdAt), style: const TextStyle(fontSize: 11.5)),
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(40, 30)),
                    onPressed: () => _likeComment(c),
                    child: Text('أعجبني',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: c.likedByMe ? const Color(0xFF1877F2) : Theme.of(context).hintColor)),
                  ),
                  if (c.likeCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                      ),
                      child: Text('👍 ${c.likeCount}', style: const TextStyle(fontSize: 12)),
                    ),
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(40, 30)),
                    onPressed: () => _startReply(c),
                    child: const Text('رد', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  if (canDelete)
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, minimumSize: const Size(40, 30)),
                      onPressed: () => _deleteComment(c),
                      child: const Text('حذف', style: TextStyle(fontSize: 12)),
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
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
                            for (final c in _comments.where((x) => x.parentId == null)) ...[
                              _commentTile(c, isAdmin, reply: false),
                              Builder(builder: (_) {
                                final replies = _comments.where((x) => x.parentId == c.id).toList();
                                if (replies.isEmpty) return const SizedBox.shrink();
                                final open = _expanded.contains(c.id);
                                return Padding(
                                  padding: const EdgeInsetsDirectional.only(start: 56),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (open) for (final r in replies) _commentTile(r, isAdmin, reply: true),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                                        onPressed: () => setState(() => open ? _expanded.remove(c.id) : _expanded.add(c.id)),
                                        icon: Icon(open ? Icons.expand_less_rounded : Icons.subdirectory_arrow_left_rounded, size: 18),
                                        label: Text(open ? 'إخفاء الردود' : 'عرض ${replies.length} ${replies.length == 1 ? 'رد' : 'ردود'}',
                                            style: const TextStyle(fontWeight: FontWeight.w700)),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    if (_replyTo != null)
                      Container(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                        child: Row(children: [
                          const Icon(Icons.reply_rounded, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text('ترد على ${_replyTo!.author?.displayName ?? ''}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() => _replyTo = null),
                          ),
                        ]),
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
                                focusNode: _focus,
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 1000,
                                decoration: InputDecoration(
                                    hintText: _replyTo != null ? 'اكتب ردّك...' : 'اكتب تعليقًا...',
                                    counterText: '',
                                    isDense: true),
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
