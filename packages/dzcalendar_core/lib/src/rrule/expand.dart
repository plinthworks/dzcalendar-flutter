import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/zoned.dart';
import 'iterate.dart';
import 'rule.dart';

/// The starts found, and `too-many-occurrences` when the limit cut them short.
final class ExpandResult<T> {
  const ExpandResult(this.starts, this.problems);
  final List<T> starts;
  final List<RRuleProblem> problems;
}

const defaultExpandLimit = 10000;

/// The starts of a timed series in `[from, to)`: its rules (merged, in
/// order), plus RDATEs, minus EXDATEs — an EXDATE instant removes that
/// moment, an EXDATE date every occurrence on that date in the series' zone.
/// Occurrences starting before [from] are skipped (the caller widens by the
/// duration). Stops at [limit] and says so rather than running away.
ExpandResult<ZonedDateTime> expandZoned(
  ZonedDateTime start,
  RRuleSet set,
  Instant from,
  Instant to, [
  int limit = defaultExpandLimit,
]) {
  final zone = start.zone;
  final fromMs = from.epochMilliseconds;
  final toMs = to.epochMilliseconds;
  final exInstants = <int>{};
  final exDays = <int>{};
  for (final x in set.exdates) {
    switch (x) {
      case ExInstant(:final at):
        exInstants.add(at.epochMilliseconds);
      case ExDay(:final date):
        exDays.add(date.epochDay);
    }
  }
  bool excluded(ZonedDateTime z) => exInstants.contains(z.epochMilliseconds) || exDays.contains(z.date.epochDay);

  final found = <int, ZonedDateTime>{};
  final state = IterationState();
  for (final rule in set.rules) {
    // Each rule brings up to one more than the limit: the union, sorted, is then cut.
    var n = 0;
    for (final z in iterateZoned(start, rule, from, state)) {
      final ms = z.epochMilliseconds;
      if (ms >= toMs) break;
      if (ms < fromMs || excluded(z)) continue;
      found[ms] = z;
      // One more than the limit: exactly `limit` occurrences is not too many.
      if (++n > limit) break;
    }
  }
  for (final r in set.rdates) {
    final z = switch (r) {
      RDay(:final date) => ZonedDateTime.fromWall(date.at(start.time), zone)!,
      RZoned(:final at) => at.withTimeZone(zone),
    };
    final ms = z.epochMilliseconds;
    if (ms >= fromMs && ms < toMs && !excluded(z)) found[ms] = z;
  }
  final keys = found.keys.toList()..sort();
  final r = _cutAt([for (final k in keys) found[k]!], limit);
  // A generator that ran out of steps did not reach the window's end: say so.
  if (state.cut && r.problems.isEmpty) {
    return ExpandResult(r.starts, const [
      RRuleProblem('too-many-occurrences', 'the rule needs too many steps to reach this window'),
    ]);
  }
  return r;
}

/// The same for an all-day series: dates in, dates out, `[from, to)`.
ExpandResult<PlainDate> expandDates(
  PlainDate start,
  RRuleSet set,
  PlainDate from,
  PlainDate to, [
  int limit = defaultExpandLimit,
]) {
  final ex = <int>{
    for (final x in set.exdates)
      switch (x) {
        ExDay(:final date) => date.epochDay,
        ExInstant(:final at) => at.inZone('UTC').date.epochDay,
      },
  };
  final found = <int, PlainDate>{};
  for (final rule in set.rules) {
    var n = 0;
    for (final d in iterateDates(start, rule, from.epochDay)) {
      if (!d.isBefore(to)) break;
      if (d.isBefore(from) || ex.contains(d.epochDay)) continue;
      found[d.epochDay] = d;
      if (++n > limit) break;
    }
  }
  for (final r in set.rdates) {
    final d = switch (r) {
      RDay(:final date) => date,
      RZoned(:final at) => at.date,
    };
    if (!d.isBefore(from) && d.isBefore(to) && !ex.contains(d.epochDay)) found[d.epochDay] = d;
  }
  final keys = found.keys.toList()..sort();
  return _cutAt([for (final k in keys) found[k]!], limit);
}

ExpandResult<T> _cutAt<T>(List<T> starts, int limit) {
  if (starts.length <= limit) return ExpandResult(starts, const []);
  return ExpandResult(starts.sublist(0, limit), [
    RRuleProblem('too-many-occurrences', 'more than $limit in the window'),
  ]);
}

/// COUNT a series may walk to find its end; beyond, it is indexed as endless.
const _walkBudget = 50000;

/// The last start a timed series can have, or null when it never ends (no
/// COUNT and no UNTIL in some rule). What the store indexes a series by.
ZonedDateTime? lastStartZoned(ZonedDateTime start, RRuleSet set) {
  var last = start;
  ZonedDateTime later(ZonedDateTime a, ZonedDateTime b) => b.instant.isAfter(a.instant) ? b : a;
  for (final rule in set.rules) {
    if (rule.count == null && !rule.hasUntil) return null;
    if (rule.hasUntil) {
      // UNTIL bounds it without walking: the until itself is an upper bound.
      final ud = rule.untilDate;
      final bound = ud != null
          ? ZonedDateTime(ud.addDays(1).startOfDayIn(start.zone), start.zone)
          : rule.untilInstant!.inZone(start.zone);
      last = later(last, bound);
      continue;
    }
    // COUNT with no BY part, sub-daily: the last start is arithmetic.
    if (rule.subDaily && plainSubDaily(rule)) {
      final unitMs = switch (rule.freq) {
        Frequency.hourly => 3600000,
        Frequency.minutely => 60000,
        _ => 1000,
      };
      last = later(last, start.instant.addMs((rule.count! - 1) * rule.interval * unitMs).inZone(start.zone));
      continue;
    }
    // COUNT: walk it — within a budget; past it the series is indexed as
    // endless, a safe upper bound, and no input can stall the store.
    if (rule.count! > _walkBudget) return null;
    final state = IterationState();
    for (final z in iterateZoned(start, rule, null, state)) {
      last = later(last, z);
    }
    if (state.cut) return null;
  }
  for (final r in set.rdates) {
    last = later(last, switch (r) {
      RDay(:final date) => ZonedDateTime.fromWall(date.at(start.time), start.zone)!,
      RZoned(:final at) => at,
    });
  }
  return last;
}

/// The same for an all-day series.
PlainDate? lastStartDate(PlainDate start, RRuleSet set) {
  var last = start;
  PlainDate later(PlainDate a, PlainDate b) => b.isAfter(a) ? b : a;
  for (final rule in set.rules) {
    if (rule.count == null && !rule.hasUntil) return null;
    if (rule.hasUntil) {
      last = later(last, rule.untilDate ?? rule.untilInstant!.inZone('UTC').date);
      continue;
    }
    if (rule.count! > _walkBudget) return null;
    for (final d in iterateDates(start, rule)) {
      last = later(last, d);
    }
  }
  for (final r in set.rdates) {
    last = later(last, switch (r) {
      RDay(:final date) => date,
      RZoned(:final at) => at.date,
    });
  }
  return last;
}

/// The first start a timed series can have: DTSTART, or an earlier RDATE.
ZonedDateTime firstStartZoned(ZonedDateTime start, RRuleSet set) {
  var first = start;
  for (final r in set.rdates) {
    final z = switch (r) {
      RDay(:final date) => ZonedDateTime.fromWall(date.at(start.time), start.zone)!,
      RZoned(:final at) => at,
    };
    if (z.instant.isBefore(first.instant)) first = z;
  }
  return first;
}

/// The same for an all-day series.
PlainDate firstStartDate(PlainDate start, RRuleSet set) {
  var first = start;
  for (final r in set.rdates) {
    final d = switch (r) {
      RDay(:final date) => date,
      RZoned(:final at) => at.date,
    };
    if (d.isBefore(first)) first = d;
  }
  return first;
}
