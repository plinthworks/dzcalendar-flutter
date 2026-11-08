// The expansion of RFC 5545 §3.3.10, period by period. Days are day numbers
// (days since 1970-01-01) while the BY parts filter and expand them; moments
// are built only for the occurrences that survive.
//
// Time semantics (ARCHITECTURE B.8):
// - DAILY and slower are wall-clock: 09:00 stays 09:00 across a clock change.
//   A wall time in a gap moves forward ("compatible"); in a repeated hour it
//   takes the first reading.
// - HOURLY, MINUTELY, SECONDLY step in elapsed time from DTSTART.

import '../time/civil.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/wall.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'rule.dart';

int _weekdayOf(int n) => (n + 3) % 7 + 1;
int _startOfWeek(int n, int wkst) => n - (_weekdayOf(n) - wkst + 7) % 7;

/// RFC week 1: the first week (starting on WKST) with at least four days of
/// the year — the one holding 4 January.
int _week1Start(int y, int wkst) => _startOfWeek(epochDayOf(y, 1, 4), wkst);

/// The week number a day has, and how many weeks its year has.
({int week, int weeks}) weekOf(int n, int wkst) {
  var (y, _, _) = civilOf(n);
  if (n >= _week1Start(y + 1, wkst)) {
    y += 1;
  } else if (n < _week1Start(y, wkst)) {
    y -= 1;
  }
  final start = _week1Start(y, wkst);
  return (week: (n - start) ~/ 7 + 1, weeks: (_week1Start(y + 1, wkst) - start) ~/ 7);
}

/// RFC 5545: with no day part at all, the rule repeats DTSTART's month, day
/// or weekday.
final class _Defaults {
  const _Defaults({this.byMonth, this.byMonthDay, this.byDay});
  final List<int>? byMonth;
  final List<int>? byMonthDay;
  final List<ByDay>? byDay;
}

_Defaults _defaultsFor(RRule r, int start) {
  if (r.byWeekNo != null || r.byYearDay != null || r.byMonthDay != null || r.byDay != null) return const _Defaults();
  final (_, m, d) = civilOf(start);
  return switch (r.freq) {
    Frequency.yearly => _Defaults(byMonth: r.byMonth ?? [m], byMonthDay: [d]),
    Frequency.monthly => _Defaults(byMonthDay: [d]),
    Frequency.weekly => _Defaults(byDay: [ByDay(_weekdayOf(start))]),
    _ => const _Defaults(),
  };
}

enum _Scope { month, year }

bool _dayMatches(int n, RRule r, _Defaults def, _Scope? nthScope, {bool weekNo = true}) {
  final (y, m, d) = civilOf(n);
  final byMonth = r.byMonth ?? def.byMonth;
  if (byMonth != null && !byMonth.contains(m)) return false;
  final byWeekNo = weekNo ? r.byWeekNo : null;
  if (byWeekNo != null) {
    final w = weekOf(n, r.wkst);
    if (!byWeekNo.any((x) => (x > 0 ? x : w.weeks + x + 1) == w.week)) return false;
  }
  final byYearDay = r.byYearDay;
  if (byYearDay != null) {
    final yday = n - epochDayOf(y, 1, 1) + 1;
    final len = isLeapYear(y) ? 366 : 365;
    if (!byYearDay.any((x) => (x > 0 ? x : len + x + 1) == yday)) return false;
  }
  final byMonthDay = r.byMonthDay ?? def.byMonthDay;
  if (byMonthDay != null) {
    final dim = monthLength(y, m);
    if (!byMonthDay.any((x) => (x > 0 ? x : dim + x + 1) == d)) return false;
  }
  final byDay = r.byDay ?? def.byDay;
  if (byDay != null) {
    final wd = _weekdayOf(n);
    final ok = byDay.any((b) {
      if (b.weekday != wd) return false;
      final nth = b.n;
      if (nth == null || nthScope == null) return true;
      // The n-th of its weekday within the month (or year), from either end.
      final first = nthScope == _Scope.month ? epochDayOf(y, m, 1) : epochDayOf(y, 1, 1);
      final len = nthScope == _Scope.month ? monthLength(y, m) : (isLeapYear(y) ? 366 : 365);
      final idx = n - first;
      return nth > 0 ? idx ~/ 7 + 1 == nth : -((len - 1 - idx) ~/ 7 + 1) == nth;
    });
    if (!ok) return false;
  }
  return true;
}

List<T> _setPos<T>(List<T> xs, List<int>? pos) {
  if (pos == null) return xs;
  final picked = <int>{};
  for (final p in pos) {
    final i = p > 0 ? p - 1 : xs.length + p;
    if (i >= 0 && i < xs.length) picked.add(i);
  }
  return [for (final i in picked.toList()..sort()) xs[i]];
}

List<int> _sorted(List<int> xs) => xs.toSet().toList()..sort();

/// Empty periods in a row before a rule is declared barren (31 February).
/// The Gregorian calendar repeats every 400 years, so any date pattern that
/// can happen happens within one cycle. Counted in periods.
int _maxEmpty(RRule r) {
  final perCycle = switch (r.freq) {
    Frequency.yearly => 400,
    Frequency.monthly => 4800,
    Frequency.weekly => 20871,
    _ => 146097,
  };
  return (perCycle / r.interval).ceil() + 1;
}

_Scope? _nthScopeOf(RRule r) => switch (r.freq) {
  Frequency.monthly => _Scope.month,
  Frequency.yearly => r.byMonth != null ? _Scope.month : _Scope.year,
  _ => null,
};

/// The candidate days of period k (before the BY tests), or null past
/// Temporal's range.
List<int>? _periodDays(RRule r, int s, int k) {
  final (y, m, _) = civilOf(s);
  final step = k * r.interval;
  switch (r.freq) {
    case Frequency.yearly:
      final yy = y + step;
      if (yy > 275759) return null;
      final first = epochDayOf(yy, 1, 1);
      return [for (var i = 0; i < (isLeapYear(yy) ? 366 : 365); i++) first + i];
    case Frequency.monthly:
      final total = y * 12 + (m - 1) + step;
      final yy = floorDiv(total, 12);
      if (yy > 275759) return null;
      final mm = total - yy * 12 + 1;
      final first = epochDayOf(yy, mm, 1);
      return [for (var i = 0; i < monthLength(yy, mm); i++) first + i];
    case Frequency.weekly:
      final first = _startOfWeek(s, r.wkst) + 7 * step;
      if (first > 100000000) return null;
      return [for (var i = 0; i < 7; i++) first + i];
    default:
      final day = s + step;
      if (day > 100000000) return null;
      return [day];
  }
}

/// The UTC day number of an instant.
int _utcDayOf(Instant i) => floorDiv(i.epochMilliseconds, msPerDay);

/// Every occurrence of an all-day rule from [start], in order. Times in the
/// rule are ignored. [fromDay] (a day number) is a hint: occurrences before
/// it are only counted, never built — COUNT stays exact, and a window two
/// years after the start costs arithmetic, not objects.
Iterable<PlainDate> iterateDates(PlainDate start, RRule r, [int? fromDay]) sync* {
  final s = start.epochDay;
  final def = _defaultsFor(r, s);
  final barren = _maxEmpty(r);
  final until = r.untilDate?.epochDay;
  final untilInstant = r.untilInstant;
  final scope = _nthScopeOf(r);
  var count = 0;
  var empty = 0;
  for (var k = 0; ; k++) {
    final days = _periodDays(r, s, k);
    if (days == null) return;
    final kept = _setPos([
      for (final n in days)
        if (_dayMatches(n, r, def, scope)) n,
    ], r.bySetPos);
    if (kept.isEmpty && ++empty > barren) return;
    if (kept.isNotEmpty) empty = 0;
    for (final n in kept) {
      if (n < s) continue;
      if (until != null && n > until) return;
      if (fromDay != null && n < fromDay && (untilInstant == null || n < _utcDayOf(untilInstant) - 2)) {
        if (r.count != null && ++count >= r.count!) return;
        continue;
      }
      // An instant UNTIL on an all-day series: the date's UTC midnight.
      if (untilInstant != null && n * msPerDay > untilInstant.epochMilliseconds) return;
      yield PlainDate.fromEpochDay(n);
      if (r.count != null && ++count >= r.count!) return;
    }
  }
}

/// Filled in by an iterator that stopped on its step budget rather than at
/// the rule's end.
final class IterationState {
  bool cut = false;
}

bool _beyondUntil(ZonedDateTime z, RRule r) {
  final d = r.untilDate;
  if (d != null) return z.date.isAfter(d);
  final i = r.untilInstant;
  return i != null && z.instant.isAfter(i);
}

/// Every occurrence of a timed rule from [start], in order, in [start]'s
/// zone. [from] is a hint, as for [iterateDates]: what starts before it may
/// be skipped (counted, not built); every occurrence at or after it is given.
Iterable<ZonedDateTime> iterateZoned(ZonedDateTime start, RRule r, [Instant? from, IterationState? state]) sync* {
  if (r.subDaily) {
    yield* _iterateSubDaily(start, r, from, state);
    return;
  }
  // Two days of margin either side: an offset moves a wall day by less than one.
  final fromDay = from == null ? null : _utcDayOf(from) - 2;
  final ud = r.untilDate;
  final ui = r.untilInstant;
  final lastSafe = ud != null ? ud.epochDay - 2 : (ui != null ? _utcDayOf(ui) - 2 : null);
  final zone = start.zone;
  final wall = start.plainDateTime;
  final s = wall.date.epochDay;
  final def = _defaultsFor(r, s);
  final hours = _sorted(r.byHour ?? [wall.time.hour]);
  final minutes = _sorted(r.byMinute ?? [wall.time.minute]);
  final seconds = _sorted(r.bySecond ?? [wall.time.second]);
  final scope = _nthScopeOf(r);
  final barren = _maxEmpty(r);
  final startMs = start.epochMilliseconds;
  var count = 0;
  var empty = 0;
  for (var k = 0; ; k++) {
    final days = _periodDays(r, s, k);
    if (days == null) return;
    // Every day × time of the period, then BYSETPOS over that whole set.
    final slots = <(int, int, int, int)>[
      for (final n in days)
        if (_dayMatches(n, r, def, scope))
          for (final h in hours)
            for (final mi in minutes)
              for (final se in seconds) (n, h, mi, se),
    ];
    final kept = _setPos(slots, r.bySetPos);
    if (kept.isEmpty && ++empty > barren) return;
    if (kept.isNotEmpty) empty = 0;
    for (final (n, h, mi, se) in kept) {
      if (fromDay != null && n < fromDay && n >= s + 2 && (lastSafe == null || n < lastSafe)) {
        if (r.count != null && ++count >= r.count!) return;
        continue;
      }
      // DTSTART is always the first occurrence as given — its second reading
      // of a repeated hour included.
      final isStart = n == s && h == wall.time.hour && mi == wall.time.minute && se == wall.time.second;
      // RFC: a time that does not exist moves forward; a repeated one takes its first reading.
      final z = isStart
          ? start
          : ZonedDateTime.fromWall(
              PlainDateTime(PlainDate.fromEpochDay(n), PlainTime(h, mi, se > 59 ? 59 : se)),
              zone,
            )!;
      if (z.epochMilliseconds < startMs) continue;
      if (_beyondUntil(z, r)) return;
      yield z;
      if (r.count != null && ++count >= r.count!) return;
    }
  }
}

/// A sub-daily rule with no BY part gives exactly one occurrence per step.
bool plainSubDaily(RRule r) =>
    r.byHour == null &&
    r.byMinute == null &&
    r.bySecond == null &&
    r.byDay == null &&
    r.byMonth == null &&
    r.byMonthDay == null &&
    r.byYearDay == null &&
    r.bySetPos == null;

/// Steps one sub-daily generator may take before it gives up: a hard bound.
const _maxSteps = 2000000;

/// HOURLY and finer: periods advance in elapsed time; finer BY parts expand
/// within, coarser ones filter.
Iterable<ZonedDateTime> _iterateSubDaily(ZonedDateTime start, RRule r, Instant? from, IterationState? state) sync* {
  final zone = start.zone;
  final rules = ZoneRules.of(zone)!;
  final startMs = start.epochMilliseconds;
  final unitMs = switch (r.freq) {
    Frequency.hourly => msPerHour,
    Frequency.minutely => msPerMinute,
    _ => msPerSecond,
  };
  final stepMs = unitMs * r.interval;
  final plain = plainSubDaily(r);
  // Steps are elapsed time, so the first step near `from` is arithmetic — and
  // with no BY part, so is the count of occurrences before it.
  final k0 = from == null || (r.count != null && !plain)
      ? 0
      : _max(0, floorDiv(from.epochMilliseconds - startMs, stepMs) - 1);
  var count = plain ? k0 : 0;
  if (r.count != null && count >= r.count!) return;
  const none = _Defaults();
  var empty = 0;
  var steps = 0;
  final emptyBound =
      switch (r.freq) {
        Frequency.hourly => 8784,
        Frequency.minutely => 527040,
        _ => 31622400,
      } /
      r.interval;
  for (var k = k0; ; k++) {
    if (++steps > _maxSteps) {
      state?.cut = true;
      return;
    }
    final at = startMs + k * stepMs;
    if (at.abs() > 8640000000000000) return;
    final p = Instant.fromEpochMilliseconds(at).inZone(zone);
    final pw = p.plainDateTime;
    final n = pw.date.epochDay;
    // The day parts filter each step; BYWEEKNO is YEARLY-only and never reaches here.
    if (!_dayMatches(n, r, none, null, weekNo: false)) {
      // Jump to the next day that can match, found in day arithmetic: a
      // barren rule (30 February) ends after one Gregorian cycle of days.
      var m = n + 1;
      while (!_dayMatches(m, r, none, null, weekNo: false)) {
        if (++m - n > 146097) return;
      }
      final midnight = PlainDate.fromEpochDay(m).startOfDayIn(zone).epochMilliseconds;
      k = _max(k, ((midnight - startMs) / stepMs).ceil() - 1);
      continue;
    }
    // An hour (or, finer, a minute) that cannot match: jump to the next one
    // that can — a rule at 09:00:00 every second costs a few steps a day.
    final nextTime = _skipTo(pw.time, r);
    if (nextTime != null) {
      final target = nextTime.hour >= 24
          ? PlainDate.fromEpochDay(n + 1).startOfDayIn(zone).epochMilliseconds
          : ZonedDateTime.fromWall(
              PlainDateTime(pw.date, PlainTime(nextTime.hour, nextTime.minute)),
              zone,
              how: Disambiguation.earlier,
            )!.epochMilliseconds;
      // Wall time rewinds at a fall-back: never jump across a transition, stop at it and look again.
      final transition = rules.nextTransition(at);
      final bound = transition != null && transition < target ? transition : target;
      final next = ((bound - startMs) / stepMs).ceil() - 1;
      if (next > k) {
        k = next;
        continue;
      }
    }
    // BYHOUR always limits; BYMINUTE limits MINUTELY and SECONDLY (expands
    // HOURLY); BYSECOND limits SECONDLY (expands the others).
    final t = pw.time;
    final byHour = r.byHour;
    final byMinute = r.byMinute;
    final bySecond = r.bySecond;
    final ok =
        (byHour == null || byHour.contains(t.hour)) &&
        (r.freq == Frequency.hourly || byMinute == null || byMinute.contains(t.minute)) &&
        (r.freq != Frequency.secondly || bySecond == null || bySecond.contains(t.second));
    var cands = <ZonedDateTime>[];
    if (ok) {
      final minutes = r.freq == Frequency.hourly ? _sorted(byMinute ?? [t.minute]) : [t.minute];
      final secs = r.freq == Frequency.secondly ? [t.second] : _sorted(bySecond ?? [t.second]);
      for (final mi in minutes) {
        for (final se in secs) {
          cands.add(
            ZonedDateTime.fromWall(
              PlainDateTime(pw.date, PlainTime(t.hour, mi, se > 59 ? 59 : se)),
              zone,
              preferOffsetMs: p.offsetMs,
            )!,
          );
        }
      }
      cands = _setPos(cands, r.bySetPos);
    }
    // Within matching days the time parts can still never meet (BYHOUR=9 with
    // an interval that never lands on 9): cut after one year of steps.
    if (cands.isEmpty && ++empty > emptyBound) return;
    if (cands.isNotEmpty) empty = 0;
    for (final z in cands) {
      if (z.epochMilliseconds < startMs) continue;
      if (_beyondUntil(z, r)) return;
      yield z;
      if (r.count != null && ++count >= r.count!) return;
    }
  }
}

int _max(int a, int b) => a > b ? a : b;

/// When [t]'s hour (or, for MINUTELY/SECONDLY, its minute) cannot match, the
/// next wall hour:minute that can, on the same day — or hour 24 for the next
/// day. Null when [t] itself may match.
({int hour, int minute})? _skipTo(PlainTime t, RRule r) {
  final hours = r.byHour;
  final minutes = r.freq != Frequency.hourly ? r.byMinute : null;
  int minOf(List<int> xs) => xs.reduce((a, b) => a < b ? a : b);
  if (hours != null && !hours.contains(t.hour)) {
    final h = _sorted(hours).where((x) => x > t.hour).firstOrNull;
    return h == null ? (hour: 24, minute: 0) : (hour: h, minute: minutes != null ? minOf(minutes) : 0);
  }
  if (minutes != null && !minutes.contains(t.minute)) {
    final mi = _sorted(minutes).where((x) => x > t.minute).firstOrNull;
    if (mi != null) return (hour: t.hour, minute: mi);
    final h = hours != null ? _sorted(hours).where((x) => x > t.hour).firstOrNull : t.hour + 1;
    return h == null || h >= 24 ? (hour: 24, minute: 0) : (hour: h, minute: minOf(minutes));
  }
  return null;
}
