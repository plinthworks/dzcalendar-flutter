// Ported from the TypeScript core's series-edit.test.ts (hand-written
// expectations, copied as values).
//
// Skipped, with the reason (calendar rules / validateProposal / constraints /
// kernel are not ported):
// - 'move, resize, and the rules': 'overlap: false refuses a move onto another
//   event', 'not-editable: an event whose start may not move', 'constraint:
//   business hours', 'allow has the last word' (CommandContext.rules,
//   violations). 'move keeps the length; resize keeps the other edge' is kept.
// - 'fixed after the Phase 6 reviews': 'rules: an all-day move onto the 25-hour
//   day is still one day long' and 'rules: moving a whole series does not
//   collide with its own occurrences' (both only check the rules' verdict);
//   'the kernel validates gestures only' (createKernel).
// - 'after the 16a reviews': 'a creation checked against the rules (a
//   person's)' (overlap rule).
// - 'after the 16a code review: a series meets the rules on all its
//   occurrences': 'A made daily ... refused' and 'a new series whose second
//   occurrence is on B ... refused' (overlap rule). The third test of that
//   group (a rule that can never give an occurrence) is kept.

import 'package:dzcalendar_core/internal.dart';
// Not exported by the library: the tests read a recurrence key as a moment.
import 'package:test/test.dart';

const P = '[Europe/Paris]';

CommandContext ctx({int? weekStart}) => CommandContext(
  normalize: NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('n')),
  weekStart: weekStart,
);

ViewWindow win(String from, String to) => viewWindow(PlainDate.parse(from), PlainDate.parse(to), 'Europe/Paris');

typedef Setup = ({EventStore store, History h, CommandContext c});

/// Six Mondays at 09:00-10:00 Paris from 5 October 2026: 5, 12, 19, 26 October (after the clocks change), 2, 9 November.
Setup weekly({String rrule = 'FREQ=WEEKLY;COUNT=6', List<Object?>? exdate, String? url}) {
  final store = EventStore();
  final c = ctx();
  final h = History.reading(store, () => c);
  final r = h.run(
    CreateEvent(
      EventInput(
        id: 'w',
        title: 'Weekly',
        start: '2026-10-05T09:00$P',
        end: '2026-10-05T10:00$P',
        rrule: rrule,
        exdate: exdate,
        url: url,
      ),
    ),
  );
  if (!r.ok) throw StateError('${r.result.problems}');
  return (store: store, h: h, c: c);
}

String K(String date, [String off = '+02:00']) => '${date}T09:00:00$off$P';

Object startOf(CalEvent e) => switch (e) {
  TimedEvent(:final start) => start,
  AllDayEvent(:final start) => start,
};

Object endOf(CalEvent e) => switch (e) {
  TimedEvent(:final end) => end,
  AllDayEvent(:final end) => end,
};

List<String> shownIn(EventStore store, String from, String to) => [
  for (final i in store.snapshot.queryInstances(win(from, to))) '${i.origin.name}:${i.event.title}:${startOf(i.event)}',
];

/// The original series and the one cut from it.
(Series, Series) split(EventStore store) {
  final xs = store.snapshot.allSeries.toList();
  return (xs.firstWhere((s) => s.id == 'w'), xs.firstWhere((s) => s.id != 'w'));
}

List<String> all(EventStore store) => shownIn(store, '2026-09-28', '2026-12-31');

/// Everything in the store, as strings.
List<String> dump(StoreSnapshot snap) => [
  for (final e in snap.allEvents)
    'E ${e.id} ${e.title} ${startOf(e)} ${endOf(e)} ${e.ref != null ? '${e.ref!.seriesId}@${e.ref!.key}' : ''}',
  for (final s in snap.allSeries)
    'S ${s.id} ${s.base is TimedEvent ? (s.base as TimedEvent).start : (s.base as AllDayEvent).start} '
        '${s.set.rules.map(serializeRRule).join('|')} ex:${s.set.exdates.join(',')} '
        'ov:${[for (final e in s.overrides.entries) '${e.key},${e.value}'].join(',')} '
        '${s.splitFrom != null ? 'from:${s.splitFrom!.seriesId}@${s.splitFrom!.at}' : ''}',
];

List<String> codesOf(List<Problem> ps) => [for (final p in ps) p.code.code];

String rule0(Series s) => serializeRRule(s.set.rules[0]);

void main() {
  group('this', () {
    test('moves one occurrence; the override is found at its new place, even in another week', () {
      final (:store, :h, c: _) = weekly();
      final r = h.run(MoveEvent('w', '2026-10-28T14:00$P', key: K('2026-10-19'), scope: EditScope.this_));
      expect(r.ok, isTrue);
      expect(shownIn(store, '2026-10-19', '2026-10-26'), isEmpty);
      expect(shownIn(store, '2026-10-26', '2026-11-02'), [
        'occurrence:Weekly:2026-10-26T09:00:00+01:00$P',
        'override:Weekly:2026-10-28T14:00:00+01:00$P',
      ]);
      final ov = store.snapshot.queryInstances(win('2026-10-28', '2026-10-29'))[0].event;
      expect('${endOf(ov)}', '2026-10-28T15:00:00+01:00$P');
      expect(ov.ref, EventRef('w', K('2026-10-19')));
    });

    test('an occurrence key as id means "this"; editing it again edits the override, no second one', () {
      final (:store, :h, c: _) = weekly();
      h.run(UpdateEvent('w@${K('2026-10-12')}', const EventPatch(title: 'Moved')));
      h.run(UpdateEvent('w@${K('2026-10-12')}', const EventPatch(title: 'Renamed')));
      final sr = store.snapshot.getSeries('w')!;
      expect([sr.overrides.length, store.snapshot.counts.events], [1, 1]);
      expect(shownIn(store, '2026-10-12', '2026-10-13'), ['override:Renamed:${K('2026-10-12')}']);
    });

    test('deleting one occurrence is an EXDATE; COUNT still counts it', () {
      final (:store, :h, c: _) = weekly();
      h.run(DeleteEvent('w', key: K('2026-10-12'), scope: EditScope.this_));
      expect(all(store), hasLength(5));
      expect([for (final e in store.snapshot.getSeries('w')!.set.exdates) '$e'], ['2026-10-12T07:00:00Z']);
    });

    test('deleting an override deletes the occurrence: event gone, EXDATE added', () {
      final (:store, :h, c: _) = weekly();
      h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'x'),
          key: K('2026-10-12'),
          scope: EditScope.this_,
        ),
      );
      final ovId = store.snapshot.getSeries('w')!.overrides[K('2026-10-12')]!;
      h.run(DeleteEvent(ovId));
      expect(
        [store.snapshot.counts.events, store.snapshot.getSeries('w')!.overrides.length, all(store).length],
        [0, 0, 5],
      );
    });

    test('a key that is not an occurrence is refused', () {
      final (:store, h: _, :c) = weekly();
      final r = applyCommand(
        store.snapshot,
        UpdateEvent(
          'w',
          const EventPatch(title: 'x'),
          key: K('2026-10-13'),
          scope: EditScope.this_,
        ),
        c,
      );
      expect(codesOf(r.problems), contains('unknown-occurrence'));
    });

    test(
      'an override changes only its own place: the series is not touched, the other occurrences are the same objects',
      () {
        final (:store, :h, c: _) = weekly();
        final before = store.snapshot.queryInstances(win('2026-11-02', '2026-11-03'))[0].event;
        final changes = <StoreChange>[];
        store.subscribe(changes.add);
        h.run(
          UpdateEvent(
            'w',
            const EventPatch(title: 'x'),
            key: K('2026-10-12'),
            scope: EditScope.this_,
          ),
        );
        expect(
          [changes[0].seriesTouched, changes[0].seriesChanged, changes[0].dirtySpans.isNotEmpty],
          [
            <String>[],
            ['w'],
            true,
          ],
        );
        expect(identical(store.snapshot.queryInstances(win('2026-11-02', '2026-11-03'))[0].event, before), isTrue);
      },
    );
  });

  group('all', () {
    test(
      'moving one occurrence a day later and an hour later moves them all, COUNT kept, wall time across the clock change',
      () {
        final (:store, :h, c: _) = weekly();
        h.run(MoveEvent('w', '2026-10-20T10:00$P', key: K('2026-10-19'), scope: EditScope.all));
        expect(all(store), [
          'occurrence:Weekly:2026-10-06T10:00:00+02:00$P',
          'occurrence:Weekly:2026-10-13T10:00:00+02:00$P',
          'occurrence:Weekly:2026-10-20T10:00:00+02:00$P',
          'occurrence:Weekly:2026-10-27T10:00:00+01:00$P',
          'occurrence:Weekly:2026-11-03T10:00:00+01:00$P',
          'occurrence:Weekly:2026-11-10T10:00:00+01:00$P',
        ]);
      },
    );

    test('a weekly Monday/Wednesday rule moved from a Monday to a Tuesday becomes Tuesday/Thursday', () {
      final (:store, :h, c: _) = weekly(rrule: 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4');
      h.run(MoveEvent('w', '2026-10-06T09:00$P', key: K('2026-10-05'), scope: EditScope.all));
      expect(rule0(store.snapshot.getSeries('w')!), 'FREQ=WEEKLY;COUNT=4;BYDAY=TU,TH');
      expect(
        [for (final x in all(store)) RegExp(r':(\d{4}-\d{2}-\d{2})T').firstMatch(x)![1]],
        ['2026-10-06', '2026-10-08', '2026-10-13', '2026-10-15'],
      );
    });

    test('keys follow the series: an override and an EXDATE move with it', () {
      final (:store, :h, c: _) = weekly();
      h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'Special'),
          key: K('2026-10-12'),
          scope: EditScope.this_,
        ),
      );
      h.run(DeleteEvent('w', key: K('2026-11-02', '+01:00'), scope: EditScope.this_));
      h.run(MoveEvent('w', '2026-10-05T11:00$P', key: K('2026-10-05'), scope: EditScope.all));
      final sr = store.snapshot.getSeries('w')!;
      expect(sr.overrides.keys.toList(), ['2026-10-12T11:00:00+02:00$P']);
      expect([for (final e in sr.set.exdates) '$e'], ['2026-11-02T10:00:00Z']);
      final ov = store.snapshot.getEvent(sr.overrides['2026-10-12T11:00:00+02:00$P']!)!;
      expect(ov.ref!.key, '2026-10-12T11:00:00+02:00$P');
      // The override keeps its own time (it was only renamed); the series moved around it.
      expect(all(store).where((x) => x.contains('Special')).toList(), ['override:Special:${K('2026-10-12')}']);
      expect(all(store), hasLength(5));
    });

    test('a title for all keeps every occurrence where it is', () {
      final (:store, :h, c: _) = weekly();
      h.run(UpdateEvent('w', const EventPatch(title: 'Renamed')));
      expect(all(store).every((x) => x.contains(':Renamed:')), isTrue);
      expect(all(store), hasLength(6));
    });

    test('switching every occurrence to all-day is refused (invalid-edit)', () {
      final (:store, h: _, :c) = weekly();
      final r = applyCommand(store.snapshot, UpdateEvent('w', const EventPatch(allDay: true), scope: EditScope.all), c);
      expect(codesOf(r.problems), contains('invalid-edit'));
    });
  });

  group('following', () {
    test('splits with COUNT shared: three before, three after at the new time, splitFrom set', () {
      final (:store, :h, c: _) = weekly();
      h.run(MoveEvent('w', '2026-10-26T11:00$P', key: K('2026-10-26', '+01:00'), scope: EditScope.following));
      expect(all(store), [
        'occurrence:Weekly:${K('2026-10-05')}',
        'occurrence:Weekly:${K('2026-10-12')}',
        'occurrence:Weekly:${K('2026-10-19')}',
        'occurrence:Weekly:2026-10-26T11:00:00+01:00$P',
        'occurrence:Weekly:2026-11-02T11:00:00+01:00$P',
        'occurrence:Weekly:2026-11-09T11:00:00+01:00$P',
      ]);
      final (a, b) = split(store);
      expect([rule0(a), rule0(b)], ['FREQ=WEEKLY;COUNT=3', 'FREQ=WEEKLY;COUNT=3']);
      expect(b.splitFrom, SplitFrom('w', K('2026-10-26', '+01:00')));
    });

    test('with UNTIL: the first ends at the last start before the cut, the second keeps UNTIL', () {
      final (:store, :h, c: _) = weekly(rrule: 'FREQ=WEEKLY;UNTIL=20261110T000000Z');
      h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'Later'),
          key: K('2026-10-19'),
          scope: EditScope.following,
        ),
      );
      final (a, b) = split(store);
      expect([rule0(a), rule0(b)], ['FREQ=WEEKLY;UNTIL=20261012T070000Z', 'FREQ=WEEKLY;UNTIL=20261110T000000Z']);
      expect([for (final x in all(store)) x.split(':')[1]], ['Weekly', 'Weekly', 'Later', 'Later', 'Later', 'Later']);
    });

    test('on the first occurrence it is "all"', () {
      final (:store, :h, c: _) = weekly();
      h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'All'),
          key: K('2026-10-05'),
          scope: EditScope.following,
        ),
      );
      expect([store.snapshot.counts.series, all(store).every((x) => x.contains(':All:'))], [1, true]);
    });

    test('EXDATEs and overrides after the cut go to the new series, moved with it', () {
      final (:store, :h, c: _) = weekly();
      h.run(DeleteEvent('w', key: K('2026-11-02', '+01:00'), scope: EditScope.this_));
      h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'Last'),
          key: K('2026-11-09', '+01:00'),
          scope: EditScope.this_,
        ),
      );
      h.run(MoveEvent('w', '2026-10-26T11:00$P', key: K('2026-10-26', '+01:00'), scope: EditScope.following));
      final (a, b) = split(store);
      expect([a.set.exdates.length, a.overrides.length], [0, 0]);
      expect([for (final e in b.set.exdates) '$e'], ['2026-11-02T10:00:00Z']);
      expect(b.overrides.keys.toList(), ['2026-11-09T11:00:00+01:00$P']);
      final ov = store.snapshot.getEvent(b.overrides['2026-11-09T11:00:00+01:00$P']!)!;
      expect(ov.ref, EventRef(b.id, '2026-11-09T11:00:00+01:00$P'));
      expect([for (final x in all(store)) x.split(':')[1]], ['Weekly', 'Weekly', 'Weekly', 'Weekly', 'Last']);
    });

    test('undo restores both series exactly; redo cuts again', () {
      final (:store, :h, c: _) = weekly();
      h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'Last'),
          key: K('2026-11-09', '+01:00'),
          scope: EditScope.this_,
        ),
      );
      final before = dump(store.snapshot);
      h.run(MoveEvent('w', '2026-10-26T11:00$P', key: K('2026-10-26', '+01:00'), scope: EditScope.following));
      final after = dump(store.snapshot);
      h.undo();
      expect(dump(store.snapshot), before);
      h.redo();
      expect(dump(store.snapshot), after);
    });

    test('deleting the following ends the series before the occurrence and drops later overrides', () {
      final (:store, :h, c: _) = weekly();
      h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'Last'),
          key: K('2026-11-09', '+01:00'),
          scope: EditScope.this_,
        ),
      );
      h.run(DeleteEvent('w', key: K('2026-10-26', '+01:00'), scope: EditScope.following));
      expect(
        [all(store).length, store.snapshot.counts.events, rule0(store.snapshot.getSeries('w')!)],
        [3, 0, 'FREQ=WEEKLY;COUNT=3'],
      );
    });

    test('series.split without a patch: two series, the same occurrences', () {
      final (:store, :h, c: _) = weekly();
      final shown = all(store);
      h.run(SplitSeries('w', K('2026-10-19')));
      expect(store.snapshot.counts.series, 2);
      expect(all(store), shown);
    });
  });

  group('deleting a whole series takes its overrides with it', () {
    test('series.delete and event.delete with scope all; undo brings everything back', () {
      final (:store, :h, c: _) = weekly();
      h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'x'),
          key: K('2026-10-12'),
          scope: EditScope.this_,
        ),
      );
      final before = dump(store.snapshot);
      h.run(DeleteEvent('w', key: K('2026-10-19'), scope: EditScope.all));
      expect([store.snapshot.counts.events, store.snapshot.counts.series], [0, 0]);
      h.undo();
      expect(dump(store.snapshot), before);
      h.run(const DeleteSeries('w'));
      expect([store.snapshot.counts.events, store.snapshot.counts.series], [0, 0]);
    });
  });

  group('WKST (owner’s decision 2026-10-16)', () {
    int create(String rrule, [int? weekStart]) {
      final store = EventStore();
      final c = ctx(weekStart: weekStart);
      History.reading(store, () => c).run(CreateEvent(EventInput(id: 's', start: '2026-10-05T09:00$P', rrule: rrule)));
      return store.snapshot.getSeries('s')!.set.rules[0].wkst;
    }

    test('a series created here takes the locale’s first day; a rule that says WKST keeps it', () {
      expect(
        [create('FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,SU', 7), create('FREQ=WEEKLY;WKST=MO', 7), create('FREQ=WEEKLY', 1)],
        [7, 1, 1],
      );
    });

    test('a rule read from a source without WKST is Monday, whatever the locale', () {
      final items = normalizeMany(
        [EventInput(id: 's', start: '2026-10-05T09:00$P', rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,SU')],
        ctx().normalize,
        sourceId: 'feed',
      ).items;
      final it = items[0];
      expect(it, isA<NormalizedSeries>());
      expect((it as NormalizedSeries).series.set.rules[0].wkst, 1);
    });
  });

  group('move, resize, and the rules', () {
    test('move keeps the length; resize keeps the other edge', () {
      final store = EventStore();
      final c = ctx();
      final h = History.reading(store, () => c);
      h.run(CreateEvent(EventInput(id: 'a', title: 'A', start: '2026-10-21T09:00$P', end: '2026-10-21T10:00$P')));
      h.run(
        CreateEvent(
          EventInput(id: 'b', title: 'B', start: '2026-10-21T11:00$P', end: '2026-10-21T12:00$P', startEditable: false),
        ),
      );
      h.run(MoveEvent('a', '2026-10-21T13:30$P'));
      expect('${endOf(store.snapshot.getEvent('a')!)}', '2026-10-21T14:30:00+02:00$P');
      h.run(ResizeEvent('a', Edge.start, '2026-10-21T13:00$P'));
      final a = store.snapshot.getEvent('a')!;
      expect(['${startOf(a)}', '${endOf(a)}'], ['2026-10-21T13:00:00+02:00$P', '2026-10-21T14:30:00+02:00$P']);
    });
  });

  group('rebaseRule', () {
    RRule r(String t) {
      final x = parseRRule(t);
      if (x.rule == null) throw StateError(t);
      return x.rule!;
    }

    ZonedDateTime z(String s) => ZonedDateTime.tryParse(s)!;

    test('weekly days shift with the start; monthly day, ordinal weekday and last day are recounted', () {
      expect(
        serializeRRule(rebaseRule(r('FREQ=WEEKLY;BYDAY=MO,WE,FR'), z(K('2026-10-05')), z(K('2026-10-06')))),
        'FREQ=WEEKLY;BYDAY=TU,TH,SA',
      );
      expect(
        serializeRRule(rebaseRule(r('FREQ=MONTHLY;BYMONTHDAY=10'), z(K('2026-10-10')), z(K('2026-10-12')))),
        'FREQ=MONTHLY;BYMONTHDAY=12',
      );
      // 13 October 2026 is the second Tuesday; 15 October the third Thursday.
      expect(
        serializeRRule(rebaseRule(r('FREQ=MONTHLY;BYDAY=2TU'), z(K('2026-10-13')), z(K('2026-10-15')))),
        'FREQ=MONTHLY;BYDAY=3TH',
      );
      // 30 October is the last Friday; moved to Thursday 29th, the last Thursday.
      expect(
        serializeRRule(
          rebaseRule(r('FREQ=MONTHLY;BYDAY=-1FR'), z('2026-10-30T09:00:00+01:00$P'), z('2026-10-29T09:00:00+01:00$P')),
        ),
        'FREQ=MONTHLY;BYDAY=-1TH',
      );
      expect(
        serializeRRule(rebaseRule(r('FREQ=DAILY;BYHOUR=9'), z(K('2026-10-05')), z('2026-10-05T14:00:00+02:00$P'))),
        'FREQ=DAILY;BYHOUR=14',
      );
    });
  });

  group('a source is the authority on its series', () {
    test('a refetch drops local overrides and the part cut off by "following"', () {
      final store = EventStore();
      final c = ctx();
      List<Normalized> feed() => normalizeMany(
        [
          EventInput(
            id: 'w',
            title: 'Weekly',
            start: '2026-10-05T09:00$P',
            end: '2026-10-05T10:00$P',
            rrule: 'FREQ=WEEKLY;COUNT=6',
          ),
        ],
        c.normalize,
        sourceId: 'feed',
      ).items;
      store.replaceSourceChunk('feed', '*', feed());
      final h = History.reading(store, () => c);
      h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'Local'),
          key: K('2026-10-12'),
          scope: EditScope.this_,
        ),
      );
      h.run(MoveEvent('w', '2026-10-26T11:00$P', key: K('2026-10-26', '+01:00'), scope: EditScope.following));
      expect([store.snapshot.counts.series, store.snapshot.counts.events], [2, 1]);
      store.replaceSourceChunk('feed', '*', feed());
      expect([store.snapshot.counts.series, store.snapshot.counts.events, all(store).length], [1, 0, 6]);
      expect(all(store).every((x) => x.contains(':Weekly:') && x.contains('T09:00')), isTrue);
    });
  });

  group('fixed after the Phase 6 reviews (expectations by hand)', () {
    ({EventStore store, History h}) series({
      required String start,
      Object? rrule,
      List<Object?>? rdate,
      CommandContext? c,
    }) {
      final store = EventStore();
      final cc = c ?? ctx();
      final h = History.reading(store, () => cc);
      final r = h.run(CreateEvent(EventInput(id: 'w', title: 'S', start: start, rrule: rrule, rdate: rdate)));
      if (!r.ok) throw StateError('${r.result.problems}');
      return (store: store, h: h);
    }

    String rule(EventStore store, [String id = 'w']) =>
        store.snapshot.getSeries(id)!.set.rules.map(serializeRRule).join(' + ');
    List<String> dates(EventStore store, [String from = '2026-01-01', String to = '2027-01-01']) => [
      for (final i in store.snapshot.queryInstances(win(from, to)))
        '${i.event.title}:${'${startOf(i.event)}'.substring(0, 10)}',
    ];

    test('following from an RDATE keeps the rule on its own weekday', () {
      final (:store, :h) = series(
        start: '2026-10-05T09:00$P',
        rrule: 'FREQ=WEEKLY;COUNT=5',
        rdate: ['2026-10-14T09:00'],
      );
      expect(
        h
            .run(
              UpdateEvent(
                'w',
                const EventPatch(title: 'X'),
                key: K('2026-10-14'),
                scope: EditScope.following,
              ),
            )
            .ok,
        isTrue,
      );
      expect(dates(store, '2026-10-01', '2026-11-30'), [
        'S:2026-10-05',
        'S:2026-10-12',
        'X:2026-10-14',
        'X:2026-10-19',
        'X:2026-10-26',
        'X:2026-11-02',
      ]);
    });

    test('following that would break an INTERVAL rule’s phase is refused, nothing changes', () {
      final (:store, :h) = series(
        start: '2026-10-05T09:00$P',
        rrule: ['FREQ=WEEKLY;BYDAY=MO;COUNT=6', 'FREQ=WEEKLY;INTERVAL=2;BYDAY=FR;COUNT=4'],
      );
      final before = dump(store.snapshot);
      final r = h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'X'),
          key: K('2026-10-12'),
          scope: EditScope.following,
        ),
      );
      expect(codesOf(r.result.problems), ['invalid-edit']);
      expect(dump(store.snapshot), before);
    });

    test('month days stay valid: 10th & 25th moved by 8 days → 18th & 2nd', () {
      final (:store, :h) = series(start: '2026-01-10T09:00$P', rrule: 'FREQ=MONTHLY;BYMONTHDAY=10,25;COUNT=6');
      h.run(MoveEvent('w', '2026-02-02T09:00', key: '2026-01-25T09:00:00+01:00$P', scope: EditScope.all));
      expect(rule(store), 'FREQ=MONTHLY;COUNT=6;BYMONTHDAY=2,18');
      expect(dates(store), [
        'S:2026-01-18',
        'S:2026-02-02',
        'S:2026-02-18',
        'S:2026-03-02',
        'S:2026-03-18',
        'S:2026-04-02',
      ]);
    });

    test('the last day moved a day later is the first of the next month, never BYMONTHDAY=0', () {
      final (:store, :h) = series(start: '2026-01-01T09:00$P', rrule: 'FREQ=MONTHLY;BYMONTHDAY=1,-1;COUNT=4');
      h.run(MoveEvent('w', '2026-01-02T09:00', key: '2026-01-01T09:00:00+01:00$P', scope: EditScope.all));
      expect(rule(store), 'FREQ=MONTHLY;COUNT=4;BYMONTHDAY=1,2');
    });

    test('a year day: day 360 (26 December) moved to 2 January is day 2', () {
      final (:store, :h) = series(start: '2026-12-26T09:00$P', rrule: 'FREQ=YEARLY;BYYEARDAY=360;COUNT=2');
      h.run(MoveEvent('w', '2027-01-02T09:00', key: '2026-12-26T09:00:00+01:00$P', scope: EditScope.all));
      expect(rule(store), 'FREQ=YEARLY;COUNT=2;BYYEARDAY=2');
    });

    test('two ordinals stay two: first and third Monday moved a day → first and third Tuesday', () {
      final (:store, :h) = series(start: '2026-01-05T09:00$P', rrule: 'FREQ=MONTHLY;BYDAY=1MO,3MO;COUNT=6');
      h.run(MoveEvent('w', '2026-01-06T09:00', key: '2026-01-05T09:00:00+01:00$P', scope: EditScope.all));
      expect(rule(store), 'FREQ=MONTHLY;COUNT=6;BYDAY=1TU,3TU');
      expect(dates(store), [
        'S:2026-01-06',
        'S:2026-01-20',
        'S:2026-02-03',
        'S:2026-02-17',
        'S:2026-03-03',
        'S:2026-03-17',
      ]);
    });

    test('a yearly ordinal counts in the year: the 10th Monday (9 March) moved a day is the 10th Tuesday', () {
      final (:store, :h) = series(start: '2026-03-09T09:00$P', rrule: 'FREQ=YEARLY;BYDAY=10MO;COUNT=2');
      h.run(MoveEvent('w', '2026-03-10T09:00', key: '2026-03-09T09:00:00+01:00$P', scope: EditScope.all));
      expect(rule(store), 'FREQ=YEARLY;COUNT=2;BYDAY=10TU');
    });

    test('UNTIL moves with the series: four days stay four at 10:00', () {
      final (:store, :h) = series(start: '2026-10-05T09:00$P', rrule: 'FREQ=DAILY;UNTIL=20261008T070000Z');
      h.run(MoveEvent('w', '2026-10-06T10:00', key: K('2026-10-06'), scope: EditScope.all));
      expect(
        [
          for (final i in store.snapshot.queryInstances(win('2026-10-01', '2026-10-31')))
            '${startOf(i.event)}'.substring(0, 16),
        ],
        ['2026-10-05T10:00', '2026-10-06T10:00', '2026-10-07T10:00', '2026-10-08T10:00'],
      );
    });

    test('an override keeps its position when the rule is recounted: no duplicate in April', () {
      final (:store, :h) = series(start: '2026-01-13T09:00$P', rrule: 'FREQ=MONTHLY;BYDAY=2TU;COUNT=6');
      h.run(
        UpdateEvent(
          'w',
          const EventPatch(title: 'Apr'),
          key: '2026-04-14T09:00:00+02:00$P',
          scope: EditScope.this_,
        ),
      );
      h.run(MoveEvent('w', '2026-01-14T09:00', key: '2026-01-13T09:00:00+01:00$P', scope: EditScope.all));
      expect(rule(store), 'FREQ=MONTHLY;COUNT=6;BYDAY=2WE');
      expect(dates(store, '2026-04-01', '2026-05-01'), ['Apr:2026-04-14']);
      expect(store.snapshot.getSeries('w')!.overrides.keys.toList(), ['2026-04-08T09:00:00+02:00$P']);
    });

    test('a series id without key works when the first start is excluded or off the rule', () {
      final a = series(start: '2026-10-05T09:00$P', rrule: 'FREQ=WEEKLY;COUNT=4');
      a.h.run(DeleteEvent('w', key: K('2026-10-05'), scope: EditScope.this_));
      expect(a.h.run(UpdateEvent('w', const EventPatch(title: 'New'))).ok, isTrue);
      expect(dates(a.store, '2026-10-01', '2026-11-30'), ['New:2026-10-12', 'New:2026-10-19', 'New:2026-10-26']);
      expect(a.h.run(const DeleteEvent('w')).ok, isTrue);
      expect(a.store.snapshot.counts.series, 0);
      final b = series(start: '2026-10-06T09:00$P', rrule: 'FREQ=WEEKLY;BYDAY=MO;COUNT=3');
      expect(b.h.run(UpdateEvent('w', const EventPatch(title: 'New'))).ok, isTrue);
      expect(dates(b.store, '2026-10-01', '2026-11-30'), ['New:2026-10-12', 'New:2026-10-19', 'New:2026-10-26']);
    });

    test('WKST is added after reading the rule: an RRULE: prefix, a trailing space', () {
      int wk(String rrule) {
        final (:store, h: _) = series(start: '2026-10-05T09:00$P', rrule: rrule, c: ctx(weekStart: 7));
        return store.snapshot.getSeries('w')!.set.rules[0].wkst;
      }

      expect([wk('RRULE:WKST=MO;FREQ=WEEKLY'), wk('FREQ=WEEKLY '), wk('rrule:freq=weekly;')], [1, 7, 7]);
    });

    test('a source refresh takes back a chain of splits', () {
      final store = EventStore();
      final c = ctx();
      List<Normalized> feed() => normalizeMany(
        [
          EventInput(
            id: 'w',
            title: 'Weekly',
            start: '2026-10-05T09:00$P',
            end: '2026-10-05T10:00$P',
            rrule: 'FREQ=WEEKLY;COUNT=6',
          ),
        ],
        c.normalize,
        sourceId: 'feed',
      ).items;
      store.replaceSourceChunk('feed', '*', feed());
      final h = History.reading(store, () => c);
      h.run(SplitSeries('w', K('2026-10-19')));
      expect(h.run(SplitSeries('n-1', K('2026-11-02', '+01:00'))).ok, isTrue);
      expect(store.snapshot.counts.series, 3);
      store.replaceSourceChunk('feed', '*', feed());
      expect([store.snapshot.counts.series, all(store).length], [1, 6]);
    });
  });

  group('series.rule: a new rule for the whole series (the editor)', () {
    List<String> starts(EventStore store, [String from = '2026-10-01', String to = '2026-11-30']) => [
      for (final i in store.snapshot.queryInstances(win(from, to))) '${startOf(i.event)}'.substring(0, 10),
    ];

    test(
      'every day, three times: the old Mondays go, the excluded date and the moved occurrence stay; undo brings the rule back',
      () {
        final (:store, :h, c: _) = weekly(exdate: ['2026-10-06T09:00$P']);
        // 6 October is excluded (a Tuesday: under the weekly rule it is no occurrence anyway).
        final r = h.run(const ChangeRule('w', 'FREQ=DAILY;COUNT=3'));
        expect(r.ok, isTrue);
        // DTSTART 5 October, every day, three occurrences counted: 5, (6 excluded but counted by COUNT), 7.
        expect(starts(store), ['2026-10-05', '2026-10-07']);
        expect([for (final e in store.snapshot.getSeries('w')!.set.exdates) '$e'], ['2026-10-06T07:00:00Z']);
        h.undo();
        expect(starts(store), ['2026-10-05', '2026-10-12', '2026-10-19', '2026-10-26', '2026-11-02', '2026-11-09']);
      },
    );

    test('WKST as for a rule created here; a rule that cannot be read, or hours on an all-day series, is refused', () {
      final (:store, :h, c: _) = weekly();
      final store2 = EventStore();
      final c7 = ctx(weekStart: 7);
      History.reading(
        store2,
        () => c7,
      ).run(CreateEvent(EventInput(id: 's', start: '2026-10-05T09:00$P', rrule: 'FREQ=WEEKLY')));
      expect(
        applyCommand(store2.snapshot, const ChangeRule('s', 'FREQ=WEEKLY;INTERVAL=2'), ctx(weekStart: 7)).ok,
        isTrue,
      );
      final bad = h.run(const ChangeRule('w', 'FREQ=NEVER'));
      expect(bad.ok, isFalse);
      expect(
        [
          for (final p in bad.result.problems) [p.code.code, p.path],
        ],
        [
          ['invalid-rrule', 'command.rrule'],
        ],
      );
      expect(h.run(const ChangeRule('nope', 'FREQ=DAILY')).ok, isFalse);
      final day = EventStore();
      final cd = ctx();
      final hd = History.reading(day, () => cd);
      hd.run(CreateEvent(EventInput(id: 'd', start: '2026-10-05', allDay: true, rrule: 'FREQ=DAILY;COUNT=2')));
      final hourly = hd.run(const ChangeRule('d', 'FREQ=HOURLY'));
      expect(hourly.ok, isFalse);
      expect(codesOf(hourly.result.problems), ['invalid-rrule']);
      expect(store.snapshot.getSeries('w')!.set.rules[0].freq, Frequency.weekly);
    });
  });

  group('after the 16a reviews: repeat, stop, WKST, a person’s creation', () {
    test('event.repeat: the same id, every field kept, its source too; undo brings the single event back', () {
      final store = EventStore();
      store.replaceSourceChunk(
        'feed',
        'all',
        normalizeMany(
          [
            EventInput(
              id: 'e',
              title: 'E',
              start: '2026-10-05T09:00$P',
              url: 'https://x.test',
              extendedProps: {'room': 'B12'},
              status: EventStatus.tentative,
              startEditable: false,
            ),
          ],
          ctx().normalize,
          sourceId: 'feed',
        ).items,
      );
      final c = ctx(weekStart: 1);
      final h = History.reading(store, () => c);
      expect(h.run(const RepeatEvent('e', 'FREQ=DAILY;COUNT=3')).ok, isTrue);
      final s = store.snapshot.getSeries('e')!;
      expect(store.snapshot.getEvent('e'), isNull);
      expect(
        [
          s.sourceId,
          s.base.title,
          s.base.url,
          s.base.props,
          s.base.status.name,
          s.base.perms.start,
          s.set.rules[0].wkst,
        ],
        [
          'feed',
          'E',
          'https://x.test',
          {'room': 'B12'},
          'tentative',
          false,
          1,
        ],
      );
      h.undo();
      expect(store.snapshot.getSeries('e'), isNull);
      expect(store.snapshot.getEvent('e')!.title, 'E');
    });

    test(
      'series.rule null: it stops — the first occurrence is the event, a moved one stands alone; nothing else lost',
      () {
        final (:store, :h, c: _) = weekly(url: 'https://y.test');
        h.run(
          UpdateEvent(
            'w',
            const EventPatch(title: 'Moved'),
            key: '2026-10-12T09:00:00+02:00$P',
            scope: EditScope.this_,
          ),
        );
        expect(h.run(const ChangeRule('w', null)).ok, isTrue);
        final events = [
          for (final e in store.snapshot.allEvents)
            [e.id == 'w' ? 'w' : 'override', e.title, '${startOf(e)}'.substring(0, 16), e.ref, e.url],
        ]..sort((a, b) => '${a[0]}'.compareTo('${b[0]}'));
        expect(events, [
          ['override', 'Moved', '2026-10-12T09:00', null, 'https://y.test'],
          ['w', 'Weekly', '2026-10-05T09:00', null, 'https://y.test'],
        ]);
        expect(store.snapshot.getSeries('w'), isNull);
      },
    );

    test('series.rule keeps the series’ own WKST when the new rule says none (not the locale’s)', () {
      final store = EventStore();
      final c = ctx(weekStart: 1);
      final h = History.reading(store, () => c);
      h.run(
        CreateEvent(
          EventInput(id: 's', start: '2026-10-06T09:00$P', rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;WKST=SU'),
        ),
      );
      h.run(const ChangeRule('s', 'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,TH;COUNT=4'));
      expect(store.snapshot.getSeries('s')!.set.rules[0].wkst, 7);
    });
  });

  group('after the 16a code review: a series meets the rules on all its occurrences', () {
    test('a rule that can never give an occurrence (UNTIL before the start): kept, and said as a warning', () {
      final (:store, :h, c: _) = weekly();
      final r = h.run(const ChangeRule('w', 'FREQ=DAILY;UNTIL=20200101T000000Z'));
      expect(r.ok, isTrue);
      expect(
        [
          for (final p in r.result.problems) [p.code.code, p.severity.name],
        ],
        [
          ['invalid-rrule', 'warning'],
        ],
      );
      expect(store.snapshot.getSeries('w'), isNotNull);
    });
  });

  group('the editor’s batch: the new rule first, then the move rebases it', () {
    List<String> dates(EventStore store) => [
      for (final i in store.snapshot.queryInstances(win('2026-10-01', '2027-01-01')))
        '${startOf(i.event)}'.substring(0, 10),
    ];

    test('Wednesdays (4) moved a day later with five of them: Thursdays 15 October to 12 November', () {
      final store = EventStore();
      final c = ctx();
      final h = History.reading(store, () => c);
      h.run(
        CreateEvent(
          EventInput(id: 'w', start: '2026-10-14T13:00$P', end: '2026-10-14T13:30$P', rrule: 'FREQ=WEEKLY;COUNT=4'),
        ),
      );
      final r = h.run(
        Batch([
          const ChangeRule('w', 'FREQ=WEEKLY;BYDAY=WE;COUNT=5'),
          UpdateEvent(
            'w',
            const EventPatch(start: '2026-10-22T13:00$P', end: '2026-10-22T13:30$P'),
            key: '2026-10-21T13:00:00+02:00$P',
            scope: EditScope.all,
          ),
        ]),
      );
      expect(r.ok, isTrue);
      expect(dates(store), ['2026-10-15', '2026-10-22', '2026-10-29', '2026-11-05', '2026-11-12']);
    });

    test('the 3rd Wednesday monthly, moved to the next day: that day is the 4th Thursday, and so is the rule', () {
      final store = EventStore();
      final c = ctx();
      final h = History.reading(store, () => c);
      h.run(
        CreateEvent(
          EventInput(id: 'm', start: '2026-10-21T13:00$P', end: '2026-10-21T13:30$P', rrule: 'FREQ=MONTHLY;COUNT=2'),
        ),
      );
      h.run(
        Batch([
          const ChangeRule('m', 'FREQ=MONTHLY;BYDAY=3WE;COUNT=3'),
          UpdateEvent(
            'm',
            const EventPatch(start: '2026-10-22T13:00$P', end: '2026-10-22T13:30$P'),
            key: '2026-10-21T13:00:00+02:00$P',
            scope: EditScope.all,
          ),
        ]),
      );
      // Thursdays of October 2026: 1, 8, 15, 22 — the 22nd is the 4th; then 26 November (5, 12, 19, 26), 24 December (3, 10, 17, 24).
      expect(dates(store), ['2026-10-22', '2026-11-26', '2026-12-24']);
    });
  });

  group('a source’s item made the other kind here (event.repeat, series.rule null)', () {
    List<Normalized> feed(Map<String, Object?> input) => normalizeMany(
      [
        EventInput(
          id: input['id'] as String?,
          title: (input['title'] as String?) ?? 'E',
          start: '2026-10-05T09:00$P',
          rrule: input['rrule'],
        ),
      ],
      ctx().normalize,
      sourceId: 'feed',
    ).items;
    List<String?> kinds(EventStore store, String id) => [
      store.snapshot.getSeries(id) != null ? 'series' : null,
      store.snapshot.getEvent(id) != null ? 'event' : null,
    ];

    test('repeat, undo, redo: the series comes back (the source still delivers the id)', () {
      final store = EventStore();
      store.replaceSourceChunk('feed', 'all', feed({'id': 'e'}));
      final c = ctx();
      final h = History.reading(store, () => c);
      h.run(const RepeatEvent('e', 'FREQ=DAILY;COUNT=3'));
      expect(h.undo(), isTrue);
      expect(h.redo(), isTrue);
      expect(kinds(store, 'e'), ['series', null]);
    });

    test('stop a source series, undo, redo: the single event comes back', () {
      final store = EventStore();
      store.replaceSourceChunk('feed', 'all', feed({'id': 's', 'rrule': 'FREQ=DAILY;COUNT=3'}));
      final c = ctx();
      final h = History.reading(store, () => c);
      h.run(const ChangeRule('s', null));
      expect(h.undo(), isTrue);
      expect(h.redo(), isTrue);
      expect(kinds(store, 's'), [null, 'event']);
    });

    test('the source withdraws the id: the series made of its event goes too, and a redo after that is dropped', () {
      final store = EventStore();
      store.replaceSourceChunk('feed', 'all', feed({'id': 'e'}));
      final c = ctx();
      final h = History.reading(store, () => c);
      h.run(const RepeatEvent('e', 'FREQ=DAILY;COUNT=3'));
      store.replaceSourceChunk('feed', 'all', []);
      expect(kinds(store, 'e'), [null, null]);

      final again = EventStore();
      again.replaceSourceChunk('feed', 'all', feed({'id': 'e'}));
      final c2 = ctx();
      final h2 = History.reading(again, () => c2);
      h2.run(const RepeatEvent('e', 'FREQ=DAILY;COUNT=3'));
      h2.undo();
      again.replaceSourceChunk('feed', 'all', []);
      expect(h2.redo(), isFalse);
      expect(kinds(again, 'e'), [null, null]);
    });

    test('the source delivers the id again as it was: it wins, no duplicate-id, and it still owns it', () {
      final store = EventStore();
      store.replaceSourceChunk('feed', 'all', feed({'id': 'e'}));
      final c = ctx();
      final h = History.reading(store, () => c);
      h.run(const RepeatEvent('e', 'FREQ=DAILY;COUNT=3'));
      final change = store.replaceSourceChunk('feed', 'all', feed({'id': 'e', 'title': 'Renamed on the server'}));
      expect(change.problems, isEmpty);
      expect([...kinds(store, 'e'), store.snapshot.getEvent('e')?.title], [null, 'event', 'Renamed on the server']);
      store.replaceSourceChunk('feed', 'all', []);
      expect(kinds(store, 'e'), [null, null]);
    });

    test(
      'the server saved it as a series: delivered so, it is the source’s series, the old event’s place withdrawn quietly',
      () {
        final store = EventStore();
        store.replaceSourceChunk('feed', 'all', feed({'id': 'e'}));
        final c = ctx();
        final h = History.reading(store, () => c);
        h.run(const RepeatEvent('e', 'FREQ=DAILY;COUNT=3'));
        final change = store.replaceSourceChunk('feed', 'all', feed({'id': 'e', 'rrule': 'FREQ=DAILY;COUNT=3'}));
        expect(change.problems, isEmpty);
        expect(kinds(store, 'e'), ['series', null]);
        expect([store.snapshot.isSourceOwned('e', series: true), store.snapshot.isSourceOwned('e')], [true, false]);
      },
    );

    test('a user’s own series under an id the source then delivers as an event is still refused (duplicate-id)', () {
      final store = EventStore();
      final c = ctx();
      final h = History.reading(store, () => c);
      h.run(CreateEvent(EventInput(id: 'x', start: '2026-10-05T09:00$P', rrule: 'FREQ=DAILY;COUNT=3')));
      final change = store.replaceSourceChunk('feed', 'all', feed({'id': 'x'}));
      expect(codesOf(change.problems), ['duplicate-id']);
      expect(kinds(store, 'x'), ['series', null]);
    });
  });
}
