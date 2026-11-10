import 'dart:math' as math;

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:dzcalendar_core/internal.dart' show UniformSizes, visibleRange;
import 'package:flutter/material.dart';

import '../env.dart';
import '../interaction.dart';
import '../keyboard.dart';
import 'common.dart';
import 'day_grid_view.dart' show DayNumber;

/// A time grid (`timeGrid*`, `resourceTimeGrid*`): day columns down a
/// time axis, an all-day row above. A day with a clock change is drawn as
/// it is: the skipped hour a band nobody lands in, the repeated hour a band
/// with both readings. Columns narrower than the theme's `minColumnWidth`
/// scroll sideways, and only those on screen are built.
class TimeGridView extends StatefulWidget {
  const TimeGridView({super.key, required this.env, required this.model, this.scrollHour = 7});

  final CalendarEnv env;
  final TimeGridModel model;

  /// The hour shown at the top at first.
  final int scrollHour;

  @override
  State<TimeGridView> createState() => _TimeGridViewState();
}

class _TimeGridViewState extends State<TimeGridView> implements DragSurface, KeySurface {
  ScrollController? _vertical;

  // What the gestures read: the scrolled body, its content, the all-day row.
  final _viewportKey = GlobalKey();
  final _contentKey = GlobalKey();
  final _allDayKey = GlobalKey();
  var _ppmNow = 1.0;
  var _colW = 0.0;

  // The day heads, the all-day row and the body scroll sideways together.
  final _heads = ScrollController();
  final _allDay = ScrollController();
  final _body = ScrollController();
  var _syncing = false;

  CalendarEnv get env => widget.env;
  TimeGridModel get model => widget.model;

  /// Pixels per axis minute: the theme's hour, taller with a larger text size
  /// (up to twice) so labels and titles keep their room.
  double _ppm(BuildContext context) =>
      env.style.hourHeight * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0) / 60;

  @override
  void initState() {
    super.initState();
    for (final c in [_heads, _allDay, _body]) {
      c.addListener(() => _sync(c));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _vertical ??= ScrollController(initialScrollOffset: _initialOffset(_ppm(context)));
  }

  double _initialOffset(double ppm) {
    for (final t in model.gutter) {
      if (t.label.hour == widget.scrollHour && t.label.minute == 0) return math.max(0, t.position * ppm - 8);
    }
    return 0;
  }

  void _sync(ScrollController from) {
    if (_syncing || from.positions.length != 1) return;
    _syncing = true;
    for (final to in [_heads, _allDay, _body]) {
      if (identical(to, from) || to.positions.length != 1) continue;
      final p = to.position;
      to.jumpTo(from.offset.clamp(p.minScrollExtent, p.maxScrollExtent));
    }
    _syncing = false;
  }

  @override
  void dispose() {
    env.interaction.detach(this);
    env.interaction.keyboard.detach(this);
    _vertical?.dispose();
    _heads.dispose();
    _allDay.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = env.style;
    final n = model.columns.length;
    if (n == 0) return Center(child: Text(env.l10n.noResources));
    final ppm = _ppm(context);
    _ppmNow = ppm;
    env.interaction.attach(this);
    env.interaction.keyboard.attach(this);
    final height = model.columns.fold<double>(0, (m, c) => math.max(m, c.axis.length)) * ppm;
    return LayoutBuilder(
      builder: (context, box) {
        final avail = math.max(0.0, box.maxWidth - style.gutterWidth);
        final colW = math.max(avail / n, style.minColumnWidth);
        _colW = colW;
        final total = colW * n;
        final scrolls = total > avail + 0.5;
        Widget sideways(ScrollController c, Widget child) => scrolls
            ? SingleChildScrollView(
                controller: c,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(width: total, child: child),
              )
            : child;
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(width: style.gutterWidth, child: _weekNumber()),
                Expanded(
                  child: sideways(
                    _heads,
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (model.groupHeads.isNotEmpty)
                          ResourceGroupRow(env: env, groups: model.groupHeads, heads: model.resourceHeads),
                        if (model.resourceHeads.isNotEmpty)
                          ResourceHeadRow(env: env, heads: model.resourceHeads, cells: n),
                        _DayHeads(env: env, model: model),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (model.allDay.lanes > 0)
              Row(
                children: [
                  SizedBox(
                    width: style.gutterWidth,
                    child: Text(env.l10n.allDay, textAlign: TextAlign.center, style: style.timeLabelStyle, maxLines: 2),
                  ),
                  Expanded(
                    child: sideways(_allDay, _AllDayRow(key: _allDayKey, env: env, model: model, colW: colW)),
                  ),
                ],
              ),
            Divider(height: 1, color: style.gridLineColor),
            Expanded(
              child: SingleChildScrollView(
                key: _viewportKey,
                controller: _vertical,
                child: SizedBox(
                  height: height,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: style.gutterWidth,
                        height: height,
                        child: _Gutter(env: env, ticks: model.gutter, ppm: ppm),
                      ),
                      Expanded(
                        child: scrolls
                            ? _VirtualColumns(
                                contentKey: _contentKey,
                                env: env,
                                model: model,
                                controller: _body,
                                colW: colW,
                                height: height,
                                ppm: ppm,
                              )
                            : Row(
                                key: _contentKey,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (var i = 0; i < n; i++)
                                    Expanded(
                                      child: _Column(env: env, model: model, index: i, ppm: ppm),
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ——— the gestures' surface ———

  RenderBox? _box(GlobalKey k) {
    final b = k.currentContext?.findRenderObject();
    return b is RenderBox && b.attached && b.hasSize ? b : null;
  }

  Rect _global(RenderBox b, Rect local) => MatrixUtils.transformRect(b.getTransformTo(null), local);

  /// The columns' part of the scrolled body, on screen (the gutter left out).
  Rect? _columnsArea() {
    final vp = _box(_viewportKey);
    if (vp == null) return null;
    final r = _global(vp, Offset.zero & vp.size);
    final g = env.style.gutterWidth;
    return env.textDirection == TextDirection.ltr
        ? Rect.fromLTRB(r.left + g, r.top, r.right, r.bottom)
        : Rect.fromLTRB(r.left, r.top, r.right - g, r.bottom);
  }

  /// Column index at [x] along a box [width] wide, start side first.
  int _columnAt(double x, double width) {
    final n = model.columns.length;
    final w = width / n;
    final along = env.textDirection == TextDirection.ltr ? x : width - x;
    return (along / w).floor().clamp(0, n - 1);
  }

  /// Column [i]'s start edge in a box [width] wide.
  double _columnX(int i, double width) {
    final w = width / model.columns.length;
    return env.textDirection == TextDirection.ltr ? i * w : width - (i + 1) * w;
  }

  bool _inAllDay(Offset g) {
    final row = _box(_allDayKey);
    return row != null && _global(row, Offset.zero & row.size).contains(g);
  }

  static bool _resourceOk(TimeGridColumn c, CalEvent ev) {
    final r = c.resource;
    if (r == null) return true;
    return ev.resourceIds.isEmpty ? r.id == unassignedId : ev.resourceIds.contains(r.id);
  }

  @override
  Hit? hitAt(Offset g) {
    if (model.columns.isEmpty) return null;
    final row = _box(_allDayKey);
    if (row != null && _inAllDay(g)) {
      return allDayHitAt(model, _columnAt(row.globalToLocal(g).dx, row.size.width));
    }
    final area = _columnsArea();
    final content = _box(_contentKey);
    if (area == null || content == null) return null;
    final p = Offset(g.dx.clamp(area.left, area.right - 0.5), g.dy.clamp(area.top, area.bottom - 0.5));
    final l = content.globalToLocal(p);
    return slotHitAt(model, _columnAt(l.dx, content.size.width), l.dy / _ppmNow, env.config.snapMinutes);
  }

  @override
  List<GhostBox> boxesFor(CalEvent ev) {
    final out = <GhostBox>[];
    final n = model.columns.length;
    switch (ev) {
      case TimedEvent(:final start, :final end):
        final content = _box(_contentKey);
        final area = _columnsArea();
        if (content == null || area == null) return out;
        final width = content.size.width;
        for (var i = 0; i < n; i++) {
          final c = model.columns[i];
          if (c.folded || !_resourceOk(c, ev)) continue;
          final s = start.instant.isBefore(c.axis.start) ? c.axis.start : start.instant;
          final e = end.instant.isAfter(c.axis.end) ? c.axis.end : end.instant;
          if (!s.isBefore(e)) continue;
          final top = c.axis.toPosition(s) * _ppmNow;
          final bottom = math.max(c.axis.toEndPosition(e) * _ppmNow, top + 6);
          final x = _columnX(i, width);
          out.add((
            rect: _global(content, Rect.fromLTRB(x + 1, top + 0.5, x + width / n - 1, bottom - 0.5)),
            clip: area,
          ));
        }
      case AllDayEvent(:final start, :final end):
        final row = _box(_allDayKey);
        final area = _columnsArea();
        if (row == null || area == null) return out;
        final rowRect = _global(row, Offset.zero & row.size);
        final clip = Rect.fromLTRB(area.left, rowRect.top, area.right, rowRect.bottom);
        final width = row.size.width;
        final w = width / n;
        int? first;
        void close(int last) {
          final a = _columnX(first!, width);
          final b = _columnX(last, width);
          final left = math.min(a, b);
          out.add((
            rect: _global(row, Rect.fromLTWH(left + 1, 2, (last - first! + 1) * w - 2, env.style.barHeight)),
            clip: clip,
          ));
          first = null;
        }

        for (var i = 0; i < n; i++) {
          final c = model.columns[i];
          final inside = !c.date.isBefore(start) && c.date.isBefore(end) && _resourceOk(c, ev);
          if (inside) first ??= i;
          if (!inside && first != null) close(i - 1);
        }
        if (first != null) close(n - 1);
    }
    return out;
  }

  @override
  bool autoscroll(Offset g, double seconds) {
    final area = _columnsArea();
    if (area == null) return false;
    const edge = 40.0;
    const speed = 900.0; // pixels a second at the very edge
    var moved = false;
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

    final v = _vertical;
    if (v != null && !_inAllDay(g)) {
      moved |= scroll(v, push(g.dy - area.top, area.bottom - g.dy).clamp(-1.5, 1.5) * speed * seconds);
    }
    final ltr = env.textDirection == TextDirection.ltr;
    final toStart = ltr ? g.dx - area.left : area.right - g.dx;
    final toEnd = ltr ? area.right - g.dx : g.dx - area.left;
    moved |= scroll(_body, push(toStart, toEnd).clamp(-1.5, 1.5) * speed * seconds);
    return moved;
  }

  @override
  bool canResize(CalEvent event) => true;

  // ——— the keyboard's surface (decision 41) ———

  /// The model as the controller has it now: a period the keyboard just went
  /// to is known before it is built.
  TimeGridModel get _now => switch (env.controller.model) {
    TimeGridViewModel(:final model) => model,
    _ => model,
  };

  int get _snap => env.config.snapMinutes < 1 ? 1 : env.config.snapMinutes;

  @override
  KeyGrid get keyGrid => KeyGrid.time;

  @override
  bool get allDayRow => _now.allDay.lanes > 0;

  @override
  bool get resourceView => _now.resourceHeads.isNotEmpty;

  /// The column of [date] (and [resourceId]'s, when given), by index.
  int _indexOf(TimeGridModel m, PlainDate date, ResourceId? resourceId) =>
      m.columns.indexWhere((c) => c.date == date && (resourceId == null || c.resource?.id == resourceId));

  SlotHit _slot(TimeGridModel m, int i, Instant at) {
    final c = m.columns[i];
    return SlotHit(date: c.date, instant: at, resourceId: c.resource?.id);
  }

  /// The first slot in view on column [i] (the top of its hours when not built yet).
  Hit? _topSlot(TimeGridModel m, int i) {
    final c = m.columns[i];
    if (c.folded || c.axis.length == 0) return null;
    final v = _vertical;
    final top = v != null && v.hasClients ? v.offset / _ppmNow : 0.0;
    final at = ((top / _snap).ceil() * _snap).toDouble().clamp(0.0, math.max(0.0, c.axis.length - _snap).toDouble());
    return slotHitAt(m, i, at, _snap);
  }

  @override
  Hit? home() {
    final m = _now;
    final today = env.state.today;
    var i = m.columns.indexWhere((c) => c.date == today && !c.folded);
    if (i < 0) i = m.columns.indexWhere((c) => !c.folded);
    if (i < 0) return null;
    final c = m.columns[i];
    // Today with now in view: the slot of now; else the first slot in view.
    if (c.date == today) {
      final now = env.controller.now();
      final v = _vertical;
      if (!now.isBefore(c.axis.start) && now.isBefore(c.axis.end) && v != null && v.hasClients) {
        final at = (c.axis.toPosition(now) / _snap).floor() * _snap.toDouble();
        final y = at * _ppmNow;
        if (y >= v.offset && (at + _snap) * _ppmNow <= v.offset + v.position.viewportDimension) {
          return slotHitAt(m, i, at, _snap);
        }
      }
    }
    return _topSlot(m, i);
  }

  @override
  KeyFit? fit(Hit hit) {
    final m = _now;
    if (m.columns.isEmpty) return null;
    final i = _indexOf(m, hit.date, hit.resourceId);
    if (i < 0) {
      final st = env.state;
      // A hidden weekday: null, and the keyboard steps on past it.
      if (st.view.hiddenDays.contains(hit.date.dayOfWeek)) return null;
      if (hit.date.isBefore(st.range.start)) return const FitOff(next: false);
      return !hit.date.isBefore(st.range.end) ? const FitOff(next: true) : null;
    }
    final c = m.columns[i];
    if (hit is DayHit) {
      if (!allDayRow) {
        final top = _topSlot(m, i);
        return top == null ? null : FitAt(top);
      }
      return FitAt(DayHit(date: c.date, allDayRow: true, resourceId: c.resource?.id));
    }
    if (c.folded || c.axis.length == 0) return null;
    final h = hit as SlotHit;
    final s = c.axis.start.epochMilliseconds;
    final last = math.max(s, c.axis.end.epochMilliseconds - _snap * 60000);
    final ms = h.instant.epochMilliseconds.clamp(s, last);
    if (ms == h.instant.epochMilliseconds && h.resourceId == c.resource?.id) return FitAt(h);
    return FitAt(
      SlotHit(
        date: c.date,
        instant: Instant.fromEpochMilliseconds(ms),
        gap: h.gap && ms == h.instant.epochMilliseconds,
        resourceId: c.resource?.id,
      ),
    );
  }

  @override
  Hit lineEdge(Hit hit, Edge edge) {
    final m = _now;
    if (hit is DayHit) {
      // The all-day row's line: the same resource's first or last day.
      final same = [
        for (var i = 0; i < m.columns.length; i++)
          if (hit.resourceId == null || m.columns[i].resource?.id == hit.resourceId) i,
      ];
      if (same.isEmpty) return hit;
      final c = m.columns[edge == Edge.start ? same.first : same.last];
      return DayHit(date: c.date, allDayRow: true, resourceId: c.resource?.id);
    }
    final i = _indexOf(m, hit.date, hit.resourceId);
    if (i < 0 || m.columns[i].folded) return hit;
    final c = m.columns[i];
    return edge == Edge.start
        ? _slot(m, i, c.axis.start)
        : _slot(
            m,
            i,
            Instant.fromEpochMilliseconds(
              math.max(c.axis.start.epochMilliseconds, c.axis.end.epochMilliseconds - _snap * 60000),
            ),
          );
  }

  @override
  List<EventInstance> itemsAt(Hit hit) => const [];

  List<EventInstance> _allDayItems(TimeGridModel m) {
    final bars = [...m.allDay.bars]..sort((a, b) => a.column != b.column ? a.column - b.column : a.lane - b.lane);
    return [for (final b in bars) b.segment.instance];
  }

  List<EventInstance> _columnItems(TimeGridColumn c) {
    final placed = [...c.events]..sort((a, b) => a.top != b.top ? a.top.compareTo(b.top) : a.left.compareTo(b.left));
    return [for (final p in placed) p.segment.instance];
  }

  static List<EventInstance> _unique(Iterable<EventInstance> all) {
    final seen = <String>{};
    return [
      for (final i in all)
        if (seen.add(i.key)) i,
    ];
  }

  @override
  List<EventInstance> items() {
    final m = _now;
    return _unique([..._allDayItems(m), for (final c in m.columns) ..._columnItems(c)]);
  }

  @override
  List<EventInstance> itemsAround(EventInstance instance) {
    final m = _now;
    for (final c in m.columns) {
      final here = _columnItems(c);
      if (here.any((x) => x.key == instance.key)) return _unique(here);
    }
    return _unique(_allDayItems(m));
  }

  @override
  Hit? cursorFor(EventInstance instance) {
    final m = _now;
    for (var i = 0; i < m.columns.length; i++) {
      final c = m.columns[i];
      final p = c.events.where((p) => p.segment.instance.key == instance.key).firstOrNull;
      if (p != null) {
        final f = fit(_slot(m, i, p.segment.from));
        return f is FitAt ? f.hit : null;
      }
    }
    final bar = m.allDay.bars.where((b) => b.segment.instance.key == instance.key).firstOrNull;
    if (bar == null || bar.column >= m.columns.length) return null;
    final c = m.columns[bar.column];
    return DayHit(date: c.date, allDayRow: true, resourceId: c.resource?.id);
  }

  @override
  Hit? firstSlot(PlainDate date, ResourceId? resourceId) {
    final m = _now;
    final i = _indexOf(m, date, resourceId);
    return i < 0 ? null : _topSlot(m, i);
  }

  @override
  Hit? stepAcross(Hit hit, int delta) {
    final m = _now;
    final heads = m.resourceHeads;
    if (heads.isEmpty) return null;
    final k = heads.indexWhere((h) => h.resource.id == hit.resourceId);
    final n = (k < 0 ? 0 : k) + delta;
    if (n < 0 || n >= heads.length) return null;
    final id = heads[n].resource.id;
    if (_indexOf(m, hit.date, id) < 0) return null;
    final moved = switch (hit) {
      SlotHit() => SlotHit(date: hit.date, instant: hit.instant, gap: hit.gap, resourceId: id),
      DayHit() => DayHit(date: hit.date, allDayRow: hit.allDayRow, resourceId: id),
    };
    final f = fit(moved);
    return f is FitAt ? f.hit : null;
  }

  @override
  void reveal(Hit hit) {
    final m = _now;
    final i = _indexOf(m, hit.date, hit.resourceId);
    if (i < 0) return;
    // Sideways: its column in view.
    if (_body.hasClients && _body.positions.length == 1 && _colW > 0) {
      final p = _body.position;
      final x = i * _colW;
      final to = x < p.pixels
          ? x
          : (x + _colW > p.pixels + p.viewportDimension ? x + _colW - p.viewportDimension : p.pixels);
      if (to != p.pixels) _body.jumpTo(to.clamp(p.minScrollExtent, p.maxScrollExtent));
    }
    final v = _vertical;
    if (hit is! SlotHit || v == null || !v.hasClients) return;
    final c = m.columns[i];
    if (c.folded) return;
    final y = c.axis.toPosition(hit.instant) * _ppmNow;
    final room = _snap * _ppmNow * 2;
    final p = v.position;
    double? to;
    if (y - room < p.pixels) {
      to = y - room;
    } else if (y + room > p.pixels + p.viewportDimension) {
      to = y + room - p.viewportDimension;
    }
    if (to != null) v.jumpTo(to.clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  Widget _weekNumber() {
    final first = model.range.dates.isEmpty ? null : model.range.dates.first;
    if (first == null) return const SizedBox.shrink();
    final week = weekNumber(first, weekRulesFor(env.locale));
    return Semantics(
      label: env.l10n.weekLabel(week),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(env.l10n.weekShort(week), textAlign: TextAlign.center, style: env.style.timeLabelStyle),
      ),
    );
  }
}

/// The columns on screen, and one more each side, in a sideways scroll:
/// built again only when that window changes, not at each scrolled pixel.
class _VirtualColumns extends StatefulWidget {
  const _VirtualColumns({
    required this.contentKey,
    required this.env,
    required this.model,
    required this.controller,
    required this.colW,
    required this.height,
    required this.ppm,
  });
  final GlobalKey contentKey;
  final CalendarEnv env;
  final TimeGridModel model;
  final ScrollController controller;
  final double colW;
  final double height;
  final double ppm;

  @override
  State<_VirtualColumns> createState() => _VirtualColumnsState();
}

class _VirtualColumnsState extends State<_VirtualColumns> {
  var _width = 0.0;
  ({int first, int last})? _window;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrolled);
  }

  @override
  void didUpdateWidget(_VirtualColumns old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_scrolled);
      widget.controller.addListener(_scrolled);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrolled);
    super.dispose();
  }

  ({int first, int last}) _visible() {
    final c = widget.controller;
    final r = visibleRange(
      UniformSizes(widget.colW, widget.model.columns.length),
      c.hasClients ? c.offset : 0.0,
      _width,
      1,
    );
    return (first: r.first, last: r.last);
  }

  void _scrolled() {
    if (_visible() != _window) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final n = w.model.columns.length;
    return LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        final r = _window = _visible();
        return SingleChildScrollView(
          controller: w.controller,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            key: w.contentKey,
            width: w.colW * n,
            height: w.height,
            child: Stack(
              children: [
                for (var i = r.first; i <= r.last; i++)
                  PositionedDirectional(
                    key: ValueKey(w.model.columns[i].key),
                    start: i * w.colW,
                    width: w.colW,
                    top: 0,
                    height: w.height,
                    child: _Column(env: w.env, model: w.model, index: i, ppm: w.ppm),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayHeads extends StatelessWidget {
  const _DayHeads({required this.env, required this.model});
  final CalendarEnv env;
  final TimeGridModel model;

  @override
  Widget build(BuildContext context) {
    final days = model.range.dates.length;
    return Row(
      children: [
        for (final col in model.columns)
          Expanded(
            child: Semantics(
              header: true,
              label: col.resource == null
                  ? env.dateLong(col.date)
                  : env.l10n.ofResource(
                      col.resource!.id == unassignedId ? env.l10n.unassigned : col.resource!.title,
                      env.dateLong(col.date),
                    ),
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text(
                      weekdayName(env, col.date, days > 3 ? NameWidth.narrow : NameWidth.short),
                      style: env.style.headerStyle,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 2),
                    DayNumber(env: env, date: col.date, today: env.isToday(col.date)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AllDayRow extends StatelessWidget {
  const _AllDayRow({super.key, required this.env, required this.model, required this.colW});
  final CalendarEnv env;
  final TimeGridModel model;
  final double colW;

  @override
  Widget build(BuildContext context) {
    final style = env.style;
    final lane = style.barHeight + 2;
    final n = model.columns.length;
    return LayoutBuilder(
      builder: (context, box) {
        final cw = box.maxWidth.isFinite ? box.maxWidth / n : colW;
        return SizedBox(
          height: model.allDay.lanes * lane + 4,
          child: Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _tap(i),
                        onLongPressStart: (d) {
                          final c = model.columns[i];
                          final hit = allDayHitAt(model, i);
                          final target = DayTarget(date: c.date, resourceId: c.resource?.id);
                          if (hit == null) return;
                          env.interaction.pressEmpty(hit, target, d.globalPosition);
                        },
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: BorderDirectional(start: BorderSide(color: style.gridLineColor, width: 0.5)),
                          ),
                          child: ValueListenableBuilder<Hit?>(
                            valueListenable: env.interaction.keyboard.cursor,
                            builder: (context, hit, _) {
                              final c = model.columns[i];
                              final here =
                                  hit is DayHit &&
                                  hit.date == c.date &&
                                  (hit.resourceId == null || hit.resourceId == c.resource?.id);
                              return here ? CursorBox(radius: style.eventRadius) : const SizedBox.expand();
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              for (final b in model.allDay.background)
                PositionedDirectional(
                  start: b.column * cw,
                  width: b.segment.dayCount * cw,
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    child: ColoredBox(color: env.colorOf(b.segment.instance).withValues(alpha: 0.25)),
                  ),
                ),
              for (final b in model.allDay.bars)
                PositionedDirectional(
                  start: b.column * cw + 1,
                  width: b.segment.dayCount * cw - 2,
                  top: 2 + b.lane * lane,
                  height: style.barHeight,
                  child: EventBar(env: env, segment: b.segment),
                ),
            ],
          ),
        );
      },
    );
  }

  void _tap(int i) {
    final hit = allDayHitAt(model, i);
    if (hit != null && env.interaction.keyboard.putAt(hit)) return;
    env.interaction.release();
    if (hit == null) return;
    env.interaction.keyboard.tapped(hit);
    env.onDateTap?.call(hit);
    final sel = selectionBetween(env.controller.kernel.interactionContext(snapMinutes: 1), hit, hit);
    env.controller.select(sel);
    env.selected(sel);
  }
}

/// The hours down the left (the right, right to left): the major ticks of an
/// ordinary day; a repeated hour's second pass marked.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.env, required this.ticks, required this.ppm});
  final CalendarEnv env;
  final List<AxisTick> ticks;
  final double ppm;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      for (final t in ticks)
        if (t.major)
          PositionedDirectional(
            start: 0,
            end: 4,
            top: math.max(0, t.position * ppm - 7),
            child: Text(
              env.clock(t.label, short: true) + (t.pass == WallPass.second ? env.l10n.secondPassMark : ''),
              textAlign: TextAlign.end,
              style: env.style.timeLabelStyle.copyWith(decoration: t.skipped ? TextDecoration.lineThrough : null),
              maxLines: 1,
            ),
          ),
    ],
  );
}

/// One day column: its lines and bands painted, then what is in it.
class _Column extends StatelessWidget {
  const _Column({required this.env, required this.model, required this.index, required this.ppm});
  final CalendarEnv env;
  final TimeGridModel model;
  final int index;
  final double ppm;

  TimeGridColumn get col => model.columns[index];

  @override
  Widget build(BuildContext context) {
    final style = env.style;
    final c = col;
    if (c.folded) {
      return Container(
        color: style.offHoursColor,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.all(4),
        child: Text(env.l10n.dayDoesNotExist, style: style.timeLabelStyle, textAlign: TextAlign.center),
      );
    }
    final snap = model.options.slotMinutes.round();
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _tap(d.localPosition.dy / ppm, snap),
          onLongPressStart: (d) {
            final minutes = d.localPosition.dy / ppm;
            final target = slotTargetAt(model, index, minutes);
            final hit = slotHitAt(model, index, minutes, env.config.snapMinutes);
            if (target != null && hit != null) env.interaction.pressEmpty(hit, target, d.globalPosition);
          },
          child: CustomPaint(
            painter: _ColumnPainter(
              ticks: c.axis.ticks(model.options.slotMinutes, model.options.labelMinutes),
              offHours: c.offHours,
              ppm: ppm,
              line: style.gridLineColor,
              offColor: style.offHoursColor,
              textDirection: env.textDirection,
            ),
            child: Stack(
              children: [
                for (final p in c.background)
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    top: p.top * ppm,
                    height: math.max(1, p.height * ppm),
                    child: IgnorePointer(
                      child: ColoredBox(color: env.colorOf(p.segment.instance).withValues(alpha: 0.25)),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<CalendarSelection?>(
                      valueListenable: env.controller.selectionListenable,
                      builder: (context, sel, _) {
                        final span = _selectionSpan(sel);
                        if (span == null) return const SizedBox.shrink();
                        return Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: span.$1 * ppm,
                              height: math.max(2, (span.$2 - span.$1) * ppm),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: style.selectionColor,
                                  borderRadius: BorderRadius.circular(style.eventRadius),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                for (final s in c.slots)
                  PositionedDirectional(
                    start: 1,
                    end: 1,
                    top: s.top * ppm + 1,
                    height: math.max(4, s.height * ppm - 2),
                    child: _SlotBox(env: env, placed: s),
                  ),
                for (final p in c.events)
                  PositionedDirectional(
                    start: p.left * w + 1,
                    width: math.max(4, p.width * w - 2),
                    top: p.top * ppm + 0.5,
                    height: math.max(6, p.visualHeight * ppm - 1),
                    child: _TimedBox(env: env, placed: p, ppm: ppm),
                  ),
                for (final m in c.more)
                  PositionedDirectional(
                    start: m.left * w + 1,
                    width: math.max(4, m.width * w - 2),
                    top: m.top * ppm,
                    height: math.max(16, m.height * ppm),
                    child: _MoreBox(env: env, more: m, date: c.date),
                  ),
                // Over the events: one across a clock change shows the hour it spans that does not exist (or happens twice).
                for (final b in c.axis.bands) _band(b),
                // The keyboard's cursor, when it is in this column.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<Hit?>(
                      valueListenable: env.interaction.keyboard.cursor,
                      builder: (context, hit, _) {
                        if (hit is! SlotHit ||
                            hit.date != c.date ||
                            (hit.resourceId != null && hit.resourceId != c.resource?.id)) {
                          return const SizedBox.shrink();
                        }
                        final top = c.axis.toPosition(hit.instant);
                        final end = c.axis.toEndPosition(hit.instant.addMs(env.config.snapMinutes * 60000));
                        return Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: top * ppm,
                              height: math.max(4, (end - top) * ppm),
                              child: CursorBox(radius: style.eventRadius),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<Instant>(
                      valueListenable: env.now,
                      builder: (context, now, _) {
                        if (now.isBefore(c.axis.start) || !now.isBefore(c.axis.end)) return const SizedBox.shrink();
                        return Stack(
                          children: [
                            Positioned(
                              left: 0,
                              right: 0,
                              top: c.axis.toPosition(now) * ppm - 1,
                              height: 2,
                              child: Semantics(
                                label: env.l10n.now,
                                child: ColoredBox(color: style.nowColor),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Where the current selection crosses this column, in axis minutes.
  (double, double)? _selectionSpan(CalendarSelection? sel) {
    if (sel is! TimeSelection) return null;
    final c = col;
    if (sel.resourceId != null && sel.resourceId != c.resource?.id) return null;
    final s = sel.start.instant;
    final e = sel.end.instant;
    if (!s.isBefore(c.axis.end) || !c.axis.start.isBefore(e)) return null;
    return (c.axis.toPosition(s), c.axis.toEndPosition(e));
  }

  Widget _band(AxisBand b) {
    final t = b.transition;
    final gap = b.kind == TransitionKind.gap;
    final (from, to) = gap ? (t.wallBefore.time, t.wallAfter.time) : (t.wallAfter.time, t.wallBefore.time);
    final text = gap
        ? env.l10n.gapBand(env.clock(from), env.clock(to))
        : env.l10n.repeatBand(env.clock(from), env.clock(to));
    final h = math.max((b.to - b.from) * ppm, 14.0);
    final color = gap ? env.style.gapBandColor : env.style.repeatBandColor;
    return PositionedDirectional(
      start: 0,
      end: 0,
      top: b.from * ppm,
      height: h,
      child: IgnorePointer(
        child: Semantics(
          label: text,
          child: Container(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 2),
            alignment: AlignmentDirectional.bottomEnd,
            decoration: BoxDecoration(
              color: color.withValues(alpha: color.a * 0.55),
              border: Border.symmetric(horizontal: BorderSide(color: color, width: 1)),
            ),
            child: Text(
              text,
              maxLines: h >= 28 ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: env.style.timeLabelStyle.copyWith(fontSize: 9, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  void _tap(double minutes, int snap) {
    final hit = slotHitAt(model, index, minutes, snap);
    if (hit != null && env.interaction.keyboard.putAt(hit)) return;
    env.interaction.release();
    if (hit == null) return;
    // The keyboard goes on from the slot tapped, on its own snap.
    env.interaction.keyboard.tapped(slotHitAt(model, index, minutes, env.config.snapMinutes) ?? hit);
    env.onDateTap?.call(hit);
    final ctx = env.controller.kernel.interactionContext(snapMinutes: snap);
    final sel = selectionBetween(ctx, hit, hit);
    env.controller.select(sel);
    env.selected(sel);
  }
}

class _ColumnPainter extends CustomPainter {
  _ColumnPainter({
    required this.ticks,
    required this.offHours,
    required this.ppm,
    required this.line,
    required this.offColor,
    required this.textDirection,
  });
  final List<AxisTick> ticks;
  final List<({double top, double height})> offHours;
  final double ppm;
  final Color line;
  final Color offColor;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final off = Paint()..color = offColor;
    for (final o in offHours) {
      canvas.drawRect(Rect.fromLTWH(0, o.top * ppm, size.width, o.height * ppm), off);
    }
    final major = Paint()
      ..color = line
      ..strokeWidth = 0.5;
    final minor = Paint()
      ..color = line.withValues(alpha: line.a * 0.45)
      ..strokeWidth = 0.5;
    for (final t in ticks) {
      final y = t.position * ppm;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), t.major ? major : minor);
    }
    // The column's edge on its start side.
    final x = textDirection == TextDirection.ltr ? 0.0 : size.width;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
  }

  @override
  bool shouldRepaint(_ColumnPainter old) =>
      !_sameTicks(old.ticks, ticks) ||
      old.offHours != offHours ||
      old.ppm != ppm ||
      old.line != line ||
      old.offColor != offColor ||
      old.textDirection != textDirection;
}

/// Ticks are made again at each build: equal ones need no repaint.
bool _sameTicks(List<AxisTick> a, List<AxisTick> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].position != b[i].position || a[i].major != b[i].major) return false;
  }
  return true;
}

/// A timed event in its column: title, then its time when there is room;
/// on a day with a clock change, which reading ("02:30*") and its real length.
class _TimedBox extends StatelessWidget {
  const _TimedBox({required this.env, required this.placed, required this.ppm});
  final CalendarEnv env;
  final PlacedTimed placed;
  final double ppm;

  @override
  Widget build(BuildContext context) {
    final style = env.style;
    final i = placed.segment.instance;
    final colors = env.colorsOf(i);
    final title = env.title(i);
    final mark = env.l10n.secondPassMark;
    // The event's times, not the piece's: an event cut at a clock change
    // still reads 01:30 – 03:30 on both pieces, its readings marked.
    final seg = placed.segment;
    final (from, to) = switch (i.event) {
      TimedEvent(:final start, :final end) => (start.instant, end.instant),
      AllDayEvent() => (seg.from, seg.to),
    };
    final start = env.time(from) + (placed.startReading?.pass == WallPass.second ? mark : '');
    final end = env.time(to) + (placed.endReading?.pass == WallPass.second ? mark : '');
    final when = env.l10n.range(start, end);
    final tall = placed.visualHeight * ppm;
    final text = style.eventStyle.copyWith(color: colors.on, height: 1.2);
    final lineHeight = (text.fontSize ?? 11) * 1.2;
    return EventGestures(
      env: env,
      instance: i,
      label: env.l10n.eventLabel(title, when),
      draggable: true,
      resizeAxis: seg.endsHere ? Axis.vertical : null,
      child: _HeldAware(
        env: env,
        child: LayoutBuilder(
          builder: (context, box) {
            // Narrow (a week on a phone): one line per field, cut with an
            // ellipsis rather than words broken across lines.
            final narrow = box.maxWidth < 72;
            final room = math.max(1, (tall - 2) ~/ lineHeight);
            final own = env.eventBuilder?.call(
              context,
              i,
              EventInfo(
                segment: seg,
                size: box.biggest,
                compact: narrow || room < 2,
                color: colors.fill,
                onColor: colors.on,
                when: when,
                held: env.interaction.held.value == i.key,
              ),
            );
            if (own != null) return own;
            final real = placed.realMinutes;
            final extra = <String>[
              if (room >= 3 || (!narrow && room >= 2)) '$start – $end',
              if (real != null && room >= 4) env.l10n.realDuration(env.l10n.duration(real.round())),
            ];
            final titleLines = math.max(1, room - extra.length);
            return Container(
              padding: const EdgeInsetsDirectional.only(start: 3, end: 2, top: 1),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: colors.fill,
                borderRadius: BorderRadius.circular(style.eventRadius),
                border: Border.all(color: Theme.of(context).colorScheme.surface, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: narrow ? 1 : titleLines,
                    softWrap: !narrow,
                    overflow: TextOverflow.ellipsis,
                    style: text.copyWith(fontWeight: FontWeight.w600),
                  ),
                  for (final e in extra)
                    Text(e, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: text),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// An app's look hears the held state itself (the gestures' builder reuses its child).
class _HeldAware extends StatelessWidget {
  const _HeldAware({required this.env, required this.child});
  final CalendarEnv env;
  final Widget child;

  @override
  Widget build(BuildContext context) => env.eventBuilder == null
      ? child
      : ValueListenableBuilder<String?>(valueListenable: env.interaction.held, builder: (_, _, _) => child);
}

class _SlotBox extends StatelessWidget {
  const _SlotBox({required this.env, required this.placed});
  final CalendarEnv env;
  final PlacedSlot placed;

  @override
  Widget build(BuildContext context) {
    final style = env.style;
    final s = placed.slot;
    final when = env.l10n.range(env.time(s.start), env.time(s.end));
    final seats = s.seats;
    return Semantics(
      button: true,
      label: env.l10n.freeSlot(when) + (seats != null ? ', ${env.l10n.seatsLeft(seats)}' : ''),
      excludeSemantics: true,
      child: Material(
        color: style.slotColor,
        borderRadius: BorderRadius.circular(style.eventRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(style.eventRadius),
          onTap: env.onSlotTap == null ? null : () => env.onSlotTap!(s),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, top: 1),
            child: Text(
              env.time(s.start) + (seats != null ? ' · ${env.l10n.seatsLeft(seats)}' : ''),
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: style.eventStyle.copyWith(color: style.onSlotColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreBox extends StatelessWidget {
  const _MoreBox({required this.env, required this.more, required this.date});
  final CalendarEnv env;
  final MoreTimed more;
  final PlainDate date;

  @override
  Widget build(BuildContext context) {
    final count = more.events.length;
    return Semantics(
      button: true,
      label: env.l10n.moreLabel(count, env.dateLong(date)),
      excludeSemantics: true,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(env.style.eventRadius),
        child: InkWell(
          onTap: () => showDaySheet(context, env, date, [for (final p in more.events) p.segment]),
          child: Center(
            child: Text(
              env.l10n.moreLink(count),
              style: env.style.eventStyle,
              maxLines: 1,
              overflow: TextOverflow.clip,
            ),
          ),
        ),
      ),
    );
  }
}
