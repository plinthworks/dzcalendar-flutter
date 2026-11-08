import '../time/civil.dart';
import '../time/duration.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../event/parse_temporal.dart';
import 'wall.dart';
import 'zone_rules.dart';

/// The rules for [zone]; a zone that names nothing is a programming error
/// here (bad *data* is checked, and reported, before it reaches the engine).
ZoneRules rulesFor(ZoneId zone) => ZoneRules.of(zone) ?? (throw ArgumentError.value(zone, 'zone', 'not a time zone'));

/// [zone] as [ZoneRules.normalize] writes it; throws like [rulesFor].
ZoneId normalizedZone(ZoneId zone) =>
    ZoneRules.normalize(zone) ?? (throw ArgumentError.value(zone, 'zone', 'not a time zone'));

/// An instant seen in a zone: its clock face and offset. Stands for
/// Temporal's `ZonedDateTime`.
final class ZonedDateTime implements Comparable<ZonedDateTime> {
  ZonedDateTime._(this.instant, this.zone, this.offsetMs);

  /// "2026-10-25T02:30:00+02:00[Europe/Paris]" (an occurrence's key, as
  /// Temporal writes a ZonedDateTime), or a wall time with its zone; the
  /// offset picks the reading of a repeated time. Null for anything else.
  static ZonedDateTime? tryParse(String text) => parseZonedDateTime(text);

  /// [wall] in [zone]: the reading whose offset is [preferOffsetMs] when the
  /// time has one (Temporal's `offset: 'prefer'` — a repeated 02:30 keeps the
  /// pass it was on), else as [how] says. The one place a wall time and an
  /// offset preference meet (parsing, recurrence). Null only for
  /// [Disambiguation.reject] on a time that is repeated or skipped.
  static ZonedDateTime? fromWall(
    PlainDateTime wall,
    ZoneId zone, {
    int? preferOffsetMs,
    Disambiguation how = Disambiguation.compatible,
  }) {
    final rules = rulesFor(zone);
    if (preferOffsetMs != null) {
      for (final at in possibleInstants(wall.wallMs, rules)) {
        if (rules.offsetAt(at) == preferOffsetMs) {
          return ZonedDateTime._(Instant.fromEpochMilliseconds(at), normalizedZone(zone), preferOffsetMs);
        }
      }
    }
    final ms = resolveWallMs(wall.wallMs, rules, how);
    return ms == null ? null : ZonedDateTime(Instant.fromEpochMilliseconds(ms), zone);
  }

  /// Throws [ArgumentError] when [zone] names no zone. The zone is kept as
  /// [ZoneRules.normalize] writes it.
  factory ZonedDateTime(Instant instant, ZoneId zone) =>
      ZonedDateTime._(instant, normalizedZone(zone), rulesFor(zone).offsetAt(instant.epochMilliseconds));

  final Instant instant;
  final ZoneId zone;

  /// Milliseconds east of UTC at that instant.
  final int offsetMs;

  /// "+02:00", "+00:09:21" (with its seconds; [toString] rounds to the minute).
  String get offset => offsetText(offsetMs);

  int get epochMilliseconds => instant.epochMilliseconds;

  PlainDateTime get plainDateTime => instant.wallAt(offsetMs);
  PlainDate get date => plainDateTime.date;
  PlainTime get time => plainDateTime.time;

  /// As Temporal's `add`: the calendar part moves the clock face (a day is
  /// the same time next day, 23 or 25 hours later across a change), read
  /// back `compatible`; then the exact part adds elapsed time.
  ZonedDateTime add(IsoDuration duration) {
    var ms = instant.epochMilliseconds;
    if (!duration.isExact) {
      final wall = plainDateTime;
      final moved = PlainDateTime(duration.addCalendarTo(wall.date), wall.time);
      ms = resolveWallMs(moved.wallMs, rulesFor(zone), Disambiguation.compatible)!;
    }
    return ZonedDateTime(Instant.fromEpochMilliseconds(ms + duration.exactMs), zone);
  }

  ZonedDateTime subtract(IsoDuration duration) => add(duration.negated());

  /// From this moment to [other] as Temporal's `until({ largestUnit: 'days' })`:
  /// whole days on the clock face in this zone (23 or 25 hours across a
  /// change), then the exact rest. [other] is read in this zone.
  IsoDuration untilInDays(ZonedDateTime other) {
    final from = epochMilliseconds;
    final to = other.epochMilliseconds;
    if (from == to) return IsoDuration.zero;
    final sign = to > from ? 1 : -1;
    final rules = rulesFor(zone);
    final startWall = plainDateTime;
    final endWall = other.instant.wallAt(rules.offsetAt(to));
    // The same date on the clock: exact time only, as Temporal (an end in
    // the second pass of a repeated hour may read earlier than the start).
    if (startWall.date == endWall.date) return _exact(to - from);
    var correction = 0;
    final timeSign = (endWall.time.msOfDay - startWall.time.msOfDay).sign;
    if (timeSign == -sign) correction = 1;
    // At most one more day back (forward) than the first guess, as Temporal.
    final maxCorrection = correction + (sign > 0 ? 1 : 0);
    for (; ; correction++) {
      final date = endWall.date.addDays(-correction * sign);
      final mid = resolveWallMs(PlainDateTime(date, startWall.time).wallMs, rules, Disambiguation.compatible)!;
      final rest = to - mid;
      if (rest.sign != -sign || correction >= maxCorrection) {
        final exact = _exact(rest);
        return IsoDuration(
          days: startWall.date.daysUntil(date),
          hours: exact.hours,
          minutes: exact.minutes,
          seconds: exact.seconds,
          milliseconds: exact.milliseconds,
        );
      }
    }
  }

  static IsoDuration _exact(int ms) {
    final sign = ms < 0 ? -1 : 1;
    final abs = ms.abs();
    return IsoDuration(
      hours: sign * (abs ~/ msPerHour),
      minutes: sign * (abs ~/ msPerMinute % 60),
      seconds: sign * (abs ~/ msPerSecond % 60),
      milliseconds: sign * (abs % msPerSecond),
    );
  }

  /// The same instant seen in [other].
  ZonedDateTime withTimeZone(ZoneId other) => ZonedDateTime(instant, other);

  /// The first instant of this date in this zone.
  ZonedDateTime startOfDay() =>
      ZonedDateTime(Instant.fromEpochMilliseconds(startOfDayMs(date.epochDay * msPerDay, rulesFor(zone))), zone);

  @override
  int compareTo(ZonedDateTime other) => instant.compareTo(other.instant);

  /// The same instant in the same zone. A link and its zone are one zone
  /// ("Asia/Calcutta", "Asia/Kolkata"), as Temporal's `equals` (owner,
  /// 2026-11-08); the name written is kept for display.
  @override
  bool operator ==(Object other) =>
      other is ZonedDateTime &&
      other.instant == instant &&
      (other.zone == zone || ZoneRules.canonical(other.zone) == ZoneRules.canonical(zone));

  @override
  int get hashCode => Object.hash(instant, ZoneRules.canonical(zone));

  /// "2026-03-29T03:00:00+02:00[Europe/Paris]", as Temporal writes it.
  @override
  String toString() => '$plainDateTime${offsetTextToMinute(offsetMs)}[$zone]';
}

extension InstantInZone on Instant {
  /// Throws [ArgumentError] when [zone] names no zone.
  ZonedDateTime inZone(ZoneId zone) => ZonedDateTime(this, zone);
}

extension PlainDateInZone on PlainDate {
  /// The first instant of this date in [zone] — midnight, or the clock
  /// change that skips it (Temporal's `startOfDay`).
  Instant startOfDayIn(ZoneId zone) => Instant.fromEpochMilliseconds(startOfDayMs(epochDay * msPerDay, rulesFor(zone)));
}

extension PlainDateTimeInZone on PlainDateTime {
  /// This clock face in [zone], as Temporal's `toZonedDateTime`; null only
  /// for [Disambiguation.reject] on a time that happens twice or never. (A
  /// skipped time comes back moved: its clock face is not this one.)
  ZonedDateTime? inZone(ZoneId zone, [Disambiguation how = Disambiguation.compatible]) {
    final ms = resolveWallMs(wallMs, rulesFor(zone), how);
    return ms == null ? null : ZonedDateTime(Instant.fromEpochMilliseconds(ms), zone);
  }
}
