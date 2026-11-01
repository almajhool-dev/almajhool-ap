import 'package:flutter/material.dart';

import '../services/core_services.dart';
import '../services/fx_settings.dart';
import '../utils/helpers.dart';

/// زر المالك بس: يطفي/يشغّل حركة الخلفيات عند كل المستخدمين مرة وحدة (توصل للكل لحظيًا).
class FxMotionSwitch extends StatefulWidget {
  /// للاختبار: بدل طلب الخادم
  final Future<void> Function(bool on)? save;
  const FxMotionSwitch({super.key, this.save});

  @override
  State<FxMotionSwitch> createState() => _FxMotionSwitchState();
}

class _FxMotionSwitchState extends State<FxMotionSwitch> {
  bool _busy = false;

  Future<void> _set(bool v) async {
    final fx = FxSettings.instance;
    final before = fx.motion;
    setState(() => _busy = true);
    fx.setMotion(v); // عندك فورًا، وعند الباقين أول ما يوصل التغيير من الخادم
    try {
      final save = widget.save ??
          (bool on) async {
            await supa.rpc('owner_set_fx_motion', params: {'p_on': on});
          };
      await save(v);
      if (mounted) {
        showSnack(context, v ? 'رجعت حركة الخلفيات عند كل المستخدمين ✨' : 'وقفت حركة الخلفيات عند كل المستخدمين');
      }
    } catch (e) {
      fx.setMotion(before);
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: FxSettings.instance,
        builder: (context, _) {
          final on = FxSettings.instance.motion;
          return SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_rounded),
            title: const Text('حركة الخلفيات لكل المستخدمين ✨'),
            subtitle: Text(on
                ? 'شغّالة عند الكل — إذا طفيتها تتوقف عند كل المستخدمين'
                : 'متوقفة عند كل المستخدمين — الخلفيات ثابتة'),
            value: on,
            onChanged: _busy ? null : _set,
          );
        },
      );
}
