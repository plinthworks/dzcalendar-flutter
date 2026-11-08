import '../event/problem.dart';
import '../event/types.dart';
import '../intervals.dart';
import '../recurrence/series.dart';

/// One step of a transaction: an event or a series appears (`after` only),
/// disappears (`before` only) or is replaced. Undo is built from these, not
/// from commands: replaying the inverse restores exactly what was there.
sealed class Mutation {
  const Mutation();
  String get id;

  /// Events and series have separate id spaces: what a mutation touches, uniquely.
  String get key;

  Mutation get inverted;
  Object? get before;
  Object? get after;
}

final class EventMutation extends Mutation {
  const EventMutation({this.before, this.after}) : assert(before != null || after != null);
  @override
  final CalEvent? before;
  @override
  final CalEvent? after;
  @override
  String get id => (after ?? before)!.id;
  @override
  String get key => 'event:$id';
  @override
  EventMutation get inverted => EventMutation(before: after, after: before);
}

final class SeriesMutation extends Mutation {
  const SeriesMutation({this.before, this.after}) : assert(before != null || after != null);
  @override
  final Series? before;
  @override
  final Series? after;
  @override
  String get id => (after ?? before)!.id;
  @override
  String get key => 'series:$id';
  @override
  SeriesMutation get inverted => SeriesMutation(before: after, after: before);
}

enum ChangeCause { command, source, undo, redo, api }

/// What one transaction did, net: an event changed twice is `updated` once.
/// [dirtySpans] (epoch ms) and [dirtyDays] (epoch days, for floating all-day
/// events) cover each touched event's old and new place.
final class StoreChange {
  const StoreChange({
    required this.version,
    required this.added,
    required this.updated,
    required this.removed,
    required this.dirtySpans,
    required this.dirtyDays,
    required this.cause,
    required this.seriesTouched,
    required this.seriesChanged,
    required this.problems,
    required this.applied,
  });

  final int version;
  final List<EventId> added;
  final List<EventId> updated;
  final List<EventId> removed;
  final List<MsSpan> dirtySpans;
  final List<MsSpan> dirtyDays;
  final ChangeCause cause;

  /// Series added, changed or removed whose occurrences may lie anywhere: a
  /// view showing any of them rebuilds rather than reading spans.
  final List<SeriesId> seriesTouched;

  /// Every series whose object changed — [seriesTouched], and those where
  /// only overrides or EXDATEs changed (their places are in the dirty spans).
  final List<SeriesId> seriesChanged;

  /// Items a source handed in that the store refused (an id owned elsewhere).
  final List<Problem> problems;

  /// The mutations as carried out: `before` what was really there, `after`
  /// the stamped object now stored — what an undo records, compared later
  /// by identity.
  final List<Mutation> applied;

  bool get isEmpty => added.isEmpty && updated.isEmpty && removed.isEmpty && seriesChanged.isEmpty;
}
