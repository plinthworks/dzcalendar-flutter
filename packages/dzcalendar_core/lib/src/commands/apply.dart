import '../event/normalize.dart';
import '../event/parse_temporal.dart';
import '../event/problem.dart';
import '../event/types.dart';
import '../recurrence/edit.dart';
import '../recurrence/series.dart';
import '../rrule/rule.dart';
import '../store/changes.dart';
import '../store/store.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/zoned.dart';
import 'patch.dart';
import 'types.dart';

final _dateHead = RegExp(r'^\d{4}-\d{2}-\d{2}');
final _annotated = RegExp(r'\[.+\]$');
final _offsetEnd = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);

/// An occurrence's key as the series writes it, from what a person or an
/// assistant may write: the wall time without the offset
/// (`2026-10-21T08:00[Europe/Paris]`, or no zone: the series'), an instant
/// (`…Z`). Anything else is left as given (it then names no occurrence).
String _keyIn(Series sr, String key) {
  if (sr.allDay) return key.length > 10 && _dateHead.hasMatch(key) ? key.substring(0, 10) : key;
  final zone = (sr.start as ZonedDateTime).zone;
  if (_annotated.hasMatch(key)) {
    final z = parseZonedDateTime(key);
    return z == null ? key : '${z.withTimeZone(zone)}';
  }
  if (_offsetEnd.hasMatch(key)) {
    final i = Instant.tryParse(key);
    return i == null ? key : '${i.inZone(zone)}';
  }
  final wall = PlainDateTime.tryParse(key);
  return wall == null ? key : '${ZonedDateTime.fromWall(wall, zone)}';
}

const _wkst = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
final _rrulePrefix = RegExp(r'^RRULE:', caseSensitive: false);
final _trailingSemicolon = RegExp(r';\s*$');
final _wkstPart = RegExp(r'^\s*WKST\s*=', caseSensitive: false);

/// A rule created here without WKST gets the locale's first day, written out.
Object? _withWeekStart(Object? rrule, int? weekStart) {
  if (weekStart == null || rrule == null) return rrule;
  Object? add(Object? t) {
    if (t is! String) return t;
    final body = t.trim().replaceFirst(_rrulePrefix, '').replaceFirst(_trailingSemicolon, '').trim();
    if (body.split(';').any(_wkstPart.hasMatch)) return t;
    return '$body;WKST=${_wkst[weekStart - 1]}';
  }

  return switch (rrule) {
    String s => add(s),
    List<Object?> l => [for (final t in l) add(t)],
    _ => rrule,
  };
}

EventInput _withRule(EventInput i, Object? rrule) => EventInput(
  id: i.id,
  groupId: i.groupId,
  title: i.title,
  start: i.start,
  end: i.end,
  duration: i.duration,
  allDay: i.allDay,
  timeZone: i.timeZone,
  resourceId: i.resourceId,
  resourceIds: i.resourceIds,
  rrule: rrule,
  exdate: i.exdate,
  rdate: i.rdate,
  seriesId: i.seriesId,
  recurrenceId: i.recurrenceId,
  display: i.display,
  status: i.status,
  busy: i.busy,
  editable: i.editable,
  startEditable: i.startEditable,
  durationEditable: i.durationEditable,
  resourceEditable: i.resourceEditable,
  classNames: i.classNames,
  tone: i.tone,
  url: i.url,
  extendedProps: i.extendedProps,
  ongoing: i.ongoing,
);

/// What a command's id names: a plain event, or an occurrence of a series and how far the edit reaches.
sealed class _Target {}

final class _EventTarget extends _Target {
  _EventTarget(this.event);
  final CalEvent event;
}

final class _OccurrenceTarget extends _Target {
  _OccurrenceTarget(this.ref, this.scope);
  final OccurrenceRef ref;
  final EditScope scope;
}

/// Turns a command into the mutations that carry it out, against [snap].
/// Pure: nothing is applied, so a command can be checked, previewed or
/// refused without touching the store. All or nothing — a batch with one
/// bad command yields no mutation at all.
CommandResult applyCommand(StoreSnapshot snap, Command cmd, CommandContext ctx) {
  // A bad context is the programmer's, not the data's: it throws, once.
  final weekStart = ctx.weekStart;
  if (weekStart != null && (weekStart < 1 || weekStart > 7)) {
    throw ArgumentError.value(weekStart, 'weekStart', 'an ISO weekday, 1 to 7');
  }
  final problems = <Problem>[];
  final mutations = <Mutation>[];
  var current = snap;

  // Each step sees the state the previous ones made: create then update works.
  bool push(Mutation m) {
    mutations.add(m);
    current = current.withMutations([m]).next;
    return true;
  }

  bool pushAll(List<Mutation> ms) {
    ms.forEach(push);
    return true;
  }

  void fail(ProblemCode code, String path, String detail) => problems.add(Problem(code, Severity.error, path, detail));

  /// Resolves `id` (+ key, scope) against the current state; reports and
  /// returns null when it names nothing editable.
  _Target? target(String id, Reach reach, String path, {bool deleting = false}) {
    final ev = current.getEvent(id);
    if (ev != null) {
      // An override stands for its occurrence: deleting it, or reaching past it, goes through the series.
      final ref = ev.ref;
      if (ref != null && (deleting || (reach.scope != null && reach.scope != EditScope.this_))) {
        return _OccurrenceTarget(ref, reach.scope ?? EditScope.this_);
      }
      return _EventTarget(ev);
    }
    final sr = current.getSeries(id);
    // No key: the series as a whole, anchored on its first start.
    if (sr != null) {
      final key = reach.key;
      return _OccurrenceTarget(
        EventRef(id, key != null ? _keyIn(sr, key) : firstKey(sr)),
        reach.scope ?? (key == null ? EditScope.all : EditScope.this_),
      );
    }
    final k = parseInstanceKey(id);
    final of = k.seriesId == null ? null : current.getSeries(k.seriesId!);
    if (of != null) return _OccurrenceTarget(EventRef(of.id, _keyIn(of, k.key!)), reach.scope ?? EditScope.this_);
    fail(ProblemCode.unknownEvent, '$path.id', id);
    return null;
  }

  /// The event a target shows now.
  CalEvent? shown(_Target t) {
    switch (t) {
      case _EventTarget(:final event):
        return event;
      case _OccurrenceTarget(:final ref):
        final sr = current.getSeries(ref.seriesId)!;
        final own = sr.overrides[ref.key];
        if (own != null) return current.getEvent(own);
        final at = startOfKey(sr, ref.key);
        return at == null ? null : materialize(sr, at);
    }
  }

  bool edit(String id, EventPatch patch, Reach reach, String path) {
    // Set and cleared at once: the patch says two things; refused, never guessed.
    final conflicts = patch.conflicts;
    if (conflicts.isNotEmpty) {
      for (final f in conflicts) {
        fail(ProblemCode.invalidEdit, '$path.patch.${f.name}', 'both set and cleared');
      }
      return false;
    }
    final t = target(id, reach, path);
    switch (t) {
      case null:
        return false;
      case _EventTarget(:final event):
        final next = patchEvent(event, patch, ctx.normalize, path, problems);
        if (next == null) return false;
        return identical(next, event) || push(EventMutation(before: event, after: next));
      case _OccurrenceTarget(:final ref, :final scope):
        final r = editOccurrence(current, ref, patch, scope, ctx.normalize, path, problems);
        return r != null && pushAll(r);
    }
  }

  bool run(Command c, String path) {
    switch (c) {
      case InvalidCommand(problems: final read):
        problems.addAll(read);
        return false;
      case CreateEvent(:final event):
        final r = normalizeEvent(_withRule(event, _withWeekStart(event.rrule, ctx.weekStart)), ctx.normalize, path);
        problems.addAll(r.problems);
        final item = r.value;
        if (item == null) return false;
        final id = switch (item) {
          NormalizedEvent(:final event) => event.id,
          NormalizedSeries(:final series) => series.id,
        };
        // A command refuses an id used by either: `update('x')` must never be ambiguous.
        if (current.getEvent(id) != null || current.getSeries(id) != null) {
          fail(ProblemCode.duplicateId, '$path.id', id);
          return false;
        }
        return push(switch (item) {
          NormalizedEvent(:final event) => EventMutation(after: event),
          NormalizedSeries(:final series) => SeriesMutation(after: series),
        });
      case UpdateEvent(:final id, :final patch):
        return edit(id, patch, c, path);
      case MoveEvent(:final id, :final start, :final end, :final resourceIds):
        // A running event moved: its start, and its expected length kept.
        final running = current.getEvent(id);
        final keepEnd = !(running is TimedEvent && running.ongoing);
        return edit(id, EventPatch(start: start, end: keepEnd ? end : null, resourceIds: resourceIds), c, path);
      case ResizeEvent(:final id, :final edge, :final to):
        final t = target(id, c, path);
        if (t == null) return false;
        final now = shown(t);
        if (now == null) return false;
        // The other edge stays where it is; a running event's is its expected end.
        final Object? other = switch (now) {
          TimedEvent(ongoing: true, :final expectedEnd) => expectedEnd,
          TimedEvent(:final end) => end,
          AllDayEvent(:final end) => end,
        };
        return edit(id, edge == Edge.start ? EventPatch(start: to, end: other) : EventPatch(end: to), c, path);
      case DeleteEvent(:final id):
        final t = target(id, c, path, deleting: true);
        switch (t) {
          case null:
            return false;
          case _EventTarget(:final event):
            return push(EventMutation(before: event));
          case _OccurrenceTarget(:final ref, :final scope):
            final r = deleteOccurrence(current, ref, scope, path, problems);
            return r != null && pushAll(r);
        }
      case DeleteSeries(:final id):
        final sr = current.getSeries(id);
        if (sr == null) {
          fail(ProblemCode.unknownEvent, '$path.id', id);
          return false;
        }
        return pushAll(deleteSeries(current, sr));
      case SplitSeries(:final id, :final at, :final patch):
        final sr = current.getSeries(id);
        if (sr == null) {
          fail(ProblemCode.unknownEvent, '$path.id', id);
          return false;
        }
        final r = editOccurrence(
          current,
          EventRef(id, _keyIn(sr, at)),
          patch ?? const EventPatch(),
          EditScope.following,
          ctx.normalize,
          path,
          problems,
          forceSplit: true,
        );
        return r != null && pushAll(r);
      case RepeatEvent(:final id, :final rrule):
        final ev = current.getEvent(id);
        if (ev == null || ev.ref != null) {
          fail(ProblemCode.unknownEvent, '$path.id', id);
          return false;
        }
        final r = normalizeEvent(_withRule(toInput(ev), _withWeekStart(rrule, ctx.weekStart)), ctx.normalize, path);
        problems.addAll(r.problems);
        final item = r.value;
        if (item is! NormalizedSeries) return false;
        final series = ev.sourceId != null ? item.series.copyWith(sourceId: ev.sourceId) : item.series;
        push(EventMutation(before: ev));
        _warnIfEmpty(series, ctx, path, problems);
        return push(SeriesMutation(after: series));
      case ChangeRule(:final id, :final rrule):
        final sr = current.getSeries(id);
        if (sr == null) {
          fail(ProblemCode.unknownEvent, '$path.id', id);
          return false;
        }
        if (rrule == null || (rrule is List && rrule.isEmpty)) {
          // It stops repeating: the first occurrence is the event, a moved one an event of its own.
          for (final oid in sr.overrides.values) {
            final o = current.getEvent(oid);
            if (o != null) push(EventMutation(before: o, after: withRef(o, null)));
          }
          push(SeriesMutation(before: sr));
          final base = withRef(sr.base, null);
          return push(EventMutation(after: sr.sourceId != null ? base.withIdentity(base.id, sr.sourceId) : base));
        }
        // A rule given without WKST keeps the series' own (not the reader's locale).
        final own = sr.set.rules.isNotEmpty ? sr.set.rules.first.wkst : null;
        final written = _withWeekStart(rrule, own ?? ctx.weekStart);
        final texts = switch (written) {
          String s => [s],
          List<Object?> l => l,
          _ => const <Object?>[],
        };
        final rules = <RRule>[];
        for (var i = 0; i < texts.length; i++) {
          final text = texts[i];
          final sub = texts.length > 1 ? '$path.rrule[$i]' : '$path.rrule';
          final parsed = text is String ? parseRRule(text) : null;
          final rule = parsed?.rule;
          if (rule == null) {
            fail(ProblemCode.invalidRrule, sub, parsed?.problem?.detail ?? '$text');
            return false;
          }
          if (sr.allDay && rule.subDaily) {
            fail(ProblemCode.invalidRrule, sub, 'FREQ=${rule.freq.name.toUpperCase()}');
            return false;
          }
          rules.add(rule);
        }
        if (rules.isEmpty) {
          fail(ProblemCode.invalidRrule, '$path.rrule', '$rrule');
          return false;
        }
        final next = sr.copyWith(
          set: RRuleSet(rules, exdates: sr.set.exdates, rdates: sr.set.rdates),
        );
        _warnIfEmpty(next, ctx, path, problems);
        return push(SeriesMutation(before: sr, after: next));
      case Batch(:final commands):
        for (var i = 0; i < commands.length; i++) {
          if (!run(commands[i], '$path.commands[$i]')) return false;
        }
        return true;
    }
  }

  return run(cmd, 'command') ? CommandResult.ok(mutations, problems) : CommandResult.failed(problems);
}

/// A rule that can never give an occurrence (an UNTIL before the start…): said, as a warning.
void _warnIfEmpty(Series sr, CommandContext ctx, String path, List<Problem> problems) {
  final zone = ctx.normalize.displayZone;
  final d0 = switch (sr.base) {
    AllDayEvent(:final start) => start,
    TimedEvent(:final start) => start.withTimeZone(zone).date,
  };
  if (expandSeries(sr, viewWindow(d0, d0.addYears(10), zone), limit: 1).occurrences.isEmpty) {
    problems.add(Problem(ProblemCode.invalidRrule, Severity.warning, '$path.rrule', 'no occurrence'));
  }
}
