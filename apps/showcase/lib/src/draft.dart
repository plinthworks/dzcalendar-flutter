import 'package:dzcalendar/dzcalendar.dart';
import 'package:dzcalendar_core/dzcalendar_core.dart' show Batch, ChangeRule, RepeatEvent;

import 'book.dart';

/// What the inspector edits: an event as a person sees it, in the
/// calendar's zone. An all-day event's [endDate] is its last day (the
/// store's end is the day after).
class Draft {
  Draft({
    required this.title,
    required this.place,
    required this.notes,
    required this.allDay,
    required this.startDate,
    required this.startTime,
    required this.endDate,
    required this.endTime,
    required this.calendarId,
    required this.repeat,
  });

  String title;
  String place;
  String notes;
  bool allDay;
  PlainDate startDate;
  PlainTime startTime;
  PlainDate endDate;
  PlainTime endTime;
  String calendarId;

  /// Null: a rule the presets cannot say, kept as it is.
  RepeatPreset? repeat;

  Draft copy() => Draft(
    title: title,
    place: place,
    notes: notes,
    allDay: allDay,
    startDate: startDate,
    startTime: startTime,
    endDate: endDate,
    endTime: endTime,
    calendarId: calendarId,
    repeat: repeat,
  );

  /// A new event from [start] to [end] (a slot, a selection), in [calendar].
  factory Draft.fresh({
    required String calendarId,
    required String title,
    required ZonedDateTime start,
    required ZonedDateTime end,
  }) => Draft(
    title: title,
    place: '',
    notes: '',
    allDay: false,
    startDate: start.date,
    startTime: start.time,
    endDate: end.date,
    endTime: end.time,
    calendarId: calendarId,
    repeat: RepeatPreset.never,
  );

  /// A new all-day event on the days [first] to [last].
  factory Draft.freshDays({
    required String calendarId,
    required String title,
    required PlainDate first,
    required PlainDate last,
    required PlainTime hour,
  }) => Draft(
    title: title,
    place: '',
    notes: '',
    allDay: true,
    startDate: first,
    startTime: hour,
    endDate: last,
    endTime: PlainTime.fromMsOfDay((hour.msOfDay + 3600000) % 86400000),
    calendarId: calendarId,
    repeat: RepeatPreset.never,
  );

  /// [instance] as the inspector shows it, its times in [zone].
  factory Draft.of(EventInstance instance, CalendarBook book, ZoneId zone) {
    final e = instance.event;
    final ref = e.ref;
    final series = ref == null ? null : book.controller.kernel.store.snapshot.getSeries(ref.seriesId);
    final repeat = ref == null ? RepeatPreset.never : CalendarBook.presetOf(series);
    final calendarId = book.calendarOf(e)?.id ?? book.writable.first.id;
    String text(String key) => '${e.props[key] ?? ''}';
    return switch (e) {
      TimedEvent(:final start, :final end) => () {
        final s = ZonedDateTime(start.instant, zone);
        final t = ZonedDateTime(end.instant, zone);
        return Draft(
          title: e.title,
          place: text(placeKey),
          notes: text(notesKey),
          allDay: false,
          startDate: s.date,
          startTime: s.time,
          endDate: t.date,
          endTime: t.time,
          calendarId: calendarId,
          repeat: repeat,
        );
      }(),
      AllDayEvent(:final start, :final end) => Draft(
        title: e.title,
        place: text(placeKey),
        notes: text(notesKey),
        allDay: true,
        startDate: start,
        startTime: PlainTime(9),
        endDate: end.addDays(-1),
        endTime: PlainTime(10),
        calendarId: calendarId,
        repeat: repeat,
      ),
    };
  }

  /// Whether the end comes after the start (an all-day event: on or after).
  bool get inOrder => allDay
      ? !endDate.isBefore(startDate)
      : PlainDateTime(endDate, endTime).compareTo(PlainDateTime(startDate, startTime)) > 0;

  /// The start and end as the store takes them: dates (the end exclusive)
  /// or moments in [zone], written in [eventZone] when the event has one.
  (Object, Object) bounds(ZoneId zone, {ZoneId? eventZone}) {
    if (allDay) return (startDate, endDate.addDays(1));
    ZonedDateTime at(PlainDate d, PlainTime t) {
      final z = ZonedDateTime.fromWall(PlainDateTime(d, t), zone)!;
      return eventZone == null || eventZone == zone ? z : ZonedDateTime(z.instant, eventZone);
    }

    return (at(startDate, startTime), at(endDate, endTime));
  }

  Map<String, Object?> props(Map<String, Object?> base) => {
    ...base,
    placeKey: place.trim().isEmpty ? null : place.trim(),
    notesKey: notes.trim().isEmpty ? null : notes.trim(),
    calendarKey: calendarId,
  }..removeWhere((k, v) => v == null);
}

/// A new event from [d]: one validated command (one step of the history).
Command createCommand(Draft d, CalendarBook book) {
  final (start, end) = d.bounds(book.controller.state.timeZone);
  final calendar = book.byId(d.calendarId)!;
  return CreateEvent(
    tagged(
      EventInput(
        title: d.title.trim(),
        start: start,
        end: end,
        allDay: d.allDay,
        rrule: d.repeat?.rule,
        extendedProps: d.props(const {}),
      ),
      calendar,
    ),
  );
}

/// Whether saving [after] over [before] asks how far it reaches: an
/// occurrence whose fields changed, but not its repeat nor its calendar (a
/// new rule, another calendar: the whole series') nor its kind (timed ↔
/// all-day is one occurrence's).
bool asksScope(EventInstance instance, Draft before, Draft after) =>
    instance.event.ref != null &&
    _fieldsChanged(before, after) &&
    before.repeat == after.repeat &&
    before.calendarId == after.calendarId &&
    before.allDay == after.allDay;

bool _fieldsChanged(Draft a, Draft b) =>
    a.title != b.title ||
    a.place != b.place ||
    a.notes != b.notes ||
    a.calendarId != b.calendarId ||
    a.allDay != b.allDay ||
    a.startDate != b.startDate ||
    a.endDate != b.endDate ||
    (!b.allDay && (a.startTime != b.startTime || a.endTime != b.endTime));

/// The commands that turn [before] into [after] on [instance], as one
/// batch, or null when nothing changed. [scope]: how far an occurrence's
/// change reaches (see [asksScope]).
Command? editCommand(EventInstance instance, Draft before, Draft after, CalendarBook book, {EditScope? scope}) {
  final e = instance.event;
  final ref = e.ref;
  final id = ref?.seriesId ?? e.id;
  final key = ref?.key;
  final zone = book.controller.state.timeZone;
  final commands = <Command>[];
  final repeatChanged = after.repeat != null && after.repeat != before.repeat;

  if (_fieldsChanged(before, after)) {
    final timesChanged =
        before.allDay != after.allDay ||
        before.startDate != after.startDate ||
        before.endDate != after.endDate ||
        (!after.allDay && (before.startTime != after.startTime || before.endTime != after.endTime));
    final eventZone = switch (e) {
      TimedEvent(:final start) => start.zone,
      _ => null,
    };
    final (start, end) = after.bounds(zone, eventZone: eventZone);
    final calendar = book.byId(after.calendarId);
    final patch = EventPatch(
      title: after.title.trim() != before.title.trim() ? after.title.trim() : null,
      allDay: before.allDay != after.allDay ? after.allDay : null,
      start: timesChanged ? start : null,
      end: timesChanged ? end : null,
      extendedProps: after.place != before.place || after.notes != before.notes || after.calendarId != before.calendarId
          ? after.props(e.props)
          : null,
      editable: calendar != null && calendar.readOnly ? false : null,
    );
    final reach = ref == null
        ? null
        : before.allDay != after.allDay
        ? EditScope.single
        : repeatChanged || before.calendarId != after.calendarId
        ? EditScope.all
        : scope ?? EditScope.single;
    commands.add(UpdateEvent(id, patch, scope: reach, key: reach == null ? null : key));
  }

  if (repeatChanged) {
    final rule = after.repeat!.rule;
    if (ref != null) {
      commands.add(ChangeRule(ref.seriesId, rule));
    } else if (rule != null) {
      commands.add(RepeatEvent(e.id, rule));
    }
  }

  if (commands.isEmpty) return null;
  return commands.length == 1 ? commands.single : Batch(commands, label: 'event.edit');
}

/// Deletes [instance]: an occurrence as far as [scope] says.
Command deleteCommand(EventInstance instance, {EditScope scope = EditScope.single}) {
  final e = instance.event;
  final ref = e.ref;
  return ref == null ? DeleteEvent(e.id) : DeleteEvent(ref.seriesId, scope: scope, key: ref.key);
}
