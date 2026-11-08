// Ported from the TypeScript core's store.test.ts (hand-written expectations,
// copied as values).
//
// Ported: queryInstances (7), snapshots and changes (5), sources: chunks,
// revisions, stable ids (7), and the normalizeMany ids test.
// Skipped, not in the port:
// - 'loadStaticSource puts an array source in the store, with its defaults'
//   (needs arraySource and loadStaticSource: sources are not ported)
// - 'refuses a chunked or asynchronous source, which the manager will handle'
//   (needs loadStaticSource)

import 'dart:convert';

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

NormalizeContext ctx() => NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('t'));

CalEvent ev(EventInput input) {
  final r = normalizeEvent(input, ctx());
  if (!r.ok) fail('${r.problems}');
  return r.value!.event;
}

PlainDate d(String s) => PlainDate.parse(s);
List<String> ids(List<EventInstance> xs) => [for (final x in xs) x.key];
List<Normalized> items(List<EventInput> inputs, [String source = 'api']) =>
    normalizeMany(inputs, ctx(), sourceId: source).items;

List<EventInput> fromJson(String text) => [
  for (final m in jsonDecode(text) as List) EventInput.fromJson(m as Map<String, Object?>),
];

void main() {
  group('queryInstances', () {
    final store = EventStore();
    store.apply([
      for (final after in [
        ev(
          EventInput(
            id: 'morning',
            title: 'B',
            start: '2026-10-26T09:00[Europe/Paris]',
            end: '2026-10-26T10:00[Europe/Paris]',
          ),
        ),
        ev(
          EventInput(
            id: 'long',
            title: 'A',
            start: '2026-10-26T09:00[Europe/Paris]',
            end: '2026-10-26T12:00[Europe/Paris]',
          ),
        ),
        // 08:00 in Tokyo (+09:00) is 23:00Z, midnight Monday in Paris, which is +01:00 since Sunday.
        ev(EventInput(id: 'tokyo', start: '2026-10-26T08:00[Asia/Tokyo]')),
        ev(EventInput(id: 'allday', start: '2026-10-26')),
        ev(EventInput(id: 'trip', start: '2026-10-20', end: '2026-10-30')),
        ev(EventInput(id: 'milestone', start: '2026-10-26T15:00[UTC]', end: '2026-10-26T15:00[UTC]')),
        ev(EventInput(id: 'hidden', start: '2026-10-26T09:00[UTC]', display: EventDisplay.none)),
        ev(EventInput(id: 'bg', start: '2026-10-26T09:00[UTC]', display: EventDisplay.background)),
        ev(EventInput(id: 'nextday', start: '2026-10-27T00:00[Europe/Paris]')),
        ev(EventInput(id: 'room', start: '2026-10-26T13:00[UTC]', resourceIds: ['r1'])),
      ])
        EventMutation(after: after),
    ], ChangeCause.api);
    final monday = viewWindow(d('2026-10-26'), d('2026-10-27'), 'Europe/Paris');

    test('finds timed events by instant, all-day ones by date, and orders them', () {
      expect(ids(store.snapshot.queryInstances(monday)), [
        // all-day first only because they start at midnight; longer first; then title
        'trip', 'allday', 'tokyo', 'long', 'morning', 'bg', 'room', 'milestone',
      ]);
    });

    test('a window is half-open: the next day’s midnight is not in it', () {
      expect(ids(store.snapshot.queryInstances(monday)), isNot(contains('nextday')));
    });

    test('a milestone is found inside its window', () {
      expect(ids(store.snapshot.queryInstances(monday)), contains('milestone'));
    });

    test('display none is never returned; background on request', () {
      expect(
        ids(store.snapshot.queryInstances(monday, const QueryOptions(includeBackground: false))),
        isNot(contains('bg')),
      );
    });

    test('by resource, only that resource’s events', () {
      expect(ids(store.snapshot.queryInstances(monday, const QueryOptions(resourceId: 'r1'))), ['room']);
      expect(store.snapshot.queryInstances(monday, const QueryOptions(resourceId: 'nobody')), isEmpty);
    });

    test(
      'the same instant on a different display day: Tokyo’s 08:00 is Monday 00:00 in Paris, Sunday 18:00 in Chicago',
      () {
        final sundayChicago = viewWindow(d('2026-10-25'), d('2026-10-26'), 'America/Chicago');
        expect(ids(store.snapshot.queryInstances(sundayChicago)), contains('tokyo'));
      },
    );

    test('the 25-hour Sunday in Paris is a 25-hour window', () {
      final w = viewWindow(d('2026-10-25'), d('2026-10-26'), 'Europe/Paris');
      expect((w.end.epochMilliseconds - w.start.epochMilliseconds) / 3600000, 25);
    });
  });

  group('snapshots and changes', () {
    test('an old snapshot never sees later changes', () {
      final store = EventStore();
      store.apply([
        EventMutation(
          after: ev(EventInput(id: 'a', start: '2026-05-01')),
        ),
      ], ChangeCause.api);
      final before = store.snapshot;
      store.apply([
        EventMutation(
          before: before.getEvent('a'),
          after: ev(EventInput(id: 'a', title: 'moved', start: '2026-05-03')),
        ),
      ], ChangeCause.api);
      store.apply([
        EventMutation(
          after: ev(EventInput(id: 'b', start: '2026-05-02')),
        ),
      ], ChangeCause.api);
      expect('${(before.getEvent('a')! as AllDayEvent).start}', '2026-05-01');
      expect(before.getEvent('b'), isNull);
      expect(before.queryInstances(viewWindow(d('2026-05-03'), d('2026-05-04'), 'UTC')), isEmpty);
      expect(store.snapshot.counts.events, 2);
    });

    test('reports net changes and the old and new places as dirty', () {
      final store = EventStore();
      final a1 = ev(EventInput(id: 'a', start: '2026-05-01T09:00[UTC]'));
      store.apply([EventMutation(after: a1)], ChangeCause.api);
      final seen = <StoreChange>[];
      store.subscribe(seen.add);
      final a2 = ev(EventInput(id: 'a', start: '2026-05-01T15:00[UTC]'));
      final change = store.apply([EventMutation(before: a1, after: a2)], ChangeCause.command);
      expect(change.added, isEmpty);
      expect(change.updated, ['a']);
      expect(change.removed, isEmpty);
      expect(change.cause, ChangeCause.command);
      int h(String s) => Instant.parse(s).epochMilliseconds;
      expect(change.dirtySpans, [
        MsSpan(h('2026-05-01T09:00Z'), h('2026-05-01T10:00Z')),
        MsSpan(h('2026-05-01T15:00Z'), h('2026-05-01T16:00Z')),
      ]);
      expect(seen, hasLength(1));
    });

    test('a batch that changes nothing notifies no one and keeps the version', () {
      final store = EventStore();
      final a = ev(EventInput(id: 'a', start: '2026-05-01'));
      store.apply([EventMutation(after: a)], ChangeCause.api);
      final v = store.snapshot.version;
      var calls = 0;
      store.subscribe((_) => calls++);
      final change = store.apply([EventMutation(before: a, after: a)], ChangeCause.api);
      expect(change.version, v);
      expect(store.snapshot.version, v);
      expect(calls, 0);
    });

    test('add then remove in one batch is no change at all', () {
      final store = EventStore();
      final a = ev(EventInput(id: 'a', start: '2026-05-01'));
      final change = store.apply([EventMutation(after: a), EventMutation(before: a)], ChangeCause.api);
      expect([change.added, change.removed], [<String>[], <String>[]]);
    });

    test('a resource event moved to another resource leaves the first resource’s index', () {
      final store = EventStore();
      final a1 = ev(EventInput(id: 'a', start: '2026-05-01', resourceIds: ['r1']));
      store.apply([EventMutation(after: a1)], ChangeCause.api);
      store.apply([
        EventMutation(
          before: a1,
          after: ev(EventInput(id: 'a', start: '2026-05-01', resourceIds: ['r2'])),
        ),
      ], ChangeCause.api);
      final w = viewWindow(d('2026-05-01'), d('2026-05-02'), 'UTC');
      expect(store.snapshot.queryInstances(w, const QueryOptions(resourceId: 'r1')), isEmpty);
      expect(ids(store.snapshot.queryInstances(w, const QueryOptions(resourceId: 'r2'))), ['a']);
    });
  });

  group('sources: chunks, revisions, stable ids', () {
    final window = viewWindow(d('2026-05-01'), d('2026-06-01'), 'UTC');

    test('an event without id gets the same id on every refetch, and keeps its object when unchanged', () {
      final store = EventStore();
      final raw = [EventInput(title: 'standup', start: '2026-05-04T09:00[UTC]')];
      store.replaceSourceChunk('api', '2026-05', items(raw));
      final first = store.snapshot.queryInstances(window)[0].event;
      expect(first.id, matches(RegExp(r'^api:')));
      expect(first.revision, 1);
      final change = store.replaceSourceChunk('api', '2026-05', items(raw));
      expect([change.added, change.updated, change.removed], [<String>[], <String>[], <String>[]]);
      expect(store.snapshot.queryInstances(window)[0].event, same(first));
    });

    test('a changed title from the source is an update, with a higher revision', () {
      final store = EventStore();
      store.replaceSourceChunk('api', 'c', items([EventInput(id: 'x', title: 'old', start: '2026-05-04')]));
      final first = store.snapshot.getEvent('x')!.revision;
      final change = store.replaceSourceChunk(
        'api',
        'c',
        items([EventInput(id: 'x', title: 'new', start: '2026-05-04')]),
      );
      expect(change.updated, ['x']);
      expect(store.snapshot.getEvent('x')!.revision, greaterThan(first));
      expect(store.snapshot.getEvent('x')!.sourceId, 'api');
    });

    test('a refetch with nested extendedProps, parsed afresh, is a no-op', () {
      final store = EventStore();
      List<EventInput> raw() => fromJson('[{"id":"x","start":"2026-05-04","extendedProps":{"room":{"floor":2}}}]');
      store.replaceSourceChunk('api', 'c', items(raw()));
      final kept = store.snapshot.getEvent('x');
      final change = store.replaceSourceChunk('api', 'c', items(raw()));
      expect(change.updated, isEmpty);
      expect(store.snapshot.getEvent('x'), same(kept));
    });

    test('an event evicted and delivered again never reuses a revision for other content', () {
      final store = EventStore();
      store.replaceSourceChunk('api', 'c', items([EventInput(id: 'x', title: 'one', start: '2026-05-04')]));
      final r1 = store.snapshot.getEvent('x')!.revision;
      store.replaceSourceChunk('api', 'c', []);
      store.replaceSourceChunk('api', 'c', items([EventInput(id: 'x', title: 'two', start: '2026-05-04')]));
      expect(store.snapshot.getEvent('x')!.revision, isNot(r1));
    });

    test('the store stamps what it is given: an apply cannot slip in a stale revision', () {
      final store = EventStore();
      store.apply([
        EventMutation(
          after: ev(EventInput(id: 'a', start: '2026-05-01')),
        ),
      ], ChangeCause.api);
      final stale = ev(EventInput(id: 'a', title: 'x', start: '2026-05-01')).withRevision(1);
      final change = store.apply([EventMutation(after: stale)], ChangeCause.api);
      expect(store.snapshot.getEvent('a')!.revision, change.version);
      expect(change.applied[0].after, same(store.snapshot.getEvent('a')));
    });

    test('two identical events in one batch are both kept, told apart by rank', () {
      final store = EventStore();
      final raw = [EventInput(title: 'x', start: '2026-05-04'), EventInput(title: 'x', start: '2026-05-04')];
      store.replaceSourceChunk('api', 'c', items(raw));
      expect(store.snapshot.counts.events, 2);
    });

    test('an event overlapping two chunks belongs to both, and goes only when both drop it', () {
      final store = EventStore();
      final spanning = EventInput(id: 'trip', start: '2026-05-30', end: '2026-06-03');
      store.replaceSourceChunk('api', '2026-05', items([spanning]));
      store.replaceSourceChunk('api', '2026-06', items([spanning]));
      expect(store.replaceSourceChunk('api', '2026-05', []).removed, isEmpty);
      expect(store.snapshot.getEvent('trip'), isNotNull);
      expect(store.replaceSourceChunk('api', '2026-06', []).removed, ['trip']);
    });

    test('a source cannot overwrite an event it does not own', () {
      final store = EventStore();
      store.apply([
        EventMutation(
          after: ev(EventInput(id: 'mine', start: '2026-05-04')),
        ),
      ], ChangeCause.command);
      final change = store.replaceSourceChunk(
        'api',
        'c',
        items([EventInput(id: 'mine', title: 'hijack', start: '2026-05-05')]),
      );
      expect([for (final p in change.problems) p.code.code], ['duplicate-id']);
      expect(store.snapshot.getEvent('mine')!.title, '');
    });
  });

  test('normalizeMany ids: same input, same id, across calls', () {
    final a = items([EventInput(title: 'x', start: '2026-05-04T09:00[UTC]')]);
    final b = items([EventInput(title: 'x', start: '2026-05-04T09:00[UTC]')]);
    expect(a[0].event.id, b[0].event.id);
    expect(items([EventInput(title: 'y', start: '2026-05-04T09:00[UTC]')])[0].event.id, isNot(a[0].event.id));
  });
}
