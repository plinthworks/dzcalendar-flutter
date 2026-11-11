import '../event/problem.dart';
import '../event/types.dart';
import '../interaction/propose.dart';
import '../intervals.dart';
import '../layout/rows.dart';
import '../project/segment.dart';
import '../resource/rows.dart';
import '../resource/tree.dart';
import '../rules/business_hours.dart';
import '../store/changes.dart';
import '../store/instance.dart';
import '../store/store.dart';
import '../time/instant.dart';
import '../views/views.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'axis.dart';

/// What a timeline model is built from (the kernel fills it from its
/// options and resources).
final class TimelineOptions {
  const TimelineOptions({
    required this.displayZone,
    this.scale,
    this.rows,
    this.resources = const [],
    this.maxLanes = 3,
    this.fillLanes = 12,
    this.businessHours,
    this.eventFilter,
    this.onProblem,
  });

  final ZoneId displayZone;

  /// Minutes per slot (dividing a day) or days. Null: 30 minutes for a day,
  /// an hour up to a week, days beyond ([defaultScale]).
  final TimelineScale? scale;

  /// The rows of a resource timeline, in order: resources (with their depth
  /// and state), group heads, "Unassigned" ([flattenRows]). Null: one row of
  /// every event.
  final List<ResourceRow>? rows;

  /// Every resource the calendar knows: what "Unassigned" is the complement of.
  final List<Resource> resources;

  /// Lanes a resource row shows; past them, "+N" (rows of a fixed height).
  final int maxLanes;

  /// Lanes of the one row of a timeline without resources (it fills the view).
  final int fillLanes;

  /// Shaded outside, per row: a resource's own hours (read in its zone), else these.
  final BusinessHours? businessHours;

  /// Only the events it keeps are shown (the kernel's `eventFilter`).
  final bool Function(CalEvent event)? eventFilter;

  /// What expansion had to say (a series cut short).
  final void Function(Problem)? onProblem;
}

/// A stretch of the axis, in positions (nominal slots from its start).
final class TimelineSpan {
  const TimelineSpan(this.from, this.to);
  final double from;
  final double to;

  @override
  bool operator ==(Object other) => other is TimelineSpan && other.from == from && other.to == to;
  @override
  int get hashCode => Object.hash(from, to);
  @override
  String toString() => '[$from, $to)';
}

/// An event placed in its row, in axis positions. Its [segment] is cut to
/// the axis (`from`/`to` instants; an all-day event covers its dates in the
/// calendar's zone); `startsHere`/`endsHere` say whether it was cut there,
/// `dayIndex` and `part` are 0. An event on several resources is one bar
/// per row (the segment's key is `<instance key>|<row key>`): select and
/// move by `segment.instance`. [to] is where it is drawn up to — a marker's
/// flag, the axis's end — not the event's end: editing reads the event.
final class TimelineBar {
  const TimelineBar({required this.segment, required this.from, required this.to, required this.lane});
  final TimedSegment segment;
  final double from;
  final double to;
  final int lane;
}

/// Events a full row does not draw, standing in its last lane: one "+N" per
/// stretch where they run into one another. [events] in the order they
/// start (the longer first).
final class TimelineMore {
  const TimelineMore({required this.key, required this.from, required this.to, required this.events});
  final String key;
  final double from;
  final double to;
  final List<TimelineBar> events;
}

/// What a row draws: its events on lanes, "+N", its shading. Kept (the same
/// object) when the row did not change, so a widget skips it.
final class TimelineRowBody {
  const TimelineRowBody({
    required this.key,
    required this.events,
    required this.background,
    required this.more,
    required this.offHours,
    required this.lanes,
  });
  final String key;
  final List<TimelineBar> events;

  /// `display: background` events: the row's whole height, under the others.
  final List<TimelineBar> background;
  final List<TimelineMore> more;

  /// Stretches outside business hours.
  final List<TimelineSpan> offHours;

  /// Lanes drawn (at most the row's cap).
  final int lanes;
}

/// A row of a timeline: a resource, a group's head, or the one row of a
/// timeline without resources.
sealed class TimelineRow {
  const TimelineRow();

  /// Stable across rebuilds: `r:<id>`, `g:<value>`, `all`.
  String get key;
}

final class TimelineResourceRow extends TimelineRow {
  const TimelineResourceRow({required this.resource, required this.depth, required this.expanded, required this.body});
  final Resource resource;
  final int depth;

  /// Null: no children; else whether they are shown.
  final bool? expanded;
  final TimelineRowBody body;
  @override
  String get key => body.key;
}

final class TimelineGroupRow extends TimelineRow {
  const TimelineGroupRow({required this.key, required this.value, required this.count, required this.expanded});
  @override
  final String key;
  final String value;
  final int count;
  final bool expanded;
}

/// A timeline without resources: one row of every event.
final class TimelineAllRow extends TimelineRow {
  const TimelineAllRow(this.body);
  final TimelineRowBody body;
  @override
  String get key => body.key;
}

/// Everything a timeline draws, as data.
final class TimelineModel {
  const TimelineModel({
    required this.version,
    required this.range,
    required this.options,
    required this.axis,
    required this.rows,
    required this.maxLanes,
  });
  final int version;
  final ViewRange range;
  final TimelineOptions options;
  final TimelineAxis axis;
  final List<TimelineRow> rows;

  /// The lanes a row may show: `maxLanes`, or `fillLanes` without resources.
  final int maxLanes;

  TimelineModel _with({int? version, List<TimelineRow>? rows}) => TimelineModel(
    version: version ?? this.version,
    range: range,
    options: options,
    axis: axis,
    rows: rows ?? this.rows,
    maxLanes: maxLanes,
  );
}

bool _isBackground(EventInstance e) =>
    e.event.display == EventDisplay.background || e.event.display == EventDisplay.inverseBackground;

/// An event's span in epoch ms: an all-day one covers its dates in the calendar's zone.
(int, int) _spanOf(EventInstance inst, ZoneId zone) => switch (inst.event) {
  AllDayEvent(:final start, :final end) => () {
    final s = start.startOfDayIn(zone).epochMilliseconds;
    final e = end.startOfDayIn(zone).epochMilliseconds;
    return (s, e > s ? e : s);
  }(),
  TimedEvent(:final start, :final end) => (start.epochMilliseconds, end.epochMilliseconds),
};

/// Shading computed once per (hours, zone) in a build: 500 doctors sharing
/// the calendar's hours read the zone once.
typedef _Shading = Map<BusinessHours, Map<ZoneId, List<TimelineSpan>>>;

/// One row's events, lanes and "+N", and its shading.
TimelineRowBody _buildRow(
  String key,
  List<EventInstance> instances,
  TimelineAxis axis,
  TimelineOptions o,
  Resource? resource,
  int max,
  _Shading shading,
) {
  final a = axis.start.epochMilliseconds;
  final b = axis.end.epochMilliseconds;
  final unit = axis.slotMinutes * 60000;
  double pos(int ms) => (ms.clamp(a, b) - a) / unit;
  // The shortest drawn: a quarter of a slot (a milestone must still be seen, and take its lane).
  final minMs = unit ~/ 4;
  final bars = <({TimelineBar bar, int s, int e, int rank})>[];
  final background = <TimelineBar>[];
  for (var i = 0; i < instances.length; i++) {
    final inst = instances[i];
    final (s, e) = _spanOf(inst, o.displayZone);
    if (e < a || s >= b || (e == a && s < e)) continue;
    final segment = TimedSegment(
      key: '${inst.key}|$key',
      instance: inst,
      dayIndex: 0,
      part: 0,
      startsHere: s >= a,
      endsHere: e <= b,
      from: Instant.fromEpochMilliseconds(s > a ? s : a),
      to: Instant.fromEpochMilliseconds(e < b ? e : b),
    );
    // A marker is a moment: its line, and its flag three slots wide beside it — the room its lane keeps for the title.
    final flag = inst.event.display == EventDisplay.marker ? 3 * unit : 0;
    final drawnEnd = flag > 0 ? (s + flag < b ? s + flag : b) : e;
    final bar = TimelineBar(segment: segment, from: pos(s), to: pos(drawnEnd), lane: 0);
    if (_isBackground(inst)) {
      background.add(bar);
    } else {
      final s0 = s > a ? s : a;
      final e0 = (flag > 0 ? s + flag : e).clamp(s0, b);
      bars.add((bar: bar, s: s0, e: e0 > s0 + minMs ? e0 : s0 + minMs, rank: i));
    }
  }
  final packed = packLanes([
    for (final x in bars) RowItem(key: x.bar.segment.key, start: x.s, end: x.e, rank: [x.rank]),
  ]);
  final placed = [
    for (final x in bars)
      TimelineBar(segment: x.bar.segment, from: x.bar.from, to: x.bar.to, lane: packed.lanes[x.bar.segment.key]!),
  ];
  var events = placed;
  final more = <TimelineMore>[];
  if (packed.laneCount > max) {
    // The last lane holds "+N": the events from it down are behind the links, one per stretch.
    final keep = max - 1;
    events = [
      for (final p in placed)
        if (p.lane < keep) p,
    ];
    // Dart's sort is not stable (the web's is): ties keep the event order.
    final order = {for (final (n, p) in placed.indexed) p.segment.key: n};
    final hidden =
        [
          for (final p in placed)
            if (p.lane >= keep) p,
        ]..sort((x, y) {
          final c = x.from.compareTo(y.from);
          if (c != 0) return c;
          final d = y.to.compareTo(x.to);
          return d != 0 ? d : order[x.segment.key]!.compareTo(order[y.segment.key]!);
        });
    var run = <TimelineBar>[];
    var end = double.negativeInfinity;
    void close() {
      if (run.isNotEmpty) {
        more.add(
          TimelineMore(
            key: 'more|$key|${run.first.from}',
            from: run.first.from,
            to: end,
            events: List.unmodifiable(run),
          ),
        );
      }
    }

    const minPos = 0.25;
    for (final h in hidden) {
      if (h.from >= end) {
        close();
        run = [];
      }
      run.add(h);
      final reach = h.to > h.from + minPos ? h.to : h.from + minPos;
      if (reach > end) end = reach;
    }
    close();
  }
  return TimelineRowBody(
    key: key,
    events: List.unmodifiable(events),
    background: List.unmodifiable(background),
    more: List.unmodifiable(more),
    offHours: _offHoursOf(axis, o, resource, shading),
    lanes: packed.laneCount < 1 ? 1 : (packed.laneCount > max ? max : packed.laneCount),
  );
}

/// What is not open, as positions: a resource's own hours (in its zone), else the calendar's.
List<TimelineSpan> _offHoursOf(TimelineAxis axis, TimelineOptions o, Resource? resource, _Shading shading) {
  final hours = resource?.businessHours ?? o.businessHours;
  if (hours == null || hours.rules.isEmpty || axis.slots.isEmpty) return const [];
  final zone = resource?.timeZone ?? o.displayZone;
  final byZone = shading[hours] ??= {};
  return byZone[zone] ??= _shadeOf(axis, hours, zone);
}

List<TimelineSpan> _shadeOf(TimelineAxis axis, BusinessHours hours, ZoneId zone) {
  final first = axis.slots.first.date;
  final last = axis.slots.last.date;
  final open = businessIntervals(first.addDays(-1), last.addDays(2), hours, zone);
  // Counted in days: a day with no open hour at all is shaded, whole (a day's hours are not drawn there).
  if (axis.unit == TimelineUnit.day) {
    return List.unmodifiable([
      for (final sl in axis.slots)
        if (!open.any((x) => x.s < sl.end.epochMilliseconds && x.e > sl.start.epochMilliseconds))
          TimelineSpan(axis.toPosition(sl.start), axis.toPosition(sl.end)),
    ]);
  }
  final whole = [MsSpan(axis.start.epochMilliseconds, axis.end.epochMilliseconds)];
  return List.unmodifiable([
    for (final x in subtractSpans(whole, open))
      TimelineSpan(
        axis.toPosition(Instant.fromEpochMilliseconds(x.s)),
        axis.toPosition(Instant.fromEpochMilliseconds(x.e)),
      ),
  ]);
}

int _lanesOf(TimelineOptions o) => o.maxLanes < 1 ? 3 : o.maxLanes;
int _fillOf(TimelineOptions o) => o.fillLanes < 1 ? 12 : o.fillLanes;

/// Everything a row's body depends on besides its resource and the snapshot.
final class _BuildKey {
  _BuildKey(TimelineAxis axis, TimelineOptions o)
    : start = axis.start.epochMilliseconds,
      end = axis.end.epochMilliseconds,
      slotMinutes = axis.slotMinutes,
      zone = o.displayZone,
      lanes = _lanesOf(o),
      hours = o.businessHours,
      resources = o.resources,
      filter = o.eventFilter,
      onProblem = o.onProblem;
  final int start;
  final int end;
  final int slotMinutes;
  final ZoneId zone;
  final int lanes;
  final BusinessHours? hours;
  final List<Resource> resources;
  final bool Function(CalEvent)? filter;

  /// A build that says nothing (a `modelAt`) must not lend its rows to one that reports.
  final void Function(Problem)? onProblem;

  bool same(_BuildKey k) =>
      k.start == start &&
      k.end == end &&
      k.slotMinutes == slotMinutes &&
      k.zone == zone &&
      k.lanes == lanes &&
      k.hours == hours &&
      identical(k.resources, resources) &&
      k.filter == filter &&
      k.onProblem == onProblem;
}

/// The last build per snapshot: what its rows were made from, and the rows —
/// a fold (a resource's children shown or hidden) reuses them.
final _last = Expando<({_BuildKey key, Map<String, TimelineRowBody> bodies})>();

final class _Build {
  _Build(this.reuse);
  final _Shading shading = {};
  final Map<String, TimelineRowBody>? reuse;
  final Map<String, TimelineRowBody> made = {};
}

List<EventInstance> _query(StoreSnapshot snap, ViewWindow w, TimelineOptions o, Resource? resource) => resource != null
    ? instancesOf(snap, w, resource, o.resources, QueryOptions(onProblem: o.onProblem, where: o.eventFilter))
    : snap.queryInstances(w, QueryOptions(onProblem: o.onProblem, where: o.eventFilter));

TimelineRow _rowOf(
  ResourceRow row,
  StoreSnapshot snap,
  TimelineAxis axis,
  ViewRange range,
  TimelineOptions o,
  _Build b,
) {
  switch (row) {
    case GroupRow(:final value, :final count, :final expanded):
      return TimelineGroupRow(key: row.rowKey, value: value, count: count, expanded: expanded);
    case ResourceItemRow(:final resource, :final depth, :final expanded):
      final key = row.rowKey;
      final body =
          b.reuse?[key] ??
          _buildRow(
            key,
            _query(snap, viewWindow(range.start, range.end, o.displayZone), o, resource),
            axis,
            o,
            resource,
            _lanesOf(o),
            b.shading,
          );
      b.made[key] = body;
      return TimelineResourceRow(resource: resource, depth: depth, expanded: expanded, body: body);
  }
}

/// Everything a timeline draws, as data: the elapsed axis, and per row its
/// events on lanes (at most `maxLanes`, the rest behind "+N"), its shading.
/// Pure — the same snapshot and options give the same model.
TimelineModel buildTimelineModel(ViewRange range, StoreSnapshot snap, TimelineOptions o) {
  final axis = buildTimelineAxis(range, o.displayZone, scale: o.scale);
  final rows = o.rows;
  if (rows == null) {
    final fill = _fillOf(o);
    final body = _buildRow(
      'all',
      _query(snap, viewWindow(range.start, range.end, o.displayZone), o, null),
      axis,
      o,
      null,
      fill,
      {},
    );
    return TimelineModel(
      version: snap.version,
      range: range,
      options: o,
      axis: axis,
      rows: [TimelineAllRow(body)],
      maxLanes: fill,
    );
  }
  final key = _BuildKey(axis, o);
  final last = _last[snap];
  final b = _Build(last != null && last.key.same(key) ? last.bodies : null);
  final out = List<TimelineRow>.unmodifiable([for (final r in rows) _rowOf(r, snap, axis, range, o, b)]);
  _last[snap] = (key: key, bodies: {...?b.reuse, ...b.made});
  return TimelineModel(version: snap.version, range: range, options: o, axis: axis, rows: out, maxLanes: _lanesOf(o));
}

/// The model after a store change: only the rows of the resources an event
/// left or joined are rebuilt ("Unassigned" when an event is on no known
/// resource); the others keep their identity, so the widget skips them. A
/// touched series may be anywhere: every row is rebuilt.
TimelineModel updateTimelineModel(TimelineModel prev, StoreSnapshot snap, StoreChange change) {
  if (change.version == prev.version || change.isEmpty) return prev;
  final o = prev.options;
  final a = prev.axis.start.epochMilliseconds;
  final b = prev.axis.end.epochMilliseconds;
  if (!change.dirtySpans.any((x) => x.s < b && x.e > a) && change.dirtyDays.isEmpty && change.seriesTouched.isEmpty) {
    return prev;
  }
  final rows = o.rows;
  if (rows == null || change.seriesTouched.isNotEmpty) {
    final next = buildTimelineModel(prev.range, snap, o);
    return prev._with(version: next.version, rows: next.rows);
  }
  final known = {for (final r in o.resources) r.id};
  final touched = <String>{};
  for (final m in change.applied) {
    if (m is! EventMutation) continue;
    for (final ev in [m.before, m.after]) {
      if (ev == null) continue;
      touched.addAll(ev.resourceIds);
      if (!ev.resourceIds.any(known.contains)) touched.add(unassignedId);
    }
  }
  var changed = false;
  final next = <TimelineRow>[];
  for (var i = 0; i < prev.rows.length; i++) {
    final row = prev.rows[i];
    if (row is! TimelineResourceRow || !touched.contains(row.resource.id)) {
      next.add(row);
      continue;
    }
    changed = true;
    next.add(_rowOf(rows[i], snap, prev.axis, prev.range, o, _Build(null)));
  }
  return changed ? prev._with(version: snap.version, rows: List.unmodifiable(next)) : prev;
}

/// Where "now" is on the axis, or null outside it. Kept out of the memoized
/// model: it moves every minute.
double? timelineNow(TimelineModel model, Instant now) {
  final t = now.epochMilliseconds;
  return t >= model.axis.start.epochMilliseconds && t < model.axis.end.epochMilliseconds
      ? model.axis.toPosition(now)
      : null;
}

/// A point of a timeline as calendar terms: row [row] (an index of the
/// model's rows) and [position] along the axis (nominal slots from its
/// start), as the widget measures it. A moment ([SlotHit]) on a scale of
/// minutes, a day ([DayHit]) on a scale of days; on a resource's row, its
/// resource. The axis is elapsed time, so every position is a moment that
/// exists (no gap, no second reading). Null for a group's head or an index
/// outside the model.
Hit? timelineHitAt(TimelineModel model, int row, double position) {
  if (row < 0 || row >= model.rows.length) return null;
  final r = model.rows[row];
  if (r is TimelineGroupRow) return null;
  final axis = model.axis;
  final s = axis.start.epochMilliseconds;
  final e = axis.end.epochMilliseconds;
  // Clamped in milliseconds: a hair short of the end in slots rounds to the end itself (the next midnight)
  // on a fine scale — 1e-6 of five minutes is 0.3 ms.
  final ms = axis.fromPosition(position.isNaN ? 0.0 : position).epochMilliseconds;
  final at = Instant.fromEpochMilliseconds(e > s ? ms.clamp(s, e - 1) : s);
  final date = ZonedDateTime(at, model.options.displayZone).date;
  final owner = r is TimelineResourceRow ? r.resource.id : null;
  return axis.unit == TimelineUnit.day
      ? DayHit(date: date, resourceId: owner)
      : SlotHit(date: date, instant: at, resourceId: owner);
}
