import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../repositories/post_repository.dart';
import '../utils/helpers.dart';
import 'common.dart';

/// التفاعلات مثل فيسبوك
class Reaction {
  final String id;
  final String emoji;
  final String label;
  final Color color;
  const Reaction(this.id, this.emoji, this.label, this.color);
}

const kReactions = [
  Reaction('like', '👍', 'أعجبني', Color(0xFF1877F2)),
  Reaction('love', '❤️', 'أحببته', Color(0xFFF33E58)),
  Reaction('care', '🥰', 'أدعمك', Color(0xFFF7B125)),
  Reaction('haha', '😂', 'أضحكني', Color(0xFFF7B125)),
  Reaction('wow', '😮', 'أدهشني', Color(0xFFF7B125)),
  Reaction('sad', '😢', 'أحزنني', Color(0xFFF7B125)),
  Reaction('angry', '😡', 'أغضبني', Color(0xFFE9710F)),
];

Reaction reactionOf(String? id) => kReactions.firstWhere((r) => r.id == id, orElse: () => kReactions.first);

/// زر «أعجبني»: ضغطة = إعجاب، ضغطة مطوّلة أو نقرتين = قائمة التفاعلات
class ReactionButton extends StatefulWidget {
  final String? current;
  final ValueChanged<String?> onChanged;
  const ReactionButton({super.key, required this.current, required this.onChanged});
  @override
  State<ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<ReactionButton> {
  DateTime? _lastTap;
  String? _beforeTap;
  final _key = GlobalKey();

  void _tap() {
    final now = DateTime.now();
    if (_lastTap != null && now.difference(_lastTap!) < const Duration(milliseconds: 320)) {
      // نقرتين: نرجّع الضغطة الأولى ونفتح التفاعلات
      _lastTap = null;
      widget.onChanged(_beforeTap);
      _openPicker();
      return;
    }
    _lastTap = now;
    _beforeTap = widget.current;
    HapticFeedback.selectionClick();
    widget.onChanged(widget.current == null ? 'like' : null);
  }

  void _openPicker() {
    HapticFeedback.mediumImpact();
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    showReactionPicker(context, anchor: pos, onPick: (r) => widget.onChanged(r));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.current == null ? null : reactionOf(widget.current);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: _key,
      borderRadius: BorderRadius.circular(10),
      onTap: _tap,
      onLongPress: _openPicker,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.elasticOut), child: c),
            child: r == null
                ? Icon(Icons.thumb_up_alt_outlined, key: const ValueKey('none'), size: 21, color: scheme.onSurface.withValues(alpha: 0.75))
                : (r.id == 'like'
                    ? Icon(Icons.thumb_up_alt_rounded, key: const ValueKey('like'), size: 21, color: r.color)
                    : Text(r.emoji, key: ValueKey(r.id), style: const TextStyle(fontSize: 19))),
          ),
          const SizedBox(width: 6),
          Text(r?.label ?? 'أعجبني',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: r?.color ?? scheme.onSurface.withValues(alpha: 0.75))),
        ]),
      ),
    );
  }
}

/// قائمة الإيموجيات اللي تطلع فوق الزر (بحركة نط)
void showReactionPicker(BuildContext context, {required Offset anchor, required ValueChanged<String> onPick}) {
  final overlay = Overlay.of(context);
  late OverlayEntry e;
  void close() => e.remove();
  final screenW = MediaQuery.sizeOf(context).width;
  const w = 7 * 46.0 + 16;
  final left = (anchor.dx - 8).clamp(8.0, screenW - w - 8);
  final top = (anchor.dy - 66).clamp(40.0, double.infinity);
  e = OverlayEntry(
    builder: (_) => Stack(children: [
      Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: close)),
      Positioned(
        left: left,
        top: top,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (_, v, child) => Transform.scale(scale: 0.6 + 0.4 * v, alignment: Alignment.bottomLeft,
                child: Opacity(opacity: v.clamp(0, 1), child: child)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF242526) : Colors.white,
                borderRadius: BorderRadius.circular(40),
                boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 4))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < kReactions.length; i++)
                  _PickerEmoji(r: kReactions[i], index: i, onTap: () {
                    HapticFeedback.lightImpact();
                    close();
                    onPick(kReactions[i].id);
                  }),
              ]),
            ),
          ),
        ),
      ),
    ]),
  );
  overlay.insert(e);
}

class _PickerEmoji extends StatefulWidget {
  final Reaction r;
  final int index;
  final VoidCallback onTap;
  const _PickerEmoji({required this.r, required this.index, required this.onTap});
  @override
  State<_PickerEmoji> createState() => _PickerEmojiState();
}

class _PickerEmojiState extends State<_PickerEmoji> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  bool _down = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 35 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.r.label,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final v = Curves.elasticOut.transform(_c.value);
            return Transform.translate(
              offset: Offset(0, (1 - v) * 18 - (_down ? 10 : 0)),
              child: Transform.scale(scale: (_down ? 1.45 : 1.0) * (0.3 + 0.7 * v), child: child),
            );
          },
          child: SizedBox(
            width: 46,
            height: 46,
            child: Center(child: Text(widget.r.emoji, style: const TextStyle(fontSize: 30))),
          ),
        ),
      ),
    );
  }
}

/// ملخص التفاعلات: أيقونات أكثر 3 أنواع + العدد (تضغطه تشوف منو تفاعل)
class ReactionSummary extends StatelessWidget {
  final Post post;
  const ReactionSummary({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    if (post.likeCount <= 0) return const SizedBox.shrink();
    final top = post.topReactions.isEmpty ? ['like'] : post.topReactions;
    final bg = Theme.of(context).cardColor;
    return InkWell(
      onTap: () => showReactors(context, post),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 18.0 + (top.length - 1) * 14,
            height: 20,
            child: Stack(children: [
              for (var i = 0; i < top.length; i++)
                PositionedDirectional(
                  start: i * 14.0,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: bg, border: Border.all(color: bg, width: 1.5)),
                    child: Text(reactionOf(top[i]).emoji, style: const TextStyle(fontSize: 13)),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 6),
          Text(_fmt(post.likeCount), style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
        ]),
      ),
    );
  }
}

String _fmt(int n) => n >= 1000000
    ? '${(n / 1000000).toStringAsFixed(1)} مليون'
    : n >= 1000
        ? '${(n / 1000).toStringAsFixed(1)} ألف'
        : '$n';

/// منو تفاعل: تبويب للكل وتبويب لكل نوع
Future<void> showReactors(BuildContext context, Post post) {
  final types = kReactions.where((r) => (post.reactions[r.id] ?? 0) > 0).toList();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SizedBox(
      height: MediaQuery.sizeOf(c).height * 0.7,
      child: DefaultTabController(
        length: types.length + 1,
        child: Column(children: [
          TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'الكل ${_fmt(post.likeCount)}'),
            for (final r in types) Tab(text: '${r.emoji} ${_fmt(post.reactions[r.id] ?? 0)}'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _ReactorsList(postId: post.id),
              for (final r in types) _ReactorsList(postId: post.id, reaction: r.id),
            ]),
          ),
        ]),
      ),
    ),
  );
}

class _ReactorsList extends StatefulWidget {
  final String postId;
  final String? reaction;
  const _ReactorsList({required this.postId, this.reaction});
  @override
  State<_ReactorsList> createState() => _ReactorsListState();
}

class _ReactorsListState extends State<_ReactorsList> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _items;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    PostRepository().reactors(widget.postId, reaction: widget.reaction).then((v) {
      if (mounted) setState(() => _items = v);
    }).catchError((e) {
      if (mounted) {
        setState(() => _items = []);
        showSnack(context, friendlyError(e), error: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) return const Center(child: Text('ماكو تفاعلات'));
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (_, i) {
        final u = (items[i]['user'] as Map).cast<String, dynamic>();
        final r = reactionOf(items[i]['reaction'] as String?);
        return ListTile(
          leading: Stack(clipBehavior: Clip.none, children: [
            Avatar(url: u['avatar_url'] as String?, name: (u['display_name'] ?? '') as String, size: 44),
            Positioned(right: -4, bottom: -4, child: Text(r.emoji, style: const TextStyle(fontSize: 18))),
          ]),
          title: NameWithBadge((u['display_name'] ?? '') as String, verified: u['is_verified'] == true),
          subtitle: Text('@${u['username'] ?? ''}'),
        );
      },
    );
  }
}
