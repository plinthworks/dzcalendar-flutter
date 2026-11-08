import 'dart:convert';

import '../event/parse_temporal.dart';
import '../event/problem.dart';
import '../rrule/rule.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../time/wall_time.dart';
import '../util/js.dart';
import '../zone/day_info.dart';
import '../zone/zoned.dart';
import 'engine.dart';
import 'types.dart';

/// A moment as the web reads it (`Temporal.Instant.from`, or
/// `Temporal.ZonedDateTime.from` when it names a zone): an [Instant], a
/// [ZonedDateTime], or ISO text with its offset (`2026-10-21T08:00Z`,
/// `…+03:00[Asia/Riyadh]`). An offset the zone does not have there is
/// refused, as Temporal's default `offset: 'reject'`. [exact]: false when
/// the text is written below the millisecond (kept to it).
({Instant at, bool exact})? readMomentExact(Object? m) {
  switch (m) {
    case Instant():
      return (at: m, exact: true);
    case ZonedDateTime():
      return (at: m.instant, exact: true);
    case final String s:
      final r = parseTemporal(s, 'moment', start: true);
      if (r.problems.any((p) => p.isError || p.code == ProblemCode.offsetMismatch)) return null;
      final exact = !r.problems.any((p) => p.code == ProblemCode.precisionTruncated);
      return switch (r.parsed) {
        ParsedZoned(:final value) when s.contains('[') => (at: value.instant, exact: exact),
        ParsedInstant(:final value) when !s.contains('[') => (at: value, exact: exact),
        _ => null,
      };
    default:
      return null;
  }
}

/// [readMomentExact]'s instant; null when it cannot be read.
Instant? readMoment(Object? m) => readMomentExact(m)?.at;

/// JavaScript's `typeof`, for the details the web writes.
String _typeOf(Object? x) => switch (x) {
  null || Map() || List() => 'object',
  String() => 'string',
  num() => 'number',
  bool() => 'boolean',
  _ => 'object',
};

/// A field's value as the web's details write it: `undefined` when absent.
String _text(Map<Object?, Object?> m, String key) => m.containsKey(key) ? jsText(m[key]) : 'undefined';

Duration _minutes(num m) => Duration(microseconds: jsRound(m * 60000000));

bool _slotMinutes(Object? x) => x is num && x >= 1 && x <= 525600;
bool _nonNegative(Object? x) => x is num && x.isFinite && x >= 0;

/// Reads the web's JSON query, checking in the web's order so the problems
/// come in the same order: the query's own fields first (an error ends the
/// reading: null), then `busy`, the weekly windows, the rules and the
/// exceptions (a warning drops the entry). [checking]: the start a
/// `checkSlot` looks at, the range when `from`/`to` are absent.
(SlotRequest?, List<Problem>) readSlotRequest(Object? json, {Object? checking}) {
  final problems = <Problem>[];
  (SlotRequest?, List<Problem>) bad(String path, String detail) {
    problems.add(Problem(ProblemCode.invalidSlotQuery, Severity.error, path, detail));
    return (null, problems);
  }

  void warn(String path, [String? detail]) =>
      problems.add(Problem(ProblemCode.invalidAvailability, Severity.warning, path, detail));

  if (json is! Map) return bad('query', jsText(json));
  final av = json['availability'];
  final zone = av is Map ? av['timeZone'] : null;
  if (zone is! String || !isValidZone(zone)) {
    final detail = av is Map ? _text(av, 'timeZone') : 'undefined';
    problems.add(Problem(ProblemCode.unknownZone, Severity.error, 'availability.timeZone', detail));
    return (null, problems);
  }
  av as Map;
  final duration = json['duration'];
  if (!_slotMinutes(duration)) return bad('duration', _text(json, 'duration'));
  final at = checking == null ? null : readMoment(checking);
  Instant? from;
  if (json.containsKey('from')) {
    from = readMoment(json['from']);
    if (from == null) return bad('from', _text(json, 'from'));
  } else if (at == null) {
    return bad('from', 'undefined');
  }
  Instant? to;
  if (json.containsKey('to')) {
    to = readMoment(json['to']);
    if (to == null) return bad('to', _text(json, 'to'));
  } else if (at == null) {
    return bad('to', 'undefined');
  }
  final step = json['step'];
  if (step != null && !_slotMinutes(step)) return bad('step', _text(json, 'step'));
  for (final k in const ['bufferBefore', 'bufferAfter', 'minNotice']) {
    if (json.containsKey(k) && !_nonNegative(json[k])) return bad(k, _text(json, k));
  }
  // Whole numbers: days are added as calendar days, bookings counted one by one.
  for (final k in const ['maxAdvanceDays', 'maxPerDay']) {
    final v = json[k];
    if (json.containsKey(k) && (v is! num || !wholeCount(v))) return bad(k, _text(json, k));
  }
  final busy = json['busy'];
  if (json.containsKey('busy') && busy is! List) return bad('busy', _typeOf(busy));
  Instant? now;
  if (json.containsKey('now')) {
    now = readMoment(json['now']);
    if (now == null) return bad('now', _text(json, 'now'));
  } else if (json.containsKey('minNotice') || json.containsKey('maxAdvanceDays')) {
    return bad('now', 'minNotice and maxAdvanceDays need now');
  }

  final busyList = <Busy>[];
  if (busy is List) {
    for (var i = 0; i < busy.length; i++) {
      final b = busy[i];
      final s = b is Map ? readMoment(b['start']) : null;
      final e = b is Map ? readMoment(b['end']) : null;
      if (s == null || e == null || e.isBefore(s)) {
        final detail = b is Map ? '${_text(b, 'start')}–${_text(b, 'end')}' : 'undefined–undefined';
        problems.add(Problem(ProblemCode.invalidSlotQuery, Severity.warning, 'busy[$i]', detail));
        continue;
      }
      busyList.add(Busy(start: s, end: e, kind: (b as Map)['kind'] == 'block' ? BusyKind.block : BusyKind.booking));
    }
  }

  List<Object?> list(String key, String path) {
    if (!av.containsKey(key)) return const [];
    final x = av[key];
    if (x is List) return x;
    warn(path, _typeOf(x));
    return const [];
  }

  Window? window(Object? w, String path) {
    if (w is Map && w['from'] != '24:00') {
      final f = w['from'];
      final t = w['to'];
      final from = f is String ? WallTime.tryParse(f) : null;
      final to = t is String ? WallTime.tryParse(t) : null;
      if (from != null && to != null) return Window(from, to);
    }
    warn(path, w == null ? 'null' : (w is Map ? '${_text(w, 'from')}–${_text(w, 'to')}' : 'undefined–undefined'));
    return null;
  }

  PlainDate? date(Map<Object?, Object?>? m, String key, String path) {
    final d = m?[key];
    final out = d is String ? PlainDate.tryParse(d) : null;
    if (out == null) warn(path, m == null ? 'undefined' : _text(m, key));
    return out;
  }

  final weekly = <WeeklyWindow>[];
  final weeklyJson = list('weekly', 'availability.weekly');
  for (var i = 0; i < weeklyJson.length; i++) {
    final path = 'availability.weekly[$i]';
    final w = window(weeklyJson[i], path);
    if (w == null) continue;
    final x = weeklyJson[i]! as Map;
    final days = x['days'];
    if (days is! List || !days.every((d) => d is int && d >= 1 && d <= 7)) {
      warn('$path.days', x.containsKey('days') ? jsonEncode(days) : null);
      continue;
    }
    weekly.add(WeeklyWindow(days: days.cast<int>(), window: w));
  }

  final rules = <RuleWindow>[];
  final rulesJson = list('rules', 'availability.rules');
  for (var i = 0; i < rulesJson.length; i++) {
    final path = 'availability.rules[$i]';
    final x = rulesJson[i];
    final w = window(x, path);
    // A null entry stops there; another non-object is read on, as the web reads its missing fields.
    if (x == null) continue;
    final m = x is Map ? x : null;
    final start = date(m, 'start', '$path.start');
    final rrule = m?['rrule'];
    if (rrule is! String || parseRRule(rrule).rule == null) {
      problems.add(
        Problem(ProblemCode.invalidRrule, Severity.warning, '$path.rrule', m == null ? 'undefined' : _text(m, 'rrule')),
      );
      continue;
    }
    if (w == null || start == null || m == null) continue;
    final exJson = m.containsKey('exdates') ? m['exdates'] : const <Object?>[];
    final exdates = <PlainDate>[];
    if (exJson is List) {
      for (var j = 0; j < exJson.length; j++) {
        final d = date({'d': exJson[j]}, 'd', '$path.exdates[$j]');
        if (d != null) exdates.add(d);
      }
    } else {
      warn('$path.exdates', _typeOf(exJson));
    }
    rules.add(RuleWindow(rrule: rrule, start: start, window: w, exdates: exdates));
  }

  // The dates the engine looks at (a week back for openings begun earlier): an exception
  // outside them is not read, as on the web.
  final rangeFrom = from ?? at!;
  final rangeTo = to ?? at!.addMs(jsRound((duration as num) * 60000));
  final first = ZonedDateTime(rangeFrom, zone).date.addDays(-7);
  final last = ZonedDateTime(rangeTo, zone).date.addDays(1);
  final exceptions = <DateException>[];
  final exJson = list('exceptions', 'availability.exceptions');
  for (var i = 0; i < exJson.length; i++) {
    final path = 'availability.exceptions[$i]';
    final x = exJson[i];
    final m = x is Map ? x : null;
    final d = date(m, 'date', '$path.date');
    if (m == null || d == null || d.isBefore(first) || !d.isBefore(last)) continue;
    final windows = <Window>[];
    final closed = m['closed'] == true;
    if (!closed) {
      final ws = m.containsKey('windows') ? m['windows'] : const <Object?>[];
      if (ws is List) {
        for (var j = 0; j < ws.length; j++) {
          final w = window(ws[j], '$path.windows[$j]');
          if (w != null) windows.add(w);
        }
      } else {
        warn('$path.windows', _typeOf(ws));
      }
    }
    exceptions.add(DateException(date: d, closed: closed, windows: windows));
  }

  return (
    SlotRequest(
      SlotRules(
        availability: Availability(timeZone: zone, weekly: weekly, exceptions: exceptions, rules: rules),
        duration: _minutes(duration as num),
        step: step == null ? null : _minutes(step as num),
        bufferBefore: _minutes((json['bufferBefore'] as num?) ?? 0),
        bufferAfter: _minutes((json['bufferAfter'] as num?) ?? 0),
        minNotice: json.containsKey('minNotice') ? _minutes(json['minNotice']! as num) : null,
        maxAdvanceDays: (json['maxAdvanceDays'] as num?)?.toInt(),
        now: now,
        maxPerDay: (json['maxPerDay'] as num?)?.toInt(),
        busy: busyList,
      ),
      from: from,
      to: to,
    ),
    problems,
  );
}
