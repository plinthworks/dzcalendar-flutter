import '../time/duration.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'problem.dart';

typedef EventId = String;
typedef ResourceId = String;
typedef SeriesId = String;

/// An occurrence's identity within its series: its *original* start, written
/// in full — `2026-10-25T02:30:00+02:00[Europe/Paris]`, or a date for an
/// all-day series. The offset is part of it, so the two 02:30s of a
/// fall-back night are two occurrences, never one.
typedef RecurrenceKey = String;

/// How an event is drawn. `marker`: a moment without length — an alert, a
/// deployment — a line where it happened and a flag with its title.
enum EventDisplay {
  auto('auto'),
  block('block'),
  listItem('list-item'),
  background('background'),
  inverseBackground('inverse-background'),
  marker('marker'),
  none('none');

  const EventDisplay(this.code);
  final String code;

  static EventDisplay? fromCode(String code) => values.where((d) => d.code == code).firstOrNull;
}

enum EventStatus {
  confirmed,
  tentative,
  cancelled;

  static EventStatus? fromCode(String code) => values.where((d) => d.name == code).firstOrNull;
}

/// An event as an application hands it in: loose, mostly optional, strings
/// welcome. `normalizeEvent` turns it into a [CalEvent] or says why it
/// cannot (owner, 2026-11-08: a typed class, and [EventInput.fromJson] for an
/// API's data).
///
/// A moment (`start`, `end`, …) is a [ZonedDateTime], [Instant], [PlainDateTime],
/// [PlainDate] or an ISO 8601 string — never a `DateTime`, which names no
/// zone (`date-object-rejected`).
final class EventInput {
  EventInput({
    this.id,
    this.groupId,
    this.title,
    this.start,
    this.end,
    this.duration,
    this.allDay,
    this.timeZone,
    this.resourceId,
    this.resourceIds,
    this.rrule,
    this.exdate,
    this.rdate,
    this.seriesId,
    this.recurrenceId,
    this.display,
    this.status,
    this.busy,
    this.editable,
    this.startEditable,
    this.durationEditable,
    this.resourceEditable,
    this.classNames,
    this.tone,
    this.url,
    this.extendedProps,
    this.ongoing,
  }) : _readProblems = const [];

  EventInput._json(
    this._readProblems, {
    this.id,
    this.groupId,
    this.title,
    this.start,
    this.end,
    this.duration,
    this.allDay,
    this.timeZone,
    this.resourceId,
    this.resourceIds,
    this.rrule,
    this.exdate,
    this.rdate,
    this.seriesId,
    this.recurrenceId,
    this.display,
    this.status,
    this.busy,
    this.editable,
    this.startEditable,
    this.durationEditable,
    this.resourceEditable,
    this.classNames,
    this.tone,
    this.url,
    this.extendedProps,
    this.ongoing,
  });

  /// From an API's JSON object, the TypeScript core's field names. Never
  /// throws: a field of the wrong type is left out and reported when the
  /// input is normalized; `null` means absent; unknown fields are ignored.
  ///
  /// Any map with string keys will do: a platform channel's or Firestore's
  /// `Map<Object?, Object?>` as well as decoded JSON.
  factory EventInput.fromJson(Map<Object?, Object?> json) {
    final problems = <(ProblemCode, String, String)>[];
    T? read<T>(String key, [ProblemCode code = ProblemCode.invalidEvent]) {
      final v = json[key];
      if (v == null || v is T) return v as T?;
      problems.add((code, key, 'expected ${_typeName<T>()}, got ${v.runtimeType}'));
      return null;
    }

    List<String>? strings(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is List && v.every((x) => x is String)) return v.cast<String>();
      problems.add((ProblemCode.invalidEvent, key, 'expected a list of strings'));
      return null;
    }

    List<Object?>? list(String key, ProblemCode code) {
      final v = json[key];
      if (v == null) return null;
      if (v is List) return List<Object?>.of(v);
      problems.add((code, key, 'expected a list'));
      return null;
    }

    EventDisplay? display;
    final d = read<String>('display');
    if (d != null) {
      display = EventDisplay.fromCode(d);
      if (display == null) problems.add((ProblemCode.invalidEvent, 'display', d));
    }
    EventStatus? status;
    final s = read<String>('status');
    if (s != null) {
      status = EventStatus.fromCode(s);
      if (status == null) problems.add((ProblemCode.invalidEvent, 'status', s));
    }
    final rrule = json['rrule'];
    if (rrule != null && rrule is! String && !(rrule is List && rrule.every((x) => x is String))) {
      problems.add((ProblemCode.invalidRrule, 'rrule', 'expected a rule string or a list of them'));
    }
    final rawProps = json['extendedProps'];
    final props = rawProps is Map && rawProps.keys.every((k) => k is String)
        ? Map<String, Object?>.from(rawProps)
        : null;
    if (rawProps != null && props == null) {
      problems.add((ProblemCode.invalidEvent, 'extendedProps', 'expected an object'));
    }

    return EventInput._json(
      problems,
      id: read<String>('id', ProblemCode.invalidId),
      groupId: read<String>('groupId'),
      title: read<String>('title'),
      start: json['start'],
      end: json['end'],
      duration: json['duration'],
      allDay: read<bool>('allDay'),
      timeZone: read<String>('timeZone', ProblemCode.unknownZone),
      resourceId: read<String>('resourceId'),
      resourceIds: strings('resourceIds'),
      rrule: rrule is String ? rrule : (rrule is List ? rrule.whereType<String>().toList() : null),
      exdate: list('exdate', ProblemCode.invalidExdate),
      rdate: list('rdate', ProblemCode.invalidRdate),
      seriesId: read<String>('seriesId'),
      recurrenceId: json['recurrenceId'],
      display: display,
      status: status,
      busy: read<bool>('busy'),
      editable: read<bool>('editable'),
      startEditable: read<bool>('startEditable'),
      durationEditable: read<bool>('durationEditable'),
      resourceEditable: read<bool>('resourceEditable'),
      classNames: strings('classNames'),
      tone: read<String>('tone'),
      url: read<String>('url'),
      extendedProps: props,
      ongoing: read<bool>('ongoing'),
    );
  }

  final String? id;
  final String? groupId;
  final String? title;
  final Object? start;
  final Object? end;

  /// Used when [end] is absent: an [IsoDuration], an ISO string ("PT1H"), or a
  /// map (`{"hours": 1}`). Days are wall days, hours elapsed hours.
  final Object? duration;
  final bool? allDay;

  /// The event's own zone, for a start that does not carry one.
  final ZoneId? timeZone;
  final ResourceId? resourceId;
  final List<ResourceId>? resourceIds;

  /// An RFC 5545 rule (`FREQ=WEEKLY;BYDAY=MO`) or a list of them: the event
  /// becomes a series (19c).
  final Object? rrule;
  final List<Object?>? exdate;
  final List<Object?>? rdate;
  final String? seriesId;
  final Object? recurrenceId;
  final EventDisplay? display;
  final EventStatus? status;

  /// Feeds the slot engine: a busy event blocks availability. Default: not cancelled.
  final bool? busy;
  final bool? editable;
  final bool? startEditable;
  final bool? durationEditable;
  final bool? resourceEditable;
  final List<String>? classNames;

  /// A tone, not a colour: a theme's name (`blue`, `green`…).
  final String? tone;
  final String? url;
  final Map<String, Object?>? extendedProps;

  /// Still running, its end not known: drawn from its start to now. An `end`
  /// or a `duration` given is the length expected. A timed event, not a series.
  final bool? ongoing;

  /// The web's JSON shape, the fields given only: moments, lengths and
  /// rules as ISO / RFC 5545 text (a [ZonedDateTime] as
  /// `2026-10-21T08:00:00+02:00[Europe/Paris]`, an [IsoDuration] as `PT1H`).
  /// What [EventInput.fromJson] reads back.
  Map<String, Object?> toJson() => {
    'id': ?id,
    'groupId': ?groupId,
    'title': ?title,
    'start': ?_jsonOf(start),
    'end': ?_jsonOf(end),
    'duration': ?_jsonOf(duration),
    'allDay': ?allDay,
    'timeZone': ?timeZone,
    'resourceId': ?resourceId,
    'resourceIds': ?_jsonOf(resourceIds),
    'rrule': ?_jsonOf(rrule),
    'exdate': ?_jsonOf(exdate),
    'rdate': ?_jsonOf(rdate),
    'seriesId': ?seriesId,
    'recurrenceId': ?_jsonOf(recurrenceId),
    'display': ?display?.code,
    'status': ?status?.name,
    'busy': ?busy,
    'editable': ?editable,
    'startEditable': ?startEditable,
    'durationEditable': ?durationEditable,
    'resourceEditable': ?resourceEditable,
    'classNames': ?_jsonOf(classNames),
    'tone': ?tone,
    'url': ?url,
    'extendedProps': ?_jsonOf(extendedProps),
    'ongoing': ?ongoing,
  };

  /// What [EventInput.fromJson] could not read: `(code, field, detail)`.
  final List<(ProblemCode, String, String)> _readProblems;
}

/// What [EventInput.fromJson] could not read, for `normalizeEvent`.
List<(ProblemCode, String, String)> readProblemsOf(EventInput input) => input._readProblems;

String _typeName<T>() => switch (T) {
  const (String) => 'a string',
  const (bool) => 'true or false',
  _ => '$T',
};

/// What may be changed. `ownStart`/`ownDuration`: what the event said `true`
/// to itself — it is then editable that way even in a calendar that is not.
final class EventPerms {
  const EventPerms({
    required this.start,
    required this.duration,
    required this.resource,
    this.ownStart = false,
    this.ownDuration = false,
  });

  final bool start;
  final bool duration;
  final bool resource;
  final bool ownStart;
  final bool ownDuration;

  @override
  bool operator ==(Object other) =>
      other is EventPerms &&
      other.start == start &&
      other.duration == duration &&
      other.resource == resource &&
      other.ownStart == ownStart &&
      other.ownDuration == ownDuration;

  @override
  int get hashCode => Object.hash(start, duration, resource, ownStart, ownDuration);
}

/// Which occurrence of which series an occurrence or an override stands for.
final class EventRef {
  const EventRef(this.seriesId, this.key);
  final SeriesId seriesId;
  final RecurrenceKey key;

  @override
  bool operator ==(Object other) => other is EventRef && other.seriesId == seriesId && other.key == key;

  @override
  int get hashCode => Object.hash(seriesId, key);

  @override
  String toString() => '$seriesId@$key';
}

/// Passed for a nullable field `copyWith` keeps: `null` clears the field.
const Object _keep = _Keep();

final class _Keep {
  const _Keep();
}

T _or<T>(Object? given, T current) => identical(given, _keep) ? current : given as T;

/// An event, checked: [TimedEvent] or [AllDayEvent]. Built by
/// `normalizeEvent` and the store; its lists and props are unmodifiable.
sealed class CalEvent {
  const CalEvent({
    required this.id,
    required this.title,
    required this.resourceIds,
    required this.display,
    required this.status,
    required this.busy,
    required this.perms,
    required this.classNames,
    required this.props,
    required this.revision,
    this.groupId,
    this.tone,
    this.url,
    this.sourceId,
    this.ref,
  });

  final EventId id;
  final String? groupId;
  final String title;
  final List<ResourceId> resourceIds;
  final EventDisplay display;
  final EventStatus status;
  final bool busy;
  final EventPerms perms;
  final List<String> classNames;
  final String? tone;
  final String? url;
  final Map<String, Object?> props;
  final String? sourceId;

  /// On an occurrence of a series, and on an override: which one it stands for.
  final EventRef? ref;

  /// +1 on every change, assigned by the store; 0 from normalization.
  final int revision;

  bool get allDay;

  /// The same event under another id and source (a source's derived id).
  CalEvent withIdentity(EventId id, String? sourceId);

  /// The same event at the store's [revision].
  CalEvent withRevision(int revision);

  /// The same event at another time of day — what a drag shows as it goes,
  /// and what [Placement] is checked on — from a timed event or an all-day
  /// one. A running event so moved is no longer running. Throws an
  /// [ArgumentError] when [end] is before [start] (the caller's arithmetic).
  TimedEvent movedToTime(ZonedDateTime start, ZonedDateTime end, {List<ResourceId>? resourceIds}) {
    if (end.instant.isBefore(start.instant)) throw ArgumentError.value(end, 'end', 'before the start');
    return TimedEvent(
      id: id,
      title: title,
      resourceIds: List.unmodifiable(resourceIds ?? this.resourceIds),
      display: display,
      status: status,
      busy: busy,
      perms: perms,
      classNames: classNames,
      props: props,
      revision: revision,
      start: start,
      end: end,
      zoneGuessed: switch (this) {
        TimedEvent(:final zoneGuessed) => zoneGuessed,
        AllDayEvent() => false,
      },
      groupId: groupId,
      tone: tone,
      url: url,
      sourceId: sourceId,
      ref: ref,
    );
  }

  /// The same event on other days ([end] exclusive), from a timed event or
  /// an all-day one. Throws an [ArgumentError] when [end] is before [start].
  AllDayEvent movedToDays(PlainDate start, PlainDate end, {List<ResourceId>? resourceIds}) {
    if (end.isBefore(start)) throw ArgumentError.value(end, 'end', 'before the start');
    return AllDayEvent(
      id: id,
      title: title,
      resourceIds: List.unmodifiable(resourceIds ?? this.resourceIds),
      display: display,
      status: status,
      busy: busy,
      perms: perms,
      classNames: classNames,
      props: props,
      revision: revision,
      start: start,
      end: end,
      groupId: groupId,
      tone: tone,
      url: url,
      sourceId: sourceId,
      ref: ref,
    );
  }
}

/// An event at a time of day. [start] and [end] may sit in different zones —
/// a flight leaves Paris and lands in Tokyo; the event's zone is its start's.
/// [end] is never before [start] as instants; equal is a milestone.
final class TimedEvent extends CalEvent {
  const TimedEvent({
    required super.id,
    required super.title,
    required super.resourceIds,
    required super.display,
    required super.status,
    required super.busy,
    required super.perms,
    required super.classNames,
    required super.props,
    required super.revision,
    required this.start,
    required this.end,
    required this.zoneGuessed,
    super.groupId,
    super.tone,
    super.url,
    super.sourceId,
    super.ref,
    this.ongoing = false,
    this.expectedEnd,
  });

  final ZonedDateTime start;
  final ZonedDateTime end;

  /// True when no zone was named and the display zone was assumed
  /// (`zone-defaulted`, `offset-only`), kept after a zone change.
  final bool zoneGuessed;

  /// Still running: [end] follows now, never before [expectedEnd].
  final bool ongoing;
  final ZonedDateTime? expectedEnd;

  @override
  bool get allDay => false;

  @override
  TimedEvent withIdentity(EventId id, String? sourceId) => copyWith(id: id, sourceId: sourceId);

  @override
  TimedEvent withRevision(int revision) => copyWith(revision: revision);

  /// Every field; a nullable one is cleared by passing `null`.
  TimedEvent copyWith({
    EventId? id,
    Object? groupId = _keep,
    String? title,
    List<ResourceId>? resourceIds,
    EventDisplay? display,
    EventStatus? status,
    bool? busy,
    EventPerms? perms,
    List<String>? classNames,
    Object? tone = _keep,
    Object? url = _keep,
    Map<String, Object?>? props,
    Object? sourceId = _keep,
    Object? ref = _keep,
    int? revision,
    ZonedDateTime? start,
    ZonedDateTime? end,
    bool? zoneGuessed,
    bool? ongoing,
    Object? expectedEnd = _keep,
  }) => TimedEvent(
    id: id ?? this.id,
    groupId: _or(groupId, this.groupId),
    title: title ?? this.title,
    resourceIds: resourceIds ?? this.resourceIds,
    display: display ?? this.display,
    status: status ?? this.status,
    busy: busy ?? this.busy,
    perms: perms ?? this.perms,
    classNames: classNames ?? this.classNames,
    tone: _or(tone, this.tone),
    url: _or(url, this.url),
    props: props ?? this.props,
    sourceId: _or(sourceId, this.sourceId),
    ref: _or(ref, this.ref),
    revision: revision ?? this.revision,
    start: start ?? this.start,
    end: end ?? this.end,
    zoneGuessed: zoneGuessed ?? this.zoneGuessed,
    ongoing: ongoing ?? this.ongoing,
    expectedEnd: _or(expectedEnd, this.expectedEnd),
  );
}

/// An event on whole dates, with no zone: the same days for every reader,
/// wherever they are. [end] is exclusive and after [start].
final class AllDayEvent extends CalEvent {
  const AllDayEvent({
    required super.id,
    required super.title,
    required super.resourceIds,
    required super.display,
    required super.status,
    required super.busy,
    required super.perms,
    required super.classNames,
    required super.props,
    required super.revision,
    required this.start,
    required this.end,
    super.groupId,
    super.tone,
    super.url,
    super.sourceId,
    super.ref,
  });

  final PlainDate start;
  final PlainDate end;

  @override
  bool get allDay => true;

  @override
  AllDayEvent withIdentity(EventId id, String? sourceId) => copyWith(id: id, sourceId: sourceId);

  @override
  AllDayEvent withRevision(int revision) => copyWith(revision: revision);

  /// Every field; a nullable one is cleared by passing `null`.
  AllDayEvent copyWith({
    EventId? id,
    Object? groupId = _keep,
    String? title,
    List<ResourceId>? resourceIds,
    EventDisplay? display,
    EventStatus? status,
    bool? busy,
    EventPerms? perms,
    List<String>? classNames,
    Object? tone = _keep,
    Object? url = _keep,
    Map<String, Object?>? props,
    Object? sourceId = _keep,
    Object? ref = _keep,
    int? revision,
    PlainDate? start,
    PlainDate? end,
  }) => AllDayEvent(
    id: id ?? this.id,
    groupId: _or(groupId, this.groupId),
    title: title ?? this.title,
    resourceIds: resourceIds ?? this.resourceIds,
    display: display ?? this.display,
    status: status ?? this.status,
    busy: busy ?? this.busy,
    perms: perms ?? this.perms,
    classNames: classNames ?? this.classNames,
    tone: _or(tone, this.tone),
    url: _or(url, this.url),
    props: props ?? this.props,
    sourceId: _or(sourceId, this.sourceId),
    ref: _or(ref, this.ref),
    revision: revision ?? this.revision,
    start: start ?? this.start,
    end: end ?? this.end,
  );
}

/// JSON-like values compared by structure: lists element by element, maps
/// key by key, anything else by `==`.
bool sameValue(Object? a, Object? b) {
  if (identical(a, b) || a == b) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameValue(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !sameValue(a[k], b[k])) return false;
    }
    return true;
  }
  return false;
}

bool _sameList(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// True when two events would draw the same — the store's rule: an event
/// equal to the one it replaces keeps the old object. [CalEvent.revision] is
/// ignored: it is the answer to this question, not part of it. Moments
/// compare as `ZonedDateTime ==` (instant and zone); `props` by structure.
/// Every field of [CalEvent] is here; `types_test.dart` fails when one is
/// added and forgotten.
bool eventEquals(CalEvent a, CalEvent b) {
  if (identical(a, b)) return true;
  switch ((a, b)) {
    case (AllDayEvent a, AllDayEvent b):
      if (a.start != b.start || a.end != b.end) return false;
    case (TimedEvent a, TimedEvent b):
      if (a.start != b.start ||
          a.end != b.end ||
          a.zoneGuessed != b.zoneGuessed ||
          a.ongoing != b.ongoing ||
          a.expectedEnd != b.expectedEnd) {
        return false;
      }
    default:
      return false;
  }
  return a.id == b.id &&
      a.title == b.title &&
      a.groupId == b.groupId &&
      a.display == b.display &&
      a.status == b.status &&
      a.busy == b.busy &&
      a.perms == b.perms &&
      a.tone == b.tone &&
      a.url == b.url &&
      a.sourceId == b.sourceId &&
      a.ref == b.ref &&
      _sameList(a.resourceIds, b.resourceIds) &&
      _sameList(a.classNames, b.classNames) &&
      sameValue(a.props, b.props);
}

/// A value as JSON: the time types as their ISO text, lists and maps
/// copied (the input's own are never handed out). Anything else is passed
/// as it is, for `jsonEncode` to refuse if it is no JSON — never turned
/// into text that would read back as something else.
Object? _jsonOf(Object? v) => switch (v) {
  ZonedDateTime() || Instant() || PlainDate() || PlainDateTime() || PlainTime() || IsoDuration() => '$v',
  final List<Object?> l => [for (final x in l) _jsonOf(x)],
  final Map<Object?, Object?> m => {for (final e in m.entries) '${e.key}': _jsonOf(e.value)},
  _ => v,
};
