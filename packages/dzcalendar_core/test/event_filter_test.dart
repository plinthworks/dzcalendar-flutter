// ModelOptions.eventFilter (owner's decision 48, phase 19g): events the
// application hides — calendars ticked off — without taking them out of the
// store. A divergence from the TypeScript core, to be proposed there.
// Expectations written by hand.

import 'dart:async';

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

Instant now() => Instant.parse('2026-10-21T08:00:00Z');
const paris = 'Europe/Paris';

Map<String, Object?> cal(String c) => {'cal': c};
bool workOnly(CalEvent e) => e.props['cal'] == 'work';

/// a and the series' changed Wednesday are work; b and the series are home.
List<EventInput> events() => [
  EventInput(id: 'a', title: 'A', start: '2026-10-21T09:00[Europe/Paris]', extendedProps: cal('work')),
  EventInput(id: 'b', title: 'B', start: '2026-10-21T10:00[Europe/Paris]', extendedProps: cal('home')),
  EventInput(id: 'd', title: 'D', start: '2026-10-22', allDay: true, extendedProps: cal('home')),
  EventInput(
    id: 's',
    title: 'S',
    start: '2026-10-19T12:00[Europe/Paris]',
    rrule: 'FREQ=DAILY;COUNT=5',
    extendedProps: cal('home'),
  ),
  EventInput(
    id: 'w',
    title: 'S moved',
    seriesId: 's',
    recurrenceId: '2026-10-21T12:00:00[Europe/Paris]',
    start: '2026-10-21T14:00[Europe/Paris]',
    extendedProps: cal('work'),
  ),
];

CalendarKernel kernel({
  String view = 'timeGridWeek',
  bool Function(CalEvent)? filter,
  void Function(Object, StackTrace)? onError,
}) => CalendarKernel(
  KernelOptions(
    timeZone: paris,
    locale: 'fr-FR',
    now: now,
    initialView: view,
    events: events(),
    options: ModelOptions(eventFilter: filter),
    onError: onError,
  ),
);

List<String> timed(CalendarKernel k) => [
  for (final c in (k.viewModel() as TimeGridViewModel).model.columns)
    for (final e in c.events) e.segment.instance.event.title,
];

List<String> allDay(CalendarKernel k) => [
  for (final b in (k.viewModel() as TimeGridViewModel).model.allDay.bars) b.segment.instance.event.title,
];

List<String> month(CalendarKernel k) => {
  for (final w in (k.viewModel() as DayGridViewModel).model.weeks)
    for (final s in w.segments) s.instance.event.title,
}.toList();

void main() {
  group('eventFilter', () {
    test('without one, everything; with one, only what it keeps — in the time grid', () {
      expect(timed(kernel()), ['S', 'S', 'A', 'B', 'S moved', 'S', 'S']);
      expect(allDay(kernel()), ['D']);
      final k = kernel(filter: workOnly);
      // The series is home: all its occurrences go; its Wednesday, changed into work, stays.
      expect(timed(k), ['A', 'S moved']);
      expect(allDay(k), isEmpty);
    });

    test('the month, the year and the list are filtered too', () {
      expect(month(kernel(view: 'dayGridMonth', filter: workOnly)), ['A', 'S moved']);
      final year = kernel(view: 'multiMonthYear', filter: workOnly).viewModel() as MultiMonthViewModel;
      expect(
        {
          for (final m in year.model.months)
            for (final w in m.model.weeks)
              for (final s in w.segments) s.instance.event.title,
        },
        {'A', 'S moved'},
      );
      final list = kernel(view: 'listWeek', filter: workOnly).viewModel() as ListViewModel;
      expect(
        [
          for (final d in list.model.days)
            for (final e in d.entries) e.instance.event.title,
        ],
        ['A', 'S moved'],
      );
    });

    test('the store keeps every event; the rules still see them', () {
      final k = kernel(filter: workOnly);
      expect(k.store.snapshot.getEvent('b'), isNotNull);
      expect(k.store.snapshot.allEvents.length, 4);
    });

    test('a new filter remakes the model and says so; the same one again says nothing', () {
      final k = kernel(filter: workOnly);
      final causes = <StateCause>[];
      k.subscribe((e) {
        if (e is KernelStateEvent) causes.addAll(e.causes);
      });
      k.setOptions(k.options.copyWith(eventFilter: workOnly));
      expect(causes, isEmpty);
      bool homeOnly(CalEvent e) => e.props['cal'] == 'home';
      k.setOptions(k.options.copyWith(eventFilter: homeOnly));
      expect(causes, [StateCause.options]);
      expect(timed(k), ['S', 'S', 'B', 'S', 'S']);
      expect(allDay(k), ['D']);
      k.setOptions(k.options.copyWith(clearEventFilter: true));
      expect(k.options.eventFilter, isNull);
      expect(timed(k), hasLength(7));
    });

    test('a tear-off of the same method is the same filter: nothing remade', () {
      final keep = _Keep('work');
      final k = kernel(filter: keep.test);
      final causes = <StateCause>[];
      k.subscribe((e) {
        if (e is KernelStateEvent) causes.addAll(e.causes);
      });
      k.setOptions(k.options.copyWith(eventFilter: keep.test));
      expect(causes, isEmpty);
      expect(timed(k), ['A', 'S moved']);
    });

    test('an undo lands filtered: a hidden event changed back stays hidden', () {
      final k = kernel(filter: workOnly);
      k.run(
        CreateEvent(
          EventInput(id: 'x', title: 'X', start: '2026-10-23T11:00[Europe/Paris]', extendedProps: cal('home')),
        ),
      );
      expect(timed(k), ['A', 'S moved']);
      expect(k.history.undo(), isTrue);
      expect(k.history.redo(), isTrue);
      expect(timed(k), ['A', 'S moved']);
      expect(k.store.snapshot.getEvent('x'), isNotNull);
    });

    test('a store change is filtered as it lands: hidden added, shown added, shown moved to hidden', () {
      final k = kernel(filter: workOnly);
      expect(timed(k), ['A', 'S moved']);
      k.run(
        CreateEvent(
          EventInput(id: 'h', title: 'H', start: '2026-10-23T09:00[Europe/Paris]', extendedProps: cal('home')),
        ),
      );
      expect(timed(k), ['A', 'S moved']);
      k.run(
        CreateEvent(
          EventInput(id: 'x', title: 'X', start: '2026-10-23T11:00[Europe/Paris]', extendedProps: cal('work')),
        ),
      );
      expect(timed(k), ['A', 'S moved', 'X']);
      final a = k.store.snapshot.getEvent('a')! as TimedEvent;
      k.store.apply([
        EventMutation(
          before: a,
          after: a.copyWith(props: cal('home')),
        ),
      ], ChangeCause.api);
      expect(timed(k), ['S moved', 'X']);
    });

    test('in a resource view, every column is filtered', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: now,
          initialView: 'resourceTimeGridDay',
          initialDate: PlainDate(2026, 10, 21),
          resources: const [
            ResourceInput(id: 'r1'),
            ResourceInput(id: 'r2'),
          ],
          options: const ModelOptions(showUnassigned: true, eventFilter: workOnly),
          events: [
            EventInput(
              id: 'p',
              title: 'P',
              start: '2026-10-21T09:00[Europe/Paris]',
              resourceId: 'r1',
              extendedProps: cal('work'),
            ),
            EventInput(
              id: 'q',
              title: 'Q',
              start: '2026-10-21T10:00[Europe/Paris]',
              resourceId: 'r1',
              extendedProps: cal('home'),
            ),
            EventInput(
              id: 'r',
              title: 'R',
              start: '2026-10-21T11:00[Europe/Paris]',
              resourceId: 'r2',
              extendedProps: cal('home'),
            ),
            EventInput(id: 'u', title: 'U', start: '2026-10-21T12:00[Europe/Paris]', extendedProps: cal('home')),
            EventInput(id: 'v', title: 'V', start: '2026-10-21T13:00[Europe/Paris]', extendedProps: cal('work')),
          ],
        ),
      );
      expect(
        [
          for (final c in (k.viewModel() as TimeGridViewModel).model.columns)
            [for (final e in c.events) e.segment.instance.event.title],
        ],
        [
          ['V'],
          ['P'],
          <String>[],
        ],
      );
    });

    test('a filter that throws is reported, and the event shown', () {
      final errors = <Object>[];
      final k = kernel(
        filter: (e) => e.id == 'b' ? throw StateError('bad filter') : workOnly(e),
        onError: (e, _) => errors.add(e),
      );
      expect(timed(k), ['A', 'B', 'S moved']);
      // Asked by each query of the build (the columns, the all-day row): reported once.
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      k.setView('dayGridMonth');
      k.viewModel();
      expect(errors, hasLength(1), reason: 'the same filter: said already');
    });

    test('a query of the store: where asks a series once, with its base', () {
      final k = kernel();
      final asked = <String>[];
      final found = k.store.snapshot.queryInstances(
        viewWindow(PlainDate(2026, 10, 19), PlainDate(2026, 10, 26), paris),
        QueryOptions(
          where: (e) {
            asked.add(e.id);
            return e.id != 's';
          },
        ),
      );
      expect(asked.where((id) => id == 's'), hasLength(1));
      expect({for (final i in found) i.event.title}, {'A', 'B', 'D', 'S moved'});
    });
  });

  // Without onError, the zone's handler hears it.
  test('the default error route is the zone’s', () {
    final caught = <Object>[];
    runZonedGuarded(() {
      final k = kernel(filter: (_) => throw StateError('x'));
      k.viewModel();
    }, (e, _) => caught.add(e));
    expect(caught, isNotEmpty);
  });
}

class _Keep {
  _Keep(this.calendar);
  final String calendar;
  bool test(CalEvent e) => e.props['cal'] == calendar;
}
