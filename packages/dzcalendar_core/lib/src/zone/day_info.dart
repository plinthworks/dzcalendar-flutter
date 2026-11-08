import '../time/civil.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import 'wall.dart';
import 'zone_rules.dart';
import 'zoned.dart';

/// 24 h, 23 h, 25 h, a day that does not exist (Apia, 30 December 2011), or
/// anything else (Lord Howe's 23 h 30, a local-mean-time change in 1911).
/// Whether a day *carries* a change is `transitions.isNotEmpty`, not its kind.
enum DayKind { normal, short, long, skipped, irregular }

/// `gap`: the wall times between the two sides never happen. `repeat`: they
/// happen twice.
enum TransitionKind { gap, repeat }

/// One change of a zone's offset.
final class Transition {
  const Transition({
    required this.at,
    required this.offsetBefore,
    required this.offsetAfter,
    required this.deltaMinutes,
    required this.wallBefore,
    required this.wallAfter,
    required this.kind,
  });

  final Instant at;

  /// "+01:00"; seconds when the offset has some ("+00:09:21").
  final String offsetBefore;
  final String offsetAfter;

  /// +60 when clocks spring forward, -60 when they fall back, +30 on Lord
  /// Howe, +1440 in Apia 2011. Fractional for historical offsets with seconds:
  /// Paris left mean time (+00:09:21) for +00:00 in 1911, a change of -9.35.
  final double deltaMinutes;

  /// The clock face just before the change, read with the old offset: 02:00
  /// in Paris each March.
  final PlainDateTime wallBefore;

  /// The clock face at the change, read with the new offset: 03:00 in Paris
  /// each March.
  final PlainDateTime wallAfter;
  final TransitionKind kind;

  @override
  bool operator ==(Object other) =>
      other is Transition &&
      other.at == at &&
      other.offsetBefore == offsetBefore &&
      other.offsetAfter == offsetAfter &&
      other.deltaMinutes == deltaMinutes &&
      other.wallBefore == wallBefore &&
      other.wallAfter == wallAfter &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(at, offsetBefore, offsetAfter, deltaMinutes, wallBefore, wallAfter, kind);

  @override
  String toString() => 'Transition($at, $offsetBefore → $offsetAfter, ${kind.name})';
}

/// Facts about a zone on one date.
final class DayInfo {
  const DayInfo({
    required this.date,
    required this.zone,
    required this.start,
    required this.end,
    required this.lengthMinutes,
    required this.kind,
    required this.transitions,
  });

  final PlainDate date;

  /// As [ZoneRules.normalize] writes it.
  final ZoneId zone;

  /// The first instant of the day. Not always midnight: São Paulo in 2018 and
  /// Havana each March skip from 23:59:59 to 01:00, and the day starts there.
  final Instant start;

  /// The first instant of the next day — so `[start, end)`.
  final Instant end;

  /// Elapsed, not wall: 1380 on a spring-forward Sunday, 1500 on a fall-back
  /// one, 0 for a skipped day. Not rounded.
  final double lengthMinutes;
  final DayKind kind;
  final List<Transition> transitions;

  @override
  bool operator ==(Object other) =>
      other is DayInfo &&
      other.date == date &&
      other.zone == zone &&
      other.start == start &&
      other.end == end &&
      other.lengthMinutes == lengthMinutes &&
      other.kind == kind &&
      _sameList(other.transitions, transitions);

  @override
  int get hashCode => Object.hash(date, zone, start, end, kind, Object.hashAll(transitions));

  @override
  String toString() => 'DayInfo($date $zone, ${kind.name}, $lengthMinutes min, $transitions)';
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

DayKind _kindFor(double minutes) => switch (minutes) {
  1440.0 => DayKind.normal,
  1380.0 => DayKind.short,
  1500.0 => DayKind.long,
  0.0 => DayKind.skipped,
  _ => DayKind.irregular,
};

/// Every offset change in `[from, to)`, in order.
List<Transition> transitionsBetween(Instant from, Instant to, ZoneId zone) =>
    _between(from.epochMilliseconds, to.epochMilliseconds, rulesFor(zone));

List<Transition> _between(int from, int to, ZoneRules rules) {
  final out = <Transition>[];
  // One millisecond back, so a transition exactly at `from` is found:
  // Havana's day starts *on* its transition.
  for (var t = rules.nextTransition(from - 1); t != null && t < to; t = rules.nextTransition(t)) {
    final transition = _describe(t, rules);
    if (transition != null) out.add(transition);
  }
  return out;
}

Transition? _describe(int at, ZoneRules rules) {
  final before = rules.offsetAt(at - 1);
  final after = rules.offsetAt(at);
  final delta = after - before;
  if (delta == 0) return null;
  final instant = Instant.fromEpochMilliseconds(at);
  return Transition(
    at: instant,
    offsetBefore: offsetText(before),
    offsetAfter: offsetText(after),
    deltaMinutes: delta / msPerMinute,
    // Read through UTC plus the old offset: the clock face the change leaves.
    wallBefore: instant.wallAt(before),
    wallAfter: instant.wallAt(after),
    kind: delta > 0 ? TransitionKind.gap : TransitionKind.repeat,
  );
}

int _startOf(PlainDate date, ZoneRules rules) => startOfDayMs(date.epochDay * msPerDay, rules);

/// A transition belongs to the one day whose `[start, end)` contains it. So
/// the day that *starts* on one owns it (São Paulo 2018, Havana), and a day of
/// length zero owns none: Apia's 30 December 2011 is `skipped`, and the jump
/// is carried by the 31st, which begins on it.
DayInfo _build(PlainDate date, ZoneId zone, int start, int end, List<Transition> transitions) {
  final lengthMinutes = (end - start) / msPerMinute;
  return DayInfo(
    date: date,
    zone: zone,
    start: Instant.fromEpochMilliseconds(start),
    end: Instant.fromEpochMilliseconds(end),
    lengthMinutes: lengthMinutes,
    kind: _kindFor(lengthMinutes),
    transitions: List.unmodifiable(transitions),
  );
}

/// The facts of [date] in [zone]. Throws [ArgumentError] when [zone] names
/// no zone.
DayInfo dayInfo(PlainDate date, ZoneId zone) {
  final rules = rulesFor(zone);
  final start = _startOf(date, rules);
  final end = _startOf(date.addDays(1), rules);
  return _build(date, normalizedZone(zone), start, end, _between(start, end, rules));
}

/// [count] consecutive days. Each day's end is the next one's start, computed
/// once, and the zone is asked for its transitions once for the whole range.
List<DayInfo> dayInfos(PlainDate from, int count, ZoneId zone) {
  if (count <= 0) return const [];
  final rules = rulesFor(zone);
  final id = normalizedZone(zone);
  final bounds = [for (var i = 0; i <= count; i++) _startOf(from.addDays(i), rules)];
  final all = _between(bounds.first, bounds.last, rules);
  final out = <DayInfo>[];
  var k = 0;
  for (var i = 0; i < count; i++) {
    final end = bounds[i + 1];
    final mine = <Transition>[];
    while (k < all.length && all[k].at.epochMilliseconds < end) {
      mine.add(all[k++]);
    }
    out.add(_build(from.addDays(i), id, bounds[i], end, mine));
  }
  return out;
}

/// How [resolveWall] picks among a wall time's readings: a [Disambiguation],
/// or the reading with a given offset.
sealed class WallPolicy {
  const WallPolicy();

  static const compatible = ByDisambiguation(Disambiguation.compatible);
  static const earlier = ByDisambiguation(Disambiguation.earlier);
  static const later = ByDisambiguation(Disambiguation.later);
  static const reject = ByDisambiguation(Disambiguation.reject);

  /// On a repeated time, the reading whose offset is [offset] ("+01:00",
  /// "+0100", "+01" alike); the first one when neither has it.
  const factory WallPolicy.preferOffset(String offset) = PreferOffset;
}

final class ByDisambiguation extends WallPolicy {
  const ByDisambiguation(this.disambiguation);
  final Disambiguation disambiguation;
}

final class PreferOffset extends WallPolicy {
  const PreferOffset(this.offset);
  final String offset;
}

/// A wall time made an instant, and what the clock does at it.
final class ResolvedWall {
  const ResolvedWall({
    required this.instant,
    required this.exists,
    required this.ambiguous,
    required this.other,
    required this.offsetMatched,
  });

  /// The instant chosen under the policy; null when the policy refuses.
  final Instant? instant;
  final bool exists;
  final bool ambiguous;

  /// The reading not chosen, when the wall time happens twice.
  final Instant? other;

  /// With [PreferOffset] on a repeated time: whether the offset named one of
  /// the two readings; false means the first was taken by default. Null for
  /// every other policy and every unambiguous time.
  final bool? offsetMatched;
}

/// A wall time on a date, made an instant under an explicit [policy]. A
/// calendar must place an event even in a gap (a drop at 02:30 on a
/// spring-forward Sunday), so a skipped time is pushed forward
/// (`compatible`, `later`) or back (`earlier`) as Temporal does.
ResolvedWall resolveWall(PlainDate date, PlainTime time, ZoneId zone, WallPolicy policy) {
  final rules = rulesFor(zone);
  final wall = date.epochDay * msPerDay + time.msOfDay;
  final readings = possibleInstants(wall, rules);
  Instant? at(int? ms) => ms == null ? null : Instant.fromEpochMilliseconds(ms);

  if (readings.length >= 2) {
    final first = readings.first;
    final second = readings.last;
    int? pick;
    bool? offsetMatched;
    switch (policy) {
      case PreferOffset(:final offset):
        final wanted = parseOffsetMs(offset);
        final secondMatches = wanted == rules.offsetAt(second);
        pick = secondMatches ? 1 : 0;
        offsetMatched = secondMatches || wanted == rules.offsetAt(first);
      case ByDisambiguation(:final disambiguation):
        pick = switch (disambiguation) {
          Disambiguation.reject => null,
          Disambiguation.later => 1,
          _ => 0,
        };
    }
    if (pick == null) {
      return ResolvedWall(instant: null, exists: true, ambiguous: true, other: null, offsetMatched: offsetMatched);
    }
    return ResolvedWall(
      instant: at(pick == 0 ? first : second),
      exists: true,
      ambiguous: true,
      other: at(pick == 0 ? second : first),
      offsetMatched: offsetMatched,
    );
  }

  if (readings.length == 1) {
    return ResolvedWall(instant: at(readings.first), exists: true, ambiguous: false, other: null, offsetMatched: null);
  }

  final how = switch (policy) {
    ByDisambiguation(:final disambiguation) => disambiguation,
    PreferOffset() => Disambiguation.compatible,
  };
  return ResolvedWall(
    instant: at(how == Disambiguation.reject ? null : resolveWallMs(wall, rules, how)),
    exists: false,
    ambiguous: false,
    other: null,
    offsetMatched: null,
  );
}

/// True for an identifier that names a zone: IANA names and their links,
/// "UTC", and offsets of whole minutes.
bool isValidZone(String zone) => ZoneRules.of(zone) != null;

/// "+02:00" is a valid zone but not a place: it has no daylight saving to follow.
bool isOffsetZone(String zone) => RegExp(r'^[+-]\d{2}(:?\d{2})?$').hasMatch(zone);

final _quiet = <ZoneId, Map<int, bool>>{};
var _quietEntries = 0;

/// True when no clock change can touch a wall time on [date]: none from the
/// start of the day before to the end of the day after (a change can move
/// wall times across midnight — Apia skipped a whole date). Cached per zone
/// and day: events cluster on few dates.
bool isQuietDay(PlainDate date, ZoneId zone) {
  // Checked before the cache, so a name that is no zone leaves nothing behind.
  final rules = rulesFor(zone);
  final days = _quiet.putIfAbsent(normalizedZone(zone), () => {});
  final cached = days[date.epochDay];
  if (cached != null) return cached;
  if (++_quietEntries > 20000) {
    _quiet.clear();
    _quietEntries = 0;
    return isQuietDay(date, zone);
  }
  final quiet = _between(_startOf(date.addDays(-1), rules), _startOf(date.addDays(2), rules), rules).isEmpty;
  return days[date.epochDay] = quiet;
}
