// What series editing needs from the rules: written out and back, moved,
// cut, and walked as one sequence. A start is a ZonedDateTime (timed series)
// or a PlainDate (all-day series), as the TypeScript's `Start` union.

import '../time/civil.dart';
import '../time/plain.dart';
import '../zone/zoned.dart';
import 'iterate.dart';
import 'rule.dart';

/// A series' start: a [ZonedDateTime] or a [PlainDate].
typedef Start = Object;

bool isDateStart(Start x) => x is PlainDate;

/// The day number of a start's date (its wall date when timed).
int dayOfStart(Start x) => x is PlainDate ? x.epochDay : (x as ZonedDateTime).date.epochDay;

bool startBefore(Start a, Start b) => a is PlainDate
    ? a.isBefore(b as PlainDate)
    : (a as ZonedDateTime).epochMilliseconds < (b as ZonedDateTime).epochMilliseconds;

bool sameStart(Start a, Start b) => !startBefore(a, b) && !startBefore(b, a);

int _weekdayOf(int n) => (n + 3) % 7 + 1;
int _daysInYear(int y) => isLeapYear(y) ? 366 : 365;
int _mod(int a, int n) => a % n; // Dart's % is already the floor remainder for n > 0

/// Moves a 1-based value (or a count from the end, negative) by [by],
/// always to a valid one: the day after the last is the first (-1 + 1 → 1),
/// the day before the first the last (1 - 1 → -1); beyond, it wraps.
int _wrap(int v, int by, int size) {
  final n = v + by;
  if (v > 0) return n >= 1 ? _mod(n - 1, size) + 1 : (n - 1 >= -size ? n - 1 : -(_mod(-n, size) + 1));
  return n <= -1 ? -(_mod(-n - 1, size) + 1) : (n + 1 <= size ? n + 1 : _mod(n, size) + 1);
}

/// Which n-th of its month (or year) a day is, from the end when [fromEnd].
int _nthOf(int n, bool fromEnd, bool year) {
  final (y, m, d) = civilOf(n);
  if (year) {
    final doy = n - epochDayOf(y, 1, 1);
    return fromEnd ? -((_daysInYear(y) - 1 - doy) ~/ 7 + 1) : doy ~/ 7 + 1;
  }
  return fromEnd ? -((monthLength(y, m) - d) ~/ 7 + 1) : (d - 1) ~/ 7 + 1;
}

bool _yearScope(RRule r) => !(r.freq == Frequency.monthly || (r.freq == Frequency.yearly && r.byMonth != null));

List<int> _sortedNums(Iterable<int> xs) => xs.toSet().toList()..sort();

/// The BY parts a rule takes from its DTSTART when it does not say them.
enum ImplicitPart { byDay, byMonthDay, byMonth, byHour, byMinute, bySecond }

/// The same rule with what it took from DTSTART written out — the weekday
/// of a WEEKLY rule, the day of a MONTHLY one, the month and day of a YEARLY
/// one, the time of day of a daily-or-slower timed one — so it repeats the
/// same dates from any other DTSTART (INTERVAL's phase aside). `added` lists
/// what was written, for [implicitRule] to take back.
({RRule rule, List<ImplicitPart> added}) explicitRule(RRule rule, Start dtstart) {
  var r = rule;
  final added = <ImplicitPart>[];
  final n = dayOfStart(dtstart);
  final (_, m, d) = civilOf(n);
  if (r.byWeekNo == null && r.byYearDay == null && r.byMonthDay == null && r.byDay == null) {
    if (r.freq == Frequency.weekly) {
      r = r.copyWith(byDay: [ByDay(_weekdayOf(n))]);
      added.add(ImplicitPart.byDay);
    }
    if (r.freq == Frequency.monthly) {
      r = r.copyWith(byMonthDay: [d]);
      added.add(ImplicitPart.byMonthDay);
    }
    if (r.freq == Frequency.yearly) {
      if (r.byMonth == null) {
        r = r.copyWith(byMonth: [m]);
        added.add(ImplicitPart.byMonth);
      }
      r = r.copyWith(byMonthDay: [d]);
      added.add(ImplicitPart.byMonthDay);
    }
  }
  if (dtstart is ZonedDateTime && !r.subDaily) {
    final t = dtstart.time;
    if (r.byHour == null) {
      r = r.copyWith(byHour: [t.hour]);
      added.add(ImplicitPart.byHour);
    }
    if (r.byMinute == null) {
      r = r.copyWith(byMinute: [t.minute]);
      added.add(ImplicitPart.byMinute);
    }
    if (r.bySecond == null) {
      r = r.copyWith(bySecond: [t.second]);
      added.add(ImplicitPart.bySecond);
    }
  }
  return (rule: r, added: added);
}

/// Takes back what [explicitRule] wrote, where the new DTSTART would imply
/// the same: the rule reads as it was given.
RRule implicitRule(RRule rule, Start dtstart, List<ImplicitPart> added) {
  var r = rule;
  final n = dayOfStart(dtstart);
  final (_, m, d) = civilOf(n);
  bool one(List<int>? xs, int v) => xs != null && xs.length == 1 && xs.first == v;
  final byDay = r.byDay;
  if (added.contains(ImplicitPart.byDay) &&
      byDay != null &&
      byDay.length == 1 &&
      byDay.first.n == null &&
      byDay.first.weekday == _weekdayOf(n)) {
    r = r.copyWith(byDay: null);
  }
  if (added.contains(ImplicitPart.byMonth) &&
      one(r.byMonth, m) &&
      added.contains(ImplicitPart.byMonthDay) &&
      one(r.byMonthDay, d)) {
    r = r.copyWith(byMonth: null, byMonthDay: null);
  } else if (added.contains(ImplicitPart.byMonthDay) && !added.contains(ImplicitPart.byMonth) && one(r.byMonthDay, d)) {
    r = r.copyWith(byMonthDay: null);
  }
  if (dtstart is ZonedDateTime) {
    final t = dtstart.time;
    if (added.contains(ImplicitPart.byHour) && one(r.byHour, t.hour)) r = r.copyWith(byHour: null);
    if (added.contains(ImplicitPart.byMinute) && one(r.byMinute, t.minute)) r = r.copyWith(byMinute: null);
    if (added.contains(ImplicitPart.bySecond) && one(r.bySecond, t.second)) r = r.copyWith(bySecond: null);
  }
  return r;
}

/// The rule that repeats the same way around a moved occurrence. What named
/// the old start names the new one ("the second Tuesday" moved to the third
/// Thursday becomes "the third Thursday"); the other values move by the same
/// difference, staying valid. Best made explicit first ([explicitRule]).
/// COUNT and UNTIL are not touched here.
RRule rebaseRule(RRule rule, Start oldStart, Start newStart) {
  final o = dayOfStart(oldStart);
  final n = dayOfStart(newStart);
  final delta = n - o;
  final (oy, om, od) = civilOf(o);
  final (ny, nm, nd) = civilOf(n);
  var next = rule;
  final yearScope = _yearScope(rule);

  if (delta != 0) {
    final byDay = rule.byDay;
    if (byDay != null) {
      final seen = <String>{};
      final out = <ByDay>[];
      for (final b in byDay) {
        final nth = b.n;
        final ByDay moved;
        if (nth == null) {
          moved = ByDay(_weekdayOf(o + _mod(b.weekday - _weekdayOf(o), 7) + delta));
        } else if (b.weekday == _weekdayOf(o) && nth == _nthOf(o, nth < 0, yearScope)) {
          // The entry that named the start is recounted from the new day; the others keep their rank.
          moved = ByDay(_weekdayOf(n), _nthOf(n, nth < 0, yearScope));
        } else {
          moved = ByDay(_weekdayOf(o + _mod(b.weekday - _weekdayOf(o), 7) + delta), nth);
        }
        if (seen.add('${moved.n ?? ''}:${moved.weekday}')) out.add(moved);
      }
      next = next.copyWith(byDay: out);
    }
    final byMonthDay = rule.byMonthDay;
    if (byMonthDay != null) {
      final oldNeg = od - monthLength(oy, om) - 1;
      final newNeg = nd - monthLength(ny, nm) - 1;
      next = next.copyWith(
        byMonthDay: _sortedNums(byMonthDay.map((v) => v == od ? nd : (v == oldNeg ? newNeg : _wrap(v, delta, 31)))),
      );
    }
    final byMonth = rule.byMonth;
    if (byMonth != null && rule.freq == Frequency.yearly && om != nm) {
      next = next.copyWith(byMonth: _sortedNums(byMonth.map((v) => v == om ? nm : _wrap(v, nm - om, 12))));
    }
    final byYearDay = rule.byYearDay;
    if (byYearDay != null) {
      final oldDoy = o - epochDayOf(oy, 1, 1) + 1;
      final newDoy = n - epochDayOf(ny, 1, 1) + 1;
      final oldNeg = oldDoy - _daysInYear(oy) - 1;
      final newNeg = newDoy - _daysInYear(ny) - 1;
      next = next.copyWith(
        byYearDay: _sortedNums(
          byYearDay.map((v) => v == oldDoy ? newDoy : (v == oldNeg ? newNeg : _wrap(v, delta, 366))),
        ),
      );
    }
    final byWeekNo = rule.byWeekNo;
    if (byWeekNo != null) {
      final weeks = (delta / 7).round();
      if (weeks != 0) next = next.copyWith(byWeekNo: _sortedNums(byWeekNo.map((v) => _wrap(v, weeks, 53))));
    }
  }

  // The time of day: the start's value becomes the new start's; the others move by as much.
  if (oldStart is ZonedDateTime && newStart is ZonedDateTime) {
    final a = oldStart.time;
    final b = newStart.time;
    List<int>? time(List<int>? xs, int from, int to, int size) =>
        xs == null ? null : _sortedNums(xs.map((v) => v == from ? to : _mod(v + to - from, size)));
    final h = time(rule.byHour, a.hour, b.hour, 24);
    final mi = time(rule.byMinute, a.minute, b.minute, 60);
    final se = time(rule.bySecond, a.second, b.second, 60);
    if (h != null) next = next.copyWith(byHour: h);
    if (mi != null) next = next.copyWith(byMinute: mi);
    if (se != null) next = next.copyWith(bySecond: se);
  }
  return next;
}

Iterable<Start> _iterateRule(Start start, RRule rule) =>
    start is PlainDate ? iterateDates(start, rule) : iterateZoned(start as ZonedDateTime, rule);

/// How many starts of [rule] (from [start]) come strictly before [cut], and
/// the last of them.
({int count, Start? last}) countBefore(RRule rule, Start start, Start cut) {
  var count = 0;
  Start? last;
  for (final x in _iterateRule(start, rule)) {
    if (!startBefore(x, cut)) break;
    count++;
    last = x;
  }
  return (count: count, last: last);
}

/// Cuts a rule at the occurrence starting at [cut] (exclusive): what repeats
/// before it, and what repeats from it on. COUNT is shared (the occurrences
/// passed stay with the first); UNTIL bounds the first by the last start
/// before the cut and stays with the second. `before` is null when nothing
/// of this rule comes before the cut, `after` when nothing from it on.
({RRule? before, RRule? after}) splitRule(RRule rule, Start start, Start cut) {
  final (:count, :last) = countBefore(rule, start, cut);
  if (count == 0) return (before: null, after: rule);
  final open = rule.open;
  final before = rule.count != null
      ? open.copyWith(count: count)
      : (last is PlainDate
            ? open.copyWith(untilDate: last)
            : open.copyWith(untilInstant: (last! as ZonedDateTime).instant));
  final total = rule.count;
  final after = total == null ? rule : (total - count > 0 ? open.copyWith(count: total - count) : null);
  return (before: before, after: after);
}

/// Every start of a set — its rules merged, its RDATEs among them, EXDATEs
/// *not* removed (an excluded start keeps its place: it is still a key) — in
/// order, each once.
Iterable<Start> iterateUnion(Start start, RRuleSet set) sync* {
  final timed = start is ZonedDateTime;
  final rdates = <Start>[
    for (final r in set.rdates)
      switch (r) {
        RDay(:final date) => timed ? ZonedDateTime.fromWall(date.at(start.time), start.zone)! : date,
        RZoned(:final at) => timed ? at : at.date,
      },
  ]..sort((a, b) => startBefore(a, b) ? -1 : (startBefore(b, a) ? 1 : 0));
  final its = [for (final r in set.rules) _iterateRule(start, r).iterator];
  final has = [for (final it in its) it.moveNext()];
  var ri = 0;
  Start? last;
  for (;;) {
    var best = -1;
    for (var i = 0; i < its.length; i++) {
      if (has[i] && (best == -1 || startBefore(its[i].current, its[best].current))) best = i;
    }
    final fromRule = best == -1 ? null : its[best].current;
    final fromRdate = ri < rdates.length ? rdates[ri] : null;
    if (fromRule == null && fromRdate == null) return;
    Start next;
    if (fromRule != null && (fromRdate == null || !startBefore(fromRdate, fromRule))) {
      next = fromRule;
      has[best] = its[best].moveNext();
    } else {
      next = fromRdate!;
      ri++;
    }
    if (last != null && sameStart(last, next)) continue;
    last = next;
    yield next;
  }
}

/// Where a start sits in the set (0 = first), or -1 when the set never
/// produces it. Walks at most [budget] starts.
int indexOfStart(Start start, RRuleSet set, Start at, [int budget = 50000]) {
  var i = 0;
  for (final x in iterateUnion(start, set)) {
    if (sameStart(x, at)) return i;
    if (startBefore(at, x) || ++i > budget) return -1;
  }
  return -1;
}

/// The n-th start of the set (0 = first), or null.
Start? nthStart(Start start, RRuleSet set, int n) {
  var i = 0;
  for (final x in iterateUnion(start, set)) {
    if (i++ == n) return x;
  }
  return null;
}
