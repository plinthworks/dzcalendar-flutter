// Ported from the TypeScript core's project.test.ts (hand-written
// expectations, copied as values).
//
// Skipped: nothing. Every test of that file has its function in the port
// (buildColumnAxis, segmentTimed, segmentAllDay, splitByWeek, DateIndex).

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:test/test.dart';

PlainDate d(String s) => PlainDate.parse(s);

EventInstance inst(EventInput input) {
  final r = normalizeEvent(input, NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('p')));
  if (!r.ok) fail('rejected: ${r.problems}');
  final event = r.value!.event;
  return EventInstance(event.id, event, InstanceOrigin.single);
}

Instant at(String s) => Instant.parse(s);

List<(TransitionKind, double, double)> bandsOf(ColumnAxis a) => [for (final b in a.bands) (b.kind, b.from, b.to)];

List<(int, int, bool, bool)> barsOf(List<AllDaySegment> segs) => [
  for (final s in segs) (s.dayIndex, s.dayCount, s.startsHere, s.endsHere),
];

void main() {
  group('segmentTimed on real days', () {
    test('a night across the 25-hour Sunday in Paris: three slices, the middle one 25 hours', () {
      final days = dayInfos(d('2026-10-24'), 3, 'Europe/Paris');
      final segs = segmentTimed(
        inst(EventInput(id: 'e', start: '2026-10-24T20:00[Europe/Paris]', end: '2026-10-26T08:00[Europe/Paris]')),
        days,
      );
      expect([for (final s in segs) s.dayIndex], [0, 1, 2]);
      expect(
        [for (final s in segs) s.to.epochMilliseconds - s.from.epochMilliseconds],
        [4 * 3600000, 25 * 3600000, 8 * 3600000],
      );
      expect([for (final s in segs) (s.startsHere, s.endsHere)], [(true, false), (false, false), (false, true)]);
    });

    test('an event ending exactly at midnight is not on the next day; a milestone at midnight is', () {
      final days = dayInfos(d('2026-05-01'), 2, 'UTC');
      final ends = segmentTimed(
        inst(EventInput(id: 'e', start: '2026-05-01T22:00[UTC]', end: '2026-05-02T00:00[UTC]')),
        days,
      );
      expect([for (final s in ends) s.dayIndex], [0]);
      final milestone = segmentTimed(
        inst(EventInput(id: 'e', start: '2026-05-02T00:00[UTC]', end: '2026-05-02T00:00[UTC]')),
        days,
      );
      expect([for (final s in milestone) s.dayIndex], [1]);
    });

    test('a Tokyo event lands on the display zone’s day', () {
      final days = dayInfos(d('2026-05-01'), 2, 'Europe/Paris');
      // 05:00 Tokyo on the 2nd is 22:00 Paris on the 1st.
      final segs = segmentTimed(inst(EventInput(id: 'e', start: '2026-05-02T05:00[Asia/Tokyo]')), days);
      expect([for (final s in segs) s.dayIndex], [0]);
    });

    test('a skipped day gets no slice (Apia, 30 December 2011)', () {
      final days = dayInfos(d('2011-12-29'), 3, 'Pacific/Apia');
      final segs = segmentTimed(
        inst(EventInput(id: 'e', start: '2011-12-29T20:00[Pacific/Apia]', end: '2011-12-31T04:00[Pacific/Apia]')),
        days,
      );
      expect([for (final s in segs) s.dayIndex], [0, 2]);
    });

    test('cutAtRepeat splits a slice at the fall-back, so each part reads the right way up', () {
      final days = dayInfos(d('2026-10-25'), 1, 'Europe/Paris');
      final ev = inst(
        EventInput(id: 'e', start: '2026-10-25T02:50+02:00[Europe/Paris]', end: '2026-10-25T02:10+01:00[Europe/Paris]'),
      );
      expect(segmentTimed(ev, days), hasLength(1));
      final parts = segmentTimed(ev, days, cutAtRepeat: true);
      expect([for (final p in parts) (p.part, p.startsHere, p.endsHere)], [(0, true, false), (1, false, true)]);
      expect([for (final p in parts) p.key], ['e|2026-10-25|0', 'e|2026-10-25|1']);
    });
  });

  group('segmentAllDay and splitByWeek', () {
    final week = [
      d('2026-05-04'),
      d('2026-05-05'),
      d('2026-05-06'),
      d('2026-05-07'),
      d('2026-05-08'),
    ]; // weekend hidden

    test('a bar across a hidden weekend is cut in two', () {
      final view = DateIndex([...week, d('2026-05-11'), d('2026-05-12')]);
      final segs = segmentAllDay(inst(EventInput(id: 'e', start: '2026-05-07', end: '2026-05-12')), view);
      expect(barsOf(segs), [(3, 2, true, false), (5, 1, false, true)]);
    });

    test('clipped to the view: neither end rounded when the event runs past both', () {
      final segs = segmentAllDay(inst(EventInput(id: 'e', start: '2026-05-01', end: '2026-05-20')), DateIndex(week));
      expect(barsOf(segs), [(0, 5, false, false)]);
    });

    test('splitByWeek cuts a bar at each row end', () {
      final view = DateIndex([for (var i = 0; i < 14; i++) d('2026-05-04').addDays(i)]);
      final segs = segmentAllDay(inst(EventInput(id: 'e', start: '2026-05-09', end: '2026-05-13')), view);
      final rows = splitByWeek(segs, [
        [0, 1, 2, 3, 4, 5, 6],
        [7, 8, 9, 10, 11, 12, 13],
      ]);
      expect(
        [for (final r in rows) barsOf(r)],
        [
          [(5, 2, true, false)],
          [(7, 2, false, true)],
        ],
      );
    });
  });

  group('buildColumnAxis', () {
    test('wall, spring forward in Paris: a gap band 02:00–03:00, positions are clock minutes', () {
      final axis = buildColumnAxis(d('2026-03-29'), 'Europe/Paris');
      expect(axis.length, 1440);
      expect(bandsOf(axis), [(TransitionKind.gap, 120, 180)]);
      expect(axis.toPosition(at('2026-03-29T01:00:00Z')), 180); // 03:00 CEST
      final pos = axis.fromPosition(150);
      expect((pos.exists, '${pos.instant}'), (false, '2026-03-29T01:30:00Z')); // pushed to 03:30
      final tick = axis.ticks(60).firstWhere((t) => t.position == 120);
      expect(tick.note, TickNote.skipped);
      expect(tick.instant, isNull);
    });

    test('wall, fall back: both 02:30s share a position, the band is marked', () {
      final axis = buildColumnAxis(d('2026-10-25'), 'Europe/Paris');
      expect(bandsOf(axis), [(TransitionKind.repeat, 120, 180)]);
      expect(axis.toPosition(at('2026-10-25T00:30:00Z')), 150);
      expect(axis.toPosition(at('2026-10-25T01:30:00Z')), 150);
      final first = axis.fromPosition(150);
      final second = axis.fromPosition(150, AxisPrefer.later);
      expect(
        ['${first.instant}', '${second.instant}', first.ambiguous],
        ['2026-10-25T00:30:00Z', '2026-10-25T01:30:00Z', true],
      );
      expect('${axis.fromPosition(150, const AxisPrefer.offset('+01:00')).instant}', '2026-10-25T01:30:00Z');
      expect(axis.toPosition(axis.day.end), 1440);
    });

    test('elapsed, fall back: a 25-hour column, the second pass marked', () {
      final axis = buildColumnAxis(d('2026-10-25'), 'Europe/Paris', mode: AxisMode.elapsed);
      expect(axis.length, 1500);
      expect(bandsOf(axis), [(TransitionKind.repeat, 180, 240)]);
      final ticks = axis.ticks(60);
      expect(ticks, hasLength(26));
      expect(
        [for (final t in ticks.sublist(2, 5)) ('${t.label}', t.note)],
        [('02:00:00', TickNote.firstPass), ('02:00:00', TickNote.secondPass), ('03:00:00', null)],
      );
    });

    test('Lord Howe: half-hour bands', () {
      expect(bandsOf(buildColumnAxis(d('2026-10-04'), 'Australia/Lord_Howe')), [(TransitionKind.gap, 120, 150)]);
      expect(bandsOf(buildColumnAxis(d('2026-04-05'), 'Australia/Lord_Howe')), [(TransitionKind.repeat, 90, 120)]);
    });

    test('Havana: the missing midnight hour is a band at the top', () {
      expect(bandsOf(buildColumnAxis(d('2023-03-12'), 'America/Havana')), [(TransitionKind.gap, 0, 60)]);
    });

    test('Apia: a skipped day has an empty axis', () {
      final axis = buildColumnAxis(d('2011-12-30'), 'Pacific/Apia');
      expect(axis.length, 0);
      expect(axis.ticks(60), isEmpty);
    });

    test('slotMin and slotMax: 08:00 to 20:00, start and end of the axis', () {
      final axis = buildColumnAxis(
        d('2026-05-01'),
        'UTC',
        slotMin: const Duration(hours: 8),
        slotMax: const Duration(hours: 20),
      );
      expect([axis.length, '${axis.start}', '${axis.end}'], [720, '2026-05-01T08:00:00Z', '2026-05-01T20:00:00Z']);
      expect(axis.toPosition(at('2026-05-01T09:30:00Z')), 90);
    });

    test('a tick step of zero or less is refused instead of looping forever', () {
      final axis = buildColumnAxis(d('2026-10-21'), 'Europe/Paris');
      expect(() => axis.ticks(0), throwsArgumentError);
      expect(
        () => buildColumnAxis(d('2026-10-21'), 'Europe/Paris', mode: AxisMode.elapsed).ticks(-5),
        throwsArgumentError,
      );
    });

    test('refuses slotMax beyond 24 hours and empty ranges, rather than draw them half right', () {
      expect(() => buildColumnAxis(d('2026-05-01'), 'UTC', slotMax: const Duration(hours: 30)), throwsArgumentError);
      expect(
        () => buildColumnAxis(
          d('2026-05-01'),
          'UTC',
          slotMin: const Duration(hours: 10),
          slotMax: const Duration(hours: 10),
        ),
        throwsArgumentError,
      );
    });

    test('elapsed axis starting after the fall-back: no phantom band at the top', () {
      final axis = buildColumnAxis(
        d('2026-10-25'),
        'Europe/Paris',
        mode: AxisMode.elapsed,
        slotMin: const Duration(hours: 6),
      );
      expect(axis.bands, isEmpty);
    });

    test('toEndPosition: an end at the fall-back closes the first pass; in the second pass it is its clock time', () {
      final axis = buildColumnAxis(d('2026-10-25'), 'Europe/Paris');
      expect(axis.toEndPosition(at('2026-10-25T01:00:00Z')), 180); // 03:00 first pass
      expect(axis.toPosition(at('2026-10-25T01:00:00Z')), 120); // 02:00 second pass
      expect(axis.toEndPosition(at('2026-10-25T01:10:00Z')), 130);
      expect(axis.toEndPosition(axis.day.end), 1440);
    });
  });
}
