import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../repositories/post_repository.dart';
import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../admin/admin_screen.dart';
import '../profile/profile_screens.dart';

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
          onRefresh: _ctrl.refresh,
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
                  if (a != null) LevelChip(a.level),
                ],
              ),
            ),
            subtitle: Text(Fmt.chatListTime(post.createdAt), style: const TextStyle(fontSize: 12)),
            trailing: (mine || isAdmin)
                ? IconButton(
                    icon: const Icon(Icons.more_horiz),
                    onPressed: () async {
                      if (!await confirmDialog(context, 'حذف المنشور', 'هل تريد حذف هذا المنشور؟', ok: 'حذف', danger: true)) {
                        return;
                      }
                      try {
                        await controller.repo.delete(post.id);
                        controller.remove(post.id);
                      } catch (e) {
                        if (context.mounted) showSnack(context, friendlyError(e), error: true);
                      }
                    },
                  )
                : null,
          ),
          if (post.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Text(post.content, style: const TextStyle(fontSize: 15.5, height: 1.5)),
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

class ComposePostScreen extends StatefulWidget {
  const ComposePostScreen({super.key});
  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  final _text = TextEditingController();
  File? _image;
  bool _busy = false;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600, maxHeight: 1600);
    if (x != null) setState(() => _image = File(x.path));
  }

  Future<void> _publish() async {
    if (_text.text.trim().isEmpty && _image == null) return;
    setState(() => _busy = true);
    try {
      await PostRepository().create(content: _text.text, image: _image);
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

  @override
  Widget build(BuildContext context) {
    final me = context.watch<SessionProvider>().profile;
    return Scaffold(
      appBar: AppBar(
        title: const Text('منشور جديد'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              onPressed: _busy ? null : _publish,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('نشر'),
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
            NameWithBadge(me?.displayName ?? '', verified: me?.verified ?? false,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            maxLines: null,
            minLines: 5,
            maxLength: 3000,
            decoration: const InputDecoration(hintText: 'اكتب شيئًا...', border: InputBorder.none, filled: false),
          ),
          if (_image != null)
            Stack(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.file(_image!)),
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: IconButton.filled(onPressed: () => setState(() => _image = null), icon: const Icon(Icons.close)),
                ),
              ],
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.photo_library_rounded), label: const Text('إضافة صورة')),
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
