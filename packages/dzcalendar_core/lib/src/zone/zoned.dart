import '../time/civil.dart';
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

  PlainDateTime get plainDateTime => instant.wallAt(offsetMs);
  PlainDate get date => plainDateTime.date;
  PlainTime get time => plainDateTime.time;

  @override
  int compareTo(ZonedDateTime other) => instant.compareTo(other.instant);

  @override
  bool operator ==(Object other) => other is ZonedDateTime && other.instant == instant && other.zone == zone;

  @override
  int get hashCode => Object.hash(instant, zone);

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
