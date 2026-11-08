import '../commands/patch.dart';
import '../event/types.dart';
import '../recurrence/series.dart';
import '../rrule/rule.dart';
import 'store.dart';

EventInput _with(
  EventInput i, {
  String? id,
  Object? rrule,
  List<Object?>? exdate,
  List<Object?>? rdate,
  String? seriesId,
  Object? recurrenceId,
}) => EventInput(
  id: id ?? i.id,
  groupId: i.groupId,
  title: i.title,
  start: i.start,
  end: i.end,
  duration: i.duration,
  allDay: i.allDay,
  timeZone: i.timeZone,
  resourceId: i.resourceId,
  resourceIds: i.resourceIds,
  rrule: rrule ?? i.rrule,
  exdate: exdate ?? i.exdate,
  rdate: rdate ?? i.rdate,
  seriesId: seriesId ?? i.seriesId,
  recurrenceId: recurrenceId ?? i.recurrenceId,
  display: i.display,
  status: i.status,
  busy: i.busy,
  editable: i.editable,
  startEditable: i.startEditable,
  durationEditable: i.durationEditable,
  resourceEditable: i.resourceEditable,
  classNames: i.classNames,
  tone: i.tone,
  url: i.url,
  extendedProps: i.extendedProps,
  ongoing: i.ongoing,
);

/// A series written back as input: its first occurrence, its rules,
/// exceptions and additions.
EventInput seriesInput(Series s) {
  final rules = s.set.rules;
  return _with(
    toInput(s.base),
    id: s.id,
    rrule: rules.length == 1 ? serializeRRule(rules.first) : [for (final r in rules) serializeRRule(r)],
    exdate: s.set.exdates.isEmpty ? null : [for (final x in s.set.exdates) '$x'],
    rdate: s.set.rdates.isEmpty
        ? null
        : [
            for (final r in s.set.rdates)
              switch (r) {
                RZoned(:final at) => at,
                RDay(:final date) => date,
              },
          ],
  );
}

/// An event written back as input; an override says which occurrence it replaces.
EventInput eventInput(CalEvent e) {
  final input = toInput(e);
  final ref = e.ref;
  return ref == null ? input : _with(input, seriesId: ref.seriesId, recurrenceId: ref.key);
}

/// Everything [snap] holds (or what [keep] keeps) as inputs: series first,
/// then events, each in id order. Normalized again, it gives the same
/// store — what an export (iCal, JSON) starts from:
/// `serializeICal(exportInputs(store.snapshot))`.
List<EventInput> exportInputs(StoreSnapshot snap, {bool Function(Object eventOrSeries)? keep}) => [
  for (final s in snap.allSeries)
    if (keep == null || keep(s)) seriesInput(s),
  for (final e in snap.allEvents)
    if (keep == null || keep(e)) eventInput(e),
];
