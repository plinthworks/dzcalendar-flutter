import '../event/types.dart';
import '../store/instance.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/day_info.dart';

/// One event's piece on one day column — what the widgets draw and keep.
///
/// [key] is stable across renders (`instance|YYYY-MM-DD|part`) — by date,
/// not column, so hiding a weekend or moving the view keeps it.
sealed class Segment {
  const Segment({
    required this.key,
    required this.instance,
    required this.dayIndex,
    required this.dayCount,
    required this.part,
    required this.startsHere,
    required this.endsHere,
  });

  final String key;
  final EventInstance instance;

  /// The first column this piece sits in (hidden days excluded).
  final int dayIndex;

  /// Columns covered: 1 for a timed slice, n for an all-day bar.
  final int dayCount;

  /// Several pieces on one day: a timed event cut at a repeated hour.
  final int part;

  /// Rounded corners, continuation arrows.
  final bool startsHere;
  final bool endsHere;
}

final class TimedSegment extends Segment {
  const TimedSegment({
    required super.key,
    required super.instance,
    required super.dayIndex,
    required super.part,
    required super.startsHere,
    required super.endsHere,
    required this.from,
    required this.to,
  }) : super(dayCount: 1);

  final Instant from;
  final Instant to;
}

final class AllDaySegment extends Segment {
  const AllDaySegment({
    required super.key,
    required super.instance,
    required super.dayIndex,
    required super.dayCount,
    required super.part,
    required super.startsHere,
    required super.endsHere,
    required this.from,
    required this.to,
  });

  /// The bar's stretch in view; [to] exclusive.
  final PlainDate from;
  final PlainDate to;

  AllDaySegment _piece(String key, int dayIndex, int dayCount, bool startsHere, bool endsHere) => AllDaySegment(
    key: key,
    instance: instance,
    dayIndex: dayIndex,
    dayCount: dayCount,
    part: part,
    startsHere: startsHere,
    endsHere: endsHere,
    from: from,
    to: to,
  );
}

/// First day whose end is after [t] (binary search over sorted days).
int _firstDayEndingAfter(List<DayInfo> days, int t) {
  var lo = 0;
  var hi = days.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (days[mid].end.epochMilliseconds > t) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return lo;
}

/// A timed event cut into the display zone's real days — 23, 24 or 25 hours
/// long, or none for a day the zone skipped. O(log D + days covered).
///
/// Each slice is `[max(start, day.start), min(end, day.end))`. An event
/// ending exactly at a day's start is not on that day; a zero-length event
/// at a day's start is. [cutAtRepeat]: cut where clocks fall back — on the
/// wall axis the second pass reuses the first's positions, and a slice 02:50
/// (first) → 02:10 (second) would end above where it starts.
List<TimedSegment> segmentTimed(EventInstance instance, List<DayInfo> days, {bool cutAtRepeat = false}) {
  final ev = instance.event;
  if (ev is! TimedEvent) throw ArgumentError('segmentTimed takes a timed event');
  final s = ev.start.instant;
  final e = ev.end.instant;
  final sMs = s.epochMilliseconds;
  final eMs = e.epochMilliseconds;
  final out = <TimedSegment>[];
  for (var d = _firstDayEndingAfter(days, sMs); d < days.length; d++) {
    final day = days[d];
    if (day.lengthMinutes == 0) continue;
    final dayStart = day.start.epochMilliseconds;
    if (dayStart >= eMs && !(eMs == sMs && dayStart == sMs)) break;
    final from = sMs > dayStart ? s : day.start;
    final to = eMs < day.end.epochMilliseconds ? e : day.end;
    final bounds = [
      from,
      if (cutAtRepeat)
        for (final t in day.transitions)
          if (t.kind == TransitionKind.repeat && t.at.isAfter(from) && t.at.isBefore(to)) t.at,
      to,
    ];
    for (var p = 0; p < bounds.length - 1; p++) {
      out.add(
        TimedSegment(
          key: '${instance.key}|${day.date}|$p',
          instance: instance,
          dayIndex: d,
          part: p,
          startsHere: p == 0 && from.epochMilliseconds == sMs,
          endsHere: p == bounds.length - 2 && to.epochMilliseconds == eMs,
          from: bounds[p],
          to: bounds[p + 1],
        ),
      );
    }
  }
  return out;
}

/// The dates a view shows, in order, hidden days already removed.
final class DateIndex {
  DateIndex(this.dates) : _cols = {for (var i = 0; i < dates.length; i++) dates[i].epochDay: i};
  final List<PlainDate> dates;
  final Map<int, int> _cols;

  /// The column of a date, -1 when it is not shown.
  int colOf(PlainDate date) => _cols[date.epochDay] ?? -1;
  int _colOfDay(int epochDay) => _cols[epochDay] ?? -1;
}

/// An all-day event as bars over consecutive shown columns. A hidden day (a
/// weekend switched off) breaks the bar in two; the event's own first and
/// last days decide the rounded ends. O(days covered).
List<AllDaySegment> segmentAllDay(EventInstance instance, DateIndex view) {
  final ev = instance.event;
  if (ev is! AllDayEvent) throw ArgumentError('segmentAllDay takes an all-day event');
  if (view.dates.isEmpty) return const [];
  final evStart = ev.start.epochDay;
  final evLast = ev.end.epochDay - 1;
  final firstShown = view.dates.first.epochDay;
  final lastShown = view.dates.last.epochDay;
  final startN = evStart > firstShown ? evStart : firstShown;
  final endN = ev.end.epochDay < lastShown + 1 ? ev.end.epochDay : lastShown + 1;

  final out = <AllDaySegment>[];
  var runStart = -1;
  var runFirstDay = 0;
  var part = 0;
  void flush(int lastDay) {
    out.add(
      AllDaySegment(
        key: '${instance.key}|${PlainDate.fromEpochDay(runFirstDay)}|$part',
        instance: instance,
        dayIndex: runStart,
        dayCount: view._colOfDay(lastDay) - runStart + 1,
        part: part,
        startsHere: runFirstDay == evStart,
        endsHere: lastDay == evLast,
        from: PlainDate.fromEpochDay(runFirstDay),
        to: PlainDate.fromEpochDay(lastDay + 1),
      ),
    );
    part++;
    runStart = -1;
  }

  var prevShown = -1;
  for (var n = startN; n < endN; n++) {
    final col = view._colOfDay(n);
    if (col == -1) {
      if (runStart != -1) flush(prevShown);
      continue;
    }
    if (runStart != -1 && col != view._colOfDay(prevShown) + 1) flush(prevShown);
    if (runStart == -1) {
      runStart = col;
      runFirstDay = n;
    }
    prevShown = n;
  }
  if (runStart != -1) flush(prevShown);
  return out;
}

/// Bars cut at the end of each displayed week, for a grid drawn one week per
/// row. [weeks] lists the columns of each row. Each piece keeps the bar's
/// `from`/`to`; its place is `dayIndex`/`dayCount`.
List<List<AllDaySegment>> splitByWeek(List<AllDaySegment> segs, List<List<int>> weeks) {
  final rowOf = <int, int>{
    for (var r = 0; r < weeks.length; r++)
      for (final c in weeks[r]) c: r,
  };
  final rows = [for (final _ in weeks) <AllDaySegment>[]];
  for (final seg in segs) {
    var col = seg.dayIndex;
    final end = seg.dayIndex + seg.dayCount;
    var piece = 0;
    while (col < end) {
      final row = rowOf[col];
      if (row == null) break;
      final rowCols = weeks[row];
      final rowLast = rowCols.last + 1;
      final rowEnd = end < rowLast ? end : rowLast;
      rows[row].add(
        seg._piece(
          '${seg.key}|w$piece',
          col,
          rowEnd - col,
          seg.startsHere && col == seg.dayIndex,
          seg.endsHere && rowEnd == end,
        ),
      );
      piece++;
      col = rowEnd;
    }
  }
  return rows;
}
