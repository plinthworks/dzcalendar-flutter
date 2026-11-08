// Ported from the TypeScript core's commands.test.ts (hand-written
// expectations, copied as values).
//
// Ported: applyCommand (7), update keeps what it was not asked to change (4),
// history (11) and the 'after the 18d review' tests (4).
// Skipped: none by test. Translation notes:
// - The four 18d-review tests used `createKernel(...).run`; the kernel is not
//   ported, so they run the same commands through a History over an EventStore
//   (which is all `kernel.run` and `kernel.store` were for here).
// - 'null in a patch takes the field away': `{tone: null, url: null}` is
//   `EventPatch(clear: {EventField.tone, EventField.url})`.
// - The TS `scope: 'thisAndFollowing' as never` is built with Command.fromJson,
//   since the Dart EditScope enum cannot hold it.
// - The random-command test keeps the TS generator (a 32-bit LCG).

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

CommandContext ctx() => CommandContext(
  normalize: NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('c')),
);

List<String> codes(CommandResult r) => [
  for (final p in r.problems)
    if (p.severity == Severity.error) p.code.code,
];

String startOf(CalEvent e) => switch (e) {
  TimedEvent() => '${e.start}',
  AllDayEvent() => '${e.start}',
};

String endOf(CalEvent e) => switch (e) {
  TimedEvent() => '${e.end}',
  AllDayEvent() => '${e.end}',
};

/// The whole store as strings.
List<String> dump(StoreSnapshot snap) => [
  for (final e in snap.allEvents)
    '${e.id}|${e.title}|${startOf(e)}|${endOf(e)}|${e.revision}|${e.resourceIds.join(',')}',
];

CreateEvent create(EventInput event) => CreateEvent(event);
UpdateEvent update(String id, EventPatch patch) => UpdateEvent(id, patch);

void main() {
  group('applyCommand', () {
    test('create, then update, then delete', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      expect(h.run(create(EventInput(id: 'a', title: 'x', start: '2026-05-01T09:00[UTC]'))).ok, true);
      expect(store.snapshot.getEvent('a')!.revision, 1);
      h.run(update('a', const EventPatch(title: 'y')));
      expect(store.snapshot.getEvent('a')!.title, 'y');
      expect(store.snapshot.getEvent('a')!.revision, 2);
      expect(endOf(store.snapshot.getEvent('a')!), '2026-05-01T10:00:00+00:00[UTC]');
      h.run(const DeleteEvent('a'));
      expect(store.snapshot.getEvent('a'), isNull);
    });

    test('is pure: the snapshot it reads is not touched', () {
      final store = EventStore();
      final r = applyCommand(store.snapshot, create(EventInput(id: 'a', start: '2026-05-01')), ctx());
      expect(r.ok, true);
      expect(store.snapshot.counts.events, 0);
    });

    test('unknown-event for update and delete of a missing id', () {
      final snap = EventStore().snapshot;
      expect(codes(applyCommand(snap, update('zz', const EventPatch()), ctx())), ['unknown-event']);
      expect(codes(applyCommand(snap, const DeleteEvent('zz'), ctx())), ['unknown-event']);
    });

    test('duplicate-id on create of an existing id', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(create(EventInput(id: 'a', start: '2026-05-01')));
      expect(codes(h.run(create(EventInput(id: 'a', start: '2026-05-02'))).result), ['duplicate-id']);
    });

    test('an update that changes nothing produces no mutation and keeps the object', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(create(EventInput(id: 'a', title: 'x', start: '2026-05-01')));
      final before = store.snapshot.getEvent('a');
      final r = h.run(update('a', const EventPatch(title: 'x')));
      expect(r.ok, true);
      expect(r.result.mutations, isEmpty);
      expect(store.snapshot.getEvent('a'), same(before));
      expect(h.canUndo, true); // only the create
      h.undo();
      expect(h.canUndo, false);
    });

    test('an update keeps a guessed zone guessed, unless it moves the event', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(create(EventInput(id: 'a', start: '2026-05-01T09:00')));
      h.run(update('a', const EventPatch(title: 'renamed')));
      expect((store.snapshot.getEvent('a')! as TimedEvent).zoneGuessed, true);
      h.run(
        update('a', const EventPatch(start: '2026-05-01T10:00[Europe/Paris]', end: '2026-05-01T11:00[Europe/Paris]')),
      );
      expect((store.snapshot.getEvent('a')! as TimedEvent).zoneGuessed, false);
    });

    test('a batch is all or nothing, and each step sees the previous ones', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      final ok = h.run(
        Batch([
          create(EventInput(id: 'a', start: '2026-05-01')),
          update('a', const EventPatch(title: 'made in the same batch')),
        ]),
      );
      expect(ok.ok, true);
      expect(store.snapshot.getEvent('a')!.title, 'made in the same batch');

      final bad = h.run(Batch([create(EventInput(id: 'b', start: '2026-05-01')), const DeleteEvent('nope')]));
      expect(codes(bad.result), ['unknown-event']);
      expect(store.snapshot.getEvent('b'), isNull);
    });

    test('a source event edited by a command keeps its source', () {
      final store = EventStore();
      store.replaceSourceChunk(
        'api',
        'c',
        normalizeMany(
          [EventInput(id: 's', start: '2026-05-01')],
          ctx().normalize,
          sourceId: 'api',
        ).items,
      );
      History.reading(store, ctx).run(update('s', const EventPatch(title: 't')));
      expect(store.snapshot.getEvent('s')!.sourceId, 'api');
    });
  });

  group('update keeps what it was not asked to change', () {
    test('a new start alone keeps the length, in elapsed time across a clock change', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(
        create(EventInput(id: 'a', start: '2026-10-24T09:00[Europe/Paris]', end: '2026-10-24T11:00[Europe/Paris]')),
      );
      h.run(update('a', const EventPatch(start: '2026-10-25T01:30[Europe/Paris]')));
      final e = store.snapshot.getEvent('a')!;
      expect(startOf(e), '2026-10-25T01:30:00+02:00[Europe/Paris]');
      // Two real hours: past the repeated hour, the clock reads 02:30 the second time.
      expect(endOf(e), '2026-10-25T02:30:00+01:00[Europe/Paris]');
    });

    test('an all-day event keeps its number of days', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(create(EventInput(id: 'a', start: '2026-05-01', end: '2026-05-04')));
      h.run(update('a', const EventPatch(start: '2026-05-10')));
      expect(endOf(store.snapshot.getEvent('a')!), '2026-05-13');
    });

    test('a wall time without zone is read in the event’s zone, not the calendar’s', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(create(EventInput(id: 'a', start: '2026-05-01T09:00[Asia/Tokyo]')));
      final r = h.run(update('a', const EventPatch(start: '2026-05-01T10:00')));
      expect(startOf(store.snapshot.getEvent('a')!), '2026-05-01T10:00:00+09:00[Asia/Tokyo]');
      expect(r.result.problems, isEmpty);
    });

    test('a duration alone moves the end', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(create(EventInput(id: 'a', start: '2026-05-01T09:00[UTC]')));
      h.run(update('a', EventPatch(duration: IsoDuration(minutes: 15))));
      expect(endOf(store.snapshot.getEvent('a')!), '2026-05-01T09:15:00+00:00[UTC]');
    });
  });

  group('history', () {
    test('a revision never names two contents, even after undo', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(create(EventInput(id: 'a', title: 'A', start: '2026-05-01')));
      h.run(update('a', const EventPatch(title: 'B')));
      final b = store.snapshot.getEvent('a')!;
      h.undo();
      h.run(update('a', const EventPatch(title: 'C')));
      final c = store.snapshot.getEvent('a')!;
      expect(c.revision, isNot(b.revision));
    });

    test('a source refresh drops, at once, every entry touching what it changed — and says so', () {
      final store = EventStore();
      final n = ctx().normalize;
      store.replaceSourceChunk(
        'api',
        'c',
        normalizeMany(
          [EventInput(id: 's', title: 'v1', start: '2026-05-01')],
          n,
          sourceId: 'api',
        ).items,
      );
      final dropped = <List<String>>[];
      final h = History.reading(store, ctx, onDropped: (labels) => dropped.add([...labels]));
      h.run(create(EventInput(id: 'mine', start: '2026-05-02')));
      h.run(update('s', const EventPatch(title: 'edit 1')));
      h.run(update('s', const EventPatch(title: 'edit 2')));
      store.replaceSourceChunk(
        'api',
        'c',
        normalizeMany(
          [EventInput(id: 's', title: 'server', start: '2026-05-01')],
          n,
          sourceId: 'api',
        ).items,
      );
      expect(dropped, [
        ['event.update', 'event.update'],
      ]);
      expect(h.undo(), true); // the create, untouched by the refresh
      expect(store.snapshot.getEvent('mine'), isNull);
      expect(store.snapshot.getEvent('s')!.title, 'server');
    });

    test('a merged drag is stored as one mutation per event', () {
      final store = EventStore();
      final h = History.reading(store, ctx, mergeKey: (c) => c is UpdateEvent ? 'drag:${c.id}' : null);
      h.run(create(EventInput(id: 'a', start: '2026-05-01T09:00[UTC]')));
      for (var m = 1; m <= 40; m++) {
        h.run(update('a', EventPatch(start: '2026-05-01T09:${m.toString().padLeft(2, '0')}[UTC]')));
      }
      h.undo();
      expect(startOf(store.snapshot.getEvent('a')!), '2026-05-01T09:00:00+00:00[UTC]');
      h.redo();
      expect(startOf(store.snapshot.getEvent('a')!), '2026-05-01T09:40:00+00:00[UTC]');
    });

    test('create then delete inside one transaction leaves nothing to undo', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.transaction('noop', () {
        h.run(create(EventInput(id: 'a', start: '2026-05-01')));
        h.run(const DeleteEvent('a'));
      });
      expect(h.canUndo, false);
    });

    test('100 random commands, undone to the start and redone to the end, byte for byte', () {
      var seed = 42;
      double r() {
        seed = (seed * 1103515245 + 12345) & 0xFFFFFFFF;
        return seed / 4294967296;
      }

      String two(int x) => x.toString().padLeft(2, '0');
      final store = EventStore();
      final h = History.reading(store, ctx, limit: 1000);
      final initial = dump(store.snapshot);
      final live = <String>[];
      var ran = 0;
      var n = 0;
      while (ran < 100) {
        final pick = r();
        final Command cmd;
        if (live.isEmpty || pick < 0.45) {
          final id = 'e${n++}';
          final day = 1 + (r() * 28).floor();
          cmd = create(
            EventInput(id: id, title: 't$n', start: '2026-05-${two(day)}T${two((r() * 23).floor())}:00[Europe/Paris]'),
          );
          live.add(id);
        } else if (pick < 0.8) {
          final id = live[(r() * live.length).floor()];
          cmd = update(id, EventPatch(title: 'u${n++}', resourceIds: r() < 0.5 ? ['r1'] : []));
        } else {
          final id = live.removeAt((r() * live.length).floor());
          cmd = DeleteEvent(id);
        }
        expect(h.run(cmd).ok, true);
        ran++;
      }
      final fin = dump(store.snapshot);
      while (h.undo()) {}
      expect(dump(store.snapshot), initial);
      while (h.redo()) {}
      expect(dump(store.snapshot), fin);
    });

    test('undo restores the very same objects, so nothing re-renders for nothing', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(create(EventInput(id: 'a', start: '2026-05-01')));
      final original = store.snapshot.getEvent('a');
      h.run(update('a', const EventPatch(title: 'x')));
      h.undo();
      expect(store.snapshot.getEvent('a'), same(original));
    });

    test('a new command clears the redo stack', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(create(EventInput(id: 'a', start: '2026-05-01')));
      h.undo();
      expect(h.canRedo, true);
      h.run(create(EventInput(id: 'b', start: '2026-05-01')));
      expect(h.canRedo, false);
    });

    test('an entry overtaken by a source refresh is dropped, not replayed over it', () {
      final store = EventStore();
      final n = ctx().normalize;
      store.replaceSourceChunk(
        'api',
        'c',
        normalizeMany(
          [EventInput(id: 's', title: 'v1', start: '2026-05-01')],
          n,
          sourceId: 'api',
        ).items,
      );
      final h = History.reading(store, ctx);
      h.run(update('s', const EventPatch(title: 'mine')));
      store.replaceSourceChunk(
        'api',
        'c',
        normalizeMany(
          [EventInput(id: 's', title: 'server', start: '2026-05-01')],
          n,
          sourceId: 'api',
        ).items,
      );
      expect(h.undo(), false);
      expect(store.snapshot.getEvent('s')!.title, 'server');
      expect(h.canUndo, false);
    });

    test('transaction: several commands, one undo', () {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.transaction('import', () {
        h.run(create(EventInput(id: 'a', start: '2026-05-01')));
        h.run(create(EventInput(id: 'b', start: '2026-05-02')));
      });
      h.undo();
      expect(store.snapshot.counts.events, 0);
      expect(h.canUndo, false);
    });

    test('mergeKey: a drag of many steps undoes in one, back to where it started', () {
      final store = EventStore();
      final h = History.reading(
        store,
        ctx,
        mergeKey: (c) => c is UpdateEvent && c.patch.start != null ? 'move:${c.id}' : null,
      );
      h.run(create(EventInput(id: 'a', start: '2026-05-01T09:00[UTC]')));
      for (var hour = 10; hour < 15; hour++) {
        h.run(update('a', EventPatch(start: '2026-05-01T$hour:00[UTC]', end: '2026-05-01T${hour + 1}:00[UTC]')));
      }
      h.undo();
      expect(startOf(store.snapshot.getEvent('a')!), '2026-05-01T09:00:00+00:00[UTC]');
      h.undo();
      expect(store.snapshot.counts.events, 0);
    });

    test('limit drops the oldest entries', () {
      final store = EventStore();
      final h = History.reading(store, ctx, limit: 2);
      for (final id in ['a', 'b', 'c']) {
        h.run(create(EventInput(id: id, start: '2026-05-01')));
      }
      var undos = 0;
      while (h.undo()) {
        undos++;
      }
      expect(undos, 2);
      expect(store.snapshot.getEvent('a'), isNotNull);
    });
  });

  group('after the 18d review: what an assistant writes', () {
    // A daily series from Monday 19 October 2026 08:00 in Paris, ten days (Paris +02:00 until the 25th, +01:00 after).
    (EventStore, History) setup() {
      final store = EventStore();
      final h = History.reading(store, ctx);
      h.run(
        create(
          EventInput(
            id: 's',
            title: 'Garde',
            start: '2026-10-19T08:00[Europe/Paris]',
            duration: IsoDuration(hours: 1),
            rrule: 'FREQ=DAILY;COUNT=10',
          ),
        ),
      );
      return (store, h);
    }

    List<EventInstance> instances(EventStore store) => store.snapshot.queryInstances(
      viewWindow(PlainDate.parse('2026-10-01'), PlainDate.parse('2026-12-01'), 'Europe/Paris'),
    );
    List<String> days(EventStore store) => [for (final i in instances(store)) startOf(i.event).substring(8, 10)];

    test('a scope that is none of this, following, all is refused: nothing changes', () {
      final (store, h) = setup();
      final r = h.run(
        Command.fromJson({
          'type': 'event.delete',
          'id': 's',
          'key': '2026-10-25T08:00:00+01:00[Europe/Paris]',
          'scope': 'thisAndFollowing',
        }),
      );
      expect(
        [
          r.ok,
          r.ok ? <String>[] : [for (final p in r.result.problems) '${p.code.code} ${p.path} ${p.detail}'],
          days(store).length,
        ],
        [
          false,
          ['invalid-edit command.scope thisAndFollowing'],
          10,
        ],
      );
    });

    test('an occurrence named by its wall time without the offset, by an instant, or as series@start', () {
      final (store, h) = setup();
      // The 21st (+02:00), the 26th (+01:00: 07:00Z is 08:00 in Paris), the 27th by the instance key without its offset.
      final a = h.run(const DeleteEvent('s', key: '2026-10-21T08:00[Europe/Paris]'));
      final b = h.run(const DeleteEvent('s', key: '2026-10-26T07:00:00Z'));
      final c = h.run(const DeleteEvent('s@2026-10-27T08:00[Europe/Paris]'));
      expect(
        [a.ok, b.ok, c.ok, days(store)],
        [
          true,
          true,
          true,
          ['19', '20', '22', '23', '24', '25', '28'],
        ],
      );
    });

    test('series.split at a start written without its offset', () {
      final (store, h) = setup();
      final r = h.run(const SplitSeries('s', '2026-10-24T08:00[Europe/Paris]', patch: EventPatch(title: 'Garde B')));
      final titles = [for (final i in instances(store)) i.event.title];
      expect(
        [r.ok, titles.where((t) => t == 'Garde').length, titles.where((t) => t == 'Garde B').length],
        [true, 5, 5],
      );
    });

    test('null in a patch takes the field away', () {
      final (store, h) = setup();
      h.run(
        create(
          EventInput(
            id: 'a',
            title: 'A',
            start: '2026-10-21T09:00[Europe/Paris]',
            end: '2026-10-21T11:00[Europe/Paris]',
            tone: 'amber',
            url: 'https://example.org',
          ),
        ),
      );
      h.run(update('a', const EventPatch(clear: {EventField.tone, EventField.url})));
      final e = store.snapshot.getEvent('a')!;
      expect([e.tone, e.url], [null, null]);
    });
  });
}
