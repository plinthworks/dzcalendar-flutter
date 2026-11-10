import 'dart:async';

import '../event/normalize.dart';
import '../event/problem.dart';
import '../event/types.dart';
import '../intervals.dart';
import '../recurrence/series.dart';
import '../rrule/rule.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'changes.dart';
import 'instance.dart';
import 'persistent.dart';

/// The stretch of time a view shows: instants for timed events, dates for
/// floating all-day ones. Made by [viewWindow] or [datesWindow] only, so the
/// two halves always describe the same days.
final class ViewWindow implements SeriesWindow {
  const ViewWindow._(this.start, this.end, this.startDate, this.endDate, this.displayZone);

  @override
  final Instant start;
  @override
  final Instant end;
  @override
  final PlainDate startDate;
  @override
  final PlainDate endDate;
  final ZoneId displayZone;
}

/// A window of whole days in a zone: the start of [startDate] to the start of [endDate].
ViewWindow viewWindow(PlainDate startDate, PlainDate endDate, ZoneId displayZone) => ViewWindow._(
  startDate.startOfDayIn(displayZone),
  endDate.startOfDayIn(displayZone),
  startDate,
  endDate,
  displayZone,
);

/// Whole dates as they exist anywhere on earth: from the first date's
/// midnight at UTC+14 to the end date's at UTC−12. What a source's chunk is
/// fetched over, so the calendar can change zone without fetching again.
ViewWindow datesWindow(PlainDate startDate, PlainDate endDate, ZoneId displayZone) =>
    ViewWindow._(startDate.startOfDayIn('+14:00'), endDate.startOfDayIn('-12:00'), startDate, endDate, displayZone);

/// The source something belongs to: its own, or — for what an edit made
/// here on a source's series (an override, a part cut off by "this and
/// following") — that series' source, up the chain of splits.
String? sourceOf(Object x, Series? Function(SeriesId) getSeries) {
  final own = switch (x) {
    CalEvent e => e.sourceId,
    Series s => s.sourceId,
    _ => null,
  };
  if (own != null) return own;
  var sr = switch (x) {
    Series s => s.splitFrom == null ? null : getSeries(s.splitFrom!.seriesId),
    CalEvent e => e.ref == null ? null : getSeries(e.ref!.seriesId),
    _ => null,
  };
  for (var i = 0; sr != null && i < 64; i++) {
    if (sr.sourceId != null) return sr.sourceId;
    final from = sr.splitFrom;
    sr = from == null ? null : getSeries(from.seriesId);
  }
  return null;
}

/// Where an event sits in its index. A milestone still covers one
/// millisecond, so a window finds it. Epoch days for an all-day event.
MsSpan spanOf(CalEvent e) => switch (e) {
  AllDayEvent(:final start, :final end) => MsSpan(start.epochDay, end.epochDay),
  TimedEvent(:final start, :final end) => MsSpan(
    start.epochMilliseconds,
    end.epochMilliseconds > start.epochMilliseconds ? end.epochMilliseconds : start.epochMilliseconds + 1,
  ),
};

bool _sameRulesAndAdditions(Series a, Series b) =>
    setEquals(RRuleSet(a.set.rules, rdates: a.set.rdates), RRuleSet(b.set.rules, rdates: b.set.rdates));

/// The keys and EXDATEs present in one series and not the other.
List<Object> _changedPlaces(Series a, Series b) {
  final out = <Object>[];
  for (final MapEntry(:key, :value) in a.overrides.entries) {
    if (b.overrides[key] != value) out.add(key);
  }
  for (final MapEntry(:key, :value) in b.overrides.entries) {
    if (a.overrides[key] != value) out.add(key);
  }
  final ea = {for (final x in a.set.exdates) '$x': x};
  final eb = {for (final x in b.set.exdates) '$x': x};
  for (final MapEntry(:key, :value) in ea.entries) {
    if (!eb.containsKey(key)) out.add(value);
  }
  for (final MapEntry(:key, :value) in eb.entries) {
    if (!ea.containsKey(key)) out.add(value);
  }
  return out;
}

final class _Indexes {
  const _Indexes(this.timed, this.days);
  static const empty = _Indexes(PersistentIntervalTree.empty, PersistentIntervalTree.empty);
  final PersistentIntervalTree timed;
  final PersistentIntervalTree days;

  _Indexes add(String id, bool allDay, MsSpan sp) =>
      allDay ? _Indexes(timed, days.insert(sp.s, sp.e, id)) : _Indexes(timed.insert(sp.s, sp.e, id), days);
  _Indexes remove(String id, bool allDay, MsSpan sp) =>
      allDay ? _Indexes(timed, days.remove(sp.s, id)) : _Indexes(timed.remove(sp.s, id), days);
}

/// A view's query: one resource's events only, without background events.
final class QueryOptions {
  const QueryOptions({this.resourceId, this.includeBackground = true, this.onProblem, this.where});
  final ResourceId? resourceId;
  final bool includeBackground;

  /// Only the events it keeps: a series is asked once, with its base event
  /// (its occurrences go or stay together); a changed occurrence is asked
  /// with its own event.
  final bool Function(CalEvent event)? where;

  /// Receives what expansion had to say (`too-many-occurrences`): the occurrences shown were cut.
  final void Function(Problem)? onProblem;
}

/// One immutable state of the store. Every index is persistent, so the next
/// snapshot copies O(log n) nodes per touched item and leaves this one
/// exactly as it was — anything holding it keeps a consistent picture.
final class StoreSnapshot {
  const StoreSnapshot._({
    required this.version,
    required PersistentOrderedMap<EventId, CalEvent> events,
    required _Indexes all,
    required PersistentOrderedMap<ResourceId, _Indexes> byResource,
    required PersistentOrderedMap<SeriesId, Series> series,
    required _Indexes seriesIdx,
    required PersistentOrderedMap<String, List<String>> owners,
    required PersistentOrderedMap<String, List<String>> chunks,
  }) : _events = events,
       _all = all,
       _byResource = byResource,
       _series = series,
       _seriesIdx = seriesIdx,
       _owners = owners,
       _chunks = chunks;

  static final empty = StoreSnapshot._(
    version: 0,
    events: PersistentOrderedMap.strings(),
    all: _Indexes.empty,
    byResource: PersistentOrderedMap.strings(),
    series: PersistentOrderedMap.strings(),
    seriesIdx: _Indexes.empty,
    owners: PersistentOrderedMap.strings(),
    chunks: PersistentOrderedMap.strings(),
  );

  final int version;
  final PersistentOrderedMap<EventId, CalEvent> _events;
  final _Indexes _all;
  final PersistentOrderedMap<ResourceId, _Indexes> _byResource;
  final PersistentOrderedMap<SeriesId, Series> _series;

  /// Series by the span of their occurrences (timed in ms, all-day in days).
  final _Indexes _seriesIdx;

  /// Which source chunks hold each source item (`event:id` / `series:id`).
  final PersistentOrderedMap<String, List<String>> _owners;

  /// The item keys each source chunk delivered last time.
  final PersistentOrderedMap<String, List<String>> _chunks;

  StoreSnapshot _with({
    int? version,
    PersistentOrderedMap<EventId, CalEvent>? events,
    _Indexes? all,
    PersistentOrderedMap<ResourceId, _Indexes>? byResource,
    PersistentOrderedMap<SeriesId, Series>? series,
    _Indexes? seriesIdx,
    PersistentOrderedMap<String, List<String>>? owners,
    PersistentOrderedMap<String, List<String>>? chunks,
  }) => StoreSnapshot._(
    version: version ?? this.version,
    events: events ?? _events,
    all: all ?? _all,
    byResource: byResource ?? _byResource,
    series: series ?? _series,
    seriesIdx: seriesIdx ?? _seriesIdx,
    owners: owners ?? _owners,
    chunks: chunks ?? _chunks,
  );

  ({int events, int series}) get counts => (events: _events.length, series: _series.length);

  CalEvent? getEvent(EventId id) => _events[id];
  Series? getSeries(SeriesId id) => _series[id];
  Iterable<CalEvent> get allEvents => _events.values;
  Iterable<Series> get allSeries => _series.values;

  /// True while some chunk of its source still delivers the event (or series).
  /// What a source's chunk holds, as tags (`event:a`, `series:w`).
  List<String> chunkTags(String sourceId, String chunk) => _chunks['$sourceId\u0000$chunk'] ?? const [];

  bool isSourceOwned(String id, {bool series = false}) => _owners.containsKey('${series ? 'series' : 'event'}:$id');

  /// The events a window shows: single events from the indexes, occurrences
  /// of the series whose span meets the window (expanded only there). A
  /// stable sort: start, longer first, title, key.
  List<EventInstance> queryInstances(ViewWindow w, [QueryOptions opts = const QueryOptions()]) {
    final resource = opts.resourceId;
    final ix = resource == null ? _all : _byResource[resource];
    final where = opts.where;
    bool keep(CalEvent e) =>
        e.display != EventDisplay.none &&
        !(!opts.includeBackground &&
            (e.display == EventDisplay.background || e.display == EventDisplay.inverseBackground)) &&
        (where == null || where(e));
    final found = <EventInstance>[];
    if (ix != null) {
      void take(String id, int _, int _) {
        final e = _events[id]!;
        if (keep(e)) {
          found.add(EventInstance(escapeId(e.id), e, e.ref != null ? InstanceOrigin.override : InstanceOrigin.single));
        }
      }

      ix.days.overlapping(w.startDate.epochDay, w.endDate.epochDay, take);
      ix.timed.overlapping(w.start.epochMilliseconds, w.end.epochMilliseconds, take);
    }
    void series(String id, int _, int _) {
      final sr = _series[id]!;
      if (resource != null && !sr.base.resourceIds.contains(resource)) return;
      if (!keep(sr.base)) return;
      final (:occurrences, :problems) = expandSeries(sr, w);
      final report = opts.onProblem;
      if (report != null) problems.forEach(report);
      for (final ev in occurrences) {
        final key = ev.ref!.key;
        if (sr.overrides.containsKey(key)) continue;
        found.add(EventInstance(occurrenceKey(sr.id, key), ev, InstanceOrigin.occurrence));
      }
    }

    _seriesIdx.days.overlapping(w.startDate.epochDay, w.endDate.epochDay, series);
    _seriesIdx.timed.overlapping(w.start.epochMilliseconds, w.end.epochMilliseconds, series);

    int startOf(CalEvent e) => switch (e) {
      AllDayEvent(:final start) => start.startOfDayIn(w.displayZone).epochMilliseconds,
      TimedEvent(:final start) => start.epochMilliseconds,
    };
    int endOf(CalEvent e) => switch (e) {
      AllDayEvent(:final end) => end.startOfDayIn(w.displayZone).epochMilliseconds,
      TimedEvent(:final end) => end.epochMilliseconds,
    };
    final keyed = [for (final i in found) (i, startOf(i.event), endOf(i.event) - startOf(i.event))];
    keyed.sort((a, b) {
      var c = a.$2.compareTo(b.$2);
      if (c != 0) return c;
      c = b.$3.compareTo(a.$3);
      if (c != 0) return c;
      c = a.$1.event.title.compareTo(b.$1.event.title);
      return c != 0 ? c : a.$1.key.compareTo(b.$1.key);
    });
    return [for (final k in keyed) k.$1];
  }

  /// The next snapshot after [mutations]. Pure. [stampAt]: give each `after`
  /// this revision (an equal one keeps the stored object instead); omitted,
  /// objects are restored exactly (undo, redo, previews).
  ({StoreSnapshot next, Map<EventId, CalEvent?> touched, Set<SeriesId> seriesTouched, List<Mutation> applied})
  withMutations(List<Mutation> mutations, {int? stampAt}) {
    var events = _events;
    var all = _all;
    var byResource = _byResource;
    var series = _series;
    var seriesIdx = _seriesIdx;
    final touched = <EventId, CalEvent?>{};
    final seriesTouched = <SeriesId>{};
    final applied = <Mutation>[];

    void drop(CalEvent e) {
      final sp = spanOf(e);
      all = all.remove(e.id, e.allDay, sp);
      for (final r in e.resourceIds) {
        final ix = byResource[r];
        if (ix != null) byResource = byResource.set(r, ix.remove(e.id, e.allDay, sp));
      }
    }

    void add(CalEvent e) {
      final sp = spanOf(e);
      all = all.add(e.id, e.allDay, sp);
      for (final r in e.resourceIds) {
        byResource = byResource.set(r, (byResource[r] ?? _Indexes.empty).add(e.id, e.allDay, sp));
      }
    }

    for (final m in mutations) {
      final id = m.id;
      switch (m) {
        case SeriesMutation(after: final next):
          final current = series[id];
          final after = next != null && stampAt != null ? _stampSeries(current, next, stampAt) : next;
          if (identical(current, after)) continue;
          applied.add(SeriesMutation(before: current, after: after));
          seriesTouched.add(id);
          if (current != null) seriesIdx = seriesIdx.remove(id, current.allDay, seriesSpan(current));
          if (after != null) {
            seriesIdx = seriesIdx.add(id, after.allDay, seriesSpan(after));
            series = series.set(id, after);
          } else {
            series = series.remove(id);
          }
        case EventMutation(after: final next):
          final current = events[id];
          if (!touched.containsKey(id)) touched[id] = current;
          final after = next != null && stampAt != null ? stamp(current, next, stampAt) : next;
          if (identical(current, after)) continue;
          applied.add(EventMutation(before: current, after: after));
          if (current != null) drop(current);
          if (after != null) {
            add(after);
            events = events.set(id, after);
          } else {
            events = events.remove(id);
          }
      }
    }
    final next = _with(
      version: version + 1,
      events: events,
      all: all,
      byResource: byResource,
      series: series,
      seriesIdx: seriesIdx,
    );
    return (next: next, touched: touched, seriesTouched: seriesTouched, applied: applied);
  }
}

/// The store's rule for `revision`: an event equal to the one it replaces
/// keeps the old object (nothing redraws); a different one takes [revision]
/// — the version of the snapshot being written, strictly increasing, so one
/// (id, revision) never names two contents.
CalEvent stamp(CalEvent? prev, CalEvent next, int revision) {
  if (prev != null && eventEquals(prev, next)) return prev;
  return next.revision == revision ? next : next.withRevision(revision);
}

/// A series equal to the stored one keeps that object; a different one
/// takes the revision. What did not change keeps its object: an override
/// leaves the base alone, so the occurrences built from it stay as drawn.
Series _stampSeries(Series? prev, Series next, int revision) {
  if (prev != null && seriesEquals(prev, next)) return prev;
  if (next.revision == revision) return next;
  final base = prev != null && eventEquals(prev.base, next.base) ? prev.base : next.base.withRevision(revision);
  final set = prev != null && setEquals(prev.set, next.set) ? prev.set : next.set;
  return next.copyWith(revision: revision, base: base, set: set);
}

StoreChange _describe(
  StoreSnapshot prev,
  StoreSnapshot next,
  Map<EventId, CalEvent?> touched,
  Set<SeriesId> seriesTouched,
  List<Mutation> applied,
  ChangeCause cause,
  List<Problem> problems,
) {
  final added = <EventId>[];
  final updated = <EventId>[];
  final removed = <EventId>[];
  final spans = <MsSpan>[];
  final days = <MsSpan>[];
  void mark(CalEvent e) => (e.allDay ? days : spans).add(spanOf(e));
  for (final MapEntry(key: id, value: before) in touched.entries) {
    final after = next.getEvent(id);
    if (identical(before, after)) continue;
    if (before == null) {
      added.add(id);
    } else if (after == null) {
      removed.add(id);
    } else {
      updated.add(id);
    }
    if (before != null) mark(before);
    if (after != null) mark(after);
  }
  final touchedSeries = <SeriesId>[];
  final seriesChanged = <SeriesId>[];
  for (final id in seriesTouched) {
    final before = prev.getSeries(id);
    final after = next.getSeries(id);
    if (identical(before, after)) continue;
    seriesChanged.add(id);
    // Only overrides or EXDATEs changed: the occurrences they name changed,
    // at known places. Anything else may move occurrences anywhere.
    if (before != null &&
        after != null &&
        identical(before.base, after.base) &&
        _sameRulesAndAdditions(before, after)) {
      for (final at in _changedPlaces(before, after)) {
        (after.allDay ? days : spans).add(occurrenceSpan(after, at));
      }
      continue;
    }
    touchedSeries.add(id);
  }
  final changed = added.length + updated.length + removed.length + seriesChanged.length > 0;
  // Handed to every listener: none may change what the others read. `applied`
  // keeps its identity (the history's `revert` is keyed on it).
  return StoreChange(
    version: changed ? next.version : prev.version,
    added: List.unmodifiable(added),
    updated: List.unmodifiable(updated),
    removed: List.unmodifiable(removed),
    seriesTouched: List.unmodifiable(touchedSeries),
    seriesChanged: List.unmodifiable(seriesChanged),
    dirtySpans: List.unmodifiable(normalizeSpans(spans)),
    dirtyDays: List.unmodifiable(normalizeSpans(days)),
    cause: cause,
    problems: List.unmodifiable(problems),
    applied: changed ? List.unmodifiable(applied) : const [],
  );
}

/// The events and series a calendar holds, as a sequence of immutable
/// snapshots; one transaction, one notification.
final class EventStore {
  EventStore([StoreSnapshot? initial]) : _snapshot = initial ?? StoreSnapshot.empty;

  StoreSnapshot _snapshot;
  final _listeners = <void Function(StoreChange)>[];

  StoreSnapshot get snapshot => _snapshot;

  StoreChange _commit(StoreSnapshot next, StoreChange change) {
    _snapshot = next;
    if (!change.isEmpty) {
      // One listener that throws must not keep the change from the others.
      for (final fn in [..._listeners]) {
        try {
          fn(change);
        } on Object catch (e, s) {
          // Reported to the zone, after the round: visible, never swallowed.
          Zone.current.handleUncaughtError(e, s);
        }
      }
    }
    return change;
  }

  /// One transaction. The store stamps revisions itself (except for undo
  /// and redo, which restore objects as they were); the change's `applied`
  /// lists what it really did. A batch that changes nothing notifies no one
  /// and keeps the version.
  StoreChange apply(List<Mutation> mutations, ChangeCause cause) {
    final restoring = cause == ChangeCause.undo || cause == ChangeCause.redo;
    final r = _snapshot.withMutations(mutations, stampAt: restoring ? null : _snapshot.version + 1);
    final change = _describe(_snapshot, r.next, r.touched, r.seriesTouched, r.applied, cause, const []);
    return change.isEmpty ? change : _commit(r.next, change);
  }

  /// Replaces what one chunk of one source delivered — events and series.
  StoreChange replaceSourceChunk(String sourceId, String chunk, List<Normalized> items) =>
      replaceSourceChunks(sourceId, [(chunk, items)]);

  /// Several chunks of one source in one transaction: one delivery, one
  /// change. An item delivered by two chunks belongs to both and goes only
  /// when both drop it. An item equal to the stored one keeps its object and
  /// revision. The source is the authority: an item edited or deleted here
  /// comes back as the source says on the next delivery.
  StoreChange replaceSourceChunks(String sourceId, List<(String, List<Normalized>)> entries) {
    final snap = _snapshot;
    var owners = snap._owners;
    var chunks = snap._chunks;
    final problems = <Problem>[];
    final mutations = <Mutation>[];
    // Said once even when two chunks of one delivery both carry it.
    final emitted = <String>{};
    final deliveredBy = <String, Set<String>>{};

    for (final (chunk, items) in entries) {
      final chunkKey = '$sourceId\u0000$chunk';
      final delivered = <String>{};
      deliveredBy[chunkKey] = delivered;
      for (final item in items) {
        final isEvent = item is NormalizedEvent;
        final id = switch (item) {
          NormalizedEvent(:final event) => event.id,
          NormalizedSeries(:final series) => series.id,
        };
        final tag = '${isEvent ? 'event' : 'series'}:$id';
        final Object? current = isEvent ? snap.getEvent(id) : snap.getSeries(id);
        // An id is one thing: an event and a series may not share it, whoever brought them.
        final Object? other = isEvent ? snap.getSeries(id) : snap.getEvent(id);
        final otherSource = switch (other) {
          CalEvent e => e.sourceId,
          Series s => s.sourceId,
          _ => null,
        };
        final currentSource = switch (current) {
          CalEvent e => e.sourceId,
          Series s => s.sourceId,
          _ => null,
        };
        // This source's own item made the other kind here: the source is its authority.
        final turned =
            other != null && otherSource == sourceId && !owners.containsKey('${isEvent ? 'series' : 'event'}:$id');
        // A local object made on this source's series (an override saved to the
        // server, delivered back under the same id) is adopted.
        final adopt = current != null && currentSource == null && sourceOf(current, snap.getSeries) == sourceId;
        if ((current != null && currentSource != sourceId && !adopt) || (other != null && !turned)) {
          // Someone else holds this id now: refuse, and stop counting this chunk among its owners.
          problems.add(Problem(ProblemCode.duplicateId, Severity.error, '$sourceId/$chunk', id).withSource(sourceId));
          final rest = (owners[tag] ?? const []).where((k) => k != chunkKey).toList();
          owners = rest.isNotEmpty ? owners.set(tag, rest) : owners.remove(tag);
          continue;
        }
        if (!delivered.add(tag)) continue;
        final own = owners[tag];
        if (own == null) {
          owners = owners.set(tag, [chunkKey]);
        } else if (!own.contains(chunkKey)) {
          owners = owners.set(tag, [...own, chunkKey]);
        }
        if (!emitted.add(tag)) continue;
        if (turned) {
          mutations.add(isEvent ? SeriesMutation(before: other as Series) : EventMutation(before: other as CalEvent));
        }
        switch (item) {
          case NormalizedEvent(:final event):
            final tagged = event.sourceId == sourceId ? event : event.withIdentity(event.id, sourceId);
            mutations.add(EventMutation(before: current as CalEvent?, after: tagged));
          case NormalizedSeries(:final series):
            final tagged = series.sourceId == sourceId ? series : series.copyWith(sourceId: sourceId);
            mutations.add(SeriesMutation(before: current as Series?, after: tagged));
        }
      }
    }

    // Withdrawn only after every chunk has said what it carries: an event that
    // moved from one chunk to its neighbour in this delivery stays.
    for (final MapEntry(key: chunkKey, value: delivered) in deliveredBy.entries) {
      for (final tag in snap._chunks[chunkKey] ?? const <String>[]) {
        if (delivered.contains(tag)) continue;
        final rest = (owners[tag] ?? const []).where((k) => k != chunkKey).toList();
        if (rest.isNotEmpty) {
          owners = owners.set(tag, rest);
          continue;
        }
        owners = owners.remove(tag);
        final colon = tag.indexOf(':');
        final kind = tag.substring(0, colon);
        final id = tag.substring(colon + 1);
        // Only what this source still owns; made the other kind here, still the source's.
        final ev = snap.getEvent(id);
        final sr = snap.getSeries(id);
        if (ev != null && ev.sourceId == sourceId && (kind == 'event' || !owners.containsKey('event:$id'))) {
          mutations.add(EventMutation(before: ev));
        }
        if (sr != null && sr.sourceId == sourceId && (kind == 'series' || !owners.containsKey('series:$id'))) {
          mutations.add(SeriesMutation(before: sr));
        }
      }
      chunks = delivered.isNotEmpty ? chunks.set(chunkKey, delivered.toList()) : chunks.remove(chunkKey);
    }

    // The source is the authority on its series too: what was edited here
    // around one (overrides, a part cut off) goes when the source says the
    // series again, or stops saying it.
    final localGone = <String>{};
    for (final m in [...mutations]) {
      if (m is! SeriesMutation) continue;
      final was = m.before;
      if (was == null) continue;
      final after = m.after;
      if (after != null && seriesEquals(was, after)) continue;
      final kept = {...?after?.overrides.values};
      for (final id in was.overrides.values) {
        final ev = snap.getEvent(id);
        // Local: made here, or made here on the source's series and never delivered by it.
        final local =
            ev != null && (ev.sourceId == null || (ev.sourceId == sourceId && !owners.containsKey('event:$id')));
        if (ev != null && local && !kept.contains(id) && localGone.add('event:$id')) {
          mutations.add(EventMutation(before: ev));
        }
      }
      // Every local part cut from it, and the parts cut from those, to the end of the chain.
      final cutFrom = [was.id];
      while (cutFrom.isNotEmpty) {
        final parent = cutFrom.removeLast();
        for (final other in snap.allSeries) {
          if (other.splitFrom?.seriesId != parent || other.sourceId != null) continue;
          if (!localGone.add('series:${other.id}')) continue;
          cutFrom.add(other.id);
          for (final id in other.overrides.values) {
            final ev = snap.getEvent(id);
            if (ev != null && localGone.add('event:$id')) mutations.add(EventMutation(before: ev));
          }
          mutations.add(SeriesMutation(before: other));
        }
      }
    }

    final base = snap._with(owners: owners, chunks: chunks);
    final r = base.withMutations(mutations, stampAt: base.version + 1);
    final change = _describe(base, r.next, r.touched, r.seriesTouched, r.applied, ChangeCause.source, problems);
    return _commit(change.isEmpty ? base : r.next, change);
  }

  /// [fn] hears every change that changed something; the returned function stops it.
  void Function() subscribe(void Function(StoreChange) fn) {
    _listeners.add(fn);
    return () => _listeners.remove(fn);
  }
}
