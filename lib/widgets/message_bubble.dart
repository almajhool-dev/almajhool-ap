import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/media_service.dart';
import '../utils/helpers.dart';
import 'common.dart';

enum ReceiptState { none, pending, failed, sent, delivered, read }

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool mine;
  final bool showSender;
  final String? senderName;
  final Message? repliedTo;
  final String? repliedSenderName;
  final ReceiptState receipt;
  final VoidCallback? onLongPress;
  final VoidCallback? onRetry;
  final VoidCallback? onSwipeReply;

  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.showSender = false,
    this.senderName,
    this.repliedTo,
    this.repliedSenderName,
    this.receipt = ReceiptState.none,
    this.onLongPress,
    this.onRetry,
    this.onSwipeReply,
  });

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(message.content ?? '', style: const TextStyle(fontSize: 12.5)),
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final bg = mine
        ? null
        : (isDark ? AppColors.darkCard : Colors.white);
    final fg = mine ? Colors.white : scheme.onSurface;
    final maxW = MediaQuery.sizeOf(context).width * 0.78;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      padding: EdgeInsets.all(message.type == 'image' && !message.deleted ? 4 : 10),
      decoration: BoxDecoration(
        color: bg,
        gradient: mine
            ? const LinearGradient(colors: [Color(0xFF6C3CF0), Color(0xFF0097B2)], begin: Alignment.topRight, end: Alignment.bottomLeft)
            : null,
        borderRadius: BorderRadiusDirectional.only(
          topStart: const Radius.circular(18),
          topEnd: const Radius.circular(18),
          bottomStart: Radius.circular(mine ? 18 : 4),
          bottomEnd: Radius.circular(mine ? 4 : 18),
        ),
        boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSender && senderName != null && !mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 4, right: 4),
              child: Text(senderName!,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: scheme.primary)),
            ),
          if (message.forwarded && !message.deleted)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.shortcut_rounded, size: 14, color: fg.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text('مُعاد توجيهها', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: fg.withValues(alpha: 0.7))),
              ]),
            ),
          if (message.replyTo != null && !message.deleted) _replyPreview(context, fg),
          _content(context, fg),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.pinned) Icon(Icons.push_pin, size: 12, color: fg.withValues(alpha: 0.7)),
              if (message.editedAt != null && !message.deleted)
                Text('معدّلة · ', style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.65))),
              Text(Fmt.time(message.createdAt), style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.65))),
              if (mine) ...[const SizedBox(width: 4), _receiptIcon()],
            ],
          ),
        ],
      ),
    );

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: message.deleted ? null : onLongPress,
        onTap: message.state == SendState.failed ? onRetry : null,
        onHorizontalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0).abs() > 300 && !message.deleted) onSwipeReply?.call();
        },
        child: bubble,
      ),
    );
  }

  Widget _receiptIcon() {
    switch (receipt) {
      case ReceiptState.pending:
        return const Icon(Icons.schedule, size: 14, color: Colors.white70);
      case ReceiptState.failed:
        return const Icon(Icons.error_outline, size: 15, color: Colors.orangeAccent);
      case ReceiptState.sent:
        return const Icon(Icons.done, size: 15, color: Colors.white70);
      case ReceiptState.delivered:
        return const Icon(Icons.done_all, size: 15, color: Colors.white70);
      case ReceiptState.read:
        return const Icon(Icons.done_all, size: 15, color: Color(0xFF7CF7FF));
      case ReceiptState.none:
        return const SizedBox.shrink();
    }
  }

  Widget _replyPreview(BuildContext context, Color fg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(color: AppColors.cyan, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(repliedSenderName ?? 'رد على رسالة',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg.withValues(alpha: 0.9))),
                Text(repliedTo?.previewText ?? 'رسالة سابقة',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, Color fg) {
    if (message.deleted) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.block, size: 15, color: fg.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text('تم حذف هذه الرسالة', style: TextStyle(fontStyle: FontStyle.italic, color: fg.withValues(alpha: 0.6))),
      ]);
    }
    switch (message.type) {
      case 'image':
        if (!message.hasMedia) return const SizedBox(width: 200, height: 150);
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ImageViewer(path: message.mediaPath!)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SignedImage(path: message.mediaPath!, width: 240, height: 240),
          ),
        );
      case 'audio':
        return message.hasMedia ? AudioBubble(path: message.mediaPath!, color: fg) : const SizedBox.shrink();
      case 'video':
      case 'file':
        final isVideo = message.type == 'video';
        return InkWell(
          onTap: message.hasMedia ? () => openMedia(context, message.mediaPath!) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(isVideo ? Icons.play_circle_fill_rounded : Icons.insert_drive_file_rounded, color: fg),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message.fileName ?? (isVideo ? 'فيديو' : 'ملف'),
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
                    Text('${Fmt.fileSize(message.fileSize)} · اضغط للفتح',
                        style: TextStyle(fontSize: 11.5, color: fg.withValues(alpha: 0.7))),
                  ],
                ),
              ),
            ],
          ),
        );
      default:
        return SelectableText.rich(
          _linkify(message.content ?? '', fg),
          style: TextStyle(color: fg, fontSize: 15.5, height: 1.35),
        );
    }
  }

  TextSpan _linkify(String text, Color fg) {
    final spans = <TextSpan>[];
    final re = RegExp(r'(@[A-Za-z0-9_.]{3,24})');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(0), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF7CF7FF))));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(children: spans);
  }
}

Future<void> openMedia(BuildContext context, String path) async {
  try {
    final url = await MediaService.signedUrl(path);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e), error: true);
  }
}

class ImageViewer extends StatelessWidget {
  final String path;
  const ImageViewer({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => openMedia(context, path)),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: SignedImage(path: path, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class AudioBubble extends StatefulWidget {
  final String path;
  final Color color;
  const AudioBubble({super.key, required this.path, required this.color});
  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  final List<StreamSubscription> _subs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) => mounted ? setState(() => _state = s) : null));
    _subs.add(_player.onPositionChanged.listen((p) => mounted ? setState(() => _pos = p) : null));
    _subs.add(_player.onDurationChanged.listen((d) => mounted ? setState(() => _dur = d) : null));
    _subs.add(_player.onPlayerComplete.listen((_) => mounted ? setState(() => _pos = Duration.zero) : null));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    if (_state == PlayerState.paused) {
      await _player.resume();
      return;
    }
    setState(() => _loading = true);
    try {
      final url = await MediaService.signedUrl(widget.path);
      await _player.play(UrlSource(url));
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _dur.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          IconButton(
            onPressed: _loading ? null : _toggle,
            icon: _loading
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: widget.color))
                : Icon(_state == PlayerState.playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                    color: widget.color, size: 34),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  color: widget.color,
                  backgroundColor: widget.color.withValues(alpha: 0.25),
                ),
                const SizedBox(height: 4),
                Text(Fmt.duration(_state == PlayerState.stopped ? _dur : _pos),
                    style: TextStyle(fontSize: 11, color: widget.color.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
