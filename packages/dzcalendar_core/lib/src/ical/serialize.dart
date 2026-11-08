import '../event/parse_temporal.dart';
import '../event/problem.dart';
import '../event/types.dart';
import '../time/civil.dart';
import '../time/duration.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'lines.dart';
import 'zones.dart';

/// What a start, end or date of an input is.
sealed class _Value {}

final class _Date extends _Value {
  _Date(this.v);
  final PlainDate v;
}

final class _Zoned extends _Value {
  _Zoned(this.v, this.zone);
  final PlainDateTime v;
  final String zone;
}

final class _Instant extends _Value {
  _Instant(this.v);
  final Instant v;
}

final class _Floating extends _Value {
  _Floating(this.v);
  final PlainDateTime v;
}

final _offsetBeforeZone = RegExp(r'[+-]\d{2}:?\d{2}(:?\d{2})?\[|Z\[', caseSensitive: false);
final _instantEnd = RegExp(r'(Z|[+-]\d{2}(:?\d{2})?)$', caseSensitive: false);

/// A moment of an input, whether one of the time types or a string; null
/// when it cannot be read (the event is then written without it).
_Value? _valueOf(Object? x) {
  switch (x) {
    case ZonedDateTime():
      return x.zone == 'UTC' ? _Instant(x.instant) : _Zoned(x.plainDateTime, x.zone);
    case PlainDate():
      return _Date(x);
    case Instant():
      return _Instant(x);
    case PlainDateTime():
      return _Floating(x);
    case null:
      return null;
  }
  final s = '$x'.trim();
  if (s.contains('[')) {
    // The wall time as written, even one a clock change skips: the reader decides, as we did.
    // An offset the zone does not have there is unreadable (Temporal's `offset: 'reject'`): left out.
    final r = parseTemporal(s, 'moment', start: true);
    if (r.problems.any((p) => p.isError || p.code == ProblemCode.offsetMismatch)) return null;
    final z = switch (r.parsed) {
      ParsedZoned(:final value) => value,
      _ => null,
    };
    if (z == null) return null;
    final wall = _offsetBeforeZone.hasMatch(s)
        ? z.plainDateTime
        : PlainDateTime.tryParse(s.substring(0, s.indexOf('[')));
    if (wall == null) return null;
    return z.zone.toUpperCase() == 'UTC' ? _Instant(z.instant) : _Zoned(wall, z.zone);
  }
  if (_instantEnd.hasMatch(s) && s.contains('T')) {
    final i = Instant.tryParse(s);
    return i == null ? null : _Instant(i);
  }
  if (s.contains('T')) {
    final w = PlainDateTime.tryParse(s);
    return w == null ? null : _Floating(w);
  }
  final d = PlainDate.tryParse(s);
  return d == null ? null : _Date(d);
}

String _dateText(PlainDate d) => '${d.year.toString().padLeft(4, '0')}${pad2(d.month)}${pad2(d.day)}';
String _wallText(PlainDateTime p) =>
    '${_dateText(p.date)}T${pad2(p.time.hour)}${pad2(p.time.minute)}${pad2(p.time.second)}';
String _utcText(Instant i) => '${_wallText(i.wallAt(0))}Z';

/// `NAME;params:value` for a date or date-time value.
String _dateLine(String name, _Value x) => switch (x) {
  _Date(:final v) => '$name;VALUE=DATE:${_dateText(v)}',
  _Zoned(:final v, :final zone) => '$name;TZID=${paramValue(zone)}:${_wallText(v)}',
  _Instant(:final v) => '$name:${_utcText(v)}',
  _Floating(:final v) => '$name:${_wallText(v)}',
};

final _bounded = RegExp('UNTIL|COUNT', caseSensitive: false);
final _rrulePrefix = RegExp('^RRULE:', caseSensitive: false);

/// Writes inputs as an iCalendar text (CRLF, lines folded at 75 octets).
/// Series keep their rules, EXDATEs and RDATEs; an override (`seriesId` +
/// `recurrenceId`) is written under its series' UID with a RECURRENCE-ID.
///
/// [stamp]: the `DTSTAMP` of every event (default: now). [vtimezone]: a
/// VTIMEZONE for each zone used (RFC 5545 asks for one; Outlook needs it).
String serializeICal(
  List<EventInput> inputs, {
  String prodId = '-//DzCalendar//EN',
  String? name,
  Instant? stamp,
  bool vtimezone = true,
}) {
  final lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:$prodId', 'CALSCALE:GREGORIAN'];
  if (name != null) lines.add('X-WR-CALNAME:${escapeText(name)}');
  final stampText = _utcText(stamp ?? Instant.fromEpochMilliseconds(DateTime.now().millisecondsSinceEpoch));
  final zones = <String, ({int from, int to})>{};
  final body = <String>[];

  for (final e in inputs) {
    final start = _valueOf(e.start);
    if (start == null) continue;
    final end = _valueOf(e.end);
    final out = ['BEGIN:VEVENT'];
    final uid = e.seriesId != null && e.recurrenceId != null ? e.seriesId : e.id;
    if (uid != null) out.add('UID:$uid');
    out.add('DTSTAMP:$stampText');
    // An all-day input given with times is written as dates.
    _Value asDate(_Value x) => e.allDay != true
        ? x
        : switch (x) {
            _Date() => x,
            _Instant(:final v) => _Date(v.wallAt(0).date),
            _Zoned(:final v) || _Floating(:final v) => _Date(v.date),
          };
    final used = <_Value>[];
    void write(String name, _Value? x) {
      if (x == null) return;
      final y = asDate(x);
      used.add(y);
      out.add(_dateLine(name, y));
    }

    write('DTSTART', start);
    if (end != null) {
      write('DTEND', end);
    } else if (e.duration != null) {
      final d = IsoDuration.tryFrom(e.duration);
      if (d != null) out.add('DURATION:$d');
    }
    if (e.recurrenceId != null) write('RECURRENCE-ID', _valueOf(e.recurrenceId));
    final rrule = e.rrule;
    final rules = switch (rrule) {
      String() => [rrule],
      List<Object?>() => [for (final r in rrule) '$r'],
      _ => const <String>[],
    };
    for (final r in rules) {
      out.add('RRULE:${r.replaceFirst(_rrulePrefix, '')}');
    }
    for (final x in e.exdate ?? const <Object?>[]) {
      write('EXDATE', _valueOf(x));
    }
    for (final x in e.rdate ?? const <Object?>[]) {
      write('RDATE', _valueOf(x));
    }
    final title = e.title;
    if (title != null) out.add('SUMMARY:${escapeText(title)}');
    final status = e.status;
    if (status != null) out.add('STATUS:${status.name.toUpperCase()}');
    // A background (closed hours, a maintenance window) takes no one's time where it is imported.
    if (e.busy == false || (e.display == EventDisplay.background && e.busy != true)) out.add('TRANSP:TRANSPARENT');
    final url = e.url;
    if (url != null) out.add('URL:$url');
    final p = e.extendedProps ?? const <String, Object?>{};
    if (p['description'] case final String d) out.add('DESCRIPTION:${escapeText(d)}');
    if (p['location'] case final String l) out.add('LOCATION:${escapeText(l)}');
    if (p['categories'] case final List<Object?> c when c.isNotEmpty) {
      out.add('CATEGORIES:${c.map((x) => escapeText('$x')).join(',')}');
    }
    if (p['organizer'] case final Map<Object?, Object?> org) {
      final n = org['name'];
      final m = org['email'];
      final hasName = n is String && n.isNotEmpty;
      if (hasName || (m is String && m.isNotEmpty)) {
        out.add('ORGANIZER${hasName ? ';CN=${paramValue(n)}' : ''}:mailto:${m is String ? m : ''}');
      }
    }
    out.add('END:VEVENT');
    body.addAll(out);

    // An open series goes on: its zone's rules are written a few years ahead.
    final ahead = rrule != null && !_bounded.hasMatch(rules.join(',')) ? 5 : 1;
    for (final x in used) {
      if (x is! _Zoned) continue;
      final y = x.v.date.year;
      final span = zones[x.zone] ?? (from: y, to: y);
      zones[x.zone] = (from: span.from < y - 1 ? span.from : y - 1, to: span.to > y + ahead ? span.to : y + ahead);
    }
  }

  if (vtimezone) {
    for (final MapEntry(key: zone, value: span) in zones.entries) {
      lines.addAll(_vtimezone(zone, span.from, span.to));
    }
  }
  lines
    ..addAll(body)
    ..add('END:VCALENDAR');
  return lines.map(fold).join();
}

const _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/// A change of offset: the wall time just before it (as VTIMEZONE's DTSTART
/// writes it), the offsets before and after (seconds).
typedef _Change = ({PlainDateTime wall, int from, int to});

int _sec(ZoneRules rules, int ms) => (rules.offsetAt(ms) / 1000).round();

int _yearStart(String zone, int year) => PlainDate(year, 1, 1).startOfDayIn(zone).epochMilliseconds;

/// The zone's changes of offset in `[fromYear, toYear]`.
List<_Change> _changesIn(String zone, int fromYear, int toYear) {
  final rules = rulesFor(zone);
  final out = <_Change>[];
  final end = _yearStart(zone, toYear + 1);
  var at = _yearStart(zone, fromYear);
  for (var n = 0; n < 400; n++) {
    final next = rules.nextTransition(at);
    if (next == null || next >= end) break;
    at = next;
    final from = _sec(rules, at - 1);
    out.add((wall: Instant.fromEpochMilliseconds(at).wallAt(from * 1000), from: from, to: _sec(rules, at)));
  }
  return out;
}

/// `FREQ=YEARLY;BYMONTH=3;BYDAY=2SU` (or `-1SU` for the last) for the weekday a change fell on.
String _ruleOf(PlainDateTime w) {
  final d = w.date;
  final n = d.day + 7 > d.daysInMonth ? -1 : (d.day / 7).ceil();
  return 'FREQ=YEARLY;BYMONTH=${d.month};BYDAY=$n${_days[d.dayOfWeek - 1]}';
}

/// A VTIMEZONE from the zone's real transitions over the years given: one
/// block per change, and when the last year changes twice by weekday rules
/// that the zone keeps for the next two years too, those two as RRULEs — so
/// a reader that only has this VTIMEZONE stays right after the years written.
List<String> _vtimezone(String zone, int fromYear, int toYear) {
  final out = ['BEGIN:VTIMEZONE', 'TZID:$zone'];
  void block(_Change c, [String? rrule]) {
    final kind = c.to > c.from ? 'DAYLIGHT' : 'STANDARD';
    out.addAll([
      'BEGIN:$kind',
      'DTSTART:${_wallText(c.wall)}',
      if (rrule != null) 'RRULE:$rrule',
      'TZOFFSETFROM:${formatOffset(c.from)}',
      'TZOFFSETTO:${formatOffset(c.to)}',
      'END:$kind',
    ]);
  }

  final rules = rulesFor(zone);
  final first = _yearStart(zone, fromYear);
  final firstOffset = _sec(rules, first);
  block((wall: Instant.fromEpochMilliseconds(first).wallAt(rules.offsetAt(first)), from: firstOffset, to: firstOffset));
  final all = _changesIn(zone, fromYear, toYear);
  final last = [
    for (final c in all)
      if (c.wall.date.year == toYear) c,
  ];
  // A year's changes by rule, time and offsets: equal for the next two years means the rules hold.
  String sig(List<_Change> cs) => cs.map((c) => '${_ruleOf(c.wall)} ${c.wall.time} ${c.from} ${c.to}').join(',');
  final ruled = last.length == 2 && [1, 2].every((k) => sig(_changesIn(zone, toYear + k, toYear + k)) == sig(last));
  for (final c in ruled ? all.sublist(0, all.length - 2) : all) {
    block(c);
  }
  if (ruled) {
    for (final c in last) {
      block(c, _ruleOf(c.wall));
    }
  }
  out.add('END:VTIMEZONE');
  return out;
}
