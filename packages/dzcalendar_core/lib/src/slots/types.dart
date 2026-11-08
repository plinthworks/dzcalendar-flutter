import '../event/problem.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../time/wall_time.dart';
import '../util/equality.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'engine.dart';
import 'json.dart';

/// Open from [from] to [to], wall times of the provider's zone. An end at
/// or before the start crosses midnight; [WallTime.endOfDay] is the next
/// midnight.
final class Window {
  const Window(this.from, this.to);
  final WallTime from;
  final WallTime to;

  @override
  bool operator ==(Object other) => other is Window && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => '$from–$to';
}

/// Open on these ISO weekdays (1 Monday … 7 Sunday), [window] each.
final class WeeklyWindow {
  WeeklyWindow({required List<int> days, required this.window}) : days = List.unmodifiable(days);
  final List<int> days;
  final Window window;

  @override
  bool operator ==(Object other) => other is WeeklyWindow && deepEquals(other.days, days) && other.window == window;

  @override
  int get hashCode => Object.hash(deepHash(days), window);
}

/// A date that does not follow the week: [closed], or its own [windows]. It
/// replaces every window that opens on that date (weekly and rules alike).
final class DateException {
  DateException({required this.date, this.closed = false, List<Window> windows = const []})
    : windows = List.unmodifiable(windows);
  final PlainDate date;
  final bool closed;
  final List<Window> windows;

  @override
  bool operator ==(Object other) =>
      other is DateException && other.date == date && other.closed == closed && deepEquals(other.windows, windows);

  @override
  int get hashCode => Object.hash(date, closed, deepHash(windows));
}

/// Open on the dates of an RFC 5545 rule (`FREQ=MONTHLY;BYDAY=1SA`) from its
/// first date [start], [window] each.
final class RuleWindow {
  RuleWindow({required this.rrule, required this.start, required this.window, List<PlainDate> exdates = const []})
    : exdates = List.unmodifiable(exdates);
  final String rrule;
  final PlainDate start;
  final Window window;
  final List<PlainDate> exdates;

  @override
  bool operator ==(Object other) =>
      other is RuleWindow &&
      other.rrule == rrule &&
      other.start == start &&
      other.window == window &&
      deepEquals(other.exdates, exdates);

  @override
  int get hashCode => Object.hash(rrule, start, window, deepHash(exdates));
}

/// When the provider can be booked, in the provider's own zone.
final class Availability {
  Availability({
    required this.timeZone,
    List<WeeklyWindow> weekly = const [],
    List<DateException> exceptions = const [],
    List<RuleWindow> rules = const [],
  }) : weekly = List.unmodifiable(weekly),
       exceptions = List.unmodifiable(exceptions),
       rules = List.unmodifiable(rules);
  final ZoneId timeZone;
  final List<WeeklyWindow> weekly;
  final List<DateException> exceptions;
  final List<RuleWindow> rules;

  @override
  bool operator ==(Object other) =>
      other is Availability &&
      other.timeZone == timeZone &&
      deepEquals(other.weekly, weekly) &&
      deepEquals(other.exceptions, exceptions) &&
      deepEquals(other.rules, rules);

  @override
  int get hashCode => Object.hash(timeZone, deepHash(weekly), deepHash(exceptions), deepHash(rules));
}

/// A [booking] is an appointment: it gets the same buffers as a new slot and
/// counts toward the daily cap. A [block] (leave, a meeting in another
/// agenda) only takes its time.
enum BusyKind { booking, block }

/// Something already taking the time.
final class Busy {
  const Busy({required this.start, required this.end, this.kind = BusyKind.booking});
  final Instant start;
  final Instant end;
  final BusyKind kind;

  @override
  bool operator ==(Object other) => other is Busy && other.start == start && other.end == end && other.kind == kind;

  @override
  int get hashCode => Object.hash(start, end, kind);
}

/// How a provider is booked — kept per provider, asked over any range
/// ([findSlots], [checkSlot]). Lengths are real (elapsed) time. A value
/// that cannot be right (a duration under a minute, a negative buffer) is
/// said as `invalid-slot-query`, never thrown.
final class SlotRules {
  SlotRules({
    required this.availability,
    required this.duration,
    this.step,
    this.bufferBefore = Duration.zero,
    this.bufferAfter = Duration.zero,
    this.minNotice,
    this.maxAdvanceDays,
    this.now,
    this.maxPerDay,
    List<Busy> busy = const [],
  }) : busy = List.unmodifiable(busy);

  final Availability availability;

  /// At least a minute, at most 365 days.
  final Duration duration;

  /// Between two slot starts, counted from each opening. Default: [duration].
  final Duration? step;

  /// Kept free before and after each appointment (preparation, cleaning).
  final Duration bufferBefore;
  final Duration bufferAfter;

  /// No slot starting sooner than this after [now].
  final Duration? minNotice;

  /// No slot starting later than this many days after [now].
  final int? maxAdvanceDays;

  /// Needed by [minNotice] and [maxAdvanceDays]: the engine never reads a clock.
  final Instant? now;

  /// At most this many bookings starting on one of the provider's dates; a
  /// full date offers nothing.
  final int? maxPerDay;
  final List<Busy> busy;

  @override
  bool operator ==(Object other) =>
      other is SlotRules &&
      other.availability == availability &&
      other.duration == duration &&
      other.step == step &&
      other.bufferBefore == bufferBefore &&
      other.bufferAfter == bufferAfter &&
      other.minNotice == minNotice &&
      other.maxAdvanceDays == maxAdvanceDays &&
      other.now == now &&
      other.maxPerDay == maxPerDay &&
      deepEquals(other.busy, busy);

  @override
  int get hashCode => Object.hash(
    availability,
    duration,
    step,
    bufferBefore,
    bufferAfter,
    minNotice,
    maxAdvanceDays,
    now,
    maxPerDay,
    deepHash(busy),
  );
}

/// The web's whole query read from JSON: the [rules], and the range when
/// it has one (a `checkSlot` may go without).
final class SlotRequest {
  const SlotRequest(this.rules, {this.from, this.to});
  final SlotRules rules;
  final Instant? from;
  final Instant? to;

  /// The web's JSON shape: minutes as numbers, moments as ISO strings,
  /// `"24:00"` for the next midnight. Never throws: a field that cannot be
  /// read is an error (null), an entry that cannot be read is dropped with a
  /// warning — pass the problems on with the answer. [checking]: the start a
  /// [check] will look at, when the query has no `from`/`to`.
  static (SlotRequest?, List<Problem>) fromJson(Object? json, {Object? checking}) =>
      readSlotRequest(json, checking: checking);

  /// [findSlots] over the range; `invalid-slot-query` without one.
  SlotsResult find() {
    final f = from;
    final t = to;
    if (f == null || t == null) {
      return SlotsResult(const [], [
        Problem(ProblemCode.invalidSlotQuery, Severity.error, f == null ? 'from' : 'to', 'undefined'),
      ]);
    }
    return findSlots(rules, from: f, to: t);
  }

  /// [checkSlot] within the range, if any.
  SlotCheck check(Object start) => checkSlot(rules, start, from: from, to: to);
}

/// What [findSlots] gives: the slots, and what was dropped or refused.
final class SlotsResult {
  const SlotsResult(this.slots, this.problems);
  final List<Slot> slots;
  final List<Problem> problems;
}

/// A bookable slot, in the provider's zone (`withTimeZone(client)` shows it in another).
final class Slot {
  const Slot(this.start, this.end);
  final ZonedDateTime start;
  final ZonedDateTime end;

  @override
  bool operator ==(Object other) => other is Slot && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start/$end';
}

/// Why [checkSlot] refused a start.
enum SlotRefusal {
  invalidQuery('invalid-query'),
  closed('closed'),
  misaligned('misaligned'),
  busy('busy'),
  notice('notice'),
  advance('advance'),
  dailyCap('daily-cap'),
  outOfRange('out-of-range');

  const SlotRefusal(this.code);

  /// The TypeScript spelling.
  final String code;
}

sealed class SlotCheck {
  const SlotCheck();
  bool get ok;
}

final class SlotAccepted extends SlotCheck {
  const SlotAccepted(this.slot);
  final Slot slot;
  @override
  bool get ok => true;
}

final class SlotRefused extends SlotCheck {
  const SlotRefused(this.reason, [this.problems = const []]);
  final SlotRefusal reason;

  /// With [SlotRefusal.invalidQuery]: why.
  final List<Problem> problems;
  @override
  bool get ok => false;
}
