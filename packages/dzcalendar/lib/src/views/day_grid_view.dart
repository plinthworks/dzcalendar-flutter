import 'dart:math' as math;

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:flutter/material.dart';
import 'package:dzcalendar_core/internal.dart' show cutDayGridModel;

import '../env.dart';
import '../interaction.dart';
import '../keyboard.dart';
import 'common.dart';

/// A day grid: a month, a week or a day as rows of cells with event bars
/// (`dayGrid*`, `resourceDayGrid*`). Rows share the height; a day showing
/// more bars than fit says "+N", which lists them. How many fit is measured
/// here and cut here (`cutDayGridModel`): the calendar's options are left
/// alone, and an app's own `dayGrid.maxLanes` stands.
class DayGridView extends StatefulWidget {
  const DayGridView({super.key, required this.env, required this.model});

  final CalendarEnv env;
  final DayGridModel model;

  static const _numberHeight = 24.0;
  static const _gap = 2.0;

  @override
  State<DayGridView> createState() => _DayGridViewState();
}

class _DayGridViewState extends State<DayGridView> implements DragSurface, KeySurface {
  CalendarEnv get env => widget.env;
  DayGridModel get model => widget.model;

  final _gridKey = GlobalKey();
  final _rowKeys = <GlobalKey>[];

  @override
  void dispose() {
    env.interaction.detach(this);
    env.interaction.keyboard.detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weeks = model.weeks;
    if (weeks.isEmpty) return const SizedBox.shrink();
    env.interaction.attach(this);
    env.interaction.keyboard.attach(this);
    while (_rowKeys.length < weeks.length) {
      _rowKeys.add(GlobalKey());
    }
    final cells = weeks.first.dates.length;
    final style = env.style;
    final names = weekdayNames(env.locale, NameWidth.short, env.state.firstDay);
    final resourceView = model.resourceHeads.isNotEmpty;
    final days = resourceView ? cells ~/ math.max(1, model.resourceHeads.length) : cells;
    return Column(
      children: [
        if (model.groupHeads.isNotEmpty)
          ResourceGroupRow(env: env, groups: model.groupHeads, heads: model.resourceHeads),
        if (resourceView) ResourceHeadRow(env: env, heads: model.resourceHeads, cells: cells),
        // Weekday names: one row of a month's dates says which day each column is.
        Row(
          children: [
            for (var c = 0; c < cells; c++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    weeks.length > 1
                        ? names[(weeks.first.dates[c].dayOfWeek - env.state.firstDay + 7) % 7]
                        : dayHead(env, weeks.first.dates[c], days),
                    textAlign: TextAlign.center,
                    style: style.headerStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
        Divider(height: 1, color: style.gridLineColor),
        Expanded(
          child: LayoutBuilder(
            key: _gridKey,
            builder: (context, box) {
              final rowHeight = box.maxHeight / weeks.length;
              final cut = rowHeight.isFinite ? cutDayGridModel(model, _fit(rowHeight)) : model;
              return Column(
                children: [
                  for (var w = 0; w < weeks.length; w++)
                    SizedBox(
                      key: _rowKeys[w],
                      height: rowHeight,
                      child: _WeekRow(env: env, model: cut, index: w, numberHeight: DayGridView._numberHeight),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Lanes a row holds, the "+N" link's included (it takes the last one where something spills); at least one.
  int _fit(double rowHeight) =>
      math.max(1, ((rowHeight - DayGridView._numberHeight) / (env.style.barHeight + DayGridView._gap)).floor());

  // ——— the gestures' surface ———

  RenderBox? _box(GlobalKey k) {
    final b = k.currentContext?.findRenderObject();
    return b is RenderBox && b.attached && b.hasSize ? b : null;
  }

  Rect _global(RenderBox b, Rect local) => MatrixUtils.transformRect(b.getTransformTo(null), local);

  int get _cells => model.weeks.first.dates.length;

  int _cellAt(double x, double width) {
    final along = env.textDirection == TextDirection.ltr ? x : width - x;
    return (along / (width / _cells)).floor().clamp(0, _cells - 1);
  }

  @override
  Hit? hitAt(Offset g) {
    final grid = _box(_gridKey);
    if (grid == null || model.weeks.isEmpty) return null;
    final area = _global(grid, Offset.zero & grid.size);
    final p = Offset(g.dx.clamp(area.left, area.right - 0.5), g.dy.clamp(area.top, area.bottom - 0.5));
    for (var w = 0; w < model.weeks.length && w < _rowKeys.length; w++) {
      final row = _box(_rowKeys[w]);
      if (row == null) continue;
      final l = row.globalToLocal(p);
      if (l.dy >= 0 && l.dy < row.size.height) return dayHitAt(model, w, _cellAt(l.dx, row.size.width));
    }
    return null;
  }

  @override
  List<GhostBox> boxesFor(CalEvent ev) {
    final out = <GhostBox>[];
    final grid = _box(_gridKey);
    if (grid == null) return out;
    final clip = _global(grid, Offset.zero & grid.size);
    // The days it covers, in the calendar's zone (a timed event's last day is the one its last moment is on).
    final (PlainDate first, PlainDate end) = switch (ev) {
      AllDayEvent(:final start, :final end) => (start, end),
      TimedEvent(:final start, :final end) => (
        ZonedDateTime(start.instant, env.zone).date,
        ZonedDateTime(
          end.instant.isAfter(start.instant) ? end.instant.addMs(-1) : start.instant,
          env.zone,
        ).date.addDays(1),
      ),
    };
    for (var w = 0; w < model.weeks.length && w < _rowKeys.length; w++) {
      final row = _box(_rowKeys[w]);
      if (row == null) continue;
      final week = model.weeks[w];
      final width = row.size.width;
      final cw = width / _cells;
      int? from;
      void close(int last) {
        final ltr = env.textDirection == TextDirection.ltr;
        final left = ltr ? from! * cw : width - (last + 1) * cw;
        out.add((
          rect: _global(
            row,
            Rect.fromLTWH(left + 2, DayGridView._numberHeight, (last - from! + 1) * cw - 4, env.style.barHeight),
          ),
          clip: clip,
        ));
        from = null;
      }

      for (var c = 0; c < _cells; c++) {
        final d = week.dates[c];
        final r = week.resources[c];
        final ok = r == null || (ev.resourceIds.isEmpty ? r.id == unassignedId : ev.resourceIds.contains(r.id));
        final inside = !d.isBefore(first) && d.isBefore(end) && ok;
        if (inside) from ??= c;
        if (!inside && from != null) close(c - 1);
      }
      if (from != null) close(_cells - 1);
    }
    return out;
  }

  // ——— the keyboard's surface (decision 41) ———

  /// The model as the controller has it now (a period the keyboard just went to).
  DayGridModel get _now => switch (env.controller.model) {
    DayGridViewModel(:final model) => model,
    _ => model,
  };

  @override
  KeyGrid get keyGrid => KeyGrid.day;

  @override
  bool get allDayRow => false;

  @override
  bool get resourceView => _now.resourceHeads.isNotEmpty;

  ResourceId? get _firstResource {
    final heads = _now.resourceHeads;
    return heads.isEmpty ? null : heads.first.resource.id;
  }

  /// Week and cell of [date] in [resourceId]'s days (the first resource's when unknown).
  (int, int)? _cellOf(DayGridModel m, PlainDate date, ResourceId? resourceId) {
    final rid = resourceView ? (resourceId ?? _firstResource) : null;
    for (var w = 0; w < m.weeks.length; w++) {
      final week = m.weeks[w];
      for (var c = 0; c < week.dates.length; c++) {
        if (week.dates[c] == date && (rid == null || week.resources[c]?.id == rid)) return (w, c);
      }
    }
    return null;
  }

  @override
  Hit? home() {
    final m = _now;
    if (m.weeks.isEmpty) return null;
    final today = env.state.today;
    final r = _firstResource;
    if (_cellOf(m, today, r) != null) return DayHit(date: today, resourceId: r);
    for (final w in m.weeks) {
      for (var c = 0; c < w.dates.length; c++) {
        if (!w.outside[c]) return DayHit(date: w.dates[c], resourceId: w.resources[c]?.id);
      }
    }
    return DayHit(date: m.weeks.first.dates.first, resourceId: m.weeks.first.resources.first?.id);
  }

  @override
  KeyFit? fit(Hit hit) {
    final m = _now;
    if (m.weeks.isEmpty) return null;
    final known = resourceView && _now.resourceHeads.any((h) => h.resource.id == hit.resourceId);
    final rid = resourceView ? (known ? hit.resourceId : _firstResource) : null;
    if (_cellOf(m, hit.date, rid) != null) {
      return hit is DayHit && !hit.allDayRow && hit.resourceId == rid
          ? FitAt(hit)
          : FitAt(DayHit(date: hit.date, resourceId: rid));
    }
    final st = env.state;
    if (st.view.hiddenDays.contains(hit.date.dayOfWeek)) return null;
    if (hit.date.isBefore(st.range.start)) return const FitOff(next: false);
    if (!hit.date.isBefore(st.range.end)) return const FitOff(next: true);
    return null;
  }

  @override
  Hit lineEdge(Hit hit, Edge edge) {
    final m = _now;
    final at = _cellOf(m, hit.date, hit.resourceId);
    if (at == null) return hit;
    final week = m.weeks[at.$1];
    final rid = week.resources[at.$2]?.id;
    final line = [
      for (var c = 0; c < week.dates.length; c++)
        if (week.resources[c]?.id == rid) week.dates[c],
    ];
    return DayHit(date: edge == Edge.start ? line.first : line.last, resourceId: rid);
  }

  static List<EventInstance> _unique(Iterable<EventInstance> all) {
    final seen = <String>{};
    return [
      for (final i in all)
        if (seen.add(i.key)) i,
    ];
  }

  List<EventInstance> _inCell(DayGridModel m, int w, int c) => _unique([
    for (final s in segmentsOn(m.weeks[w], c))
      if (s.instance.event.display != EventDisplay.background) s.instance,
  ]);

  @override
  List<EventInstance> itemsAt(Hit hit) {
    final m = _now;
    final at = _cellOf(m, hit.date, hit.resourceId);
    return at == null ? const [] : _inCell(m, at.$1, at.$2);
  }

  @override
  List<EventInstance> items() {
    final m = _now;
    return _unique([
      for (var w = 0; w < m.weeks.length; w++)
        for (var c = 0; c < m.weeks[w].dates.length; c++) ..._inCell(m, w, c),
    ]);
  }

  /// The first cell that shows [instance].
  (int, int)? _firstCellOf(DayGridModel m, EventInstance instance) {
    for (var w = 0; w < m.weeks.length; w++) {
      for (var c = 0; c < m.weeks[w].dates.length; c++) {
        if (segmentsOn(m.weeks[w], c).any((s) => s.instance.key == instance.key)) return (w, c);
      }
    }
    return null;
  }

  @override
  List<EventInstance> itemsAround(EventInstance instance) {
    final m = _now;
    final at = _firstCellOf(m, instance);
    return at == null ? const [] : _inCell(m, at.$1, at.$2);
  }

  @override
  Hit? cursorFor(EventInstance instance) {
    final m = _now;
    final at = _firstCellOf(m, instance);
    if (at == null) return null;
    final week = m.weeks[at.$1];
    return DayHit(date: week.dates[at.$2], resourceId: week.resources[at.$2]?.id);
  }

  @override
  Hit? firstSlot(PlainDate date, ResourceId? resourceId) => null;

  @override
  Hit? stepAcross(Hit hit, int delta) {
    final heads = _now.resourceHeads;
    if (heads.isEmpty) return null;
    final k = heads.indexWhere((h) => h.resource.id == hit.resourceId);
    final n = (k < 0 ? 0 : k) + delta;
    if (n < 0 || n >= heads.length) return null;
    final id = heads[n].resource.id;
    return _cellOf(_now, hit.date, id) == null ? null : DayHit(date: hit.date, resourceId: id);
  }

  /// A month does not scroll.
  @override
  void reveal(Hit hit) {}

  @override
  bool autoscroll(Offset global, double seconds) => false;

  /// A month draws a timed event's day, not its length.
  @override
  bool canResize(CalEvent event) => event.allDay;
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.env, required this.model, required this.index, required this.numberHeight});
  final CalendarEnv env;
  final DayGridModel model;
  final int index;
  final double numberHeight;

  @override
  Widget build(BuildContext context) {
    final week = model.weeks[index];
    final style = env.style;
    final cells = week.dates.length;
    final lane = style.barHeight + DayGridView._gap;
    final shown = model.maxLanes ?? week.laneCount;
    return LayoutBuilder(
      builder: (context, box) {
        final cw = box.maxWidth / cells;
        return Stack(
          children: [
            // Cells: background, the day number, taps.
            Row(
              children: [
                for (var c = 0; c < cells; c++)
                  Expanded(
                    child: _Cell(env: env, model: model, week: index, cell: c),
                  ),
              ],
            ),
            // Background events tint whole days.
            for (final s in week.background)
              PositionedDirectional(
                start: (s.dayIndex - week.firstColumn) * cw,
                width: s.dayCount * cw,
                top: 0,
                bottom: 0,
                child: IgnorePointer(child: ColoredBox(color: env.colorOf(s.instance).withValues(alpha: 0.25))),
              ),
            for (final bar in week.bars)
              if (bar.lane < shown)
                for (final piece in bar.pieces)
                  PositionedDirectional(
                    start: piece.from * cw + 2,
                    width: (piece.to - piece.from) * cw - 4,
                    top: numberHeight + bar.lane * lane,
                    height: style.barHeight,
                    child: EventBar(env: env, segment: bar.segment),
                  ),
            for (var c = 0; c < cells; c++)
              if (week.hiddenKeysPerDay[c].isNotEmpty)
                PositionedDirectional(
                  start: c * cw,
                  width: cw,
                  top: numberHeight + (shown - 1) * lane,
                  height: style.barHeight,
                  child: _MoreLink(env: env, week: week, cell: c),
                ),
          ],
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.env, required this.model, required this.week, required this.cell});
  final CalendarEnv env;
  final DayGridModel model;
  final int week;
  final int cell;

  @override
  Widget build(BuildContext context) {
    final w = model.weeks[week];
    final date = w.dates[cell];
    final style = env.style;
    final outside = w.outside[cell];
    final today = env.isToday(date);
    final count = segmentsOn(w, cell).length;
    final resource = w.resources[cell];
    final label = env.l10n.dayLabel(env.dateLong(date), count);
    return ValueListenableBuilder<CalendarSelection?>(
      valueListenable: env.controller.selectionListenable,
      builder: (context, sel, _) {
        final selected = switch (sel) {
          DaySelection(:final start, :final end, :final resourceId) =>
            !date.isBefore(start) && date.isBefore(end) && (resourceId == null || resourceId == resource?.id),
          _ => false,
        };
        return Semantics(
          button: true,
          label: resource != null ? env.l10n.ofResource(resource.title, label) : label,
          selected: selected,
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _tap(),
            onLongPressStart: (d) {
              final hit = dayHitAt(model, week, cell);
              if (hit == null) return;
              env.interaction.pressEmpty(hit, DayTarget(date: date, resourceId: resource?.id), d.globalPosition);
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected
                    ? style.selectionColor
                    : w.closed[cell]
                    ? style.offHoursColor
                    : null,
                border: BorderDirectional(
                  end: BorderSide(color: style.gridLineColor, width: 0.5),
                  bottom: BorderSide(color: style.gridLineColor, width: 0.5),
                ),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: AlignmentDirectional.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: DayNumber(env: env, date: date, today: today, outside: outside),
                    ),
                  ),
                  // The keyboard's cursor on this day.
                  ValueListenableBuilder<Hit?>(
                    valueListenable: env.interaction.keyboard.cursor,
                    builder: (context, hit, _) =>
                        hit is DayHit && hit.date == date && (hit.resourceId == null || hit.resourceId == resource?.id)
                        ? CursorBox(radius: style.eventRadius)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _tap() {
    final hit = dayHitAt(model, week, cell);
    if (hit != null && env.interaction.keyboard.putAt(hit)) return;
    env.interaction.release();
    if (hit == null) return;
    env.interaction.keyboard.tapped(hit);
    env.onDateTap?.call(hit);
    final ctx = env.controller.kernel.interactionContext(snapMinutes: 1);
    final sel = selectionBetween(ctx, hit, hit);
    env.controller.select(sel);
    env.selected(sel);
  }
}

/// A day's number, circled on today.
class DayNumber extends StatelessWidget {
  const DayNumber({
    super.key,
    required this.env,
    required this.date,
    required this.today,
    this.outside = false,
    this.maxWidth,
  });
  final CalendarEnv env;
  final PlainDate date;
  final bool today;
  final bool outside;

  /// The room it has, when its parent does not bound it (a year's [FittedBox]).
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final style = env.style;
    final marked = env.dayNumber(date);
    final second = env.secondaryDay(date);
    final color = today
        ? style.onTodayColor
        : outside
        ? style.outsideDayColor
        : null;
    final numberStyle = style.dayNumberStyle.copyWith(color: color, fontWeight: today ? FontWeight.w600 : null);
    final secondStyle = outside
        ? style.secondaryDateStyle.copyWith(color: style.outsideDayColor)
        : style.secondaryDateStyle;
    // Gregorian alone: the number, nothing to measure.
    if (second == null && env.state.displayCalendar == null) {
      return UnconstrainedBox(child: _circle(marked, numberStyle));
    }
    return LayoutBuilder(
      builder: (context, box) {
        final room = maxWidth ?? (box.maxWidth.isFinite ? box.maxWidth : double.infinity);
        // As the circle draws it: at least 24 wide.
        double numberWidth(String t) => math.max(24, _width(context, t, numberStyle) + 8);
        // A month's first day says its month ("1 Ram.") where the cell has room; else its number.
        var text = marked;
        if (numberWidth(text) > room) text = env.date(date, 'd');
        // The secondary day beside it, its month dropped, then itself, when they do not fit.
        String? beside = second;
        if (beside != null && numberWidth(text) + 2 + _width(context, beside, secondStyle) > room) {
          final plain = env.state.formatSecondary(date, 'd');
          beside = plain != null && numberWidth(text) + 2 + _width(context, plain, secondStyle) <= room ? plain : null;
        }
        final number = _circle(text, numberStyle);
        if (beside == null) return UnconstrainedBox(child: number);
        return UnconstrainedBox(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              number,
              const SizedBox(width: 2),
              Text(beside, maxLines: 1, softWrap: false, style: secondStyle),
            ],
          ),
        );
      },
    );
  }

  /// Sized to the number (a circle on today), never stretched by the cell.
  Widget _circle(String text, TextStyle numberStyle) => Container(
    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
    padding: const EdgeInsets.symmetric(horizontal: 4),
    alignment: Alignment.center,
    decoration: today ? BoxDecoration(color: env.style.todayColor, borderRadius: BorderRadius.circular(12)) : null,
    child: Text(text, maxLines: 1, softWrap: false, style: numberStyle),
  );

  static double _width(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = painter.width;
    painter.dispose();
    return w;
  }
}

class _MoreLink extends StatelessWidget {
  const _MoreLink({required this.env, required this.week, required this.cell});
  final CalendarEnv env;
  final DayGridWeek week;
  final int cell;

  @override
  Widget build(BuildContext context) {
    final keys = week.hiddenKeysPerDay[cell];
    final date = week.dates[cell];
    return Semantics(
      button: true,
      label: env.l10n.moreLabel(keys.length, env.dateLong(date)),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showDaySheet(context, env, date, segmentsOn(week, cell)),
        child: Center(
          child: Text(
            env.l10n.moreLink(keys.length),
            style: env.style.eventStyle.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ),
      ),
    );
  }
}
