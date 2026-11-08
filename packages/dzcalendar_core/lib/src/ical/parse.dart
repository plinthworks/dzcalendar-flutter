import '../event/problem.dart';
import '../event/types.dart';
import '../time/civil.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/day_info.dart';
import '../zone/zoned.dart';
import 'lines.dart';
import 'zones.dart';

/// What a file says of itself.
final class ICalCalendar {
  const ICalCalendar({this.name, this.zone, this.prodId});

  /// `X-WR-CALNAME`.
  final String? name;

  /// `X-WR-TIMEZONE`, as an IANA zone.
  final String? zone;
  final String? prodId;
}

final class ParsedICal {
  const ParsedICal(this.events, this.problems, this.calendar);
  final List<EventInput> events;
  final List<Problem> problems;
  final ICalCalendar calendar;
}

final class _Component {
  _Component(this.name);
  final String name;
  final List<ContentLine> props = [];
  final List<_Component> children = [];

  ContentLine? prop(String name) => props.where((p) => p.name == name).firstOrNull;
}

Problem _issue(ProblemCode code, Severity severity, String path, [String? detail]) =>
    Problem(code, severity, path, detail);

/// Components that only stand directly in a VCALENDAR: one opening inside
/// another closes it.
const _top = {'VEVENT', 'VTODO', 'VJOURNAL', 'VFREEBUSY', 'VTIMEZONE', 'VCALENDAR'};

List<_Component> _components(String text, List<Problem> problems) {
  final root = _Component('');
  final stack = [root];
  for (final (:text, :line) in unfold(text)) {
    final cl = parseLine(text, line);
    if (cl == null) {
      problems.add(_issue(ProblemCode.icalSyntax, Severity.error, 'line $line', text));
      continue;
    }
    if (cl.name == 'BEGIN') {
      final c = _Component(cl.value.trim().toUpperCase());
      // A missing END: the next event opening closes the open one rather than nesting in it.
      if (_top.contains(c.name)) {
        while (stack.length > 1 && stack.last.name != 'VCALENDAR' && c.name != 'VCALENDAR') {
          problems.add(_issue(ProblemCode.icalSyntax, Severity.error, 'line $line', text));
          stack.removeLast();
        }
      }
      stack.last.children.add(c);
      stack.add(c);
    } else if (cl.name == 'END') {
      final name = cl.value.trim().toUpperCase();
      final at = stack.map((c) => c.name).toList().lastIndexOf(name);
      if (at <= 0) {
        problems.add(_issue(ProblemCode.icalSyntax, Severity.error, 'line $line', text));
      } else {
        if (at != stack.length - 1) problems.add(_issue(ProblemCode.icalSyntax, Severity.error, 'line $line', text));
        stack.length = at;
      }
    } else {
      stack.last.props.add(cl);
    }
  }
  if (stack.length > 1) {
    problems.add(_issue(ProblemCode.icalSyntax, Severity.error, 'end', 'BEGIN:${stack.last.name} never ends'));
  }
  return root.children;
}

final _date = RegExp(r'^(\d{4})(\d{2})(\d{2})$');
final _dateTime = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$', caseSensitive: false);
final _year = RegExp(r'^(\d{4})');
final _offsetZone = RegExp(r'^[+-]\d');

PlainDate? _plainDate(int y, int m, int d) =>
    m >= 1 && m <= 12 && d >= 1 && d <= monthLength(y, m) ? PlainDate(y, m, d) : null;

/// A DATE-TIME's wall time, a leap second read as :59; null when malformed.
PlainDateTime? _wallOf(String v) {
  final t = _dateTime.firstMatch(v.trim());
  if (t == null) return null;
  final date = _plainDate(int.parse(t[1]!), int.parse(t[2]!), int.parse(t[3]!));
  final h = int.parse(t[4]!);
  final m = int.parse(t[5]!);
  final s = int.parse(t[6]!);
  if (date == null || h > 23 || m > 59) return null;
  return PlainDateTime(date, PlainTime(h, m, s > 59 ? 59 : s));
}

/// A date or date-time value as the core reads it: `date` (an all-day
/// start), `zoned`, or `floating` (a wall time in no zone).
typedef _Moment = ({String kind, String text});

/// A zone a TZID names: an IANA zone, a VTIMEZONE's own rules (no IANA zone
/// keeps them), or nothing known.
sealed class _Zone {}

final class _Iana extends _Zone {
  _Iana(this.id);
  final String id;
}

final class _Own extends _Zone {
  _Own(this.observances);
  final List<Observance> observances;
}

/// Parses an iCalendar text into event inputs. Never throws on data: what is
/// wrong is in `problems`, and an event whose start cannot be read is left
/// out. Only VEVENTs are read. [defaultZone]: where floating times (no TZID,
/// no `Z`) are read when the file names no zone (`X-WR-TIMEZONE`).
ParsedICal parseICal(String text, {String? defaultZone}) {
  final problems = <Problem>[];
  final events = <EventInput>[];
  final cals = _components(text, problems);
  // Several VCALENDARs in one text (concatenated feeds) are read as one; the first names it.
  final all = cals.where((c) => c.name == 'VCALENDAR').toList();
  final _Component cal;
  if (all.isEmpty) {
    cal = _Component('VCALENDAR')..children.addAll(cals);
  } else if (all.length == 1) {
    cal = all.first;
  } else {
    cal = _Component('VCALENDAR');
    for (final c in all) {
      cal.props.addAll(c.props);
      cal.children.addAll(c.children);
    }
  }
  final wrZone = cal.prop('X-WR-TIMEZONE')?.value.trim();
  final calZone = wrZone == null || wrZone.isEmpty ? null : (isValidZone(wrZone) ? wrZone : ianaIn(wrZone));
  // An empty default is none; one that is no zone makes the floating times unreadable (as on the web).
  final floatingZone = calZone ?? (defaultZone == null || defaultZone.isEmpty ? null : defaultZone);
  final name = cal.prop('X-WR-CALNAME');
  final calendar = ICalCalendar(
    name: name == null ? null : unescapeText(name.value),
    zone: calZone,
    prodId: cal.prop('PRODID')?.value,
  );

  final vevents = cal.children.where((c) => c.name == 'VEVENT').toList();
  for (final kind in const ['VTODO', 'VJOURNAL']) {
    if (cal.children.any((c) => c.name == kind)) {
      problems.add(_issue(ProblemCode.icalUnsupported, Severity.warning, kind, 'skipped'));
    }
  }
  final vtimezones = {
    for (final c in cal.children.where((c) => c.name == 'VTIMEZONE')) c.prop('TZID')?.value.trim() ?? '': c,
  };
  // The years the file's events start in: what a VTIMEZONE is compared over.
  final years = {
    for (final v in vevents)
      if (_year.firstMatch(v.prop('DTSTART')?.value ?? '') case final m?) int.parse(m[1]!),
  }.toList()..sort();

  final unsupported = <String>{};
  void once(String what, String path) {
    if (unsupported.add(what)) problems.add(_issue(ProblemCode.icalUnsupported, Severity.warning, path, what));
  }

  final zones = <String, _Zone?>{};
  _Zone? zoneFor(String tzid, String path) {
    if (zones.containsKey(tzid)) return zones[tzid];
    final iana = ianaIn(tzid);
    _Zone? zone = iana == null ? null : _Iana(iana);
    final vtz = zone != null ? null : vtimezones[tzid];
    if (vtz != null) {
      final obs = _observances(vtz);
      // Old events can fall under rules the VTIMEZONE no longer states (US 2005 vs its 2007+ rules):
      // all the years first, then the latest alone.
      final latest = years.isNotEmpty ? [years.last] : [2026];
      final found =
          matchObservances(obs, years.isNotEmpty ? years.sublist(years.length > 12 ? years.length - 12 : 0) : latest) ??
          (years.length > 1 ? matchObservances(obs, latest) : null);
      if (found != null) {
        problems.add(_issue(ProblemCode.zoneGuessed, Severity.warning, path, '$tzid → $found'));
        zone = _Iana(found);
      } else if (obs.isNotEmpty) {
        // Each wall time gets the offset the VTIMEZONE's rules give it, as a fixed-offset moment:
        // right for every start, though a series repeats at that one offset.
        zone = _Own(obs);
        problems.add(_issue(ProblemCode.zoneFixedOffset, Severity.warning, path, tzid));
      }
    }
    if (zone == null) problems.add(_issue(ProblemCode.unknownZone, Severity.warning, path, tzid));
    zones[tzid] = zone;
    return zone;
  }

  // UTC times stay UTC's on a recurring event: RFC 5545 repeats them in UTC.
  var keepUtc = false;

  /// One value of a date or date-time property, written as the core reads it.
  _Moment? moment(String value, ContentLine p, String path) {
    final v = value.trim();
    final d = _date.firstMatch(v);
    if (d != null) {
      final date = _plainDate(int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!));
      if (date != null) return (kind: 'date', text: '$date');
    } else if (_dateTime.firstMatch(v) case final t?) {
      final wall = _wallOf(v);
      if (wall != null) {
        if (t[7]!.isNotEmpty) {
          final at = Instant.fromEpochMilliseconds(wall.wallMs);
          // A file that names its zone means its UTC times to be read there;
          // otherwise they are UTC's, as RFC 5545 repeats them.
          final inZone = floatingZone != null && !keepUtc;
          if (!inZone) return (kind: 'zoned', text: '$wall[UTC]');
          if (isValidZone(floatingZone)) return (kind: 'zoned', text: '${ZonedDateTime(at, floatingZone)}');
          // A default zone that is none: the web cannot place it either (ical-syntax below).
        } else {
          final tzid = p.param('TZID');
          final _Zone? zone = tzid != null ? zoneFor(tzid, path) : (floatingZone == null ? null : _Iana(floatingZone));
          switch (zone) {
            case _Own(:final observances):
              final off = fixedZone(offsetIn(observances, wall));
              return (kind: 'zoned', text: '$wall$off[$off]');
            // A fixed-offset zone (`+05:30`) is written with its offset, as the own-rules reading is.
            case _Iana(:final id):
              return (kind: 'zoned', text: _offsetZone.hasMatch(id) ? '$wall$id[$id]' : '$wall[$id]');
            case null:
              return (kind: 'floating', text: '$wall');
          }
        }
      }
    }
    problems.add(_issue(ProblemCode.icalSyntax, Severity.error, path, v));
    return null;
  }

  List<String> list(_Component c, String name, String path) {
    final out = <String>[];
    final props = c.props.where((p) => p.name == name).toList();
    for (var k = 0; k < props.length; k++) {
      final p = props[k];
      final period = p.param('VALUE')?.toUpperCase() == 'PERIOD';
      if (period) once('RDATE;VALUE=PERIOD', '$path.$name');
      for (final raw in p.value.split(',')) {
        final m = moment(period ? raw.split('/').first : raw, p, '$path.$name[$k]');
        if (m != null) out.add(m.text);
      }
    }
    return out;
  }

  for (var i = 0; i < vevents.length; i++) {
    final v = vevents[i];
    final path = 'VEVENT[$i]';
    final dtstart = v.prop('DTSTART');
    keepUtc = v.props.any((p) => p.name == 'RRULE' || p.name == 'RDATE');
    final start = dtstart == null ? null : moment(dtstart.value, dtstart, '$path.DTSTART');
    if (start == null) {
      if (dtstart == null) problems.add(_issue(ProblemCode.icalSyntax, Severity.error, '$path.DTSTART', 'missing'));
      continue;
    }
    // An empty UID is none (the event gets an id of its own), as on the web.
    final uidText = v.prop('UID')?.value.trim();
    final uid = uidText == null || uidText.isEmpty ? null : uidText;
    final rid = v.prop('RECURRENCE-ID');
    final recurrence = rid == null ? null : moment(rid.value, rid, '$path.RECURRENCE-ID');
    if (rid != null && rid.param('RANGE')?.toUpperCase() == 'THISANDFUTURE') {
      once('RECURRENCE-ID;RANGE=THISANDFUTURE', '$path.RECURRENCE-ID');
    }
    final override = uid != null && recurrence != null;

    final dtend = v.prop('DTEND');
    final end = dtend == null ? null : moment(dtend.value, dtend, '$path.DTEND');
    final duration = v.prop('DURATION')?.value.trim();

    final summary = v.prop('SUMMARY');
    final rrules = [for (final p in v.props.where((p) => p.name == 'RRULE')) p.value.trim()];
    if (v.prop('EXRULE') != null) once('EXRULE', '$path.EXRULE');
    final exdate = list(v, 'EXDATE', path);
    final rdate = list(v, 'RDATE', path);

    final status = v.prop('STATUS')?.value.trim().toLowerCase();
    final url = v.prop('URL');

    final props = <String, Object?>{};
    final description = v.prop('DESCRIPTION');
    if (description != null) props['description'] = unescapeText(description.value);
    final location = v.prop('LOCATION');
    if (location != null) props['location'] = unescapeText(location.value);
    final categories = [for (final p in v.props.where((p) => p.name == 'CATEGORIES')) ...splitText(p.value)];
    if (categories.isNotEmpty) props['categories'] = categories;
    final organizer = v.prop('ORGANIZER');
    if (organizer != null) {
      final cn = organizer.param('CN');
      final email = organizer.value.replaceFirst(RegExp('^mailto:', caseSensitive: false), '').trim();
      props['organizer'] = {if (cn != null && cn.isNotEmpty) 'name': cn, if (email.isNotEmpty) 'email': email};
    }

    events.add(
      EventInput(
        id: override ? '$uid@${rid!.value.trim()}' : uid,
        seriesId: override ? uid : null,
        recurrenceId: override ? recurrence.text : null,
        start: start.text,
        allDay: start.kind == 'date' ? true : null,
        end: end?.text,
        // RFC 5545 §3.6.1: no end and no duration is one day for a date, an instant for a time.
        duration: end != null
            ? null
            : (duration != null && duration.isNotEmpty ? duration : (start.kind == 'date' ? 'P1D' : 'PT0S')),
        title: summary == null ? null : unescapeText(summary.value),
        rrule: rrules.isEmpty ? null : (rrules.length == 1 ? rrules.first : rrules),
        exdate: exdate.isEmpty ? null : exdate,
        rdate: rdate.isEmpty ? null : rdate,
        status: status == null ? null : EventStatus.fromCode(status),
        busy: v.prop('TRANSP')?.value.trim().toUpperCase() == 'TRANSPARENT' ? false : null,
        url: url?.value.trim(),
        extendedProps: props.isEmpty ? null : props,
      ),
    );
  }
  return ParsedICal(events, problems, calendar);
}

List<Observance> _observances(_Component vtz) {
  final out = <Observance>[];
  for (final c in vtz.children) {
    if (c.name != 'STANDARD' && c.name != 'DAYLIGHT') continue;
    final from = offsetSeconds(c.prop('TZOFFSETFROM')?.value ?? '');
    final to = offsetSeconds(c.prop('TZOFFSETTO')?.value ?? '');
    final start = _wallOf(c.prop('DTSTART')?.value ?? '');
    if (from == null || to == null || start == null) continue;
    final rrule = c.prop('RRULE')?.value.trim();
    final rdates = [
      for (final p in c.props.where((p) => p.name == 'RDATE'))
        for (final x in p.value.split(','))
          if (_wallOf(x) case final w?) w,
    ];
    out.add(
      Observance(
        start: start,
        from: from,
        to: to,
        rdates: rdates,
        standard: c.name == 'STANDARD',
        rrule: rrule == null || rrule.isEmpty ? null : rrule,
      ),
    );
  }
  return out;
}
