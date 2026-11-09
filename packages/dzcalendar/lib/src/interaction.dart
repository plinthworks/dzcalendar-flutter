import 'dart:async';

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'env.dart';

/// A box a dragged event would take on screen (global coordinates), and the
/// part of the screen it may show in (the scrolled area it belongs to).
typedef GhostBox = ({Rect rect, Rect clip});

/// What a view gives the gestures (owner's decision 35): what is under a
/// point, in calendar terms, and where an event would be drawn. Everything
/// after that is the core's (`proposeMove`, `proposeResize`,
/// `selectionBetween`), the same for every view.
abstract interface class DragSurface {
  /// The calendar point under [global] (clamped into the view), null when none.
  Hit? hitAt(Offset global);

  /// Where [event] would be drawn, as it is or as a gesture proposes it.
  List<GhostBox> boxesFor(CalEvent event);

  /// Scrolls when [global] is near an edge, by [seconds] worth: true when it moved.
  bool autoscroll(Offset global, double seconds);

  /// Whether the view draws [event]'s length (a month draws a timed event's day only).
  bool canResize(CalEvent event);
}

/// Where a dragged event would go (or is landing, or going back to).
@immutable
final class Ghost {
  const Ghost({
    required this.boxes,
    required this.color,
    required this.onColor,
    required this.label,
    this.valid = true,
  });
  final List<GhostBox> boxes;
  final Color color;
  final Color onColor;
  final String label;

  /// False: the calendar's rules refuse this place.
  final bool valid;

  Ghost withBoxes(List<GhostBox> b) => Ghost(boxes: b, color: color, onColor: onColor, label: label, valid: valid);
}

enum _Kind { move, resize, select }

class _Drag {
  _Drag({
    required this.kind,
    required this.pointer,
    required this.start,
    required this.grab,
    required this.ctx,
    this.instance,
    this.target,
  }) : last = start;

  final _Kind kind;
  final int pointer;
  final Offset start;
  final Hit grab;
  final InteractionContext ctx;
  final EventInstance? instance;

  /// A selection's menu, when the finger is lifted without moving.
  final ActionTarget? target;
  Offset last;

  /// A handle is pulled from where the finger is on it: the edge it stands
  /// for is this far from the finger.
  Offset shift = Offset.zero;
  var moved = false;

  /// The finger itself went past the slop (a handle starts `moved` before it).
  var travelled = false;
  Proposal? proposal;
  CalendarSelection? selection;
}

/// The calendar's editing gestures, one for a [DzCalendar] (owner's
/// decisions 35, 37, 40): a long press grabs an event (it then follows the
/// finger, the view scrolling at its edges) or, on empty time, selects
/// (`selectable`) or offers the menu; let go without moving, the event is
/// held — its handle changes its length, its button opens its menu. A drop
/// runs the core's command through the history and the event lands; a
/// refused one goes back.
///
/// The finger is followed through the pointer router, not a recognizer:
/// the event's widget may be rebuilt, moved or dropped while it is dragged.
class CalendarInteraction {
  CalendarInteraction(TickerProvider vsync) {
    _ticker = vsync.createTicker(_onTick);
    _motion = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 200));
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
  }

  /// Set at each build of the calendar.
  late CalendarEnv env;

  /// The calendar's context: menus open from it.
  BuildContext? context;

  DragSurface? _surface;
  _Drag? _drag;

  /// The pointers down now, where each is: a gesture follows the one under it.
  final _down = <int, Offset>{};
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  late final AnimationController _motion;
  var _disposed = false;

  /// Bumped by each gesture and each slide: a slide's end that finds
  /// another under way leaves it alone.
  var _gen = 0;

  /// The key of the event being dragged (drawn faded where it was).
  final lifted = ValueNotifier<String?>(null);

  /// The key of the event held (its handles shown).
  final held = ValueNotifier<String?>(null);

  /// Where the dragged event would go.
  final ghost = ValueNotifier<Ghost?>(null);

  /// A gesture is under way (a drag, or a drop settling).
  bool get busy => _drag != null || lifted.value != null;

  /// The view now on screen offers itself; the one that leaves takes itself back.
  void attach(DragSurface s) {
    if (!identical(_surface, s)) cancel();
    _surface = s;
  }

  /// Ends a gesture under way without dropping it (another view, period or
  /// controller; editing turned off): the event stays where it was.
  void cancel() {
    if (_drag == null) return;
    _drag = null;
    _ticker.stop();
    _gen++;
    _motion.stop();
    _settle();
  }

  void detach(DragSurface s) {
    if (identical(_surface, s)) _surface = null;
  }

  // ——— what an event may do ———

  bool mayMove(CalEvent ev) =>
      ev.display != EventDisplay.background && ev.perms.start && (env.config.editable || ev.perms.ownStart);

  bool mayResize(CalEvent ev) =>
      ev.display != EventDisplay.background &&
      ev.perms.duration &&
      (env.config.editable || ev.perms.ownDuration) &&
      (_surface?.canResize(ev) ?? false);

  // ——— gestures the views report ———

  /// A long press on an event: grabbed when it may move, else its menu.
  void pressEvent(EventInstance i, Offset global) {
    if (_drag != null) return; // another finger is dragging
    if (mayMove(i.event) && _start(_Kind.move, global, instance: i)) return;
    _menu(EventTarget(i), global);
  }

  /// An event tapped: the app opens it; held, or no app to open it, its menu.
  void tapEvent(EventInstance i, Offset global) {
    final open = env.onEventTap;
    if (open == null || held.value == i.key) {
      _menu(EventTarget(i), global);
    } else {
      release();
      open(i);
    }
  }

  /// A held event's handle pulled: its end follows the finger.
  void pullHandle(EventInstance i, Offset global) {
    if (mayResize(i.event)) _start(_Kind.resize, global, instance: i, moved: true);
  }

  /// The held event's button.
  void openMenu(EventInstance i, Offset global) => _menu(EventTarget(i), global);

  /// A long press on empty time or a day: a selection that follows the finger
  /// (`selectable`), its menu when let go without moving; else the menu at once.
  void pressEmpty(Hit hit, ActionTarget target, Offset global) {
    release();
    if (!env.config.selectable || !_start(_Kind.select, global, hit: hit, target: target)) {
      _menu(target, global);
      return;
    }
    final sel = selectionBetween(_drag!.ctx, hit, hit);
    _drag!.selection = sel;
    env.controller.select(sel);
  }

  /// Lets go of the held event (a tap elsewhere, another period).
  void release() => held.value = null;

  bool _start(
    _Kind kind,
    Offset global, {
    EventInstance? instance,
    Hit? hit,
    ActionTarget? target,
    bool moved = false,
  }) {
    final s = _surface;
    final pointer = _pointerAt(global);
    if (s == null || pointer == null || _drag != null) return false;
    final grab = hit ?? s.hitAt(global);
    if (grab == null) return false;
    _gen++;
    _motion.stop();
    ghost.value = null;
    _drag = _Drag(
      kind: kind,
      pointer: pointer,
      start: global,
      grab: grab,
      ctx: env.controller.kernel.interactionContext(snapMinutes: env.config.snapMinutes),
      instance: instance,
      target: target,
    )..moved = moved;
    if (kind == _Kind.resize && instance != null && !instance.event.allDay) {
      final boxes = s.boxesFor(instance.event);
      if (boxes.isNotEmpty) _drag!.shift = Offset(0, boxes.last.rect.bottom - 1 - global.dy);
    }
    // A landing cut short leaves nothing lifted but this gesture's event.
    lifted.value = instance?.key;
    if (instance != null && held.value != instance.key) held.value = null;
    HapticFeedback.mediumImpact();
    _lastTick = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    if (moved) _update();
    return true;
  }

  /// The pointer down nearest [global] (the one that made the long press or
  /// pulls the handle), within a few slops; none: no gesture.
  int? _pointerAt(Offset global) {
    int? best;
    var dist = kTouchSlop * 4;
    for (final MapEntry(:key, :value) in _down.entries) {
      final d = (value - global).distance;
      if (d <= dist) {
        dist = d;
        best = key;
      }
    }
    return best;
  }

  void _route(PointerEvent e) {
    switch (e) {
      case PointerDownEvent() || PointerMoveEvent():
        _down[e.pointer] = e.position;
      case PointerUpEvent() || PointerCancelEvent():
        _down.remove(e.pointer);
      default:
    }
    final d = _drag;
    if (d == null || e.pointer != d.pointer) return;
    switch (e) {
      case PointerMoveEvent():
        d.last = e.position;
        if (!d.travelled && (e.position - d.start).distance >= kTouchSlop) d.travelled = true;
        if (!d.moved) {
          if ((e.position - d.start).distance < kTouchSlop) return;
          d.moved = true;
          d.travelled = true;
          held.value = null;
        }
        _update();
      case PointerUpEvent():
        _end();
      case PointerCancelEvent():
        _cancel();
      default:
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final d = _drag;
    final s = _surface;
    if (d == null || !d.travelled || s == null || dt <= 0) return;
    if (s.autoscroll(d.last, dt.clamp(0, 0.05))) _update();
  }

  /// The place under the finger, proposed again: the ghost, or the selection.
  void _update() {
    final d = _drag;
    final s = _surface;
    if (d == null || s == null) return;
    final hit = s.hitAt(d.last + d.shift);
    if (d.kind == _Kind.select) {
      if (hit == null) return;
      final sel = selectionBetween(d.ctx, d.grab, hit);
      d.selection = sel;
      env.controller.select(sel);
      return;
    }
    final ev = d.instance!.event;
    final p = hit == null
        ? null
        : d.kind == _Kind.move
        ? proposeMove(d.ctx, ev, d.grab, hit)
        : proposeResize(d.ctx, ev, Edge.end, hit);
    if (p != null && (d.proposal == null || _spanKey(p.proposed) != _spanKey(d.proposal!.proposed))) {
      HapticFeedback.selectionClick();
    }
    d.proposal = p;
    ghost.value = p == null ? null : _ghostOf(d.instance!, p.proposed, valid: p.valid);
  }

  Ghost _ghostOf(EventInstance i, CalEvent ev, {bool valid = true}) {
    final colors = env.colorsOf(i);
    final when = switch (ev) {
      TimedEvent(:final start, :final end) => '${env.time(start.instant)} – ${env.time(end.instant)}',
      AllDayEvent() => null,
    };
    final title = env.title(i);
    return Ghost(
      boxes: _surface?.boxesFor(ev) ?? const [],
      color: colors.fill,
      onColor: colors.on,
      label: when == null ? title : '$when  $title',
      valid: valid,
    );
  }

  void _end() {
    final d = _drag!;
    _drag = null;
    _ticker.stop();
    switch (d.kind) {
      case _Kind.select:
        final sel = d.selection;
        if (d.moved && sel != null) {
          env.onSelect?.call(sel);
        } else if (d.target != null) {
          _menu(d.target!, d.start);
        }
      case _Kind.move || _Kind.resize:
        if (!d.moved) {
          // Let go where it was taken: held, its handles shown.
          lifted.value = null;
          ghost.value = null;
          held.value = d.instance!.key;
          return;
        }
        unawaited(_drop(d));
    }
  }

  void _cancel() {
    final d = _drag!;
    _drag = null;
    _ticker.stop();
    if (d.instance != null) _back(d.instance!);
  }

  /// A drop: refused (it goes back), asked how far (an occurrence), run
  /// through the history — told to `onEventChange` — and landed.
  Future<void> _drop(_Drag d) async {
    final i = d.instance!;
    final p = d.proposal;
    if (p == null || isUnchanged(p)) return _back(i);
    // A place the rules refuse is still run (validated): refused there, the
    // app's `onCommandRefused` hears why.
    var scope = EditScope.this_;
    if (i.event.ref != null && p.valid) {
      final chosen = await _askScope(d.last);
      if (_disposed) return;
      if (chosen == null) return _back(i);
      scope = chosen;
    }
    final r = env.controller.run(commandFor(i, p, scope), validate: true);
    if (!r.ok) {
      HapticFeedback.heavyImpact();
      return _back(i);
    }
    HapticFeedback.lightImpact();
    _fly(() => _surface?.boxesFor(p.proposed) ?? const [], _settle);
  }

  void _back(EventInstance i) => _fly(() => _surface?.boxesFor(i.event) ?? const [], _settle);

  void _settle() {
    ghost.value = null;
    lifted.value = null;
  }

  /// The ghost slides to [to] (~200 ms), then [done]; at once when the
  /// system asks for less motion, or there is nothing to slide.
  void _fly(List<GhostBox> Function() target, void Function() done) {
    final from = ghost.value;
    final to0 = target();
    final ctx = context;
    final still = ctx == null || !ctx.mounted || (MediaQuery.maybeDisableAnimationsOf(ctx) ?? false);
    if (from == null || from.boxes.isEmpty || to0.isEmpty || still) return done();
    final gen = ++_gen;
    final a = from.boxes;
    void step() {
      // Read again each frame: the drop's rebuild may move where it lands (a lane added).
      final now = target();
      final to = now.isEmpty ? to0 : now;
      final t = Curves.easeOutCubic.transform(_motion.value);
      ghost.value = from.withBoxes([
        for (var k = 0; k < to.length; k++)
          (rect: Rect.lerp(a[k < a.length ? k : a.length - 1].rect, to[k].rect, t)!, clip: to[k].clip),
      ]);
    }

    _motion
      ..reset()
      ..addListener(step);
    _motion.forward().whenCompleteOrCancel(() {
      _motion.removeListener(step);
      if (!_disposed && gen == _gen) done();
    });
  }

  Future<EditScope?> _askScope(Offset global) async {
    final ctx = context;
    if (ctx == null || !ctx.mounted) return null;
    final l10n = env.l10n;
    final overlay = Overlay.of(ctx).context.findRenderObject()! as RenderBox;
    return showMenu<EditScope>(
      context: ctx,
      position: RelativeRect.fromRect(global & const Size(1, 1), Offset.zero & overlay.size),
      semanticLabel: l10n.changeWhich,
      items: [
        PopupMenuItem<EditScope>(enabled: false, height: 32, child: Text(l10n.changeWhich)),
        PopupMenuItem(value: EditScope.this_, child: Text(l10n.scopeThis)),
        PopupMenuItem(value: EditScope.following, child: Text(l10n.scopeFollowing)),
        PopupMenuItem(value: EditScope.all, child: Text(l10n.scopeAll)),
      ],
    );
  }

  void _menu(ActionTarget target, Offset global) {
    final ctx = context;
    if (ctx == null || !ctx.mounted) return;
    unawaited(env.showActions(ctx, target, global));
  }

  void dispose() {
    _disposed = true;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    _ticker.dispose();
    _motion.dispose();
    lifted.dispose();
    held.dispose();
    ghost.dispose();
  }
}

/// What a proposal changes, to tell two apart (a haptic tick on each new place).
String _spanKey(CalEvent ev) => switch (ev) {
  TimedEvent(:final start, :final end) =>
    '${start.instant.epochMilliseconds}/${end.instant.epochMilliseconds}/${ev.resourceIds.join(',')}',
  AllDayEvent(:final start, :final end) => '$start/$end/${ev.resourceIds.join(',')}',
};

/// The ghost, over the calendar: drawn where the gesture says, clipped to
/// the area it belongs to.
class GhostLayer extends StatelessWidget {
  const GhostLayer({super.key, required this.interaction, required this.radius, required this.style});
  final CalendarInteraction interaction;
  final double radius;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ValueListenableBuilder<Ghost?>(
      valueListenable: interaction.ghost,
      builder: (context, g, _) {
        if (g == null) return const SizedBox.expand();
        final box = context.findRenderObject() as RenderBox?;
        final origin = box != null && box.hasSize ? box.localToGlobal(Offset.zero) : Offset.zero;
        return CustomPaint(
          size: Size.infinite,
          painter: _GhostPainter(
            g,
            origin,
            radius,
            style,
            Directionality.of(context),
            Theme.of(context).colorScheme.error,
          ),
        );
      },
    ),
  );
}

class _GhostPainter extends CustomPainter {
  _GhostPainter(this.ghost, this.origin, this.radius, this.style, this.direction, this.refused);
  final Color refused;
  final Ghost ghost;
  final Offset origin;
  final double radius;
  final TextStyle style;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = ghost.valid ? ghost.color.withValues(alpha: 0.9) : ghost.color.withValues(alpha: 0.35);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ghost.valid ? 1 : 2
      ..color = ghost.valid ? ghost.onColor.withValues(alpha: 0.6) : refused;
    for (final (index, b) in ghost.boxes.indexed) {
      final r = b.rect.shift(-origin);
      canvas.save();
      canvas.clipRect(b.clip.shift(-origin));
      final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
      canvas.drawShadow(Path()..addRRect(rr), Colors.black, 4, false);
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, edge);
      if (index == 0 && r.width > 12) {
        final tp = TextPainter(
          text: TextSpan(
            text: ghost.label,
            style: style.copyWith(color: ghost.valid ? ghost.onColor : null),
          ),
          textDirection: direction,
          maxLines: (r.height / ((style.fontSize ?? 11) * 1.3)).floor().clamp(1, 3),
          ellipsis: '…',
        )..layout(maxWidth: r.width - 6);
        final x = direction == TextDirection.ltr ? r.left + 3 : r.right - 3 - tp.width;
        tp.paint(canvas, Offset(x, r.top + 1));
        tp.dispose();
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GhostPainter old) =>
      !identical(old.ghost, ghost) ||
      old.origin != origin ||
      old.radius != radius ||
      old.direction != direction ||
      old.refused != refused;
}
