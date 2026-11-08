import 'dart:convert';

import '../event/problem.dart';
import '../intervals.dart';
import '../rrule/expand.dart';
import '../rrule/rule.dart';
import '../time/duration.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../util/js.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'json.dart';
import 'types.dart';

const _minute = Duration(minutes: 1);
const _year = Duration(minutes: 525600);

/// At most this many slots are offered, and this many starts looked at: a
/// tiny step over years would never end.
const maxSlots = 10000;
const maxCandidates = 200000;

/// How far back openings are looked for: one that began earlier still counts
/// from its true start.
const _lookbackDays = 7;

/// The dates Temporal can hold: the web's engine stops there (a `RangeError`,
/// said as `invalid-slot-query`), and so does this one.
final _firstDate = PlainDate(-271821, 4, 19);
final _lastDate = PlainDate(275760, 9, 13);

bool slotLength(Duration d) => d >= _minute && d <= _year;
bool wholeCount(num x) => x.isFinite && x >= 0 && x == x.truncate() && x <= 100000;

/// Milliseconds, fractions kept (as the web's numbers).
double _ms(Duration d) => d.inMicroseconds / 1000;

/// An opening and where its slot grid starts: its own start, or a fixed
/// grid for one open for days on end.
typedef _Opening = ({int s, int e, int a});

/// Busy time, with buffers (which may be fractions of a millisecond).
typedef _Busy = ({double s, double e});

/// The rules read and checked once, over a range.
final class _Plan {
  _Plan({
    required this.zone,
    required this.from,
    required this.to,
    required this.dur,
    required this.step,
    required this.before,
    required this.after,
    required this.earliest,
    required this.latest,
    required this.cap,
    required this.busy,
    required this.booked,
    required this.open,
  });

  final ZoneId zone;
  final int from;
  final int to;
  final int dur;
  final int step;
  final double before;
  final double after;
  final double earliest;
  final double latest;

  /// Null: no daily cap.
  final int? cap;

  /// Busy time a slot (with its buffers) must not touch: merged.
  final List<_Busy> busy;

  /// Bookings per provider date (epoch day).
  final Map<int, int> booked;

  /// Merged openings, each with the origin of its slot grid.
  final List<_Opening> open;
}

List<_Busy> _mergeBusy(List<_Busy> xs) {
  final sorted = xs.where((x) => x.e > x.s).toList()
    ..sort((a, b) {
      final c = a.s.compareTo(b.s);
      return c != 0 ? c : a.e.compareTo(b.e);
    });
  final out = <_Busy>[];
  for (final x in sorted) {
    if (out.isNotEmpty && x.s <= out.last.e) {
      if (x.e > out.last.e) out.last = (s: out.last.s, e: x.e);
    } else {
      out.add(x);
    }
  }
  return out;
}

_Plan? _plan(SlotRules q, Instant? fromIn, Instant? toIn, Instant? at, List<Problem> problems) {
  _Plan? bad(String path, Object? detail) {
    problems.add(Problem(ProblemCode.invalidSlotQuery, Severity.error, path, jsText(detail)));
    return null;
  }

  final zone = q.availability.timeZone;
  if (!isValidZone(zone)) {
    problems.add(Problem(ProblemCode.unknownZone, Severity.error, 'availability.timeZone', zone));
    return null;
  }
  if (!slotLength(q.duration)) return bad('duration', q.duration);
  final dur = jsRound(_ms(q.duration));
  // checkSlot without a range: the slot's own time.
  final from = fromIn ?? at;
  final to = toIn ?? at?.addMs(dur);
  if (from == null) return bad('from', 'undefined');
  if (to == null) return bad('to', 'undefined');
  final step = q.step ?? q.duration;
  if (!slotLength(step)) return bad('step', q.step);
  for (final (k, v) in [('bufferBefore', q.bufferBefore), ('bufferAfter', q.bufferAfter), ('minNotice', q.minNotice)]) {
    if (v != null && v.isNegative) return bad(k, v);
  }
  // Whole numbers: days are added as calendar days, bookings counted one by one.
  for (final (k, v) in [('maxAdvanceDays', q.maxAdvanceDays), ('maxPerDay', q.maxPerDay)]) {
    if (v != null && !wholeCount(v)) return bad(k, v);
  }
  final now = q.now;
  if (now == null && (q.minNotice != null || q.maxAdvanceDays != null)) {
    return bad('now', 'minNotice and maxAdvanceDays need now');
  }
  final before = _ms(q.bufferBefore);
  final after = _ms(q.bufferAfter);
  final busy = <_Busy>[];
  final booked = <int, int>{};
  for (var i = 0; i < q.busy.length; i++) {
    final b = q.busy[i];
    final s = b.start.epochMilliseconds;
    final e = b.end.epochMilliseconds;
    if (e < s) {
      problems.add(Problem(ProblemCode.invalidSlotQuery, Severity.warning, 'busy[$i]', '${b.start}–${b.end}'));
      continue;
    }
    // A booking keeps its own buffers: two appointments are bufferAfter + bufferBefore apart.
    if (b.kind == BusyKind.booking) {
      busy.add((s: s - before, e: e + after));
      final d = ZonedDateTime(b.start, zone).date.epochDay;
      booked[d] = (booked[d] ?? 0) + 1;
    } else {
      busy.add((s: s.toDouble(), e: e.toDouble()));
    }
  }
  final zFrom = ZonedDateTime(from, zone).date;
  final zTo = ZonedDateTime(to, zone).date;
  // Openings that began before the range (a window opened the day before, or chained ones) keep their
  // grid: it starts at the opening's true start, looked for up to a week back. One open since the very
  // first day looked at (open for days on end: 24/7) cannot be traced to a start — its grid is fixed
  // instead, multiples of the step since the epoch, the same whatever range is asked.
  final first = zFrom.addDays(-_lookbackDays);
  final last = zTo.addDays(1);
  if (first.isBefore(_firstDate) || last.isAfter(_lastDate)) return bad('query', 'out of the representable range');
  final firstEnd = first.addDays(1).startOfDayIn(zone).epochMilliseconds;
  final stepMs = jsRound(_ms(step));
  final open = [
    for (final o in openSpans(q.availability, first, last, problems))
      (s: o.s, e: o.e, a: o.s < firstEnd ? (o.s / stepMs).ceil() * stepMs : o.s),
  ];
  return _Plan(
    zone: zone,
    from: from.epochMilliseconds,
    to: to.epochMilliseconds,
    dur: dur,
    step: stepMs,
    before: before,
    after: after,
    earliest: now == null ? double.negativeInfinity : now.epochMilliseconds + _ms(q.minNotice ?? Duration.zero),
    latest: now != null && q.maxAdvanceDays != null
        ? ZonedDateTime(now, zone).add(IsoDuration(days: q.maxAdvanceDays!)).epochMilliseconds.toDouble()
        : double.infinity,
    cap: q.maxPerDay,
    busy: _mergeBusy(busy),
    booked: booked,
    open: open,
  );
}

/// Every start the openings offer, in order: from each opening's start, one
/// step at a time (elapsed minutes), while a whole slot fits in the opening.
Iterable<int> _candidates(_Plan p) sync* {
  // Openings wholly before the range are skipped, and a long one is entered at the range's start on its grid.
  for (final o in p.open) {
    if (o.e <= p.from) continue;
    final t0 = o.a >= p.from ? o.a : o.a + ((p.from - o.a) / p.step).ceil() * p.step;
    for (var t = t0; t + p.dur <= o.e; t += p.step) {
      yield t;
    }
  }
}

/// The first rule a candidate start breaks, or null; [cursor] walks the
/// merged busy spans forward.
SlotRefusal? _refusal(_Plan p, int t, ZonedDateTime start, List<int> cursor) {
  if (t < p.earliest) return SlotRefusal.notice;
  if (t > p.latest) return SlotRefusal.advance;
  final cap = p.cap;
  if (cap != null && (p.booked[start.date.epochDay] ?? 0) >= cap) return SlotRefusal.dailyCap;
  final s = t - p.before;
  final e = t + p.dur + p.after;
  while (cursor[0] < p.busy.length && p.busy[cursor[0]].e <= s) {
    cursor[0]++;
  }
  if (cursor[0] < p.busy.length && p.busy[cursor[0]].s < e) return SlotRefusal.busy;
  return null;
}

Slot _slotAt(_Plan p, int t) => Slot(
  ZonedDateTime(Instant.fromEpochMilliseconds(t), p.zone),
  ZonedDateTime(Instant.fromEpochMilliseconds(t + p.dur), p.zone),
);

/// The bookable slots starting at or after [from] and ending at or before
/// [to]: the openings of the provider's week and exceptions, cut into slots
/// of `duration`, minus what is busy (with buffers), too soon
/// (`minNotice`), too far (`maxAdvanceDays`) or on a full date
/// (`maxPerDay`). Bad input never throws: it is in the problems.
SlotsResult findSlots(SlotRules rules, {required Instant from, required Instant to}) {
  final problems = <Problem>[];
  try {
    final p = _plan(rules, from, to, null, problems);
    if (p == null) return SlotsResult(const [], problems);
    final slots = <Slot>[];
    final cursor = [0];
    var seen = 0;
    for (final t in _candidates(p)) {
      if (t + p.dur > p.to) break;
      if (++seen > maxCandidates || slots.length >= maxSlots) {
        problems.add(
          const Problem(
            ProblemCode.tooManyOccurrences,
            Severity.warning,
            'step',
            'more than $maxSlots slots or $maxCandidates starts: narrow the range',
          ),
        );
        break;
      }
      final slot = _slotAt(p, t);
      if (_refusal(p, t, slot.start, cursor) == null) slots.add(slot);
    }
    return SlotsResult(List.unmodifiable(slots), problems);
  } catch (e) {
    // Last resort: a value no check foresaw is still an answer, not a throw.
    problems.add(Problem(ProblemCode.invalidSlotQuery, Severity.error, 'query', '$e'));
    return SlotsResult(const [], problems);
  }
}

/// Whether [start] is one of the slots [findSlots] would offer — what a
/// server asks before saving a booking, with the same rules as the page.
/// [start] is an [Instant], a [ZonedDateTime] or their ISO text (as a
/// request body has it; a time written below the millisecond is
/// `misaligned`, slots never are). Without [from]/[to], the range is the
/// slot itself.
SlotCheck checkSlot(SlotRules rules, Object start, {Instant? from, Instant? to}) {
  try {
    final problems = <Problem>[];
    final read = readMomentExact(start);
    if (read == null) {
      return SlotRefused(SlotRefusal.invalidQuery, [
        Problem(ProblemCode.invalidSlotQuery, Severity.error, 'start', jsText(start)),
      ]);
    }
    final p = _plan(rules, from, to, read.at, problems);
    if (p == null || problems.any((x) => x.isError)) return SlotRefused(SlotRefusal.invalidQuery, problems);
    final t = read.at.epochMilliseconds;
    if (t < p.from || t + p.dur > p.to) return const SlotRefused(SlotRefusal.outOfRange);
    _Opening? opening;
    for (final o in p.open) {
      if (o.s <= t && t + p.dur <= o.e) {
        opening = o;
        break;
      }
    }
    if (opening == null) return const SlotRefused(SlotRefusal.closed);
    // Off the grid — or between milliseconds, which slots never are.
    if (t < opening.a || (t - opening.a) % p.step != 0 || !read.exact) {
      return const SlotRefused(SlotRefusal.misaligned);
    }
    final slot = _slotAt(p, t);
    final reason = _refusal(p, t, slot.start, [0]);
    return reason != null ? SlotRefused(reason) : SlotAccepted(slot);
  } catch (e) {
    return SlotRefused(SlotRefusal.invalidQuery, [
      Problem(ProblemCode.invalidSlotQuery, Severity.error, 'query', '$e'),
    ]);
  }
}

/// Where a window opened on [date] lies, in epoch ms. Wall times are
/// resolved `compatible` (a start in a skipped hour opens when the hour
/// ends): a window across a clock change has its real length.
MsSpan? _spanOf(PlainDate date, Window w, ZoneId zone) {
  final s = resolveWall(date, w.from.time, zone, WallPolicy.compatible).instant!.epochMilliseconds;
  final crosses = w.to.isEndOfDay || w.to.compareTo(w.from) <= 0;
  final endDate = crosses ? date.addDays(1) : date;
  final endTime = w.to.time;
  // A closing time the clocks skip closes when they jump (02:30 on a night that goes from 02:00 to
  // 03:00 closes at the jump): a time that does not exist never adds open time.
  final end = resolveWall(endDate, endTime, zone, WallPolicy.earlier);
  final e = end.exists ? end.instant!.epochMilliseconds : _gapStart(end.instant!, zone);
  return e > s ? MsSpan(s, e) : null;
}

/// The moment the clocks jumped over a wall time that does not exist
/// ([before]: its `earlier` reading).
int _gapStart(Instant before, ZoneId zone) =>
    rulesFor(zone).nextTransition(before.epochMilliseconds) ?? before.epochMilliseconds;

/// The provider's open time for windows opening on dates [from] (inclusive)
/// to [to] (exclusive) of their zone: sorted, merged epoch-ms spans. An
/// exception replaces every window opening on its date.
List<MsSpan> openSpans(Availability av, PlainDate from, PlainDate to, List<Problem> problems) {
  final zone = av.timeZone;
  final byDate = <int, List<Window>>{};
  void add(PlainDate d, Window w) => (byDate[d.epochDay] ??= []).add(w);
  bool inRange(PlainDate d) => !d.isBefore(from) && d.isBefore(to);
  // A window opening at 24:00, or at a time out of range, opens nothing: said, dropped.
  bool readable(Window w, String path) {
    if (w.from.isValid && w.to.isValid && !w.from.isEndOfDay) return true;
    problems.add(Problem(ProblemCode.invalidAvailability, Severity.warning, path, '$w'));
    return false;
  }

  for (var i = 0; i < av.weekly.length; i++) {
    final w = av.weekly[i];
    if (!readable(w.window, 'availability.weekly[$i]')) continue;
    if (!w.days.every((d) => d >= 1 && d <= 7)) {
      problems.add(
        Problem(ProblemCode.invalidAvailability, Severity.warning, 'availability.weekly[$i].days', jsonEncode(w.days)),
      );
      continue;
    }
    for (var d = from; d.isBefore(to); d = d.addDays(1)) {
      if (w.days.contains(d.dayOfWeek)) add(d, w.window);
    }
  }

  for (var i = 0; i < av.rules.length; i++) {
    final w = av.rules[i];
    final path = 'availability.rules[$i]';
    final readWindow = readable(w.window, path);
    final rule = parseRRule(w.rrule).rule;
    if (rule == null) {
      problems.add(Problem(ProblemCode.invalidRrule, Severity.warning, '$path.rrule', w.rrule));
      continue;
    }
    if (!readWindow) continue;
    final found = expandDates(
      w.start,
      RRuleSet([rule], exdates: [for (final x in w.exdates) ExDate.date(x)]),
      from,
      to,
    );
    for (final p in found.problems) {
      problems.add(
        Problem(
          p.code == 'too-many-occurrences' ? ProblemCode.tooManyOccurrences : ProblemCode.invalidRrule,
          Severity.warning,
          '$path.rrule',
          p.detail,
        ),
      );
    }
    for (final d in found.starts) {
      add(d, w.window);
    }
  }

  for (var i = 0; i < av.exceptions.length; i++) {
    final x = av.exceptions[i];
    if (!inRange(x.date)) continue;
    byDate[x.date.epochDay] = x.closed
        ? []
        : [
            for (var j = 0; j < x.windows.length; j++)
              if (readable(x.windows[j], 'availability.exceptions[$i].windows[$j]')) x.windows[j],
          ];
  }

  final spans = <MsSpan>[];
  for (final MapEntry(key: day, value: windows) in byDate.entries) {
    final date = PlainDate.fromEpochDay(day);
    for (final w in windows) {
      final sp = _spanOf(date, w, zone);
      if (sp != null) spans.add(sp);
    }
  }
  return normalizeSpans(spans);
}
