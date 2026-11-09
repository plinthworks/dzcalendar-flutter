// Ported from the TypeScript core's interaction.test.ts (hand-written
// expectations, copied as values).
//
// Ported: proposeMove (7), proposeResize (2), selection and commands (2),
// parity between pointer and keyboard (1), fixed after the Phase 7 reviews
// (3). Skipped: none.
// Translation notes:
// - `p.start` / `p.end` are the proposed event's (`Proposal.proposed`); a
//   selection's are `DaySelection` / `TimeSelection`'s.
// - The rules `{ displayZone, overlap: false }` are
//   `RulesContext(displayZone:, overlap: RulesContext.noOverlap)`.
// - `commandFor` gives a `MoveEvent` (`event.move`) or an `UpdateEvent`
//   (`event.update`); `toMatchObject` checks the same fields.
// - An occurrence `{ ...t, id, ref }` is `withRef(t.withIdentity(id, null), EventRef(...))`.
// - `p.ambiguity` absent is `null`; `p.ambiguity?.edge` is `Edge.end.name`.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

const p = '[Europe/Paris]';
const paris = 'Europe/Paris';

PlainDate d(String s) => PlainDate.parse(s);
Instant i(String s) => Instant.parse(s);

CalEvent ev(EventInput input) {
  final r = normalizeEvent(input, NormalizeContext(displayZone: paris, newId: createIdGenerator('t')));
  final v = r.value;
  if (v is! NormalizedEvent) throw StateError('${r.problems}');
  return v.event;
}

InteractionContext ctx({StoreSnapshot? snap, RulesContext? rules, int snapMinutes = 15, ZoneId zone = paris}) =>
    InteractionContext(snap: snap ?? EventStore().snapshot, displayZone: zone, snapMinutes: snapMinutes, rules: rules);

Hit slot(String iso) {
  final z = ZonedDateTime.tryParse(iso)!;
  return SlotHit(date: z.date, instant: z.instant);
}

String _text(CalEvent e, {required bool start}) => switch (e) {
  TimedEvent() => '${start ? e.start : e.end}',
  AllDayEvent() => '${start ? e.start : e.end}',
};

String start(Proposal x) => _text(x.proposed, start: true);
String end(Proposal x) => _text(x.proposed, start: false);
List<String> s(Proposal x) => [start(x), end(x)];

List<String> sel(CalendarSelection x) => switch (x) {
  DaySelection(:final start, :final end) => ['$start', '$end'],
  TimeSelection(:final start, :final end) => ['$start', '$end'],
};

void main() {
  group('proposeMove', () {
    test('keeps the grab offset and the length; snaps the start on the wall clock', () {
      final e = ev(EventInput(start: '2026-10-21T09:00$p', end: '2026-10-21T10:00$p'));
      // Grabbed 30 min after its start, dropped at 14:10 the next day: 13:40, snapped to 13:45.
      final x = proposeMove(ctx(), e, slot('2026-10-21T09:30$p'), slot('2026-10-22T14:10$p'));
      expect([...s(x), x.valid, x.allDay], ['2026-10-22T13:45:00+02:00$p', '2026-10-22T14:45:00+02:00$p', true, false]);
    });

    test('dropped in the second 02:30 of the fall-back night: that pass, with the first as the alternative', () {
      final e = ev(EventInput(start: '2026-10-24T01:00$p', end: '2026-10-24T01:30$p'));
      final x = proposeMove(ctx(), e, slot('2026-10-24T01:00$p'), slot('2026-10-25T02:30+01:00$p'));
      expect(
        [start(x), '${x.ambiguity?.chosen}', '${x.ambiguity?.alternative}'],
        ['2026-10-25T02:30:00+01:00$p', '2026-10-25T01:30:00Z', '2026-10-25T00:30:00Z'],
      );
    });

    test('snapped into the spring-forward gap: moved to 03:00, flagged to be announced', () {
      final e = ev(EventInput(start: '2026-03-28T01:00$p', end: '2026-03-28T02:00$p'));
      final x = proposeMove(ctx(snapMinutes: 60), e, slot('2026-03-28T01:00$p'), slot('2026-03-29T01:40+01:00$p'));
      expect([start(x), x.skipped], ['2026-03-29T03:00:00+02:00$p', true]);
    });

    test('keeps the event’s own zone (a Tokyo call stays in Tokyo)', () {
      final e = ev(EventInput(start: '2026-10-22T09:00[Asia/Tokyo]', end: '2026-10-22T10:00[Asia/Tokyo]'));
      final x = proposeMove(ctx(), e, slot('2026-10-22T02:00+02:00[Europe/Paris]'), slot('2026-10-22T03:00$p'));
      expect(s(x), ['2026-10-22T10:00:00+09:00[Asia/Tokyo]', '2026-10-22T11:00:00+09:00[Asia/Tokyo]']);
    });

    test('days: a day event by whole days; a timed one keeps its wall time across the clock change', () {
      final a = ev(EventInput(start: '2026-10-05', end: '2026-10-07'));
      expect(s(proposeMove(ctx(), a, DayHit(date: d('2026-10-06')), DayHit(date: d('2026-10-09')))), [
        '2026-10-08',
        '2026-10-10',
      ]);
      final t = ev(EventInput(start: '2026-10-21T09:00$p', end: '2026-10-21T10:00$p'));
      expect(s(proposeMove(ctx(), t, DayHit(date: d('2026-10-21')), DayHit(date: d('2026-10-26')))), [
        '2026-10-26T09:00:00+01:00$p',
        '2026-10-26T10:00:00+01:00$p',
      ]);
    });

    test('between the all-day row and the grid: a timed event becomes a day, a day becomes one timed hour', () {
      final t = ev(EventInput(start: '2026-10-21T09:00$p', end: '2026-10-21T10:00$p'));
      final a = proposeMove(ctx(), t, slot('2026-10-21T09:00$p'), DayHit(date: d('2026-10-23'), allDayRow: true));
      expect([...s(a), a.allDay], ['2026-10-23', '2026-10-24', true]);
      final day = ev(EventInput(start: '2026-10-21'));
      final b = proposeMove(ctx(), day, DayHit(date: d('2026-10-21'), allDayRow: true), slot('2026-10-22T10:07$p'));
      expect([...s(b), b.allDay], ['2026-10-22T10:00:00+02:00$p', '2026-10-22T11:00:00+02:00$p', false]);
    });

    test('validates against the rules: overlap refused, the violation given', () {
      final store = EventStore();
      final other = ev(EventInput(id: 'b', start: '2026-10-21T11:00$p', end: '2026-10-21T12:00$p'));
      store.apply([EventMutation(after: other)], ChangeCause.api);
      final e = ev(EventInput(id: 'a', start: '2026-10-21T09:00$p', end: '2026-10-21T10:00$p'));
      final x = proposeMove(
        ctx(
          snap: store.snapshot,
          rules: const RulesContext(displayZone: paris, overlap: RulesContext.noOverlap),
        ),
        e,
        slot('2026-10-21T09:00$p'),
        slot('2026-10-21T11:30$p'),
      );
      expect(
        [
          x.valid,
          [for (final v in x.violations) v.code.code],
        ],
        [
          false,
          ['overlap'],
        ],
      );
    });
  });

  group('proposeResize', () {
    test('timed: the end snaps; never shorter than one step', () {
      final e = ev(EventInput(start: '2026-10-21T09:00$p', end: '2026-10-21T10:00$p'));
      expect(s(proposeResize(ctx(), e, Edge.end, slot('2026-10-21T11:20$p'))), [
        '2026-10-21T09:00:00+02:00$p',
        '2026-10-21T11:15:00+02:00$p',
      ]);
      expect(s(proposeResize(ctx(), e, Edge.end, slot('2026-10-21T08:00$p'))), [
        '2026-10-21T09:00:00+02:00$p',
        '2026-10-21T09:15:00+02:00$p',
      ]);
      expect(s(proposeResize(ctx(), e, Edge.start, slot('2026-10-21T07:50$p'))), [
        '2026-10-21T07:45:00+02:00$p',
        '2026-10-21T10:00:00+02:00$p',
      ]);
    });

    test('days: the cell under the pointer is the last day', () {
      final a = ev(EventInput(start: '2026-10-05', end: '2026-10-07'));
      expect(s(proposeResize(ctx(), a, Edge.end, DayHit(date: d('2026-10-09')))), ['2026-10-05', '2026-10-10']);
      expect(s(proposeResize(ctx(), a, Edge.end, DayHit(date: d('2026-10-01')))), ['2026-10-05', '2026-10-06']);
    });
  });

  group('selection and commands', () {
    test('a selection covers whole slots in either direction; over days, whole days', () {
      expect(sel(selectionBetween(ctx(), slot('2026-10-21T11:10$p'), slot('2026-10-21T09:05$p'))), [
        '2026-10-21T09:00:00+02:00$p',
        '2026-10-21T11:15:00+02:00$p',
      ]);
      expect(sel(selectionBetween(ctx(), DayHit(date: d('2026-10-23')), DayHit(date: d('2026-10-21')))), [
        '2026-10-21',
        '2026-10-24',
      ]);
    });

    test('commandFor: a move, an update when the kind changes, a series occurrence through its series', () {
      final t = ev(EventInput(id: 'a', start: '2026-10-21T09:00$p', end: '2026-10-21T10:00$p'));
      final x = proposeMove(ctx(), t, slot('2026-10-21T09:00$p'), slot('2026-10-21T11:00$p'));
      expect(
        commandFor(EventInstance('a', t, InstanceOrigin.single), x),
        isA<MoveEvent>().having((c) => c.id, 'id', 'a'),
      );
      final q = proposeMove(ctx(), t, slot('2026-10-21T09:00$p'), DayHit(date: d('2026-10-21'), allDayRow: true));
      expect(
        commandFor(EventInstance('a', t, InstanceOrigin.single), q),
        isA<UpdateEvent>().having((c) => c.id, 'id', 'a').having((c) => c.patch.allDay, 'patch.allDay', true),
      );
      const key = '2026-10-21T09:00:00+02:00$p';
      final occ = withRef(t.withIdentity('s@$key', null), const EventRef('s', key));
      expect(
        commandFor(EventInstance('s@$key', occ, InstanceOrigin.occurrence), x, EditScope.following),
        isA<MoveEvent>()
            .having((c) => c.id, 'id', 's')
            .having((c) => c.key, 'key', key)
            .having((c) => c.scope, 'scope', EditScope.following),
      );
    });
  });

  group('parity: the pointer and the keyboard propose the same thing', () {
    test('a hit from a position on the axis equals a hit from a date and a time', () {
      final date = d('2026-10-25');
      final axis = buildColumnAxis(date, paris);
      final e = ev(EventInput(start: '2026-10-25T05:00$p', end: '2026-10-25T06:00$p')) as TimedEvent;
      for (final minutes in [0, 150, 210, 600, 1425]) {
        // The pointer: a position on the drawn axis. The keyboard: a wall time stepped to, read in the zone.
        final fromPointer = SlotHit(date: date, instant: axis.fromPosition(minutes.toDouble()).instant);
        final wall = PlainTime(minutes ~/ 60, minutes % 60);
        final fromKeys = SlotHit(date: date, instant: resolveWall(date, wall, paris, WallPolicy.compatible).instant!);
        final grab = SlotHit(date: date, instant: e.start.instant);
        final a = proposeMove(ctx(), e, grab, fromPointer);
        final b = proposeMove(ctx(), e, grab, fromKeys);
        expect([start(a), a.valid], [start(b), b.valid]);
      }
    });
  });

  group('fixed after the Phase 7 reviews (by hand)', () {
    test('a resize into the repeated hour: the ambiguity is the end’s; clamped to the minimum, none', () {
      final e = ev(EventInput(start: '2026-10-25T00:00$p', end: '2026-10-25T00:45$p'));
      final x = proposeResize(ctx(), e, Edge.end, slot('2026-10-25T02:30+01:00$p'));
      expect(
        [start(x), x.ambiguity?.edge.name, '${x.ambiguity?.chosen}'],
        ['2026-10-25T00:00:00+02:00$p', 'end', '2026-10-25T01:30:00Z'],
      );
      final late = ev(EventInput(start: '2026-10-25T02:30+01:00$p', end: '2026-10-25T03:30$p'));
      final q = proposeResize(ctx(), late, Edge.end, slot('2026-10-25T02:20+02:00$p'));
      expect([end(q), q.ambiguity], ['2026-10-25T02:45:00+01:00$p', null]);
    });

    test('a hit in a skipped hour lands on the first moment after it and is flagged', () {
      final e = ev(EventInput(start: '2026-03-27T09:00$p', end: '2026-03-27T10:00$p'));
      final gapHit = SlotHit(date: d('2026-03-29'), instant: i('2026-03-29T01:00:00Z'), gap: true);
      final x = proposeMove(ctx(), e, slot('2026-03-27T09:00$p'), gapHit);
      expect([start(x), x.skipped], ['2026-03-29T03:00:00+02:00$p', true]);
    });

    test('Lord Howe’s half-hour changes: a selection holds the tapped moment and ends on the wall slot', () {
      const lh = '[Australia/Lord_Howe]';
      final c = ctx(zone: 'Australia/Lord_Howe', snapMinutes: 60);
      // The spring change, 4 October 2026: 02:00 → 02:30.
      final tap = slot('2026-10-04T02:40+11:00$lh');
      expect(sel(selectionBetween(c, tap, tap)), ['2026-10-04T02:30:00+11:00$lh', '2026-10-04T03:00:00+11:00$lh']);
      // 5 April 2026, fall back 02:00 → 01:30: 01:45 of the second pass.
      final back = slot('2026-04-05T01:45+10:30$lh');
      final b = selectionBetween(c, back, back) as TimeSelection;
      final t = ZonedDateTime.tryParse('2026-04-05T01:45+10:30$lh')!.epochMilliseconds;
      expect(b.start.epochMilliseconds <= t && t < b.end.epochMilliseconds, isTrue);
    });
  });
}
