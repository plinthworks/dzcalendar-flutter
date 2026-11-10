import 'dart:async';

import '../event/problem.dart';
import '../event/types.dart';
import '../recurrence/series.dart';
import '../store/export.dart';
import '../time/instant.dart';
import '../store/store.dart';
import '../zone/zone_rules.dart';
import 'chunks.dart';

/// Told when a request is no longer wanted (owner's decision 57): the
/// application ties it to its client — dio's `CancelToken`, an
/// `http.Client` closed. An answer that comes after anyway is ignored.
final class CancelToken {
  CancelToken._();

  /// A token never cancelled (a fetch made outside the manager).
  static final CancelToken never = CancelToken._();

  final _done = Completer<void>();

  bool get cancelled => _done.isCompleted;

  /// Completes when the request is cancelled; never, otherwise.
  Future<void> get whenCancelled => _done.future;

  /// Calls [fn] once when cancelled (at once if it already is): where an
  /// app cancels its own client's request (dio: `dioToken.cancel()`).
  void onCancel(void Function() fn) {
    if (cancelled) {
      fn();
    } else {
      _done.future.then((_) => fn());
    }
  }
}

/// The manager's side of a [CancelToken]: the only way to cancel it.
final class CancelSource {
  final token = CancelToken._();

  void cancel() {
    if (!token._done.isCompleted) token._done.complete();
  }
}

/// What a source is asked for.
final class FetchRequest {
  const FetchRequest({required this.window, required this.cancel, required this.sourceId, required this.zone});

  /// The stretch to fetch; null for a source not cut, which answers for all
  /// of time. A chunk is whole dates: its instants run from the first date's
  /// midnight at UTC+14 to the last's at UTC−12, so the events of those dates
  /// are in it whatever zone the calendar shows — changing zone fetches
  /// nothing (unless the source says it depends on the zone).
  final ViewWindow? window;
  final CancelToken cancel;
  final String sourceId;

  /// The zone the calendar shows (what a zone-dependent source tells its server).
  final ZoneId zone;
}

/// What a fetch answers: the events, and what reading them said (an iCal
/// file's lines).
final class SourceAnswer {
  const SourceAnswer(this.events, {this.problems = const []});
  final List<EventInput> events;
  final List<Problem> problems;
}

typedef SourceFetch = FutureOr<SourceAnswer> Function(FetchRequest request);

enum EditKind { created, updated, deleted }

/// One thing a person changed in a source's events, as the store held it
/// before and holds it now (null: made, or gone).
sealed class SourceEdit {
  const SourceEdit();
  String get id;
  EditKind get kind;

  /// What to send: the item as it is now, written back as the web's input
  /// (`input.toJson()` for a request body); null when it is gone.
  EventInput? get input;
}

final class EventEdit extends SourceEdit {
  const EventEdit(this.id, {this.before, this.after});
  @override
  final String id;
  final CalEvent? before;
  final CalEvent? after;
  @override
  EditKind get kind => before == null ? EditKind.created : (after == null ? EditKind.deleted : EditKind.updated);
  @override
  EventInput? get input => after == null ? null : eventInput(after!);
}

final class SeriesEdit extends SourceEdit {
  const SeriesEdit(this.id, {this.before, this.after});
  @override
  final String id;
  final Series? before;
  final Series? after;
  @override
  EditKind get kind => before == null ? EditKind.created : (after == null ? EditKind.deleted : EditKind.updated);
  @override
  EventInput? get input => after == null ? null : seriesInput(after!);
}

enum SaveCause { command, undo, redo }

/// A person's edits to write back (owner's decision 58: a person's only —
/// a gesture, an undo, a redo; the application's own commands are not), in
/// the order they happened. One request is all or nothing: a throw puts
/// every edit back, even one the server took. Timeouts are the
/// application's client's (dio's).
///
/// With `CalendarController.onEventChange` set too (decision 60): `save`
/// writes the source's events (a refusal puts them back by itself);
/// `onEventChange` is still told, to inform (a message) — and a `revert()`
/// asked there is an undo, saved in turn.
final class SaveRequest {
  const SaveRequest({required this.sourceId, required this.edits, required this.cause});
  final String sourceId;
  final List<SourceEdit> edits;
  final SaveCause cause;
}

/// What a live source is given when it is connected.
final class LiveContext {
  const LiveContext({required this.changed, required this.now, required this.failed});

  /// Its events changed: the calendar fetches it again.
  final void Function() changed;

  /// The calendar's clock (what a message dates by itself).
  final Instant Function() now;

  /// The feed failed ([closed]: it ended — no more messages will come):
  /// told to the application (`SourceLiveFailed`), never as a crash.
  final void Function(Object error, StackTrace? stack, {bool closed}) failed;
}

/// A source that is told rather than asked: called once when it is added
/// (again if it is given anew); answers how to stop — called when the
/// source is removed or replaced, or the calendar disposed.
typedef LiveConnect = void Function() Function(LiveContext context);

/// Attempts after the first, each [backoff] × 2ⁿ later (at most
/// [maxBackoff]); [retryIf] says which errors are worth another try (not a
/// refusal: dio's 401, 403, 404).
final class RetryPolicy {
  const RetryPolicy({required this.attempts, required this.backoff, this.maxBackoff, this.retryIf})
    : assert(attempts >= 0);
  final int attempts;
  final Duration backoff;
  final Duration? maxBackoff;
  final bool Function(Object error)? retryIf;
}

/// A source of events the calendar fetches as it moves (owner's decision
/// 54). Plain data: two specs are the same source only when identical.
final class EventSourceSpec {
  const EventSourceSpec({
    required this.id,
    required this.fetch,
    this.chunk = ChunkPolicy.month,
    this.staleAfter,
    this.retry,
    this.zoneDependent = false,
    this.defaults,
    this.key,
    this.save,
    this.live,
    this.forgot,
    this.createsHere = false,
  });

  /// Where what a person makes here is saved (owner's decision 59): an
  /// event or a series made in the calendar, no source's yet, goes to this
  /// source's [save] (`before` null) — one source only, the first so marked.
  /// Saved, the source is fetched again: the server's version is adopted
  /// under the same id, or, under another id, replaces the local copy.
  final bool createsHere;

  /// Writes a person's edits back, optimistically: they show at once; a
  /// throw (or a failed future) puts them back as they were; while it is
  /// out, a refetch does not overwrite them. Without it, an edit lasts until
  /// the source is fetched again.
  final FutureOr<void> Function(SaveRequest request)? save;

  /// A source told rather than asked (`liveSource`).
  final LiveConnect? live;

  /// Its events the calendar forgot (`forgetBefore`), by id: a source that
  /// keeps its events lets these go.
  final void Function(List<String> ids)? forgot;

  final String id;

  /// What makes two specs the same source: a spec made again with an equal
  /// key (a provider rebuilt, a closure made anew) replaces the old one
  /// without fetching anything. Null: the same only when identical.
  final Object? key;
  final SourceFetch fetch;
  final ChunkPolicy chunk;

  /// Chunks older than this are fetched again when shown. Null: never.
  final Duration? staleAfter;

  /// Null: a failed fetch is not tried again (until shown again).
  final RetryPolicy? retry;

  /// The answer depends on the calendar's zone (the server is told it):
  /// fetched again when the zone changes, the events shown until the
  /// answers arrive.
  final bool zoneDependent;

  /// Laid under every event of the source ([EventInput.withDefaults]).
  final EventInput? defaults;
}

/// A fixed list, one chunk for all of time.
EventSourceSpec arraySource(String id, List<EventInput> events, {EventInput? defaults}) =>
    EventSourceSpec(id: id, fetch: (_) => SourceAnswer(events), chunk: ChunkPolicy.none, defaults: defaults);

/// Events from a function of the stretch asked, synchronous or not
/// (sehhaty's API through its own client). Default: a month a request.
EventSourceSpec fnSource(
  String id,
  FutureOr<List<EventInput>> Function(FetchRequest request) fetch, {
  ChunkPolicy chunk = ChunkPolicy.month,
  Duration? staleAfter,
  RetryPolicy? retry,
  bool zoneDependent = false,
  EventInput? defaults,
  Object? key,
  FutureOr<void> Function(SaveRequest request)? save,
  bool createsHere = false,
}) => EventSourceSpec(
  key: key,
  save: save,
  createsHere: createsHere,
  id: id,
  fetch: (r) {
    final v = fetch(r);
    return v is Future<List<EventInput>> ? v.then(SourceAnswer.new) : SourceAnswer(v);
  },
  chunk: chunk,
  staleAfter: staleAfter,
  retry: retry,
  zoneDependent: zoneDependent,
  defaults: defaults,
);
