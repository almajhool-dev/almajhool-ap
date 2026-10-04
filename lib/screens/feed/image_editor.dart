import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;

/// محرر صور بسيط: قص بنسب مختلفة، تكبير وتحريك، وتدوير.
/// يرجع صورة JPEG جاهزة للرفع.
class ImageEditorScreen extends StatefulWidget {
  final Uint8List bytes;
  const ImageEditorScreen({super.key, required this.bytes});

  static Future<Uint8List?> open(BuildContext context, Uint8List bytes) =>
      Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => ImageEditorScreen(bytes: bytes)));

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  final _boundary = GlobalKey();
  final _tc = TransformationController();
  double? _imageRatio; // عرض/ارتفاع الصورة الأصلية
  double? _ratio; // نسبة القص المختارة (null = الأصلية)
  int _turns = 0; // تدوير بمضاعفات 90°
  bool _saving = false;

  static const _ratios = <String, double?>{
    'الأصلي': null,
    'مربع 1:1': 1,
    'طولي 4:5': 4 / 5,
    'قصة 9:16': 9 / 16,
    'عريض 16:9': 16 / 9,
  };

  @override
  void initState() {
    super.initState();
    ui.decodeImageFromList(widget.bytes, (im) {
      if (mounted) setState(() => _imageRatio = im.width / im.height);
    });
  }

  double get _baseRatio {
    final r = _imageRatio ?? 1;
    return _turns.isOdd ? 1 / r : r;
  }

  double get _frameRatio => _ratio ?? _baseRatio;

  Future<void> _done() async {
    setState(() => _saving = true);
    try {
      final ro = _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final pixelRatio = 1440 / ro.size.width;
      final image = await ro.toImage(pixelRatio: pixelRatio.clamp(1.0, 6.0));
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final jpg = await compute(_toJpeg, data!.buffer.asUint8List());
      if (mounted) Navigator.pop(context, jpg);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر حفظ الصورة: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('تعديل الصورة'),
        actions: [
          TextButton(
            onPressed: _saving || _imageRatio == null ? null : _done,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('تم', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _imageRatio == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: AspectRatio(
                        aspectRatio: _frameRatio,
                        child: Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.white54, width: 1.5)),
                          child: ClipRect(
                            child: RepaintBoundary(
                              key: _boundary,
                              child: ColoredBox(
                                color: Colors.black,
                                child: InteractiveViewer(
                                  transformationController: _tc,
                                  minScale: 1,
                                  maxScale: 6,
                                  child: SizedBox.expand(
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      child: RotatedBox(
                                        quarterTurns: _turns,
                                        child: Image.memory(widget.bytes, gaplessPlayback: true),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('حرّك الصورة بإصبعك وكبّرها لاختيار الجزء المطلوب',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final e in _ratios.entries)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(e.key),
                      selected: _ratio == e.value,
                      onSelected: (_) => setState(() {
                        _ratio = e.value;
                        _tc.value = Matrix4.identity();
                      }),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _tool(Icons.rotate_left_rounded, 'تدوير', () => setState(() {
                        _turns = (_turns + 3) % 4;
                        _tc.value = Matrix4.identity();
                      })),
                  _tool(Icons.rotate_right_rounded, 'تدوير', () => setState(() {
                        _turns = (_turns + 1) % 4;
                        _tc.value = Matrix4.identity();
                      })),
                  _tool(Icons.restart_alt_rounded, 'إعادة', () => setState(() {
                        _turns = 0;
                        _ratio = null;
                        _tc.value = Matrix4.identity();
                      })),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      );
}

Uint8List _toJpeg(Uint8List png) {
  final decoded = img.decodePng(png)!;
  return Uint8List.fromList(img.encodeJpg(decoded, quality: 85));
}

/// ضغط أي صورة إلى JPEG بعرض أقصى 1440 (للصور غير المعدّلة).
Future<Uint8List> compressImage(Uint8List bytes) => compute(_compress, bytes);

Uint8List _compress(Uint8List bytes) {
  var im = img.decodeImage(bytes);
  if (im == null) return bytes;
  im = img.bakeOrientation(im);
  if (im.width > 1440) im = img.copyResize(im, width: 1440);
  return Uint8List.fromList(img.encodeJpg(im, quality: 82));
}
