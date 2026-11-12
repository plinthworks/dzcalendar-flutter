import 'dart:math' as math;

import 'package:dzcalendar_core/internal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../controller.dart' show timelineSliders;
import '../env.dart';
import '../interaction.dart';
import '../keyboard.dart';
import 'common.dart';

/// A column of a timeline's resource area: a field of the resources, its
/// head, its width (the web's `areaColumns`). Several columns show on
/// tablets and desktops; a phone shows the title alone (owner's decision 63).
@immutable
final class ResourceAreaColumn {
  const ResourceAreaColumn({required this.field, this.header, this.width});

  /// Read with `Resource.field`: its own (`title`, `id`…), what was given
  /// (`fields`), its `extendedProps`.
  final String field;

  /// The column's head; default: "Resources" for the title, else the field's name.
  final String? header;

  /// Pixels; default the theme's `resourceAreaWidth` for the first, 110 for the others.
  final double? width;

  @override
  bool operator ==(Object other) =>
      other is ResourceAreaColumn && other.field == field && other.header == header && other.width == width;
  @override
  int get hashCode => Object.hash(field, header, width);
}

/// The collapsed rows after a fold, for an application that keeps them.
typedef ResourceToggleCallback = void Function(Set<String> collapsedResources, Set<String> collapsedGroups);

/// A timeline (`timeline*`, `resourceTimeline*`): rows of resources (or one
/// row of every event) along an elapsed time axis, the resource area at the
/// start. One scroller both ways (owner's decision 62): the time heads stay
/// on top, the resource area at the start, and only the rows and the
/// stretch of time in view (and a margin) are built.
class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.env,
    required this.model,
    this.scrollHour = 7,
    this.columns = const [],
    this.onResourceToggle,
  });

  final CalendarEnv env;
  final TimelineModel model;

  /// The hour of today (else of the first day) brought into view at first.
  final int scrollHour;
  final List<ResourceAreaColumn> columns;
  final ResourceToggleCallback? onResourceToggle;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

/// The stretch of the axis whose content is built, in positions: what is in
/// view and half a view on each side, moved in steps of half a view.
@immutable
final class _Window {
  const _Window(this.from, this.to);
  final double from;
  final double to;
  bool meets(double a, double b) => b >= from && a <= to;
  @override
  bool operator ==(Object other) => other is _Window && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
}

/// Where things are, in logical pixels (the start edge is 0; right to left
/// mirrors at paint).
@immutable
final class _Geo {
  const _Geo({required this.areaW, required this.headH, required this.axisW, required this.tops});
  final double areaW;
  final double headH;
  final double axisW;

  /// Row tops from the first row, and the end after the last ([tops.length] = rows + 1).
  final List<double> tops;

  int get rows => tops.length - 1;

  /// The row at [y] (from the first row's top), clamped.
  int rowAt(double y) {
    if (rows <= 0) return 0;
    var lo = 0;
    var hi = rows - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (tops[mid] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

/// The slots meeting [w], as indexes (first, last): found by the axis's
/// search, not a walk over every slot (a month of 5-minute slots is 8,928).
(int, int) _slotRange(TimelineAxis a, _Window w) {
  final n = a.slots.length;
  if (n == 0) return (0, -1);
  final first = a.slotAt(a.fromPosition(math.max(0, w.from)));
  final last = a.slotAt(a.fromPosition(math.min(a.length - 1e-6, w.to)));
  return (first < 0 ? 0 : first, last < 0 ? n - 1 : last);
}

const _minCol = 40.0;
const _maxCol = 480.0;
const _phoneArea = 112.0;
const _initialsArea = 44.0;

class _TimelineViewState extends State<TimelineView> implements DragSurface, KeySurface {
  final _h = ScrollController();
  final _v = ScrollController();
  final _viewportKey = GlobalKey();
  late final _window = ValueNotifier<_Window>(const _Window(0, 0));

  /// The column widths a person set by their handles (tablets, desktops).
  List<double>? _widths;

  /// A phone's area shows initials only.
  var _initials = false;

  // What the gestures read (set at each layout).
  var _slotW = 44.0;
  var _laneH = 26.0;
  _Geo _geo = const _Geo(areaW: 0, headH: 52, axisW: 0, tops: [0]);
  var _room = Size.zero;

  /// The axis the scroll was last placed for: another one (a period, a scale) is placed again.
  (int, int, int)? _placedFor;

  /// The slot width the scroll was placed at: another one (a rotation, a text size, a span) keeps the
  /// moment at the start edge in place.
  double? _placedW;

  /// Where a period brought in by ◀ ▶ (`timeline.step`) lands — its end going back, its start going on —
  /// tied to the period it left: if that period stays (navigation refused), it is never used.
  ({int direction, PlainDate from, String view})? _landing;

  /// What the keyboard asked to see in a period not yet built: revealed once it is placed.
  Hit? _revealLater;

  /// Narrower than a tablet: one narrow column (decision 63), by the calendar's own width — a narrow
  /// pane on a tablet is laid out as a phone.
  var _narrow = false;

  /// The positions at which days (or months) start: their lines are drawn heavier.
  late Set<int> _groupStarts = _startsOf(axis);
  TimelineAxis? _startsFor;

  static Set<int> _startsOf(TimelineAxis a) => {for (final g in a.groups) g.start.epochMilliseconds};

  CalendarEnv get env => widget.env;
  TimelineModel get model => widget.model;
  TimelineAxis get axis => model.axis;
  bool get _rtl => env.textDirection == TextDirection.rtl;

  @override
  void initState() {
    super.initState();
    _h.addListener(_moveWindow);
    timelineSliders[env.controller] = _slide;
  }

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    if (!identical(old.env.controller, env.controller)) {
      if (timelineSliders[old.env.controller] == _slide) timelineSliders[old.env.controller] = null;
      timelineSliders[env.controller] = _slide;
    }
  }

  @override
  void dispose() {
    env.interaction.detach(this);
    env.interaction.keyboard.detach(this);
    if (timelineSliders[env.controller] == _slide) timelineSliders[env.controller] = null;
    _h.dispose();
    _v.dispose();
    _window.dispose();
    super.dispose();
  }

  // ——— sizes ———

  double _scale(BuildContext context) => MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);

  List<ResourceAreaColumn> get _columns =>
      widget.columns.isEmpty ? const [ResourceAreaColumn(field: 'title')] : widget.columns;

  bool get _resources => model.options.rows != null;

  List<double> _columnWidths(BuildContext context, double room) {
    if (!_resources) return const [];
    if (_narrow) return [_initials ? _initialsArea : math.min(_phoneArea, room * 0.4)];
    final cols = _columns;
    final set = _widths;
    return [
      for (var i = 0; i < cols.length; i++)
        (set != null && i < set.length ? set[i] : cols[i].width ?? (i == 0 ? env.style.resourceAreaWidth : 110)).clamp(
          _minCol,
          _maxCol,
        ),
    ];
  }

  /// A slot's width: the theme's, or what `timeline.span` shares out of the room for time.
  double _slotWidth(double room) {
    final span = env.controller.options.timeline.span;
    if (span != null && room > 0) {
      final slots = math.min(span.inMilliseconds / (axis.slotMinutes * 60000), axis.length);
      if (slots > 0) return math.max(2, room / slots);
    }
    return axis.unit == TimelineUnit.day ? env.style.timelineDayWidth : env.style.timelineSlotWidth;
  }

  // ——— the window along time ———

  void _moveWindow() {
    final shown = math.max(1.0, _room.width - _geo.areaW) / _slotW;
    final half = math.max(1.0, (shown / 2).floorToDouble());
    final at = (_h.hasClients ? _h.offset : 0) / _slotW;
    final from = ((at - half) / half).floor() * half;
    final next = _Window(from, from + shown + 3 * half);
    if (next != _window.value) _window.value = next;
  }

  // ——— ◀ ▶ by `timeline.step` ———

  bool _slide(int direction) => _slideBy(direction) != null;

  /// Slides along time by `timeline.step` (short of it at the axis's edge):
  /// where the scroll was and where it goes, in pixels. Null: no step, or
  /// already at that edge — the period changes instead.
  (double, double)? _slideBy(int direction, {bool animate = true}) {
    final step = env.controller.options.timeline.step;
    if (step == null || !_h.hasClients || !mounted) return null;
    final p = _h.position;
    final px = step.inMilliseconds / (axis.slotMinutes * 60000) * _slotW;
    final atEdge = direction > 0 ? p.pixels >= p.maxScrollExtent - 0.5 : p.pixels <= p.minScrollExtent + 0.5;
    if (atEdge) {
      _landing = (direction: direction, from: env.state.date, view: env.state.view.type);
      return null;
    }
    final from = p.pixels;
    final to = (from + direction * px).clamp(p.minScrollExtent, p.maxScrollExtent);
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _h.jumpTo(to);
    } else {
      _h.animateTo(to, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    }
    return (from, to);
  }

  /// Where the scroll goes for a new axis: a period brought in by ◀ ▶ at its
  /// edge; else today's (or the first day's) `scrollHour`, a day scale
  /// today's column two from the start.
  double _home() {
    final landing = _landing;
    _landing = null;
    // Only for the period ◀ ▶ brought in: the same view, another date.
    if (landing != null && landing.view == env.state.view.type && landing.from != env.state.date) {
      return landing.direction > 0 ? 0 : double.infinity;
    }
    final slots = axis.slots;
    if (slots.isEmpty) return 0;
    final today = env.state.today;
    final day = slots.any((s) => s.date == today) ? today : slots.first.date;
    if (axis.unit == TimelineUnit.day) {
      final s = slots.firstWhere((s) => s.date == day);
      return math.max(0, (axis.toPosition(s.start) - 2) * _slotW);
    }
    final s = slots.firstWhere(
      (s) => s.date == day && s.time != null && s.time!.hour >= widget.scrollHour,
      orElse: () => slots.firstWhere((s) => s.date == day),
    );
    return axis.toPosition(s.start) * _slotW;
  }

  void _place() {
    final key = (axis.start.epochMilliseconds, axis.end.epochMilliseconds, axis.slotMinutes);
    final w = _slotW;
    if (key == _placedFor) {
      final was = _placedW;
      if (was == null || was == w) return;
      // The same axis at another scale: the moment at the start edge stays there.
      _placedW = w;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_h.hasClients) return;
        final p = _h.position;
        _h.jumpTo((p.pixels * w / was).clamp(p.minScrollExtent, p.maxScrollExtent));
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // No scroller yet (no rows to show): placed when there is one.
      if (!mounted || !_h.hasClients) return;
      _placedFor = key;
      _placedW = w;
      final p = _h.position;
      _h.jumpTo(_home().clamp(p.minScrollExtent, p.maxScrollExtent));
      _moveWindow();
    });
  }

  /// The one row of a timeline without resources fills the view: as many lanes as its height holds.
  void _fillLanes(double bodyH) {
    if (_resources || _laneH <= 0) return;
    final n = math.max(2, ((bodyH - 8) / _laneH).floor());
    final t = env.controller.options.timeline;
    if (n == t.fillLanes) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final now = env.controller.options;
      if (now.timeline.fillLanes != n) {
        env.controller.setOptions(now.copyWith(timeline: now.timeline.copyWith(fillLanes: n)));
      }
    });
  }

  // ——— building ———

  @override
  Widget build(BuildContext context) {
    env.interaction.attach(this);
    env.interaction.keyboard.attach(this);
    final scale = _scale(context);
    _laneH = env.style.laneHeight * scale;
    final headH = 52 * scale;
    return LayoutBuilder(
      builder: (context, box) {
        _room = box.biggest;
        _narrow = box.maxWidth < 600;
        if (!identical(_startsFor, axis)) {
          _startsFor = axis;
          _groupStarts = _startsOf(axis);
        }
        final widths = _columnWidths(context, box.maxWidth);
        // Never so wide that no time is left to see.
        final areaW = math.min(widths.fold(0.0, (a, b) => a + b), box.maxWidth * 0.6);
        _slotW = _slotWidth(box.maxWidth - areaW);
        final bodyH = math.max(0.0, box.maxHeight - headH);
        final tops = <double>[0];
        for (final r in model.rows) {
          tops.add(
            tops.last +
                switch (r) {
                  TimelineGroupRow() => _laneH + 8,
                  TimelineResourceRow() => model.maxLanes * _laneH + 8,
                  TimelineAllRow() => math.max(bodyH, model.maxLanes * _laneH + 8),
                },
          );
        }
        _geo = _Geo(areaW: areaW, headH: headH, axisW: axis.length * _slotW, tops: tops);
        _moveWindow();
        _place();
        if (_revealLater != null) {
          // After the placing (its callback was added first).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final r = _revealLater;
            _revealLater = null;
            if (r != null && mounted) reveal(r);
          });
        }
        _fillLanes(bodyH);
        if (_resources && model.rows.isEmpty) {
          return Center(child: Text(env.l10n.noResources));
        }
        return KeyedSubtree(
          key: _viewportKey,
          child: _TimelineScroll(
            geo: _geo,
            diagonalDragBehavior: DiagonalDragBehavior.weightedEvent,
            verticalDetails: ScrollableDetails.vertical(controller: _v),
            horizontalDetails: ScrollableDetails(
              direction: _rtl ? AxisDirection.left : AxisDirection.right,
              controller: _h,
            ),
            delegate: TwoDimensionalChildBuilderDelegate(
              maxXIndex: 1,
              maxYIndex: model.rows.length,
              builder: (context, v) => _cell(v, widths),
            ),
          ),
        );
      },
    );
  }

  Widget _cell(ChildVicinity v, List<double> widths) {
    if (v.yIndex == 0) {
      return v.xIndex == 0
          ? _Corner(
              env: env,
              columns: _columns,
              widths: widths,
              phone: _narrow,
              initials: _initials,
              onInitials: () => setState(() => _initials = !_initials),
              onWidth: (i, w) => setState(() {
                final next = [...widths];
                next[i] = w.clamp(_minCol, _maxCol);
                _widths = next;
              }),
              shown: _resources,
            )
          : _TimeHead(env: env, axis: axis, slotW: _slotW, window: _window, scroll: _h);
    }
    final i = v.yIndex - 1;
    final row = model.rows[i];
    if (v.xIndex == 0) {
      return _AreaCell(
        env: env,
        row: row,
        columns: _narrow ? const [ResourceAreaColumn(field: 'title')] : _columns,
        widths: widths,
        initials: _narrow && _initials,
        onToggle: _toggle,
      );
    }
    return _RowBody(
      env: env,
      model: model,
      index: i,
      slotW: _slotW,
      laneH: _laneH,
      window: _window,
      groupStarts: _groupStarts,
      snapMs: _snapMs,
      onTap: (pos) => _tap(i, pos),
      onPress: (pos, global) => _press(i, pos, global),
    );
  }

  void _toggle(TimelineRow row) {
    final k = env.controller.kernel;
    switch (row) {
      case TimelineResourceRow(:final resource):
        k.toggleResourceRow(resource.id);
      case TimelineGroupRow(:final value):
        k.toggleGroupRow(value);
      case TimelineAllRow():
        return;
    }
    widget.onResourceToggle?.call(k.options.collapsedResources, k.options.collapsedGroups);
  }

  // ——— taps on empty time ———

  /// The slot under a point: a tap means the slot it is in (a day on a day scale).
  Hit? _slotHit(int row, double pos) {
    final hit = timelineHitAt(model, row, pos);
    if (hit is! SlotHit) return hit;
    final s = axis.slotAt(hit.instant);
    if (s < 0) return hit;
    final slot = axis.slots[s];
    return SlotHit(date: slot.date, instant: slot.start, resourceId: hit.resourceId, slotStart: slot.start);
  }

  void _tap(int row, double pos) {
    final hit = _slotHit(row, pos);
    if (hit == null) return;
    if (env.interaction.keyboard.putAt(hit)) return;
    env.interaction.release();
    // The keyboard goes on from the slot tapped.
    env.interaction.keyboard.tapped(hit);
    env.onDateTap?.call(hit);
    final ctx = env.controller.kernel.interactionContext(snapMinutes: axis.slotMinutes);
    final sel = selectionBetween(ctx, hit, hit);
    env.controller.select(sel);
    env.selected(sel);
  }

  void _press(int row, double pos, Offset global) {
    final hit = _slotHit(row, pos);
    if (hit == null) return;
    final ActionTarget target = switch (hit) {
      SlotHit(:final date, :final instant, :final resourceId) => SlotTarget(
        date: date,
        instant: instant,
        exists: true,
        ambiguous: false,
        resourceId: resourceId,
      ),
      DayHit(:final date, :final resourceId) => DayTarget(date: date, resourceId: resourceId),
    };
    env.interaction.pressEmpty(hit, target, global);
  }

  // ——— the gestures' surface ———

  RenderBox? get _box => _viewportKey.currentContext?.findRenderObject() as RenderBox?;

  /// The body's box (below the heads, after the area), in the viewport's coordinates.
  Rect _bodyRect(Size size) => _rtl
      ? Rect.fromLTRB(0, _geo.headH, math.max(0, size.width - _geo.areaW), size.height)
      : Rect.fromLTRB(math.min(_geo.areaW, size.width), _geo.headH, size.width, size.height);

  double get _vx => _h.hasClients ? _h.offset : 0;
  double get _vy => _v.hasClients ? _v.offset : 0;

  @override
  Hit? hitAt(Offset global) {
    final box = _box;
    if (box == null || !box.hasSize || model.rows.isEmpty) return null;
    final body = _bodyRect(box.size);
    if (body.isEmpty) return null;
    final l = box.globalToLocal(global);
    final p = Offset(l.dx.clamp(body.left, body.right - 0.5), l.dy.clamp(body.top, body.bottom - 0.5));
    final along = (_rtl ? box.size.width - p.dx : p.dx) - _geo.areaW + _vx;
    var row = _geo.rowAt(p.dy - _geo.headH + _vy);
    // Over a group's band: the row of events under it (the last band: the one above), so a drag goes on.
    if (row < model.rows.length && model.rows[row] is TimelineGroupRow) {
      var r = row + 1;
      while (r < model.rows.length && model.rows[r] is TimelineGroupRow) {
        r++;
      }
      if (r >= model.rows.length) {
        r = row - 1;
        while (r >= 0 && model.rows[r] is TimelineGroupRow) {
          r--;
        }
      }
      if (r < 0) return null;
      row = r;
    }
    return timelineHitAt(model, row, along / _slotW);
  }

  @override
  List<GhostBox> boxesFor(CalEvent ev) {
    final box = _box;
    if (box == null || !box.hasSize) return const [];
    final zone = env.zone;
    final (s, e) = switch (ev) {
      AllDayEvent(:final start, :final end) => (start.startOfDayIn(zone), end.startOfDayIn(zone)),
      TimedEvent(:final start, :final end) => (start.instant, end.instant),
    };
    final from = axis.toPosition(s);
    final to = math.max(axis.toPosition(e), from + 0.25);
    final body = _bodyRect(box.size);
    final clip = box.localToGlobal(body.topLeft) & body.size;
    final known = {for (final r in model.options.resources) r.id};
    final out = <GhostBox>[];
    for (var i = 0; i < model.rows.length; i++) {
      final row = model.rows[i];
      if (row is TimelineGroupRow) continue;
      if (row is TimelineResourceRow) {
        final id = row.resource.id;
        final mine = id == unassignedId ? !ev.resourceIds.any(known.contains) : ev.resourceIds.contains(id);
        if (!mine) continue;
      }
      final top = _geo.headH + _geo.tops[i] - _vy + 3;
      final h = math.max(8.0, _geo.tops[i + 1] - _geo.tops[i] - 6);
      final a = _geo.areaW + from * _slotW - _vx;
      final b = _geo.areaW + to * _slotW - _vx;
      final left = _rtl ? box.size.width - b : a;
      final rect = box.localToGlobal(Offset(left, top)) & Size(b - a, h);
      if (rect.overlaps(clip)) out.add((rect: rect, clip: clip));
    }
    return out;
  }

  /// Near an edge of the rows' time, the timeline scrolls that way: along
  /// time at the start or end edge, through the rows at the top or bottom.
  @override
  bool autoscroll(Offset g, double seconds) {
    final box = _box;
    if (box == null || !box.hasSize) return false;
    final body = _bodyRect(box.size);
    if (body.isEmpty) return false;
    final area = box.localToGlobal(body.topLeft) & body.size;
    const edge = 40.0;
    const speed = 900.0; // pixels a second at the very edge
    double push(double towardStart, double towardEnd) =>
        towardStart < edge ? -(edge - towardStart) / edge : (towardEnd < edge ? (edge - towardEnd) / edge : 0);
    bool scroll(ScrollController c, double by) {
      if (by == 0 || !c.hasClients || c.positions.length != 1) return false;
      final p = c.position;
      final to = (p.pixels + by).clamp(p.minScrollExtent, p.maxScrollExtent);
      if (to == p.pixels) return false;
      c.jumpTo(to);
      return true;
    }

    var moved = scroll(_v, push(g.dy - area.top, area.bottom - g.dy).clamp(-1.5, 1.5) * speed * seconds);
    final toStart = _rtl ? area.right - g.dx : g.dx - area.left;
    final toEnd = _rtl ? g.dx - area.left : area.right - g.dx;
    moved |= scroll(_h, push(toStart, toEnd).clamp(-1.5, 1.5) * speed * seconds);
    return moved;
  }

  /// A timeline counted in days draws a timed event's days only: its length is not changed there.
  @override
  bool canResize(CalEvent event) => event is AllDayEvent || axis.unit != TimelineUnit.day;

  // ——— the keyboard's surface (decision 41): a cursor on a row, at a moment (or a day) ———

  /// The model as the controller has it now: a period the keyboard just went to is known before it is built.
  TimelineModel get _now => switch (env.controller.model) {
    TimelineViewModel(:final model) => model,
    _ => model,
  };

  int get _snapMs => math.max(1, env.config.snapMinutes) * 60000;

  static ResourceId? _ownerOf(TimelineRow r) => r is TimelineResourceRow ? r.resource.id : null;

  /// The row of [id] (a timeline without resources: its one row); not found, the first row drawn.
  static int _rowOf(TimelineModel m, ResourceId? id) {
    var first = -1;
    for (var i = 0; i < m.rows.length; i++) {
      final r = m.rows[i];
      if (r is TimelineGroupRow) continue;
      if (first < 0) first = i;
      if (_ownerOf(r) == id) return i;
    }
    return first;
  }

  Hit _hitAtRow(TimelineModel m, int row, Instant at) {
    final date = ZonedDateTime(at, env.zone).date;
    final owner = _ownerOf(m.rows[row]);
    return m.axis.unit == TimelineUnit.day
        ? DayHit(date: date, resourceId: owner)
        : SlotHit(date: date, instant: at, resourceId: owner);
  }

  Instant _instantOf(Hit h) => switch (h) {
    SlotHit(:final instant) => instant,
    DayHit(:final date) => date.startOfDayIn(env.zone),
  };

  Hit? _fitted(Hit h) => switch (fit(h)) {
    FitAt(:final hit) => hit,
    _ => null,
  };

  @override
  KeyGrid get keyGrid => KeyGrid.timeline;

  @override
  KeyGrid get hitGrid => _now.axis.unit == TimelineUnit.day ? KeyGrid.day : KeyGrid.time;

  @override
  bool get allDayRow => false;

  @override
  bool get resourceView => _now.options.rows != null;

  /// Now when it is in view; else the moment at the view's start edge, on the first row in view.
  @override
  Hit? home() {
    final m = _now;
    if (m.axis.slots.isEmpty) return null;
    var i = _rowOf(m, null);
    if (i < 0) return null;
    if (identical(m, model) && _v.hasClients) {
      for (var r = i; r < m.rows.length && r < _geo.rows; r++) {
        if (m.rows[r] is! TimelineGroupRow && _geo.tops[r] >= _vy - 0.5) {
          i = r;
          break;
        }
      }
    }
    final along = identical(m, model) && _slotW > 0 ? _vx / _slotW : 0.0;
    final shown = math.max(0.0, _room.width - _geo.areaW) / math.max(1.0, _slotW);
    final now = env.controller.now();
    final at = timelineNow(m, now);
    final snap = _snapMs;
    final Instant t;
    if (at != null && at >= along && at < along + shown) {
      t = Instant.fromEpochMilliseconds(now.epochMilliseconds ~/ snap * snap);
    } else {
      final edge = m.axis.fromPosition(math.min(along, math.max(0, m.axis.length - 1e-6))).epochMilliseconds;
      t = Instant.fromEpochMilliseconds((edge + snap - 1) ~/ snap * snap);
    }
    return _fitted(_hitAtRow(m, i, t));
  }

  @override
  KeyFit? fit(Hit hit) {
    final m = _now;
    if (m.axis.slots.isEmpty) return null;
    final i = _rowOf(m, hit.resourceId);
    if (i < 0) return null;
    final t = _instantOf(hit).epochMilliseconds;
    final s = m.axis.start.epochMilliseconds;
    final e = m.axis.end.epochMilliseconds;
    if (t < s) return const FitOff(next: false);
    if (t >= e) return const FitOff(next: true);
    final owner = _ownerOf(m.rows[i]);
    if (m.axis.unit == TimelineUnit.day) {
      final date = hit is DayHit ? hit.date : ZonedDateTime(Instant.fromEpochMilliseconds(t), env.zone).date;
      return FitAt(DayHit(date: date, resourceId: owner));
    }
    final ms = math.max(s, math.min(t, e - _snapMs));
    // A step along time keeps the hit's date (a time grid's column): here the date is the moment's own.
    if (hit is SlotHit && ms == t && hit.resourceId == owner && hit.date == ZonedDateTime(hit.instant, env.zone).date) {
      return FitAt(hit);
    }
    return FitAt(_hitAtRow(m, i, Instant.fromEpochMilliseconds(ms)));
  }

  @override
  Hit lineEdge(Hit hit, Edge edge) {
    final m = _now;
    final i = _rowOf(m, hit.resourceId);
    if (i < 0) return hit;
    final at = edge == Edge.start
        ? m.axis.start
        : Instant.fromEpochMilliseconds(m.axis.end.epochMilliseconds - (m.axis.unit == TimelineUnit.day ? 1 : _snapMs));
    return _fitted(_hitAtRow(m, i, at)) ?? hit;
  }

  @override
  List<EventInstance> itemsAt(Hit hit) => const [];

  /// A row's events in reading order: along time, then down its lanes.
  static List<TimelineBar> _barsOf(TimelineRow r) {
    final body = switch (r) {
      TimelineResourceRow(:final body) => body,
      TimelineAllRow(:final body) => body,
      TimelineGroupRow() => null,
    };
    if (body == null) return const [];
    return [...body.events]..sort((a, b) => a.from != b.from ? a.from.compareTo(b.from) : a.lane - b.lane);
  }

  @override
  List<EventInstance> items() {
    final seen = <String>{};
    return [
      for (final r in _now.rows)
        for (final b in _barsOf(r))
          if (seen.add(b.segment.instance.key)) b.segment.instance,
    ];
  }

  @override
  List<EventInstance> itemsAround(EventInstance instance) {
    for (final r in _now.rows) {
      final bars = _barsOf(r);
      if (bars.any((b) => b.segment.instance.key == instance.key)) {
        return [for (final b in bars) b.segment.instance];
      }
    }
    return const [];
  }

  @override
  Hit? cursorFor(EventInstance instance) {
    final m = _now;
    for (var i = 0; i < m.rows.length; i++) {
      final bar = _barsOf(m.rows[i]).where((b) => b.segment.instance.key == instance.key).firstOrNull;
      if (bar != null) return _fitted(_hitAtRow(m, i, m.axis.fromPosition(bar.from)));
    }
    return null;
  }

  @override
  Hit? firstSlot(PlainDate date, ResourceId? resourceId) => null;

  @override
  Hit? stepAcross(Hit hit, int delta) {
    final m = _now;
    final drawn = [
      for (var i = 0; i < m.rows.length; i++)
        if (m.rows[i] is! TimelineGroupRow) i,
    ];
    final k = drawn.indexWhere((i) => _ownerOf(m.rows[i]) == hit.resourceId);
    final n = (k < 0 ? 0 : k) + delta;
    if (n < 0 || n >= drawn.length) return null;
    return _fitted(_hitAtRow(m, drawn[n], _instantOf(hit)));
  }

  @override
  void reveal(Hit hit) {
    final m = _now;
    // A period the keyboard just went to: once it is built and placed.
    if (!identical(m, model)) {
      _revealLater = hit;
      return;
    }
    final i = _rowOf(m, hit.resourceId);
    if (i < 0 || _slotW <= 0) return;
    if (_h.hasClients) {
      // Along time: a slot of room before it, two after.
      final x = m.axis.toPosition(_instantOf(hit)) * _slotW;
      final laneW = math.max(0.0, _room.width - _geo.areaW);
      final p = _h.position;
      double? to;
      if (x < p.pixels + _slotW) {
        to = x - _slotW;
      } else if (x > p.pixels + laneW - 2 * _slotW) {
        to = x - laneW + 2 * _slotW;
      }
      if (to != null) _h.jumpTo(to.clamp(p.minScrollExtent, p.maxScrollExtent));
    }
    if (_v.hasClients && identical(m, model) && i < _geo.rows) {
      final top = _geo.tops[i];
      final bottom = _geo.tops[i + 1];
      final viewH = math.max(0.0, _room.height - _geo.headH);
      final p = _v.position;
      double? to;
      if (top < p.pixels) {
        to = top;
      } else if (bottom > p.pixels + viewH) {
        to = bottom - viewH;
      }
      if (to != null) _v.jumpTo(to.clamp(p.minScrollExtent, p.maxScrollExtent));
    }
  }

  /// A timeline with a step slides by it (as ◀ ▶ do), the cursor by as much on the same row.
  @override
  Hit? slide(Hit at, int direction) {
    // A cursor on days, or a period not yet built: the period changes.
    if (at is! SlotHit || !identical(_now, model) || _slotW <= 0) return null;
    final moved = _slideBy(direction, animate: false);
    if (moved == null) return null;
    final (from, to) = moved;
    final ms = axis.fromPosition(to / _slotW).epochMilliseconds - axis.fromPosition(from / _slotW).epochMilliseconds;
    final snap = _snapMs;
    // Rounded away from nothing: a view that moved takes the cursor with it.
    final by = ms.sign * (ms.abs() / snap).ceil() * snap;
    if (by == 0) return at;
    return _fitted(SlotHit(date: at.date, instant: at.instant.addMs(by), resourceId: at.resourceId)) ?? at;
  }
}

// ——— the scroller and its viewport ———

class _TimelineScroll extends TwoDimensionalScrollView {
  const _TimelineScroll({
    required this.geo,
    required super.delegate,
    required super.verticalDetails,
    required super.horizontalDetails,
    super.diagonalDragBehavior,
  });

  final _Geo geo;

  @override
  Widget buildViewport(BuildContext context, ViewportOffset verticalOffset, ViewportOffset horizontalOffset) =>
      _TimelineViewport(
        geo: geo,
        verticalOffset: verticalOffset,
        verticalAxisDirection: verticalDetails.direction,
        horizontalOffset: horizontalOffset,
        horizontalAxisDirection: horizontalDetails.direction,
        delegate: delegate,
        mainAxis: mainAxis,
        cacheExtent: cacheExtent,
        clipBehavior: clipBehavior,
      );
}

class _TimelineViewport extends TwoDimensionalViewport {
  const _TimelineViewport({
    required this.geo,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.delegate,
    required super.mainAxis,
    super.cacheExtent,
    super.clipBehavior,
  });

  final _Geo geo;

  @override
  RenderTwoDimensionalViewport createRenderObject(BuildContext context) => _RenderTimeline(
    geo: geo,
    horizontalOffset: horizontalOffset,
    horizontalAxisDirection: horizontalAxisDirection,
    verticalOffset: verticalOffset,
    verticalAxisDirection: verticalAxisDirection,
    delegate: delegate,
    mainAxis: mainAxis,
    childManager: context as TwoDimensionalChildManager,
    cacheExtent: cacheExtent,
    clipBehavior: clipBehavior,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderTimeline renderObject) {
    renderObject
      ..horizontalOffset = horizontalOffset
      ..horizontalAxisDirection = horizontalAxisDirection
      ..verticalOffset = verticalOffset
      ..verticalAxisDirection = verticalAxisDirection
      ..delegate = delegate
      ..mainAxis = mainAxis
      ..cacheExtent = cacheExtent
      ..clipBehavior = clipBehavior
      ..geo = geo;
  }
}

/// Lays out (x, y): (0, 0) the area's head, (1, 0) the time heads, (0, r+1)
/// row r's area cell, (1, r+1) its body. Rows are built where seen (and the
/// cache extent); the heads and the area are pinned, painted over the body.
class _RenderTimeline extends RenderTwoDimensionalViewport {
  _RenderTimeline({
    required _Geo geo,
    required super.horizontalOffset,
    required super.horizontalAxisDirection,
    required super.verticalOffset,
    required super.verticalAxisDirection,
    required super.delegate,
    required super.mainAxis,
    required super.childManager,
    super.cacheExtent,
    super.clipBehavior,
  }) : _geo = geo;

  _Geo _geo;
  set geo(_Geo value) {
    if (identical(value, _geo)) return;
    _geo = value;
    markNeedsLayout(withDelegateRebuild: true);
  }

  final _laid = <ChildVicinity>[];
  final _clip = LayerHandle<ClipRectLayer>();

  void _put(ChildVicinity v, Size size, Offset at) {
    final child = buildOrObtainChildFor(v);
    if (child == null) return;
    child.layout(BoxConstraints.tight(size));
    parentDataOf(child).layoutOffset = at;
    _laid.add(v);
  }

  @override
  void layoutChildSequence() {
    final g = _geo;
    final vx = horizontalOffset.pixels;
    final vy = verticalOffset.pixels;
    final size = viewportDimension;
    _laid.clear();
    final n = g.rows;
    if (n > 0) {
      final first = g.rowAt(math.max(0, vy - cacheExtent));
      final last = g.rowAt(vy + math.max(0.0, size.height - g.headH) + cacheExtent);
      for (var r = first; r <= last; r++) {
        final top = g.headH + g.tops[r] - vy;
        final h = g.tops[r + 1] - g.tops[r];
        _put(ChildVicinity(xIndex: 1, yIndex: r + 1), Size(g.axisW, h), Offset(g.areaW - vx, top));
        _put(ChildVicinity(xIndex: 0, yIndex: r + 1), Size(g.areaW, h), Offset(0, top));
      }
    }
    _put(const ChildVicinity(xIndex: 1, yIndex: 0), Size(g.axisW, g.headH), Offset(g.areaW - vx, 0));
    _put(const ChildVicinity(xIndex: 0, yIndex: 0), Size(g.areaW, g.headH), Offset.zero);
    verticalOffset.applyViewportDimension(size.height);
    verticalOffset.applyContentDimensions(0, math.max(0, g.headH + g.tops[n] - size.height));
    horizontalOffset.applyViewportDimension(size.width);
    horizontalOffset.applyContentDimensions(0, math.max(0, g.areaW + g.axisW - size.width));
  }

  /// Bodies, then the area, then the time heads, then the corner: what is pinned is over what scrolls.
  static int _layer(ChildVicinity v) => v.yIndex > 0 ? (v.xIndex == 1 ? 0 : 1) : (v.xIndex == 1 ? 2 : 3);

  Iterable<RenderBox> _inOrder({bool reverse = false}) sync* {
    final order = [..._laid]..sort((a, b) => _layer(a).compareTo(_layer(b)));
    for (final v in reverse ? order.reversed : order) {
      final child = getChildFor(v);
      if (child != null) yield child;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _clip.layer = context.pushClipRect(needsCompositing, offset, Offset.zero & size, (context, offset) {
      for (final child in _inOrder()) {
        final pd = parentDataOf(child);
        if (pd.isVisible) context.paintChild(child, offset + pd.paintOffset!);
      }
    }, oldLayer: _clip.layer);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in _inOrder(reverse: true)) {
      final pd = parentDataOf(child);
      if (!pd.isVisible) continue;
      final hit = result.addWithPaintOffset(
        offset: pd.paintOffset,
        position: position,
        hitTest: (result, transformed) => child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

// ——— the heads ———

/// The area's head: its columns' names (tablets, desktops) with handles
/// that set their widths, or a phone's button between names and initials.
class _Corner extends StatelessWidget {
  const _Corner({
    required this.env,
    required this.columns,
    required this.widths,
    required this.phone,
    required this.initials,
    required this.onInitials,
    required this.onWidth,
    required this.shown,
  });
  final CalendarEnv env;
  final List<ResourceAreaColumn> columns;
  final List<double> widths;
  final bool phone;
  final bool initials;
  final VoidCallback onInitials;
  final void Function(int column, double width) onWidth;
  final bool shown;

  @override
  Widget build(BuildContext context) {
    if (!shown) return const SizedBox.shrink();
    final style = env.style;
    final l = env.l10n;
    final border = BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: BorderDirectional(
        end: BorderSide(color: style.gridLineColor),
        bottom: BorderSide(color: style.gridLineColor),
      ),
    );
    if (phone) {
      return DecoratedBox(
        decoration: border,
        child: Center(
          child: IconButton(
            tooltip: initials ? l.widenResources : l.narrowResources,
            icon: Icon(initials ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left),
            // The arrows point the way the column grows or shrinks, mirrored right to left.
            onPressed: onInitials,
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: border,
      child: Row(
        children: [
          for (var i = 0; i < columns.length && i < widths.length; i++)
            SizedBox(
              width: widths[i],
              child: Stack(
                children: [
                  Align(
                    alignment: AlignmentDirectional.bottomStart,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 8),
                      child: Semantics(
                        header: true,
                        child: Text(
                          columns[i].header ?? (columns[i].field == 'title' ? l.resources : columns[i].field),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style.headerStyle.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    end: 0,
                    top: 0,
                    bottom: 0,
                    width: 8,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeColumn,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragUpdate: (d) {
                          final dir = Directionality.of(context) == TextDirection.rtl ? -1 : 1;
                          onWidth(i, widths[i] + dir * d.delta.dx);
                        },
                        child: Center(child: Container(width: 1, color: style.gridLineColor)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Days (or months) above, slots below. The group's name stays in view
/// while its group is; the slots are written only in the window.
class _TimeHead extends StatelessWidget {
  const _TimeHead({
    required this.env,
    required this.axis,
    required this.slotW,
    required this.window,
    required this.scroll,
  });
  final CalendarEnv env;
  final TimelineAxis axis;
  final double slotW;
  final ValueListenable<_Window> window;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final style = env.style;
    final day = axis.unit == TimelineUnit.day;
    final today = env.state.today;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: style.gridLineColor)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final half = box.maxHeight / 2;
          return Stack(
            children: [
              // The groups: a day over hours, a month over days; the name follows the scroll inside its group.
              ListenableBuilder(
                listenable: scroll,
                builder: (context, _) {
                  final seen = (scroll.hasClients ? scroll.offset : 0.0);
                  return Stack(
                    children: [
                      for (final g in axis.groups)
                        if (g.lengthMinutes > 0)
                          () {
                            final a = axis.toPosition(g.start) * slotW;
                            final b = axis.toPosition(g.end) * slotW;
                            final from = math.max(a, seen);
                            final isToday = !day && g.date == today;
                            return PositionedDirectional(
                              start: a,
                              width: b - a,
                              top: 0,
                              height: half,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: BorderDirectional(start: BorderSide(color: style.gridLineColor)),
                                ),
                                padding: EdgeInsetsDirectional.only(start: from - a + 6, top: 4, end: 4),
                                alignment: AlignmentDirectional.centerStart,
                                child: Semantics(
                                  header: true,
                                  label: day ? monthTitle(env, g.date) : env.dateLong(g.date),
                                  excludeSemantics: true,
                                  child: Text(
                                    day ? monthTitle(env, g.date) : env.date(g.date, 'MMMEd'),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.clip,
                                    style: style.headerStyle.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isToday ? style.todayColor : null,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }(),
                    ],
                  );
                },
              ),
              ValueListenableBuilder<_Window>(
                valueListenable: window,
                builder: (context, w, _) {
                  // Labels need about 40 px: on a dense scale, one every few slots.
                  final every = day ? 1 : math.max(1, (40 / slotW).ceil());
                  final slots = axis.slots;
                  final (first, last) = _slotRange(axis, w);
                  return Stack(
                    children: [
                      for (var i = first; i <= last; i++)
                        () {
                          final s = slots[i];
                          final a = axis.toPosition(s.start) * slotW;
                          final b = axis.toPosition(s.end) * slotW;
                          final labelled =
                              day ||
                              s.time == null ||
                              (s.time!.hour * 60 + s.time!.minute) ~/ axis.slotMinutes % every == 0;
                          final second = s.pass == WallPass.second;
                          final isToday = day && s.date == today;
                          final text = day
                              ? env.dayNumber(s.date)
                              : '${env.clock(s.time!, short: true)}${second ? env.l10n.secondPassMark : ''}';
                          return PositionedDirectional(
                            start: a,
                            width: math.max(0, b - a),
                            top: half,
                            bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                border: BorderDirectional(
                                  start: BorderSide(color: style.gridLineColor.withValues(alpha: 0.6), width: 0.5),
                                ),
                              ),
                              padding: const EdgeInsetsDirectional.only(start: 3, top: 2),
                              alignment: day ? Alignment.topCenter : AlignmentDirectional.topStart,
                              child: !labelled
                                  ? null
                                  : Semantics(
                                      // Said with its offset when the hour comes twice (D.6).
                                      label: day
                                          ? env.dateLong(s.date)
                                          : s.pass != null
                                          ? '${env.clock(s.time!)} (UTC${s.offset})'
                                          : env.clock(s.time!),
                                      excludeSemantics: true,
                                      child: Text(
                                        day ? '${weekdayName(env, s.date, NameWidth.narrow)}\n$text' : text,
                                        maxLines: day ? 2 : 1,
                                        softWrap: false,
                                        overflow: TextOverflow.visible,
                                        textAlign: day ? TextAlign.center : TextAlign.start,
                                        style: style.timeLabelStyle.copyWith(
                                          color: isToday ? style.todayColor : null,
                                          fontWeight: isToday ? FontWeight.w700 : null,
                                          height: day ? 1.15 : null,
                                        ),
                                      ),
                                    ),
                            ),
                          );
                        }(),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ——— the resource area ———

/// A row's head: a resource (indented by depth, its fold, its columns) or a
/// group (its fold, its name and count). Pinned at the start.
class _AreaCell extends StatelessWidget {
  const _AreaCell({
    required this.env,
    required this.row,
    required this.columns,
    required this.widths,
    required this.initials,
    required this.onToggle,
  });
  final CalendarEnv env;
  final TimelineRow row;
  final List<ResourceAreaColumn> columns;
  final List<double> widths;
  final bool initials;
  final void Function(TimelineRow row) onToggle;

  @override
  Widget build(BuildContext context) {
    final style = env.style;
    final scheme = Theme.of(context).colorScheme;
    final r = row;
    if (r is TimelineAllRow) return const SizedBox.shrink();
    final group = r is TimelineGroupRow;
    final decoration = BoxDecoration(
      color: group ? scheme.surfaceContainerHigh : scheme.surface,
      border: BorderDirectional(
        end: BorderSide(color: style.gridLineColor),
        bottom: BorderSide(color: style.gridLineColor, width: 0.5),
      ),
    );
    Widget fold(bool? expanded, String name) => expanded == null
        ? const SizedBox(width: 20)
        : SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 18,
              tooltip: expanded ? env.l10n.hideRows(name) : env.l10n.showRows(name),
              icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
              // A right-pointing chevron reads backwards right to left.
              onPressed: () => onToggle(r),
            ),
          );
    switch (r) {
      case TimelineGroupRow(:final value, :final count, :final expanded):
        final name = value.isEmpty ? '—' : value;
        return DecoratedBox(
          decoration: decoration,
          child: Row(
            children: [
              fold(expanded, name),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    initials ? _initialsOf(name) : '$name (${env.l10n.number(count)})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.headerStyle.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      case TimelineResourceRow(:final resource, :final depth, :final expanded):
        final title = resource.id == unassignedId ? env.l10n.unassigned : resource.title;
        final indent = initials ? 0.0 : math.min(depth * 12.0, 48.0);
        return DecoratedBox(
          decoration: decoration,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns.length && c < widths.length; c++)
                SizedBox(
                  width: widths[c],
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(start: c == 0 ? indent : 8, top: 6, end: 4),
                    child: c == 0
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!initials) fold(expanded, title),
                              Expanded(
                                child: Tooltip(
                                  message: initials ? title : '',
                                  child: Text(
                                    initials ? _initialsOf(title) : title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    semanticsLabel: title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(fontWeight: depth == 0 ? FontWeight.w600 : null),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            _fieldText(resource, columns[c].field),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                  ),
                ),
            ],
          ),
        );
      case TimelineAllRow():
        return const SizedBox.shrink();
    }
  }

  static String _fieldText(Resource r, String field) {
    final v = r.field(field);
    return v == null ? '' : '$v';
  }

  static String _initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    final first = words.first.characters.first;
    return words.length == 1 ? first : '$first${words.last.characters.first}';
  }
}

// ——— a row's time ———

/// A row's events on lanes, its "+N", its shading, the selection, now; a
/// group's row a band. Only what meets the window is built.
class _RowBody extends StatelessWidget {
  const _RowBody({
    required this.env,
    required this.model,
    required this.index,
    required this.slotW,
    required this.laneH,
    required this.window,
    required this.groupStarts,
    required this.snapMs,
    required this.onTap,
    required this.onPress,
  });
  final CalendarEnv env;
  final TimelineModel model;
  final Set<int> groupStarts;

  /// The keyboard cursor's length on a scale in minutes.
  final int snapMs;
  final int index;
  final double slotW;
  final double laneH;
  final ValueListenable<_Window> window;
  final void Function(double position) onTap;
  final void Function(double position, Offset global) onPress;

  TimelineAxis get axis => model.axis;

  @override
  Widget build(BuildContext context) {
    final style = env.style;
    final row = model.rows[index];
    final body = switch (row) {
      TimelineResourceRow(:final body) => body,
      TimelineAllRow(:final body) => body,
      TimelineGroupRow() => null,
    };
    if (body == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          border: Border(bottom: BorderSide(color: style.gridLineColor, width: 0.5)),
        ),
      );
    }
    final rtl = env.textDirection == TextDirection.rtl;
    final owner = row is TimelineResourceRow ? row.resource.id : null;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        double along(Offset local) => (rtl ? width - local.dx : local.dx) / slotW;
        return ValueListenableBuilder<_Window>(
          valueListenable: window,
          builder: (context, w, _) => Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => onTap(along(d.localPosition)),
                  onLongPressStart: (d) => onPress(along(d.localPosition), d.globalPosition),
                  child: ValueListenableBuilder<CalendarSelection?>(
                    valueListenable: env.controller.selectionListenable,
                    builder: (context, sel, _) => CustomPaint(
                      painter: _RowPainter(
                        axis: axis,
                        groupStarts: groupStarts,
                        window: w,
                        slotW: slotW,
                        offHours: body.offHours,
                        selected: _selected(sel, owner),
                        line: style.gridLineColor,
                        offColor: style.offHoursColor,
                        selectionColor: style.selectionColor,
                        rtl: rtl,
                      ),
                    ),
                  ),
                ),
              ),
              for (final b in body.background)
                if (w.meets(b.from, b.to))
                  PositionedDirectional(
                    start: b.from * slotW,
                    width: math.max(1, (b.to - b.from) * slotW),
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: ColoredBox(color: env.colorOf(b.segment.instance).withValues(alpha: 0.25)),
                    ),
                  ),
              for (final b in body.events)
                if (w.meets(b.from, b.to))
                  PositionedDirectional(
                    start: b.from * slotW,
                    width: math.max(6, (b.to - b.from) * slotW - 1),
                    top: 4 + b.lane * laneH,
                    height: laneH - 2,
                    child: _Bar(env: env, bar: b),
                  ),
              for (final m in body.more)
                if (w.meets(m.from, m.to))
                  PositionedDirectional(
                    start: m.from * slotW,
                    width: math.max(28, (m.to - m.from) * slotW - 1),
                    top: 4 + (model.maxLanes - 1) * laneH,
                    height: laneH - 2,
                    child: _More(env: env, axis: axis, more: m),
                  ),
              // The keyboard's cursor, when it is on this row.
              ValueListenableBuilder<Hit?>(
                valueListenable: env.interaction.keyboard.cursor,
                builder: (context, hit, _) {
                  final span = hit == null || hit.resourceId != owner ? null : _cursorSpan(hit);
                  if (span == null) return const SizedBox.shrink();
                  return PositionedDirectional(
                    start: span.from * slotW,
                    width: math.max(4, (span.to - span.from) * slotW),
                    top: 1,
                    bottom: 1,
                    child: IgnorePointer(child: CursorBox(radius: style.eventRadius)),
                  );
                },
              ),
              ValueListenableBuilder<Instant>(
                valueListenable: env.now,
                builder: (context, now, _) {
                  final at = timelineNow(model, now);
                  if (at == null) return const SizedBox.shrink();
                  return PositionedDirectional(
                    start: at * slotW - 1,
                    width: 2,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(child: ColoredBox(color: style.nowColor)),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// The cursor's stretch, in positions: its slot on a scale in days, a snap's length on one in minutes.
  TimelineSpan? _cursorSpan(Hit hit) {
    final Instant at = switch (hit) {
      SlotHit(:final instant) => instant,
      DayHit(:final date) => date.startOfDayIn(env.zone),
    };
    if (at.isBefore(axis.start) || !at.isBefore(axis.end)) return null;
    final from = axis.toPosition(at);
    final double to;
    if (hit is DayHit) {
      final s = axis.slotAt(at);
      to = s < 0 ? from + 1 : axis.toPosition(axis.slots[s].end);
    } else {
      to = axis.toPosition(
        Instant.fromEpochMilliseconds(math.min(at.epochMilliseconds + snapMs, axis.end.epochMilliseconds)),
      );
    }
    return TimelineSpan(from, math.max(to, from + 0.05));
  }

  /// The selection's stretch on this row, in positions; null when it is elsewhere.
  TimelineSpan? _selected(CalendarSelection? sel, String? owner) {
    if (sel == null) return null;
    final rid = sel.resourceId;
    if (rid != null && owner != null && rid != owner) return null;
    final zone = env.zone;
    final (Instant s, Instant e) = switch (sel) {
      TimeSelection(:final start, :final end) => (start.instant, end.instant),
      DaySelection(:final start, :final end) => (start.startOfDayIn(zone), end.startOfDayIn(zone)),
    };
    final a = axis.toPosition(s);
    final b = axis.toPosition(e);
    return b > a ? TimelineSpan(a, b) : null;
  }
}

class _RowPainter extends CustomPainter {
  _RowPainter({
    required this.axis,
    required this.groupStarts,
    required this.window,
    required this.slotW,
    required this.offHours,
    required this.selected,
    required this.line,
    required this.offColor,
    required this.selectionColor,
    required this.rtl,
  });
  final TimelineAxis axis;

  /// Where days (or months) start, in epoch ms: heavier lines.
  final Set<int> groupStarts;
  final _Window window;
  final double slotW;
  final List<TimelineSpan> offHours;
  final TimelineSpan? selected;
  final Color line;
  final Color offColor;
  final Color selectionColor;
  final bool rtl;

  double _x(double pos, Size size) => rtl ? size.width - pos * slotW : pos * slotW;

  Rect _band(double a, double b, Size size) {
    final x1 = _x(a, size);
    final x2 = _x(b, size);
    return Rect.fromLTRB(math.min(x1, x2), 0, math.max(x1, x2), size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final off = Paint()..color = offColor;
    for (final s in offHours) {
      if (window.meets(s.from, s.to)) canvas.drawRect(_band(s.from, s.to, size), off);
    }
    final sel = selected;
    if (sel != null) canvas.drawRect(_band(sel.from, sel.to, size), Paint()..color = selectionColor);
    final thin = Paint()
      ..color = line.withValues(alpha: 0.45)
      ..strokeWidth = 0.5;
    final thick = Paint()
      ..color = line
      ..strokeWidth = 1;
    final (first, last) = _slotRange(axis, window);
    for (var i = first; i <= last; i++) {
      final s = axis.slots[i];
      final p = axis.toPosition(s.start);
      final x = _x(p, size);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        groupStarts.contains(s.start.epochMilliseconds) ? thick : thin,
      );
    }
    canvas.drawLine(Offset(0, size.height - 0.25), Offset(size.width, size.height - 0.25), thin);
  }

  @override
  bool shouldRepaint(_RowPainter old) =>
      old.window != window ||
      old.slotW != slotW ||
      !identical(old.offHours, offHours) ||
      old.selected != selected ||
      !identical(old.axis, axis) ||
      old.line != line ||
      old.offColor != offColor ||
      old.selectionColor != selectionColor ||
      old.rtl != rtl;
}

/// An event on its lane: a bar with its title (and its start, room
/// permitting); a marker its line and its flag. Tap opens it; a long press
/// grabs it (across rows: to another resource), held its end's handle
/// changes its length along time.
class _Bar extends StatelessWidget {
  const _Bar({required this.env, required this.bar});
  final CalendarEnv env;
  final TimelineBar bar;

  @override
  Widget build(BuildContext context) {
    final seg = bar.segment;
    final i = seg.instance;
    final title = env.title(i);
    final when = env.span(i);
    return EventGestures(
      env: env,
      instance: i,
      label: env.l10n.eventLabel(title, when),
      draggable: true,
      resizeAxis: seg.endsHere ? Axis.horizontal : null,
      // An app's look hears the held state itself (the gestures' builder reuses this child).
      child: env.eventBuilder == null
          ? LayoutBuilder(builder: (context, box) => _look(context, box, title, when))
          : ValueListenableBuilder<String?>(
              valueListenable: env.interaction.held,
              builder: (context, _, _) => LayoutBuilder(builder: (context, box) => _look(context, box, title, when)),
            ),
    );
  }

  Widget _look(BuildContext context, BoxConstraints box, String title, String when) {
    final seg = bar.segment;
    final i = seg.instance;
    final colors = env.colorsOf(i);
    final style = env.style;
    final radius = Radius.circular(style.eventRadius);
    final own = env.eventBuilder?.call(
      context,
      i,
      EventInfo(
        segment: seg,
        size: box.biggest,
        compact: box.maxWidth < 80,
        color: colors.fill,
        onColor: colors.on,
        when: when,
        held: env.interaction.held.value == i.key,
      ),
    );
    if (own != null) return own;
    if (i.event.display == EventDisplay.marker) {
      return Row(
        children: [
          Container(width: 2, color: colors.fill),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: AlignmentDirectional.centerStart,
              decoration: BoxDecoration(
                color: colors.fill.withValues(alpha: 0.2),
                borderRadius: BorderRadiusDirectional.horizontal(end: radius),
              ),
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: style.eventStyle.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      );
    }
    final timed = i.event is TimedEvent;
    final text = timed && seg.startsHere && box.maxWidth >= 96 ? '${env.time(seg.from)} $title' : title;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadiusDirectional.horizontal(
          start: seg.startsHere ? radius : Radius.zero,
          end: seg.endsHere ? radius : Radius.zero,
        ),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: style.eventStyle.copyWith(color: colors.on),
      ),
    );
  }
}

/// "+N": the events a full row does not draw, in a sheet.
class _More extends StatelessWidget {
  const _More({required this.env, required this.axis, required this.more});
  final CalendarEnv env;
  final TimelineAxis axis;
  final TimelineMore more;

  @override
  Widget build(BuildContext context) {
    final date = ZonedDateTime(axis.fromPosition(more.from), env.zone).date;
    final n = more.events.length;
    return Semantics(
      button: true,
      label: env.l10n.moreLabel(n, env.dateLong(date)),
      excludeSemantics: true,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(env.style.eventRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(env.style.eventRadius),
          onTap: () => showDaySheet(context, env, date, [for (final e in more.events) e.segment]),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                env.l10n.moreLink(n),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: env.style.eventStyle.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
