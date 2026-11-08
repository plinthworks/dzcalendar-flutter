import '../commands/patch.dart';
import '../commands/types.dart';
import '../event/normalize.dart';
import '../event/parse_temporal.dart';
import '../event/problem.dart';
import '../event/types.dart';
import '../rrule/edit.dart';
import '../rrule/expand.dart';
import '../rrule/rule.dart';
import '../store/changes.dart';
import '../store/store.dart';
import '../time/duration.dart';
import '../time/plain.dart';
import '../zone/zoned.dart';
import 'series.dart';

/// One occurrence: its series and its original start.
typedef OccurrenceRef = EventRef;

/// The mutations that carry an edit out, or null when it cannot be done
/// (the problems say why).
typedef EditResult = List<Mutation>?;

/// The original start a key stands for, or null when the key is not even one.
Start? startOfKey(Series sr, RecurrenceKey key) => sr.allDay ? PlainDate.tryParse(key) : parseZonedDateTime(key);

/// True when the series shows an occurrence at that key now (an override
/// counts; an EXDATE does not).
bool isOccurrence(Series sr, RecurrenceKey key) {
  if (sr.overrides.containsKey(key)) return true;
  final at = startOfKey(sr, key);
  if (at == null) return false;
  return switch ((sr.start, at)) {
    (PlainDate s, PlainDate a) => expandDates(s, sr.set, a, a.addDays(1), 1).starts.any((d) => d == a),
    (ZonedDateTime s, ZonedDateTime a) => expandZoned(
      s,
      sr.set,
      a.instant,
      a.instant.addMs(1),
      1,
    ).starts.any((x) => '$x' == key),
    _ => false,
  };
}

/// The first start the series' rules and RDATEs produce (an excluded one
/// too: it is still the series' first key).
RecurrenceKey firstKey(Series sr) => keyOf(nthStart(sr.start, sr.set, 0) ?? sr.start);

/// The occurrence as it is now: its override, or the series' own.
CalEvent? _current(StoreSnapshot snap, Series sr, RecurrenceKey key) {
  final id = sr.overrides[key];
  if (id != null) return snap.getEvent(id);
  final at = startOfKey(sr, key);
  return at == null ? null : materialize(sr, at);
}

/// How a start moves when one occurrence moves from [from] to [to]: the same
/// wall-clock difference, in its own zone.
Start _shiftStart(Start x, Start from, Start to) {
  if (from is PlainDate || x is PlainDate) {
    final toDate = to is PlainDate ? to : (to as ZonedDateTime).date;
    final fromDate = from is PlainDate ? from : (from as ZonedDateTime).date;
    final days = fromDate.daysUntil(toDate);
    return x is PlainDate ? x.addDays(days) : (x as ZonedDateTime).add(IsoDuration(days: days));
  }
  final delta = (to as ZonedDateTime).plainDateTime.wallMs - (from as ZonedDateTime).plainDateTime.wallMs;
  final z = x as ZonedDateTime;
  return ZonedDateTime.fromWall(z.plainDateTime.addMs(delta), z.zone)!;
}

/// An EXDATE as the start it excludes (a date on a timed series: the
/// series' first start that day).
Start? _exdateStart(Series sr, ExDate x) {
  if (sr.allDay) {
    return switch (x) {
      ExDay(:final date) => date,
      ExInstant(:final at) => at.inZone('UTC').date,
    };
  }
  final zone = (sr.start as ZonedDateTime).zone;
  switch (x) {
    case ExInstant(:final at):
      return at.inZone(zone);
    case ExDay(:final date):
      for (final s in iterateUnion(sr.start, sr.set)) {
        final c = (s as ZonedDateTime).date.compareTo(date);
        if (c == 0) return s;
        if (c > 0) return null;
      }
      return null;
  }
}

IsoDuration _unit(Frequency f, int n) => switch (f) {
  Frequency.yearly => IsoDuration(years: n),
  Frequency.monthly => IsoDuration(months: n),
  Frequency.weekly => IsoDuration(weeks: n),
  Frequency.daily => IsoDuration(days: n),
  Frequency.hourly => IsoDuration(hours: n),
  Frequency.minutely => IsoDuration(minutes: n),
  Frequency.secondly => IsoDuration(seconds: n),
};

Start _minus(Start x, IsoDuration d) =>
    x is PlainDate ? d.negated().addCalendarTo(x) : (x as ZonedDateTime).subtract(d);

Start _startOf(CalEvent e) => switch (e) {
  TimedEvent(:final start) => start,
  AllDayEvent(:final start) => start,
};

/// What the base takes from the edited occurrence: everything but its place,
/// its link, its source tag.
CalEvent _baseFields(CalEvent edited, SeriesId id, Series sr) => switch (edited) {
  TimedEvent() => edited.copyWith(id: id, ref: null, sourceId: null, revision: sr.base.revision),
  AllDayEvent() => edited.copyWith(id: id, ref: null, sourceId: null, revision: sr.base.revision),
};

CalEvent _withSpan(CalEvent fields, Start start, IsoDuration length, CalEvent edited) => switch (fields) {
  AllDayEvent() => fields.copyWith(start: start as PlainDate, end: start.addDays(length.days < 1 ? 1 : length.days)),
  TimedEvent() => fields.copyWith(
    start: start as ZonedDateTime,
    end: start.add(length).withTimeZone((edited as TimedEvent).end.zone),
  ),
};

/// The series moved so that its occurrence at [at] becomes [edited]: rules
/// recounted from that occurrence, the new first start the one that keeps
/// it at its position, and every key (overrides, EXDATEs, UNTIL) carried by
/// position — the fourth occurrence stays the fourth. Null when the rules
/// cannot describe the move.
({Series series, Map<RecurrenceKey, RecurrenceKey> keys})? _moveAll(
  Series sr,
  Start at,
  CalEvent edited,
  IsoDuration length,
  SeriesId id,
) {
  final fields = _baseFields(edited, id, sr);
  final keys = <RecurrenceKey, RecurrenceKey>{};
  final to = _startOf(edited);
  if (sameStart(at, to)) {
    // Nothing moves: the base takes the new fields, every key stays.
    for (final k in sr.overrides.keys) {
      keys[k] = k;
    }
    return (series: sr.copyWith(id: id, base: _withSpan(fields, sr.start, length, edited)), keys: keys);
  }

  final old = sr.start;
  final index = indexOfStart(old, sr.set, at);
  if (index < 0) return null;

  // Rules written out (what they took from the old start), then recounted around the moved occurrence.
  final rewritten = [
    for (final r in sr.set.rules)
      if (explicitRule(r, old) case (:final rule, :final added))
        (open: rebaseRule(rule, at, to).open, added: added, original: r),
  ];
  final rdates = [
    for (final x in sr.set.rdates)
      switch (_shiftStart(
        switch (x) {
          RDay(:final date) => date,
          RZoned(:final at) => at,
        },
        at,
        to,
      )) {
        PlainDate d => RDate.date(d),
        final z => RDate.zoned(z as ZonedDateTime),
      },
  ];
  final openSet = RRuleSet([for (final w in rewritten) w.open], rdates: rdates);

  // The new first start: `index` starts before `to`, looking back whole periods so INTERVAL keeps its phase.
  final freq = rewritten.isNotEmpty ? rewritten.first.open.freq : Frequency.daily;
  var step = 1;
  for (final w in rewritten) {
    if (w.open.interval > step) step = w.open.interval;
  }
  Start? first;
  for (var back = index + 1; back <= (index + 1) * 64 && first == null; back *= 2) {
    final from = _minus(to, _unit(freq, back * step));
    final seq = <Start>[];
    var found = false;
    for (final s in iterateUnion(from, openSet)) {
      if (sameStart(s, to)) {
        found = true;
        break;
      }
      if (startBefore(to, s) || seq.length > 200000) break;
      seq.add(s);
    }
    if (!found) return null;
    if (seq.length >= index) first = index == 0 ? to : seq[seq.length - index];
  }
  final f = first;
  if (f == null) return null;

  // Counts stay; an UNTIL moves to where the old last occurrence of its rule went.
  final rules = <RRule>[];
  for (final w in rewritten) {
    var r = w.open;
    final count = w.original.count;
    if (count != null) r = r.copyWith(count: count);
    if (w.original.hasUntil) {
      Start? last;
      for (final s in iterateUnion(old, RRuleSet([w.original]))) {
        last = s;
      }
      final i = last != null ? indexOfStart(old, sr.set, last) : -1;
      final moved = i >= 0 ? nthStart(f, openSet, i) : null;
      r = switch (moved) {
        PlainDate d => r.copyWith(untilDate: d),
        ZonedDateTime z => r.copyWith(untilInstant: z.instant),
        _ => r.copyWith(untilDate: w.original.untilDate, untilInstant: w.original.untilInstant),
      };
    }
    rules.add(implicitRule(r, f, w.added));
  }
  final set = RRuleSet(rules, rdates: rdates);

  // Keys go by position — found in one walk of each series.
  final wanted = <(Start?, void Function(Start))>[];
  final exdates = <ExDate>[];
  for (final x in sr.set.exdates) {
    wanted.add((
      _exdateStart(sr, x),
      (m) => exdates.add(switch (m) {
        PlainDate d => ExDate.date(d),
        _ => x is ExDay ? ExDate.date((m as ZonedDateTime).date) : ExDate.instant((m as ZonedDateTime).instant),
      }),
    ));
  }
  for (final k in sr.overrides.keys) {
    wanted.add((startOfKey(sr, k), (m) => keys[k] = keyOf(m)));
  }
  final positions = _positionsOf(old, sr.set, [for (final w in wanted) w.$1]);
  final found = _startsAt(f, set, positions);
  for (var i = 0; i < wanted.length; i++) {
    final m = positions[i] >= 0 ? found[positions[i]] : null;
    if (m != null) wanted[i].$2(m);
  }

  final series = sr.copyWith(
    id: id,
    base: _withSpan(fields, f, length, edited),
    set: RRuleSet(set.rules, exdates: exdates, rdates: set.rdates),
  );
  // The occurrence edited must be where it was asked to be.
  final check = nthStart(f, series.set, index);
  if (check == null || !sameStart(check, to)) return null;
  return (series: series, keys: keys);
}

/// The position of each start in the set (-1 when absent), in one walk.
List<int> _positionsOf(Start start, RRuleSet set, List<Start?> wanted) {
  final index = <String, List<int>>{};
  for (var i = 0; i < wanted.length; i++) {
    final w = wanted[i];
    if (w != null) (index['$w'] ??= []).add(i);
  }
  final out = List.filled(wanted.length, -1);
  Start? last;
  for (final w in wanted) {
    if (w != null && (last == null || startBefore(last, w))) last = w;
  }
  if (last == null) return out;
  var i = 0;
  var left = index.length;
  for (final s in iterateUnion(start, set)) {
    final hit = index['$s'];
    if (hit != null) {
      for (final j in hit) {
        out[j] = i;
      }
      if (--left == 0) break;
    }
    if (startBefore(last, s) || ++i > 200000) break;
  }
  return out;
}

/// The starts at these positions, in one walk.
Map<int, Start> _startsAt(Start start, RRuleSet set, List<int> positions) {
  final want = positions.where((p) => p >= 0).toSet();
  final out = <int, Start>{};
  if (want.isEmpty) return out;
  final max = want.reduce((a, b) => a > b ? a : b);
  var i = 0;
  for (final s in iterateUnion(start, set)) {
    if (want.contains(i)) out[i] = s;
    if (++i > max) break;
  }
  return out;
}

/// Edits one occurrence, the following ones, or all of them. Pure: the
/// mutations that carry it out, nothing applied. [forceSplit]: cut even when
/// the patch changes nothing (`series.split`). [dropOverrides]: `all` lets
/// the series take back the occurrences edited on their own.
EditResult editOccurrence(
  StoreSnapshot snap,
  OccurrenceRef ref,
  EventPatch patch,
  EditScope scope,
  NormalizeContext ctx,
  String path,
  List<Problem> problems, {
  bool dropOverrides = false,
  bool forceSplit = false,
}) {
  final sr = snap.getSeries(ref.seriesId);
  if (sr == null) {
    problems.add(Problem(ProblemCode.unknownEvent, Severity.error, '$path.id', ref.seriesId));
    return null;
  }
  final at = startOfKey(sr, ref.key);
  // "All" may be anchored on any key of the series (an excluded first one too); the others need a shown occurrence.
  final known =
      at != null &&
      (scope == EditScope.all
          ? sr.overrides.containsKey(ref.key) || indexOfStart(sr.start, sr.set, at) >= 0
          : isOccurrence(sr, ref.key));
  if (at == null || !known) {
    problems.add(Problem(ProblemCode.unknownOccurrence, Severity.error, '$path.key', ref.key));
    return null;
  }
  // `this` edits the occurrence as it is now (its override, if any); the
  // others edit what the series itself makes there, so an override's own
  // move is not spread to every occurrence.
  final target = scope == EditScope.this_ ? _current(snap, sr, ref.key) : materialize(sr, at);
  if (target == null) {
    problems.add(Problem(ProblemCode.unknownEvent, Severity.error, '$path.key', ref.key));
    return null;
  }
  final edited = patchEvent(target, patch, ctx, path, problems);
  if (edited == null) return null;
  if (identical(edited, target) && !(forceSplit && scope == EditScope.following)) return const [];
  if (scope != EditScope.this_ && edited.allDay != sr.allDay) {
    // A whole series switching between days and times needs its rules rewritten: one occurrence only.
    problems.add(
      Problem(
        ProblemCode.invalidEdit,
        Severity.error,
        '$path.patch.allDay',
        'only one occurrence can change between all-day and timed',
      ),
    );
    return null;
  }
  if (scope == EditScope.this_) return _editThis(sr, ref.key, target, edited, ctx);

  // A start-only move keeps the series' own length, not the moved occurrence's.
  final length = patch.hasEnd || patch.hasDuration ? occurrenceLength(edited) : occurrenceLength(sr.base);
  final first = indexOfStart(sr.start, sr.set, at) == 0;
  final r = scope == EditScope.all || first
      ? _editAll(snap, sr, at, edited, length, dropOverrides)
      : _editFollowing(snap, sr, ref.key, at, edited, length, ctx);
  if (r == null) {
    problems.add(
      Problem(ProblemCode.invalidEdit, Severity.error, '$path.key', 'the series cannot repeat this way from here'),
    );
  }
  return r;
}

List<Mutation> _editThis(Series sr, RecurrenceKey key, CalEvent occ, CalEvent edited, NormalizeContext ctx) {
  if (sr.overrides.containsKey(key)) return [EventMutation(before: occ, after: edited)];
  // A new event stands in for the occurrence, found at its new place by the
  // ordinary index; the series skips its key from now on.
  final id = ctx.newId();
  final ref = EventRef(sr.id, key);
  final override = switch (edited) {
    TimedEvent() => edited.copyWith(id: id, sourceId: null, revision: 0, ref: ref),
    AllDayEvent() => edited.copyWith(id: id, sourceId: null, revision: 0, ref: ref),
  };
  return [
    EventMutation(after: override),
    SeriesMutation(
      before: sr,
      after: sr.copyWith(overrides: {...sr.overrides, key: id}),
    ),
  ];
}

/// The override events re-linked to their new keys (and series); those whose place is gone go too.
Map<RecurrenceKey, EventId> _relink(
  StoreSnapshot snap,
  Map<RecurrenceKey, EventId> overrides,
  Map<RecurrenceKey, RecurrenceKey> keys,
  SeriesId seriesId,
  List<Mutation> out,
) {
  final next = <RecurrenceKey, EventId>{};
  for (final MapEntry(key: k, value: id) in overrides.entries) {
    final ev = snap.getEvent(id);
    final nk = keys[k];
    if (nk == null) {
      if (ev != null) out.add(EventMutation(before: ev));
      continue;
    }
    next[nk] = id;
    if (ev != null && (nk != k || ev.ref?.seriesId != seriesId)) {
      out.add(EventMutation(before: ev, after: withRef(ev, EventRef(seriesId, nk))));
    }
  }
  return next;
}

List<Mutation>? _editAll(StoreSnapshot snap, Series sr, Start at, CalEvent edited, IsoDuration length, bool drop) {
  final moved = _moveAll(sr, at, edited, length, sr.id);
  if (moved == null) return null;
  final mutations = <Mutation>[];
  Map<RecurrenceKey, EventId> overrides;
  if (drop) {
    for (final id in sr.overrides.values) {
      final ev = snap.getEvent(id);
      if (ev != null) mutations.add(EventMutation(before: ev));
    }
    overrides = {};
  } else {
    overrides = _relink(snap, sr.overrides, moved.keys, sr.id, mutations);
  }
  mutations.add(
    SeriesMutation(
      before: sr,
      after: moved.series.copyWith(overrides: overrides),
    ),
  );
  return mutations;
}

List<Mutation>? _editFollowing(
  StoreSnapshot snap,
  Series sr,
  RecurrenceKey key,
  Start at,
  CalEvent edited,
  IsoDuration length,
  NormalizeContext ctx,
) {
  final (:head, :tail) = _cutSeries(sr, at);
  final id = ctx.newId();
  final mutations = <Mutation>[];

  // The occurrence edited becomes the first of the new series: its own override is folded in.
  final own = sr.overrides[key];
  final ownEvent = own == null ? null : snap.getEvent(own);
  if (ownEvent != null) mutations.add(EventMutation(before: ownEvent));

  final headOverrides = <RecurrenceKey, EventId>{};
  final tailOverrides = <RecurrenceKey, EventId>{};
  for (final MapEntry(key: k, value: v) in sr.overrides.entries) {
    if (k == key) continue;
    final s = startOfKey(sr, k);
    (s != null && startBefore(s, at) ? headOverrides : tailOverrides)[k] = v;
  }

  // The rest of the series as a series of its own, from the cut, unchanged:
  // it must repeat exactly what the old one did from there on.
  final occurrence = materialize(sr, at);
  final tailSeries = Series(
    id: id,
    revision: sr.revision,
    base: switch (occurrence) {
      TimedEvent() => occurrence.copyWith(id: id),
      AllDayEvent() => occurrence.copyWith(id: id),
    },
    set: tail,
    overrides: tailOverrides,
    splitFrom: sr.splitFrom,
  );
  if (!_sameUnion(sr, at, tailSeries)) return null;

  mutations.add(
    SeriesMutation(
      before: sr,
      after: sr.copyWith(set: head, overrides: headOverrides),
    ),
  );
  final repeats = nthStart(at, tail, 1) != null;
  if (!repeats) {
    // Nothing repeats after the cut: the edited occurrence is a plain event now.
    for (final v in tailOverrides.values) {
      final ev = snap.getEvent(v);
      if (ev != null) mutations.add(EventMutation(before: ev));
    }
    mutations.add(
      EventMutation(
        after: switch (edited) {
          TimedEvent() => edited.copyWith(id: id, ref: null, sourceId: null, revision: 0),
          AllDayEvent() => edited.copyWith(id: id, ref: null, sourceId: null, revision: 0),
        },
      ),
    );
    return mutations;
  }
  final moved = _moveAll(tailSeries, at, edited, length, id);
  if (moved == null) return null;
  final overrides = _relink(snap, tailOverrides, moved.keys, id, mutations);
  mutations.add(
    SeriesMutation(
      after: moved.series.copyWith(id: id, revision: 0, overrides: overrides, splitFrom: SplitFrom(sr.id, key)),
    ),
  );
  return mutations;
}

/// True when [tail] (starting at [at]) repeats what [sr] did from [at] on — the first 64 starts.
bool _sameUnion(Series sr, Start at, Series tail) {
  final a = <String>[];
  for (final s in iterateUnion(sr.start, sr.set)) {
    if (startBefore(s, at)) continue;
    a.add('$s');
    if (a.length == 64) break;
  }
  final b = <String>[];
  for (final s in iterateUnion(tail.start, tail.set)) {
    b.add('$s');
    if (b.length == 64) break;
  }
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The series on each side of a cut (the cut goes to the tail). The tail's
/// rules have what they took from the old start written out; the cut is
/// added as an RDATE when no rule starts there, so the tail begins with it.
({RRuleSet head, RRuleSet tail}) _cutSeries(Series sr, Start at) {
  final headRules = <RRule>[];
  final tailRules = <RRule>[];
  for (final r in sr.set.rules) {
    final (:before, :after) = splitRule(r, sr.start, at);
    if (before != null) headRules.add(before);
    if (after != null) {
      final (:rule, :added) = explicitRule(after, sr.start);
      tailRules.add(implicitRule(rule, at, added));
    }
  }
  final atMs = at is ZonedDateTime ? at.epochMilliseconds : 0;
  final atDate = at is PlainDate ? at : (at as ZonedDateTime).date;
  bool exAfter(ExDate x) => switch (x) {
    ExDay(:final date) => !date.isBefore(atDate),
    ExInstant(at: final i) => i.epochMilliseconds >= atMs,
  };
  bool rAfter(RDate x) => switch (x) {
    RDay(:final date) => !date.isBefore(atDate),
    RZoned(at: final z) => z.epochMilliseconds >= atMs,
  };
  final tailRdates = sr.set.rdates.where(rAfter).toList();
  final tail = RRuleSet(tailRules, exdates: sr.set.exdates.where(exAfter).toList(), rdates: tailRdates);
  final startsAtCut = nthStart(at, tail, 0);
  final head = RRuleSet(
    headRules,
    exdates: sr.set.exdates.where((x) => !exAfter(x)).toList(),
    rdates: sr.set.rdates.where((x) => !rAfter(x)).toList(),
  );
  if (startsAtCut != null && sameStart(startsAtCut, at)) return (head: head, tail: tail);
  final cut = at is PlainDate ? RDate.date(at) : RDate.zoned(at as ZonedDateTime);
  return (head: head, tail: RRuleSet(tailRules, exdates: tail.exdates, rdates: [cut, ...tailRdates]));
}

/// Deletes one occurrence (an EXDATE), the following ones (the series ends
/// before it), or the whole series.
EditResult deleteOccurrence(
  StoreSnapshot snap,
  OccurrenceRef ref,
  EditScope scope,
  String path,
  List<Problem> problems,
) {
  final sr = snap.getSeries(ref.seriesId);
  if (sr == null) {
    problems.add(Problem(ProblemCode.unknownEvent, Severity.error, '$path.id', ref.seriesId));
    return null;
  }
  if (scope == EditScope.all) return deleteSeries(snap, sr);
  final at = startOfKey(sr, ref.key);
  if (at == null || !isOccurrence(sr, ref.key)) {
    problems.add(Problem(ProblemCode.unknownOccurrence, Severity.error, '$path.key', ref.key));
    return null;
  }
  if (scope == EditScope.following && indexOfStart(sr.start, sr.set, at) == 0) return deleteSeries(snap, sr);
  final mutations = <Mutation>[];
  if (scope == EditScope.this_) {
    final own = sr.overrides[ref.key];
    final overrides = {...sr.overrides};
    if (own != null) {
      final ev = snap.getEvent(own);
      if (ev != null) mutations.add(EventMutation(before: ev));
      overrides.remove(ref.key);
    }
    final ex = at is PlainDate ? ExDate.date(at) : ExDate.instant((at as ZonedDateTime).instant);
    final set = RRuleSet(sr.set.rules, exdates: [...sr.set.exdates, ex], rdates: sr.set.rdates);
    mutations.add(
      SeriesMutation(
        before: sr,
        after: sr.copyWith(set: set, overrides: overrides),
      ),
    );
    return mutations;
  }
  final (:head, tail: _) = _cutSeries(sr, at);
  final overrides = <RecurrenceKey, EventId>{};
  for (final MapEntry(key: k, value: v) in sr.overrides.entries) {
    final s = startOfKey(sr, k);
    if (s != null && startBefore(s, at)) {
      overrides[k] = v;
    } else {
      final ev = snap.getEvent(v);
      if (ev != null) mutations.add(EventMutation(before: ev));
    }
  }
  mutations.add(
    SeriesMutation(
      before: sr,
      after: sr.copyWith(set: head, overrides: overrides),
    ),
  );
  return mutations;
}

/// The series and every event standing in for one of its occurrences.
List<Mutation> deleteSeries(StoreSnapshot snap, Series sr) => [
  for (final id in sr.overrides.values)
    if (snap.getEvent(id) case final ev?) EventMutation(before: ev),
  SeriesMutation(before: sr),
];
