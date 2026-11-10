// Phase 19i-2: saves, live sources, jsonSource, icalSource (owner's
// decisions 54–57). Ported from the TypeScript core's sources.test.ts
// (writing edits back 6, review fixes 5 of 9 — the 4 others are in
// sources_test.dart —, jsonSource 5), live.test.ts (liveSource 2, forget 1,
// the clock 1; sseSource is not ported: a Dart app gives a Stream) and the
// ical package's icalSource tests (3). Expectations copied as values.
// Translation notes:
// - `history.run({ type: 'event.move', id, start })` is
//   `history.run(MoveEvent(id, start))`; `event.repeat` is `RepeatEvent`.
// - `fetchImpl` (the web's fetch) is the application's request function
//   (decision 55): it answers the decoded JSON, or throws for an HTTP error.
// - `connect(emit)` is a `Stream<LiveMessage>` (decision 56): a
//   `StreamController` in the tests.
import 'dart:async';

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

const paris = 'Europe/Paris';
PlainDate d(String s) => PlainDate.parse(s);
final _ids = createIdGenerator('t');
NormalizeContext ctx() => NormalizeContext(displayZone: paris, newId: _ids);
Future<void> flush() => Future<void>.delayed(Duration.zero);

({EventStore store, SourceManager m, List<SourceNotice> notices}) setup({int keepChunks = 12}) {
  final store = EventStore();
  final notices = <SourceNotice>[];
  final m = SourceManager(store: store, normalize: ctx, notify: notices.add, keepChunks: keepChunks);
  return (store: store, m: m, notices: notices);
}

History historyOf(EventStore store) => History(store, CommandContext(normalize: ctx(), weekStart: 1), limit: 50);

List<String> titles(EventStore store, [String from = '2026-01-01', String to = '2027-01-01']) => [
  for (final i in store.snapshot.queryInstances(viewWindow(d(from), d(to), paris))) i.event.title,
];

void main() {
  group('writing edits back (save)', () {
    final event = EventInput(
      id: 'a',
      title: 'A',
      start: '2026-10-06T09:00[Europe/Paris]',
      end: '2026-10-06T10:00[Europe/Paris]',
    );

    ({
      EventStore store,
      SourceManager m,
      List<SourceNotice> notices,
      History history,
      List<Completer<SourceAnswer>> answers,
      String Function() start,
    })
    editable(FutureOr<void> Function(SaveRequest) save) {
      final (:store, :m, :notices) = setup();
      final answers = <Completer<SourceAnswer>>[];
      var first = true;
      m.add(
        EventSourceSpec(
          id: 's',
          save: save,
          fetch: (_) {
            if (first) return SourceAnswer([event]);
            final a = Completer<SourceAnswer>();
            answers.add(a);
            return a.future;
          },
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      first = false;
      return (
        store: store,
        m: m,
        notices: notices,
        history: historyOf(store),
        answers: answers,
        start: () => '${(store.snapshot.getEvent('a')! as TimedEvent).start}',
      );
    }

    test('shows the edit at once, and sends it with what it was', () async {
      final sent = <SaveRequest>[];
      final (:history, :start, :m, :notices, store: _, answers: _) = editable(sent.add);
      history.run(const MoveEvent('a', '2026-10-07T09:00[Europe/Paris]'));
      expect(start(), '2026-10-07T09:00:00+02:00[Europe/Paris]');
      await flush(); // saves of one source go one after the other, from a future chain
      expect(sent, hasLength(1));
      expect(sent[0].cause, SaveCause.command);
      final e = sent[0].edits.single as EventEdit;
      expect(
        [e.id, '${(e.before! as TimedEvent).start}', '${(e.after! as TimedEvent).start}'],
        ['a', '2026-10-06T09:00:00+02:00[Europe/Paris]', '2026-10-07T09:00:00+02:00[Europe/Paris]'],
      );
      await m.idle();
      expect(notices.whereType<SourceSaved>(), hasLength(1));
    });

    test('a refused save puts the event back, says so, and leaves nothing to undo', () async {
      final (:history, :start, :m, :notices, store: _, answers: _) = editable((_) => Future.error(StateError('403')));
      history.run(const MoveEvent('a', '2026-10-07T09:00[Europe/Paris]'));
      await m.idle();
      expect(start(), '2026-10-06T09:00:00+02:00[Europe/Paris]');
      final failed = notices.whereType<SourceSaveFailed>().single;
      expect([failed.sourceId, failed.reverted], ['s', true]);
      expect(history.canUndo, isFalse);
    });

    test('an undo is saved too', () async {
      final causes = <SaveCause>[];
      final (:history, :m, start: _, notices: _, store: _, answers: _) = editable((r) => causes.add(r.cause));
      history.run(const MoveEvent('a', '2026-10-07T09:00[Europe/Paris]'));
      history.undo();
      await m.idle();
      expect(causes, [SaveCause.command, SaveCause.undo]);
    });

    test('a refetch while the save is out does not overwrite the edit, then asks again', () async {
      final pending = Completer<void>();
      final (:history, :start, :m, :answers, notices: _, store: _) = editable((_) => pending.future);
      history.run(const MoveEvent('a', '2026-10-07T09:00[Europe/Paris]'));
      m.refetch();
      answers[0].complete(SourceAnswer([event])); // the server has not seen the edit yet
      await flush();
      expect(start(), '2026-10-07T09:00:00+02:00[Europe/Paris]');
      pending.complete();
      await flush();
      await flush();
      // Something came in during the save: the source is asked again for the truth.
      expect(answers, hasLength(2));
      answers[1].complete(
        SourceAnswer([
          EventInput(
            id: 'a',
            title: 'A',
            start: '2026-10-07T09:00[Europe/Paris]',
            end: '2026-10-07T10:00[Europe/Paris]',
          ),
        ]),
      );
      await m.idle();
      expect(start(), '2026-10-07T09:00:00+02:00[Europe/Paris]');
    });

    test('made a series while its save is out: a refetch answering the old event keeps the series', () async {
      final pending = Completer<void>();
      final (:store, :history, :m, :answers, start: _, notices: _) = editable((_) => pending.future);
      expect(history.run(const RepeatEvent('a', 'FREQ=DAILY;COUNT=3')).ok, isTrue);
      m.refetch();
      answers[0].complete(SourceAnswer([event])); // the server has not seen the edit yet
      await flush();
      expect([store.snapshot.getSeries('a') != null, store.snapshot.getEvent('a') != null], [true, false]);
      pending.complete();
      await flush();
      await flush();
      // Asked again once saved: the server's series now.
      answers[1].complete(
        SourceAnswer([
          EventInput(
            id: 'a',
            title: 'A',
            start: '2026-10-06T09:00[Europe/Paris]',
            end: '2026-10-06T10:00[Europe/Paris]',
            rrule: 'FREQ=DAILY;COUNT=3',
          ),
        ]),
      );
      await m.idle();
      expect(
        [
          store.snapshot.getSeries('a') != null,
          store.snapshot.getEvent('a') != null,
          store.snapshot.isSourceOwned('a', series: true),
        ],
        [true, false, true],
      );
    });

    test('edits to a source without save stay local (until fetched again)', () {
      final (:store, :m, notices: _) = setup();
      m.add(fnSource('s', (_) => [event]));
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      final history = historyOf(store);
      expect(history.run(const MoveEvent('a', '2026-10-07T09:00[Europe/Paris]')).ok, isTrue);
      m.refetch();
      expect('${(store.snapshot.getEvent('a')! as TimedEvent).start}', '2026-10-06T09:00:00+02:00[Europe/Paris]');
    });
  });

  group('review fixes (saves)', () {
    final weekly = EventInput(
      id: 'w',
      title: 'standup',
      start: '2026-10-05T09:00[Europe/Paris]',
      duration: 'PT30M',
      rrule: 'FREQ=WEEKLY;COUNT=6',
    );
    const key = '2026-10-12T09:00:00+02:00[Europe/Paris]';

    ({EventStore store, SourceManager m, List<SourceNotice> notices, History history, List<String> Function() shown})
    seriesSource(FutureOr<void> Function(SaveRequest) save, [List<EventInput> Function()? server]) {
      final (:store, :m, :notices) = setup();
      m.add(
        EventSourceSpec(
          id: 's',
          chunk: ChunkPolicy.none,
          fetch: (_) => SourceAnswer(server?.call() ?? [weekly]),
          save: save,
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-11-16'), paris);
      List<String> shown() => [
        for (final i in store.snapshot.queryInstances(viewWindow(d('2026-10-05'), d('2026-11-16'), paris)))
          '${'${(i.event as TimedEvent).start}'.substring(5, 16)} ${i.event.title}',
      ];
      return (store: store, m: m, notices: notices, history: historyOf(store), shown: shown);
    }

    test('moving one occurrence sends the series and the override it made', () async {
      final sent = <SaveRequest>[];
      final (:history, :m, store: _, notices: _, shown: _) = seriesSource(sent.add);
      expect(history.run(const MoveEvent('w@$key', '2026-10-12T11:00[Europe/Paris]')).ok, isTrue);
      await m.idle();
      final kinds = [
        for (final e in sent[0].edits)
          switch (e) {
            EventEdit(:final after) => after?.ref != null ? 'event:override' : 'event:${e.id}',
            SeriesEdit(:final id) => 'series:$id',
          },
      ]..sort();
      expect(kinds, ['event:override', 'series:w']);
    });

    test('a refused occurrence edit leaves neither the override nor a double', () async {
      final (:history, :m, :shown, store: _, notices: _) = seriesSource((_) => Future.error(StateError('no')));
      history.run(const MoveEvent('w@$key', '2026-10-12T11:00[Europe/Paris]'));
      await m.idle();
      expect(shown().where((x) => x.startsWith('10-12')), ['10-12T09:00 standup']);
    });

    test('"this and following" sends the cut series and its new tail', () async {
      final sent = <SaveRequest>[];
      final (:history, :m, store: _, notices: _, shown: _) = seriesSource(sent.add);
      expect(
        history.run(const MoveEvent('w@$key', '2026-10-12T10:00[Europe/Paris]', scope: EditScope.following)).ok,
        isTrue,
      );
      await m.idle();
      final series = sent[0].edits.whereType<SeriesEdit>().toList();
      expect(series, hasLength(2));
      expect(series.any((e) => e.after?.splitFrom?.seriesId == 'w'), isTrue);
    });

    test('an override saved and delivered back under its id is adopted, not refused', () async {
      var server = <EventInput>[weekly];
      final (:history, :m, :store, :shown, :notices) = seriesSource((req) {
        // The server stores what it is sent.
        for (final e in req.edits) {
          final input = switch (e) {
            EventEdit(:final after) => after == null ? null : eventInput(after),
            SeriesEdit(:final after) => after == null ? null : seriesInput(after),
          };
          server = [
            for (final x in server)
              if (x.id != e.id) x,
            ?input,
          ];
        }
      }, () => server);
      history.run(const MoveEvent('w@$key', '2026-10-12T11:00[Europe/Paris]'));
      await m.idle();
      m.refetch();
      await m.idle();
      expect(notices.whereType<SourceProblems>(), isEmpty);
      expect(shown().where((x) => x.startsWith('10-12')), ['10-12T11:00 standup']);
      expect([for (final k in store.snapshot.getSeries('w')!.overrides.keys) k], [key]);
    });

    test('a chunk with a save out is not evicted', () async {
      final pending = Completer<void>();
      final (:store, :m, notices: _) = setup(keepChunks: 0);
      m.add(
        fnSource(
          's',
          (_) => [EventInput(id: 'a', title: 'A', start: '2026-10-06T09:00[Europe/Paris]')],
          save: (_) => pending.future,
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      historyOf(store).run(const MoveEvent('a', '2026-10-07T09:00[Europe/Paris]'));
      m.setRange(d('2027-03-01'), d('2027-03-08'), paris);
      expect('${(store.snapshot.getEvent('a')! as TimedEvent).start}', '2026-10-07T09:00:00+02:00[Europe/Paris]');
      pending.complete();
      await m.idle();
    });
  });

  group('jsonSource', () {
    test('asks for the stretch as instants and the zone, and reads the list', () async {
      final urls = <String>[];
      final (:m, :store, notices: _) = setup();
      m.add(
        jsonSource(
          'j',
          url: 'https://api.test/events?cal=7',
          params: {'team': 'a b'},
          request: (r) async {
            urls.add(r.url);
            return [
              {'id': 'a', 'start': '2026-10-06T09:00:00Z'},
            ];
          },
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      await m.idle();
      expect(urls, [
        'https://api.test/events?cal=7&team=a%20b&start=2026-09-30T10%3A00%3A00Z&end=2026-11-01T12%3A00%3A00Z&timeZone=Europe%2FParis',
      ]);
      expect(store.snapshot.getEvent('a')?.sourceId, 'j');
    });

    test('posts a form when asked, and maps the JSON', () async {
      final asked = <SourceHttpRequest>[];
      final (:m, :store, notices: _) = setup();
      m.add(
        jsonSource(
          'j',
          url: '/e',
          method: 'POST',
          startParam: 'from',
          zoneParam: null,
          request: (r) async {
            asked.add(r);
            return {
              'items': [
                {'id': 'a', 'start': '2026-10-06T09:00:00Z'},
              ],
            };
          },
          map: (raw) => readEventList((raw! as Map)['items']),
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      await m.idle();
      final r = asked.single;
      expect(
        [r.url, r.method, r.body, r.headers['content-type']],
        [
          '/e',
          'POST',
          'from=2026-09-30T10%3A00%3A00Z&end=2026-11-01T12%3A00%3A00Z',
          'application/x-www-form-urlencoded',
        ],
      );
      expect(store.snapshot.allEvents, hasLength(1));
    });

    test('an HTTP error (thrown by the application\'s request) is a failed fetch', () async {
      final (:m, store: _, :notices) = setup();
      m.add(jsonSource('j', url: '/e', request: (_) async => throw StateError('HTTP 503')));
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      await m.idle();
      expect((notices.whereType<SourceFetchFailed>().single.error as StateError).message, 'HTTP 503');
    });

    test('the zone sent: another zone asks again, in it; the events shown until the answer', () async {
      var answer = 'Paris';
      final urls = <String>[];
      final (:m, :store, notices: _) = setup();
      m.add(
        jsonSource(
          'j',
          url: '/e',
          request: (r) async {
            urls.add(r.url);
            return [
              {'id': 'a', 'title': answer, 'start': '2026-10-06T09:00:00Z'},
            ];
          },
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      await m.idle();
      answer = 'New York';
      m.setRange(d('2026-10-05'), d('2026-10-12'), 'America/New_York');
      expect(titles(store), ['Paris']);
      await m.idle();
      expect([for (final u in urls) u.substring(u.lastIndexOf('=') + 1)], ['Europe%2FParis', 'America%2FNew_York']);
      expect(titles(store), ['New York']);
    });

    test('a whole feed (unit none) is sent no zone: not asked again for another one', () async {
      final urls = <String>[];
      final (:m, store: _, notices: _) = setup();
      final spec = jsonSource(
        'j',
        url: '/e',
        chunk: ChunkPolicy.none,
        request: (r) async {
          urls.add(r.url);
          return [];
        },
      );
      m.add(spec);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      await m.idle();
      m.setRange(d('2026-10-05'), d('2026-10-12'), 'America/New_York');
      await m.idle();
      expect(
        [spec.zoneDependent, urls],
        [
          false,
          ['/e'],
        ],
      );
    });

    test('an item that is not an object is a problem; the others are read', () async {
      final (:m, :store, :notices) = setup();
      m.add(
        jsonSource(
          'j',
          url: '/e',
          request: (_) async => [
            'nope',
            {'id': 'a', 'start': '2026-10-06T09:00:00Z'},
          ],
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      await m.idle();
      expect(store.snapshot.getEvent('a'), isNotNull);
      final bad = notices.whereType<SourceProblems>().single.report.problems.where(
        (p) => p.code == ProblemCode.invalidEvent,
      );
      expect([for (final p in bad) p.path], ['answer[0]']);
    });
  });

  group('liveSource', () {
    CalendarKernel make(List<EventSourceSpec> sources) => CalendarKernel(
      KernelOptions(
        timeZone: paris,
        locale: 'fr-FR',
        initialDate: d('2026-10-21'),
        initialView: 'timeGridWeek',
        now: () => Instant.parse('2026-10-21T08:00:00Z'),
        sources: sources,
      ),
    );
    EventInput run(String id, String title, {Map<String, Object?>? props, String? start}) => EventInput(
      id: id,
      title: title,
      start: start ?? '2026-10-21T09:00[Europe/Paris]',
      duration: 'PT20M',
      extendedProps: props,
    );

    test(
      'each message changes its events: made, changed (props merged), gone, all anew; closed when removed',
      () async {
        final feed = StreamController<LiveMessage>();
        var listened = 0;
        final k = make([
          liveSource(
            'runs',
            connect: () {
              listened++;
              return feed.stream;
            },
          ),
        ]);
        List<String> seen() => [
          for (final e in k.store.snapshot.allEvents)
            if (e.sourceId == 'runs') '${e.id}:${e.title}:${e.props['status']}',
        ]..sort();
        feed.add(LiveCreate(run('a', 'Import', props: {'status': 'running', 'rows': 3})));
        await flush();
        final made = seen();
        feed
          ..add(LiveUpdate('a', EventInput(extendedProps: const {'status': 'ok'})))
          ..add(LiveCreate(run('b', 'Billing')));
        await flush();
        final changed = seen();
        final rows = k.store.snapshot.getEvent('a')?.props['rows'];
        feed.add(const LiveRemove('b'));
        await flush();
        final removed = seen();
        feed.add(LiveReset([run('c', 'Backup')]));
        await flush();
        final reset = seen();
        k.sources.remove('runs');
        expect(feed.hasListener, isFalse);
        expect(
          [made, changed, rows, removed, reset, listened, seen()],
          [
            ['a:Import:running'],
            ['a:Import:ok', 'b:Billing:null'],
            3,
            ['a:Import:ok'],
            ['c:Backup:null'],
            1,
            <String>[],
          ],
        );
        k.dispose();
      },
    );

    test(
      'an update of an event it never had changes nothing; one without an id is given one; dispose closes it',
      () async {
        final feed = StreamController<LiveMessage>();
        final k = make([liveSource('feed', connect: () => feed.stream)]);
        feed
          ..add(LiveUpdate('nobody', EventInput(title: 'x')))
          ..add(LiveCreate(EventInput(title: 'Anonymous', start: '2026-10-21T10:00[Europe/Paris]')));
        await flush();
        final ids = [for (final e in k.store.snapshot.allEvents) e.id];
        k.dispose();
        expect(ids, ['feed-1']);
        expect(feed.hasListener, isFalse);
      },
    );

    test('what the calendar forgot is not brought back by the next message, nor kept by the source', () async {
      final feed = StreamController<LiveMessage>();
      final spec = liveSource('feed', connect: () => feed.stream);
      var fetched = 0;
      final k = make([
        EventSourceSpec(
          id: spec.id,
          chunk: spec.chunk,
          live: spec.live,
          forgot: spec.forgot,
          fetch: (r) {
            final a = spec.fetch(r) as SourceAnswer;
            fetched = a.events.length;
            return a;
          },
        ),
      ]);
      feed
        ..add(
          LiveCreate(EventInput(id: 'old', title: 'Old', start: '2026-10-10T09:00[Europe/Paris]', duration: 'PT1H')),
        )
        ..add(LiveCreate(run('new', 'New')));
      await flush();
      k.forgetBefore(Instant.parse('2026-10-14T08:00:00Z'));
      feed.add(LiveCreate(run('newer', 'Newer', start: '2026-10-21T10:00[Europe/Paris]')));
      await flush();
      expect([for (final e in k.store.snapshot.allEvents) e.id]..sort(), ['new', 'newer']);
      expect(fetched, 2);
      k.dispose();
    });

    test('a run said finished without an end ends at the calendar\'s now, not the real clock', () async {
      final feed = StreamController<LiveMessage>();
      final k = make([liveSource('runs', connect: () => feed.stream)]);
      // Started 09:00 Paris (07:00Z), the calendar's clock at 08:00Z: an hour on.
      feed.add(
        LiveCreate(EventInput(id: 'r', title: 'Import', start: '2026-10-21T09:00[Europe/Paris]', ongoing: true)),
      );
      await flush();
      feed.add(LiveUpdate('r', EventInput(ongoing: false)));
      await flush();
      final e = k.store.snapshot.getEvent('r')! as TimedEvent;
      expect('${e.end.instant}', '2026-10-21T08:00:00Z');
      k.dispose();
    });
  });

  group('icalSource', () {
    const cal = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//test//EN
BEGIN:VEVENT
UID:one@test
DTSTART;TZID=Asia/Kolkata:20261021T093000
DTEND;TZID=Asia/Kolkata:20261021T101500
SUMMARY:Standup
END:VEVENT
BEGIN:VEVENT
UID:bad@test
DTSTART:nope
SUMMARY:Broken
END:VEVENT
END:VCALENDAR
''';
    FetchRequest req(String id) => FetchRequest(window: null, cancel: CancelToken.never, sourceId: id, zone: paris);

    test(
      'fetches the URL through the application\'s request, with its cancel token; events and what was wrong',
      () async {
        final asked = <SourceHttpRequest>[];
        final src = icalSource(
          'feed',
          url: 'https://example.com/a.ics',
          request: (r) async {
            asked.add(r);
            return cal;
          },
        );
        final a = await src.fetch(req('feed'));
        expect(asked.single.url, 'https://example.com/a.ics');
        expect(identical(asked.single.cancel, CancelToken.never), isTrue);
        expect([for (final e in a.events) e.title], ['Standup']);
        expect(a.problems, isNotEmpty);
        final inline = icalSource('mem', text: () => cal);
        expect((await inline.fetch(req('mem'))).events.first.title, 'Standup');
      },
    );

    test('a webcal:// link is fetched over HTTPS', () async {
      final urls = <String>[];
      final src = icalSource(
        'w',
        url: 'webcal://example.com/team.ics',
        request: (r) async {
          urls.add(r.url);
          return cal;
        },
      );
      await src.fetch(req('w'));
      expect(urls, ['https://example.com/team.ics']);
    });

    test('staleAfter and retry passed on; none by default', () {
      final feed = icalSource(
        'feed',
        url: 'u',
        request: (_) async => '',
        staleAfter: const Duration(minutes: 15),
        retry: const RetryPolicy(attempts: 3, backoff: Duration(milliseconds: 500)),
      );
      expect([feed.staleAfter, feed.retry?.attempts], [const Duration(minutes: 15), 3]);
      final plain = icalSource('feed', url: 'u', request: (_) async => '');
      expect([plain.staleAfter, plain.retry], [null, null]);
    });
  });

  group('decisions 58–60 and the 19i-2 reviews', () {
    CalendarKernel kernelWith(List<EventSourceSpec> sources) => CalendarKernel(
      KernelOptions(
        timeZone: paris,
        locale: 'fr',
        initialDate: d('2026-10-06'),
        initialView: 'timeGridWeek',
        now: () => Instant.parse('2026-10-06T06:00:00Z'),
        sources: sources,
      ),
    );
    final a = EventInput(
      id: 'a',
      title: 'A',
      start: '2026-10-06T09:00[Europe/Paris]',
      end: '2026-10-06T10:00[Europe/Paris]',
    );

    test('58: a person\'s change is saved, the application\'s own command is not; an undo is', () async {
      final sent = <(SaveCause, String)>[];
      final k = kernelWith([
        fnSource('s', (_) => [a], save: (r) => sent.add((r.cause, r.edits.single.id))),
      ]);
      k.run(const MoveEvent('a', '2026-10-07T09:00[Europe/Paris]')); // the app's: already saved elsewhere
      await k.sources.idle();
      expect(sent, isEmpty);
      k.run(const MoveEvent('a', '2026-10-08T09:00[Europe/Paris]'), validate: true); // a person's
      k.history.undo();
      await k.sources.idle();
      expect(sent, [(SaveCause.command, 'a'), (SaveCause.undo, 'a')]);
      k.dispose();
    });

    test('59: a creation goes to the source that takes them; the server\'s version, same id, adopted', () async {
      final server = <EventInput>[a];
      final sent = <SourceEdit>[];
      final k = kernelWith([
        fnSource(
          'agenda',
          (_) => [...server],
          createsHere: true,
          save: (r) {
            sent.addAll(r.edits);
            for (final e in r.edits) {
              server.add(e.input!);
            }
          },
        ),
      ]);
      expect(
        k
            .run(
              CreateEvent(EventInput(id: 'b', title: 'Booking', start: '2026-10-07T11:00[Europe/Paris]')),
              validate: true,
            )
            .ok,
        isTrue,
      );
      await k.sources.idle();
      final e = sent.single;
      expect([e.id, e.kind, e.input!.title], ['b', EditKind.created, 'Booking']);
      // Fetched again after the save: now the source's.
      expect(k.store.snapshot.getEvent('b')?.sourceId, 'agenda');
      k.dispose();
    });

    test('59: the server names it otherwise: the local copy goes, the server\'s stays', () async {
      final server = <EventInput>[a];
      final k = kernelWith([
        fnSource(
          'agenda',
          (_) => [...server],
          createsHere: true,
          save: (r) {
            for (final e in r.edits) {
              server.add(EventInput(id: 'srv-1', title: e.input!.title, start: e.input!.start, end: e.input!.end));
            }
          },
        ),
      ]);
      k.run(
        CreateEvent(EventInput(id: 'tmp', title: 'Booking', start: '2026-10-07T11:00[Europe/Paris]')),
        validate: true,
      );
      await k.sources.idle();
      expect(k.store.snapshot.getEvent('tmp'), isNull);
      expect(k.store.snapshot.getEvent('srv-1')?.sourceId, 'agenda');
      k.dispose();
    });

    test(
      '59: a refused creation is taken back, nothing to undo; without a source that takes them, nothing is sent',
      () async {
        final notices = <SourceNotice>[];
        final k = CalendarKernel(
          KernelOptions(
            timeZone: paris,
            locale: 'fr',
            initialDate: d('2026-10-06'),
            onSource: notices.add,
            sources: [
              fnSource('agenda', (_) => [a], createsHere: true, save: (_) => Future.error(StateError('409'))),
            ],
          ),
        );
        k.run(
          CreateEvent(EventInput(id: 'b', title: 'Booking', start: '2026-10-07T11:00[Europe/Paris]')),
          validate: true,
        );
        await k.sources.idle();
        expect(k.store.snapshot.getEvent('b'), isNull);
        expect(notices.whereType<SourceSaveFailed>().single.reverted, isTrue);
        expect(k.history.canUndo, isFalse);
        k.dispose();

        var saves = 0;
        final plain = kernelWith([
          fnSource('agenda', (_) => [a], save: (_) => saves++),
        ]);
        plain.run(
          CreateEvent(EventInput(id: 'c', title: 'Local', start: '2026-10-07T11:00[Europe/Paris]')),
          validate: true,
        );
        await plain.sources.idle();
        expect(saves, 0);
        expect(plain.store.snapshot.getEvent('c'), isNotNull);
        plain.dispose();
      },
    );

    test('a live feed\'s error and its end are notices, not crashes', () async {
      final feed = StreamController<LiveMessage>();
      final notices = <SourceNotice>[];
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final k = CalendarKernel(
          KernelOptions(
            timeZone: paris,
            locale: 'fr',
            sources: [liveSource('runs', connect: () => feed.stream)],
            onSource: notices.add,
          ),
        );
        feed.addError(StateError('socket lost'));
        await flush();
        await feed.close();
        await flush();
        k.dispose();
      }, (e, _) => errors.add(e));
      final failed = notices.whereType<SourceLiveFailed>().toList();
      expect([for (final f in failed) f.closed], [false, true]);
      expect(errors, isEmpty);
    });

    test('a live update keeps the application\'s own props as they are, and what reading said', () async {
      final feed = StreamController<LiveMessage>();
      final when = PlainDate(2026, 10, 21);
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr',
          initialDate: when,
          sources: [liveSource('runs', connect: () => feed.stream)],
        ),
      );
      feed.add(
        LiveCreate(
          EventInput(id: 'r', title: 'Run', start: '2026-10-21T09:00[Europe/Paris]', extendedProps: {'due': when}),
        ),
      );
      await flush();
      feed.add(LiveUpdate('r', EventInput(title: 'Run 2', extendedProps: const {'rows': 4})));
      await flush();
      final e = k.store.snapshot.getEvent('r')!;
      expect([e.title, e.props['due'], e.props['rows']], ['Run 2', when, 4]);
      k.dispose();
    });

    test('jsonSource gives the path and the parameters apart too (dio\'s baseUrl, queryParameters)', () async {
      final asked = <SourceHttpRequest>[];
      final (:m, store: _, notices: _) = setup();
      m.add(
        jsonSource(
          'j',
          url: '/events',
          zoneParam: null,
          request: (r) async {
            asked.add(r);
            return [];
          },
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      await m.idle();
      expect(
        [asked.single.path, asked.single.queryParameters],
        [
          '/events',
          {'start': '2026-09-30T10:00:00Z', 'end': '2026-11-01T12:00:00Z'},
        ],
      );
    });
  });
}
