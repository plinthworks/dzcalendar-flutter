// Ported from the TypeScript core's series.test.ts (hand-written
// expectations, copied as values).
//
// Skipped, with the reason:
// - 'a source delivers series and takes them back': arraySource and
//   loadStaticSource (sources' fetching) are not ported. Its store half is
//   kept below as 'a source chunk delivers series and takes them back', fed
//   through normalizeMany and replaceSourceChunk directly.
// - 'view models follow series changes (time grid and day grid rebuild when a
//   series is added)': buildTimeGridModel / updateTimeGridModel /
//   buildDayGridModel / updateDayGridModel are not ported.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

const _paris = 'Europe/Paris';

NormalizeContext nctx() => NormalizeContext(displayZone: _paris, newId: createIdGenerator('s'));

// One context, so History's ids never repeat.
final CommandContext _cctx = CommandContext(normalize: nctx());
CommandContext cctx() => _cctx;

ViewWindow week(String from, String to, [String zone = _paris]) =>
    viewWindow(PlainDate.parse(from), PlainDate.parse(to), zone);

Series series(EventInput input) {
  final r = normalizeEvent(input, nctx());
  final v = r.value;
  if (!r.ok || v is! NormalizedSeries) throw StateError(r.ok ? 'not a series' : '${r.problems}');
  return v.series;
}

EventStore storeWith(List<EventInput> inputs) {
  final store = EventStore();
  store.apply([for (final i in inputs) SeriesMutation(after: series(i))], ChangeCause.api);
  return store;
}

Object startOf(CalEvent e) => switch (e) {
  TimedEvent(:final start) => start,
  AllDayEvent(:final start) => start,
};

Object endOf(CalEvent e) => switch (e) {
  TimedEvent(:final end) => end,
  AllDayEvent(:final end) => end,
};

List<String> starts(List<EventInstance> xs) => [for (final x in xs) '${startOf(x.event)}'];

List<String> seriesIds(List<EventInstance> xs) => [for (final x in xs) x.event.ref!.seriesId];

List<String> codesOf(List<Problem> ps) => [for (final p in ps) p.code.code];

void main() {
  group('normalize: an event with a rule is a series', () {
    test('keeps the first occurrence as its base and the rules as given', () {
      final s = series(
        EventInput(
          id: 'standup',
          title: 'Standup',
          start: '2026-10-19T09:00[Europe/Paris]',
          end: '2026-10-19T09:15[Europe/Paris]',
          rrule: 'FREQ=WEEKLY;BYDAY=MO,WE',
        ),
      );
      expect(
        [s.id, s.base.title, s.set.rules.length, '${s.start}'],
        ['standup', 'Standup', 1, '2026-10-19T09:00:00+02:00[Europe/Paris]'],
      );
    });

    test('reads EXDATE as a date or a moment, RDATE in the series zone', () {
      final s = series(
        EventInput(
          id: 'x',
          start: '2026-10-19T09:00[America/Chicago]',
          rrule: 'FREQ=DAILY',
          exdate: ['2026-10-20', '2026-10-21T09:00'],
          rdate: ['2026-10-25T18:00'],
        ),
      );
      expect([for (final e in s.set.exdates) '$e'], ['2026-10-20', '2026-10-21T14:00:00Z']);
      expect([for (final r in s.set.rdates) '$r'], ['2026-10-25T18:00:00-05:00[America/Chicago]']);
    });
  });

  group('queryInstances expands series in the window only', () {
    test('a weekly rule: occurrences keyed seriesId@originalStart, same objects on the next query', () {
      final store = storeWith([
        EventInput(
          id: 'standup',
          start: '2026-10-19T09:00[Europe/Paris]',
          end: '2026-10-19T09:15[Europe/Paris]',
          rrule: 'FREQ=WEEKLY;BYDAY=MO,WE',
        ),
      ]);
      final w = week('2026-10-26', '2026-11-02');
      final a = store.snapshot.queryInstances(w);
      expect(
        [
          for (final x in a) [x.key, x.origin.name],
        ],
        [
          ['standup@2026-10-26T09:00:00+01:00[Europe/Paris]', 'occurrence'],
          ['standup@2026-10-28T09:00:00+01:00[Europe/Paris]', 'occurrence'],
        ],
      );
      expect(a[0].event.ref, EventRef('standup', '2026-10-26T09:00:00+01:00[Europe/Paris]'));
      final b = store.snapshot.queryInstances(w);
      expect(identical(b[0].event, a[0].event), isTrue);
    });

    test('09:00 in Paris stays 09:00 on the wall across the clock change (FC#6729)', () {
      final store = storeWith([EventInput(id: 'w', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=DAILY')]);
      final got = store.snapshot.queryInstances(week('2026-10-24', '2026-10-27'));
      expect(starts(got), [
        '2026-10-24T09:00:00+02:00[Europe/Paris]',
        '2026-10-25T09:00:00+01:00[Europe/Paris]',
        '2026-10-26T09:00:00+01:00[Europe/Paris]',
      ]);
    });

    test('an occurrence that began before the window and runs into it is shown', () {
      final store = storeWith([
        EventInput(
          id: 'night',
          start: '2026-10-19T22:00[Europe/Paris]',
          end: '2026-10-20T06:00[Europe/Paris]',
          rrule: 'FREQ=WEEKLY',
        ),
      ]);
      final got = store.snapshot.queryInstances(week('2026-10-27', '2026-10-28'));
      expect(starts(got), ['2026-10-26T22:00:00+01:00[Europe/Paris]']);
    });

    test('an endless rule is found centuries later; a finished one is not', () {
      final store = storeWith([
        EventInput(id: 'forever', start: '2026-01-05T09:00[Europe/Paris]', rrule: 'FREQ=WEEKLY'),
        EventInput(id: 'done', start: '2026-01-05T10:00[Europe/Paris]', rrule: 'FREQ=WEEKLY;COUNT=3'),
      ]);
      expect(seriesIds(store.snapshot.queryInstances(week('2226-01-01', '2226-01-08'))), ['forever']);
    });

    test('all-day series: dates, a multi-day occurrence reaching into the window', () {
      final store = storeWith([EventInput(id: 'trip', start: '2026-10-01', end: '2026-10-04', rrule: 'FREQ=MONTHLY')]);
      final got = store.snapshot.queryInstances(week('2026-11-03', '2026-11-04'));
      expect([for (final x in got) '${startOf(x.event)}/${endOf(x.event)}'], ['2026-11-01/2026-11-04']);
    });

    test('EXDATE as a date removes that day of a timed series (FC#6105)', () {
      final store = storeWith([
        EventInput(
          id: 'x',
          start: '2026-10-19T09:00[Europe/Paris]',
          rrule: 'FREQ=DAILY;COUNT=3',
          exdate: ['2026-10-20'],
        ),
      ]);
      expect(starts(store.snapshot.queryInstances(week('2026-10-19', '2026-10-26'))), [
        '2026-10-19T09:00:00+02:00[Europe/Paris]',
        '2026-10-21T09:00:00+02:00[Europe/Paris]',
      ]);
    });

    test('resource filter and display: none apply to series too', () {
      final store = storeWith([
        EventInput(id: 'a', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=DAILY', resourceIds: ['room1']),
        EventInput(
          id: 'hidden',
          start: '2026-10-19T09:00[Europe/Paris]',
          rrule: 'FREQ=DAILY',
          display: EventDisplay.none,
        ),
      ]);
      final w = week('2026-10-19', '2026-10-20');
      expect(seriesIds(store.snapshot.queryInstances(w, const QueryOptions(resourceId: 'room1'))), ['a']);
      expect(store.snapshot.queryInstances(w, const QueryOptions(resourceId: 'room2')), isEmpty);
      expect(seriesIds(store.snapshot.queryInstances(w)), ['a']);
    });

    test('ids are escaped in keys: an id with @ or | cannot pass for another', () {
      final store = storeWith([
        EventInput(id: 'a@b|c', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=DAILY;COUNT=1'),
      ]);
      expect(
        store.snapshot.queryInstances(week('2026-10-19', '2026-10-20'))[0].key,
        'a%40b%7Cc@2026-10-19T09:00:00+02:00[Europe/Paris]',
      );
    });
  });

  group('store, commands and history', () {
    test('seriesTouched reports the series; the version moves; equal series keep their object', () {
      final store = EventStore();
      final changes = <StoreChange>[];
      store.subscribe(changes.add);
      final s = series(EventInput(id: 'x', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=DAILY'));
      store.apply([SeriesMutation(after: s)], ChangeCause.api);
      final stored = store.snapshot.getSeries('x')!;
      expect(
        [changes.length, changes[0].seriesTouched, stored.revision],
        [
          1,
          ['x'],
          1,
        ],
      );
      store.apply([
        SeriesMutation(
          before: stored,
          after: series(EventInput(id: 'x', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=DAILY')),
        ),
      ], ChangeCause.api);
      expect(changes.length, 1);
      expect(identical(store.snapshot.getSeries('x'), stored), isTrue);
    });

    test('create with a rule, delete the series, undo brings every occurrence back', () {
      final store = EventStore();
      final h = History.reading(store, cctx);
      expect(
        h.run(CreateEvent(EventInput(id: 's', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=DAILY'))).ok,
        isTrue,
      );
      final w = week('2026-10-19', '2026-10-22');
      expect(store.snapshot.queryInstances(w), hasLength(3));
      h.run(const DeleteSeries('s'));
      expect(store.snapshot.queryInstances(w), hasLength(0));
      h.undo();
      expect(store.snapshot.queryInstances(w), hasLength(3));
      expect(
        codesOf(h.run(CreateEvent(EventInput(id: 's', start: '2026-10-19'))).result.problems),
        contains('duplicate-id'),
      );
    });

    test('a source chunk delivers series and takes them back', () {
      final store = EventStore();
      final items = normalizeMany(
        [EventInput(id: 'r', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=WEEKLY')],
        nctx(),
        sourceId: 'feed',
      ).items;
      store.replaceSourceChunk('feed', '*', items);
      expect([store.snapshot.counts.series, store.snapshot.getSeries('r')?.sourceId], [1, 'feed']);
      final none = normalizeMany(<EventInput>[], nctx(), sourceId: 'feed').items;
      store.replaceSourceChunk('feed', '*', none);
      expect(store.snapshot.counts.series, 0);
    });
  });

  group('performance', () {
    test('a year of a daily series expands quickly', () {
      final store = storeWith([EventInput(id: 'd', start: '2026-01-01T09:00[Europe/Paris]', rrule: 'FREQ=DAILY')]);
      final w = week('2026-01-01', '2027-01-01');
      store.snapshot.queryInstances(w);
      final fresh = storeWith([EventInput(id: 'd2', start: '2026-01-01T09:00[Europe/Paris]', rrule: 'FREQ=DAILY')]);
      final t0 = Stopwatch()..start();
      final got = fresh.snapshot.queryInstances(w);
      expect([got.length, t0.elapsedMilliseconds < 200], [365, true]);
    });
  });

  group('fixed after the architect review', () {
    ViewWindow w(String from, String to) => week(from, to);

    test('a DTSTART on the second 02:30 is itself the first occurrence', () {
      final store = storeWith([
        EventInput(id: 'x', start: '2026-10-25T02:30+01:00[Europe/Paris]', rrule: 'FREQ=DAILY;COUNT=2'),
      ]);
      final got = store.snapshot.queryInstances(w('2026-10-25', '2026-10-27'));
      expect(starts(got), ['2026-10-25T02:30:00+01:00[Europe/Paris]', '2026-10-26T02:30:00+01:00[Europe/Paris]']);
      expect(got[0].event.ref!.key, '${store.snapshot.getSeries('x')!.start}');
    });

    test('an all-day EXDATE given as a moment excludes the day it names, not the UTC day', () {
      final store = storeWith([
        EventInput(
          id: 'x',
          start: '2026-03-09',
          rrule: 'FREQ=DAILY;COUNT=3',
          exdate: ['2026-03-10T00:00+01:00[Europe/Paris]'],
        ),
      ]);
      expect(starts(store.snapshot.queryInstances(w('2026-03-09', '2026-03-12'))), ['2026-03-09', '2026-03-11']);
    });

    // 13 real hours (10:00Z -> 23:00Z). After Paris falls back, leaving at 12:00 (11:00Z) lands at 00:00Z: 09:00 in Tokyo.
    test('an occurrence keeps the end zone of the series (a Paris -> Tokyo flight)', () {
      final store = storeWith([
        EventInput(
          id: 'f',
          start: '2026-10-19T12:00[Europe/Paris]',
          end: '2026-10-20T08:00[Asia/Tokyo]',
          rrule: 'FREQ=WEEKLY',
        ),
      ]);
      final occ = store.snapshot.queryInstances(w('2026-10-26', '2026-10-27'))[0].event;
      expect(
        ['${startOf(occ)}', '${endOf(occ)}'],
        ['2026-10-26T12:00:00+01:00[Europe/Paris]', '2026-10-27T09:00:00+09:00[Asia/Tokyo]'],
      );
    });

    test('a one-day timed occurrence over the 25-hour day still reaches the next window', () {
      final store = storeWith([
        EventInput(
          id: 'x',
          start: '2026-10-19T00:30[Europe/Paris]',
          end: '2026-10-20T00:30[Europe/Paris]',
          rrule: 'FREQ=DAILY',
        ),
      ]);
      expect(starts(store.snapshot.queryInstances(w('2026-10-26', '2026-10-27'))), [
        '2026-10-25T00:30:00+02:00[Europe/Paris]',
        '2026-10-26T00:30:00+01:00[Europe/Paris]',
      ]);
    });

    test('an RDATE before DTSTART is found', () {
      final store = storeWith([
        EventInput(
          id: 'x',
          start: '2026-10-19T09:00[Europe/Paris]',
          rrule: 'FREQ=WEEKLY;COUNT=2',
          rdate: ['2026-10-12T09:00'],
        ),
      ]);
      expect(starts(store.snapshot.queryInstances(w('2026-10-12', '2026-10-13'))), [
        '2026-10-12T09:00:00+02:00[Europe/Paris]',
      ]);
    });

    test('too-many-occurrences reaches whoever asks', () {
      final store = storeWith([EventInput(id: 'x', start: '2026-10-19T00:00[Europe/Paris]', rrule: 'FREQ=MINUTELY')]);
      final seen = <String>[];
      final got = store.snapshot.queryInstances(
        w('2026-10-19', '2026-10-26'),
        QueryOptions(onProblem: (p) => seen.add(p.code.code)),
      );
      expect(
        [got.length, seen],
        [
          2000,
          ['too-many-occurrences'],
        ],
      );
    });

    test('no input stalls the store: an enormous COUNT, a sub-daily rule that never happens', () {
      final t0 = Stopwatch()..start();
      final store = storeWith([
        EventInput(id: 'a', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=SECONDLY;COUNT=999999999'),
        EventInput(id: 'b', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=DAILY;COUNT=999999'),
        EventInput(id: 'c', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=MINUTELY;BYMONTH=2;BYMONTHDAY=30'),
      ]);
      store.snapshot.queryInstances(w('2030-01-01', '2030-01-02'), QueryOptions(onProblem: (_) {}));
      expect(t0.elapsedMilliseconds, lessThan(3000));
    });

    test('delete by a series id takes the series, by an occurrence key that occurrence; keys round-trip', () {
      final store = storeWith([EventInput(id: 's|1', start: '2026-10-19T09:00[Europe/Paris]', rrule: 'FREQ=DAILY')]);
      final occ = occurrenceKey('s|1', '2026-10-19T09:00:00+02:00[Europe/Paris]');
      CommandResult del(String id) => applyCommand(store.snapshot, DeleteEvent(id), cctx());
      final whole = del('s|1');
      expect(whole.ok, isTrue);
      expect(
        [
          for (final m in whole.mutations)
            '${m is SeriesMutation ? 'series' : 'event'}:${m.after != null ? 'kept' : 'gone'}',
        ],
        ['series:gone'],
      );
      final one = del(occ);
      expect(one.ok, isTrue);
      final m = one.mutations[0];
      expect(m, isA<SeriesMutation>());
      expect([for (final e in (m.after! as Series).set.exdates) '$e'], ['2026-10-19T07:00:00Z']);
      expect(codesOf(del('nope').problems), ['unknown-event']);
      final parsed = parseInstanceKey(occ);
      expect([parsed.seriesId, parsed.key, parsed.eventId], ['s|1', '2026-10-19T09:00:00+02:00[Europe/Paris]', null]);
      final plain = parseInstanceKey('a%40b');
      expect([plain.eventId, plain.seriesId, plain.key], ['a@b', null, null]);
    });
  });

  group('fixed after the code review', () {
    test('a source may not bring a series whose id is an event’s (or the reverse)', () {
      final store = EventStore();
      final r = normalizeEvent(EventInput(id: 'x', start: '2026-10-19'), nctx());
      final v = r.value;
      if (!r.ok || v is! NormalizedEvent) fail('event');
      store.apply([EventMutation(after: v.event)], ChangeCause.api);
      final change = store.replaceSourceChunk(
        'feed',
        '*',
        normalizeMany(
          [EventInput(id: 'x', start: '2026-10-19', rrule: 'FREQ=DAILY')],
          nctx(),
          sourceId: 'feed',
        ).items,
      );
      expect(
        [codesOf(change.problems), store.snapshot.counts.series],
        [
          ['duplicate-id'],
          0,
        ],
      );
    });
  });
}
