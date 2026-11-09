import 'dart:math' as math;

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:dzcalendar_core/internal.dart' show UniformSizes, visibleRange;
import 'package:flutter/material.dart';

import '../env.dart';
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

class _TimeGridViewState extends State<TimeGridView> {
  ScrollController? _vertical;

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
    final height = model.columns.fold<double>(0, (m, c) => math.max(m, c.axis.length)) * ppm;
    return LayoutBuilder(
      builder: (context, box) {
        final avail = math.max(0.0, box.maxWidth - style.gutterWidth);
        final colW = math.max(avail / n, style.minColumnWidth);
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
                    child: sideways(_allDay, _AllDayRow(env: env, model: model, colW: colW)),
                  ),
                ],
              ),
            Divider(height: 1, color: style.gridLineColor),
            Expanded(
              child: SingleChildScrollView(
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
                                env: env,
                                model: model,
                                controller: _body,
                                colW: colW,
                                height: height,
                                ppm: ppm,
                              )
                            : Row(
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

/// The columns on screen, and one more each side, in a sideways scroll.
class _VirtualColumns extends StatelessWidget {
  const _VirtualColumns({
    required this.env,
    required this.model,
    required this.controller,
    required this.colW,
    required this.height,
    required this.ppm,
  });
  final CalendarEnv env;
  final TimeGridModel model;
  final ScrollController controller;
  final double colW;
  final double height;
  final double ppm;

  @override
  Widget build(BuildContext context) {
    final n = model.columns.length;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final offset = controller.hasClients ? controller.offset : 0.0;
            final r = visibleRange(UniformSizes(colW, n), offset, box.maxWidth, 1);
            return SizedBox(
              width: colW * n,
              height: height,
              child: Stack(
                children: [
                  for (var i = r.first; i <= r.last; i++)
                    PositionedDirectional(
                      key: ValueKey(model.columns[i].key),
                      start: i * colW,
                      width: colW,
                      top: 0,
                      height: height,
                      child: _Column(env: env, model: model, index: i, ppm: ppm),
                    ),
                ],
              ),
            );
          },
        ),
      ),
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
  const _AllDayRow({required this.env, required this.model, required this.colW});
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
                          env.showActions(
                            context,
                            DayTarget(date: c.date, resourceId: c.resource?.id),
                            d.globalPosition,
                          );
                        },
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: BorderDirectional(start: BorderSide(color: style.gridLineColor, width: 0.5)),
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
    if (hit == null) return;
    env.onDateTap?.call(hit);
    final sel = selectionBetween(env.controller.kernel.interactionContext(snapMinutes: 1), hit, hit);
    env.controller.select(sel);
    env.onSelect?.call(sel);
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
    final now = env.controller.now();
    final showNow = !now.isBefore(c.axis.start) && now.isBefore(c.axis.end);
    final selection = _selectionSpan();
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _tap(d.localPosition.dy / ppm, snap),
          onLongPressStart: (d) {
            final target = slotTargetAt(model, index, d.localPosition.dy / ppm);
            if (target != null) env.showActions(context, target, d.globalPosition);
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
                if (selection != null)
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    top: selection.$1 * ppm,
                    height: math.max(2, (selection.$2 - selection.$1) * ppm),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: style.selectionColor,
                          borderRadius: BorderRadius.circular(style.eventRadius),
                        ),
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
                if (showNow)
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    top: c.axis.toPosition(now) * ppm - 1,
                    height: 2,
                    child: IgnorePointer(
                      child: Semantics(
                        label: env.l10n.now,
                        child: ColoredBox(color: style.nowColor),
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
  (double, double)? _selectionSpan() {
    final sel = env.controller.selection;
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
    if (hit == null) return;
    env.onDateTap?.call(hit);
    final ctx = env.controller.kernel.interactionContext(snapMinutes: snap);
    final sel = selectionBetween(ctx, hit, hit);
    env.controller.select(sel);
    env.onSelect?.call(sel);
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
    final color = env.colorOf(i);
    final on = env.onColor(color);
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
    final text = style.eventStyle.copyWith(color: on, height: 1.2);
    final lineHeight = (text.fontSize ?? 11) * 1.2;
    return EventGestures(
      env: env,
      instance: i,
      label: env.l10n.eventLabel(title, when),
      child: Container(
        padding: const EdgeInsetsDirectional.only(start: 3, end: 2, top: 1),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(style.eventRadius),
          border: Border.all(color: Theme.of(context).colorScheme.surface, width: 0.5),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            // Narrow (a week on a phone): one line per field, cut with an
            // ellipsis rather than words broken across lines.
            final narrow = box.maxWidth < 72;
            final room = math.max(1, (tall - 2) ~/ lineHeight);
            final real = placed.realMinutes;
            final extra = <String>[
              if (room >= 3 || (!narrow && room >= 2)) '$start – $end',
              if (real != null && room >= 4) env.l10n.realDuration(env.l10n.duration(real.round())),
            ];
            final titleLines = math.max(1, room - extra.length);
            return Column(
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
            );
          },
        ),
      ),
    );
  }
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
