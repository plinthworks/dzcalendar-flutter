// Ported from the TypeScript core's timegrid-model.test.ts (hand-written
// expectations, copied as values).
//
// Ported: readings on a day the clocks change (2), updateTimeGridModel (3),
// gutter and now (2). Skipped: none. Translation notes:
// - `createHistory(store, ctx())` is `History(store, ctx())`; a command object
//   (`{ type: 'event.update', … }`) is the typed command (`UpdateEvent`,
//   `CreateEvent`, an `EventPatch`).
// - `toEqual({ offset, pass: 'first' })` compares a `Reading('+02:00',
//   WallPass.first)`; `'startReading' in ev` is `ev.startReading == null`.
// - `===` / `toBe` on model parts is `identical`.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

PlainDate d(String s) => PlainDate.parse(s);
final nav = NavContext(firstDay: 1, today: d('2026-10-21'));
const opts = TimeGridOptions(displayZone: 'Europe/Paris');
CommandContext ctx() => CommandContext(
  normalize: NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('m')),
);
EventStore storeWith(List<EventInput> inputs) {
  final s = EventStore();
  s.replaceSourceChunk('t', 'all', normalizeMany(inputs, ctx().normalize, sourceId: 't').items);
  return s;
}

ViewRange range(String at, String view) => computeViewRange(d(at), builtinViews[view]!, nav);

void main() {
  group('readings on a day the clocks change', () {
    test('the two 02:30s say which pass they are, the real length is given', () {
      final store = storeWith([
        EventInput(id: 'first', start: '2026-10-25T02:30+02:00[Europe/Paris]', duration: {'minutes': 30}),
        EventInput(id: 'second', start: '2026-10-25T02:30+01:00[Europe/Paris]', duration: {'minutes': 30}),
        EventInput(
          id: 'across',
          start: '2026-10-25T01:30+02:00[Europe/Paris]',
          end: '2026-10-25T02:30+01:00[Europe/Paris]',
        ),
      ]);
      final col = buildTimeGridModel(range('2026-10-25', 'timeGridDay'), store.snapshot, opts).columns.first;
      List<PlacedTimed> byKey(String k) => [
        for (final e in col.events)
          if (e.segment.instance.key == k) e,
      ];
      expect(byKey('first').first.startReading, const Reading('+02:00', WallPass.first));
      expect(byKey('second').first.startReading, const Reading('+01:00', WallPass.second));
      // 01:30 (+02:00) to 02:30 (+01:00): two hours, drawn as two parts on the wall axis.
      expect([for (final e in byKey('across')) e.realMinutes], [120, 120]);
    });

    test('an ordinary day carries no readings at all', () {
      final store = storeWith([EventInput(id: 'a', start: '2026-10-21T09:00[Europe/Paris]')]);
      final ev = buildTimeGridModel(
        range('2026-10-21', 'timeGridDay'),
        store.snapshot,
        opts,
      ).columns.first.events.first;
      expect(ev.startReading == null && ev.realMinutes == null, isTrue);
    });
  });

  group('updateTimeGridModel', () {
    test('rebuilds only the columns a change touches; the others keep their identity', () {
      final store = storeWith([
        EventInput(id: 'mon', start: '2026-10-19T09:00[Europe/Paris]'),
        EventInput(id: 'wed', start: '2026-10-21T09:00[Europe/Paris]'),
      ]);
      final r0 = range('2026-10-21', 'timeGridWeek');
      final prev = buildTimeGridModel(r0, store.snapshot, opts);
      final h = History(store, ctx());
      final r = h.run(const UpdateEvent('wed', EventPatch(start: '2026-10-21T14:00[Europe/Paris]')));
      final next = updateTimeGridModel(prev, store.snapshot, r.change!);
      expect(
        [for (var i = 0; i < next.columns.length; i++) identical(next.columns[i], prev.columns[i])],
        [true, true, false, true, true, true, true],
      );
      expect(identical(next.allDay, prev.allDay), isTrue);
      expect(next.columns[2].events.first.top, 840);
      // Same as a full rebuild.
      final full = buildTimeGridModel(r0, store.snapshot, opts);
      expect(
        [
          for (final e in next.columns[2].events) [e.segment.key, e.top, e.height],
        ],
        [
          for (final e in full.columns[2].events) [e.segment.key, e.top, e.height],
        ],
      );
    });

    test('a change outside the view returns the same model object', () {
      final store = storeWith([]);
      final prev = buildTimeGridModel(range('2026-10-21', 'timeGridWeek'), store.snapshot, opts);
      final r = History(store, ctx()).run(CreateEvent(EventInput(id: 'far', start: '2027-01-01T09:00[Europe/Paris]')));
      final next = updateTimeGridModel(prev, store.snapshot, r.change!);
      expect(identical(next.columns, prev.columns), isTrue);
      expect(identical(next.allDay, prev.allDay), isTrue);
    });

    test('an all-day change rebuilds the all-day row and no column', () {
      final store = storeWith([]);
      final prev = buildTimeGridModel(range('2026-10-21', 'timeGridWeek'), store.snapshot, opts);
      final r = History(store, ctx()).run(CreateEvent(EventInput(id: 'ad', start: '2026-10-22')));
      final next = updateTimeGridModel(prev, store.snapshot, r.change!);
      expect(
        [for (var i = 0; i < next.columns.length; i++) identical(next.columns[i], prev.columns[i])].every((x) => x),
        isTrue,
      );
      expect([for (final b in next.allDay.bars) b.segment.instance.key], ['ad']);
    });
  });

  group('gutter and now', () {
    test('the gutter comes from an ordinary day, even in the week of a clock change', () {
      final model = buildTimeGridModel(
        range('2026-10-25', 'timeGridWeek'),
        EventStore().snapshot,
        const TimeGridOptions(displayZone: 'Europe/Paris', slotMinutes: 60),
      );
      expect(model.gutter, hasLength(25));
      expect(model.gutter.any((t) => t.pass != null || t.skipped), isFalse);
    });

    test('locateNow finds the column and the position; outside the view, null', () {
      final model = buildTimeGridModel(range('2026-10-21', 'timeGridWeek'), EventStore().snapshot, opts);
      final now = locateNow(model, Instant.parse('2026-10-21T08:15:00Z'));
      expect(
        [now?.column, now?.columns, now?.position],
        [
          2,
          [2],
          615,
        ],
      );
      expect(locateNow(model, Instant.parse('2026-11-30T08:15:00Z')), isNull);
    });
  });
}
