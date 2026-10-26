import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../utils/helpers.dart';

/// مكان ينرسل بالمحادثة: الإحداثيات (بحقل file_name «lat,lng») + اسم المكان (بالنص «📍 الاسم»)
class SharedPlace {
  final double lat, lng;
  final String label;
  const SharedPlace(this.lat, this.lng, this.label);

  LatLng get point => LatLng(lat, lng);
  String get coords => '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
  String get mapsUrl => 'https://www.google.com/maps/search/?api=1&query=$coords';
  String get directionsUrl => 'https://www.google.com/maps/dir/?api=1&destination=$coords';

  static SharedPlace? fromMessage(Message m) {
    final f = (m.fileName ?? '').split(',');
    if (f.length != 2) return null;
    final lat = double.tryParse(f[0].trim()), lng = double.tryParse(f[1].trim());
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return null;
    final label = (m.content ?? '').replaceFirst(RegExp(r'^\s*📍\s*'), '').trim();
    return SharedPlace(lat, lng, label.isEmpty ? 'موقع' : label);
  }
}

/// الموقع: الصلاحية، المكان الحالي، اسم المكان والبحث (OpenStreetMap مجاني بدون مفتاح)، وفتح الخرائط
class Geo {
  Geo._();
  static const tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const ua = 'com.almajhool.almajhool_app';
  static const _headers = {'User-Agent': 'VYFRI/1.0 (Android app; https://t.me/ikd5n)'};
  static const baghdad = LatLng(33.3152, 44.3661);

  static Future<bool> granted() async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// مكان الهاتف الحالي. إذا [ask] يطلب الصلاحية ويدل المستخدم للإعدادات إذا لازم.
  static Future<Position?> current(BuildContext context, {bool ask = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (ask && context.mounted) {
          final go = await confirmDialog(context, 'الموقع طافي', 'شغّل الموقع (GPS) بالهاتف حتى نحدد مكانك.', ok: 'افتح الإعدادات');
          if (go) await Geolocator.openLocationSettings();
        }
        return null;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && ask) p = await Geolocator.requestPermission();
      if (p == LocationPermission.deniedForever) {
        if (ask && context.mounted) {
          final go = await confirmDialog(context, 'صلاحية الموقع', 'اسمح للتطبيق يوصل للموقع من الإعدادات حتى تكدر تدز موقعك.',
              ok: 'افتح الإعدادات');
          if (go) await Geolocator.openAppSettings();
        }
        return null;
      }
      if (p != LocationPermission.always && p != LocationPermission.whileInUse) return null;
      try {
        return await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      } catch (_) {
        return await Geolocator.getLastKnownPosition();
      }
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  /// اسم المكان من الإحداثيات (مثلاً: «شارع أبو نؤاس، الكرادة، بغداد»)
  static Future<String?> placeName(LatLng p) async {
    try {
      final r = await http
          .get(
              Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=17&accept-language=ar'
                  '&lat=${p.latitude.toStringAsFixed(6)}&lon=${p.longitude.toStringAsFixed(6)}'),
              headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>();
      final a = ((j['address'] as Map?) ?? const {}).cast<String, dynamic>();
      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = a[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final name = (j['name'] is String) ? (j['name'] as String).trim() : '';
      final parts = <String>{
        if (name.isNotEmpty) name,
        for (final keys in const [
          ['road', 'pedestrian', 'footway'],
          ['neighbourhood', 'suburb', 'quarter', 'city_district'],
          ['city', 'town', 'village', 'county', 'state'],
        ])
          if (pick(keys) case final v?) v,
      }.take(3).toList();
      if (parts.isNotEmpty) return parts.join('، ');
      final d = j['display_name'];
      return d is String && d.isNotEmpty ? d.split(',').take(3).map((e) => e.trim()).join('، ') : null;
    } catch (_) {
      return null;
    }
  }

  /// البحث عن مكان بالاسم
  static Future<List<(String, LatLng)>> search(String q, {LatLng? near}) async {
    final r = await http
        .get(
            Uri.parse('https://nominatim.openstreetmap.org/search?format=jsonv2&limit=8&accept-language=ar'
                '&q=${Uri.encodeQueryComponent(q)}'
                '${near == null ? '' : '&viewbox=${near.longitude - 1},${near.latitude + 1},${near.longitude + 1},${near.latitude - 1}'}'),
            headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('البحث ما اشتغل، جرّب بعد شوية');
    final out = <(String, LatLng)>[];
    for (final e in (jsonDecode(utf8.decode(r.bodyBytes)) as List)) {
      final m = (e as Map).cast<String, dynamic>();
      final lat = double.tryParse('${m['lat']}'), lng = double.tryParse('${m['lon']}');
      if (lat == null || lng == null) continue;
      out.add(('${m['display_name'] ?? ''}', LatLng(lat, lng)));
    }
    return out;
  }

  /// يفتح المكان بتطبيق الخرائط (أو الطريق إليه)
  static Future<void> open(BuildContext context, SharedPlace p, {bool directions = false}) async {
    final urls = directions
        ? [p.directionsUrl]
        : ['geo:${p.coords}?q=${p.coords}(${Uri.encodeComponent(p.label)})', p.mapsUrl];
    for (final u in urls) {
      try {
        if (await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication)) return;
      } catch (_) {}
    }
    if (context.mounted) showSnack(context, 'ما لگينا تطبيق خرائط بالهاتف', error: true);
  }

  static String distance(double meters) =>
      meters < 1000 ? '${meters.round()} متر' : '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)} كم';
}

Widget _pin({double size = 46}) => Icon(Icons.location_on_rounded,
    size: size, color: Colors.red, shadows: const [Shadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))]);

/// اختيار الموقع: موقعي الحالي، أو أي مكان بالخريطة (تحرّك الخريطة والدبوس بالنص)، أو بحث بالاسم
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});
  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  final _q = TextEditingController();
  Position? _me;
  LatLng _center = Geo.baghdad;
  String? _label;
  bool _locating = false, _searching = false, _naming = false, _sending = false;
  List<(String, LatLng)> _results = const [];
  Timer? _nameTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void dispose() {
    _nameTimer?.cancel();
    _q.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final p = await Geo.current(context);
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (p != null) _me = p;
    });
    if (p != null) {
      final pt = LatLng(p.latitude, p.longitude);
      _map.move(pt, 17);
      _onMoved(pt);
    }
  }

  void _onMoved(LatLng c) {
    _center = c;
    _nameTimer?.cancel();
    if (!_naming || _label != null) {
      setState(() {
        _label = null;
        _naming = true;
      });
    }
    _nameTimer = Timer(const Duration(milliseconds: 1100), () async {
      final n = await Geo.placeName(c);
      if (!mounted || _center != c) return;
      setState(() {
        _label = n;
        _naming = false;
      });
    });
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.length < 2) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final r = await Geo.search(q, near: _me == null ? null : LatLng(_me!.latitude, _me!.longitude));
      if (!mounted) return;
      setState(() => _results = r);
      if (r.isEmpty) showSnack(context, 'ما لگينا مكان بهذا الاسم');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _send(LatLng p, String? label) {
    final l = (label ?? '').trim();
    Navigator.pop(context, SharedPlace(p.latitude, p.longitude, l.isEmpty ? 'موقع' : (l.length > 110 ? l.substring(0, 110) : l)));
  }

  Future<void> _sendMine() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      var p = _me;
      if (p == null) {
        await _locate();
        p = _me;
      }
      if (p == null || !mounted) return;
      final pt = LatLng(p.latitude, p.longitude);
      final n = await Geo.placeName(pt);
      if (!mounted) return;
      _send(pt, n == null ? 'موقعي الحالي' : 'موقعي الحالي: $n');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('مشاركة الموقع 📍')),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: Geo.baghdad,
            initialZoom: 12,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onPositionChanged: (cam, gesture) {
              if (gesture) _onMoved(cam.center);
            },
          ),
          children: [
            TileLayer(urlTemplate: Geo.tiles, userAgentPackageName: Geo.ua),
            if (_me != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: LatLng(_me!.latitude, _me!.longitude),
                  radius: 8,
                  color: Colors.blue,
                  borderColor: Colors.white,
                  borderStrokeWidth: 3,
                ),
              ]),
            const SimpleAttributionWidget(source: Text('OpenStreetMap')),
          ],
        ),
        // الدبوس بنص الخريطة: رأسه على المكان المحدد
        IgnorePointer(child: Center(child: Padding(padding: const EdgeInsets.only(bottom: 46), child: _pin()))),
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Column(children: [
            Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              color: scheme.surface,
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'دوّر على مكان (مثلاً: المنصور، بغداد)',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                      : (_results.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _results = const []))
                          : null),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_results.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 6),
                constraints: const BoxConstraints(maxHeight: 260),
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(14),
                  color: scheme.surface,
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final (name, pt) = _results[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.place_outlined),
                        title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () {
                          setState(() => _results = const []);
                          _map.move(pt, 17);
                          _onMoved(pt);
                        },
                      );
                    },
                  ),
                ),
              ),
          ]),
        ),
        PositionedDirectional(
          end: 14,
          bottom: 200,
          child: FloatingActionButton.small(
            heroTag: 'loc_me',
            onPressed: _locating ? null : _locate,
            child: _locating
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.withValues(alpha: 0.15),
                      child: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location_rounded, color: Colors.blue),
                    ),
                    title: const Text('إرسال موقعي الحالي', style: TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(_me == null
                        ? (_locating ? 'دا نحدد مكانك...' : 'نحدد مكانك بالـ GPS')
                        : 'دقة تقريبًا ${_me!.accuracy.round()} متر'),
                    onTap: _sendMine,
                  ),
                  const Divider(height: 10),
                  Row(children: [
                    _pin(size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _naming ? 'دا نجيب اسم المكان...' : (_label ?? 'حرّك الخريطة وخلي الدبوس على المكان اللي تريده'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _send(_center, _label),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('إرسال المكان المحدد'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// عرض موقع وصلك: الخريطة، المسافة عنك، والطريق إليه
class LocationViewScreen extends StatefulWidget {
  final SharedPlace place;
  const LocationViewScreen({super.key, required this.place});
  @override
  State<LocationViewScreen> createState() => _LocationViewScreenState();
}

class _LocationViewScreenState extends State<LocationViewScreen> {
  final _map = MapController();
  Position? _me;

  @override
  void initState() {
    super.initState();
    _whereAmI(ask: false);
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _whereAmI({bool ask = true}) async {
    if (!ask && !await Geo.granted()) return;
    if (!mounted) return;
    final p = await Geo.current(context, ask: ask);
    if (!mounted || p == null) return;
    setState(() => _me = p);
    if (ask) {
      _map.fitCamera(CameraFit.coordinates(
        coordinates: [widget.place.point, LatLng(p.latitude, p.longitude)],
        padding: const EdgeInsets.fromLTRB(60, 80, 60, 260),
        maxZoom: 17,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.place;
    final me = _me;
    final dist = me == null ? null : Geolocator.distanceBetween(me.latitude, me.longitude, p.lat, p.lng);
    return Scaffold(
      appBar: AppBar(title: Text(p.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: p.point,
            initialZoom: 16,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            TileLayer(urlTemplate: Geo.tiles, userAgentPackageName: Geo.ua),
            if (me != null)
              CircleLayer(circles: [
                CircleMarker(
                  point: LatLng(me.latitude, me.longitude),
                  radius: 8,
                  color: Colors.blue,
                  borderColor: Colors.white,
                  borderStrokeWidth: 3,
                ),
              ]),
            MarkerLayer(markers: [
              Marker(point: p.point, width: 52, height: 52, alignment: Alignment.topCenter, child: _pin(size: 52)),
            ]),
            const SimpleAttributionWidget(source: Text('OpenStreetMap')),
          ],
        ),
        PositionedDirectional(
          end: 14,
          bottom: 210,
          child: FloatingActionButton.small(
            heroTag: 'loc_view_me',
            tooltip: 'وين آني؟',
            onPressed: () => _whereAmI(),
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('📍 ${p.label}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    dist == null ? p.coords : '${p.coords} · يبعد عنك ${Geo.distance(dist)}',
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Geo.open(context, p, directions: true),
                    icon: const Icon(Icons.directions_rounded),
                    label: const Text('الطريق للمكان 🧭'),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Geo.open(context, p),
                        icon: const Icon(Icons.map_rounded),
                        label: const Text('فتح بالخرائط'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'نسخ الرابط',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: p.mapsUrl));
                        showSnack(context, 'تم نسخ رابط الموقع');
                      },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// فقاعة الموقع بالمحادثة: خريطة صغيرة + اسم المكان، والضغط يفتح الخريطة والطريق
class LocationBubble extends StatelessWidget {
  final Message message;
  final Color color;
  const LocationBubble({super.key, required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    final p = SharedPlace.fromMessage(message);
    if (p == null) return Text(message.content ?? '📍 موقع', style: TextStyle(color: color, fontSize: 15));
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LocationViewScreen(place: p))),
      child: SizedBox(
        width: 240,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 140,
              child: IgnorePointer(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: p.point,
                    initialZoom: 15,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                  ),
                  children: [
                    TileLayer(urlTemplate: Geo.tiles, userAgentPackageName: Geo.ua),
                    MarkerLayer(markers: [
                      Marker(point: p.point, width: 38, height: 38, alignment: Alignment.topCenter, child: _pin(size: 38)),
                    ]),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Text('📍 ${p.label}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('اضغط حتى تفتح الخريطة والطريق',
                style: TextStyle(color: color.withValues(alpha: 0.75), fontSize: 11.5)),
          ),
        ]),
      ),
    );
  }
}
