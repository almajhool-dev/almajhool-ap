import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/sticker_service.dart';
import '../utils/helpers.dart';

/// صورة ملصق (متحركة) مع إيموجي احتياطي إذا ما حمّلت.
class StickerImage extends StatelessWidget {
  final String url;
  final String fallback;
  final double size;
  const StickerImage({super.key, required this.url, this.fallback = '🎨', this.size = 140});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (_, __) => Center(child: Text(fallback, style: TextStyle(fontSize: size * 0.5))),
          errorWidget: (_, __, ___) => Center(child: Text(fallback, style: TextStyle(fontSize: size * 0.5))),
        ),
      );
}

/// يفتح لوحة الملصقات. الموثّقين يختارون ملصق، وغيرهم تطلعلهم مزايا التوثيق.
Future<Sticker?> showStickerSheet(BuildContext context, {required bool verified}) {
  return showModalBottomSheet<Sticker>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => verified ? const _StickerPicker() : const VerifiedPerksSheet(),
  );
}

class VerifiedPerksSheet extends StatelessWidget {
  const VerifiedPerksSheet({super.key});

  @override
  Widget build(BuildContext context) {
    Widget perk(IconData i, Color c, String t, String s) => ListTile(
          leading: CircleAvatar(backgroundColor: c.withValues(alpha: 0.15), child: Icon(i, color: c)),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(s),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_rounded, color: Colors.blue, size: 48),
            const SizedBox(height: 6),
            const Text('مزايا الحسابات الموثّقة 💎', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            const Text('هاي الميزات تنفتح بس للحسابات اللي عليها علامة التوثيق', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            perk(Icons.emoji_emotions_rounded, Colors.orange, 'ملصقات متحركة', 'أكثر من 100 ملصق متحرك تدزه بالمحادثات'),
            perk(Icons.add_photo_alternate_rounded, Colors.purple, 'ملصقاتك الخاصة', 'سوّي ملصق من أي صورة أو GIF من معرضك'),
            perk(Icons.auto_awesome_rounded, Colors.amber, 'فقاعة رسائل ذهبية', 'رسائلك تطلع بلون مميز للكل'),
            perk(Icons.verified_rounded, Colors.blue, 'علامة التوثيق', 'تطلع يم اسمك بكل مكان'),
            const SizedBox(height: 6),
            const Text('تتوثّق تلقائيًا من توصل المستوى 50، أو يوثّقك مالك التطبيق.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

class _StickerPicker extends StatefulWidget {
  const _StickerPicker();
  @override
  State<_StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<_StickerPicker> {
  List<Sticker>? _mine;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  Future<void> _loadMine() async {
    try {
      final l = await StickerService.mine();
      if (mounted) setState(() => _mine = l);
    } catch (_) {
      if (mounted) setState(() => _mine = []);
    }
  }

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      final s = await StickerService.createFromGallery();
      if (s != null && mounted) setState(() => _mine = [s, ...?_mine]);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _delete(Sticker s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف الملصق؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true || s.id == null) return;
    try {
      await StickerService.remove(s.id!);
      if (mounted) setState(() => _mine?.removeWhere((x) => x.id == s.id));
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Widget _grid(List<Sticker> list, {bool mine = false}) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: list.length + (mine ? 1 : 0),
      itemBuilder: (_, i) {
        if (mine && i == 0) {
          return InkWell(
            onTap: _adding ? null : _add,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
              ),
              child: Center(
                child: _adding
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_photo_alternate_rounded),
                        SizedBox(height: 2),
                        Text('ملصق جديد', style: TextStyle(fontSize: 11)),
                      ]),
              ),
            ),
          );
        }
        final s = list[i - (mine ? 1 : 0)];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.pop(context, s),
          onLongPress: mine ? () => _delete(s) : null,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: StickerImage(url: s.url, fallback: s.emoji, size: 72),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final packs = StickerService.packs;
    return DefaultTabController(
      length: packs.length + 1,
      initialIndex: 1,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(icon: Icon(Icons.star_rounded), text: 'ملصقاتي'),
                for (final p in packs) Tab(text: '${p.icon} ${p.name}'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _mine == null
                      ? const Center(child: CircularProgressIndicator())
                      : Column(children: [
                          if (_mine!.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text('سوّي ملصقك من أي صورة أو GIF 👇 (اضغط مطولًا للحذف)',
                                  style: TextStyle(fontSize: 12.5)),
                            ),
                          Expanded(child: _grid(_mine!, mine: true)),
                        ]),
                  for (final p in packs) _grid(p.stickers),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
