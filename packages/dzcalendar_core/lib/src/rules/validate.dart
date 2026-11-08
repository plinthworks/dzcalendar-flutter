import '../event/types.dart';
import '../intervals.dart';
import '../resource/tree.dart';
import '../store/instance.dart';
import '../store/store.dart';
import '../time/plain.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'business_hours.dart';
import 'constraint.dart';

/// Where an event is proposed to go — a move, a resize, an edit, whoever
/// asks: the [event] as it is and as it would be ([proposed]: its start, end
/// and resources are what is checked).
final class Placement {
  const Placement({required this.event, required this.proposed, this.external = false});

  final CalEvent event;
  final CalEvent proposed;

  /// It comes from outside this calendar (a widget of the page, another
  /// calendar): an `allow` may take it or not.
  final bool external;

  List<ResourceId> get resourceIds => proposed.resourceIds;
}

enum ViolationCode {
  constraint('constraint'),
  overlap('overlap'),
  allow('allow'),
  validRange('valid-range'),
  notEditable('not-editable');

  const ViolationCode(this.code);

  /// The TypeScript core's spelling.
  final String code;
}

/// What stands in the way: the [eventId] moved, and a [detail] (the resource
/// whose constraint refused, the event in the way, `start`/`duration`/
/// `resource` for what is not editable, `before`/`after` for the range).
final class Violation {
  const Violation(this.code, this.eventId, [this.detail]);
  final ViolationCode code;
  final EventId eventId;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is Violation && other.code == code && other.eventId == eventId && other.detail == detail;

  @override
  int get hashCode => Object.hash(code, eventId, detail);

  @override
  String toString() => '${code.code}(${detail ?? ''}) on $eventId';
}

/// Whether [moving] may sit over [still].
typedef OverlapFn = bool Function(CalEvent still, CalEvent moving);

/// Days outside it are not reachable; [end] is exclusive.
final class ValidRange {
  const ValidRange({this.start, this.end});
  final PlainDate? start;
  final PlainDate? end;

  @override
  bool operator ==(Object other) => other is ValidRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The calendar's rules: what [validateProposal] checks.
final class RulesContext {
  const RulesContext({
    required this.displayZone,
    this.businessHours,
    this.constraint,
    this.overlap,
    this.allow,
    this.validRange,
    this.resources,
  });

  final ZoneId displayZone;
  final BusinessHours? businessHours;
  final ConstraintSpec? constraint;

  /// Null (the default): events may overlap. [noOverlap]: none may
  /// (backgrounds aside). Another function decides pair by pair.
  final OverlapFn? overlap;

  /// The application's last word, asked only when nothing else refused.
  final bool Function(Placement p)? allow;
  final ValidRange? validRange;

  /// Each resource an event goes on checks its own `eventConstraint` (else
  /// the calendar's) against its own business hours in its own zone, and its
  /// `eventOverlap` decides for the events it shares.
  final ResourceTree? resources;

  /// No event may sit over another (the web's `overlap: false`).
  static bool noOverlap(CalEvent still, CalEvent moving) => false;

  /// Functions compare by identity (pass the same one, or [noOverlap]).
  @override
  bool operator ==(Object other) =>
      other is RulesContext &&
      other.displayZone == displayZone &&
      other.businessHours == businessHours &&
      other.constraint == constraint &&
      other.overlap == overlap &&
      other.allow == allow &&
      other.validRange == validRange &&
      identical(other.resources, resources);

  @override
  int get hashCode => Object.hash(displayZone, businessHours, constraint, overlap, allow, validRange, resources);
}

/// The instances around many proposals, queried once (a series checked
/// occurrence by occurrence): sorted as the store sorts them, so the first
/// one in the way is the one a query of the proposal's own window finds.
final class Neighbours {
  Neighbours(StoreSnapshot snap, PlainDate from, PlainDate to, this.zone)
    : _all = snap.queryInstances(viewWindow(from, to, zone)) {
    for (final i in _all) {
      final sp = _spanIn(i.event, zone);
      _starts.add(sp.s);
      if (sp.e - sp.s > _longest) _longest = sp.e - sp.s;
    }
  }

  final ZoneId zone;
  final List<EventInstance> _all;
  final _starts = <int>[];
  var _longest = 0;

  /// Those that may meet `[s, e)`: a superset (the checks test the overlap themselves).
  Iterable<EventInstance> near(int s, int e) sync* {
    var lo = 0;
    var hi = _starts.length;
    final from = s - _longest;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_starts[mid] < from) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    for (var i = lo; i < _starts.length && _starts[i] < e; i++) {
      yield _all[i];
    }
  }
}

/// An event's time as instants: an all-day one covers its days in [zone];
/// never empty (a marker takes a millisecond).
MsSpan _spanIn(CalEvent e, ZoneId zone) {
  final (s, end) = switch (e) {
    TimedEvent(:final start, :final end) => (start.epochMilliseconds, end.epochMilliseconds),
    AllDayEvent(:final start, :final end) => (
      start.startOfDayIn(zone).epochMilliseconds,
      end.startOfDayIn(zone).epochMilliseconds,
    ),
  };
  return MsSpan(s, end > s + 1 ? end : s + 1);
}

PlainDate _firstDate(CalEvent e, ZoneId zone) => switch (e) {
  TimedEvent(:final start) => start.withTimeZone(zone).date,
  AllDayEvent(:final start) => start,
};

PlainDate _lastDate(CalEvent e, ZoneId zone) => switch (e) {
  TimedEvent(:final end) => end.withTimeZone(zone).date,
  AllDayEvent(:final end) => end,
};

/// All-day lengths in calendar days (a 25-hour day is still one day), timed
/// ones in elapsed milliseconds.
(bool, int) _lengthOf(CalEvent e, ZoneId zone) => switch (e) {
  AllDayEvent(:final start, :final end) => (true, start.daysUntil(end)),
  TimedEvent() => (false, _spanIn(e, zone).e - _spanIn(e, zone).s),
};

String _startText(CalEvent e) => switch (e) {
  TimedEvent(:final start) => '$start',
  AllDayEvent(:final start) => '$start',
};

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What stands in the way of a proposal, cheapest checks first: editable,
/// valid range, constraint, overlap (one indexed query over the proposal's
/// window), then the application's `allow`. Empty means it may go.
///
/// [movingSeries]: a series moving as a whole — its own occurrences move
/// with it and are not in the way.
List<Violation> validateProposal(StoreSnapshot snap, Placement p, RulesContext rules, {String? movingSeries}) =>
    validateWith(snap, p, rules, movingSeries: movingSeries);

/// [validateProposal], with the instances around it already queried
/// ([around]: a series' year, checked occurrence by occurrence).
List<Violation> validateWith(
  StoreSnapshot snap,
  Placement p,
  RulesContext rules, {
  String? movingSeries,
  Neighbours? around,
}) {
  final ev = p.event;
  final to = p.proposed;
  final out = <Violation>[];
  final zone = rules.displayZone;
  void v(ViolationCode code, [String? detail]) => out.add(Violation(code, ev.id, detail));

  final startMoved = _startText(to) != _startText(ev);
  final resized = _lengthOf(to, zone) != _lengthOf(ev, zone);
  final reassigned = !_sameList(to.resourceIds, ev.resourceIds);
  if (startMoved && !ev.perms.start) v(ViolationCode.notEditable, 'start');
  if (resized && !ev.perms.duration) v(ViolationCode.notEditable, 'duration');
  if (reassigned && !ev.perms.resource) v(ViolationCode.notEditable, 'resource');

  final span = _spanIn(to, zone);
  final range = rules.validRange;
  if (range != null) {
    final start = range.start;
    final end = range.end;
    if (start != null && _firstDate(to, zone).isBefore(start)) v(ViolationCode.validRange, 'before');
    if (end != null && span.e > end.startOfDayIn(zone).epochMilliseconds) v(ViolationCode.validRange, 'after');
  }

  final fromDate = _firstDate(to, zone).addDays(-1);
  final toDate = _lastDate(to, zone).addDays(1);
  Iterable<EventInstance> window(bool noBackground) {
    if (around == null || around.zone != zone) {
      return snap.queryInstances(viewWindow(fromDate, toDate, zone), QueryOptions(includeBackground: !noBackground));
    }
    return around
        .near(fromDate.startOfDayIn(zone).epochMilliseconds, toDate.startOfDayIn(zone).epochMilliseconds)
        .where(
          (i) =>
              !noBackground ||
              (i.event.display != EventDisplay.background && i.event.display != EventDisplay.inverseBackground),
        );
  }

  // One check per resource the event goes on (its own rule and hours, in its zone), else the calendar's.
  final tree = rules.resources;
  final resources = [
    if (tree != null)
      for (final id in to.resourceIds) ?tree.byId[id]?.resource,
  ];
  final checks = resources.isNotEmpty
      ? [
          for (final r in resources)
            (
              spec: r.eventConstraint ?? rules.constraint,
              hours: r.businessHours ?? rules.businessHours,
              zone: r.timeZone ?? zone,
              id: r.id as String?,
            ),
        ]
      : [(spec: rules.constraint, hours: rules.businessHours, zone: zone, id: null as String?)];
  for (final c in checks) {
    final spec = c.spec;
    if (spec == null) continue;
    final hours = c.hours;
    final allowed = switch (spec) {
      // Business hours as a constraint with none given constrains nothing (rather than refusing everything).
      // Read in the resource's zone: two days of margin cover any offset between it and the calendar's.
      BusinessHoursConstraint() =>
        hours == null ? [span] : businessIntervals(fromDate.addDays(-1), toDate.addDays(1), hours, c.zone),
      GroupConstraint(:final groupId) => [
        for (final i in window(false))
          if (i.event.groupId == groupId && i.event.id != ev.id) _spanIn(i.event, zone),
      ],
      SpansConstraint(:final spans) => spans,
    };
    if (subtractSpans([span], normalizeSpans(allowed)).isNotEmpty) {
      v(ViolationCode.constraint, c.id);
      break;
    }
  }

  // A resource's `eventOverlap` decides for the events it shares: false refuses, true allows,
  // whatever the calendar says.
  final strict = {
    for (final r in resources)
      if (r.eventOverlap == false) r.id,
  };
  final lenient = {
    for (final r in resources)
      if (r.eventOverlap == true) r.id,
  };
  final global = rules.overlap;
  if (global != null || strict.isNotEmpty) {
    final others = window(true);
    for (final inst in others) {
      final o = inst.event;
      if (o.id == ev.id || (ev.ref != null && ev.ref == o.ref)) continue;
      if (movingSeries != null && o.ref?.seriesId == movingSeries) continue;
      // Resources: only events that share one meet (none on either side shares the calendar).
      final shared = [
        for (final r in o.resourceIds)
          if (to.resourceIds.contains(r)) r,
      ];
      if (to.resourceIds.isNotEmpty && o.resourceIds.isNotEmpty && shared.isEmpty) continue;
      final os = _spanIn(o, zone);
      if (!(os.s < span.e && os.e > span.s)) continue;
      final refused = shared.any(strict.contains)
          ? true
          : shared.isNotEmpty && shared.every(lenient.contains)
          ? false
          : global != null && !global(o, to);
      if (refused) {
        v(ViolationCode.overlap, o.id);
        break;
      }
    }
  }

  final allow = rules.allow;
  if (allow != null && out.isEmpty && !allow(p)) v(ViolationCode.allow);
  return out;
}
