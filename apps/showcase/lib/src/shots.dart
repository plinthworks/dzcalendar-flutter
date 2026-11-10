import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// For screenshots on simulators, where nothing can tap: plays [shot] once
/// the calendar is drawn.
///   `tap:<text>`    a finger's tap on the first text starting with it
///   `search:<text>` the search field filled
Future<void> playShot(BuildContext context, String shot, {required TextEditingController search}) async {
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  if (!context.mounted) return;
  final colon = shot.indexOf(':');
  if (colon < 0) return;
  final what = shot.substring(0, colon);
  final arg = shot.substring(colon + 1);
  switch (what) {
    case 'search':
      search.text = arg;
    case 'tap':
      Offset? at;
      void visit(Element e) {
        final w = e.widget;
        final text = w is Text ? w.data : (w is RichText ? w.text.toPlainText() : null);
        if (at == null && text != null && text.startsWith(arg)) {
          final box = e.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize) at = box.localToGlobal(box.size.center(Offset.zero));
        }
        if (at == null) e.visitChildren(visit);
      }

      context.visitChildElements(visit);
      final p = at;
      if (p == null) return;
      final binding = GestureBinding.instance;
      binding.handlePointerEvent(PointerDownEvent(pointer: 41, position: p));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      binding.handlePointerEvent(PointerUpEvent(pointer: 41, position: p));
  }
}
