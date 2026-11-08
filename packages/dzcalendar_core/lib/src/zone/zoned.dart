import '../time/civil.dart';
import '../time/duration.dart';
import '../time/instant.dart';
import '../time/plain.dart';
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
