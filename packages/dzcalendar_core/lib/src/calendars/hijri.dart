import '../event/problem.dart';
import '../time/plain.dart';
import 'umalqura.g.dart';

/// A day of the Hijri calendar: [month] 1 (Muharram) to 12 (Dhu al-Hijjah),
/// [day] 1 to 30. Made by a [HijriCalendar], which knows the months'
/// lengths; [date] is the same day in the Gregorian calendar.
final class HijriDate implements Comparable<HijriDate> {
  const HijriDate._(this.year, this.month, this.day, this.date);

  final int year;
  final int month;
  final int day;

  /// The same day, Gregorian (its weekday, its place in the grids).
  final PlainDate date;

  @override
  int compareTo(HijriDate other) => date.compareTo(other.date);

  /// The same Hijri day on the same Gregorian day (two calendars, one
  /// corrected, may write one day differently).
  @override
  bool operator ==(Object other) =>
      other is HijriDate && other.year == year && other.month == month && other.day == day && other.date == date;

  @override
  int get hashCode => Object.hash(year, month, day, date);

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} AH';
}

/// How the months are reckoned where no application said otherwise.
enum HijriReckoning {
  /// Saudi Arabia's official calendar (the browser's `islamic-umalqura`):
  /// ICU's table for 1300–1600 AH, the civil reckoning outside (owner's
  /// decision 51).
  ummAlQura('islamic-umalqura'),

  /// The tabular calendar (`islamic-civil`): months of 30 and 29 days in
  /// turn, 11 leap years in 30, from Friday 16 July 622 (Julian).
  civil('islamic-civil');

  const HijriReckoning(this.id);

  /// The name the web gives it (Intl's `-u-ca-`).
  final String id;
}

/// The month of a Hijri year an application corrects: [month] 1–12.
typedef HijriMonth = ({int year, int month});

/// The Hijri calendar, Umm al-Qura or civil, with the months' first days an
/// application was told (owner's decision 52: Algeria's announced
/// Ramadan). Immutable; equal when made from the same corrections.
final class HijriCalendar {
  HijriCalendar._(this.reckoning, Map<HijriMonth, PlainDate> starts)
    : monthStarts = Map.unmodifiable(starts),
      _starts = _effective(reckoning, starts),
      _firstYear = reckoning == HijriReckoning.ummAlQura || starts.isEmpty ? umAlQuraFirstYear : _civilFrom(starts);

  /// Umm al-Qura, as published.
  static final ummAlQura = HijriCalendar._(HijriReckoning.ummAlQura, const {});

  /// The tabular calendar.
  static final civil = HijriCalendar._(HijriReckoning.civil, const {});

  /// [reckoning] with [starts]: each month's first day as announced. Never
  /// throws: a start that cannot be — outside the table's years (Umm
  /// al-Qura) or 1–12, more than two days from the reckoning's, or not
  /// after the month before — is left out (an error at
  /// `monthStarts[1447-09]`); a month made shorter than 29 days or longer
  /// than 30 by its neighbours' is kept, with a warning.
  static (HijriCalendar, List<Problem>) withMonthStarts(
    Map<HijriMonth, PlainDate> starts, {
    HijriReckoning reckoning = HijriReckoning.ummAlQura,
  }) {
    final base = reckoning == HijriReckoning.ummAlQura ? ummAlQura : civil;
    final problems = <Problem>[];
    final kept = <HijriMonth, PlainDate>{};
    String path(HijriMonth m) => 'monthStarts[${m.year}-${m.month.toString().padLeft(2, '0')}]';
    final keys = starts.keys.toList()..sort((a, b) => a.year != b.year ? a.year - b.year : a.month - b.month);
    PlainDate? previous;
    HijriMonth? previousKey;
    for (final m in keys) {
      final given = starts[m]!;
      // Umm al-Qura's first month is where the table meets the civil
      // reckoning: moved, a day before it would be read twice.
      final inRange =
          m.month >= 1 &&
          m.month <= 12 &&
          (reckoning == HijriReckoning.civil
              ? m.year >= 1 && m.year <= 9999
              : m.year >= umAlQuraFirstYear &&
                    m.year <= umAlQuraLastYear &&
                    !(m.year == umAlQuraFirstYear && m.month == 1));
      if (!inRange) {
        problems.add(Problem(ProblemCode.invalidOption, Severity.error, path(m), 'no such month in the table'));
        continue;
      }
      final table = base.monthStart(m.year, m.month);
      final off = table.daysUntil(given);
      if (off.abs() > 2) {
        problems.add(Problem(ProblemCode.invalidOption, Severity.error, path(m), '$given is $off days from $table'));
        continue;
      }
      final p = previous;
      if (p != null && previousKey != null && _index(previousKey) == _index(m) - 1 && !given.isAfter(p)) {
        problems.add(Problem(ProblemCode.invalidOption, Severity.error, path(m), '$given is not after $p'));
        continue;
      }
      kept[m] = given;
      previous = given;
      previousKey = m;
    }
    final made = kept.isEmpty ? base : HijriCalendar._(reckoning, kept);
    // The months the corrections lengthen or shorten past 29–30: kept, said once each.
    final touched = <(int, int)>{
      for (final m in kept.keys) ...[_before(m.year, m.month), (m.year, m.month)],
    }.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
    {
      for (final (y, mo) in touched) {
        final len = made.monthLength(y, mo);
        if (len < 29 || len > 30) {
          problems.add(
            Problem(
              ProblemCode.invalidOption,
              Severity.warning,
              path((year: y, month: mo)),
              '${_monthText(y, mo)} has $len days',
            ),
          );
        }
      }
    }
    return (made, problems);
  }

  final HijriReckoning reckoning;

  /// The corrections in force (an empty map: as published).
  final Map<HijriMonth, PlainDate> monthStarts;

  /// Umm al-Qura: the first day of every month of the table, and one more
  /// (the day after its last), as epoch days, corrections applied; null for
  /// the civil reckoning without corrections.
  final List<int>? _starts;

  String get id => reckoning.id;

  /// [date] in this calendar.
  HijriDate fromDate(PlainDate date) {
    final day = date.epochDay;
    final s = _starts;
    if (s != null && day >= s.first && day < s.last) {
      // The last month starting on or before it.
      var lo = 0;
      var hi = s.length - 1;
      while (hi - lo > 1) {
        final mid = (lo + hi) >> 1;
        if (s[mid] <= day) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final first = _firstYear;
      return HijriDate._(first + lo ~/ 12, lo % 12 + 1, day - s[lo] + 1, date);
    }
    final (y, m, d) = _civilFromDays(day - _civilEpochDay);
    return HijriDate._(y, m, d, date);
  }

  /// The first day of [month] (1–12) of [year], Gregorian. Throws an
  /// [ArgumentError] for another month (the caller's mistake; [toDate]
  /// takes data and answers null).
  PlainDate monthStart(int year, int month) {
    if (month < 1 || month > 12) throw ArgumentError.value(month, 'month', '1–12');
    final s = _starts;
    final first = _firstYear;
    final i = (year - first) * 12 + month - 1;
    if (s != null && i >= 0 && i < s.length - 1) return PlainDate.fromEpochDay(s[i]);
    return PlainDate.fromEpochDay(_civilMonthStart(year, month - 1) + _civilEpochDay);
  }

  /// The days of [month] (1–12) of [year].
  int monthLength(int year, int month) {
    final (ny, nm) = month == 12 ? (year + 1, 1) : (year, month + 1);
    return monthStart(year, month).daysUntil(monthStart(ny, nm));
  }

  /// The Gregorian day of [year]-[month]-[day]; null when the month has no
  /// such day (or [month] is not 1–12).
  PlainDate? toDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > monthLength(year, month)) return null;
    return monthStart(year, month).addDays(day - 1);
  }

  /// The year [_starts] begins with.
  final int _firstYear;

  @override
  bool operator ==(Object other) =>
      other is HijriCalendar &&
      other.reckoning == reckoning &&
      other.monthStarts.length == monthStarts.length &&
      monthStarts.entries.every((e) => other.monthStarts[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    reckoning,
    Object.hashAllUnordered([for (final e in monthStarts.entries) Object.hash(e.key, e.value)]),
  );

  @override
  String toString() => monthStarts.isEmpty ? id : '$id (${monthStarts.length} months corrected)';
}

// ——— the reckonings ———

/// 16 July 622 (Julian) — 19 July 622 proleptic Gregorian — as days since
/// 1970-01-01: ICU's civil epoch (Julian day 1948440).
const _civilEpochDay = 1948440 - 2440588;

int _floorDiv(int a, int b) => (a / b).floor();

bool _civilLeap(int year) => (14 + 11 * year) % 30 < 11;

/// Days from the civil epoch to the first of [month0] (0–11) of [year].
int _civilMonthStart(int year, int month0) => (29.5 * month0).ceil() + 354 * (year - 1) + _floorDiv(3 + 11 * year, 30);

int _civilYearStart(int year) => 354 * (year - 1) + _floorDiv(3 + 11 * year, 30);

int _civilMonthLength(int year, int month0) => 29 + (month0 + 1) % 2 + (month0 == 11 && _civilLeap(year) ? 1 : 0);

/// The civil date [days] after the epoch (ICU's arithmetic).
(int, int, int) _civilFromDays(int days) {
  var year = _floorDiv(30 * days + 10646, 10631);
  // The estimate may land a year late or early near a year's turn.
  while (days < _civilYearStart(year)) {
    year--;
  }
  while (days >= _civilYearStart(year + 1)) {
    year++;
  }
  var month0 = ((days - 29 - _civilYearStart(year)) / 29.5).ceil().clamp(0, 11);
  while (month0 > 0 && days < _civilMonthStart(year, month0)) {
    month0--;
  }
  while (month0 < 11 && days >= _civilMonthStart(year, month0) + _civilMonthLength(year, month0)) {
    month0++;
  }
  return (year, month0 + 1, days - _civilMonthStart(year, month0) + 1);
}

/// Umm al-Qura's month starts (epoch days), the table's, then [starts] laid on.
List<int>? _effective(HijriReckoning reckoning, Map<HijriMonth, PlainDate> starts) {
  if (reckoning == HijriReckoning.civil) {
    if (starts.isEmpty) return null;
    // A civil calendar corrected: the corrected years' months, from a year
    // before the first (its edge stays the civil reckoning's) to the last.
    final from = _civilFrom(starts);
    final to = starts.keys.map((m) => m.year).reduce((a, b) => a > b ? a : b);
    final out = [
      for (var y = from; y <= to + 1; y++)
        for (var m = 0; m < 12; m++)
          if (y <= to || m == 0) _civilMonthStart(y, m) + _civilEpochDay,
    ];
    for (final MapEntry(key: m, value: d) in starts.entries) {
      out[(m.year - from) * 12 + m.month - 1] = d.epochDay;
    }
    return out;
  }
  final out = _table;
  if (starts.isEmpty) return out;
  final copy = [...out];
  for (final MapEntry(key: m, value: d) in starts.entries) {
    copy[(m.year - umAlQuraFirstYear) * 12 + m.month - 1] = d.epochDay;
  }
  return copy;
}

final List<int> _table = () {
  final out = <int>[];
  var day = umAlQuraEpochDay;
  for (final mask in umAlQuraMonths) {
    for (var m = 0; m < 12; m++) {
      out.add(day);
      day += (mask & (1 << (11 - m))) != 0 ? 30 : 29;
    }
  }
  out.add(day);
  return List<int>.unmodifiable(out);
}();

/// The first year of a corrected civil calendar's list: a year before the first corrected.
int _civilFrom(Map<HijriMonth, PlainDate> starts) => starts.keys.map((m) => m.year).reduce((a, b) => a < b ? a : b) - 1;

int _index(HijriMonth m) => m.year * 12 + m.month - 1;

(int, int) _before(int year, int month) => month == 1 ? (year - 1, 12) : (year, month - 1);

String _monthText(int year, int month) => '$year-${month.toString().padLeft(2, '0')}';
