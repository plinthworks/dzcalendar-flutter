import '../event/types.dart';
import '../recurrence/series.dart';
import '../store/changes.dart';
import '../store/store.dart';
import 'apply.dart';
import 'types.dart';

/// What [History.run] did: the command's result and, when it changed
/// something, the store's change.
final class RunResult {
  const RunResult(this.result, [this.change]);
  final CommandResult result;
  final StoreChange? change;
  bool get ok => result.ok;
}

final class _Entry {
  _Entry(this.label, this.mutations, this.mergeKey);
  final String label;
  List<Mutation> mutations;
  final String? mergeKey;
  int commands = 0;
}

enum _Kind { command, undo, redo }

/// One mutation per id: the first `before`, the last `after`. A forty-step
/// drag is stored as one move; created-then-deleted is nothing at all.
List<Mutation> _compact(List<Mutation> mutations) {
  final first = <String, Mutation>{};
  final last = <String, Mutation>{};
  for (final m in mutations) {
    first.putIfAbsent(m.key, () => m);
    last[m.key] = m;
  }
  final out = <Mutation>[];
  for (final MapEntry(:key, value: f) in first.entries) {
    final before = f.before;
    final after = last[key]!.after;
    if (identical(before, after)) continue;
    out.add(switch (f) {
      EventMutation() => EventMutation(before: before as CalEvent?, after: after as CalEvent?),
      SeriesMutation() => SeriesMutation(before: f.before, after: (last[key]! as SeriesMutation).after),
    });
  }
  return out;
}

/// What each event or series (`kind:id`) looks like after these mutations.
Map<String, Mutation> _finalStates(List<Mutation> mutations) => {for (final m in mutations) m.key: m};

/// True when [next] starts from exactly what [prev] left, for every item they
/// share — nothing slipped in between. Only then may the two be undone as one.
bool _continues(List<Mutation> prev, List<Mutation> next) {
  final left = _finalStates(prev);
  return next.every((m) => !left.containsKey(m.key) || identical(left[m.key]!.after, m.before));
}

/// A running event whose end alone moved (to now): the same event, grown.
bool _onlyGrew(CalEvent a, CalEvent b) =>
    a is TimedEvent && b is TimedEvent && a.ongoing && b.ongoing && eventEquals(a.copyWith(end: b.end), b);

/// Undo and redo over a store, built from the mutations each command really
/// applied. Entries something else touched since (a source refresh, another
/// writer) are dropped: replaying them would overwrite that change.
final class History {
  /// One [context] for every command — its id generator included, so two
  /// commands never make the same id. [mergeKey]: commands with the same
  /// non-null key, run one after another, become one entry (a drag moved
  /// forty times is undone once); the key must name the gesture, not only
  /// the event. [limit]: entries kept, the oldest going first.
  History(
    EventStore store,
    CommandContext context, {
    int limit = 200,
    String? Function(Command)? mergeKey,
    void Function(List<String>)? onDropped,
  }) : this.reading(store, () => context, limit: limit, mergeKey: mergeKey, onDropped: onDropped);

  /// The context read at each command, so a calendar whose zone or locale
  /// changes keeps one history. [context] must hand back the same id
  /// generator each time (a new one per call makes the same ids twice).
  History.reading(this._store, this._context, {int limit = 200, this.mergeKey, this.onDropped}) : _limit = limit {
    _unsubscribe = _store.subscribe(_heard);
  }

  final EventStore _store;
  final CommandContext Function() _context;
  final int _limit;
  final String? Function(Command)? mergeKey;

  /// Labels of the entries thrown away because something else changed what they touch.
  final void Function(List<String> labels)? onDropped;

  var _done = <_Entry>[];
  var _undone = <_Entry>[];
  _Entry? _open;
  var _writing = false;
  late final void Function() _unsubscribe;

  /// A running event grown since: what it is now.
  final _grewTo = Expando<CalEvent>('grewTo');

  /// The entry each write's applied mutations went into, and what the write was.
  final _origin = Expando<_Entry>('origin');
  final _kindOf = Expando<_Kind>('kind');
  _Kind? _pending;
  List<Mutation>? _deferred;

  bool get canUndo => _done.isNotEmpty;
  bool get canRedo => _undone.isNotEmpty;

  final _listeners = <void Function()>[];
  var _said = (false, false);

  /// [listener] is called when [canUndo] or [canRedo] changes (a toolbar's
  /// Undo and Redo buttons). Owner's decision 13 (2026-11-08).
  void addListener(void Function() listener) => _listeners.add(listener);
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    final now = (canUndo, canRedo);
    if (now == _said) return;
    _said = now;
    for (final fn in [..._listeners]) {
      fn();
    }
  }

  Object? _stored(Mutation m) => m is EventMutation ? _store.snapshot.getEvent(m.id) : _store.snapshot.getSeries(m.id);

  /// True when the store still shows exactly what these mutations left. By identity.
  bool _stillApplies(List<Mutation> mutations) {
    for (final m in _finalStates(mutations).values) {
      if (!identical(_stored(m), m.after)) return false;
    }
    return true;
  }

  /// A source item may come back only while its source still delivers it:
  /// restored after the source withdrew it, nothing would ever remove it.
  bool _restoresOrphan(List<Mutation> steps) {
    bool owned(String id) => _store.snapshot.isSourceOwned(id) || _store.snapshot.isSourceOwned(id, series: true);
    return _finalStates(steps).values.any((m) {
      final after = m.after;
      final source = switch (after) {
        CalEvent e => e.sourceId,
        Series s => s.sourceId,
        _ => null,
      };
      return source != null && !owned(m.id);
    });
  }

  StoreChange _write(List<Mutation> mutations, ChangeCause cause) {
    _writing = true;
    try {
      return _store.apply(mutations, cause);
    } finally {
      _writing = false;
    }
  }

  void _heard(StoreChange change) {
    if (_writing) return;
    final grown = <CalEvent, CalEvent>{};
    for (final m in change.applied) {
      if (m case EventMutation(:final before?, :final after?) when _onlyGrew(before, after)) {
        grown[before] = after;
        _grewTo[before] = after;
      }
    }
    if (grown.isNotEmpty) {
      Mutation follow(Mutation m) => switch (m) {
        EventMutation(:final before, :final after) => EventMutation(
          before: before != null && grown.containsKey(before) ? grown[before] : before,
          after: after != null && grown.containsKey(after) ? grown[after] : after,
        ),
        SeriesMutation() => m,
      };
      for (final e in [..._done, ..._undone]) {
        e.mutations = e.mutations.map(follow).toList();
      }
    }
    final kept = {for (final e in grown.values) e.id};
    final ids = {
      for (final id in [...change.added, ...change.updated.where((id) => !kept.contains(id)), ...change.removed])
        'event:$id',
      for (final id in change.seriesChanged) 'series:$id',
    };
    bool touches(_Entry e) => e.mutations.any((m) => ids.contains(m.key));
    final dropped = [
      for (final e in [..._done, ..._undone])
        if (touches(e)) e.label,
    ];
    if (dropped.isEmpty) return;
    _done = _done.where((e) => !touches(e)).toList();
    _undone = _undone.where((e) => !touches(e)).toList();
    onDropped?.call(dropped);
    _notify();
  }

  CalEvent? _latest(CalEvent? e) {
    var x = e;
    while (x != null && _grewTo[x] != null) {
      x = _grewTo[x];
    }
    return x;
  }

  List<Mutation> _nowOf(List<Mutation> applied) => [
    for (final m in applied)
      switch (m) {
        EventMutation(:final before, :final after) => EventMutation(before: _latest(before), after: _latest(after)),
        SeriesMutation() => m,
      },
  ];

  void _push(_Entry entry) {
    _undone = [];
    _done.add(entry);
    if (_done.length > _limit) _done.removeAt(0);
  }

  void _record(String label, List<Mutation> applied, String? key) {
    final open = _open;
    if (open != null) {
      open.mutations.addAll(applied);
      _origin[applied] = open;
      open.commands += 2;
      return;
    }
    final last = _done.isEmpty ? null : _done.last;
    if (key != null && _undone.isEmpty && last != null && last.mergeKey == key && _continues(last.mutations, applied)) {
      last.mutations = _compact([...last.mutations, ...applied]);
      _origin[applied] = last;
      last.commands++;
      return;
    }
    final entry = _Entry(label, _compact(applied), key)..commands = 1;
    _origin[applied] = entry;
    _push(entry);
  }

  /// Applies a command and records how to take it back.
  RunResult run(Command cmd) {
    final result = applyCommand(_store.snapshot, cmd, _context());
    if (!result.ok || result.mutations.isEmpty) return RunResult(result);
    _pending = _Kind.command;
    final change = _write(result.mutations, ChangeCause.command);
    _pending = null;
    if (change.applied.isNotEmpty) {
      _record(cmd.label, change.applied, mergeKey?.call(cmd));
      _kindOf[change.applied] = _Kind.command;
      _settleDeferred(change.applied);
    }
    _notify();
    return RunResult(result, change);
  }

  bool _replay(List<_Entry> from, List<_Entry> to, bool backwards) {
    if (from.isEmpty) return false;
    final entry = from.last;
    final steps = backwards ? [for (final m in entry.mutations.reversed) m.inverted] : entry.mutations;
    final expected = backwards ? entry.mutations : [for (final m in entry.mutations.reversed) m.inverted];
    from.removeLast();
    if (!_stillApplies(expected) || _restoresOrphan(steps)) {
      onDropped?.call([entry.label]);
      return false;
    }
    _pending = backwards ? _Kind.undo : _Kind.redo;
    final change = _write(steps, backwards ? ChangeCause.undo : ChangeCause.redo);
    _pending = null;
    to.add(entry);
    _kindOf[change.applied] = backwards ? _Kind.undo : _Kind.redo;
    _origin[change.applied] = entry;
    _settleDeferred(change.applied);
    return true;
  }

  bool undo() {
    final r = _replay(_done, _undone, true);
    _notify();
    return r;
  }

  bool redo() {
    final r = _replay(_undone, _done, false);
    _notify();
    return r;
  }

  bool _mayTakeBack(List<Mutation> applied, _Kind kind, _Entry? entry) {
    if (entry == null || !_stillApplies(_nowOf(applied))) return false;
    if (_restoresOrphan([for (final m in _nowOf(applied).reversed) m.inverted])) return false;
    return switch (kind) {
      _Kind.command => !(entry.commands > 1 || identical(entry, _open)),
      _Kind.undo => _undone.contains(entry),
      _Kind.redo => _done.contains(entry),
    };
  }

  bool _takeBack(List<Mutation> applied, _Kind kind, _Entry? entry) {
    if (entry == null || !_mayTakeBack(applied, kind, entry)) return false;
    final steps = [for (final m in _nowOf(applied).reversed) m.inverted];
    switch (kind) {
      case _Kind.command:
        _done = _done.where((e) => !identical(e, entry)).toList();
        _undone = _undone.where((e) => !identical(e, entry)).toList();
      case _Kind.undo:
        _undone = _undone.where((e) => !identical(e, entry)).toList();
        _done.add(entry);
      case _Kind.redo:
        _done = _done.where((e) => !identical(e, entry)).toList();
        _undone.add(entry);
    }
    _write(steps, kind == _Kind.undo ? ChangeCause.redo : ChangeCause.undo);
    _notify();
    return true;
  }

  /// A revert asked while its own change was being announced: done once the write is over.
  void _settleDeferred(List<Mutation> applied) {
    if (!identical(_deferred, applied)) return;
    _deferred = null;
    _takeBack(applied, _kindOf[applied]!, _origin[applied]);
  }

  /// Takes back exactly what one command applied (`change.applied`), not the
  /// last entry: a server's late refusal of the first of two drags. False,
  /// and nothing changed, when something else changed those items since.
  bool revert(List<Mutation> applied) {
    if (applied.isEmpty) return false;
    if (_writing && _pending != null && _kindOf[applied] == null) {
      if (_pending == _Kind.command && _open != null) return false;
      _deferred = applied;
      return true;
    }
    final kind = _kindOf[applied];
    return kind != null && _takeBack(applied, kind, _origin[applied]);
  }

  /// Whether [revert] would take it back now — the same checks, nothing written.
  bool canRevert(List<Mutation> applied) {
    final kind = _kindOf[applied];
    return applied.isNotEmpty && kind != null && _mayTakeBack(applied, kind, _origin[applied]);
  }

  /// Every [run] inside [fn] becomes a single entry. If [fn] throws, what it
  /// already applied stays applied and undoable as that entry.
  T transaction<T>(String label, T Function() fn) {
    if (_open != null) return fn();
    final entry = _Entry(label, [], null);
    _open = entry;
    try {
      return fn();
    } finally {
      _open = null;
      entry.mutations = _compact(entry.mutations);
      if (entry.mutations.isNotEmpty) _push(entry);
      _notify();
    }
  }

  void clear() {
    _done = [];
    _undone = [];
    _notify();
  }

  /// Stops listening to the store, and drops the listeners.
  void dispose() {
    _unsubscribe();
    _listeners.clear();
  }
}
