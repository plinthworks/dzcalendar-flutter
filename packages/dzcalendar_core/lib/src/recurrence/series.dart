import '../event/parse_temporal.dart';
import '../event/problem.dart';
import '../event/types.dart';
import '../intervals.dart';
import '../rrule/edit.dart';
import '../rrule/expand.dart';
import '../rrule/rule.dart';
import '../time/duration.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/zoned.dart';

/// Where a series was cut from by "this and following", and at which key.
final class SplitFrom {
  const SplitFrom(this.seriesId, this.at);
  final SeriesId seriesId;
  final RecurrenceKey at;
  @override
  bool operator ==(Object other) => other is SplitFrom && other.seriesId == seriesId && other.at == at;
  @override
  int get hashCode => Object.hash(seriesId, at);
}

const Object _keep = _Keep();

final class _Keep {
  const _Keep();
}

T _or<T>(Object? given, T current) => identical(given, _keep) ? current : given as T;

/// A recurring event: its first occurrence ([base]: title, colours, zone,
/// length — everything but which day), the rule set that repeats it, and the
/// occurrences replaced by events of their own ([overrides]).
final class Series {
  Series({
    required this.id,
    required this.base,
    required this.set,
    this.revision = 0,
    Map<RecurrenceKey, EventId> overrides = const {},
    this.sourceId,
    this.splitFrom,
  }) : overrides = Map.unmodifiable(overrides);

  final SeriesId id;

  /// As for events: the store version that wrote it.
  final int revision;

  /// The first occurrence as an event: its id is the series id; start and end give the length.
  final CalEvent base;
  final RRuleSet set;
  final Map<RecurrenceKey, EventId> overrides;
  final String? sourceId;
  final SplitFrom? splitFrom;

  bool get allDay => base.allDay;

  /// The first start, as the series writes it: a [ZonedDateTime] or a [PlainDate].
  Start get start => switch (base) {
    TimedEvent(:final start) => start,
    AllDayEvent(:final start) => start,
  };

  Series copyWith({
    SeriesId? id,
    int? revision,
    CalEvent? base,
    RRuleSet? set,
    Map<RecurrenceKey, EventId>? overrides,
    Object? sourceId = _keep,
    Object? splitFrom = _keep,
  }) => Series(
    id: id ?? this.id,
    revision: revision ?? this.revision,
    base: base ?? this.base,
    set: set ?? this.set,
    overrides: overrides ?? this.overrides,
    sourceId: _or(sourceId, this.sourceId),
    splitFrom: _or(splitFrom, this.splitFrom),
  );
}

/// The length every occurrence takes: whole days on the wall clock, the rest
/// in elapsed time — RFC 5545's nominal DURATION, so a 3-day timed
/// occurrence still ends at its wall time after a clock change.
IsoDuration occurrenceLength(CalEvent base) => switch (base) {
  AllDayEvent(:final start, :final end) => IsoDuration(days: start.daysUntil(end)),
  TimedEvent(:final start, :final end) => start.untilInDays(end),
};

/// An occurrence's key: its original start in full.
RecurrenceKey keyOf(Start start) => '$start';

/// Instance keys are `id`, or `seriesId@key` for an occurrence; ids are
/// escaped so neither `@` nor `|` can collide.
String escapeId(String id) => id.replaceAll('%', '%25').replaceAll('|', '%7C').replaceAll('@', '%40');
String occurrenceKey(SeriesId seriesId, RecurrenceKey key) => '${escapeId(seriesId)}@$key';
String _unescapeId(String id) => id.replaceAll('%40', '@').replaceAll('%7C', '|').replaceAll('%25', '%');

/// The inverse of [escapeId] / [occurrenceKey]: an event, or an occurrence of a series.
({EventId? eventId, SeriesId? seriesId, RecurrenceKey? key}) parseInstanceKey(String key) {
  final at = key.indexOf('@');
  return at == -1
      ? (eventId: _unescapeId(key), seriesId: null, key: null)
      : (eventId: null, seriesId: _unescapeId(key.substring(0, at)), key: key.substring(at + 1));
}

/// Keyed by the base event, not the series: an override or an EXDATE makes a
/// new series object around the same base, and its occurrences stay the same
/// objects — nothing on screen redraws for them.
final _cache = Expando<Map<RecurrenceKey, CalEvent>>('occurrences');

/// Occurrences kept per series: years of browsing an endless one must not grow memory without end.
const _cacheCap = 8000;

/// The occurrence starting at [start] as an event — the same object for the
/// same series base and key.
CalEvent materialize(Series series, Start start) {
  final byKey = _cache[series.base] ??= {};
  final key = keyOf(start);
  final hit = byKey[key];
  if (hit != null) return hit;
  // Forget the older half (a Map keeps insertion order): what is on screen stays the same object.
  if (byKey.length >= _cacheCap) {
    for (final k in byKey.keys.take(_cacheCap ~/ 2).toList()) {
      byKey.remove(k);
    }
  }
  final len = occurrenceLength(series.base);
  final id = occurrenceKey(series.id, key);
  final ref = EventRef(series.id, key);
  final CalEvent ev = switch (series.base) {
    AllDayEvent b => b.copyWith(
      id: id,
      start: start as PlainDate,
      end: start.addDays(len.days < 1 ? 1 : len.days),
      ref: ref,
    ),
    // The end keeps the base's end zone: a Paris → Tokyo flight lands in Tokyo every time.
    TimedEvent b => b.copyWith(
      id: id,
      start: start as ZonedDateTime,
      end: start.add(len).withTimeZone(b.end.zone),
      ref: ref,
    ),
  };
  return byKey[key] = ev;
}

/// True when two sets repeat with the same rules, exceptions and additions.
bool setEquals(RRuleSet a, RRuleSet b) {
  if (identical(a, b)) return true;
  String rules(RRuleSet s) => s.rules.map(serializeRRule).join('\n');
  String dates(List<Object> xs) => xs.map((x) => '$x').join(',');
  return rules(a) == rules(b) && dates(a.exdates) == dates(b.exdates) && dates(a.rdates) == dates(b.rdates);
}

/// True when two series repeat the same event the same way (revision aside).
bool seriesEquals(Series a, Series b) {
  if (identical(a, b)) return true;
  if (a.id != b.id || a.sourceId != b.sourceId) return false;
  if (!eventEquals(a.base, b.base) || !setEquals(a.set, b.set) || a.splitFrom != b.splitFrom) return false;
  if (a.overrides.length != b.overrides.length) return false;
  for (final MapEntry(:key, :value) in a.overrides.entries) {
    if (b.overrides[key] != value) return false;
  }
  return true;
}

/// What a series is expanded through: instants for a timed one, dates for an all-day one.
abstract interface class SeriesWindow {
  Instant get start;
  Instant get end;
  PlainDate get startDate;

  /// Exclusive.
  PlainDate get endDate;
}

/// Occurrences a series may show in one window before it says `too-many-occurrences`.
const defaultOccurrenceLimit = 2000;

/// Where an endless series ends in an index.
const forever = 9007199254740991;

/// The occurrences of a series that meet the window, as events — one that
/// began before the window and runs into it included. Overrides are not
/// skipped here: that is the caller's (the store knows them).
({List<CalEvent> occurrences, List<Problem> problems}) expandSeries(
  Series sr,
  SeriesWindow w, {
  int limit = defaultOccurrenceLimit,
}) {
  final len = occurrenceLength(sr.base);
  final List<Start> starts;
  final List<RRuleProblem> codes;
  switch (sr.base) {
    case AllDayEvent(:final start):
      final days = len.days < 1 ? 1 : len.days;
      final r = expandDates(start, sr.set, w.startDate.addDays(-(days - 1)), w.endDate, limit);
      starts = r.starts;
      codes = r.problems;
    case TimedEvent(:final start):
      // Widened back by the length — and by an hour per wall day in it, which
      // a 25-hour day adds — so an occurrence that began before is found.
      final back = start.add(len).epochMilliseconds - start.epochMilliseconds + (len.days + 1) * 3600000;
      final from = w.start.addMs(-(back > 0 ? back : 0));
      final r = expandZoned(start, sr.set, from, w.end, limit);
      starts = r.starts;
      codes = r.problems;
  }
  final occurrences = <CalEvent>[
    for (final x in starts)
      if (materialize(sr, x) case final ev when _meets(ev, w)) ev,
  ];
  final problems = [
    for (final p in codes) Problem(ProblemCode.tooManyOccurrences, Severity.warning, 'series:${sr.id}', p.detail),
  ];
  return (occurrences: occurrences, problems: problems);
}

bool _meets(CalEvent ev, SeriesWindow w) => switch (ev) {
  AllDayEvent(:final start, :final end) => start.isBefore(w.endDate) && end.isAfter(w.startDate),
  TimedEvent(:final start, :final end) =>
    start.epochMilliseconds < w.end.epochMilliseconds &&
        (end.epochMilliseconds > start.epochMilliseconds ? end.epochMilliseconds : start.epochMilliseconds + 1) >
            w.start.epochMilliseconds,
};

/// Where a series sits in an index: its first start (an RDATE may come
/// first) to its last end, or [forever]. Epoch days for an all-day series.
MsSpan seriesSpan(Series sr) {
  final len = occurrenceLength(sr.base);
  switch (sr.base) {
    case AllDayEvent(:final start):
      final first = firstStartDate(start, sr.set);
      final last = lastStartDate(start, sr.set);
      return MsSpan(first.epochDay, last == null ? forever : last.epochDay + (len.days < 1 ? 1 : len.days));
    case TimedEvent(:final start):
      final s = firstStartZoned(start, sr.set).epochMilliseconds;
      final last = lastStartZoned(start, sr.set);
      if (last == null) return MsSpan(s, forever);
      final end = last.add(len).epochMilliseconds;
      return MsSpan(s, end > s ? end : s + 1);
  }
}

/// Where the occurrence a key (a String), an EXDATE or a date names sits, in
/// the index's units. A date on a timed series covers that whole day.
MsSpan occurrenceSpan(Series sr, Object at) {
  final len = occurrenceLength(sr.base);
  switch (sr.base) {
    case AllDayEvent():
      final d = switch (at) {
        String s => PlainDate.parse(s),
        ExDay(:final date) => date,
        ExInstant(at: final i) => i.inZone('UTC').date,
        PlainDate d => d,
        _ => throw ArgumentError.value(at, 'at'),
      };
      return MsSpan(d.epochDay, d.epochDay + (len.days < 1 ? 1 : len.days));
    case TimedEvent(start: final base):
      final zone = base.zone;
      final day = switch (at) {
        ExDay(:final date) => date,
        PlainDate d => d,
        _ => null,
      };
      if (day != null) {
        final s = ZonedDateTime(day.startOfDayIn(zone), zone);
        return MsSpan(s.epochMilliseconds, s.add(IsoDuration(days: 1)).add(len).epochMilliseconds);
      }
      final start = switch (at) {
        String s => parseZonedDateTime(s) ?? (throw ArgumentError.value(at, 'at')),
        ExInstant(at: final i) => i.inZone(zone),
        Instant i => i.inZone(zone),
        _ => throw ArgumentError.value(at, 'at'),
      };
      final s = start.epochMilliseconds;
      final e = start.add(len).epochMilliseconds;
      return MsSpan(s, e > s ? e : s + 1);
  }
}
