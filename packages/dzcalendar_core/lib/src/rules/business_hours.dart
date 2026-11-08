import '../event/problem.dart';
import '../intervals.dart';
import '../time/plain.dart';
import '../time/wall_time.dart';
import '../util/equality.dart';
import '../util/js.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';

/// Opening hours as people write them: days of the week and wall times, in a
/// zone of their own — a shop in Paris stays open 09:00–18:00 *Paris time*,
/// whatever zone the calendar shows, through both countries' clock changes.
final class BusinessHoursRule {
  /// Throws an [ArgumentError] on a weekday outside 1–7, a time out of range
  /// or a zone that is none: business hours are configuration, a mistake
  /// there is the programmer's, said once when they are made — never in the
  /// middle of a drag (the web's `assertBusinessHours`). Data from outside
  /// goes through [BusinessHours.fromJson], which never throws.
  BusinessHoursRule({required List<int> daysOfWeek, required this.from, required this.to, this.timeZone})
    : daysOfWeek = List.unmodifiable(daysOfWeek) {
    for (final d in daysOfWeek) {
      if (d < 1 || d > 7) throw ArgumentError.value(daysOfWeek, 'daysOfWeek', 'ISO weekdays 1–7');
    }
    if (!from.isValid) throw ArgumentError.value(from, 'from', 'not a wall time');
    if (!to.isValid) throw ArgumentError.value(to, 'to', 'not a wall time');
    final zone = timeZone;
    if (zone != null && !isValidZone(zone)) throw ArgumentError.value(zone, 'timeZone', 'not a time zone');
  }

  /// ISO weekdays, 1 (Monday) to 7 (Sunday).
  final List<int> daysOfWeek;

  /// Opens. [WallTime.endOfDay] opens no time.
  final WallTime from;

  /// Closes; at or before [from], the next day (22:00–06:00);
  /// [WallTime.endOfDay] is the next midnight.
  final WallTime to;

  /// Default: the calendar's display zone.
  final ZoneId? timeZone;

  @override
  bool operator ==(Object other) =>
      other is BusinessHoursRule &&
      deepEquals(other.daysOfWeek, daysOfWeek) &&
      other.from == from &&
      other.to == to &&
      other.timeZone == timeZone;

  @override
  int get hashCode => Object.hash(deepHash(daysOfWeek), from, to, timeZone);
}

/// When a calendar or a resource is open: some [rules], none
/// ([BusinessHours.none]), or Monday to Friday 09:00–17:00
/// ([BusinessHours.standard], the web's `true`).
final class BusinessHours {
  BusinessHours(List<BusinessHoursRule> rules) : rules = List.unmodifiable(rules);
  const BusinessHours._(this.rules);

  static const none = BusinessHours._([]);
  static final standard = BusinessHours([
    BusinessHoursRule(daysOfWeek: const [1, 2, 3, 4, 5], from: const WallTime(9), to: const WallTime(17)),
  ]);

  final List<BusinessHoursRule> rules;

  /// The web's spellings: `true`, `false`, a rule (`{"daysOfWeek": [1,2],
  /// "start": "09:00", "end": "17:00", "timeZone": "Asia/Riyadh"}`) or a
  /// list of them. Never throws: null and an `invalid-option` error at
  /// [path] (the detail says what) when it cannot be read.
  static (BusinessHours?, List<Problem>) fromJson(Object? json, [String path = 'businessHours']) {
    (BusinessHours?, List<Problem>) bad(String why) =>
        (null, [Problem(ProblemCode.invalidOption, Severity.error, path, why)]);
    switch (json) {
      case true:
        return (standard, const []);
      case false:
        return (none, const []);
      case final List<Object?> list:
        final rules = <BusinessHoursRule>[];
        for (final x in list) {
          final (rule, why) = _rule(x);
          if (why != null) return bad(why);
          rules.add(rule!);
        }
        return (BusinessHours(rules), const []);
      default:
        final (rule, why) = _rule(json);
        return why != null ? bad(why) : (BusinessHours([rule!]), const []);
    }
  }

  /// A rule, or why it cannot be read.
  static (BusinessHoursRule?, String?) _rule(Object? x) {
    if (x is! Map) return (null, jsText(x));
    final days = x['daysOfWeek'];
    if (days is! List || !days.every((d) => d is int && d >= 1 && d <= 7)) return (null, 'daysOfWeek: ${jsText(days)}');
    final start = x['start'];
    final s = start is String ? WallTime.tryParse(start) : null;
    if (s == null) return (null, 'start: ${jsText(start)}');
    final end = x['end'];
    final e = end is String ? WallTime.tryParse(end) : null;
    if (e == null) return (null, 'end: ${jsText(end)}');
    final zone = x['timeZone'];
    if (zone != null && (zone is! String || !isValidZone(zone))) return (null, 'timeZone: ${jsText(zone)}');
    return (BusinessHoursRule(daysOfWeek: days.cast<int>(), from: s, to: e, timeZone: zone as String?), null);
  }

  @override
  bool operator ==(Object other) => other is BusinessHours && deepEquals(other.rules, rules);

  @override
  int get hashCode => deepHash(rules);
}

/// The open stretches between the start of [from] and the start of [to]
/// (exclusive) in [displayZone], as epoch-millisecond spans, sorted and merged.
///
/// Each rule is walked in its own zone's dates, with a day of margin each
/// side, so a rule in another zone or crossing midnight is never cut short;
/// every wall time is resolved (`compatible`), so an interval across a clock
/// change has its true length — a 22:00–06:00 shift on the 25-hour night is 9 h.
List<MsSpan> businessIntervals(PlainDate from, PlainDate to, BusinessHours hours, ZoneId displayZone) {
  final winStart = from.startOfDayIn(displayZone).epochMilliseconds;
  final winEnd = to.startOfDayIn(displayZone).epochMilliseconds;
  final spans = <MsSpan>[];
  for (final rule in hours.rules) {
    if (rule.from.isEndOfDay) continue;
    final zone = rule.timeZone ?? displayZone;
    final crosses = rule.to.isEndOfDay || rule.to.compareTo(rule.from) <= 0;
    final last = to.addDays(1);
    for (var d = from.addDays(-2); !d.isAfter(last); d = d.addDays(1)) {
      if (!rule.daysOfWeek.contains(d.dayOfWeek)) continue;
      final s = resolveWall(d, rule.from.time, zone, WallPolicy.compatible).instant!.epochMilliseconds;
      final endDate = crosses ? d.addDays(1) : d;
      final e = resolveWall(endDate, rule.to.time, zone, WallPolicy.compatible).instant!.epochMilliseconds;
      final cs = s > winStart ? s : winStart;
      final ce = e < winEnd ? e : winEnd;
      if (ce > cs) spans.add(MsSpan(cs, ce));
    }
  }
  return normalizeSpans(spans);
}
