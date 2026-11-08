import '../event/normalize.dart';
import '../event/problem.dart';
import '../event/types.dart';
import '../time/duration.dart';
import '../zone/zoned.dart';
import 'types.dart';

/// How long an event lasts: elapsed time if timed, calendar days if all-day.
IsoDuration lengthOf(CalEvent e) => switch (e) {
  AllDayEvent(:final start, :final end) => IsoDuration(days: start.daysUntil(end)),
  TimedEvent(:final start, :final end) => IsoDuration(milliseconds: end.epochMilliseconds - start.epochMilliseconds),
};

/// An [EventInput] being put together: every field settable, and cleared.
final class _Draft {
  String? id;
  String? groupId;
  String? title;
  Object? start;
  Object? end;
  Object? duration;
  bool? allDay;
  String? timeZone;
  String? resourceId;
  List<String>? resourceIds;
  EventDisplay? display;
  EventStatus? status;
  bool? busy;
  bool? editable;
  bool? startEditable;
  bool? durationEditable;
  bool? resourceEditable;
  List<String>? classNames;
  String? tone;
  String? url;
  Map<String, Object?>? extendedProps;
  bool? ongoing;

  EventInput build() => EventInput(
    id: id,
    groupId: groupId,
    title: title,
    start: start,
    end: end,
    duration: duration,
    allDay: allDay,
    timeZone: timeZone,
    resourceId: resourceId,
    resourceIds: resourceIds,
    display: display,
    status: status,
    busy: busy,
    editable: editable,
    startEditable: startEditable,
    durationEditable: durationEditable,
    resourceEditable: resourceEditable,
    classNames: classNames,
    tone: tone,
    url: url,
    extendedProps: extendedProps,
    ongoing: ongoing,
  );
}

/// A stored event written back as input, so a patch can be laid over it and
/// normalized again. Every field an input can express; a round trip changes
/// nothing.
_Draft _toDraft(CalEvent e) {
  final d = _Draft()
    ..id = e.id
    ..groupId = e.groupId
    ..title = e.title
    ..allDay = e.allDay
    ..resourceIds = e.resourceIds
    ..display = e.display
    ..status = e.status
    ..busy = e.busy
    ..classNames = e.classNames
    ..tone = e.tone
    ..url = e.url
    ..extendedProps = e.props;
  switch (e) {
    case AllDayEvent(:final start, :final end):
      d
        ..start = start
        ..end = end;
    case TimedEvent(:final start, :final end, :final ongoing, :final expectedEnd):
      d.start = start;
      // Still running: its end follows now — what it says is the end expected, if any.
      d.end = ongoing ? expectedEnd : end;
      if (ongoing) d.ongoing = true;
  }
  // As written: a `true` only where the event said it, a `false` always.
  final p = e.perms;
  if (p.ownStart || !p.start) d.startEditable = p.start;
  if (p.ownDuration || !p.duration) d.durationEditable = p.duration;
  if (!p.resource) d.resourceEditable = false;
  return d;
}

/// A stored event as input (for `event.repeat`, and round trips).
EventInput toInput(CalEvent e) => _toDraft(e).build();

/// The stored event as input, made ready for [p] to be laid over it: every
/// field the patch derives from (permissions from `editable`, `busy` from
/// `status`, the moments from `allDay` or `timeZone`) cleared or converted,
/// so an update means what the same fields mean in a create.
_Draft _patchedBase(CalEvent before, EventPatch p) {
  final base = _toDraft(before);
  if (p.editable != null) {
    base
      ..startEditable = null
      ..durationEditable = null
      ..resourceEditable = null;
  }
  // `busy` follows `status` unless it was set against it on purpose.
  if (p.status != null && p.busy == null && before.busy == (before.status != EventStatus.cancelled)) base.busy = null;
  if (p.hasResources) base.resourceIds = null;

  final toAllDay = p.allDay == true && !before.allDay;
  final toTimed = p.allDay == false && before.allDay;
  switch (before) {
    case TimedEvent(:final start, :final end) when toAllDay:
      // The days the event touches: an end at 01:00 still covers that day.
      final startDate = start.date;
      final endWall = end.withTimeZone(start.zone).plainDateTime;
      var endDate = endWall.date;
      if (endWall.time.msOfDay != 0 || !endDate.isAfter(startDate)) endDate = endDate.addDays(1);
      base
        ..start = startDate
        ..end = endDate;
    case AllDayEvent() when toTimed:
      // Midnight of its first day, for the default timed length.
      base.end = null;
    case TimedEvent(:final start, :final end) when p.hasTimeZone && !p.hasStart && !p.hasEnd:
      // Same clock times, another place.
      base
        ..start = start.plainDateTime
        ..end = end.withTimeZone(start.zone).plainDateTime;
    default:
      break;
  }

  // A new start (or duration) without a new end keeps the event's length
  // rather than its old end — elapsed for timed, whole days for all-day:
  // never an edit turned into end-before-start.
  if ((p.hasStart || p.hasDuration) && !p.hasEnd && !toTimed && !toAllDay) {
    base.end = null;
    // A running event moved keeps the length it was expected to have (none: still from its start to now).
    final IsoDuration? expected = switch (before) {
      TimedEvent(ongoing: true, :final start, :final expectedEnd) =>
        expectedEnd == null ? null : IsoDuration(milliseconds: expectedEnd.epochMilliseconds - start.epochMilliseconds),
      _ => lengthOf(before),
    };
    final length = p.duration ?? expected;
    if (length != null) base.duration = length;
  }
  // A wall time written without a zone is read in the event's own zone —
  // unless that zone was itself a guess, which keeps following the calendar.
  if (before case TimedEvent(:final start, zoneGuessed: false) when !p.hasTimeZone && !toAllDay) {
    base.timeZone = start.zone;
  }
  return base;
}

/// [p] laid over a draft: a field given wins, a field cleared goes.
void _overlay(_Draft d, EventPatch p) {
  if (p.title != null) d.title = p.title;
  if (p.start != null) d.start = p.start;
  if (p.end != null) d.end = p.end;
  if (p.duration != null) d.duration = p.duration;
  if (p.allDay != null) d.allDay = p.allDay;
  if (p.timeZone != null) d.timeZone = p.timeZone;
  if (p.resourceId != null) d.resourceId = p.resourceId;
  if (p.resourceIds != null) d.resourceIds = p.resourceIds;
  if (p.display != null) d.display = p.display;
  if (p.status != null) d.status = p.status;
  if (p.busy != null) d.busy = p.busy;
  if (p.editable != null) d.editable = p.editable;
  if (p.startEditable != null) d.startEditable = p.startEditable;
  if (p.durationEditable != null) d.durationEditable = p.durationEditable;
  if (p.resourceEditable != null) d.resourceEditable = p.resourceEditable;
  if (p.classNames != null) d.classNames = p.classNames;
  if (p.tone != null) d.tone = p.tone;
  if (p.url != null) d.url = p.url;
  if (p.groupId != null) d.groupId = p.groupId;
  if (p.extendedProps != null) d.extendedProps = p.extendedProps;
  if (p.ongoing != null) d.ongoing = p.ongoing;
  for (final f in p.clear) {
    switch (f) {
      case EventField.end:
        d.end = null;
      case EventField.groupId:
        d.groupId = null;
      case EventField.tone:
        d.tone = null;
      case EventField.url:
        d.url = null;
    }
  }
}

/// [before] with [p] laid over it, normalized as a create would be: the
/// same object when nothing changes, null (with the problems) when the
/// result is not an event. Its source and its place in a series survive.
CalEvent? patchEvent(CalEvent before, EventPatch p, NormalizeContext ctx, String path, List<Problem> problems) {
  final base = _patchedBase(before, p);
  // Finished without an end said: it ends now (where it was drawn up to, at the latest).
  if (before case TimedEvent(
    ongoing: true,
    :final start,
    :final end,
  ) when p.ongoing == false && !p.hasEnd && !p.hasDuration) {
    final now = ctx.now?.call();
    base.end = now != null && now.isAfter(start.instant) ? now.inZone(end.zone) : end;
  }
  _overlay(base, p);
  base.id = before.id;
  final r = normalizeEvent(base.build(), ctx, path);
  problems.addAll(r.problems);
  final value = r.value;
  if (value == null) return null;
  if (value is! NormalizedEvent) {
    // A rule is the series' business: an edit never turns an event into one.
    problems.add(Problem(ProblemCode.invalidRrule, Severity.error, '$path.patch', 'an update cannot add a rule'));
    return null;
  }
  var next = value.event;
  // Written back as a ZonedDateTime, a guessed zone reads as a named one.
  // Untouched moments keep the guess, so the event still follows the calendar.
  final movesTime = p.hasStart || p.hasEnd || p.hasTimeZone || p.hasAllDay;
  if (!movesTime && before is TimedEvent && next is TimedEvent && before.zoneGuessed) {
    next = next.copyWith(zoneGuessed: true);
  }
  if (before.sourceId != null) next = next.withIdentity(next.id, before.sourceId);
  if (before.ref != null) next = withRef(next, before.ref);
  return eventEquals(before, next) ? before : next;
}
