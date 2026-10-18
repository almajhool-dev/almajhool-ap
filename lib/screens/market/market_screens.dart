import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../services/core_services.dart';
import '../../utils/helpers.dart';
import '../../widgets/common.dart';
import '../contacts/contacts_tab.dart';
import '../profile/profile_screens.dart';

const kMarketCats = {
  'phones': ('📱', 'هواتف'),
  'electronics': ('💻', 'إلكترونيات'),
  'cars': ('🚗', 'سيارات'),
  'realestate': ('🏠', 'عقارات'),
  'fashion': ('👕', 'ملابس'),
  'home': ('🛋', 'أثاث وبيت'),
  'games': ('🎮', 'ألعاب'),
  'services': ('🛠', 'خدمات'),
  'other': ('📦', 'أخرى'),
};

String fmtPrice(num v) {
  if (v == 0) return 'مجانًا';
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b د.ع';
}

class MarketItem {
  final Map<String, dynamic> m;
  MarketItem(this.m);
  String get id => m['id'] as String;
  String get title => (m['title'] ?? '') as String;
  String get description => (m['description'] ?? '') as String;
  int get price => ((m['price'] ?? 0) as num).toInt();
  String get category => (m['category'] ?? 'other') as String;
  String get city => (m['city'] ?? '') as String;
  String get condition => (m['condition'] ?? 'used') as String;
  String get status => (m['status'] ?? 'active') as String;
  List<String> get images => [for (final e in (m['images'] as List? ?? const [])) '$e'];
  Map<String, dynamic> get seller => (m['seller'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get sellerId => (m['seller_id'] ?? seller['id']) as String;
  DateTime get createdAt => DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now();
}

/// سوق البيع والشراء (مثل Marketplace فيسبوك)
class MarketScreen extends StatefulWidget {
  final String? sellerId;
  const MarketScreen({super.key, this.sellerId});
  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  String? _cat;
  final _q = TextEditingController();
  List<MarketItem>? _items;

  bool get _mine => widget.sellerId != null && widget.sellerId == supa.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await supa.rpc('market_list', params: {
        'p_category': _cat,
        'p_q': _q.text.trim().isEmpty ? null : _q.text.trim(),
        'p_seller': widget.sellerId,
        'p_limit': 60,
      });
      if (mounted) setState(() => _items = [for (final e in r as List) MarketItem(Map<String, dynamic>.from(e as Map))]);
    } catch (e) {
      if (mounted) {
        setState(() => _items = []);
        showSnack(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _sell() async {
    final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const MarketEditScreen()));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sellerId == null ? 'السوق 🛍' : (_mine ? 'إعلاناتي' : 'إعلانات البائع')),
        actions: [
          if (widget.sellerId == null)
            IconButton(
              tooltip: 'إعلاناتي',
              icon: const Icon(Icons.person_pin_rounded),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => MarketScreen(sellerId: supa.auth.currentUser?.id))),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sell,
        icon: const Icon(Icons.sell_rounded),
        label: const Text('بيع شي'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          if (widget.sellerId == null) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                child: TextField(
                  controller: _q,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    hintText: 'دوّر بالسوق...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _load),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 46,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                        label: const Text('الكل'),
                        selected: _cat == null,
                        onSelected: (_) {
                          setState(() => _cat = null);
                          _load();
                        }),
                  ),
                  for (final e in kMarketCats.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        label: Text('${e.value.$1} ${e.value.$2}'),
                        selected: _cat == e.key,
                        onSelected: (_) {
                          setState(() => _cat = e.key);
                          _load();
                        },
                      ),
                    ),
                ]),
              ),
            ),
          ],
          if (items == null)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.storefront_rounded,
                title: _mine ? 'ما عندك إعلانات بعد' : 'ماكو إعلانات هنا',
                subtitle: 'اضغط «بيع شي» وانشر أول إعلان',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 90),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.72),
                itemCount: items.length,
                itemBuilder: (_, i) => _ItemTile(item: items[i], onChanged: _load),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ItemTile extends StatelessWidget {
  final MarketItem item;
  final VoidCallback onChanged;
  const _ItemTile({required this.item, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final changed = await Navigator.push<bool>(
            context, MaterialPageRoute(builder: (_) => MarketItemScreen(item: item)));
        if (changed == true) onChanged();
      },
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              if (item.images.isNotEmpty)
                CachedNetworkImage(imageUrl: item.images.first, fit: BoxFit.cover, memCacheWidth: 500)
              else
                const ColoredBox(color: Colors.black12, child: Icon(Icons.image_outlined)),
              if (item.status == 'sold')
                Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: const Text('تم البيع', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
            child: Text(fmtPrice(item.price), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: Text(item.city.isEmpty ? (kMarketCats[item.category]?.$2 ?? '') : item.city,
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          ),
        ]),
      ),
    );
  }
}

class MarketItemScreen extends StatefulWidget {
  final MarketItem item;
  const MarketItemScreen({super.key, required this.item});
  @override
  State<MarketItemScreen> createState() => _MarketItemScreenState();
}

class _MarketItemScreenState extends State<MarketItemScreen> {
  int _img = 0;

  Future<void> _status(String s) async {
    try {
      await supa.rpc('market_set_status', params: {'p_id': widget.item.id, 'p_status': s});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final mine = it.sellerId == supa.auth.currentUser?.id;
    final s = it.seller;
    return Scaffold(
      appBar: AppBar(title: Text(it.title, overflow: TextOverflow.ellipsis)),
      body: ListView(children: [
        AspectRatio(
          aspectRatio: 1,
          child: Stack(children: [
            PageView.builder(
              itemCount: it.images.length,
              onPageChanged: (i) => setState(() => _img = i),
              itemBuilder: (_, i) => CachedNetworkImage(imageUrl: it.images[i], fit: BoxFit.cover, width: double.infinity),
            ),
            if (it.images.length > 1)
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < it.images.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _img ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: i == _img ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(6)),
                    ),
                ]),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(it.title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(fmtPrice(it.price), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [
              Chip(label: Text('${kMarketCats[it.category]?.$1 ?? ''} ${kMarketCats[it.category]?.$2 ?? ''}')),
              Chip(label: Text(it.condition == 'new' ? 'جديد ✨' : 'مستعمل')),
              if (it.city.isNotEmpty) Chip(avatar: const Icon(Icons.place_outlined, size: 18), label: Text(it.city)),
              if (it.status == 'sold') const Chip(label: Text('تم البيع ✅')),
            ]),
            const SizedBox(height: 12),
            if (it.description.isNotEmpty) ...[
              const Text('الوصف', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              SelectableText(it.description, style: const TextStyle(height: 1.6)),
              const SizedBox(height: 14),
            ],
            const Text('البائع', style: TextStyle(fontWeight: FontWeight.w800)),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(url: s['avatar_url'] as String?, name: (s['display_name'] ?? '') as String, size: 44),
              title: NameWithBadge((s['display_name'] ?? '') as String, verified: s['is_verified'] == true),
              subtitle: Text('نُشر ${Fmt.chatListTime(it.createdAt)}'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: it.sellerId))),
            ),
            const SizedBox(height: 10),
            if (mine) ...[
              FilledButton.icon(
                onPressed: () async {
                  final ok = await Navigator.push<bool>(
                      context, MaterialPageRoute(builder: (_) => MarketEditScreen(editing: it)));
                  if (ok == true && context.mounted) Navigator.pop(context, true);
                },
                icon: const Icon(Icons.edit),
                label: const Text('تعديل الإعلان'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _status(it.status == 'sold' ? 'active' : 'sold'),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(it.status == 'sold' ? 'رجّعه متاح' : 'تم البيع'),
              ),
              TextButton.icon(
                onPressed: () async {
                  if (await confirmDialog(context, 'حذف الإعلان', 'تريد تحذف هذا الإعلان؟', ok: 'حذف', danger: true)) {
                    _status('removed');
                  }
                },
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: const Text('حذف الإعلان', style: TextStyle(color: Colors.redAccent)),
              ),
            ] else
              FilledButton.icon(
                onPressed: () => startDirectChat(context, it.sellerId),
                icon: const Icon(Icons.chat_rounded),
                label: const Text('راسل البائع'),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// إضافة/تعديل إعلان بيع
class MarketEditScreen extends StatefulWidget {
  final MarketItem? editing;
  const MarketEditScreen({super.key, this.editing});
  @override
  State<MarketEditScreen> createState() => _MarketEditScreenState();
}

class _MarketEditScreenState extends State<MarketEditScreen> {
  late final _title = TextEditingController(text: widget.editing?.title ?? '');
  late final _price = TextEditingController(text: widget.editing == null ? '' : '${widget.editing!.price}');
  late final _city = TextEditingController(text: widget.editing?.city ?? '');
  late final _desc = TextEditingController(text: widget.editing?.description ?? '');
  late String _cat = widget.editing?.category ?? 'other';
  late String _cond = widget.editing?.condition ?? 'used';
  late final List<String> _urls = [...?widget.editing?.images];
  final List<XFile> _new = [];
  bool _busy = false;

  Future<void> _pick() async {
    final left = 8 - _urls.length - _new.length;
    if (left <= 0) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 82, maxWidth: 1600, limit: left);
    if (picked.isNotEmpty) setState(() => _new.addAll(picked.take(left)));
  }

  Future<void> _save() async {
    final price = int.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? -1;
    if (_title.text.trim().length < 3) return showSnack(context, 'اكتب اسم الغرض', error: true);
    if (price < 0) return showSnack(context, 'اكتب السعر بالأرقام', error: true);
    if (_urls.isEmpty && _new.isEmpty) return showSnack(context, 'ضيف صورة وحدة على الأقل', error: true);
    setState(() => _busy = true);
    try {
      final urls = [..._urls];
      for (final f in _new) {
        final path = '${supa.auth.currentUser!.id}/market_${const Uuid().v4()}.jpg';
        await supa.storage.from('posts').uploadBinary(path, await f.readAsBytes(),
            fileOptions: const FileOptions(contentType: 'image/jpeg'));
        urls.add(supa.storage.from('posts').getPublicUrl(path));
      }
      await supa.rpc('market_save', params: {
        'p_id': widget.editing?.id,
        'p_title': _title.text.trim(),
        'p_description': _desc.text.trim(),
        'p_price': price,
        'p_category': _cat,
        'p_city': _city.text.trim(),
        'p_condition': _cond,
        'p_images': urls,
      });
      if (mounted) {
        showSnack(context, widget.editing == null ? 'انتشر إعلانك بالسوق 🎉' : 'انحفظ التعديل ✅');
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.editing == null ? 'بيع شي' : 'تعديل الإعلان')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SizedBox(
          height: 104,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            InkWell(
              onTap: _pick,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 96,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).colorScheme.primary, width: 1.5)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_a_photo_rounded),
                  const SizedBox(height: 4),
                  Text('${_urls.length + _new.length}/8', style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),
            for (final u in _urls)
              _Thumb(child: CachedNetworkImage(imageUrl: u, fit: BoxFit.cover), onRemove: () => setState(() => _urls.remove(u))),
            for (final f in _new)
              _Thumb(
                  child: FutureBuilder(
                    future: f.readAsBytes(),
                    builder: (_, s) => s.hasData ? Image.memory(s.data!, fit: BoxFit.cover) : const SizedBox(),
                  ),
                  onRemove: () => setState(() => _new.remove(f))),
          ]),
        ),
        const SizedBox(height: 14),
        TextField(controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'شنو تبيع؟ (اسم الغرض)')),
        TextField(
          controller: _price,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'السعر (دينار عراقي)', hintText: 'مثلاً 250000 — اكتب 0 إذا مجاني'),
        ),
        const SizedBox(height: 12),
        const Text('القسم', style: TextStyle(fontWeight: FontWeight.w700)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in kMarketCats.entries)
            ChoiceChip(label: Text('${e.value.$1} ${e.value.$2}'), selected: _cat == e.key, onSelected: (_) => setState(() => _cat = e.key)),
        ]),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'new', label: Text('جديد')),
            ButtonSegment(value: 'used', label: Text('مستعمل')),
          ],
          selected: {_cond},
          onSelectionChanged: (s) => setState(() => _cond = s.first),
        ),
        const SizedBox(height: 12),
        TextField(controller: _city, maxLength: 60, decoration: const InputDecoration(labelText: 'المدينة', hintText: 'مثلاً بغداد')),
        TextField(
          controller: _desc,
          minLines: 3,
          maxLines: 8,
          maxLength: 3000,
          decoration: const InputDecoration(labelText: 'الوصف', hintText: 'الحالة، المواصفات، طريقة الاستلام...'),
        ),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.editing == null ? 'انشر الإعلان' : 'احفظ التعديل'),
        ),
      ]),
    );
  }
}

class _Thumb extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;
  const _Thumb({required this.child, required this.onRemove});
  @override
  Widget build(BuildContext context) => Container(
        width: 96,
        margin: const EdgeInsetsDirectional.only(end: 8),
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: child),
          PositionedDirectional(
            top: 2,
            end: 2,
            child: InkWell(
              onTap: onRemove,
              child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 16, color: Colors.white)),
            ),
          ),
        ]),
      );
}
