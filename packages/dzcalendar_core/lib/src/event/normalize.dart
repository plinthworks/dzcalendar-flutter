import '../time/duration.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'parse_temporal.dart';
import 'problem.dart';
import 'types.dart';

/// Identifiers the calendar makes up itself, for an event handed in without
/// one. A value, not a global counter: a test injects a deterministic one,
/// and two calendars never share a sequence.
typedef IdGenerator = String Function();

IdGenerator createIdGenerator([String prefix = 'dz']) {
  var next = 0;
  return () => '$prefix-${++next}';
}

final class NormalizeContext {
  const NormalizeContext({
    required this.displayZone,
    required this.newId,
    this.defaultEventZone,
    this.defaultTimedDuration,
    this.defaultAllDayDuration,
    this.strictZones = false,
    this.now,
    this.knownResources,
  });

  /// Where the calendar is read: the last resort for an event naming no zone.
  final ZoneId displayZone;

  /// The zone of events that name none, before [displayZone].
  final ZoneId? defaultEventZone;
  final IsoDuration? defaultTimedDuration;
  final IsoDuration? defaultAllDayDuration;

  /// True: a moment without a zone is an error rather than a guess.
  final bool strictZones;
  final IdGenerator newId;

  /// The present, for an event still running; absent, its expected end stands.
  final Instant Function()? now;

  /// When given, a resource id outside it is reported.
  final Set<ResourceId>? knownResources;
}

/// One event; a series (19c) will be the other kind.
sealed class Normalized {
  const Normalized();

  /// The event the item stands for.
  CalEvent get event;
}

final class NormalizedEvent extends Normalized {
  const NormalizedEvent(this.event);
  @override
  final CalEvent event;
}

/// An accepted input ([value] set, with its warnings) or a refused one.
final class NormalizeResult {
  const NormalizeResult._(this.value, this.problems);
  final Normalized? value;
  final List<Problem> problems;
  bool get ok => value != null;
}

final class NormalizationReport {
  const NormalizationReport(this.accepted, this.rejected, this.problems);
  final int accepted;
  final int rejected;
  final List<Problem> problems;
}

final _defaultTimed = IsoDuration(hours: 1);
final _defaultAllDay = IsoDuration(days: 1);
const _maxEpochMs = 8640000000000000;

/// A bad context is the programmer's mistake, not the data's, and would fail
/// every event the same way: it throws, once.
void _assertContext(NormalizeContext ctx) {
  if (!isValidZone(ctx.displayZone)) {
    throw ArgumentError.value(ctx.displayZone, 'displayZone', 'not a time zone');
  }
  final zone = ctx.defaultEventZone;
  if (zone != null && !isValidZone(zone)) {
    throw ArgumentError.value(zone, 'defaultEventZone', 'not a time zone');
  }
}

/// One loose input to one strict event, or the reasons it cannot be one.
///
/// Bad data never throws: one malformed row from an API cannot take the
/// screen down. Every guess — a zone assumed, a skipped wall time moved — is
/// a warning, so nothing is bent in silence. A bad [ctx] does throw.
NormalizeResult normalizeEvent(EventInput input, NormalizeContext ctx, [String path = 'event']) {
  _assertContext(ctx);
  return _checked(input, ctx, path);
}

NormalizeResult _checked(EventInput input, NormalizeContext ctx, String path) {
  try {
    return _normalize(input, ctx, path);
  } on Object catch (e) {
    // Whatever a check missed still becomes a problem, never an exception.
    return NormalizeResult._(null, [Problem(ProblemCode.invalidEvent, Severity.error, path, '$e')]);
  }
}

NormalizeResult _normalize(EventInput input, NormalizeContext ctx, String path) {
  final problems = <Problem>[];
  NormalizeResult failed() => NormalizeResult._(null, problems);
  bool hasError() => problems.any((p) => p.isError);
  void add(ProblemCode code, Severity severity, String at, [String? detail]) =>
      problems.add(Problem(code, severity, at, detail));

  for (final (code, field, detail) in readProblemsOf(input)) {
    add(code, Severity.error, '$path.$field', detail);
  }
  if (input.id == '') add(ProblemCode.invalidId, Severity.error, '$path.id', '');
  final zone = input.timeZone;
  if (zone != null && !isValidZone(zone)) add(ProblemCode.unknownZone, Severity.error, '$path.timeZone', zone);

  if (input.start == null) {
    add(ProblemCode.missingStart, Severity.error, '$path.start');
    return failed();
  }
  final start = parseTemporal(input.start, '$path.start', start: true);
  problems.addAll(start.problems);
  final end = input.end == null ? null : parseTemporal(input.end, '$path.end', start: false);
  if (end != null) problems.addAll(end.problems);

  IsoDuration? duration;
  if (input.duration != null) {
    duration = IsoDuration.tryFrom(input.duration);
    if (duration == null || duration.sign < 0) {
      add(ProblemCode.invalidDuration, Severity.error, '$path.duration', '${input.duration}');
    } else if (IsoDuration.losesPrecision(input.duration)) {
      add(ProblemCode.precisionTruncated, Severity.warning, '$path.duration', '${input.duration}');
    }
  }

  final startParsed = start.parsed;
  if (startParsed == null || (end != null && end.parsed == null) || hasError()) return failed();
  final endParsed = end?.parsed;
  final allDay = input.allDay ?? (startParsed is ParsedDate && (endParsed == null || endParsed is ParsedDate));

  // A marker is a moment: its start alone, whatever came with it.
  final marker = input.display == EventDisplay.marker;
  if (marker && allDay) {
    add(ProblemCode.markerAllDay, Severity.error, '$path.start', '${input.start}');
    return failed();
  }
  final ongoing = input.ongoing == true && !marker;
  if (ongoing && (allDay || input.rrule != null)) {
    add(ProblemCode.ongoingNotTimed, Severity.error, '$path.ongoing', allDay ? '${input.start}' : 'rrule');
    return failed();
  }
  if (marker && (endParsed != null || duration != null)) {
    add(
      ProblemCode.markerLengthIgnored,
      Severity.warning,
      endParsed != null ? '$path.end' : '$path.duration',
      '${endParsed != null ? input.end : input.duration}',
    );
  }

  // Repeating events, and overrides of one occurrence, come with the
  // recurrence engine (Phase 19c).
  if (input.rrule != null) {
    add(ProblemCode.invalidRrule, Severity.error, '$path.rrule', 'recurrence is not ported yet (19c)');
    return failed();
  }
  if (input.recurrenceId != null) {
    add(ProblemCode.invalidRecurrenceId, Severity.error, '$path.recurrenceId', 'not ported yet (19c)');
    return failed();
  }

  final common = _Common.of(input, ctx, path, problems);
  CalEvent? event;
  if (allDay) {
    event = _allDay(input, ctx, path, common, startParsed, endParsed, duration, problems);
  } else if (marker || (ongoing && endParsed == null && duration == null)) {
    event = _timed(input, ctx, path, common, startParsed, null, IsoDuration.zero, problems);
  } else {
    event = _timed(input, ctx, path, common, startParsed, endParsed, duration, problems);
  }
  if (event == null || hasError()) return failed();
  if (ongoing && event is TimedEvent) {
    event = _stillRunning(event, endParsed != null || duration != null, ctx.now?.call());
  }
  return NormalizeResult._(NormalizedEvent(event), problems);
}

final _spaces = RegExp(r'\s+');
final _tone = RegExp(r'^[a-z0-9_-]+$', caseSensitive: false);
const _empty = <String>[];

// Ten thousand events without resources or classes share one empty list, and
// one permissions object per combination (the TypeScript core does the same).
List<String> _list(List<String> xs) => xs.isEmpty ? _empty : List.unmodifiable(xs);
final _permsTable = [
  for (var i = 0; i < 32; i++)
    EventPerms(
      start: i & 1 != 0,
      duration: i & 2 != 0,
      resource: i & 4 != 0,
      ownStart: i & 8 != 0,
      ownDuration: i & 16 != 0,
    ),
];
EventPerms _perms(bool start, bool duration, bool resource, bool ownStart, bool ownDuration) =>
    _permsTable[(start ? 1 : 0) |
        (duration ? 2 : 0) |
        (resource ? 4 : 0) |
        (ownStart ? 8 : 0) |
        (ownDuration ? 16 : 0)];

/// The fields every event has, read once.
final class _Common {
  _Common(this.id, this.input, this.resourceIds, this.perms, this.classNames, this.tone, this.props);

  final String id;
  final EventInput input;
  final List<String> resourceIds;
  final EventPerms perms;
  final List<String> classNames;
  final String? tone;
  final Map<String, Object?> props;

  static _Common of(EventInput input, NormalizeContext ctx, String path, List<Problem> problems) {
    final ids = <String>{if (input.resourceId != null) input.resourceId!, ...?input.resourceIds}.toList();
    final known = ctx.knownResources;
    if (known != null) {
      for (final r in ids) {
        if (!known.contains(r)) {
          problems.add(Problem(ProblemCode.unknownResource, Severity.warning, '$path.resourceIds', r));
        }
      }
    }
    final editable = input.editable ?? true;
    final start = input.startEditable ?? editable;
    final duration = input.durationEditable ?? editable;
    // Class names as tokens: "a b" is two classes, "" none.
    final classes = <String>{
      for (final c in input.classNames ?? const <String>[]) ...c.split(_spaces).where((t) => t.isNotEmpty),
    }.toList();
    final tone = input.tone;
    final props = input.extendedProps;
    return _Common(
      input.id ?? ctx.newId(),
      input,
      _list(ids),
      _perms(
        start,
        duration,
        input.resourceEditable ?? editable,
        // What it said `true` to itself: its own field, else `editable`.
        start && (input.startEditable ?? input.editable) == true,
        duration && (input.durationEditable ?? input.editable) == true,
      ),
      _list(classes),
      // A tone names a theme token: anything else is ignored, never interpolated.
      tone != null && _tone.hasMatch(tone) ? tone : null,
      props == null || props.isEmpty ? const {} : Map.unmodifiable(props),
    );
  }

  EventStatus get status => input.status ?? EventStatus.confirmed;
  bool get busy => input.busy ?? status != EventStatus.cancelled;
}

/// The zone a moment without one is read in, and whether that was a guess.
({ZoneId zone, bool guessed}) _eventZone(EventInput input, NormalizeContext ctx) {
  final named = input.timeZone ?? ctx.defaultEventZone;
  return named != null ? (zone: named, guessed: false) : (zone: ctx.displayZone, guessed: true);
}

({ZonedDateTime value, bool guessed})? _toZoned(
  Parsed parsed,
  EventInput input,
  NormalizeContext ctx,
  String path,
  List<Problem> problems, [
  ZoneId? zoneOverride,
]) {
  if (parsed is ParsedZoned) return (value: parsed.value, guessed: false);
  final (:zone, :guessed) = zoneOverride != null ? (zone: zoneOverride, guessed: false) : _eventZone(input, ctx);
  if (guessed) {
    final code = parsed is ParsedInstant ? ProblemCode.offsetOnly : ProblemCode.zoneDefaulted;
    if (ctx.strictZones) {
      problems.add(Problem(code, Severity.error, path, 'strictZones'));
      return null;
    }
    problems.add(Problem(code, Severity.warning, path, zone));
  }
  switch (parsed) {
    case ParsedInstant(:final value):
      return (value: value.inZone(zone), guessed: guessed);
    case ParsedWall(:final value):
      final placed = placeWall(value, zone, path);
      problems.addAll(placed.problems);
      return (value: placed.value, guessed: guessed);
    case ParsedDate(:final value):
      return (value: ZonedDateTime(value.startOfDayIn(zone), zone), guessed: guessed);
    case ParsedZoned():
      throw StateError('unreachable');
  }
}

TimedEvent? _timed(
  EventInput input,
  NormalizeContext ctx,
  String path,
  _Common c,
  Parsed startP,
  Parsed? endP,
  IsoDuration? duration,
  List<Problem> problems,
) {
  final placed = _toZoned(startP, input, ctx, '$path.start', problems);
  if (placed == null) return null;
  final start = placed.value;

  ZonedDateTime end;
  if (endP != null) {
    // An end without a zone of its own is read in the start's zone — the
    // event's — not the display zone, which belongs to the reader.
    final placedEnd = _toZoned(endP, input, ctx, '$path.end', problems, endP is ParsedZoned ? null : start.zone);
    if (placedEnd == null) return null;
    end = placedEnd.value;
  } else {
    final d = duration ?? ctx.defaultTimedDuration ?? _defaultTimed;
    end = start.add(d);
    if (end.epochMilliseconds.abs() > _maxEpochMs) {
      problems.add(Problem(ProblemCode.invalidDuration, Severity.error, '$path.duration', 'outside the range of time'));
      return null;
    }
  }

  // Compared as instants, whatever the two zones.
  if (end.instant.isBefore(start.instant)) {
    problems.add(Problem(ProblemCode.endBeforeStart, Severity.error, '$path.end', '$start > $end'));
    return null;
  }
  return TimedEvent(
    id: c.id,
    groupId: input.groupId,
    title: input.title ?? '',
    resourceIds: c.resourceIds,
    display: input.display ?? EventDisplay.auto,
    status: c.status,
    busy: c.busy,
    perms: c.perms,
    classNames: c.classNames,
    tone: c.tone,
    url: input.url,
    props: c.props,
    revision: 0,
    start: start,
    end: end,
    zoneGuessed: placed.guessed,
  );
}

AllDayEvent? _allDay(
  EventInput input,
  NormalizeContext ctx,
  String path,
  _Common c,
  Parsed startP,
  Parsed? endP,
  IsoDuration? duration,
  List<Problem> problems,
) {
  // A zone serves an all-day event read from an instant: it says which date
  // the instant falls on. Otherwise the event floats and the zone is noise.
  final zone = input.timeZone;
  if (zone != null && startP is! ParsedInstant && endP is! ParsedInstant) {
    problems.add(Problem(ProblemCode.alldayZoneIgnored, Severity.warning, '$path.timeZone', zone));
  }
  final start = _toDate(startP, input, ctx, '$path.start', problems);
  if (start == null) return null;
  PlainDate? end;
  if (endP != null) {
    end = _toDate(endP, input, ctx, '$path.end', problems);
  } else {
    final d = duration ?? ctx.defaultAllDayDuration ?? _defaultAllDay;
    // Only whole days move a date; hours on an all-day event mean nothing.
    final days = d.totalDaysFrom(start).truncate();
    end = start.addDays(days < 1 ? 1 : days);
    // Temporal's dates end ±271 821 years out (10⁸ days from 1970).
    if (end.epochDay > 100000000) {
      problems.add(Problem(ProblemCode.invalidDuration, Severity.error, '$path.duration', 'outside the range of time'));
      return null;
    }
  }
  if (end == null) return null;
  if (!end.isAfter(start)) {
    problems.add(Problem(ProblemCode.endBeforeStart, Severity.error, '$path.end', '$start ≥ $end (end is exclusive)'));
    return null;
  }
  return AllDayEvent(
    id: c.id,
    groupId: input.groupId,
    title: input.title ?? '',
    resourceIds: c.resourceIds,
    display: input.display ?? EventDisplay.auto,
    status: c.status,
    busy: c.busy,
    perms: c.perms,
    classNames: c.classNames,
    tone: c.tone,
    url: input.url,
    props: c.props,
    revision: 0,
    start: start,
    end: end,
  );
}

PlainDate? _toDate(Parsed parsed, EventInput input, NormalizeContext ctx, String path, List<Problem> problems) {
  final value = switch (parsed) {
    ParsedDate(:final value) => value,
    ParsedWall(:final value) => value,
    ParsedZoned(:final value) => value,
    ParsedInstant(:final value) => value,
  };
  if (parsed is ParsedDate) return parsed.value;
  problems.add(Problem(ProblemCode.alldayWithTime, Severity.warning, path, '$value'));
  if (parsed is ParsedWall) return parsed.value.date;
  // An instant has a date only somewhere: same zone rules, same warnings.
  return _toZoned(parsed, input, ctx, path, problems)?.value.date;
}

/// A running event: its end where now is (never before its start or its
/// expected end), the expected end kept.
TimedEvent _stillRunning(TimedEvent e, bool expected, Instant? now) {
  final end = now != null && now.isAfter(e.end.instant) ? now.inZone(e.end.zone) : e.end;
  return e.copyWith(end: end, ongoing: true, expectedEnd: expected ? e.end : null);
}

/// cyrb53, a 53-bit string hash, as the TypeScript core computes it — so a
/// source's event gets the same derived id on every platform.
String hash53(String text, [int seed = 0]) {
  var h1 = (0xdeadbeef ^ seed).toSigned(32);
  var h2 = (0x41c6ce57 ^ seed).toSigned(32);
  for (final ch in text.codeUnits) {
    h1 = _imul(h1 ^ ch, 2654435761);
    h2 = _imul(h2 ^ ch, 1597334677);
  }
  h1 = _imul(h1 ^ (h1.toUnsigned(32) >> 16), 2246822507) ^ _imul(h2 ^ (h2.toUnsigned(32) >> 13), 3266489909);
  h2 = _imul(h2 ^ (h2.toUnsigned(32) >> 16), 2246822507) ^ _imul(h1 ^ (h1.toUnsigned(32) >> 13), 3266489909);
  return (4294967296 * (2097151 & h2) + h1.toUnsigned(32)).toRadixString(36);
}

/// JavaScript's `Math.imul`: the low 32 bits of the product, signed. Split in
/// 16-bit halves so no product leaves 53 bits (exact when compiled to JS).
int _imul(int a, int b) {
  final a32 = a.toUnsigned(32);
  final b32 = b.toUnsigned(32);
  final lo = (a32 & 0xffff) * b32;
  final hi = ((a32 >> 16) * (b32 & 0xffff)).toUnsigned(16) << 16;
  return (lo + hi).toSigned(32);
}

/// Many inputs, each judged alone. A rejected input never stops the others;
/// a repeated id rejects the later input and keeps the first.
///
/// With a [sourceId], an event the source sent without an id gets one
/// derived from what it is — source, start, end, title — not from a counter:
/// fetched again, it is the same event. Identical events in one batch are
/// told apart by their rank: `#1`, `#2`. [indexes] places a part of a list
/// in the whole, for the problems' paths.
({List<Normalized> items, NormalizationReport report}) normalizeMany(
  Iterable<EventInput> inputs,
  NormalizeContext ctx, {
  String? sourceId,
  List<int>? indexes,
}) {
  _assertContext(ctx);
  final items = <Normalized>[];
  final problems = <Problem>[];
  final seen = <String>{};
  final ranks = <String, int>{};
  Problem tag(Problem p) => sourceId == null ? p : p.withSource(sourceId);
  var rejected = 0;
  var i = 0;
  for (final input in inputs) {
    final path = 'events[${indexes != null ? indexes[i] : i}]';
    i++;
    final r = _checked(input, ctx, path);
    problems.addAll(r.problems.map(tag));
    final item = r.value;
    if (item == null) {
      rejected++;
      continue;
    }
    var event = item.event;
    if (sourceId != null) {
      var id = event.id;
      if (input.id == null) {
        // Two 53-bit hashes under different seeds: ~106 bits, so ids derived
        // across chunks and refreshes do not meet by chance.
        final text = '${_startText(event)}|${_endText(event)}|${event.title}';
        final base = '$sourceId:${hash53(text)}${hash53(text, 0x9e3779b9)}';
        final rank = ranks[base] ?? 0;
        ranks[base] = rank + 1;
        id = rank == 0 ? base : '$base#$rank';
      }
      event = event.withIdentity(id, sourceId);
    }
    if (!seen.add(event.id)) {
      problems.add(tag(Problem(ProblemCode.duplicateId, Severity.error, '$path.id', event.id)));
      rejected++;
      continue;
    }
    items.add(NormalizedEvent(event));
  }
  return (items: items, report: NormalizationReport(items.length, rejected, problems));
}

String _startText(CalEvent e) => switch (e) {
  TimedEvent(:final start) => '$start',
  AllDayEvent(:final start) => '$start',
};

String _endText(CalEvent e) => switch (e) {
  TimedEvent(:final end) => '$end',
  AllDayEvent(:final end) => '$end',
};
