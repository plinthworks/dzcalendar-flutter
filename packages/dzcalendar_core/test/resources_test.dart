// Ported from the TypeScript core's resources.test.ts (hand-written
// expectations, copied as values).
//
// Ported: resource tree (5), rows and columns (2), rules on resources (3),
// resourceOrder after the 18j review (2).
// Skipped (what they need is not ported):
// - 'resource columns in the time grid' (4) and 'resource columns in the day
//   grid' (2): buildTimeGridModel / buildDayGridModel (the grid models, 19e).
// - '"Unassigned"' (3) and 'moving between resources' (1): proposeMove
//   (interaction) and createKernel.
// - 'kernel resources' (3): createKernel.
// Translation notes:
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
}
