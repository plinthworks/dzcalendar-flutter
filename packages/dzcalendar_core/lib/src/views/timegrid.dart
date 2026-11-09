import '../event/problem.dart';
import '../event/types.dart';
import '../intervals.dart';
import '../layout/column.dart';
import '../layout/rows.dart';
import '../project/segment.dart';
import '../project/time_axis.dart';
import '../resource/rows.dart';
import '../resource/tree.dart';
import '../rules/business_hours.dart';
import '../slots/types.dart' show Slot;
import '../store/changes.dart';
import '../store/instance.dart';
import '../store/store.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../util/js.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'daygrid.dart';
import 'views.dart';

final class TimeGridOptions {
  const TimeGridOptions({
    required this.displayZone,
    this.axis = AxisMode.wall,
    this.slotMin = Duration.zero,
    this.slotMax = const Duration(hours: 24),
    this.minEventMinutes = 15,
    this.slotMinutes = 60,
    this.labelMinutes = 60,
    this.resourceId,
    this.resources,
    this.resourceGroups = const [],
    this.availableSlots = const [],
    this.businessHours,
    this.maxStack,
    this.onProblem,
  });

  final ZoneId displayZone;

  /// Where the queries' problems go (a series cut short there).
  final void Function(Problem)? onProblem;

  /// `wall`: every day's rows aligned, a clock change marked; `elapsed`:
  /// real time drawn to scale.
  final AxisMode axis;

  /// The first hour shown, and the end of the last (up to 24 hours).
  final Duration slotMin;
  final Duration slotMax;

  /// The shortest an event is drawn, in minutes.
  final double minEventMinutes;

  /// Gutter tick step, and a label every this many minutes of the clock.
  final double slotMinutes;
  final int labelMinutes;

  /// Only this resource's events.
  final String? resourceId;

  /// A resource view: one column per resource and date, resources first.
  /// Each column shows that resource's events and its own business hours
  /// (read in its zone).
  final List<Resource>? resources;
  final List<ResourceGroupHead> resourceGroups;

  /// Bookable slots to draw (what `findSlots` gives): each column gets the
  /// ones in its hours.
  final List<AvailableSlot> availableSlots;

  /// Hours outside are shaded (`offHours` on each column).
  final BusinessHours? businessHours;

  /// Overlapping events side by side, at most: a cluster wider keeps
  /// `maxStack - 1` lanes and puts the rest behind "+N" links in the last
  /// one. Null, or under 1: no limit.
  final int? maxStack;
}

/// A slot that can be booked, as the time grid draws it.
final class AvailableSlot {
  const AvailableSlot({required this.start, required this.end, this.resourceId, this.seats});

  /// A slot of `findSlots`, for [resourceId]'s columns (every column without).
  AvailableSlot.of(Slot slot, {String? resourceId, int? seats})
    : this(start: slot.start.instant, end: slot.end.instant, resourceId: resourceId, seats: seats);

  final Instant start;
  final Instant end;

  /// In a resource view, only that resource's columns show it; without, every column does.
  final String? resourceId;

  /// Seats still free: said and shown beside its time.
  final int? seats;

  @override
  bool operator ==(Object other) =>
      other is AvailableSlot &&
      other.start == start &&
      other.end == end &&
      other.resourceId == resourceId &&
      other.seats == seats;

  @override
  int get hashCode => Object.hash(start, end, resourceId, seats);
}

/// A slot placed in a column, in axis minutes.
final class PlacedSlot {
  const PlacedSlot({required this.key, required this.top, required this.height, required this.slot});

  /// `start-end` in epoch ms: what the widgets key the slot on.
  final String key;
  final double top;
  final double height;
  final AvailableSlot slot;

  PlacedSlot _cut(double height) => PlacedSlot(key: key, top: top, height: height, slot: slot);
}

/// How a moment reads on a day the clocks change: its offset in the display
/// zone, and which pass of a repeated hour (`02:30`, `02:30*`).
final class Reading {
  const Reading(this.offset, this.pass);
  final String offset;
  final WallPass? pass;

  @override
  bool operator ==(Object other) => other is Reading && other.offset == offset && other.pass == pass;

  @override
  int get hashCode => Object.hash(offset, pass);

  @override
  String toString() => '$offset${pass == null ? '' : ' ${pass!.name}'}';
}

/// A timed piece placed in its column: vertical in axis minutes, horizontal in fractions.
final class PlacedTimed {
  const PlacedTimed({
    required this.segment,
    required this.top,
    required this.height,
    required this.visualHeight,
    required this.left,
    required this.width,
    required this.lane,
    required this.lanes,
    required this.z,
    this.startReading,
    this.endReading,
    this.realMinutes,
  });

  final TimedSegment segment;
  final double top;

  /// True height on the axis; may be 0 (a milestone).
  final double height;

  /// What is drawn: at least the minimum event height, never past the column.
  final double visualHeight;
  final double left;
  final double width;
  final int lane;
  final int lanes;
  final int z;

  /// How the *event's* start and end read — present only on days with a
  /// clock change. The end is read as an end: one at 03:00 of the first
  /// pass belongs to the first pass.
  final Reading? startReading;
  final Reading? endReading;

  /// Real elapsed minutes of the whole event, on days with a clock change.
  final double? realMinutes;
}

/// Events a crowded cluster does not draw, standing in its last lane: one
/// "+N" per stretch of time.
final class MoreTimed {
  const MoreTimed({
    required this.key,
    required this.top,
    required this.height,
    required this.left,
    required this.width,
    required this.events,
  });
  final String key;
  final double top;
  final double height;
  final double left;
  final double width;

  /// The hidden events, in order.
  final List<PlacedTimed> events;
}

final class TimeGridColumn {
  const TimeGridColumn({
    required this.key,
    required this.date,
    required this.resource,
    required this.axis,
    required this.folded,
    required this.events,
    required this.background,
    required this.outside,
    required this.more,
    required this.offHours,
    required this.slots,
  });

  /// The date, and the resource's id after a `|` in a resource view.
  final String key;
  final PlainDate date;
  final Resource? resource;
  final ColumnAxis axis;

  /// A day the zone skipped: drawn folded, with nothing in it.
  final bool folded;
  final List<PlacedTimed> events;

  /// `display: background` events: full width, under the others.
  final List<PlacedTimed> background;

  /// Ids of the timed events of this day entirely outside the hours shown.
  final List<String> outside;
  final List<MoreTimed> more;

  /// Stretches outside business hours, in axis minutes.
  final List<({double top, double height})> offHours;
  final List<PlacedSlot> slots;
}

final class AllDayBar {
  const AllDayBar({required this.segment, required this.lane, required this.column});
  final Segment segment;
  final int lane;

  /// The first column it is drawn over.
  final int column;
}

final class TimeGridAllDay {
  const TimeGridAllDay({required this.bars, required this.lanes, required this.background});
  final List<AllDayBar> bars;
  final int lanes;
  final List<AllDayBar> background;
}

final class TimeGridModel {
  const TimeGridModel({
    required this.version,
    required this.range,
    required this.options,
    required this.columns,
    required this.gutter,
    required this.allDay,
    required this.resourceHeads,
    required this.groupHeads,
  });

  final int version;
  final ViewRange range;
  final TimeGridOptions options;
  final List<TimeGridColumn> columns;

  /// Graduations for the left gutter, from an ordinary column when there is one.
  final List<AxisTick> gutter;
  final TimeGridAllDay allDay;
  final List<ResourceHead> resourceHeads;
  final List<ResourceGroupHead> groupHeads;

  TimeGridModel _with({required int version, required List<TimeGridColumn> columns, required TimeGridAllDay allDay}) =>
      TimeGridModel(
        version: version,
        range: range,
        options: options,
        columns: columns,
        gutter: gutter,
        allDay: allDay,
        resourceHeads: resourceHeads,
        groupHeads: groupHeads,
      );
}

ColumnAxis _axisFor(PlainDate date, TimeGridOptions o) =>
    buildColumnAxis(date, o.displayZone, mode: o.axis, slotMin: o.slotMin, slotMax: o.slotMax);

List<EventInstance> _query(StoreSnapshot snap, ViewWindow w, TimeGridOptions o, Resource? resource) => resource != null
    ? instancesOf(snap, w, resource, o.resources ?? const [], QueryOptions(onProblem: o.onProblem))
    : snap.queryInstances(w, QueryOptions(resourceId: o.resourceId, onProblem: o.onProblem));

String _columnKey(PlainDate date, Resource? resource) => resource != null ? '$date|${resource.id}' : '$date';

Reading _readingOf(Instant i, ZoneId zone, List<Transition> repeats) {
  final ms = i.epochMilliseconds;
  WallPass? pass;
  for (final t in repeats) {
    final at = t.at.epochMilliseconds;
    final span = (-t.deltaMinutes * 60000).round();
    if (ms >= at && ms < at + span) {
      pass = WallPass.second;
    } else if (ms >= at - span && ms < at) {
      pass = WallPass.first;
    }
  }
  return Reading(ZonedDateTime(i, zone).offset, pass);
}

/// How an end reads: its clock face is that of the moment just before it,
/// marked as the second pass only when it lies inside that pass.
Reading _endReadingOf(Instant start, Instant end, ZoneId zone, List<Transition> repeats) {
  if (end == start) return _readingOf(end, zone, repeats);
  final before = _readingOf(end.addMs(-1), zone, repeats);
  final at = _readingOf(end, zone, repeats);
  final pass = before.pass == at.pass ? before.pass : (before.pass == WallPass.first ? WallPass.first : null);
  return Reading(before.offset, pass);
}

/// One day column: its axis, its events placed side by side. Queries only
/// that day, so [updateTimeGridModel] can rebuild one column and keep the
/// others.
TimeGridColumn buildTimeGridColumn(
  PlainDate date,
  StoreSnapshot snap,
  TimeGridOptions o, {
  ColumnAxis? axis,
  Resource? resource,
}) {
  final ax = axis ?? _axisFor(date, o);
  final key = _columnKey(date, resource);
  if (ax.length == 0) {
    return TimeGridColumn(
      key: key,
      date: date,
      resource: resource,
      axis: ax,
      folded: true,
      events: const [],
      background: const [],
      outside: const [],
      more: const [],
      offHours: const [],
      slots: const [],
    );
  }
  final day = ax.day;
  final instances = _query(snap, viewWindow(date, date.addDays(1), o.displayZone), o, resource);
  final order = {for (var i = 0; i < instances.length; i++) instances[i].key: i};

  // Only what falls inside the axis's hours: an event at 22:00 in an
  // 08:00–20:00 grid is not drawn as a sliver at the bottom. A piece cut by
  // the axis loses its rounded end, like one cut by midnight.
  final aStart = ax.start.epochMilliseconds;
  final aEnd = ax.end.epochMilliseconds;
  final segs = <TimedSegment>[];
  final outside = <String>{};
  for (final inst in instances) {
    if (inst.event.allDay) {
      // An all-day background (a closed day) tints the whole column too, every hour shown.
      if (inst.event.display == EventDisplay.background) {
        segs.add(
          TimedSegment(
            key: '${inst.key}|day${resource != null ? '|${resource.id}' : ''}',
            instance: inst,
            dayIndex: 0,
            part: 0,
            startsHere: true,
            endsHere: true,
            from: ax.start,
            to: ax.end,
          ),
        );
      }
      continue;
    }
    for (final seg in segmentTimed(inst, [day], cutAtRepeat: o.axis == AxisMode.wall)) {
      final f = seg.from.epochMilliseconds;
      final t = seg.to.epochMilliseconds;
      final inside = f == t ? f >= aStart && f < aEnd : t > aStart && f < aEnd;
      if (!inside) {
        if (!isBackground(inst.event.display)) outside.add(inst.event.id);
        continue;
      }
      final cut = f >= aStart && t <= aEnd
          ? seg
          : seg.placed(startsHere: seg.startsHere && f >= aStart, endsHere: seg.endsHere && t <= aEnd);
      // An event on two resources has a piece in each column: each its own key.
      segs.add(resource != null ? cut.placed(key: '${cut.key}|${resource.id}') : cut);
    }
  }

  final minVisual = o.minEventMinutes;
  final repeats = [
    for (final t in day.transitions)
      if (t.kind == TransitionKind.repeat) t,
  ];
  final changeDay = day.transitions.isNotEmpty;
  PlacedTimed place(TimedSegment seg, double left, double width, int lane, int lanes, int z) {
    final top = ax.toPosition(seg.from);
    final h = ax.toEndPosition(seg.to) - top;
    final height = h > 0 ? h : 0.0;
    final room = ax.length - top;
    final visual = height > minVisual ? height : minVisual;
    final ev = seg.instance.event;
    final timed = changeDay && ev is TimedEvent ? ev : null;
    return PlacedTimed(
      segment: seg,
      top: top,
      height: height,
      visualHeight: room < visual ? room : visual,
      left: left,
      width: width,
      lane: lane,
      lanes: lanes,
      z: z,
      startReading: timed == null ? null : _readingOf(timed.start.instant, o.displayZone, repeats),
      endReading: timed == null ? null : _endReadingOf(timed.start.instant, timed.end.instant, o.displayZone, repeats),
      realMinutes: timed == null ? null : (timed.end.epochMilliseconds - timed.start.epochMilliseconds) / 60000,
    );
  }

  final fg = [
    for (final s in segs)
      if (!isBackground(s.instance.event.display)) s,
  ];
  final placements = layoutColumn([
    for (final seg in fg)
      () {
        final top = ax.toPosition(seg.from);
        final end = ax.toEndPosition(seg.to);
        return ColItem(key: seg.key, start: top, end: end > top ? end : top, order: order[seg.instance.key] ?? 0);
      }(),
  ], minVisual: minVisual);
  final byKey = {for (final s in fg) s.key: s};
  final background = [
    for (final s in segs)
      if (isBackground(s.instance.event.display)) place(s, 0, 1, 0, 1, -1),
  ];
  final offHours = _offHoursOf(date, ax, o, resource);
  final slots = _slotsOf(ax, o, resource);
  // A bad limit is no limit.
  final max = o.maxStack != null && o.maxStack! >= 1 ? o.maxStack : null;
  TimeGridColumn column(List<PlacedTimed> events, List<MoreTimed> more) => TimeGridColumn(
    key: key,
    date: date,
    resource: resource,
    axis: ax,
    folded: false,
    events: List.unmodifiable(events),
    background: List.unmodifiable(background),
    outside: List.unmodifiable(outside),
    more: List.unmodifiable(more),
    offHours: offHours,
    slots: slots,
  );
  if (max == null || !placements.any((p) => p.lanes > max)) {
    return column([for (final p in placements) place(byKey[p.key]!, p.left, p.width, p.lane, p.lanes, p.z)], const []);
  }
  // A cluster wider than `max`: its first `max - 1` lanes are drawn, as wide as
  // `max` lanes allow; the others go behind "+N" in lane `max - 1`, one link per
  // stretch where hidden events run into one another.
  final keep = max - 1;
  final events = <PlacedTimed>[];
  final hidden = <PlacedTimed>[];
  for (final p in placements) {
    final seg = byKey[p.key]!;
    if (p.lanes <= max) {
      events.add(place(seg, p.left, p.width, p.lane, p.lanes, p.z));
      continue;
    }
    if (p.lane >= keep) {
      hidden.add(place(seg, keep / max, 1 / max, keep, max, p.z));
      continue;
    }
    final span = jsRound(p.width * p.lanes);
    final to = p.lane + span < keep ? p.lane + span : keep;
    events.add(place(seg, p.lane / max, (to - p.lane) / max, p.lane, max, p.z));
  }
  // Stable, as the web's sort: equal ones stay in the layout's order.
  final rank = {for (var i = 0; i < hidden.length; i++) hidden[i]: i};
  hidden.sort((a, b) {
    var c = a.top.compareTo(b.top);
    if (c != 0) return c;
    c = b.visualHeight.compareTo(a.visualHeight);
    return c != 0 ? c : rank[a]!.compareTo(rank[b]!);
  });
  final more = <MoreTimed>[];
  var run = <PlacedTimed>[];
  var end = double.negativeInfinity;
  void close() {
    if (run.isEmpty) return;
    final top = run.first.top;
    final h = end - top;
    more.add(
      MoreTimed(
        key: 'more|$key|${jsText(top)}|${more.length}',
        top: top,
        height: h > minVisual ? h : minVisual,
        left: keep / max,
        width: 1 / max,
        events: List.unmodifiable(run),
      ),
    );
  }

  for (final h in hidden) {
    if (h.top >= end) {
      close();
      run = [];
    }
    run.add(h);
    final e = h.top + h.visualHeight;
    if (e > end) end = e;
  }
  close();
  return column(events, more);
}

/// The slots this axis shows, placed and cut to it. A slot drawn under the
/// next one's start stops there: with a step shorter than the duration,
/// each start keeps a part of its own to click.
List<PlacedSlot> _slotsOf(ColumnAxis axis, TimeGridOptions o, Resource? resource) {
  if (o.availableSlots.isEmpty) return const [];
  final a = axis.start.epochMilliseconds;
  final b = axis.end.epochMilliseconds;
  final found = <String, PlacedSlot>{};
  for (final slot in o.availableSlots) {
    if (resource != null && slot.resourceId != null && slot.resourceId != resource.id) continue;
    final s = slot.start.epochMilliseconds;
    final e = slot.end.epochMilliseconds;
    if (e <= s || e <= a || s >= b) continue;
    final key = '$s-$e';
    if (found.containsKey(key)) continue;
    final top = s <= a ? 0.0 : axis.toPosition(slot.start);
    final bottom = e >= b ? axis.length : axis.toEndPosition(slot.end);
    found[key] = PlacedSlot(key: key, top: top, height: bottom - top > 0 ? bottom - top : 0, slot: slot);
  }
  // Stable, as the web's sort: the two passes of a repeated hour share positions on a wall axis.
  final given = found.values.toList();
  final rank = {for (var i = 0; i < given.length; i++) given[i]: i};
  final out = given
    ..sort((x, y) {
      var c = x.top.compareTo(y.top);
      if (c != 0) return c;
      c = x.height.compareTo(y.height);
      return c != 0 ? c : rank[x]!.compareTo(rank[y]!);
    });
  return List.unmodifiable([
    for (var i = 0; i < out.length; i++)
      () {
        final x = out[i];
        for (var j = i + 1; j < out.length; j++) {
          final y = out[j];
          if (y.top > x.top) return y.top < x.top + x.height ? x._cut(y.top - x.top) : x;
        }
        return x;
      }(),
  ]);
}

/// What is not open, inside the axis's hours, as positions. A resource's
/// own hours win over the calendar's, and are read in its zone.
List<({double top, double height})> _offHoursOf(
  PlainDate date,
  ColumnAxis axis,
  TimeGridOptions o,
  Resource? resource,
) {
  final hours = resource?.businessHours ?? o.businessHours;
  if (hours == null || hours.rules.isEmpty) return const [];
  final zone = resource?.timeZone ?? o.displayZone;
  // The resource's dates around this one: its zone may be a day ahead or behind.
  final open = zone == o.displayZone
      ? businessIntervals(date, date.addDays(1), hours, zone)
      : businessIntervals(date.addDays(-1), date.addDays(2), hours, zone);
  final closed = subtractSpans([MsSpan(axis.start.epochMilliseconds, axis.end.epochMilliseconds)], open);
  return List.unmodifiable([
    for (final x in closed)
      () {
        final top = axis.toPosition(Instant.fromEpochMilliseconds(x.s));
        final h = axis.toEndPosition(Instant.fromEpochMilliseconds(x.e)) - top;
        return (top: top, height: h > 0 ? h : 0.0);
      }(),
  ]);
}

TimeGridAllDay _buildAllDay(ViewRange range, StoreSnapshot snap, TimeGridOptions o) {
  final view = DateIndex(range.dates);
  final n = range.dates.length;
  final bars = <({Segment segment, int column})>[];
  final background = <AllDayBar>[];
  final order = <String, int>{};
  final owners = <Resource?>[...?o.resources];
  if (o.resources == null) owners.add(null);
  for (var r = 0; r < owners.length; r++) {
    final resource = owners[r];
    final instances = [
      for (final i in _query(snap, viewWindow(range.start, range.end, o.displayZone), o, resource))
        if (i.event.allDay) i,
    ];
    for (var i = 0; i < instances.length; i++) {
      order[instances[i].key] = i;
    }
    for (final inst in instances) {
      for (final seg in segmentAllDay(inst, view)) {
        final segment = resource != null ? seg.placed(key: '${seg.key}|${resource.id}') : seg;
        final column = r * n + seg.dayIndex;
        if (isBackground(inst.event.display)) {
          background.add(AllDayBar(segment: segment, lane: 0, column: column));
        } else {
          bars.add((segment: segment, column: column));
        }
      }
    }
  }
  final packed = packLanes([
    for (final b in bars)
      RowItem(
        key: b.segment.key,
        start: b.column,
        end: b.column + b.segment.dayCount,
        rank: [order[b.segment.instance.key] ?? 0],
      ),
  ]);
  return TimeGridAllDay(
    bars: List.unmodifiable([
      for (final b in bars) AllDayBar(segment: b.segment, lane: packed.lanes[b.segment.key]!, column: b.column),
    ]),
    lanes: packed.laneCount,
    background: List.unmodifiable(background),
  );
}

List<AxisTick> _gutterOf(List<TimeGridColumn> columns, TimeGridOptions o) {
  TimeGridColumn? ordinary;
  for (final c in columns) {
    if (!c.folded && c.axis.day.transitions.isEmpty) {
      ordinary = c;
      break;
    }
  }
  ordinary ??= columns.where((c) => !c.folded).firstOrNull;
  return ordinary == null ? const [] : ordinary.axis.ticks(o.slotMinutes, o.labelMinutes);
}

/// Everything a time grid draws, as data: per shown day, its axis (with DST
/// bands), its events placed side by side; above, the all-day row; at the
/// left, the gutter. Pure — the same snapshot and options give the same model.
TimeGridModel buildTimeGridModel(ViewRange range, StoreSnapshot snap, TimeGridOptions o) {
  // The axis is the day's in the calendar's zone: built once per date, shared by every resource's column.
  final axes = [for (final d in range.dates) _axisFor(d, o)];
  final resources = o.resources;
  final columns = [
    if (resources != null)
      for (final r in resources)
        for (var i = 0; i < range.dates.length; i++)
          buildTimeGridColumn(range.dates[i], snap, o, axis: axes[i], resource: r)
    else
      for (var i = 0; i < range.dates.length; i++) buildTimeGridColumn(range.dates[i], snap, o, axis: axes[i]),
  ];
  final n = range.dates.length;
  return TimeGridModel(
    version: snap.version,
    range: range,
    options: o,
    columns: List.unmodifiable(columns),
    gutter: _gutterOf(columns, o),
    allDay: _buildAllDay(range, snap, o),
    resourceHeads: [
      for (var r = 0; r < (resources?.length ?? 0); r++) ResourceHead(resource: resources![r], from: r * n, count: n),
    ],
    groupHeads: o.resourceGroups,
  );
}

bool _overlaps(int s, int e, List<MsSpan> spans) => spans.any((x) => x.s < e && x.e > s);

/// The model after a store change, rebuilding only what the change touched:
/// columns whose day overlaps a dirty span, and the all-day row if an
/// all-day event moved. Untouched columns keep their identity. Returns
/// [prev] itself when nothing it shows changed.
TimeGridModel updateTimeGridModel(TimeGridModel prev, StoreSnapshot snap, StoreChange change) {
  if (change.version == prev.version ||
      change.added.length + change.updated.length + change.removed.length + change.seriesChanged.length == 0) {
    return prev;
  }
  final o = prev.options;
  // A series' occurrences may fall in any column: a touched series rebuilds them all.
  final everything = change.seriesTouched.isNotEmpty;
  var touched = false;
  final columns = [
    for (final col in prev.columns)
      if (col.folded ||
          (!everything &&
              !_overlaps(col.axis.start.epochMilliseconds, col.axis.end.epochMilliseconds, change.dirtySpans)))
        col
      else
        () {
          touched = true;
          return buildTimeGridColumn(col.date, snap, o, axis: col.axis, resource: col.resource);
        }(),
  ];
  final dates = prev.range.dates;
  final dayLo = dates.isEmpty ? 0 : dates.first.epochDay;
  final dayHi = dates.isEmpty ? 0 : dates.last.epochDay + 1;
  final allDayDirty = everything || _overlaps(dayLo, dayHi, change.dirtyDays);
  if (!touched && !allDayDirty) return prev;
  return prev._with(
    version: snap.version,
    columns: List.unmodifiable(columns),
    allDay: allDayDirty ? _buildAllDay(prev.range, snap, o) : prev.allDay,
  );
}

/// Where "now" falls: which column, how far down — the first, and in a
/// resource view every resource's column of that day. Kept out of the
/// model: it moves every minute.
({int column, List<int> columns, double position})? locateNow(TimeGridModel model, Instant now) {
  final t = now.epochMilliseconds;
  final columns = [
    for (var i = 0; i < model.columns.length; i++)
      if (!model.columns[i].folded &&
          model.columns[i].axis.start.epochMilliseconds <= t &&
          t < model.columns[i].axis.end.epochMilliseconds)
        i,
  ];
  if (columns.isEmpty) return null;
  return (column: columns.first, columns: columns, position: model.columns[columns.first].axis.toPosition(now));
}
