// Ported from the TypeScript Pro's timeline.test.ts (hand-written
// expectations, copied as values).
//
// Ported: 'timeline axis: elapsed, cut on the wall clock' (9), 'timeline
// model' (6), 'timeline in the kernel' (1). Added by hand (19j-1): markers,
// backgrounds, a fall-back night, the axis's edges, days shaded on a day
// scale, the event filter, a fold keeping its rows, the settings refused.
// Translation notes:
// - `{ slot: 60 }` / `{ slot: 'day' }` / `{ slot: 7 }` are
//   `scale: TimelineScale.minutes(60)` / `TimelineScale.day` /
//   `TimelineScale.tryMinutes(7)` — null for a length that does not divide a
//   day, so the default is taken, as the web does with `slot: 7`; given
//   directly, `TimelineScale.minutes(7)` is a programmer's mistake and
//   `buildTimelineAxis` throws (checked below too).
// - `toBeCloseTo(x, 9)` is `closeTo(x, 1e-9)`.
// - A row's `kind` is its class (`TimelineResourceRow`, `TimelineGroupRow`,
//   `TimelineAllRow`); its events, lanes and shading are in its `body`.
// - `{ ...before, resourceIds: ['a'], title: 'moved' }` is `copyWith`.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

PlainDate d(String s) => PlainDate.parse(s);
final nav = NavContext(firstDay: 1, today: d('2026-10-21'));
ViewRange range(String type, String at) => computeViewRange(d(at), timelineViews[type]!, nav);
String label(TimelineSlot s) {
  final t = s.time;
  return '${t != null ? t.toString().substring(0, 5) : '${s.date}'}${s.pass == WallPass.second ? '*' : ''}${s.offset}';
}

Instant i(String s) => Instant.parse(s);

const paris = 'Europe/Paris';

EventStore storeWith(List<EventInput> inputs) {
  final s = EventStore();
  s.replaceSourceChunk(
    't',
    'all',
    normalizeMany(
      inputs,
      NormalizeContext(displayZone: paris, newId: createIdGenerator('t')),
      sourceId: 't',
    ).items,
  );
  return s;
}

final tree = buildResourceTree([
  const ResourceInput(id: 'a', title: 'A'),
  ResourceInput(
    id: 'b',
    title: 'B',
    timeZone: 'Asia/Riyadh',
    businessHours: BusinessHours([
      BusinessHoursRule(daysOfWeek: const [7, 1, 2, 3, 4], from: const WallTime(8), to: const WallTime(12)),
    ]),
  ),
]).tree;
List<ResourceRow> rows([List<ResourceRow> extra = const []]) => [...extra, ...flattenRows(tree)];

TimelineOptions opts({
  List<ResourceRow>? rows,
  int maxLanes = 3,
  TimelineScale? scale,
  BusinessHours? businessHours,
  bool Function(CalEvent)? eventFilter,
}) => TimelineOptions(
  displayZone: paris,
  rows: rows,
  resources: tree.order,
  maxLanes: maxLanes,
  scale: scale,
  businessHours: businessHours,
  eventFilter: eventFilter,
);

TimelineRowBody body(TimelineModel m, int row) => (m.rows[row] as TimelineResourceRow).body;
List<List<Object>> bars(TimelineRowBody b) => [
  for (final e in b.events) [e.segment.instance.key, e.from, e.to, e.lane],
];

void main() {
  group('timeline axis: elapsed, cut on the wall clock', () {
    test('Paris, 25 October 2026 (fall back at 03:00 to 02:00): 50 half hours, 02:00 and 02:30 twice', () {
      final a = buildTimelineAxis(range('timelineDay', '2026-10-25'), 'Europe/Paris');
      expect([a.unit, a.slotMinutes, a.slots.length, a.length], [TimelineUnit.time, 30, 50, 50]);
      expect(a.slots.sublist(3, 9).map(label).toList(), [
        '01:30+02:00',
        '02:00+02:00',
        '02:30+02:00',
        '02:00*+01:00',
        '02:30*+01:00',
        '03:00+01:00',
      ]);
      expect(a.slots[4].pass, WallPass.first);
      // Every slot is 30 real minutes: the second 02:00 starts an hour after the first.
      expect(a.slots[6].start.epochMilliseconds - a.slots[4].start.epochMilliseconds, 3600000);
    });

    test('Paris, 29 March 2026 (02:00 becomes 03:00): 46 half hours, 01:30 is followed by 03:00', () {
      final a = buildTimelineAxis(range('timelineDay', '2026-03-29'), 'Europe/Paris');
      expect([a.slots.length, a.length], [46, 46]);
      expect(a.slots.sublist(2, 5).map(label).toList(), ['01:00+01:00', '01:30+01:00', '03:00+02:00']);
      expect('${a.slots[3].end}', '2026-03-29T01:00:00Z');
    });

    test('a week of hours: 24, 24, … and 25 on the Sunday the clocks fall back — 169 hours wide', () {
      final a = buildTimelineAxis(range('timelineWeek', '2026-10-21'), 'Europe/Paris');
      expect(
        [
          a.slotMinutes,
          [for (final g in a.groups) g.lengthMinutes / 60],
          a.length,
        ],
        [
          60,
          [24, 24, 24, 24, 24, 24, 25],
          169,
        ],
      );
      // Sunday starts 144 hours in; its 25 hours run to 169.
      expect([a.toPosition(a.groups[6].start), a.toPosition(a.groups[6].end)], [144, 169]);
    });

    test('Lord Howe: spring skips half an hour (47 slots), autumn repeats one (49, 01:30 twice)', () {
      // 4 October 2026: 02:00 (+10:30) becomes 02:30 (+11:00).
      final spring = buildTimelineAxis(range('timelineDay', '2026-10-04'), 'Australia/Lord_Howe');
      expect([spring.slots.length, spring.groups[0].lengthMinutes], [47, 1410]);
      expect(spring.slots.sublist(3, 5).map(label).toList(), ['01:30+10:30', '02:30+11:00']);
      // 5 April 2026: 02:00 (+11:00) becomes 01:30 (+10:30).
      final autumn = buildTimelineAxis(range('timelineDay', '2026-04-05'), 'Australia/Lord_Howe');
      expect([autumn.slots.length, autumn.groups[0].lengthMinutes], [49, 1470]);
      expect(autumn.slots.sublist(2, 6).map(label).toList(), [
        '01:00+11:00',
        '01:30+11:00',
        '01:30*+10:30',
        '02:00+10:30',
      ]);
    });

    test('São Paulo, 4 November 2018: the day starts at 01:00 (midnight skipped), 23 hours', () {
      final a = buildTimelineAxis(
        range('timelineDay', '2018-11-04'),
        'America/Sao_Paulo',
        scale: const TimelineScale.minutes(60),
      );
      expect([a.slots.length, label(a.slots[0]), '${a.slots[0].start}'], [23, '01:00-02:00', '2018-11-04T03:00:00Z']);
    });

    test('Kolkata: no clock change, 48 half hours at +05:30', () {
      final a = buildTimelineAxis(range('timelineDay', '2026-10-25'), 'Asia/Kolkata');
      expect([a.slots.length, a.slots[0].offset], [48, '+05:30']);
    });

    test('a month of days: each as wide as its hours (25 October is 25/24 of a day), months above', () {
      final a = buildTimelineAxis(range('timelineMonth', '2026-10-21'), 'Europe/Paris');
      expect([a.unit, a.slotMinutes, a.slots.length, a.groups.length], [TimelineUnit.day, 1440, 31, 1]);
      final sunday = a.slots[24];
      expect('${sunday.date}', '2026-10-25');
      expect(a.toPosition(sunday.end) - a.toPosition(sunday.start), closeTo(25 / 24, 1e-9));
      expect(a.length, closeTo(31 + 1 / 24, 1e-9));
    });

    test('positions: clamped, back and forth; the slot of an instant', () {
      final a = buildTimelineAxis(range('timelineDay', '2026-10-25'), 'Europe/Paris');
      final second0200 = i('2026-10-25T01:00:00Z');
      expect([a.toPosition(second0200), a.slotAt(second0200), '${a.fromPosition(6)}'], [6, 6, '2026-10-25T01:00:00Z']);
      expect(
        [
          a.toPosition(i('2026-10-20T00:00:00Z')),
          a.toPosition(i('2026-11-20T00:00:00Z')),
          a.slotAt(i('2026-11-20T00:00:00Z')),
        ],
        [0, 50, -1],
      );
    });

    test('a slot length that does not divide a day falls back to the default', () {
      expect(
        buildTimelineAxis(range('timelineDay', '2026-10-21'), 'UTC', scale: TimelineScale.tryMinutes(7)).slotMinutes,
        30,
      );
      expect(
        () => buildTimelineAxis(range('timelineDay', '2026-10-21'), 'UTC', scale: const TimelineScale.minutes(7)),
        throwsArgumentError,
      );
      expect(buildTimelineAxis(range('timelineWeek', '2026-10-21'), 'UTC', scale: TimelineScale.day).slots.length, 7);
    });
  });

  group('timeline model', () {
    test('a row per resource; an event at its true place and length; lanes for overlaps', () {
      final store = storeWith([
        EventInput(id: 'x', start: '2026-10-21T09:00[Europe/Paris]', duration: {'hours': 2}, resourceId: 'a'),
        EventInput(id: 'y', start: '2026-10-21T10:00[Europe/Paris]', duration: {'hours': 1}, resourceId: 'a'),
        EventInput(id: 'z', start: '2026-10-21T09:00[Europe/Paris]', duration: {'minutes': 30}, resourceId: 'b'),
      ]);
      final m = buildTimelineModel(range('resourceTimelineDay', '2026-10-21'), store.snapshot, opts(rows: rows()));
      final row = body(m, 0);
      // 09:00 is 18 half hours in, two hours wide (4 slots); y beside it on the second lane.
      expect(bars(row), [
        ['x', 18, 22, 0],
        ['y', 20, 22, 1],
      ]);
      expect(row.lanes, 2);
    });

    test('past maxLanes the last lane is "+N", one per stretch', () {
      final store = storeWith([
        for (final (k, t) in ['09:00', '09:00', '09:00', '09:00', '14:00'].indexed)
          EventInput(id: 'e$k', start: '2026-10-21T$t[Europe/Paris]', duration: {'hours': 1}, resourceId: 'a'),
      ]);
      final m = buildTimelineModel(
        range('resourceTimelineDay', '2026-10-21'),
        store.snapshot,
        opts(rows: rows(), maxLanes: 3),
      );
      final row = body(m, 0);
      // Lanes 0 and 1 drawn; the two others of 09:00 behind one link; 14:00 alone in lane 0.
      expect(
        [
          for (final e in row.events) [e.segment.instance.key, e.lane],
        ],
        [
          ['e0', 0],
          ['e1', 1],
          ['e4', 0],
        ],
      );
      expect(
        [
          for (final x in row.more)
            [
              x.from,
              x.to,
              [for (final e in x.events) e.segment.instance.key],
            ],
        ],
        [
          [
            18,
            20,
            ['e2', 'e3'],
          ],
        ],
      );
      expect(row.lanes, 3);
    });

    test("a resource's hours are shaded in its zone; an all-day event spans its dates in the calendar's zone", () {
      final store = storeWith([EventInput(id: 'off', start: '2026-10-21', allDay: true, resourceId: 'b')]);
      final m = buildTimelineModel(range('resourceTimelineDay', '2026-10-21'), store.snapshot, opts(rows: rows()));
      final b = body(m, 1);
      // Riyadh 08:00–12:00 is 07:00–11:00 in Paris (UTC+2 that day): shaded before 14 slots and from 22.
      expect(b.offHours, const [TimelineSpan(0, 14), TimelineSpan(22, 48)]);
      expect(
        [
          for (final e in b.events) [e.from, e.to],
        ],
        [
          [0, 48],
        ],
      );
    });

    test('"Unassigned": events on no resource or an unknown one; groups pass through', () {
      final store = storeWith([
        EventInput(id: 'none', start: '2026-10-21T09:00[Europe/Paris]'),
        EventInput(id: 'ghost', start: '2026-10-21T10:00[Europe/Paris]', resourceId: 'zz'),
        EventInput(id: 'mine', start: '2026-10-21T11:00[Europe/Paris]', resourceIds: ['zz', 'a']),
      ]);
      const un = ResourceItemRow(resource: unassignedResource, depth: 0, expanded: null);
      final m = buildTimelineModel(range('resourceTimelineDay', '2026-10-21'), store.snapshot, opts(rows: rows([un])));
      final first = m.rows[0] as TimelineResourceRow;
      expect(
        [
          first.resource.id == unassignedId,
          [for (final e in first.body.events) e.segment.instance.key],
        ],
        [
          true,
          ['none', 'ghost'],
        ],
      );
    });

    test('without resources: one row of every event, with its own lane count', () {
      final store = storeWith([
        EventInput(id: 'x', start: '2026-10-21T09:00[Europe/Paris]', resourceId: 'a'),
        EventInput(id: 'y', start: '2026-10-21T09:00[Europe/Paris]'),
      ]);
      final m = buildTimelineModel(
        range('timelineDay', '2026-10-21'),
        store.snapshot,
        const TimelineOptions(displayZone: paris, fillLanes: 5),
      );
      final row = m.rows.single as TimelineAllRow;
      expect([m.rows.length, m.maxLanes, row.body.events.length], [1, 5, 2]);
    });

    test('an update rebuilds only the rows of the resources an event left or joined', () {
      final store = storeWith([
        EventInput(id: 'x', start: '2026-10-21T09:00[Europe/Paris]', resourceId: 'a'),
        EventInput(id: 'y', start: '2026-10-21T09:00[Europe/Paris]', resourceId: 'b'),
      ]);
      final m = buildTimelineModel(range('resourceTimelineDay', '2026-10-21'), store.snapshot, opts(rows: rows()));
      final before = store.snapshot.getEvent('x')! as TimedEvent;
      final change = store.apply([
        EventMutation(
          before: before,
          after: before.copyWith(resourceIds: ['a'], title: 'moved'),
        ),
      ], ChangeCause.api);
      final next = updateTimelineModel(m, store.snapshot, change);
      expect(
        [identical(next.rows[0], m.rows[0]), identical(next.rows[1], m.rows[1]), identical(next.axis, m.axis)],
        [false, true, true],
      );
    });
  });

  group('timeline model (19j-1, by hand)', () {
    test('a marker keeps three slots of its lane for its flag; a background is under the lanes', () {
      final store = storeWith([
        EventInput(id: 'm', start: '2026-10-21T09:00[Europe/Paris]', display: EventDisplay.marker, resourceId: 'a'),
        EventInput(id: 'x', start: '2026-10-21T10:00[Europe/Paris]', resourceId: 'a'),
        EventInput(
          id: 'bg',
          start: '2026-10-21T08:00[Europe/Paris]',
          duration: {'hours': 4},
          display: EventDisplay.background,
          resourceId: 'a',
        ),
      ]);
      final m = buildTimelineModel(range('resourceTimelineDay', '2026-10-21'), store.snapshot, opts(rows: rows()));
      final row = body(m, 0);
      // The marker at 09:00 (18) reaches 18 + 3; x at 10:00 (20) meets it: lane 1.
      expect(bars(row), [
        ['m', 18, 21, 0],
        ['x', 20, 22, 1],
      ]);
      expect(
        [
          for (final e in row.background) [e.segment.instance.key, e.from, e.to],
        ],
        [
          ['bg', 16, 24],
        ],
      );
      expect(row.lanes, 2);
    });

    test("the axis's edges: cut at the start, ends exactly at it left out", () {
      final store = storeWith([
        // 22:00 the day before to 02:00 (Paris, UTC+2): the first four half hours.
        EventInput(id: 'over', start: '2026-10-20T22:00[Europe/Paris]', duration: {'hours': 4}, resourceId: 'a'),
        // Ends at midnight, where the axis starts: not shown.
        EventInput(id: 'before', start: '2026-10-20T23:00[Europe/Paris]', duration: {'hours': 1}, resourceId: 'a'),
        // Starts at midnight the next day, where the axis ends: not shown.
        EventInput(id: 'after', start: '2026-10-22T00:00[Europe/Paris]', duration: {'hours': 1}, resourceId: 'a'),
      ]);
      final m = buildTimelineModel(range('resourceTimelineDay', '2026-10-21'), store.snapshot, opts(rows: rows()));
      final row = body(m, 0);
      expect(bars(row), [
        ['over', 0, 4, 0],
      ]);
      final seg = row.events.single.segment;
      expect(
        [seg.startsHere, seg.endsHere, '${seg.from}', '${seg.to}'],
        [false, true, '2026-10-20T22:00:00Z', '2026-10-21T00:00:00Z'],
      );
    });

    test('Paris, 25 October 2026: the second 02:30 (+01:00) is two slots after the first', () {
      final store = storeWith([
        // 00:30Z is 02:30 at +02:00; 01:30Z is 02:30 again at +01:00.
        EventInput(id: 'first', start: '2026-10-25T02:30+02:00[Europe/Paris]', duration: {'minutes': 30}),
        EventInput(id: 'second', start: '2026-10-25T02:30+01:00[Europe/Paris]', duration: {'minutes': 30}),
      ]);
      final m = buildTimelineModel(
        range('timelineDay', '2026-10-25'),
        store.snapshot,
        const TimelineOptions(displayZone: paris),
      );
      // The axis starts at 22:00Z on the 24th: 2.5 h and 3.5 h in.
      expect(bars((m.rows.single as TimelineAllRow).body), [
        ['first', 5, 6, 0],
        ['second', 7, 8, 0],
      ]);
    });

    test('counted in days, a day with no open hour is shaded whole (a 25-hour Sunday 25/24 wide)', () {
      final m = buildTimelineModel(
        range('resourceTimelineWeek', '2026-10-21'),
        EventStore().snapshot,
        opts(rows: rows(), scale: TimelineScale.day, businessHours: BusinessHours.standard),
      );
      // Resource a has no hours of its own: the calendar's, Monday to Friday. The week starts Monday the 19th.
      final a = body(m, 0).offHours;
      expect(a.length, 2);
      expect([a[0].from, a[0].to, a[1].from], [5, 6, 6]);
      expect(a[1].to, closeTo(7 + 1 / 24, 1e-9));
    });

    test('the event filter hides what it does not keep', () {
      final store = storeWith([
        EventInput(id: 'keep', start: '2026-10-21T09:00[Europe/Paris]', resourceId: 'a'),
        EventInput(id: 'hide', start: '2026-10-21T09:00[Europe/Paris]', resourceId: 'a', title: 'secret'),
      ]);
      final m = buildTimelineModel(
        range('resourceTimelineDay', '2026-10-21'),
        store.snapshot,
        opts(rows: rows(), eventFilter: (e) => e.title != 'secret'),
      );
      expect(bars(body(m, 0)), [
        ['keep', 18, 20, 0],
      ]);
    });

    test('where now is: a position inside the axis, null outside', () {
      final m = buildTimelineModel(
        range('timelineDay', '2026-10-21'),
        EventStore().snapshot,
        const TimelineOptions(displayZone: paris),
      );
      // 08:15Z is 10:15 in Paris: 20.5 half hours in.
      expect(timelineNow(m, i('2026-10-21T08:15:00Z')), 20.5);
      expect(timelineNow(m, i('2026-10-21T22:00:00Z')), isNull);
    });
    test('a point of a row: a moment (its resource), a day on a day scale, nothing on a group head', () {
      final store = EventStore();
      final m = buildTimelineModel(
        range('resourceTimelineDay', '2026-10-21'),
        store.snapshot,
        opts(
          rows: [
            const GroupRow(value: 'G', count: 2, expanded: true),
            ...rows(),
          ],
        ),
      );
      // Row 1 is a; 20.5 half hours in is 10:15 in Paris (08:15Z).
      final hit = timelineHitAt(m, 1, 20.5)! as SlotHit;
      expect(['${hit.date}', '${hit.instant}', hit.resourceId], ['2026-10-21', '2026-10-21T08:15:00Z', 'a']);
      expect(timelineHitAt(m, 0, 3), isNull);
      expect(timelineHitAt(m, 9, 3), isNull);
      // Past the end: the last moment of the day, still the 21st.
      expect('${(timelineHitAt(m, 2, 99)! as SlotHit).date}', '2026-10-21');
      final week = buildTimelineModel(
        range('timelineWeek', '2026-10-21'),
        store.snapshot,
        const TimelineOptions(displayZone: paris, scale: TimelineScale.day),
      );
      // Two and a half days into the week of Monday the 19th: Wednesday.
      final day = timelineHitAt(week, 0, 2.5)! as DayHit;
      expect(['${day.date}', day.resourceId], ['2026-10-21', null]);
    });
    test('the right edge on a five-minute scale is the last moment of the day, not the next midnight', () {
      final m = buildTimelineModel(
        range('timelineDay', '2026-10-21'),
        EventStore().snapshot,
        const TimelineOptions(displayZone: paris, scale: TimelineScale.minutes(5)),
      );
      final hit = timelineHitAt(m, 0, m.axis.length + 10)! as SlotHit;
      // Midnight on the 22nd in Paris is 22:00Z on the 21st: a millisecond before it.
      expect(['${hit.date}', '${hit.instant}'], ['2026-10-21', '2026-10-21T21:59:59.999Z']);
    });

    test('a folded child changed while hidden is up to date when shown again (toggles)', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: () => i('2026-10-21T08:00:00Z'),
          initialView: 'resourceTimelineDay',
          initialDate: d('2026-10-21'),
          resources: const [
            ResourceInput(id: 'dep'),
            ResourceInput(id: 'a', parentId: 'dep'),
          ],
        ),
      );
      TimelineModel model() => (k.viewModel() as TimelineViewModel).model;
      k.toggleResourceRow('dep');
      expect([for (final r in model().rows) r.key], ['r:dep']);
      k.run(CreateEvent(EventInput(id: 'n', start: '2026-10-21T09:00[Europe/Paris]', resourceId: 'a')));
      k.toggleResourceRow('dep');
      expect(k.options.collapsedResources, isEmpty);
      expect(bars((model().rows[1] as TimelineResourceRow).body), [
        ['n', 18, 20, 0],
      ]);
      k.toggleGroupRow('x');
      expect(k.options.collapsedGroups, {'x'});
      k.dispose();
    });

    test('a model built without problems reported does not lend its rows to the shown one (a week of minutes)', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: () => i('2026-10-21T08:00:00Z'),
          initialView: 'resourceTimelineWeek',
          initialDate: d('2026-10-21'),
          resources: const [ResourceInput(id: 'a')],
          events: [
            EventInput(id: 's', start: '2026-10-21T09:00[Europe/Paris]', rrule: 'FREQ=MINUTELY', resourceId: 'a'),
          ],
        ),
      );
      k.modelAt('resourceTimelineWeek', d('2026-10-21'));
      k.viewModel();
      expect(k.viewProblems, isNotEmpty);
      k.dispose();
    });
  });

  group('timeline in the kernel', () {
    Instant now() => i('2026-10-21T08:00:00Z');
    test('the eight views are known to every kernel; rows follow the tree, its collapsed state and "Unassigned"', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: now,
          initialView: 'resourceTimelineWeek',
          resources: const [
            ResourceInput(id: 'dep'),
            ResourceInput(id: 'a', parentId: 'dep'),
            ResourceInput(id: 'b', parentId: 'dep'),
          ],
        ),
      );
      expect(timelineViews.keys.every((t) => k.viewSpec(t)?.family == 'timeline'), isTrue);
      TimelineModel model() => (k.viewModel() as TimelineViewModel).model;
      List<String> keys() => [
        for (final r in model().rows)
          switch (r) {
            TimelineResourceRow(:final resource) => resource.id.replaceAll(unassignedId, 'UN'),
            _ => r.key,
          },
      ];
      expect(keys(), ['dep', 'a', 'b']);
      k.setOptions(k.options.copyWith(collapsedResources: {'dep'}, showUnassigned: true));
      expect(keys(), ['UN', 'dep']);
      expect(model().axis.slotMinutes, 60);
      k.setOptions(k.options.copyWith(timeline: const TimelineSettings(scale: TimelineScale.day)));
      expect(model().axis.unit, TimelineUnit.day);
      k.dispose();
    });

    test('a fold keeps the rows it did not touch (same body); groups are rows', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: now,
          initialView: 'resourceTimelineDay',
          initialDate: d('2026-10-21'),
          events: [EventInput(id: 'x', start: '2026-10-21T09:00[Europe/Paris]', resourceId: 'b')],
          resources: const [
            ResourceInput(id: 'dep', fields: {'unit': 'Nord'}),
            ResourceInput(id: 'a', parentId: 'dep'),
            ResourceInput(id: 'b', fields: {'unit': 'Sud'}),
          ],
          options: const ModelOptions(resourceGroupField: 'unit'),
        ),
      );
      TimelineModel model() => (k.viewModel() as TimelineViewModel).model;
      final open = model();
      expect([for (final r in open.rows) r.key], ['g:Nord', 'r:dep', 'r:a', 'g:Sud', 'r:b']);
      k.setOptions(k.options.copyWith(collapsedResources: {'dep'}));
      final folded = model();
      expect([for (final r in folded.rows) r.key], ['g:Nord', 'r:dep', 'g:Sud', 'r:b']);
      final bOpen = open.rows[4] as TimelineResourceRow;
      final bFolded = folded.rows[3] as TimelineResourceRow;
      expect(identical(bOpen.body, bFolded.body), isTrue);
      expect(bars(bFolded.body), [
        ['x', 18, 20, 0],
      ]);
      k.setOptions(k.options.copyWith(collapsedGroups: {'Sud'}));
      final shut = model().rows.last as TimelineGroupRow;
      expect([shut.value, shut.count, shut.expanded], ['Sud', 1, false]);
      k.dispose();
    });

    test('settings no timeline can draw are refused when given, and change nothing', () {
      final k = CalendarKernel(KernelOptions(timeZone: paris, locale: 'fr-FR', now: now, initialView: 'timelineDay'));
      for (final bad in [
        const TimelineSettings(scale: TimelineScale.minutes(7)),
        const TimelineSettings(maxLanes: 0),
        const TimelineSettings(fillLanes: 0),
        const TimelineSettings(step: Duration.zero),
        const TimelineSettings(step: Duration(days: 1)),
        const TimelineSettings(span: Duration(minutes: -5)),
      ]) {
        expect(() => k.setOptions(k.options.copyWith(timeline: bad)), throwsArgumentError, reason: '$bad');
      }
      expect(k.options.timeline, const TimelineSettings());
      // Equal settings, a new object: nothing changes.
      var told = 0;
      k.subscribe((_) => told++);
      k.setOptions(k.options.copyWith(timeline: const TimelineSettings(maxLanes: 3)));
      k.setOptions(k.options.copyWith(collapsedResources: <String>{}));
      expect(told, 0);
      k.dispose();
    });

    test('a store change on one resource rebuilds its row only, through the kernel', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: now,
          initialView: 'resourceTimelineDay',
          initialDate: d('2026-10-21'),
          resources: const [
            ResourceInput(id: 'a'),
            ResourceInput(id: 'b'),
          ],
        ),
      );
      final before = (k.viewModel() as TimelineViewModel).model;
      k.run(CreateEvent(EventInput(id: 'n', start: '2026-10-21T09:00[Europe/Paris]', resourceId: 'b')));
      final after = (k.viewModel() as TimelineViewModel).model;
      expect([identical(after.rows[0], before.rows[0]), identical(after.rows[1], before.rows[1])], [true, false]);
      expect(bars((after.rows[1] as TimelineResourceRow).body), [
        ['n', 18, 20, 0],
      ]);
      k.dispose();
    });
  });
}
