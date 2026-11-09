// Ported from the TypeScript core's multimonth.test.ts (hand-written
// expectations, copied as values).
//
// Ported: multi-month range (2), multi-month model (2), hidden days for the
// whole calendar (3, with the kernel, 19e-1). Skipped: none.
// Translation notes:
// - The kernel's `hiddenDays` is `options: ModelOptions(hiddenDays: ...)`;
//   `setOptions({ hiddenDays })` is `setOptions(k.options.copyWith(hiddenDays:))`;
//   `RangeError` is `ArgumentError`. `{ ...BUILTIN_VIEWS.timeGridWeek, type,
//   hiddenDays }` is `copyWith(type:, hiddenDays:)`.
// - `{ ...BUILTIN_VIEWS.listMonth, duration: { months: 2 } }` is
//   `copyWith(duration: IsoDuration(months: 2))`.
// - A mutation `{ kind: 'event', before, after: { ...ev, title } }` is
//   `EventMutation(before:, after: ev.copyWith(title:))`; `toBe` is `identical`.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

PlainDate d(String s) => PlainDate.parse(s);
final nav = NavContext(firstDay: 1, today: d('2026-10-21'));

void main() {
  group('multi-month range', () {
    test('a year is twelve month grids; the range runs from the first grid to the last', () {
      final r = computeViewRange(d('2026-10-21'), builtinViews['multiMonthYear']!, nav);
      expect(
        [for (final m in r.months!) '${m.activeStart}'.substring(0, 7)],
        [for (var i = 0; i < 12; i++) '2026-${'${i + 1}'.padLeft(2, '0')}'],
      );
      // January 2026 starts on a Thursday: its grid starts Monday 29 December 2025.
      expect('${r.start}', '2025-12-29');
      // December 2026's six-week grid ends Sunday 10 January 2027 (exclusive end: the 11th).
      expect('${r.end}', '2027-01-11');
      expect(['${r.activeStart}', '${r.activeEnd}'], ['2026-01-01', '2027-01-01']);
      expect(r.dates, hasLength(365));
    });

    test('a list month runs for its duration', () {
      final spec = builtinViews['listMonth']!.copyWith(duration: IsoDuration(months: 2));
      final r = computeViewRange(d('2026-10-21'), spec, nav);
      expect(['${r.start}', '${r.end}'], ['2026-10-01', '2026-12-01']);
    });
  });

  group('multi-month model', () {
    final store = EventStore();
    store.replaceSourceChunk(
      's',
      '*',
      normalizeMany([
        EventInput(id: 'eve', start: '2026-10-31T20:00[Europe/Paris]', title: 'eve'),
        EventInput(id: 'nov', start: '2026-11-02T09:00[Europe/Paris]', title: 'nov'),
      ], NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('t'))).items,
    );
    final range = computeViewRange(d('2026-10-21'), builtinViews['multiMonthYear']!, nav);
    final model = buildMultiMonthModel(
      range,
      store.snapshot,
      const DayGridOptions(displayZone: 'Europe/Paris', maxLanes: 3),
    );
    List<String> keysIn(int month) => [
      for (final w in model.months[month - 1].model.weeks)
        for (final s in w.segments) s.instance.event.id,
    ];

    test('each date’s events are drawn in its own month only, never in a neighbour’s padding', () {
      expect(keysIn(10), ['eve']);
      expect(keysIn(11), ['nov']);
      // 2 November is padding at the end of October's grid; 31 October at the start of November's.
      expect([
        for (final w in model.months[9].model.weeks)
          for (final x in w.dates) '$x',
      ], contains('2026-11-02'));
      expect([
        for (final w in model.months[10].model.weeks)
          for (final x in w.dates) '$x',
      ], contains('2026-10-31'));
    });

    test('a change redraws the months it touches; the others keep their objects', () {
      final nov = store.snapshot.getEvent('nov')! as TimedEvent;
      final change = store.apply([
        EventMutation(
          before: nov,
          after: nov.copyWith(title: 'nov!'),
        ),
      ], ChangeCause.api);
      final next = updateMultiMonthModel(model, store.snapshot, change);
      expect(identical(next.months[0], model.months[0]), isTrue);
      expect(identical(next.months[10], model.months[10]), isFalse);
    });
  });

  group('hidden days for the whole calendar', () {
    CalendarKernel k() => CalendarKernel(
      KernelOptions(
        timeZone: 'Europe/Paris',
        locale: 'fr-FR',
        initialDate: d('2026-10-21'),
        initialView: 'dayGridMonth',
        options: const ModelOptions(hiddenDays: [6, 7]),
        now: () => Instant.parse('2026-10-21T08:00:00Z'),
      ),
    );

    test('every view leaves them out; a view naming its own keeps them', () {
      final kernel = k();
      expect([for (final x in kernel.state.range.weeks[0]) x.dayOfWeek], [1, 2, 3, 4, 5]);
      kernel.setView('timeGridWeek');
      expect(
        [for (final x in kernel.state.range.dates) '$x'],
        ['2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22', '2026-10-23'],
      );
      final own = CalendarKernel(
        KernelOptions(
          timeZone: 'UTC',
          locale: 'fr-FR',
          initialDate: d('2026-10-21'),
          options: const ModelOptions(hiddenDays: [6, 7]),
          initialView: 'mine',
          views: {
            'mine': builtinViews['timeGridWeek']!.copyWith(type: 'mine', hiddenDays: [3]),
          },
        ),
      );
      expect([for (final x in own.state.range.dates) x.dayOfWeek], [1, 2, 4, 5, 6, 7]);
    });

    test('setOptions changes them; the same list again says nothing; all seven are refused', () {
      final kernel = k();
      final seen = <StateCause>[];
      kernel.subscribe((e) {
        if (e is KernelStateEvent) seen.addAll(e.causes);
      });
      kernel.setOptions(kernel.options.copyWith(hiddenDays: [7, 6]));
      expect(seen, isEmpty);
      kernel.setOptions(kernel.options.copyWith(hiddenDays: []));
      expect(seen, [StateCause.options]);
      expect(kernel.state.range.weeks[0], hasLength(7));
      expect(() => kernel.setOptions(kernel.options.copyWith(hiddenDays: [1, 2, 3, 4, 5, 6, 7])), throwsArgumentError);
    });

    test('the view spec in force keeps its identity while nothing changes', () {
      final kernel = k();
      final a = kernel.state.view;
      kernel.navigate(NavDirection.next);
      expect(identical(kernel.state.view, a), isTrue);
    });
  });
}
