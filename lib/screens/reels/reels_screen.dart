import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/models.dart';
import '../../repositories/post_repository.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../../widgets/reactions.dart';
import '../../services/video_cache.dart';
import '../feed/feed_screens.dart';
import '../profile/profile_screens.dart';

/// الريلز: فيديوهات قصيرة بالطول، تسحب لفوك للفيديو الجاي (مثل ريلز فيسبوك/تيك توك)
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key});
  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final _repo = PostRepository();
  final _ctrl = PostsController.local();
  final _page = PageController();
  bool _loading = true;
  bool _more = true;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _ctrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load({bool more = false}) async {
    try {
      final list = await _repo.reels(before: more && _ctrl.posts.isNotEmpty ? _ctrl.posts.last.createdAt : null);
      if (!mounted) return;
      setState(() {
        if (more) {
          _ctrl.posts.addAll(list.where((p) => !_ctrl.posts.any((x) => x.id == p.id)));
        } else {
          _ctrl.posts = list;
        }
        _more = list.length >= 10;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showSnack(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  void dispose() {
    _page.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posts = _ctrl.posts;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('ريلز', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        actions: [
          IconButton(
            tooltip: 'ريل جديد',
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 28),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ComposePostScreen()));
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : posts.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.video_library_rounded, color: Colors.white54, size: 64),
                    const SizedBox(height: 12),
                    const Text('ماكو ريلز بعد', style: TextStyle(color: Colors.white, fontSize: 18)),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const ComposePostScreen()));
                        _load();
                      },
                      icon: const Icon(Icons.videocam_rounded),
                      label: const Text('انشر أول ريل'),
                    ),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(),
                  child: PageView.builder(
                    controller: _page,
                    scrollDirection: Axis.vertical,
                    allowImplicitScrolling: true, // يجهز الريل الجاي من قبل حتى يشتغل فورًا
                    itemCount: posts.length,
                    onPageChanged: (i) {
                      setState(() => _current = i);
                      VideoCache.prefetch(posts.skip(i + 1).take(3).map((p) => p.videoUrl));
                      if (_more && i >= posts.length - 3) _load(more: true);
                    },
                    itemBuilder: (_, i) => _ReelPage(
                      key: ValueKey(posts[i].id),
                      post: posts[i],
                      active: i == _current,
                      controller: _ctrl,
                    ),
                  ),
                ),
    );
  }
}

class _ReelPage extends StatefulWidget {
  final Post post;
  final bool active;
  final PostsController controller;
  const _ReelPage({super.key, required this.post, required this.active, required this.controller});
  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _v;
  bool _ready = false;
  bool _paused = false;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = widget.post.videoUrl;
    if (url == null) return;
    final v = await VideoCache.controller(url);
    if (!mounted) {
      v.dispose();
      return;
    }
    _v = v;
    try {
      await v.initialize();
      await v.setLooping(true);
      if (!mounted) return;
      setState(() => _ready = true);
      if (widget.active) v.play();
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant _ReelPage old) {
    super.didUpdateWidget(old);
    if (_v == null || !_ready) return;
    if (widget.active && !_paused) {
      _v!.play();
    } else if (!widget.active) {
      _v!.pause();
    }
  }

  @override
  void dispose() {
    _v?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_v == null) return;
    setState(() {
      _paused = !_paused;
      _paused ? _v!.pause() : _v!.play();
    });
  }

  void _doubleTapLike() {
    final p = widget.controller.posts.firstWhere((x) => x.id == widget.post.id, orElse: () => widget.post);
    if (p.myReaction == null) widget.controller.react(p, 'love');
    setState(() => _showHeart = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.controller.posts.firstWhere((x) => x.id == widget.post.id, orElse: () => widget.post);
    final a = p.author;
    final v = _v;
    return Stack(fit: StackFit.expand, children: [
      GestureDetector(
        onTap: _togglePlay,
        onDoubleTap: _doubleTapLike,
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: _ready && v != null
              ? AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))
              : const CircularProgressIndicator(color: Colors.white),
        ),
      ),
      if (_paused)
        const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 90)),
      Center(
        child: AnimatedScale(
          scale: _showHeart ? 1.2 : 0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          child: const Text('❤️', style: TextStyle(fontSize: 96)),
        ),
      ),
      // تدرج خفيف حتى يبين الكلام
      const Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 260,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
          ),
        ),
      ),
      // الكاتب والكلام
      PositionedDirectional(
        start: 14,
        end: 80,
        bottom: 26,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: p.authorId))),
            child: Row(children: [
              Avatar(url: a?.avatarUrl, name: a?.displayName ?? '', size: 38),
              const SizedBox(width: 8),
              Flexible(
                child: NameWithBadge(a?.displayName ?? '',
                    verified: a?.verified ?? false,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ]),
          ),
          if (p.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(p.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 14.5, height: 1.4)),
          ],
        ]),
      ),
      // أزرار التفاعل
      PositionedDirectional(
        end: 10,
        bottom: 30,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _ReelAction(
            child: GestureDetector(
              onLongPress: () {
                final box = context.findRenderObject() as RenderBox?;
                final size = box?.size ?? Size.zero;
                showReactionPicker(context,
                    anchor: Offset(16, size.height - 260), onPick: (r) => widget.controller.react(p, r));
              },
              onTap: () => widget.controller.react(p, p.myReaction == null ? 'like' : null),
              child: p.myReaction == null
                  ? const Icon(Icons.thumb_up_alt_outlined, color: Colors.white, size: 32)
                  : Text(reactionOf(p.myReaction).emoji, style: const TextStyle(fontSize: 30)),
            ),
            label: '${p.likeCount}',
          ),
          _ReelAction(
            child: IconButton(
              icon: const Icon(Icons.mode_comment_rounded, color: Colors.white, size: 30),
              onPressed: () => openPost(context, p.id, controller: widget.controller),
            ),
            label: '${p.commentCount}',
          ),
          _ReelAction(
            child: IconButton(
              icon: Transform.flip(flipX: true, child: const Icon(Icons.reply_rounded, color: Colors.white, size: 32)),
              onPressed: () => showSharePost(context, p, controller: widget.controller),
            ),
            label: '${p.shareCount}',
          ),
        ]),
      ),
    ]);
  }
}

class _ReelAction extends StatelessWidget {
  final Widget child;
  final String label;
  const _ReelAction({required this.child, required this.label});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 46, child: Center(child: child)),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ]),
      );
}
