// Ported from the TypeScript core's maxstack.test.ts (hand-written
// expectations, copied as values).
//
// Ported: maxStack, a crowded cluster behind "+N" (4), maxStack edges (2).
// Skipped: none. Translation notes:
// - 'fractional' and NaN limits: Dart's `int? maxStack` cannot hold them;
//   the test keeps 0 and a negative one (no limit, as on the web).

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

PlainDate d(String s) => PlainDate.parse(s);
final nav = NavContext(firstDay: 1, today: d('2026-10-21'));
final day = computeViewRange(d('2026-10-21'), builtinViews['timeGridDay']!, nav);
EventInput at(String hh, String id, [int minutes = 60]) =>
    EventInput(id: id, title: id, start: '2026-10-21T$hh[Europe/Paris]', duration: {'minutes': minutes});

TimeGridColumn column(List<EventInput> events, [int? maxStack]) {
  final store = EventStore();
  store.replaceSourceChunk(
    's',
    '*',
    normalizeMany(
      events,
      NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('t')),
      sourceId: 's',
    ).items,
  );
  return buildTimeGridModel(
    day,
    store.snapshot,
    TimeGridOptions(displayZone: 'Europe/Paris', maxStack: maxStack),
  ).columns.first;
}

String idOf(PlacedTimed e) => e.segment.instance.event.id;

void main() {
  group('maxStack: a crowded cluster behind "+N"', () {
    // Six events all at 09:00–10:00: six lanes.
    final six = [
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) at('09:00', id),
    ];

    test('without it, everything side by side', () {
      final c = column(six);
      expect(c.events, hasLength(6));
      expect(c.more, isEmpty);
    });

    test('maxStack 3: two lanes drawn a third wide, four behind one "+N" in the third', () {
      final c = column(six, 3);
      expect(
        [
          for (final e in c.events) [idOf(e), e.left, e.width],
        ],
        [
          ['a', 0, 1 / 3],
          ['b', 1 / 3, 1 / 3],
        ],
      );
      expect(c.more, hasLength(1));
      expect([for (final e in c.more.first.events) idOf(e)], ['c', 'd', 'e', 'f']);
      final m = c.more.first;
      expect([m.top, m.height, m.left, m.width], [540, 60, 2 / 3, 1 / 3]);
    });

    test('a cluster within the limit is untouched; two separate crowded hours give two links', () {
      final c = column([
        ...six,
        at('14:00', 'g'),
        for (final id in ['h', 'i', 'j', 'k']) at('16:00', id, 30),
      ], 3);
      expect(c.events.firstWhere((e) => idOf(e) == 'g').width, 1);
      expect(
        [
          for (final m in c.more) [m.top, m.events.length],
        ],
        [
          [540, 4],
          [960, 2],
        ],
      );
    });

    test('an event spanning several lanes is cut to what the drawn lanes allow', () {
      // A long event at 08:00–12:00 widens over lanes free beside it; with maxStack 2 it keeps one lane.
      final c = column([at('08:00', 'long', 240), at('09:00', 'x'), at('09:00', 'y'), at('11:00', 'z')], 2);
      final long = c.events.firstWhere((e) => idOf(e) == 'long');
      expect([long.left, long.width], [0, 1 / 2]);
      expect(
        [
          for (final m in c.more)
            for (final e in m.events) idOf(e),
        ]..sort(),
        [
          for (final id in ['x', 'y', 'z'])
            if (!c.events.any((e) => idOf(e) == id)) id,
        ]..sort(),
      );
    });
  });

  group('maxStack edges', () {
    final three = [
      for (final id in ['a', 'b', 'c']) at('09:00', id),
    ];

    test('1: a crowded cluster wholly behind one "+N" across the column', () {
      final c = column(three, 1);
      expect(c.events, isEmpty);
      expect(
        [
          for (final m in c.more) [m.left, m.width, m.events.length],
        ],
        [
          [0, 1, 3],
        ],
      );
    });

    test('0, negative: no limit', () {
      for (final bad in [0, -2]) {
        expect(column(three, bad).events, hasLength(3));
      }
    });
  });
}
