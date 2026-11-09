import '../event/problem.dart';
import '../event/types.dart';
import '../layout/rows.dart';
import '../project/segment.dart';
import '../resource/rows.dart';
import '../resource/tree.dart';
import '../rules/business_hours.dart';
import '../store/changes.dart';
import '../store/store.dart';
import '../time/plain.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'views.dart';

/// A background or inverse background (drawn as the complement): neither
/// takes a lane.
bool isBackground(EventDisplay d) => d == EventDisplay.background || d == EventDisplay.inverseBackground;

/// A group's head above its resources' columns.
final class ResourceGroupHead {
  const ResourceGroupHead({required this.value, required this.from, required this.count});
  final String value;

  /// Index of its first resource, and how many follow.
  final int from;
  final int count;
}

/// A resource's head above its columns (its days).
final class ResourceHead {
  const ResourceHead({required this.resource, required this.from, required this.count});
  final Resource resource;
  final int from;
  final int count;
}

/// The groups of [columnResources] as heads.
List<ResourceGroupHead> groupHeadsOf(ColumnResources c) => [
  for (final g in c.groups) ResourceGroupHead(value: g.value, from: g.from, count: g.count),
];

/// Business hours that close nothing: none given, or none at all (the
/// web's `false`).
bool _noHours(BusinessHours? h) => h == null || h.rules.isEmpty;

final class DayGridOptions {
  const DayGridOptions({
    required this.displayZone,
    this.maxLanes,
    this.resourceId,
    this.resources,
    this.resourceGroups = const [],
    this.businessHours,
    this.showNonCurrentDates = true,
    this.onProblem,
  });

  final ZoneId displayZone;

  /// Where the queries' problems go (a series cut short there): what the
  /// kernel's `viewProblems` reports.
  final void Function(Problem)? onProblem;

  /// Rows of bars per day before "+N"; null: as many as needed.
  final int? maxLanes;

  /// Only this resource's events.
  final String? resourceId;

  /// A resource view: in each row, every resource's days side by side
  /// (resources first). Each resource's cells show its events, and are
  /// `closed` by its own business hours, read in its zone.
  final List<Resource>? resources;
  final List<ResourceGroupHead> resourceGroups;

  /// Days without any open hour are marked `closed`.
  final BusinessHours? businessHours;

  /// False: padding days outside the month are left empty.
  final bool showNonCurrentDates;

  DayGridOptions copyWith({bool? showNonCurrentDates, int? maxLanes}) => DayGridOptions(
    displayZone: displayZone,
    maxLanes: maxLanes ?? this.maxLanes,
    resourceId: resourceId,
    resources: resources,
    resourceGroups: resourceGroups,
    businessHours: businessHours,
    showNonCurrentDates: showNonCurrentDates ?? this.showNonCurrentDates,
    onProblem: onProblem,
  );
}

final class DayGridBar {
  const DayGridBar({required this.segment, required this.lane, required this.pieces});
  final Segment segment;
  final int lane;

  /// Week-row columns this bar is drawn over, `to` exclusive; several pieces
  /// when "+N" cuts it.
  final List<({int from, int to})> pieces;
}

final class DayGridWeek {
  const DayGridWeek({
    required this.dates,
    required this.resources,
    required this.background,
    required this.firstColumn,
    required this.bars,
    required this.laneCount,
    required this.hiddenKeysPerDay,
    required this.segments,
    required this.outside,
    required this.closed,
  });

  /// One per cell: in a resource view, the week's dates once per resource.
  final List<PlainDate> dates;

  /// Per cell, whose it is (null outside a resource view).
  final List<Resource?> resources;

  /// `display: background` events: tint whole days, take no lane.
  final List<Segment> background;

  /// This row's first cell among all the rows' cells: `dayIndex - firstColumn` is a cell.
  final int firstColumn;
  final List<DayGridBar> bars;
  final int laneCount;

  /// Per day of the row: the keys its "+N" link stands for.
  final List<List<String>> hiddenKeysPerDay;
  List<int> get hiddenPerDay => [for (final k in hiddenKeysPerDay) k.length];

  /// Every bar of the row, drawn or not: what the "+N" popover lists.
  final List<Segment> segments;

  /// Per day: outside the active period (a padding day of a month grid).
  final List<bool> outside;

  /// Per day: no business hour at all (always false without business hours).
  final List<bool> closed;
}

final class DayGridModel {
  const DayGridModel({
    required this.version,
    required this.range,
    required this.options,
    required this.weeks,
    required this.resourceHeads,
    required this.groupHeads,
  });

  /// The store version the model reflects.
  final int version;
  final ViewRange range;
  final DayGridOptions options;
  final List<DayGridWeek> weeks;

  /// A resource view's heads, over a row's cells. Empty otherwise.
  final List<ResourceHead> resourceHeads;
  final List<ResourceGroupHead> groupHeads;

  /// The lanes a day shows before "+N"; null: as many as needed.
  int? get maxLanes => options.maxLanes;

  DayGridModel _withWeeks(List<DayGridWeek> weeks) => DayGridModel(
    version: version,
    range: range,
    options: options,
    weeks: weeks,
    resourceHeads: resourceHeads,
    groupHeads: groupHeads,
  );
}

/// [model] cut to [maxLanes] lanes per day (the "+N" link's included), as
/// a model built with that `maxLanes` would be: what a renderer fits to the
/// height it measures, without changing the calendar's options. A model
/// already cut (its options name a `maxLanes`: the application's setting)
/// is returned as it is. Throws an [ArgumentError] when [maxLanes] is
/// under 1, as the option does.
DayGridModel cutDayGridModel(DayGridModel model, int maxLanes) {
  if (maxLanes < 1) throw ArgumentError.value(maxLanes, 'maxLanes', 'an integer ≥ 1');
  if (model.maxLanes != null) return model;
  final weeks = [
    for (final w in model.weeks)
      if (w.laneCount <= maxLanes) w else _cutWeek(w, maxLanes),
  ];
  return DayGridModel(
    version: model.version,
    range: model.range,
    options: model.options.copyWith(maxLanes: maxLanes),
    weeks: List.unmodifiable(weeks),
    resourceHeads: model.resourceHeads,
    groupHeads: model.groupHeads,
  );
}

DayGridWeek _cutWeek(DayGridWeek w, int maxLanes) {
  // Uncut, every bar is one piece on its packed lane, in the builder's order.
  final items = [
    for (final b in w.bars) RowItem(key: b.segment.key, start: b.pieces.first.from, end: b.pieces.first.to),
  ];
  final lanes = {for (final b in w.bars) b.segment.key: b.lane};
  final over = computeOverflow(lanes, items, w.dates.length, maxLanes);
  final piecesOf = <String, List<({int from, int to})>>{};
  for (final p in over.pieces) {
    (piecesOf[p.key] ??= []).add((from: p.from, to: p.to));
  }
  return DayGridWeek(
    dates: w.dates,
    resources: w.resources,
    background: w.background,
    firstColumn: w.firstColumn,
    bars: List.unmodifiable([
      for (final b in w.bars)
        if (piecesOf[b.segment.key] case final pieces?) DayGridBar(segment: b.segment, lane: b.lane, pieces: pieces),
    ]),
    laneCount: w.laneCount,
    hiddenKeysPerDay: List.unmodifiable(over.hiddenKeysPerDay),
    segments: w.segments,
    outside: w.outside,
    closed: w.closed,
  );
}

/// A month (or week, or day) as rows of bars. All-day events span their
/// days; a timed event sits on each display-zone day it touches, so a
/// late-night event in Tokyo lands on the right day in Paris. All-day
/// first, then by start: the order of `queryInstances`.
DayGridModel buildDayGridModel(ViewRange range, StoreSnapshot snap, DayGridOptions o) {
  bool inActive(PlainDate d) => !d.isBefore(range.activeStart) && d.isBefore(range.activeEnd);
  final hideOutside = !o.showNonCurrentDates;
  // Hidden padding days keep their columns but take no segment.
  final view = DateIndex(range.dates, keep: hideOutside ? inActive : null);
  final days = [for (final d in range.dates) dayInfo(d, o.displayZone)];

  var col = 0;
  final weekCols = [
    for (final w in range.weeks) [for (final _ in w) col++],
  ];
  final owners = <Resource?>[...?o.resources];
  if (o.resources == null) owners.add(null);
  final per = owners.length;
  // Cells: each row holds every owner's days; cellStart[r] is the row's first cell among all rows.
  final cellStart = <int>[];
  var cells = 0;
  for (final w in range.weeks) {
    cellStart.add(cells);
    cells += w.length * per;
  }
  final rowOf = <int>[
    for (var r = 0; r < weekCols.length; r++)
      for (final _ in weekCols[r]) r,
  ];
  int cellOf(int dayIndex, int k) {
    final r = rowOf[dayIndex];
    return cellStart[r] + k * range.weeks[r].length + (dayIndex - weekCols[r].first);
  }

  final rows = [for (final _ in range.weeks) <Segment>[]];
  final bgRows = [for (final _ in range.weeks) <Segment>[]];
  final rank = <String, List<int>>{};
  final w = viewWindow(range.start, range.end, o.displayZone);
  for (var k = 0; k < owners.length; k++) {
    final resource = owners[k];
    final instances = resource != null
        ? instancesOf(snap, w, resource, o.resources ?? const [], QueryOptions(onProblem: o.onProblem))
        : snap.queryInstances(w, QueryOptions(resourceId: o.resourceId, onProblem: o.onProblem));
    final segs = <Segment>[];
    final bgSegs = <Segment>[];
    for (var i = 0; i < instances.length; i++) {
      final inst = instances[i];
      rank[inst.key] = [if (inst.event.allDay) 0 else 1, i];
      final out = isBackground(inst.event.display) ? bgSegs : segs;
      if (inst.event.allDay) {
        out.addAll(segmentAllDay(inst, view));
      } else {
        out.addAll(segmentTimed(inst, days).where((sg) => !hideOutside || inActive(range.dates[sg.dayIndex])));
      }
    }
    // Split by real weeks, then each piece moved to the owner's cells; its own key per owner.
    void place(List<List<Segment>> into, List<List<Segment>> split) {
      for (var r = 0; r < split.length; r++) {
        for (final sg in split[r]) {
          into[r].add(
            resource == null ? sg : sg.placed(key: '${sg.key}|${resource.id}', dayIndex: cellOf(sg.dayIndex, k)),
          );
        }
      }
    }

    place(rows, splitByWeek(segs, weekCols));
    place(bgRows, splitByWeek(bgSegs, weekCols));
  }

  // Business hours per owner: its own (else the calendar's), read in its zone.
  final closedFor = [
    for (final resource in owners)
      () {
        final hours = resource?.businessHours ?? o.businessHours;
        if (_noHours(hours)) return (PlainDate _) => false;
        final zone = resource?.timeZone ?? o.displayZone;
        final open = businessIntervals(range.start.addDays(-1), range.end.addDays(1), hours!, zone);
        return (PlainDate d) {
          final s = d.startOfDayIn(o.displayZone).epochMilliseconds;
          final e = d.addDays(1).startOfDayIn(o.displayZone).epochMilliseconds;
          return !open.any((x) => x.s < e && x.e > s);
        };
      }(),
  ];

  final weeks = <DayGridWeek>[];
  for (var r = 0; r < range.weeks.length; r++) {
    final week = range.weeks[r];
    final first = cellStart[r];
    final dates = owners.length == 1 ? week : [for (final _ in owners) ...week];
    final resources = [
      for (final res in owners)
        for (final _ in week) res,
    ];
    final outside = [for (final d in dates) !inActive(d)];
    final closed = [
      for (var k = 0; k < owners.length; k++)
        for (final d in week) closedFor[k](d),
    ];
    final items = [
      for (final s in rows[r])
        RowItem(
          key: s.key,
          start: s.dayIndex - first,
          end: s.dayIndex - first + s.dayCount,
          rank: rank[s.instance.key]!,
        ),
    ];
    final packed = packLanes(items);
    final bySeg = {for (final s in rows[r]) s.key: s};
    final max = o.maxLanes;
    final List<DayGridBar> bars;
    final List<List<String>> hidden;
    if (max == null || packed.laneCount <= max) {
      bars = [
        for (final it in items)
          DayGridBar(segment: bySeg[it.key]!, lane: packed.lanes[it.key]!, pieces: [(from: it.start, to: it.end)]),
      ];
      hidden = [for (final _ in dates) const <String>[]];
    } else {
      final over = computeOverflow(packed.lanes, items, dates.length, max);
      final piecesOf = <String, List<({int from, int to})>>{};
      for (final p in over.pieces) {
        (piecesOf[p.key] ??= []).add((from: p.from, to: p.to));
      }
      bars = [
        for (final it in items)
          if (piecesOf.containsKey(it.key))
            DayGridBar(segment: bySeg[it.key]!, lane: packed.lanes[it.key]!, pieces: piecesOf[it.key]!),
      ];
      hidden = over.hiddenKeysPerDay;
    }
    weeks.add(
      DayGridWeek(
        dates: List.unmodifiable(dates),
        resources: List.unmodifiable(resources),
        background: List.unmodifiable(bgRows[r]),
        firstColumn: first,
        bars: List.unmodifiable(bars),
        laneCount: packed.laneCount,
        hiddenKeysPerDay: List.unmodifiable(hidden),
        segments: List.unmodifiable(rows[r]),
        outside: List.unmodifiable(outside),
        closed: List.unmodifiable(closed),
      ),
    );
  }
  final width = range.weeks.isEmpty ? 0 : range.weeks.first.length;
  final resourceList = o.resources ?? const <Resource>[];
  return DayGridModel(
    version: snap.version,
    range: range,
    options: o,
    weeks: List.unmodifiable(weeks),
    resourceHeads: [
      for (var k = 0; k < resourceList.length; k++)
        ResourceHead(resource: resourceList[k], from: k * width, count: width),
    ],
    groupHeads: o.resourceGroups,
  );
}

/// The model after a store change. Rebuilt from the snapshot (a month is a
/// few milliseconds), then every row the change did not touch — no dirty
/// day, no dirty instant in its span — takes back its previous object, so
/// the widgets skip it with `identical`.
DayGridModel updateDayGridModel(DayGridModel prev, StoreSnapshot snap, StoreChange change) {
  if (change.added.length + change.updated.length + change.removed.length + change.seriesChanged.length == 0) {
    return prev;
  }
  final next = buildDayGridModel(prev.range, snap, prev.options);
  // A series' occurrences may be in any week: no week can be kept on the strength of its spans.
  if (next.weeks.length != prev.weeks.length || change.seriesTouched.isNotEmpty) return next;
  var reused = 0;
  final zone = prev.options.displayZone;
  final weeks = [
    for (var i = 0; i < next.weeks.length; i++)
      () {
        final week = next.weeks[i];
        final old = prev.weeks[i];
        if (week.dates.isEmpty || old.dates.isEmpty || old.dates.first != week.dates.first) return week;
        final first = week.dates.first;
        final last = week.dates.last;
        final d0 = first.epochDay;
        final d1 = last.epochDay + 1;
        final s0 = first.startOfDayIn(zone).epochMilliseconds;
        final s1 = last.addDays(1).startOfDayIn(zone).epochMilliseconds;
        final touched =
            change.dirtyDays.any((x) => x.s < d1 && x.e > d0) || change.dirtySpans.any((x) => x.s < s1 && x.e > s0);
        if (touched) return week;
        reused++;
        return old;
      }(),
  ];
  return reused == 0 ? next : next._withWeeks(List.unmodifiable(weeks));
}

/// A month grid per month of the range: the month view's model, reused whole.
final class MultiMonthModel {
  const MultiMonthModel({required this.version, required this.range, required this.months});
  final int version;
  final ViewRange range;

  /// One month grid each; padding days are drawn empty (each date's events
  /// show in its own month only).
  final List<({PlainDate month, DayGridModel model})> months;
}

MultiMonthModel buildMultiMonthModel(ViewRange range, StoreSnapshot snap, DayGridOptions opts) {
  final o = opts.copyWith(showNonCurrentDates: false);
  return MultiMonthModel(
    version: snap.version,
    range: range,
    months: [
      for (final r in range.months ?? [range]) (month: r.activeStart, model: buildDayGridModel(r, snap, o)),
    ],
  );
}

/// Each month follows the store on its own: a month the change does not
/// touch keeps its object.
MultiMonthModel updateMultiMonthModel(MultiMonthModel prev, StoreSnapshot snap, StoreChange change) {
  var same = true;
  final months = [
    for (final m in prev.months)
      () {
        final model = updateDayGridModel(m.model, snap, change);
        // Every row kept: the month is unchanged, whatever the store's version says.
        final kept =
            identical(model, m.model) ||
            (model.weeks.length == m.model.weeks.length &&
                [
                  for (var i = 0; i < model.weeks.length; i++) identical(model.weeks[i], m.model.weeks[i]),
                ].every((x) => x));
        if (kept) return m;
        same = false;
        return (month: m.month, model: model);
      }(),
  ];
  return same ? prev : MultiMonthModel(version: snap.version, range: prev.range, months: months);
}
