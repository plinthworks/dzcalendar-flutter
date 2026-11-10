import 'dart:async';

import '../event/normalize.dart';
import '../event/problem.dart';
import '../event/types.dart';
import '../store/store.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'chunks.dart';
import 'source.dart';

/// What the manager tells its owner. Not sealed: saves (19i-2) add kinds —
/// keep a default branch.
abstract class SourceNotice {
  const SourceNotice();
}

/// Fetching started (true) or everything settled (false).
final class SourceLoading extends SourceNotice {
  const SourceLoading(this.loading);
  final bool loading;
}

/// A fetch failed for good (after its retries). The chunks keep what they had.
final class SourceFetchFailed extends SourceNotice {
  const SourceFetchFailed(this.sourceId, this.chunks, this.error, [this.stack]);
  final String sourceId;
  final List<String> chunks;
  final Object error;
  final StackTrace? stack;
}

/// Some events of a delivery were refused or bent, or a source could not be added.
final class SourceProblems extends SourceNotice {
  const SourceProblems(this.sourceId, this.report);
  final String sourceId;
  final NormalizationReport report;
}

/// Timers, injectable for tests.
abstract interface class Timers {
  Object set(void Function() fn, Duration after);
  void clear(Object handle);
}

final class SystemTimers implements Timers {
  const SystemTimers();
  @override
  Object set(void Function() fn, Duration after) => Timer(after, fn);
  @override
  void clear(Object handle) => (handle as Timer).cancel();
}

/// Dates held beside the shown ones (`hold`): [ready] completes once
/// nothing is fetching, with the held chunks that could not be loaded
/// (`source:chunk`) — what a print or an export lacks.
final class SourceHold {
  SourceHold._(this.ready, this._release);
  final Future<List<String>> ready;
  final void Function() _release;
  var _held = true;

  /// What it loaded stays as spare chunks (the least recently shown dropped first).
  void release() {
    if (!_held) return;
    _held = false;
    _release();
  }
}

enum _ReqState { queued, running, waiting, done }

class _Request {
  _Request(this.src, this.chunks, this.gen);
  final _Source src;
  final List<Chunk> chunks;
  final int gen;
  final cancel = CancelSource();
  var attempt = 0;
  var state = _ReqState.queued;
  Object? timer;
}

class _Entry {
  _Entry(this.lastUsed, [this.req]);

  /// When its events were delivered (epoch ms); null while the first fetch is out.
  int? fetchedAt;

  /// Asked to be fetched again (`refetch`), whatever its age.
  var stale = false;
  _Request? req;
  int lastUsed;
}

class _Source {
  _Source(this.spec);
  EventSourceSpec spec;
  var gen = 0;
  final cache = <String, _Entry>{};
  final requests = <_Request>{};
}

/// The key of a source not cut: one chunk for all of time.
const wholeChunk = '*';

/// Fetches each source's events chunk by chunk as the calendar moves, and
/// keeps the store in step (owner's decision 54): contiguous missing chunks
/// go out as one request, at most [maxConcurrent] at once; a request nobody
/// needs any more is cancelled; an answer from before a refetch is ignored;
/// a chunk is applied atomically (an event over two chunks is owned by both
/// and leaves with the last).
final class SourceManager {
  SourceManager({
    required this.store,
    required this.normalize,
    void Function(SourceNotice notice)? notify,
    Instant Function()? now,
    Timers timers = const SystemTimers(),
    this.maxConcurrent = 4,
    this.keepChunks = 12,
    this.reserved = const [],
    int? Function()? forgotten,
  }) : _notify = notify ?? ((_) {}),
       _now = now,
       _timers = timers,
       _forgotten = forgotten;

  final EventStore store;

  /// Read at every delivery: the zone may have changed since.
  final NormalizeContext Function() normalize;

  /// Requests in flight at once, all sources together.
  final int maxConcurrent;

  /// Loaded chunks kept per source outside what is needed, the least
  /// recently shown dropped first.
  final int keepChunks;

  /// Ids the owner loads by other means (the kernel's `events`): refused,
  /// with a `duplicate-id` problem.
  final List<String> reserved;

  final void Function(SourceNotice) _notify;
  final Instant Function()? _now;
  final Timers _timers;

  /// The events that ended before this (epoch ms) are forgotten: a delivery
  /// does not bring them back.
  final int? Function()? _forgotten;

  final _sources = <String, _Source>{};
  final _queue = <_Request>[];
  var _running = 0;
  var _waiting = 0;
  var _tick = 0;
  ({PlainDate start, PlainDate end, ZoneId zone})? _range;
  final _holds = <({PlainDate start, PlainDate end})>{};
  var _loading = false;
  var _idlers = <Completer<void>>[];
  var _destroyed = false;

  int _nowMs() =>
      (_now?.call() ?? Instant.fromEpochMilliseconds(DateTime.now().millisecondsSinceEpoch)).epochMilliseconds;

  bool get _busy => _queue.length + _running + _waiting > 0;

  /// Something is being fetched, queued or waiting to be tried again.
  bool get loading => _loading;

  void _say(SourceNotice n) {
    // Torn down: nobody to tell (an app reacting while it disposes would throw).
    if (_destroyed) return;
    try {
      _notify(n);
    } catch (e, st) {
      Zone.current.handleUncaughtError(e, st);
    }
  }

  void _settle() {
    final now = _busy;
    if (now != _loading) {
      _loading = now;
      _say(SourceLoading(now));
    }
    if (!now && _idlers.isNotEmpty) {
      final done = _idlers;
      _idlers = [];
      for (final c in done) {
        c.complete();
      }
    }
  }

  List<Chunk> _whole() => [Chunk(wholeChunk, PlainDate(1970, 1, 1), PlainDate(1970, 1, 1))];

  List<Chunk> _needed(_Source src) {
    final policy = src.spec.chunk;
    if (policy.unit == ChunkUnit.none) return _whole();
    final r = _range;
    final out = r == null ? <Chunk>[] : chunksCovering(policy.unit, r.start, r.end, policy.prefetch);
    if (_holds.isEmpty) return out;
    final seen = {for (final c in out) c.key};
    for (final h in _holds) {
      for (final c in chunksCovering(policy.unit, h.start, h.end)) {
        if (seen.add(c.key)) out.add(c);
      }
    }
    return out;
  }

  /// Drops chunks from the store (and the cache).
  void _drop(_Source src, List<String> keys) {
    if (keys.isEmpty) return;
    for (final k in keys) {
      src.cache.remove(k);
    }
    store.replaceSourceChunks(src.spec.id, [for (final k in keys) (k, const <Normalized>[])]);
  }

  void _abort(_Request req) {
    switch (req.state) {
      case _ReqState.done:
        return;
      case _ReqState.waiting:
        _timers.clear(req.timer!);
        _waiting--;
      case _ReqState.running:
        _running--;
      case _ReqState.queued:
        _queue.remove(req);
    }
    req.state = _ReqState.done;
    req.cancel.cancel();
    req.src.requests.remove(req);
    // Chunks never loaded go; loaded ones keep their (stale) events.
    for (final c in req.chunks) {
      final e = req.src.cache[c.key];
      if (e == null || e.req != req) continue;
      if (e.fetchedAt == null) {
        req.src.cache.remove(c.key);
      } else {
        e.req = null;
      }
    }
  }

  void _sync(_Source src) {
    final needed = _needed(src);
    final keys = {for (final c in needed) c.key};
    final stale = src.spec.staleAfter?.inMilliseconds;
    final t = _nowMs();
    _tick++;
    // Nobody needs it any more: cancelled.
    for (final req in [...src.requests]) {
      if (!req.chunks.any((c) => keys.contains(c.key))) _abort(req);
    }
    var run = <Chunk>[];
    final runs = <List<Chunk>>[];
    for (final c in needed) {
      final e = src.cache[c.key];
      if (e != null) e.lastUsed = _tick;
      final fetchedAt = e?.fetchedAt;
      final missing =
          e == null || (e.req == null && fetchedAt != null && (e.stale || (stale != null && t - fetchedAt >= stale)));
      if (missing) {
        run.add(c);
      } else if (run.isNotEmpty) {
        runs.add(run);
        run = [];
      }
    }
    if (run.isNotEmpty) runs.add(run);
    for (final chunks in runs) {
      _request(src, chunks);
    }
    // A few chunks kept for going back; the rest dropped.
    final spare = [
      for (final MapEntry(key: k, value: e) in src.cache.entries)
        if (!keys.contains(k) && e.req == null && e.fetchedAt != null) (k, e),
    ]..sort((a, b) => b.$2.lastUsed - a.$2.lastUsed);
    _drop(src, [for (final (k, _) in spare.skip(keepChunks)) k]);
    _dispatch();
    _settle();
  }

  void _request(_Source src, List<Chunk> chunks) {
    final req = _Request(src, chunks, src.gen);
    for (final c in chunks) {
      final e = src.cache[c.key];
      if (e != null) {
        e.req = req;
      } else {
        src.cache[c.key] = _Entry(_tick, req);
      }
    }
    src.requests.add(req);
    _queue.add(req);
  }

  void _dispatch() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final req = _queue.removeAt(0);
      req.state = _ReqState.running;
      _running++;
      _start(req);
    }
  }

  void _start(_Request req) {
    final src = req.src;
    final r = _range;
    // Held dates before anything is shown: read in the calendar's zone.
    final zone = r?.zone ?? normalize().displayZone;
    final window = src.spec.chunk.unit == ChunkUnit.none
        ? null
        : datesWindow(req.chunks.first.start, req.chunks.last.end, zone);
    final FutureOr<SourceAnswer> answer;
    try {
      answer = src.spec.fetch(
        FetchRequest(window: window, cancel: req.cancel.token, sourceId: src.spec.id, zone: zone),
      );
    } catch (e, st) {
      _failed(req, e, st);
      return;
    }
    if (answer is Future<SourceAnswer>) {
      answer.then((v) => _delivered(req, v), onError: (Object e, StackTrace st) => _failed(req, e, st));
    } else {
      _delivered(req, answer);
    }
  }

  /// False for an answer nobody waits for any more: cancelled, or from before a refetch.
  bool _current(_Request req) =>
      req.state == _ReqState.running &&
      !_destroyed &&
      req.gen == req.src.gen &&
      identical(_sources[req.src.spec.id], req.src);

  void _finish(_Request req) {
    if (req.state == _ReqState.running) _running--;
    req.state = _ReqState.done;
    req.src.requests.remove(req);
  }

  void _late(_Request req) {
    if (req.state == _ReqState.running) _finish(req);
    _dispatch();
    _settle();
  }

  void _delivered(_Request req, SourceAnswer v) {
    if (!_current(req)) return _late(req);
    final src = req.src;
    final gen = src.gen;
    _finish(req);
    try {
      _apply(src, req.chunks, v.events, v.problems);
    } catch (e, st) {
      // Not applied: as a failed fetch (what was loaded before stays).
      _release(req);
      _say(SourceFetchFailed(src.spec.id, [for (final c in req.chunks) c.key], e, st));
      _dispatch();
      _settle();
      return;
    }
    // Fetched again while this was applied (a listener's refetch): its chunks stay stale.
    final again = src.gen != gen;
    final t = _nowMs();
    for (final c in req.chunks) {
      final e = src.cache[c.key];
      if (e != null && e.req == req) {
        e.req = null;
        e.fetchedAt = t;
        e.stale = again;
      }
    }
    if (again && identical(_sources[src.spec.id], src)) _sync(src);
    _dispatch();
    _settle();
  }

  /// [req]'s chunks without it: never loaded, forgotten; loaded before, kept.
  void _release(_Request req) {
    for (final c in req.chunks) {
      final e = req.src.cache[c.key];
      if (e == null || e.req != req) continue;
      if (e.fetchedAt == null) {
        req.src.cache.remove(c.key);
      } else {
        e.req = null;
      }
    }
  }

  void _failed(_Request req, Object error, StackTrace stack) {
    if (!_current(req)) return _late(req);
    final retry = req.src.spec.retry;
    var again = retry != null && req.attempt < retry.attempts;
    if (again) {
      try {
        again = retry.retryIf?.call(error) ?? true;
      } catch (e, st) {
        Zone.current.handleUncaughtError(e, st);
        again = false;
      }
    }
    if (retry != null && again) {
      _running--;
      req.attempt++;
      req.state = _ReqState.waiting;
      _waiting++;
      req.timer = _timers.set(() {
        if (req.state != _ReqState.waiting) return;
        _waiting--;
        req.state = _ReqState.queued;
        _queue.add(req);
        _dispatch();
        _settle();
      }, _backoff(retry, req.attempt));
      _dispatch();
      _settle();
      return;
    }
    _finish(req);
    for (final c in req.chunks) {
      final e = req.src.cache[c.key];
      if (e == null || e.req != req) continue;
      // Never loaded: asked again when the shown range next changes. Loaded
      // before: what it had stays, until it is stale or fetched again.
      if (e.fetchedAt == null) {
        req.src.cache.remove(c.key);
      } else {
        e.req = null;
      }
    }
    _say(SourceFetchFailed(req.src.spec.id, [for (final c in req.chunks) c.key], error, stack));
    _dispatch();
    _settle();
  }

  static Duration _backoff(RetryPolicy retry, int attempt) {
    final max = retry.maxBackoff;
    var d = retry.backoff;
    for (var i = 1; i < attempt && (max == null || d < max); i++) {
      d *= 2;
    }
    return max != null && d > max ? max : d;
  }

  /// Normalizes the whole answer first (derived ids depend on the batch),
  /// then gives each chunk what meets it. A series, and the overrides of a
  /// series in the answer, go to every chunk asked; so does an event meeting
  /// none.
  void _apply(_Source src, List<Chunk> chunks, List<EventInput> inputs, List<Problem> problems) {
    final id = src.spec.id;
    final defaults = src.spec.defaults;
    final ctx = normalize();
    final normalized = normalizeMany(
      defaults == null ? inputs : [for (final e in inputs) e.withDefaults(defaults)],
      ctx,
      sourceId: id,
    );
    final report = normalized.report;
    // What is forgotten stays so: an event that ended before the mark is not brought back (a series is its rule's).
    final mark = _forgotten?.call();
    bool kept(CalEvent e) => switch (e) {
      AllDayEvent(:final end) => end.startOfDayIn(ctx.displayZone).epochMilliseconds > mark!,
      TimedEvent(:final ongoing) when ongoing => true,
      TimedEvent(:final end) => end.epochMilliseconds > mark!,
    };
    final items = mark == null
        ? normalized.items
        : [
            for (final n in normalized.items)
              if (n is! NormalizedEvent || kept(n.event)) n,
          ];
    if (problems.isNotEmpty || report.problems.isNotEmpty) {
      _say(
        SourceProblems(
          id,
          NormalizationReport(report.accepted, report.rejected, [
            for (final p in problems) p.withSource(id),
            ...report.problems,
          ]),
        ),
      );
    }
    final entries = [for (final c in chunks) (c.key, <Normalized>[])];
    if (chunks.length == 1) {
      entries.first.$2.addAll(items);
    } else {
      final zone = _range?.zone ?? ctx.displayZone;
      final seriesIds = {
        for (final n in items)
          if (n is NormalizedSeries) n.series.id,
      };
      final spans = [for (final c in chunks) datesWindow(c.start, c.end, zone)];
      for (final n in items) {
        final ev = n.event;
        final ref = ev.ref;
        final everywhere = n is NormalizedSeries || (ref != null && seriesIds.contains(ref.seriesId));
        var met = false;
        if (!everywhere) {
          for (var i = 0; i < chunks.length; i++) {
            final c = chunks[i];
            final hit = switch (ev) {
              AllDayEvent(:final start, :final end) => start.isBefore(c.end) && end.isAfter(c.start),
              TimedEvent(:final start, :final end) => () {
                final s = start.epochMilliseconds;
                final e = end.epochMilliseconds;
                final w = spans[i];
                return s < w.end.epochMilliseconds &&
                    (e > w.start.epochMilliseconds || (e == s && s >= w.start.epochMilliseconds));
              }(),
            };
            if (hit) {
              entries[i].$2.add(n);
              met = true;
            }
          }
        }
        if (!met) {
          for (final e in entries) {
            e.$2.add(n);
          }
        }
      }
    }
    store.replaceSourceChunks(id, entries);
  }

  // ——— the owner's calls ———

  /// Adds a source, or replaces the one with its id: its events stay until
  /// the new spec's arrive.
  void add(EventSourceSpec spec) {
    if (_destroyed) return;
    if (reserved.contains(spec.id)) {
      _say(
        SourceProblems(
          spec.id,
          NormalizationReport(0, 0, [
            Problem(ProblemCode.duplicateId, Severity.error, 'sources', spec.id).withSource(spec.id),
          ]),
        ),
      );
      return;
    }
    final prev = _sources[spec.id];
    if (prev != null) {
      if (identical(prev.spec, spec)) return;
      // The same source made again (a provider rebuilt): taken, nothing fetched.
      if (spec.key != null && spec.key == prev.spec.key && spec.chunk == prev.spec.chunk) {
        prev.spec = spec;
        return;
      }
      final recut = prev.spec.chunk.unit != spec.chunk.unit;
      prev.spec = spec;
      if (recut) {
        // Other chunk keys: what the old ones hold would never be replaced.
        prev.gen++;
        for (final req in [...prev.requests]) {
          _abort(req);
        }
        _drop(prev, [...prev.cache.keys]);
      } else {
        // What another spec fetched for dates not shown would come back unchanged when they are: gone.
        final shown = {for (final c in _needed(prev)) c.key};
        _drop(prev, [
          for (final k in prev.cache.keys)
            if (!shown.contains(k)) k,
        ]);
      }
      refetch(spec.id);
      return;
    }
    final src = _Source(spec);
    _sources[spec.id] = src;
    _sync(src);
  }

  /// Withdraws a source and its events.
  void remove(String id) {
    final src = _sources[id];
    if (src == null) return;
    src.gen++;
    for (final req in [...src.requests]) {
      _abort(req);
    }
    _sources.remove(id);
    final keys = [...src.cache.keys];
    src.cache.clear();
    if (keys.isNotEmpty) store.replaceSourceChunks(id, [for (final k in keys) (k, const <Normalized>[])]);
    _dispatch();
    _settle();
  }

  EventSourceSpec? operator [](String id) => _sources[id]?.spec;
  List<String> get ids => [..._sources.keys];

  /// What is shown: `[start, end)` dates, read in [zone]. Fetches what is missing.
  void setRange(PlainDate start, PlainDate end, ZoneId zone) {
    if (_destroyed) return;
    final r = _range;
    // The same range again (a locale or an option changed): nothing to fetch,
    // and a chunk that just failed is not asked again in a loop.
    if (r != null && r.start == start && r.end == end && r.zone == zone) return;
    // Another zone: what a source was told in the old one is asked again.
    final rezoned = r != null && r.zone != zone;
    _range = (start: start, end: end, zone: zone);
    for (final src in [..._sources.values]) {
      if (rezoned && src.spec.zoneDependent) {
        refetch(src.spec.id);
      } else {
        _sync(src);
      }
    }
  }

  /// Fetches again (one source, or all); the events stay until the answers
  /// replace them. Older answers are ignored.
  void refetch([String? id]) {
    if (_destroyed) return;
    final which = id == null ? [..._sources.values] : [?_sources[id]];
    for (final src in which) {
      src.gen++;
      for (final req in [...src.requests]) {
        _abort(req);
      }
      // Every loaded chunk stale, whatever its age: the shown ones are asked
      // again now, their events kept until the answers replace them.
      for (final e in src.cache.values) {
        e.stale = true;
      }
      _sync(src);
    }
  }

  /// Completes once nothing is fetching or waiting to retry.
  Future<void> idle() {
    if (!_busy) return Future.value();
    final c = Completer<void>();
    _idlers.add(c);
    return c.future;
  }

  /// Fetches `[start, end)` (dates in the shown zone) beside what is shown
  /// and keeps it until released (a print or an export of other dates).
  SourceHold hold(PlainDate start, PlainDate end) {
    final h = (start: start, end: end);
    _holds.add(h);
    for (final src in [..._sources.values]) {
      _sync(src);
    }
    final ready = idle().then((_) {
      final failed = <String>[];
      for (final src in _sources.values) {
        final unit = src.spec.chunk.unit;
        for (final c in unit == ChunkUnit.none ? _whole() : chunksCovering(unit, start, end)) {
          final e = src.cache[c.key];
          if (e == null || e.fetchedAt == null) failed.add('${src.spec.id}:${c.key}');
        }
      }
      return failed;
    });
    return SourceHold._(ready, () {
      if (_destroyed) return;
      _holds.remove(h);
      for (final src in [..._sources.values]) {
        _sync(src);
      }
    });
  }

  /// Cancels everything; nothing is fetched or told after.
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    for (final src in _sources.values) {
      for (final req in [...src.requests]) {
        _abort(req);
      }
    }
    _sources.clear();
    _loading = false;
    final done = _idlers;
    _idlers = [];
    for (final c in done) {
      c.complete();
    }
  }
}
