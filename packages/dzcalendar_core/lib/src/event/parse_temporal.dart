import '../time/civil.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/day_info.dart';
import '../zone/wall.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'problem.dart';

/// One moment as written, sorted into what it actually says.
sealed class Parsed {
  const Parsed();
}

/// A place and a time: the only form that is a moment by itself.
final class ParsedZoned extends Parsed {
  const ParsedZoned(this.value);
  final ZonedDateTime value;
}

/// A moment with no place (`…Z`, `…+02:00`, an [Instant]).
final class ParsedInstant extends Parsed {
  const ParsedInstant(this.value);
  final Instant value;
}

/// A clock reading with no place (`2026-03-29T09:00`).
final class ParsedWall extends Parsed {
  const ParsedWall(this.value);
  final PlainDateTime value;
}

/// A calendar day.
final class ParsedDate extends Parsed {
  const ParsedDate(this.value);
  final PlainDate value;
}

/// What [parseTemporal] found, or why it could not: `parsed` is null when
/// `problems` holds an error.
typedef ParseResult = ({Parsed? parsed, List<Problem> problems});

/// [input] read as a moment. `start` names the error code: start errors are
/// `invalid-start`, end errors `invalid-end`. Never throws.
ParseResult parseTemporal(Object? input, String path, {required bool start}) {
  final invalid = start ? ProblemCode.invalidStart : ProblemCode.invalidEnd;
  ParseResult fail(ProblemCode code, String detail) =>
      (parsed: null, problems: [Problem(code, Severity.error, path, detail)]);
  return switch (input) {
    ZonedDateTime v => (parsed: ParsedZoned(v), problems: const []),
    Instant v => (parsed: ParsedInstant(v), problems: const []),
    PlainDateTime v => (parsed: ParsedWall(v), problems: const []),
    PlainDate v => (parsed: ParsedDate(v), problems: const []),
    // Owner (2026-11-08), as the web refuses Date (K.15): no zone, no guess.
    DateTime _ => fail(
      ProblemCode.dateObjectRejected,
      'convert explicitly: Instant.fromEpochMilliseconds(value.millisecondsSinceEpoch)',
    ),
    String s => _parseString(s, path, invalid),
    null => fail(invalid, 'absent'),
    _ => fail(invalid, 'not a time value or an ISO 8601 string: ${input.runtimeType}'),
  };
}

/// Temporal's limits: instants within ±10⁸ days of the epoch, dates from
/// -271821-04-19 (day -100 000 001) to +275760-09-13 (day 100 000 000).
const _maxEpochMs = 8640000000000000;
bool _inRange(int epochDay) => epochDay >= -100000001 && epochDay <= 100000000;
bool _instantInRange(int ms) => ms.abs() <= _maxEpochMs;

final _zoneAnnotation = RegExp(r'\[!?([^\]=]+)\]');
final _toMinuteOffset = RegExp(r'^[+-]\d{2}(:?\d{2})?$');
// Seconds with a fraction past the millisecond that is not all zeros.
final _subMs = RegExp(r'^[Tt ]\d{2}:?\d{2}:?\d{2}[.,]\d{3}(\d{1,6})');

/// The parts of an ISO 8601 string, as Temporal's grammar has them.
final class _Iso {
  _Iso(this.date, this.msOfDay, this.offset, this.zone);
  final PlainDate date;
  final int? msOfDay;

  /// Milliseconds east of UTC; 0 for "Z" (see [exact]).
  final int? offset;
  final String? zone;
  bool exact = false;

  /// Digits below the millisecond were dropped.
  bool truncated = false;

  /// The offset was written to the minute ("+00:09"), so it may stand for
  /// an offset with seconds (Paris until 1911), as Temporal matches it.
  bool offsetToMinute = false;
}

final _annotation = RegExp(r'^\[(!?)([^\]=\[]+)(?:=([^\]\[]+))?\]');

/// Null when [text] is no ISO 8601 date, date-time, instant or zoned string.
_Iso? _readIso(String text) {
  final d = readDate(text);
  if (d == null) return null;
  final date = PlainDate(d.$1, d.$2, d.$3);
  if (!_inRange(date.epochDay)) return null;
  var rest = d.$4;
  int? ms;
  int? offset;
  var exact = false;
  var toMinute = false;
  var truncated = false;
  if (rest.isNotEmpty && 'Tt '.contains(rest[0])) {
    final lost = _subMs.firstMatch(rest)?[1];
    truncated = lost != null && int.parse(lost) != 0;
    final t = readTime(rest.substring(1));
    if (t == null) return null;
    ms = t.$1;
    rest = t.$2;
    final bracket = rest.indexOf('[');
    final head = bracket < 0 ? rest : rest.substring(0, bracket);
    rest = bracket < 0 ? '' : rest.substring(bracket);
    if (head == 'Z' || head == 'z') {
      offset = 0;
      exact = true;
    } else if (head.isNotEmpty) {
      offset = parseOffsetMs(head);
      if (offset == null) return null;
      toMinute = _toMinuteOffset.hasMatch(head);
    }
  }
  String? zone;
  var calendarSeen = false;
  while (rest.isNotEmpty) {
    final m = _annotation.firstMatch(rest);
    if (m == null) return null;
    rest = rest.substring(m.end);
    final critical = m[1] == '!';
    final key = m[2]!;
    final value = m[3];
    if (value == null) {
      // A zone: one only, and first.
      if (zone != null || calendarSeen) return null;
      zone = key;
    } else if (key == 'u-ca') {
      // The model counts in ISO: the fields written are ISO's anyway, and the
      // calendar a reader sees comes from the locale, at format time.
      calendarSeen = true;
    } else if (critical) {
      return null; // an annotation Temporal must understand and does not
    }
  }
  return _Iso(date, ms, offset, zone)
    ..exact = exact
    ..offsetToMinute = toMinute
    ..truncated = truncated;
}

ParseResult _parseString(String raw, String path, ProblemCode invalid) {
  final text = raw.trim();
  ParseResult fail(ProblemCode code, String detail) =>
      (parsed: null, problems: [Problem(code, Severity.error, path, detail)]);
  // The zone first, as the TypeScript core reads it: a name that is no zone
  // is said as such, whatever else the string holds.
  final named = _zoneAnnotation.firstMatch(text)?[1];
  if (named != null && !named.startsWith('u-') && !isValidZone(named)) return fail(ProblemCode.unknownZone, named);
  final iso = _readIso(text);
  if (iso == null) return fail(invalid, 'not ISO 8601: $raw');
  final warnings = [if (iso.truncated) Problem(ProblemCode.precisionTruncated, Severity.warning, path, raw)];
  ParseResult ok(Parsed p, [List<Problem> more = const []]) => (parsed: p, problems: [...warnings, ...more]);
  final zone = iso.zone;
  final ms = iso.msOfDay;

  if (zone != null) {
    final rules = ZoneRules.of(zone);
    if (rules == null) return fail(ProblemCode.unknownZone, zone);
    final r = _parseZoned(iso, text, zone, rules, path);
    final value = r.value;
    if (!_instantInRange(value.epochMilliseconds)) return fail(invalid, 'outside the range of time: $raw');
    return ok(ParsedZoned(value), r.problems);
  }
  if (ms == null) return ok(ParsedDate(iso.date));
  final wallMs = iso.date.epochDay * msPerDay + ms;
  final offset = iso.offset;
  if (offset != null) {
    final at = wallMs - offset;
    if (!_instantInRange(at)) return fail(invalid, 'outside the range of time: $raw');
    return ok(ParsedInstant(Instant.fromEpochMilliseconds(at)));
  }
  return ok(ParsedWall(PlainDateTime.fromWallMs(wallMs)));
}

({ZonedDateTime value, List<Problem> problems}) _parseZoned(
  _Iso iso,
  String text,
  String zone,
  ZoneRules rules,
  String path,
) {
  final problems = <Problem>[];
  if (isOffsetZone(zone)) problems.add(Problem(ProblemCode.offsetOnly, Severity.warning, path, zone));
  final wall = PlainDateTime.fromWallMs(iso.date.epochDay * msPerDay + (iso.msOfDay ?? 0));
  final offset = iso.offset;

  if (offset != null) {
    if (iso.exact) {
      final at = Instant.fromEpochMilliseconds(wall.wallMs);
      return (value: ZonedDateTime(at, zone), problems: problems);
    }
    // The offset picks among the wall time's readings (the two 02:30s of a
    // fall-back night). One the zone never had there is stale data written
    // before a rule change, usually: the zone is the authority, the wall
    // time stands, read `compatible` (Temporal's `offset: 'ignore'`).
    for (final at in possibleInstants(wall.wallMs, rules)) {
      final actual = rules.offsetAt(at);
      final matches = iso.offsetToMinute ? _toMinute(actual) == offset : actual == offset;
      if (matches) {
        return (value: ZonedDateTime(Instant.fromEpochMilliseconds(at), zone), problems: problems);
      }
    }
    final at = resolveWallMs(wall.wallMs, rules, Disambiguation.compatible)!;
    final value = ZonedDateTime(Instant.fromEpochMilliseconds(at), zone);
    problems.add(Problem(ProblemCode.offsetMismatch, Severity.warning, path, '$text → ${value.offset}'));
    return (value: value, problems: problems);
  }

  final placed = placeWall(wall, zone, path);
  return (value: placed.value, problems: [...problems, ...placed.problems]);
}

int _toMinute(int offsetMs) {
  final minutes = (offsetMs.abs() + msPerMinute ~/ 2) ~/ msPerMinute;
  return (offsetMs < 0 ? -minutes : minutes) * msPerMinute;
}

/// A clock reading put in a zone. A skipped reading moves forward
/// (02:30 becomes 03:30 in Paris each March); a repeated one takes its first
/// occurrence. Both say so.
({ZonedDateTime value, List<Problem> problems}) placeWall(PlainDateTime wall, ZoneId zone, String path) {
  final rules = rulesFor(zone);
  if (isQuietDay(wall.date, zone)) {
    final at = resolveWallMs(wall.wallMs, rules, Disambiguation.compatible)!;
    return (value: ZonedDateTime(Instant.fromEpochMilliseconds(at), zone), problems: const []);
  }
  final readings = possibleInstants(wall.wallMs, rules);
  if (readings.length == 1) {
    return (value: ZonedDateTime(Instant.fromEpochMilliseconds(readings.single), zone), problems: const []);
  }
  if (readings.length > 1) {
    final value = ZonedDateTime(Instant.fromEpochMilliseconds(readings.first), zone);
    return (
      value: value,
      problems: [Problem(ProblemCode.wallTimeAmbiguous, Severity.warning, path, '$wall → ${value.offset}')],
    );
  }
  final at = resolveWallMs(wall.wallMs, rules, Disambiguation.later)!;
  final value = ZonedDateTime(Instant.fromEpochMilliseconds(at), zone);
  return (
    value: value,
    problems: [Problem(ProblemCode.wallTimeSkipped, Severity.warning, path, '$wall → ${value.plainDateTime}')],
  );
}
