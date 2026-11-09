import '../time/duration.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../util/js.dart';
import '../views/views.dart';
import '../zone/day_info.dart';
import '../zone/zoned.dart';
import '../zone/zone_rules.dart';

/// One step of a timeline's scale: a wall-clock slot (time unit) or a day
/// (day unit).
final class TimelineSlot {
  const TimelineSlot({
    required this.start,
    required this.end,
    required this.date,
    required this.time,
    required this.pass,
    required this.offset,
  });

  final Instant start;
  final Instant end;

  /// The date it belongs to, in the calendar's zone.
  final PlainDate date;

  /// Its wall time (time unit); null for a day slot.
  final PlainTime? time;

  /// Null when the wall time happens once.
  final WallPass? pass;

  /// The zone's offset at its start (`+01:00`): what tells the two 02:00s apart.
  final String offset;
}

/// A head above the slots: a day (time unit) or a month (day unit).
final class TimelineGroup {
  const TimelineGroup({required this.date, required this.start, required this.end, required this.lengthMinutes});

  /// The day, or the month's first day.
  final PlainDate date;
  final Instant start;
  final Instant end;

  /// Elapsed minutes: 1380, 1440, 1500 for a day; 0 for a day the zone skipped.
  final double lengthMinutes;
}

enum TimelineUnit { time, day }

/// A slot length: minutes dividing a day ([TimelineScale.minutes]) or whole
/// days ([TimelineScale.day]).
sealed class TimelineScale {
  const TimelineScale();

  /// Minutes per slot, dividing 1440 (5, 10, 15, 20, 30, 60, 120…). Not
  /// checked here, so it can be `const`: [buildTimelineAxis] throws on one
  /// that does not divide a day (configuration, the programmer's mistake).
  const factory TimelineScale.minutes(int minutes) = MinuteScale;
  static const day = DayScale();

  /// A scale from data (an option, a JSON setting): null when [minutes]
  /// does not divide a day — the web then takes [defaultScale].
  static TimelineScale? tryMinutes(int minutes) {
    final s = MinuteScale(minutes);
    return s.isValid ? s : null;
  }

  /// Whether the axis can cut a day into it.
  bool get isValid;
}

final class MinuteScale extends TimelineScale {
  const MinuteScale(this.minutes);
  final int minutes;

  @override
  bool get isValid => minutes >= 1 && 1440 % minutes == 0;

  @override
  bool operator ==(Object other) => other is MinuteScale && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;
}

final class DayScale extends TimelineScale {
  const DayScale();

  @override
  bool get isValid => true;

  @override
  bool operator ==(Object other) => other is DayScale;

  @override
  int get hashCode => (DayScale).hashCode;
}

/// The default scale for a range: 30 minutes for one day, an hour up to a
/// week, days beyond (owner's decision, as on the web).
TimelineScale defaultScale(ViewRange range) {
  final days = range.start.daysUntil(range.end);
  return days <= 1
      ? const TimelineScale.minutes(30)
      : days <= 7
      ? const TimelineScale.minutes(60)
      : TimelineScale.day;
}

/// The timeline's axis: always elapsed (ARCHITECTURE C.3). A position is
/// real time since the axis start, so an event's length on screen is its
/// true length, a 25-hour day is 25 hours wide and a 23-hour one 23. The
/// slots are cut on the wall clock: the 02:00 slot happens twice on a
/// fall-back night (once per offset), not at all on a spring-forward one.
final class TimelineAxis {
  TimelineAxis._({
    required this.unit,
    required this.slotMinutes,
    required this.start,
    required this.end,
    required this.slots,
    required this.groups,
  }) : _starts = [for (final x in slots) x.start.epochMilliseconds];

  final TimelineUnit unit;

  /// A nominal slot, in minutes (the time unit's step; 1440 for days): the
  /// scale's unit on screen.
  final int slotMinutes;
  final Instant start;
  final Instant end;
  final List<TimelineSlot> slots;
  final List<TimelineGroup> groups;
  final List<int> _starts;

  int get _unitMs => slotMinutes * 60000;

  /// Length in nominal slots (a fall-back day of 30-minute slots is 50, not 48).
  double get length => (end.epochMilliseconds - start.epochMilliseconds) / _unitMs;

  /// An instant's position, in nominal slots from the start, clamped to the axis.
  double toPosition(Instant at) {
    final s = start.epochMilliseconds;
    final ms = at.epochMilliseconds.clamp(s, end.epochMilliseconds);
    return (ms - s) / _unitMs;
  }

  /// The instant at a position (slots from the start), clamped.
  Instant fromPosition(double x) {
    final p = x.isNaN ? 0.0 : x.clamp(0.0, length);
    return Instant.fromEpochMilliseconds(jsRound(start.epochMilliseconds + p * _unitMs));
  }

  /// The slot holding an instant (its index), or -1 outside.
  int slotAt(Instant at) {
    final ms = at.epochMilliseconds;
    if (ms < start.epochMilliseconds || ms >= end.epochMilliseconds || _starts.isEmpty) return -1;
    // The last slot starting at or before it.
    var lo = 0;
    var hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= ms) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}

PlainTime _wall(int m) => PlainTime(m ~/ 60, m % 60);

String _offsetAt(Instant at, ZoneId zone) => ZonedDateTime(at, zone).offset;

/// A day's wall slots. Without a transition, arithmetic; with one, every wall
/// time read in the zone.
void _daySlots(DayInfo day, int step, ZoneId zone, List<TimelineSlot> out) {
  if (day.lengthMinutes == 0) return;
  final s = day.start.epochMilliseconds;
  if (day.transitions.isEmpty && day.lengthMinutes == 1440) {
    final offset = _offsetAt(day.start, zone);
    for (var m = 0; m < 1440; m += step) {
      out.add(
        TimelineSlot(
          start: Instant.fromEpochMilliseconds(s + m * 60000),
          end: Instant.fromEpochMilliseconds(s + (m + step) * 60000),
          date: day.date,
          time: _wall(m),
          pass: null,
          offset: offset,
        ),
      );
    }
    return;
  }
  final starts = <({Instant at, PlainTime time, WallPass? pass})>[];
  for (var m = 0; m < 1440; m += step) {
    final r = resolveWall(day.date, _wall(m), zone, WallPolicy.earlier);
    final at = r.instant;
    if (!r.exists || at == null) continue;
    final other = r.other;
    if (r.ambiguous && other != null) {
      starts
        ..add((at: at, time: _wall(m), pass: WallPass.first))
        ..add((at: other, time: _wall(m), pass: WallPass.second));
    } else {
      starts.add((at: at, time: _wall(m), pass: null));
    }
  }
  // A day starting after midnight (São Paulo 2018, Havana): its first slot begins at the day's start.
  starts.sort((a, b) => a.at.compareTo(b.at));
  for (var i = 0; i < starts.length; i++) {
    final x = starts[i];
    final at = i == 0 && x.at.epochMilliseconds > s ? day.start : x.at;
    final end = i + 1 < starts.length ? starts[i + 1].at : day.end;
    if (end.epochMilliseconds <= at.epochMilliseconds) continue;
    out.add(TimelineSlot(start: at, end: end, date: day.date, time: x.time, pass: x.pass, offset: _offsetAt(at, zone)));
  }
}

/// The axis of a timeline over [range] (its whole days, `start` to `end`), in
/// the calendar's [zone]. Hidden days are not taken out: a timeline is
/// continuous time. Without a [scale], [defaultScale].
TimelineAxis buildTimelineAxis(ViewRange range, ZoneId zone, {TimelineScale? scale}) {
  if (scale != null && !scale.isValid) throw ArgumentError.value(scale, 'scale', 'minutes dividing a day');
  final slot = scale ?? defaultScale(range);
  final days = dayInfos(range.start, range.start.daysUntil(range.end), zone);
  final slots = <TimelineSlot>[];
  final List<TimelineGroup> groups;
  switch (slot) {
    case DayScale():
      for (final d in days) {
        if (d.lengthMinutes == 0) continue;
        slots.add(
          TimelineSlot(
            start: d.start,
            end: d.end,
            date: d.date,
            time: null,
            pass: null,
            offset: _offsetAt(d.start, zone),
          ),
        );
      }
      // Months above the days.
      groups = [];
      for (final d in days) {
        final last = groups.isEmpty ? null : groups.last;
        if (last != null && last.date.month == d.date.month && last.date.year == d.date.year) {
          groups[groups.length - 1] = TimelineGroup(
            date: last.date,
            start: last.start,
            end: d.end,
            lengthMinutes: last.lengthMinutes + d.lengthMinutes,
          );
        } else {
          groups.add(
            TimelineGroup(
              date: PlainDate(d.date.year, d.date.month, 1),
              start: d.start,
              end: d.end,
              lengthMinutes: d.lengthMinutes,
            ),
          );
        }
      }
    case MinuteScale(:final minutes):
      for (final d in days) {
        _daySlots(d, minutes, zone, slots);
      }
      groups = [
        for (final d in days) TimelineGroup(date: d.date, start: d.start, end: d.end, lengthMinutes: d.lengthMinutes),
      ];
  }
  final start = days.isNotEmpty ? days.first.start : range.start.startOfDayIn(zone);
  final end = days.isNotEmpty ? days.last.end : start;
  return TimelineAxis._(
    unit: slot is DayScale ? TimelineUnit.day : TimelineUnit.time,
    slotMinutes: switch (slot) {
      DayScale() => 1440,
      MinuteScale(:final minutes) => minutes,
    },
    start: start,
    end: end,
    slots: List.unmodifiable(slots),
    groups: List.unmodifiable(groups),
  );
}

/// The eight timeline views: day, week, month, year — without resources
/// (`timelineDay`…) and with (`resourceTimelineDay`…).
final Map<String, ViewSpec> timelineViews = Map.unmodifiable({
  for (final (name, duration, alignment) in [
    ('Day', IsoDuration(days: 1), ViewAlignment.day),
    ('Week', IsoDuration(weeks: 1), ViewAlignment.week),
    ('Month', IsoDuration(months: 1), ViewAlignment.month),
    ('Year', IsoDuration(years: 1), ViewAlignment.year),
  ]) ...{
    'timeline$name': ViewSpec(type: 'timeline$name', family: 'timeline', duration: duration, alignment: alignment),
    'resourceTimeline$name': ViewSpec(
      type: 'resourceTimeline$name',
      family: 'timeline',
      duration: duration,
      alignment: alignment,
      resources: true,
    ),
  },
});
