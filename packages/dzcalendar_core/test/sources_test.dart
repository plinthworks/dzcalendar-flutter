// Phase 19i-1: the source manager, reading (owner's decisions 54, 57).
// Ported from the TypeScript core's sources.test.ts (hand-written
// expectations, copied as values): chunks (1), source manager (17 of 17),
// review fixes (3 of 9: the others are saves, 19i-2), hold (2), a spec
// replaced (1), kernel with sources (1).
// Translation notes:
// - `deferred()` is a `Completer`; `await flush()` is a turn of the event loop.
// - `signal.aborted` / `addEventListener('abort')` is the request's
//   `CancelToken` (`cancelled`, `whenCancelled`).
// - `SourceResult` (a list, or `{events, problems}`) is a `SourceAnswer`.
import 'dart:async';

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

const paris = 'Europe/Paris';
PlainDate d(String s) => PlainDate.parse(s);
NormalizeContext ctx() => NormalizeContext(displayZone: paris, newId: createIdGenerator('t'));

/// A source whose answers the test gives by hand, one per request, in order.
({EventSourceSpec spec, List<({FetchRequest req, Completer<SourceAnswer> answer})> calls}) manual(
  String id, {
  ChunkPolicy chunk = ChunkPolicy.month,
  RetryPolicy? retry,
  bool zoneDependent = false,
}) {
  final calls = <({FetchRequest req, Completer<SourceAnswer> answer})>[];
  final spec = EventSourceSpec(
    id: id,
    chunk: chunk,
    retry: retry,
    zoneDependent: zoneDependent,
    fetch: (req) {
      final answer = Completer<SourceAnswer>();
      calls.add((req: req, answer: answer));
      return answer.future;
    },
  );
  return (spec: spec, calls: calls);
}

String span(FetchRequest r) => '${r.window!.startDate}..${r.window!.endDate}';
Future<void> flush() => Future<void>.delayed(Duration.zero);
EventInput at(String id, String start, {String? title}) => EventInput(id: id, title: title ?? id, start: start);

({EventStore store, SourceManager m, List<SourceNotice> notices}) setup({
  Timers timers = const SystemTimers(),
  int keepChunks = 12,
  int maxConcurrent = 4,
  Instant Function()? now,
}) {
  final store = EventStore();
  final notices = <SourceNotice>[];
  final m = SourceManager(
    store: store,
    normalize: ctx,
    notify: notices.add,
    timers: timers,
    keepChunks: keepChunks,
    maxConcurrent: maxConcurrent,
    now: now,
  );
  return (store: store, m: m, notices: notices);
}

List<String> titles(EventStore store, [String from = '2026-01-01', String to = '2027-01-01']) => [
  for (final i in store.snapshot.queryInstances(viewWindow(d(from), d(to), paris))) i.event.title,
];

class FakeTimers implements Timers {
  final pending = <({void Function() fn, Duration after})>[];
  @override
  Object set(void Function() fn, Duration after) {
    final t = (fn: fn, after: after);
    pending.add(t);
    return t;
  }

  @override
  void clear(Object handle) => pending.remove(handle);
}

void main() {
  group('chunks', () {
    test('a week in October is the October chunk; a month grid is three months, one request', () {
      List<String> keys(ChunkUnit u, String a, String b, [int p = 0]) => [
        for (final c in chunksCovering(u, d(a), d(b), p)) c.key,
      ];
      expect(keys(ChunkUnit.month, '2026-10-19', '2026-10-26'), ['2026-10']);
      expect(keys(ChunkUnit.month, '2026-09-28', '2026-11-09'), ['2026-09', '2026-10', '2026-11']);
      expect(keys(ChunkUnit.month, '2026-10-19', '2026-10-26', 1), ['2026-09', '2026-10', '2026-11']);
      // Weeks begin on Monday whatever the locale: a chunk is a fetch, not a row.
      expect(keys(ChunkUnit.week, '2026-10-18', '2026-10-25'), ['2026-10-12', '2026-10-19']);
      expect(keys(ChunkUnit.year, '2026-12-28', '2027-01-04'), ['2026', '2027']);
    });
  });

  group('source manager', () {
    test('fetches the shown month, its window wide enough for every zone', () {
      final (:m, store: _, notices: _) = setup();
      final s = manual('s');
      m.add(s.spec);
      expect(s.calls, isEmpty); // nothing shown yet
      m.setRange(d('2026-10-19'), d('2026-10-26'), paris);
      expect(s.calls, hasLength(1));
      final w = s.calls[0].req.window!;
      expect(span(s.calls[0].req), '2026-10-01..2026-11-01');
      // 1 October begins first at UTC+14 (30 September, 10:00 UTC); 1 November ends last at UTC−12.
      expect('${w.start}', '2026-09-30T10:00:00Z');
      expect('${w.end}', '2026-11-01T12:00:00Z');
      expect(w.displayZone, paris);
    });

    test('two contiguous missing chunks go out as one request; a known one splits the run', () {
      final (:m, store: _, notices: _) = setup();
      final s = manual('s');
      m.add(s.spec);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      m.setRange(d('2026-08-31'), d('2026-12-07'), paris); // Aug, Sep, [Oct in flight], Nov, Dec
      expect(
        [for (final c in s.calls) span(c.req)],
        ['2026-10-01..2026-11-01', '2026-08-01..2026-10-01', '2026-11-01..2027-01-01'],
      );
    });

    test('cancels a request nobody shows any more, and ignores its late answer', () async {
      final (:m, :store, notices: _) = setup();
      final s = manual('s');
      m.add(s.spec);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      var cancelled = 0;
      unawaited(s.calls[0].req.cancel.whenCancelled.then((_) => cancelled++));
      m.setRange(d('2027-03-01'), d('2027-03-08'), paris);
      await flush();
      expect(cancelled, 1);
      expect(s.calls[0].req.cancel.cancelled, isTrue);
      s.calls[0].answer.complete(SourceAnswer([at('late', '2026-10-06T09:00[Europe/Paris]')]));
      await flush();
      expect(store.snapshot.getEvent('late'), isNull);
      // Back to October: asked again, not served from a cancelled request.
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      expect(
        [for (final c in s.calls) span(c.req)],
        ['2026-10-01..2026-11-01', '2027-03-01..2027-04-01', '2026-10-01..2026-11-01'],
      );
    });

    test('keeps a request half of which is still shown', () {
      final (:m, store: _, notices: _) = setup();
      final s = manual('s');
      m.add(s.spec);
      m.setRange(d('2026-09-28'), d('2026-11-09'), paris); // Sep..Nov
      m.setRange(d('2026-11-02'), d('2026-11-09'), paris); // Nov only
      expect(s.calls[0].req.cancel.cancelled, isFalse);
      expect(s.calls, hasLength(1));
    });

    test('a refetch ignores the answer of the generation before it', () async {
      final (:m, :store, notices: _) = setup();
      final s = manual('s');
      m.add(s.spec);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      m.refetch('s');
      expect(s.calls, hasLength(2));
      expect(s.calls[0].req.cancel.cancelled, isTrue);
      s.calls[1].answer.complete(SourceAnswer([at('new', '2026-10-06T09:00[Europe/Paris]')]));
      s.calls[0].answer.complete(SourceAnswer([at('old', '2026-10-06T09:00[Europe/Paris]')]));
      await flush();
      expect(titles(store), ['new']);
    });

    test('a refetch keeps the events on screen until the new answer replaces them', () async {
      final (:m, :store, notices: _) = setup();
      final s = manual('s');
      m.add(s.spec);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      s.calls[0].answer.complete(SourceAnswer([at('a', '2026-10-06T09:00[Europe/Paris]', title: 'A')]));
      await flush();
      m.refetch();
      expect(titles(store), ['A']);
      s.calls[1].answer.complete(SourceAnswer([at('a', '2026-10-06T09:00[Europe/Paris]', title: 'A2')]));
      await flush();
      expect(titles(store), ['A2']);
    });

    test('an event over two chunks belongs to both and leaves with the last', () async {
      final (:m, :store, notices: _) = setup(keepChunks: 0);
      final night = EventInput(
        id: 'night',
        title: 'night',
        start: '2026-10-31T22:00[Europe/Paris]',
        end: '2026-11-01T02:00[Europe/Paris]',
      );
      m.add(fnSource('s', (r) => r.window!.startDate.month <= 11 && r.window!.endDate.month >= 11 ? [night] : []));
      m.setRange(d('2026-10-26'), d('2026-11-02'), paris); // Oct + Nov: one request
      await flush();
      expect(store.snapshot.getEvent('night'), isNotNull);
      m.setRange(d('2026-11-02'), d('2026-11-09'), paris); // Oct dropped, Nov still holds it
      await flush();
      expect(store.snapshot.getEvent('night'), isNotNull);
      m.setRange(d('2027-02-01'), d('2027-02-08'), paris); // Nov dropped too
      await flush();
      expect(store.snapshot.getEvent('night'), isNull);
    });

    test('applies a multi-chunk answer as one store change', () async {
      final (:m, :store, notices: _) = setup();
      final s = manual('s');
      m.add(s.spec);
      m.setRange(d('2026-09-28'), d('2026-11-09'), paris);
      final changes = <StoreChange>[];
      store.subscribe(changes.add);
      s.calls[0].answer.complete(
        SourceAnswer([
          at('a', '2026-09-29T09:00[Europe/Paris]'),
          at('b', '2026-10-15T09:00[Europe/Paris]'),
          at('c', '2026-11-03T09:00[Europe/Paris]'),
        ]),
      );
      await flush();
      expect(changes, hasLength(1));
      expect(store.snapshot.allEvents, hasLength(3));
    });

    test('a synchronous source is in the store before setRange returns', () {
      final (:m, :store, notices: _) = setup();
      m.add(fnSource('s', (_) => [at('a', '2026-10-06T09:00[Europe/Paris]', title: 'A')]));
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      expect(titles(store), ['A']);
      expect(m.loading, isFalse);
    });

    test('a source not cut is fetched once, with no window, and never dropped', () {
      final (:m, :store, notices: _) = setup(keepChunks: 0);
      final asked = <FetchRequest>[];
      m.add(
        EventSourceSpec(
          id: 's',
          chunk: ChunkPolicy.none,
          fetch: (r) {
            asked.add(r);
            return SourceAnswer([at('a', '2026-10-06T09:00[Europe/Paris]')]);
          },
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      m.setRange(d('2030-10-05'), d('2030-10-12'), paris);
      expect(asked, hasLength(1));
      expect(asked[0].window, isNull);
      expect(store.snapshot.getEvent('a'), isNotNull);
    });

    test('changing the zone fetches nothing: a chunk is its dates everywhere', () {
      final (:m, store: _, notices: _) = setup();
      final s = manual('s');
      m.add(s.spec);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      m.setRange(d('2026-10-05'), d('2026-10-12'), 'Pacific/Kiritimati');
      m.setRange(d('2026-10-05'), d('2026-10-12'), 'Pacific/Pago_Pago');
      expect(s.calls, hasLength(1));
    });

    test('at most four requests at once, the rest queued', () async {
      final (:m, store: _, notices: _) = setup();
      final sources = [for (var i = 0; i < 6; i++) manual('s$i')];
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      for (final s in sources) {
        m.add(s.spec);
      }
      expect(sources.where((s) => s.calls.isNotEmpty), hasLength(4));
      sources[0].calls[0].answer.complete(const SourceAnswer([]));
      await flush();
      expect(sources.where((s) => s.calls.isNotEmpty), hasLength(5));
      expect(m.loading, isTrue);
    });

    test('says when it starts and stops loading', () async {
      final (:m, store: _, :notices) = setup();
      final s = manual('s');
      m.add(s.spec);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      expect(m.loading, isTrue);
      s.calls[0].answer.complete(const SourceAnswer([]));
      await m.idle();
      expect([for (final n in notices.whereType<SourceLoading>()) n.loading], [true, false]);
    });

    test('retries with exponential backoff, then reports the error', () async {
      final timers = FakeTimers();
      final (:m, store: _, :notices) = setup(timers: timers);
      final s = manual('s', retry: const RetryPolicy(attempts: 2, backoff: Duration(milliseconds: 100)));
      m.add(s.spec);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      s.calls[0].answer.completeError(StateError('down'));
      await flush();
      expect([for (final p in timers.pending) p.after.inMilliseconds], [100]);
      expect(m.loading, isTrue); // waiting to retry is still loading
      timers.pending.removeAt(0).fn();
      expect(s.calls, hasLength(2));
      s.calls[1].answer.completeError(StateError('down'));
      await flush();
      expect([for (final p in timers.pending) p.after.inMilliseconds], [200]);
      timers.pending.removeAt(0).fn();
      s.calls[2].answer.completeError(StateError('down'));
      await flush();
      final err = notices.whereType<SourceFetchFailed>().single;
      expect(
        [err.sourceId, err.chunks],
        [
          's',
          ['2026-10'],
        ],
      );
      expect(m.loading, isFalse);
      // The same range again (a locale changed, say): not asked again in a loop.
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      expect(s.calls, hasLength(3));
      // Shown again after moving away: asked again.
      m.setRange(d('2026-11-02'), d('2026-11-09'), paris);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      expect([for (final c in s.calls.skip(3)) span(c.req)], ['2026-11-01..2026-12-01', '2026-10-01..2026-11-01']);
    });

    test('a stale chunk is fetched again when shown; a fresh one is not', () {
      var t = Instant.parse('2026-10-17T10:00:00Z');
      final store = EventStore();
      final m = SourceManager(store: store, normalize: ctx, now: () => t);
      var fetched = 0;
      m.add(
        EventSourceSpec(
          id: 's',
          staleAfter: const Duration(minutes: 5),
          fetch: (_) {
            fetched++;
            return const SourceAnswer([]);
          },
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      t = t.addMs(4 * 60000);
      m.setRange(d('2026-10-12'), d('2026-10-19'), paris);
      expect(fetched, 1);
      t = t.addMs(2 * 60000);
      m.setRange(d('2026-10-19'), d('2026-10-26'), paris);
      expect(fetched, 2);
    });

    test('reports problems in a delivery, with the source named', () {
      final (:m, store: _, :notices) = setup();
      m.add(
        EventSourceSpec(
          id: 's',
          fetch: (_) => SourceAnswer(
            [EventInput(id: 'bad', start: 'yesterday')],
            problems: [Problem(ProblemCode.icalSyntax, Severity.error, 'line 3')],
          ),
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      final n = notices.whereType<SourceProblems>().single;
      expect([for (final p in n.report.problems) '${p.code.name} ${p.sourceId}'], ['icalSyntax s', 'invalidStart s']);
    });

    test('remove takes the source\'s events away', () {
      final (:m, :store, notices: _) = setup();
      m.add(fnSource('s', (_) => [at('a', '2026-10-06T09:00[Europe/Paris]')]));
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      m.remove('s');
      expect(store.snapshot.allEvents, isEmpty);
      expect(m.ids, isEmpty);
    });

    test('replacing a spec keeps the events until the new one answers', () async {
      final (:m, :store, notices: _) = setup();
      m.add(fnSource('s', (_) => [at('a', '2026-10-06T09:00[Europe/Paris]', title: 'A')]));
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      final next = manual('s');
      m.add(next.spec);
      expect(titles(store), ['A']);
      next.calls[0].answer.complete(SourceAnswer([at('a', '2026-10-06T09:00[Europe/Paris]', title: 'B')]));
      await flush();
      expect(titles(store), ['B']);
    });
  });

  group('review fixes', () {
    test('a source cannot take the id of the kernel\'s own events', () {
      final notices = <SourceNotice>[];
      final m = SourceManager(store: EventStore(), normalize: ctx, reserved: ['events'], notify: notices.add);
      m.add(fnSource('events', (_) => []));
      expect(m.ids, isEmpty);
      expect(
        [for (final p in notices.whereType<SourceProblems>().single.report.problems) p.code],
        [ProblemCode.duplicateId],
      );
    });

    test('removing a source lets the queued requests of the others go', () async {
      final (:m, store: _, notices: _) = setup(maxConcurrent: 1);
      final a = manual('a');
      final b = manual('b');
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      m.add(a.spec);
      m.add(b.spec);
      expect(b.calls, isEmpty);
      m.remove('a');
      expect(b.calls, hasLength(1));
      b.calls[0].answer.complete(const SourceAnswer([]));
      await m.idle();
      expect(m.loading, isFalse);
    });

    test('a new spec with another chunk unit drops what the old chunks held', () {
      final (:m, :store, notices: _) = setup();
      m.add(fnSource('s', (_) => [at('a', '2026-10-06T09:00[Europe/Paris]')]));
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      m.add(fnSource('s', (_) => [], chunk: const ChunkPolicy(ChunkUnit.week)));
      expect(store.snapshot.getEvent('a'), isNull);
    });
  });

  group('hold: other dates fetched and kept beside the shown ones (printing, exports)', () {
    test('fetches December beside October, ready once loaded, kept while held, then a spare chunk', () async {
      final (:m, :store, notices: _) = setup(keepChunks: 0);
      final s = manual('s');
      m.add(s.spec);
      m.setRange(d('2026-10-01'), d('2026-11-01'), paris);
      expect([for (final c in s.calls) span(c.req)], ['2026-10-01..2026-11-01']);
      final h = m.hold(d('2026-12-01'), d('2027-01-01'));
      expect([for (final c in s.calls) span(c.req)], ['2026-10-01..2026-11-01', '2026-12-01..2027-01-01']);
      List<String>? ready;
      unawaited(h.ready.then((r) => ready = r));
      s.calls[0].answer.complete(SourceAnswer([at('o', '2026-10-21T09:00[Europe/Paris]', title: 'Oct')]));
      await flush();
      expect(ready, isNull);
      s.calls[1].answer.complete(SourceAnswer([at('x', '2026-12-21T09:00[Europe/Paris]', title: 'Dec')]));
      await flush();
      expect(ready, isEmpty);
      expect(titles(store), ['Oct', 'Dec']);
      // Moving the shown range does not drop what is held.
      m.setRange(d('2026-11-01'), d('2026-12-01'), paris);
      expect(titles(store), contains('Dec'));
      h.release();
      // Released, with no spare chunk kept: gone (October too, no longer shown).
      expect(titles(store), isEmpty);
    });

    test('December fails: ready names it (source:chunk); what the file lacks is known', () async {
      final (:m, store: _, notices: _) = setup();
      final s = manual('s');
      m.add(s.spec);
      final h = m.hold(d('2026-12-01'), d('2027-01-01'));
      s.calls[0].answer.completeError(StateError('503'));
      await flush();
      final failed = await h.ready;
      expect(failed, ['s:2026-12']);
      h.release();
    });
  });

  group('a spec replaced under the same id', () {
    test('what the old spec fetched for dates no longer shown goes; the dates shown are fetched again', () async {
      final (:m, :store, notices: _) = setup();
      EventSourceSpec spec(String name) => fnSource('s', (r) {
        final s = r.window!.startDate;
        return [at('$name-${s.month}', '${s}T09:00[$paris]', title: '$name ${s.month}')];
      });
      m.add(spec('old'));
      m.setRange(d('2026-10-01'), d('2026-11-01'), paris);
      await m.idle();
      m.setRange(d('2026-11-01'), d('2026-12-01'), paris);
      await m.idle();
      expect(titles(store), ['old 10', 'old 11']);
      m.add(spec('new'));
      await m.idle();
      // October, not shown, held the old spec's answer: gone, not served when it is shown again.
      expect(titles(store), ['new 11']);
    });
  });

  group('kernel with sources', () {
    test('fetches what each view shows as it moves, not again on a zone change', () {
      final asked = <String>[];
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          initialDate: d('2026-10-21'),
          initialView: 'timeGridWeek',
          now: () => Instant.parse('2026-10-21T08:00:00Z'),
          sources: [
            fnSource('s', (r) {
              asked.add(span(r));
              return [at('a', '2026-10-21T09:00[Europe/Paris]', title: 'A')];
            }),
          ],
        ),
      );
      expect(asked, ['2026-10-01..2026-11-01']);
      expect(k.store.snapshot.getEvent('a')?.sourceId, 's');
      k.navigate(NavDirection.next); // 26 Oct – 1 Nov: still October
      k.navigate(NavDirection.next); // 2 – 8 Nov
      k.setTimeZone('Asia/Kolkata');
      k.setView('dayGridMonth'); // November's grid runs into December
      expect(asked, ['2026-10-01..2026-11-01', '2026-11-01..2026-12-01', '2026-12-01..2027-01-01']);
      k.dispose();
    });

    test('the sources\' notices reach onSource and the subscribers; disposing cancels what is out', () async {
      final told = <SourceNotice>[];
      final s = manual('s');
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          initialDate: d('2026-10-21'),
          sources: [s.spec],
          onSource: told.add,
        ),
      );
      final events = <KernelEvent>[];
      k.subscribe(events.add);
      expect(told.whereType<SourceLoading>().single.loading, isTrue);
      expect(k.sources.loading, isTrue);
      s.calls[0].answer.complete(SourceAnswer([at('a', '2026-10-21T09:00[Europe/Paris]')]));
      await k.sources.idle();
      expect([for (final n in told.whereType<SourceLoading>()) n.loading], [true, false]);
      expect(events.whereType<KernelSourceEvent>(), hasLength(1));
      expect(events.whereType<KernelStoreEvent>(), hasLength(1));
      k.sources.refetch();
      expect(s.calls, hasLength(2));
      k.dispose();
      expect(s.calls[1].req.cancel.cancelled, isTrue);
    });

    test('a source cannot be named "events" (the kernel\'s own list)', () {
      final told = <SourceNotice>[];
      final k = CalendarKernel(
        KernelOptions(timeZone: paris, locale: 'fr', sources: [fnSource('events', (_) => [])], onSource: told.add),
      );
      expect(k.sources.ids, isEmpty);
      expect(told.whereType<SourceProblems>(), hasLength(1));
    });

    test('forgetBefore: a source delivering an event forgotten does not bring it back', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr',
          initialDate: d('2026-10-21'),
          initialView: 'dayGridMonth',
          sources: [
            fnSource(
              's',
              (_) => [at('old', '2026-10-02T09:00[Europe/Paris]'), at('new', '2026-10-25T09:00[Europe/Paris]')],
            ),
          ],
        ),
      );
      expect(k.forgetBefore(Instant.parse('2026-10-10T00:00:00Z')), 1);
      k.sources.refetch();
      expect(k.store.snapshot.getEvent('old'), isNull);
      expect(k.store.snapshot.getEvent('new'), isNotNull);
    });
  });

  group('after the 19i-1 reviews', () {
    test('a zone-dependent source: told the zone, asked again in another, its events shown until the answer', () async {
      final (:m, :store, notices: _) = setup();
      final told = manual('z', zoneDependent: true);
      final plain = manual('p');
      final whole = manual('w', chunk: ChunkPolicy.none, zoneDependent: true);
      m.add(told.spec);
      m.add(plain.spec);
      m.add(whole.spec);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      expect(told.calls[0].req.zone, paris);
      told.calls[0].answer.complete(SourceAnswer([at('a', '2026-10-06T09:00[Europe/Paris]', title: 'Paris')]));
      plain.calls[0].answer.complete(const SourceAnswer([]));
      whole.calls[0].answer.complete(const SourceAnswer([]));
      await m.idle();
      m.setRange(d('2026-10-05'), d('2026-10-12'), 'America/New_York');
      expect(titles(store), ['Paris']);
      expect([told.calls.length, plain.calls.length], [2, 1]);
      expect(told.calls[1].req.zone, 'America/New_York');
      expect(told.calls[1].req.window!.displayZone, 'America/New_York');
      told.calls[1].answer.complete(SourceAnswer([at('a', '2026-10-06T09:00[Europe/Paris]', title: 'New York')]));
      // A whole feed, zone-dependent: asked again too (the TS: jsonSource sends none, so it is not marked).
      for (final c in whole.calls.skip(1)) {
        c.answer.complete(const SourceAnswer([]));
      }
      await m.idle();
      expect(titles(store), ['New York']);
    });

    test('prefetch: the chunks either side asked with the shown one, one request', () {
      final (:m, store: _, notices: _) = setup();
      final s = manual('s', chunk: const ChunkPolicy(ChunkUnit.week, prefetch: 1));
      m.add(s.spec);
      m.setRange(d('2026-10-19'), d('2026-10-26'), paris);
      expect([for (final c in s.calls) span(c.req)], ['2026-10-12..2026-11-02']);
      // A week on: the one after is new, alone.
      m.setRange(d('2026-10-26'), d('2026-11-02'), paris);
      expect([for (final c in s.calls) span(c.req)].last, '2026-11-02..2026-11-09');
    });

    test(
      'a series, and its override, go to every chunk of a multi-chunk answer: they stay while one is kept',
      () async {
        final (:m, :store, notices: _) = setup(keepChunks: 0);
        final s = manual('s');
        m.add(s.spec);
        m.setRange(d('2026-09-28'), d('2026-11-09'), paris); // Sep..Nov, one request
        s.calls[0].answer.complete(
          SourceAnswer([
            EventInput(
              id: 'w',
              title: 'standup',
              start: '2026-09-07T09:00[Europe/Paris]',
              rrule: 'FREQ=WEEKLY;COUNT=20',
            ),
            EventInput(
              id: 'w2',
              title: 'late',
              seriesId: 'w',
              recurrenceId: '2026-09-14T09:00:00+02:00[Europe/Paris]',
              start: '2026-09-14T11:00[Europe/Paris]',
            ),
          ]),
        );
        await flush();
        m.setRange(d('2026-11-02'), d('2026-11-09'), paris); // only November now
        expect(store.snapshot.getSeries('w'), isNotNull);
        expect(store.snapshot.getEvent('w2'), isNotNull);
      },
    );

    test('a fetch that throws at once is retried; an error the policy refuses is not; the backoff capped', () async {
      final timers = FakeTimers();
      final (:m, store: _, :notices) = setup(timers: timers);
      var tries = 0;
      m.add(
        EventSourceSpec(
          id: 's',
          retry: RetryPolicy(
            attempts: 5,
            backoff: const Duration(seconds: 1),
            maxBackoff: const Duration(seconds: 3),
            retryIf: (e) => e is! ArgumentError,
          ),
          fetch: (_) {
            tries++;
            throw tries < 4 ? StateError('down') : ArgumentError('403');
          },
        ),
      );
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      final waits = <int>[];
      while (timers.pending.isNotEmpty) {
        final p = timers.pending.removeAt(0);
        waits.add(p.after.inSeconds);
        p.fn();
      }
      expect(waits, [1, 2, 3]); // 4 capped to 3; the 4th error is refused: no more
      expect(tries, 4);
      expect(notices.whereType<SourceFetchFailed>().single.error, isA<ArgumentError>());
    });

    test('a spec made again with the same key replaces the old one without fetching', () {
      final (:m, store: _, notices: _) = setup();
      var fetched = 0;
      EventSourceSpec spec() => fnSource('s', (_) {
        fetched++;
        return [];
      }, key: 'agenda-42');
      m.add(spec());
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      m.add(spec());
      m.add(spec());
      expect(fetched, 1);
      m.add(fnSource('s', (_) => [], key: 'agenda-43'));
      expect(fetched, 1); // another key: the new spec's own fetch
    });

    test('nothing is told after destroy; idle completes', () async {
      final (:m, store: _, :notices) = setup();
      final s = manual('s');
      m.add(s.spec);
      m.setRange(d('2026-10-05'), d('2026-10-12'), paris);
      final idle = m.idle();
      final before = notices.length;
      m.destroy();
      await idle;
      expect(notices.length, before);
      expect(s.calls[0].req.cancel.cancelled, isTrue);
    });

    test('a request held before anything is shown has a window, in the calendar\'s zone', () {
      final (:m, store: _, notices: _) = setup();
      final s = manual('s');
      m.add(s.spec);
      m.hold(d('2026-12-01'), d('2027-01-01'));
      expect(span(s.calls.single.req), '2026-12-01..2027-01-01');
      expect(s.calls.single.req.window!.displayZone, paris);
    });

    test('withDefaults keeps every field given, and fills every one missing', () {
      final full = EventInput(
        id: 'i',
        groupId: 'g',
        title: 't',
        start: 's',
        end: 'e',
        duration: 'PT1H',
        allDay: true,
        timeZone: paris,
        resourceId: 'r',
        resourceIds: const ['r'],
        rrule: 'FREQ=DAILY',
        exdate: const ['x'],
        rdate: const ['y'],
        seriesId: 'si',
        recurrenceId: 'ri',
        display: EventDisplay.block,
        status: EventStatus.tentative,
        busy: false,
        editable: false,
        startEditable: false,
        durationEditable: false,
        resourceEditable: false,
        classNames: const ['c'],
        tone: 'blue',
        url: 'u',
        extendedProps: const {'k': 1},
        ongoing: true,
      );
      expect(EventInput().withDefaults(full).toJson(), full.toJson());
      expect(full.withDefaults(EventInput(title: 'other', tone: 'red')).toJson(), full.toJson());
    });
  });
}
