import '../time/civil.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/zoned.dart';

/// RFC 5545 recurrence, as data. Daily and slower rules keep their wall time
/// across clock changes; hourly and finer step in elapsed time.
enum Frequency { yearly, monthly, weekly, daily, hourly, minutely, secondly }

/// A weekday (ISO: 1 Monday … 7 Sunday), optionally the n-th of its period
/// (2 the second, -1 the last).
final class ByDay {
  const ByDay(this.weekday, [this.n]);
  final int weekday;
  final int? n;

  @override
  bool operator ==(Object other) => other is ByDay && other.weekday == weekday && other.n == n;
  @override
  int get hashCode => Object.hash(weekday, n);
}

/// A recurrence rule, RFC 5545 §3.3.10. UNTIL keeps the kind of value it was
/// given: a date ([untilDate], all-day series) or an instant ([untilInstant]).
final class RRule {
  const RRule({
    required this.freq,
    this.interval = 1,
    this.count,
    this.untilInstant,
    this.untilDate,
    this.bySecond,
    this.byMinute,
    this.byHour,
    this.byDay,
    this.byMonthDay,
    this.byYearDay,
    this.byWeekNo,
    this.byMonth,
    this.bySetPos,
    this.wkst = 1,
  });

  final Frequency freq;
  final int interval;
  final int? count;
  final Instant? untilInstant;
  final PlainDate? untilDate;
  final List<int>? bySecond;
  final List<int>? byMinute;
  final List<int>? byHour;
  final List<ByDay>? byDay;
  final List<int>? byMonthDay;
  final List<int>? byYearDay;
  final List<int>? byWeekNo;
  final List<int>? byMonth;
  final List<int>? bySetPos;

  /// ISO weekday the week starts on.
  final int wkst;

  bool get hasUntil => untilInstant != null || untilDate != null;
  bool get subDaily => freq == Frequency.hourly || freq == Frequency.minutely || freq == Frequency.secondly;

  /// The same rule with its end changed: [count] or an until, or neither.
  RRule withEnd({int? count, Instant? untilInstant, PlainDate? untilDate}) => RRule(
    freq: freq,
    interval: interval,
    count: count,
    untilInstant: untilInstant,
    untilDate: untilDate,
    bySecond: bySecond,
    byMinute: byMinute,
    byHour: byHour,
    byDay: byDay,
    byMonthDay: byMonthDay,
    byYearDay: byYearDay,
    byWeekNo: byWeekNo,
    byMonth: byMonth,
    bySetPos: bySetPos,
    wkst: wkst,
  );

  /// The rule as RFC 5545 text, parts in a fixed order: equal rules print equal.
  @override
  String toString() => serializeRRule(this);

  @override
  bool operator ==(Object other) => other is RRule && serializeRRule(other) == serializeRRule(this);
  @override
  int get hashCode => serializeRRule(this).hashCode;
}

/// An EXDATE: an instant excludes that moment; a date excludes every
/// occurrence on that date in the series' zone.
sealed class ExDate {
  const ExDate();
  const factory ExDate.instant(Instant at) = ExInstant;
  const factory ExDate.date(PlainDate date) = ExDay;
}

final class ExInstant extends ExDate {
  const ExInstant(this.at);
  final Instant at;
  @override
  bool operator ==(Object other) => other is ExInstant && other.at == at;
  @override
  int get hashCode => at.hashCode;
  @override
  String toString() => '$at';
}

final class ExDay extends ExDate {
  const ExDay(this.date);
  final PlainDate date;
  @override
  bool operator ==(Object other) => other is ExDay && other.date == date;
  @override
  int get hashCode => date.hashCode;
  @override
  String toString() => '$date';
}

/// An RDATE: a moment for a timed series, a date for an all-day one.
sealed class RDate {
  const RDate();
  const factory RDate.zoned(ZonedDateTime at) = RZoned;
  const factory RDate.date(PlainDate date) = RDay;
}

final class RZoned extends RDate {
  const RZoned(this.at);
  final ZonedDateTime at;
  @override
  bool operator ==(Object other) => other is RZoned && other.at == at;
  @override
  int get hashCode => at.hashCode;
  @override
  String toString() => '$at';
}

final class RDay extends RDate {
  const RDay(this.date);
  final PlainDate date;
  @override
  bool operator ==(Object other) => other is RDay && other.date == date;
  @override
  int get hashCode => date.hashCode;
  @override
  String toString() => '$date';
}

/// Rules with their exceptions and additions (RFC 5545 EXDATE, RDATE).
final class RRuleSet {
  const RRuleSet(this.rules, {this.exdates = const [], this.rdates = const []});
  final List<RRule> rules;
  final List<ExDate> exdates;
  final List<RDate> rdates;
}

/// Why a rule could not be read or expanded: `invalid-rrule`, `too-many-occurrences`.
final class RRuleProblem {
  const RRuleProblem(this.code, this.detail);
  final String code;
  final String detail;
  @override
  String toString() => '$code: $detail';
}

const _days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
final _int = RegExp(r'^[+-]?\d{1,15}$');
final _byDayEntry = RegExp(r'^([+-]?\d{1,2})?(MO|TU|WE|TH|FR|SA|SU)$');
final _until = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$');

List<int>? _ints(String v, int lo, int hi, {required bool nonZero}) {
  final out = <int>[];
  for (final part in v.split(',')) {
    if (!_int.hasMatch(part)) return null;
    final n = int.parse(part);
    if (n.abs() < lo || n.abs() > hi || (nonZero && n == 0) || (!nonZero && n < 0)) return null;
    out.add(n);
  }
  return out;
}

/// The rule, or why it cannot be read.
typedef ParsedRRule = ({RRule? rule, RRuleProblem? problem});

ParsedRRule _bad(String detail) => (rule: null, problem: RRuleProblem('invalid-rrule', detail));

/// Reads `FREQ=WEEKLY;BYDAY=MO,WE;COUNT=10` (with or without `RRULE:`).
/// Never throws: an unreadable rule is a problem naming the part at fault.
ParsedRRule parseRRule(String text) {
  var body = text.trim();
  if (body.toUpperCase().startsWith('RRULE:')) body = body.substring(6);
  if (body.isEmpty) return _bad('empty rule');
  final fields = <String, String>{};
  for (final part in body.split(';')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    if (eq <= 0) return _bad('not NAME=VALUE: $part');
    final name = part.substring(0, eq).toUpperCase();
    if (fields.containsKey(name)) return _bad('$name given twice');
    fields[name] = part.substring(eq + 1).toUpperCase();
  }
  final freqText = fields['FREQ'];
  final freq = Frequency.values.where((f) => f.name.toUpperCase() == freqText).firstOrNull;
  if (freq == null) return _bad('FREQ must be one of ${Frequency.values.map((f) => f.name.toUpperCase()).join(', ')}');

  var interval = 1;
  int? count;
  Instant? untilInstant;
  PlainDate? untilDate;
  var wkst = 1;
  List<int>? bySecond, byMinute, byHour, byMonthDay, byYearDay, byWeekNo, byMonth, bySetPos;
  List<ByDay>? byDay;

  for (final MapEntry(key: name, value: v) in fields.entries) {
    switch (name) {
      case 'FREQ':
        break;
      case 'INTERVAL' || 'COUNT':
        final n = _int.hasMatch(v) ? int.parse(v) : 0;
        if (n < 1) return _bad('$name must be a positive integer: $v');
        if (name == 'INTERVAL') {
          interval = n;
        } else {
          count = n;
        }
      case 'UNTIL':
        final m = _until.firstMatch(v);
        final date = m == null ? null : PlainDate.tryParse('${m[1]}-${m[2]}-${m[3]}');
        final time = m?[4] == null ? null : PlainTime.tryParse('${m![4]}:${m[5]}:${m[6]}');
        if (date == null || (m![4] != null && time == null)) return _bad('UNTIL is not a date or UTC date-time: $v');
        // Local forms are read as UTC.
        if (time == null) {
          untilDate = date;
        } else {
          untilInstant = Instant.fromEpochMilliseconds(date.epochDay * msPerDay + time.msOfDay);
        }
      case 'WKST':
        final i = _days.indexOf(v);
        if (i < 0) return _bad('WKST is not a weekday: $v');
        wkst = i + 1;
      case 'BYDAY':
        final days = <ByDay>[];
        for (final d in v.split(',')) {
          final m = _byDayEntry.firstMatch(d);
          if (m == null) return _bad('BYDAY entry: $d');
          final weekday = _days.indexOf(m[2]!) + 1;
          final ordinal = m[1];
          if (ordinal != null) {
            final n = int.parse(ordinal);
            if (n == 0 || n.abs() > 53) return _bad('BYDAY ordinal: $d');
            days.add(ByDay(weekday, n));
          } else {
            days.add(ByDay(weekday));
          }
        }
        byDay = days;
      case 'BYSECOND' || 'BYMINUTE' || 'BYHOUR':
        final list = _ints(v, 0, name == 'BYHOUR' ? 23 : (name == 'BYMINUTE' ? 59 : 60), nonZero: false);
        if (list == null) return _bad('$name: $v');
        if (name == 'BYSECOND') {
          bySecond = list;
        } else if (name == 'BYMINUTE') {
          byMinute = list;
        } else {
          byHour = list;
        }
      case 'BYMONTHDAY' || 'BYYEARDAY' || 'BYWEEKNO' || 'BYSETPOS':
        final max = switch (name) {
          'BYMONTHDAY' => 31,
          'BYWEEKNO' => 53,
          _ => 366,
        };
        final list = _ints(v, 1, max, nonZero: true);
        if (list == null) return _bad('$name: $v');
        switch (name) {
          case 'BYMONTHDAY':
            byMonthDay = list;
          case 'BYYEARDAY':
            byYearDay = list;
          case 'BYWEEKNO':
            byWeekNo = list;
          default:
            bySetPos = list;
        }
      case 'BYMONTH':
        final list = _ints(v, 1, 12, nonZero: true);
        if (list == null || list.any((n) => n < 0)) return _bad('BYMONTH: $v');
        byMonth = list;
      default:
        // RSCALE, SKIP and other extensions are not read (ARCHITECTURE K.7): say so.
        return _bad('unsupported part: $name');
    }
  }
  final hasOrdinal = byDay?.any((d) => d.n != null) ?? false;
  if (count != null && (untilDate != null || untilInstant != null)) return _bad('COUNT and UNTIL together');
  if (byWeekNo != null && freq != Frequency.yearly) return _bad('BYWEEKNO only with FREQ=YEARLY');
  if (byYearDay != null && (freq == Frequency.daily || freq == Frequency.weekly || freq == Frequency.monthly)) {
    return _bad('BYYEARDAY not with FREQ=${freq.name.toUpperCase()}');
  }
  if (byMonthDay != null && freq == Frequency.weekly) return _bad('BYMONTHDAY not with FREQ=WEEKLY');
  if (hasOrdinal && freq != Frequency.monthly && freq != Frequency.yearly) {
    return _bad('BYDAY ordinals only with MONTHLY or YEARLY');
  }
  if (hasOrdinal && freq == Frequency.yearly && byWeekNo != null) return _bad('BYDAY ordinals not with BYWEEKNO');
  return (
    rule: RRule(
      freq: freq,
      interval: interval,
      count: count,
      untilInstant: untilInstant,
      untilDate: untilDate,
      bySecond: bySecond,
      byMinute: byMinute,
      byHour: byHour,
      byDay: byDay,
      byMonthDay: byMonthDay,
      byYearDay: byYearDay,
      byWeekNo: byWeekNo,
      byMonth: byMonth,
      bySetPos: bySetPos,
      wkst: wkst,
    ),
    problem: null,
  );
}

/// The rule back as text, parts in a fixed order, so equal rules print equal.
String serializeRRule(RRule r) {
  final out = ['FREQ=${r.freq.name.toUpperCase()}'];
  if (r.interval != 1) out.add('INTERVAL=${r.interval}');
  if (r.count != null) out.add('COUNT=${r.count}');
  final ud = r.untilDate;
  final ui = r.untilInstant;
  if (ud != null) out.add('UNTIL=${'$ud'.replaceAll('-', '')}');
  if (ui != null) {
    // To the second, as Temporal's toString({ smallestUnit: 'second' }) truncates.
    final s = Instant.fromEpochMilliseconds(ui.epochMilliseconds - ui.epochMilliseconds % msPerSecond);
    out.add('UNTIL=${'$s'.replaceAll('-', '').replaceAll(':', '')}');
  }
  void list(String name, List<int>? xs) {
    if (xs != null) out.add('$name=${xs.join(',')}');
  }

  list('BYMONTH', r.byMonth);
  list('BYWEEKNO', r.byWeekNo);
  list('BYYEARDAY', r.byYearDay);
  list('BYMONTHDAY', r.byMonthDay);
  final byDay = r.byDay;
  if (byDay != null) out.add('BYDAY=${byDay.map((d) => '${d.n ?? ''}${_days[d.weekday - 1]}').join(',')}');
  list('BYHOUR', r.byHour);
  list('BYMINUTE', r.byMinute);
  list('BYSECOND', r.bySecond);
  list('BYSETPOS', r.bySetPos);
  if (r.wkst != 1) out.add('WKST=${_days[r.wkst - 1]}');
  return out.join(';');
}
