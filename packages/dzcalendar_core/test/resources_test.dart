// Ported from the TypeScript core's resources.test.ts (hand-written
// expectations, copied as values).
//
// Ported: resource tree (5), rows and columns (2), rules on resources (3),
// resourceOrder after the 18j review (2), resource columns in the time grid
// (4) and in the day grid (2) (19e-1).
// '"Unassigned"' (3), 'moving between resources' (1) and 'kernel
// resources' (3) (19e-1, with proposeMove and the kernel).
// Skipped: none.
// Translation notes:
// - A kernel's `resources` are `ResourceInput`s, their own fields (`unit`,
//   `g`) in `fields`; the entry `{ title: 'none' }` the TS refuses for its
//   missing id is `ResourceInput(id: '')` (a typed input always has one).
// - `setOptions({ resourceOrder: 'title' })` is
//   `setOptions(k.options.copyWith(resourceOrder: ResourceOrder.parse('title')))`;
//   `['title']` is `ResourceOrder.fields(['title'])` — the same order.
// - `UNASSIGNED` is `unassignedId`; `rules().resources` absent is `null`.
// - Inputs the TS hands in untyped (null entries, a string for the list) go
//   through `buildResourceTreeFromJson`; typed ones through it too, as JSON
//   maps, so the problems are read the web's way.
// - `orderBy: 'title'` is `ResourceOrder.parse('title')`; a function is
//   `ResourceOrder.compare(...)` (`localeCompare` on plain ids is
//   `compareTo`).
// - A proposal `{ event, start, end, resourceIds }` is
//   `Placement(event:, proposed: event.copyWith(start:, end:, resourceIds:))`;
//   `overlap: false` is `RulesContext.noOverlap`, `constraint:
//   'businessHours'` is `ConstraintSpec.businessHours`.
// - The grids' `businessHours: { daysOfWeek, start, end }` goes through
//   `BusinessHours.fromJson`; a slot's `Temporal.Instant.from` is
//   `Instant.parse`; `c === before[i]` is `identical`.
// - 'a prototype key is no field' keeps its point in Dart: `constructor` is
//   not a field of these resources.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

const paris = 'Europe/Paris';

ResourceTree treeOf(Object? json, {ResourceOrder? orderBy}) => buildResourceTreeFromJson(json, orderBy: orderBy).tree;
List<String> ids(List<Resource> rs) => [for (final r in rs) r.id];

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

void main() {
  group('resource tree', () {
    test('orders siblings by `order`, then as given; children under their parent, depth first', () {
      final r = buildResourceTreeFromJson([
        {'id': 'c', 'title': 'Carla'},
        {'id': 'a', 'title': 'Ali', 'order': 2},
        {'id': 'b', 'title': 'Bilal', 'order': 1},
        {'id': 'd', 'title': 'Dina', 'parentId': 'b'},
        {'id': 'e', 'title': 'Emad', 'parentId': 'b', 'order': 0},
      ]);
      expect(r.problems, isEmpty);
      expect(ids(r.tree.order), ['b', 'e', 'd', 'a', 'c']);
      expect([for (final n in r.tree.roots) n.resource.id], ['b', 'a', 'c']);
      final dina = r.tree.byId['d']!;
      expect(
        [dina.depth, dina.path, dina.parent?.resource.id],
        [
          1,
          ['b', 'd'],
          'b',
        ],
      );
    });

    test('`orderBy` names fields (a leading - descends), after `order`', () {
      final inputs = [
        {'id': 'x', 'title': 'Zed'},
        {'id': 'y', 'title': 'Amy'},
        {
          'id': 'z',
          'title': 'Moe',
          'extendedProps': {'rank': 1},
        },
      ];
      expect(ids(treeOf(inputs, orderBy: ResourceOrder.parse('title')).order), ['y', 'z', 'x']);
      expect(ids(treeOf(inputs, orderBy: ResourceOrder.parse('-title')).order), ['x', 'z', 'y']);
      // A field read from extendedProps; resources without it go last, as given.
      expect(ids(treeOf(inputs, orderBy: ResourceOrder.parse('rank')).order), ['z', 'x', 'y']);
      expect(ids(treeOf(inputs, orderBy: ResourceOrder.compare((a, b) => b.id.compareTo(a.id))).order), [
        'z',
        'y',
        'x',
      ]);
    });

    test('never throws: refused entries, duplicates, unknown parents and cycles are problems', () {
      final r = buildResourceTreeFromJson([
        null,
        {'title': 'no id'},
        {'id': 'a'},
        {'id': 'a'},
        {'id': 'b', 'parentId': 'nope'},
        {'id': 'c', 'parentId': 'd'},
        {'id': 'd', 'parentId': 'c'},
        {'id': 'e', 'timeZone': 'Mars/Olympus'},
        {
          'id': 'f',
          'businessHours': {
            'daysOfWeek': [9],
            'start': '09:00',
            'end': '10:00',
          },
        },
      ]);
      expect(
        [
          for (final p in r.problems) [p.code.code, p.severity.name, p.path],
        ],
        [
          ['invalid-resource', 'error', 'resources[0]'],
          ['invalid-resource', 'error', 'resources[1].id'],
          ['duplicate-id', 'error', 'resources[3].id'],
          ['unknown-zone', 'warning', 'resources[7].timeZone'],
          ['invalid-resource', 'warning', 'resources[8].businessHours'],
          ['unknown-resource', 'warning', 'resources[4].parentId'],
          ['resource-cycle', 'warning', 'resources[5].parentId'],
        ],
      );
      // c, first of its cycle, became a root; d stays its child. The bad zone and hours are dropped.
      final tree = r.tree;
      expect(ids(tree.order), ['a', 'b', 'c', 'd', 'e', 'f']);
      expect(
        [
          tree.byId['d']!.parent?.resource.id,
          tree.byId['e']!.resource.timeZone,
          tree.byId['f']!.resource.businessHours,
        ],
        ['c', null, null],
      );
      for (final junk in <Object?>[
        null,
        'x',
        42,
        <String, Object?>{},
        [1, 'a', <Object?>[]],
      ]) {
        expect(() => buildResourceTreeFromJson(junk), returnsNormally);
      }
      expect(buildResourceTreeFromJson('x').problems.map((p) => p.code.code).toList(), ['invalid-resource']);
    });

    test('an orderBy that throws is input order, said once; a prototype key is no field', () {
      final inputs = [
        {'id': 'b'},
        {'id': 'a'},
        {'id': 'c'},
      ];
      final r = buildResourceTreeFromJson(inputs, orderBy: ResourceOrder.compare((a, b) => throw StateError('boom')));
      expect(
        [
          ids(r.tree.order),
          [for (final p in r.problems) '${p.code.code}@${p.path}'],
        ],
        [
          ['b', 'a', 'c'],
          ['invalid-resource@resourceOrder'],
        ],
      );
      // 'constructor' is not a field of these resources, so the order stays as given.
      expect(ids(treeOf(inputs, orderBy: ResourceOrder.parse('constructor')).order), ['b', 'a', 'c']);
    });

    test('a cycle above a resource is broken at its own first member, not under it', () {
      // e hangs under a, and a ⇄ b loop: a (first of the loop) becomes the root, e stays a's child.
      final r = buildResourceTreeFromJson([
        {'id': 'e', 'parentId': 'a'},
        {'id': 'a', 'parentId': 'b'},
        {'id': 'b', 'parentId': 'a'},
      ]);
      expect(
        [
          for (final p in r.problems) [p.code.code, p.path],
        ],
        [
          ['resource-cycle', 'resources[1].parentId'],
        ],
      );
      expect(
        [
          [for (final n in r.tree.roots) n.resource.id],
          r.tree.byId['e']!.parent?.resource.id,
          r.tree.byId['b']!.parent?.resource.id,
        ],
        [
          ['a'],
          'a',
          'a',
        ],
      );
    });
  });

  group('rows and columns', () {
    final tree = treeOf([
      {'id': 'card', 'title': 'Cardiology', 'unit': 'North'},
      {'id': 'ali', 'title': 'Dr Ali', 'parentId': 'card'},
      {'id': 'sara', 'title': 'Dr Sara', 'parentId': 'card'},
      {'id': 'derm', 'title': 'Dermatology', 'unit': 'South'},
      {'id': 'omar', 'title': 'Dr Omar', 'parentId': 'derm'},
      {'id': 'ent', 'title': 'ENT', 'unit': 'North'},
    ]);

    test('flattens depth first; a collapsed resource hides its subtree; a filter drops one with its subtree', () {
      List<String> rows(RowState s, [bool Function(Resource)? f]) => [
        for (final r in flattenRows(tree, s, f))
          switch (r) {
            GroupRow(:final value, :final count) => '[$value:$count]',
            ResourceItemRow(:final depth, :final resource, :final expanded) =>
              '${'  ' * depth}${resource.id}${expanded == null ? '' : (expanded ? '-' : '+')}',
          },
      ];
      expect(rows(const RowState()), ['card-', '  ali', '  sara', 'derm-', '  omar', 'ent']);
      expect(rows(const RowState(expanded: {'derm'})), ['card+', 'derm-', '  omar', 'ent']);
      expect(rows(const RowState(), (r) => r.id != 'card'), ['derm-', '  omar', 'ent']);
    });

    test('groups the roots by a field, in the order a group first comes; a collapsed group keeps its count', () {
      List<String> rows(RowState s) => [
        for (final r in flattenRows(tree, s))
          switch (r) {
            GroupRow(:final value, :final count, :final expanded) => '[$value:$count${expanded ? '' : '+'}]',
            ResourceItemRow(:final resource) => resource.id,
          },
      ];
      expect(rows(const RowState(groupBy: 'unit')), [
        '[North:4]',
        'card',
        'ali',
        'sara',
        'ent',
        '[South:2]',
        'derm',
        'omar',
      ]);
      expect(rows(const RowState(groupBy: 'unit', collapsedGroups: {'North'})), [
        '[North:4+]',
        '[South:2]',
        'derm',
        'omar',
      ]);
      final cols = columnResources(tree, 'unit');
      expect(
        [
          ids(cols.resources),
          [
            for (final g in cols.groups) {'value': g.value, 'from': g.from, 'count': g.count},
          ],
        ],
        [
          ['card', 'ali', 'sara', 'ent', 'derm', 'omar'],
          [
            {'value': 'North', 'from': 0, 'count': 4},
            {'value': 'South', 'from': 4, 'count': 2},
          ],
        ],
      );
    });
  });

  group('rules on resources', () {
    final tree = treeOf([
      {
        'id': 'riyadh',
        'timeZone': 'Asia/Riyadh',
        'businessHours': {
          'daysOfWeek': [7, 1, 2, 3, 4],
          'start': '08:00',
          'end': '12:00',
        },
        'eventConstraint': 'businessHours',
      },
      {'id': 'paris'},
      {'id': 'r1', 'eventOverlap': false},
      {'id': 'r2', 'eventOverlap': true},
      {'id': 'r3'},
    ]);
    final store = storeWith([
      EventInput(id: 'ev', start: '2026-10-21T08:00[Europe/Paris]', duration: {'minutes': 30}, resourceId: 'riyadh'),
      EventInput(id: 'x1', start: '2026-10-21T10:00[Europe/Paris]', duration: {'hours': 1}, resourceId: 'r1'),
      EventInput(id: 'x2', start: '2026-10-21T10:00[Europe/Paris]', duration: {'hours': 1}, resourceId: 'r2'),
      EventInput(id: 'x3', start: '2026-10-21T10:00[Europe/Paris]', duration: {'hours': 1}, resourceId: 'r3'),
      EventInput(id: 'mover', start: '2026-10-21T15:00[Europe/Paris]', duration: {'minutes': 30}),
    ]);
    TimedEvent ev(String id) => store.snapshot.getEvent(id)! as TimedEvent;
    Placement at(String id, String hm, List<String> resourceIds) {
      final start = ZonedDateTime.tryParse('2026-10-21T$hm[Europe/Paris]')!;
      final e = ev(id);
      return Placement(
        event: e,
        proposed: e.copyWith(start: start, end: start.add(IsoDuration(minutes: 30)), resourceIds: resourceIds),
      );
    }

    List<List<String?>> codes(
      Placement p, {
      ConstraintSpec? constraint,
      BusinessHours? businessHours,
      OverlapFn? overlap,
    }) => [
      for (final v in validateProposal(
        store.snapshot,
        p,
        RulesContext(
          displayZone: paris,
          resources: tree,
          constraint: constraint,
          businessHours: businessHours,
          overlap: overlap,
        ),
      ))
        [v.code.code, v.detail],
    ];

    test("a resource's constraint is checked against its own hours in its own zone", () {
      // 10:00–10:30 in Paris is 11:00–11:30 in Riyadh: inside 08:00–12:00.
      expect(codes(at('ev', '10:00', ['riyadh'])), isEmpty);
      // 11:00 in Paris is 12:00 in Riyadh: closed.
      expect(codes(at('ev', '11:00', ['riyadh'])), [
        ['constraint', 'riyadh'],
      ]);
    });

    test("the calendar's constraint uses each resource's hours; a resource without any uses the calendar's", () {
      final hours = BusinessHours.fromJson({
        'daysOfWeek': [1, 2, 3, 4, 5],
        'start': '09:00',
        'end': '17:00',
      }).$1;
      List<List<String?>> withRules(Placement p) =>
          codes(p, constraint: ConstraintSpec.businessHours, businessHours: hours);
      expect(withRules(at('mover', '08:30', ['paris'])), [
        ['constraint', 'paris'],
      ]);
      expect(withRules(at('mover', '09:30', ['paris'])), isEmpty);
      expect(withRules(at('mover', '13:00', ['paris'])), isEmpty);
      // Also inside the calendar's 09:00–17:00, but Riyadh's own hours close at 12:00 there (11:00 in Paris).
      expect(withRules(at('mover', '13:00', ['riyadh'])), [
        ['constraint', 'riyadh'],
      ]);
    });

    test("a resource's eventOverlap decides for the events it shares, over the calendar's", () {
      // r1 refuses overlaps even though the calendar allows them; r2 and r3 follow the calendar.
      expect(codes(at('mover', '10:30', ['r1'])), [
        ['overlap', 'x1'],
      ]);
      expect(codes(at('mover', '10:30', ['r2'])), isEmpty);
      // The calendar refuses overlaps: r2 allows its own, r3 does not.
      expect(codes(at('mover', '10:30', ['r2']), overlap: RulesContext.noOverlap), isEmpty);
      expect(codes(at('mover', '10:30', ['r3']), overlap: RulesContext.noOverlap), [
        ['overlap', 'x3'],
      ]);
    });
  });

  group('resourceOrder after the 18j review', () {
    List<String> depthFirst(List<ResourceNode> nodes) => [
      for (final n in nodes) ...[n.resource.id, ...depthFirst(n.children)],
    ];

    test('a value absent goes last in a descending order too', () {
      final tree = treeOf([
        {'id': 'none'},
        {'id': 'a', 'floor': 1},
        {'id': 'b', 'floor': 2},
      ], orderBy: ResourceOrder.parse('-floor'));
      expect(depthFirst(tree.roots), ['b', 'a', 'none']);
    });

    test('a comparison that throws: the whole tree in input order (every group), said once', () {
      var calls = 0;
      final r = buildResourceTreeFromJson(
        [
          {'id': 'z'},
          {'id': 'y', 'parentId': 'z'},
          {'id': 'x', 'parentId': 'z'},
          {'id': 'w'},
        ],
        orderBy: ResourceOrder.compare((a, b) {
          if (++calls > 1) throw StateError('boom');
          return 1;
        }),
      );
      expect(depthFirst(r.tree.roots), ['z', 'y', 'x', 'w']);
      expect([for (final p in r.problems) '${p.code.code} ${p.path}'], ['invalid-resource resourceOrder']);
    });
  });

  group('resource columns in the time grid', () {
    final resources = treeOf([
      {'id': 'paris', 'title': 'Dr Paris'},
      {
        'id': 'riyadh',
        'title': 'Dr Riyadh',
        'timeZone': 'Asia/Riyadh',
        'businessHours': {
          'daysOfWeek': [7, 1, 2, 3, 4],
          'start': '08:00',
          'end': '12:00',
        },
      },
    ]).order;
    final nav = NavContext(firstDay: 1, today: PlainDate.parse('2026-10-21'));
    final day = computeViewRange(PlainDate.parse('2026-10-21'), builtinViews['resourceTimeGridDay']!, nav);
    final week = computeViewRange(PlainDate.parse('2026-10-21'), builtinViews['resourceTimeGridWeek']!, nav);

    test('one column per resource and date, resources first; each shows its own events, a shared one in both', () {
      final store = storeWith([
        EventInput(id: 'p', start: '2026-10-21T10:00[Europe/Paris]', resourceId: 'paris'),
        EventInput(id: 'r', start: '2026-10-21T10:00[Europe/Paris]', resourceId: 'riyadh'),
        EventInput(id: 'both', start: '2026-10-21T14:00[Europe/Paris]', resourceIds: ['paris', 'riyadh']),
        EventInput(id: 'none', start: '2026-10-21T15:00[Europe/Paris]'),
      ]);
      final m = buildTimeGridModel(week, store.snapshot, TimeGridOptions(displayZone: paris, resources: resources));
      expect(m.columns.length, 14);
      expect(
        [m.columns[0].key, m.columns[6].key, m.columns[7].key],
        ['2026-10-19|paris', '2026-10-25|paris', '2026-10-19|riyadh'],
      );
      TimeGridColumn wed(int r) => m.columns[r * 7 + 2];
      expect([for (final e in wed(0).events) e.segment.instance.key]..sort(), ['both', 'p']);
      expect([for (final e in wed(1).events) e.segment.instance.key]..sort(), ['both', 'r']);
      // The shared event: a key per column, so each column's node is its own.
      String keyOf(int r) => wed(r).events.firstWhere((e) => e.segment.instance.key == 'both').segment.key;
      expect(keyOf(0), isNot(keyOf(1)));
      expect(
        [
          for (final h in m.resourceHeads) [h.resource.id, h.from, h.count],
        ],
        [
          ['paris', 0, 7],
          ['riyadh', 7, 7],
        ],
      );
    });

    test("a resource's hours are read in its zone; one without its own takes the calendar's", () {
      // Wednesday 21 October 2026: Paris is UTC+2 (summer time ends on the 25th), Riyadh UTC+3 all year.
      // Riyadh 08:00–12:00 is 05:00–09:00 UTC, 07:00–11:00 in Paris: shaded before 07:00 and from 11:00.
      final m = buildTimeGridModel(
        day,
        EventStore().snapshot,
        TimeGridOptions(
          displayZone: paris,
          resources: resources,
          businessHours: BusinessHours.fromJson({
            'daysOfWeek': [1, 2, 3, 4, 5],
            'start': '09:00',
            'end': '17:00',
          }).$1,
        ),
      );
      expect(
        [
          for (final c in m.columns)
            [
              for (final x in c.offHours) [x.top, x.height],
            ],
        ],
        [
          [
            [0, 540],
            [1020, 420],
          ],
          [
            [0, 420],
            [660, 780],
          ],
        ],
      );
    });

    test('all-day bars sit in their resource’s columns; the update rebuilds the touched resource’s column', () {
      final store = storeWith([
        EventInput(id: 'leave', start: '2026-10-20', end: '2026-10-22', allDay: true, resourceId: 'riyadh'),
        EventInput(id: 'meet', start: '2026-10-22T09:00[Europe/Paris]', resourceId: 'paris'),
      ]);
      final m = buildTimeGridModel(week, store.snapshot, TimeGridOptions(displayZone: paris, resources: resources));
      // Tuesday and Wednesday of the second resource: columns 7 + 1, two days.
      expect(
        [
          for (final b in m.allDay.bars) [b.segment.instance.key, b.column, b.segment.dayCount],
        ],
        [
          ['leave', 8, 2],
        ],
      );
      final before = [...m.columns];
      final change = store.apply([EventMutation(before: store.snapshot.getEvent('meet'))], ChangeCause.api);
      final next = updateTimeGridModel(m, store.snapshot, change);
      // Thursday's columns (one per resource) rebuilt; every other one kept as it was.
      final rebuilt = [
        for (var i = 0; i < next.columns.length; i++)
          if (!identical(next.columns[i], before[i])) next.columns[i].key,
      ];
      expect(rebuilt, ['2026-10-22|paris', '2026-10-22|riyadh']);
      expect(next.columns[3].events, isEmpty);
    });

    test("bookable slots with a resourceId show in that resource's columns only", () {
      AvailableSlot slot(String h, [String? resourceId]) => AvailableSlot(
        start: Instant.parse('2026-10-21T$h:00:00Z'),
        end: Instant.parse('2026-10-21T$h:30:00Z'),
        resourceId: resourceId,
      );
      final m = buildTimeGridModel(
        day,
        EventStore().snapshot,
        TimeGridOptions(displayZone: paris, resources: resources, availableSlots: [slot('08', 'riyadh'), slot('09')]),
      );
      expect(
        [
          for (final c in m.columns) [for (final s in c.slots) s.top],
        ],
        [
          [660],
          [600, 660],
        ],
      );
    });
  });

  group('resource columns in the day grid', () {
    final resources = treeOf([
      {'id': 'a'},
      {
        'id': 'b',
        'businessHours': {
          'daysOfWeek': [1, 2],
          'start': '09:00',
          'end': '12:00',
        },
      },
    ]).order;
    final nav = NavContext(firstDay: 1, today: PlainDate.parse('2026-10-21'));

    test('a week: every resource’s seven days in one row, bars at their resource’s cells', () {
      final range = computeViewRange(PlainDate.parse('2026-10-21'), builtinViews['resourceDayGridWeek']!, nav);
      final store = storeWith([
        EventInput(id: 'onB', start: '2026-10-21', allDay: true, resourceId: 'b'),
        EventInput(id: 'onBoth', start: '2026-10-19', end: '2026-10-21', allDay: true, resourceIds: ['a', 'b']),
      ]);
      final m = buildDayGridModel(range, store.snapshot, DayGridOptions(displayZone: paris, resources: resources));
      final w = m.weeks.first;
      expect([w.dates.length, '${w.dates[7]}', w.resources[6]?.id, w.resources[7]?.id], [14, '2026-10-19', 'a', 'b']);
      final bars = [
        for (final b in w.bars) [b.segment.instance.key, b.pieces.first.from, b.pieces.first.to],
      ]..sort((x, y) => (x[1] as int) - (y[1] as int));
      // onBoth: Monday–Tuesday of a (cells 0–1) and of b (7–8); onB: b's Wednesday (cell 9).
      expect(bars, [
        ['onBoth', 0, 2],
        ['onBoth', 7, 9],
        ['onB', 9, 10],
      ]);
      // b is closed except Monday and Tuesday; a has no hours of its own, nor the calendar: never closed.
      expect(w.closed, [false, false, false, false, false, false, false, false, false, true, true, true, true, true]);
      expect(
        [
          for (final h in m.resourceHeads) [h.resource.id, h.from, h.count],
        ],
        [
          ['a', 0, 7],
          ['b', 7, 7],
        ],
      );
    });

    test('a month: each week row holds both resources’ weeks; `firstColumn` counts cells', () {
      final range = computeViewRange(PlainDate.parse('2026-10-21'), builtinViews['resourceDayGridMonth']!, nav);
      final store = storeWith([EventInput(id: 'x', start: '2026-10-28', allDay: true, resourceId: 'b')]);
      final m = buildDayGridModel(range, store.snapshot, DayGridOptions(displayZone: paris, resources: resources));
      // Six weeks from Monday 28 September; the 28th of October is the Wednesday of the fifth.
      expect([for (final w in m.weeks) w.firstColumn], [0, 14, 28, 42, 56, 70]);
      final row = m.weeks[4];
      expect(
        [
          for (final b in row.bars) [b.segment.instance.key, b.segment.dayIndex - row.firstColumn],
        ],
        [
          ['x', 9],
        ],
      );
    });
  });

  group('"Unassigned"', () {
    Hit at(EventStore store, String id, [String? resourceId]) {
      final e = store.snapshot.getEvent(id)! as TimedEvent;
      return SlotHit(date: PlainDate(2026, 10, 21), instant: e.start.instant, resourceId: resourceId);
    }

    test('onto it: the resource taken from goes; out of it: onto the one dropped on', () {
      final store = storeWith([
        EventInput(id: 'e', start: '2026-10-21T10:00[Europe/Paris]', resourceIds: ['a', 'b']),
        EventInput(id: 'f', start: '2026-10-21T11:00[Europe/Paris]'),
      ]);
      final ctx = InteractionContext(snap: store.snapshot, displayZone: paris, snapMinutes: 15);
      CalEvent get(String id) => store.snapshot.getEvent(id)!;
      expect(proposeMove(ctx, get('e'), at(store, 'e', 'a'), at(store, 'e', unassignedId)).resourceIds, ['b']);
      expect(proposeMove(ctx, get('f'), at(store, 'f', unassignedId), at(store, 'f', 'a')).resourceIds, ['a']);
      expect(
        proposeMove(ctx, get('f'), at(store, 'f', unassignedId), at(store, 'f', unassignedId)).resourceIds,
        <String>[],
      );
    });

    test(
      'keepAllDay (a view without an all-day row): an all-day event dropped on a moment stays all-day, moved by days',
      () {
        final store = storeWith([EventInput(id: 'L', start: '2026-10-21', end: '2026-10-23', allDay: true)]);
        final ev = store.snapshot.getEvent('L')!;
        Hit slot(String iso) {
          final z = ZonedDateTime.tryParse(iso)!;
          return SlotHit(date: z.date, instant: z.instant);
        }

        final x = proposeMove(
          InteractionContext(snap: store.snapshot, displayZone: paris, snapMinutes: 15, keepAllDay: true),
          ev,
          slot('2026-10-21T09:00[Europe/Paris]'),
          slot('2026-10-24T15:00[Europe/Paris]'),
        );
        final moved = x.proposed as AllDayEvent;
        expect([x.allDay, '${moved.start}', '${moved.end}'], [true, '2026-10-24', '2026-10-26']);
        // Without it (a time grid's hours), it becomes timed: the grid has an all-day row for days.
        expect(
          proposeMove(
            InteractionContext(snap: store.snapshot, displayZone: paris, snapMinutes: 15),
            ev,
            slot('2026-10-21T09:00[Europe/Paris]'),
            slot('2026-10-24T15:00[Europe/Paris]'),
          ).allDay,
          isFalse,
        );
      },
    );

    test('showUnassigned puts the column first in resource views; it shows events on no known resource', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'en-GB',
          now: () => Instant.parse('2026-10-21T08:00:00Z'),
          initialView: 'resourceTimeGridDay',
          resources: const [
            ResourceInput(id: 'a', fields: {'g': 'x'}),
          ],
          options: const ModelOptions(resourceGroupField: 'g', showUnassigned: true),
          events: [
            EventInput(id: 'n', start: '2026-10-21T09:00[Europe/Paris]'),
            EventInput(id: 'z', start: '2026-10-21T10:00[Europe/Paris]', resourceId: 'zz'),
            EventInput(id: 'y', start: '2026-10-21T11:00[Europe/Paris]', resourceId: 'a'),
          ],
        ),
      );
      final m = (k.viewModel() as TimeGridViewModel).model;
      expect(
        [
          [for (final c in m.columns) c.resource?.id == unassignedId],
          [for (final e in m.columns[0].events) e.segment.instance.key],
          [for (final g in m.groupHeads) '${g.value} ${g.from} ${g.count}'],
        ],
        [
          [true, false],
          ['n', 'z'],
          ['x 1 1'],
        ],
      );
    });
  });

  group('moving between resources', () {
    final store = storeWith([
      EventInput(id: 'e', start: '2026-10-21T10:00[Europe/Paris]', resourceIds: ['a', 'b']),
    ]);
    final ev = store.snapshot.getEvent('e')! as TimedEvent;
    final ctx = InteractionContext(snap: store.snapshot, displayZone: paris, snapMinutes: 15);
    Hit hit([String? resourceId]) =>
        SlotHit(date: PlainDate(2026, 10, 21), instant: ev.start.instant, resourceId: resourceId);

    test('the resource grabbed on is swapped for the one under the pointer; the others stay', () {
      expect(proposeMove(ctx, ev, hit('a'), hit('c')).resourceIds, ['c', 'b']);
      // Onto its other resource: the two become one.
      expect(proposeMove(ctx, ev, hit('a'), hit('b')).resourceIds, ['b']);
      expect(proposeMove(ctx, ev, hit('a'), hit('a')).resourceIds, ['a', 'b']);
      // Grabbed outside a resource column, dropped on one: that one alone.
      expect(proposeMove(ctx, ev, hit(), hit('c')).resourceIds, ['c']);
      // Over no resource (a plain view): unchanged.
      expect(proposeMove(ctx, ev, hit('a'), hit()).resourceIds, ['a', 'b']);
    });
  });

  group('kernel resources', () {
    Instant now() => Instant.parse('2026-10-21T08:00:00Z');
    const inputs = [
      ResourceInput(id: 'b', title: 'Bilal', fields: {'unit': 'South'}),
      ResourceInput(id: 'a', title: 'Ali', fields: {'unit': 'North'}),
    ];

    test('a resource view gets the resources as columns; setResources redraws, with cause "resources"', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'en-GB',
          now: now,
          initialView: 'resourceTimeGridDay',
          resources: inputs,
          options: ModelOptions(resourceOrder: ResourceOrder.parse('title'), resourceGroupField: 'unit'),
        ),
      );
      TimeGridModel m() => (k.viewModel() as TimeGridViewModel).model;
      expect(
        [
          [for (final c in m().columns) c.key],
          [for (final g in m().groupHeads) '${g.value} ${g.from} ${g.count}'],
        ],
        [
          ['2026-10-21|a', '2026-10-21|b'],
          ['North 0 1', 'South 1 1'],
        ],
      );
      final seen = <KernelEvent>[];
      k.subscribe(seen.add);
      final problems = k.setResources(const [
        ResourceInput(id: 'c', title: 'Carla'),
        ResourceInput(id: '', title: 'none'),
      ]);
      expect(
        [
          [for (final p in problems) p.code.code],
          k.resourceProblems.length,
          ids(k.resources.order),
        ],
        [
          ['invalid-resource'],
          1,
          ['c'],
        ],
      );
      expect(
        [for (final e in seen) e is KernelStateEvent ? e.causes : 'store'],
        [
          [StateCause.resources],
        ],
      );
      expect([for (final c in m().columns) c.key], ['2026-10-21|c']);
      expect(k.rules().resources?.byId.containsKey('c'), isTrue);
    });

    test('another order or group field rebuilds the columns; the same one changes nothing', () {
      final k = CalendarKernel(
        KernelOptions(timeZone: paris, locale: 'en-GB', now: now, initialView: 'resourceDayGridDay', resources: inputs),
      );
      List<String> keys() => [for (final h in (k.viewModel() as DayGridViewModel).model.resourceHeads) h.resource.id];
      expect(keys(), ['b', 'a']);
      var states = 0;
      k.subscribe((e) {
        if (e is KernelStateEvent) states++;
      });
      k.setOptions(k.options.copyWith(resourceOrder: ResourceOrder.parse('title')));
      expect(keys(), ['a', 'b']);
      k.setOptions(k.options.copyWith(resourceOrder: ResourceOrder.fields(['title'])));
      expect(states, 1);
    });

    test('a plain view ignores the resources; without any, rules carry none', () {
      final k = CalendarKernel(
        KernelOptions(timeZone: paris, locale: 'en-GB', now: now, initialView: 'timeGridDay', resources: inputs),
      );
      expect([for (final c in (k.viewModel() as TimeGridViewModel).model.columns) c.key], ['2026-10-21']);
      expect(CalendarKernel(KernelOptions(timeZone: paris, locale: 'en-GB', now: now)).rules().resources, isNull);
    });
  });
}
