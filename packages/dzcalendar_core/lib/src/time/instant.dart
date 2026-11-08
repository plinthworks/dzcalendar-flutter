import 'civil.dart';
import 'plain.dart';

/// A point on the time line, to the millisecond, with no zone. Stands for
/// Temporal's `Instant`; milliseconds since the epoch are what the indexes
/// sort on (the TypeScript core's `EpochMs`).
final class Instant implements Comparable<Instant> {
  const Instant.fromEpochMilliseconds(this.epochMilliseconds);

  /// "2026-03-29T01:00:00Z", "2026-03-29T03:00:00+02:00", with or without a
  /// trailing "[Europe/Paris]" (an annotation: the offset decides). An instant
  /// needs its offset; a bare date-time is no instant.
  static Instant? tryParse(String text) {
    var body = text;
    final bracket = body.indexOf('[');
    if (bracket >= 0) {
      if (!body.endsWith(']')) return null;
      body = body.substring(0, bracket);
    }
    final d = readDate(body);
    if (d == null || d.$4.isEmpty || (d.$4[0] != 'T' && d.$4[0] != 't')) return null;
    final t = readTime(d.$4.substring(1));
    if (t == null) return null;
    final rest = t.$2;
    final int offset;
    if (rest == 'Z' || rest == 'z') {
      offset = 0;
    } else {
      final o = parseOffsetMs(rest);
      if (o == null) return null;
      offset = o;
    }
    final wall = epochDayOf(d.$1, d.$2, d.$3) * msPerDay + t.$1;
    return Instant.fromEpochMilliseconds(wall - offset);
  }

  static Instant parse(String text) => tryParse(text) ?? (throw FormatException('not an ISO instant', text));

  final int epochMilliseconds;

  Instant addMs(int ms) => ms == 0 ? this : Instant.fromEpochMilliseconds(epochMilliseconds + ms);
  Instant add(Duration elapsed) => addMs(elapsed.inMilliseconds);

  /// Elapsed time from this instant to [other].
  Duration until(Instant other) => Duration(milliseconds: other.epochMilliseconds - epochMilliseconds);

  bool isBefore(Instant other) => epochMilliseconds < other.epochMilliseconds;
  bool isAfter(Instant other) => epochMilliseconds > other.epochMilliseconds;

  /// The clock face in UTC plus [offsetMs]: no zone asked.
  PlainDateTime wallAt(int offsetMs) => PlainDateTime.fromWallMs(epochMilliseconds + offsetMs);

  @override
  int compareTo(Instant other) => epochMilliseconds.compareTo(other.epochMilliseconds);

  @override
  bool operator ==(Object other) => other is Instant && other.epochMilliseconds == epochMilliseconds;

  @override
  int get hashCode => epochMilliseconds.hashCode;

  /// "2026-03-29T01:00:00Z", as Temporal writes it.
  @override
  String toString() => '${wallAt(0)}Z';
}
