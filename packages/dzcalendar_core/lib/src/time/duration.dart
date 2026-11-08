import 'civil.dart';
import 'plain.dart';

/// A length of time as Temporal's `Duration` counts it (owner's decision 6,
/// 2026-11-08): a calendar part — years, months, weeks, days, moved on the
/// clock face, so a day is 23, 24 or 25 hours — and an exact part — hours,
/// minutes, seconds, milliseconds. "P1D", "PT1H30M", "PT0S".
///
/// Every field has the same sign. For exact time alone between instants,
/// `dart:core`'s [Duration] is used, as Temporal's `Instant` does.
final class IsoDuration {
  /// Throws [ArgumentError] when the fields' signs differ: a programming
  /// error. Data from outside goes through [tryFrom].
  IsoDuration({
    this.years = 0,
    this.months = 0,
    this.weeks = 0,
    this.days = 0,
    this.hours = 0,
    this.minutes = 0,
    this.seconds = 0,
    this.milliseconds = 0,
  }) {
    if (_mixedSigns(_fields)) throw ArgumentError('an IsoDuration has one sign: $_fields');
    if (_checked(years, months, weeks, days, hours, minutes, seconds, milliseconds) == null) {
      throw ArgumentError('an IsoDuration past Temporal\'s limits: $_fields');
    }
  }

  const IsoDuration._(
    this.years,
    this.months,
    this.weeks,
    this.days,
    this.hours,
    this.minutes,
    this.seconds,
    this.milliseconds,
  );

  static const zero = IsoDuration._(0, 0, 0, 0, 0, 0, 0, 0);

  final int years;
  final int months;
  final int weeks;
  final int days;
  final int hours;
  final int minutes;
  final int seconds;
  final int milliseconds;

  List<int> get _fields => [years, months, weeks, days, hours, minutes, seconds, milliseconds];

  /// -1, 0 or 1.
  int get sign {
    for (final f in [years, months, weeks, days, hours, minutes, seconds, milliseconds]) {
      if (f != 0) return f.sign;
    }
    return 0;
  }

  bool get isZero => sign == 0;

  /// True when only hours and smaller are set: exact time, the same length
  /// on every day.
  bool get isExact => years == 0 && months == 0 && weeks == 0 && days == 0;

  /// The exact part, in milliseconds.
  int get exactMs => ((hours * 60 + minutes) * 60 + seconds) * msPerSecond + milliseconds;

  IsoDuration negated() => IsoDuration._(-years, -months, -weeks, -days, -hours, -minutes, -seconds, -milliseconds);

  /// An [IsoDuration] as given, an ISO 8601 string ("P1DT2H", "-PT30M",
  /// "PT1.5H"), or a map as an API's JSON writes Temporal's `DurationLike`
  /// (`{"hours": 1}`: unknown keys ignored, at least one known one needed;
  /// `microseconds` and `nanoseconds` read to the millisecond). Null for
  /// anything else, mixed signs, or a length past Temporal's limits. Never throws.
  static IsoDuration? tryFrom(Object? value) => switch (value) {
    IsoDuration d => d,
    String s => tryParse(s),
    Map<Object?, Object?> m => _fromMap(m),
    _ => null,
  };

  static const _mapNames = [
    'years',
    'months',
    'weeks',
    'days',
    'hours',
    'minutes',
    'seconds',
    'milliseconds',
    'microseconds',
    'nanoseconds',
  ];

  static IsoDuration? _fromMap(Map<Object?, Object?> m) {
    if (!m.keys.any(_mapNames.contains)) return null;
    final f = <int>[];
    for (final name in _mapNames) {
      final v = m[name] ?? 0;
      if (v is int) {
        f.add(v);
      } else if (v is double && v.isFinite && v == v.truncateToDouble() && v.abs() < 9e15) {
        f.add(v.toInt());
      } else {
        return null;
      }
    }
    if (_mixedSigns(f)) return null;
    // Below the millisecond: kept to the millisecond (decision 1).
    final ms = f[7] + f[8] ~/ 1000 + f[9] ~/ 1000000;
    return _checked(f[0], f[1], f[2], f[3], f[4], f[5], f[6], ms);
  }

  /// True when [value] (a string or a map, as [tryFrom] reads it) says
  /// something below the millisecond, which [tryFrom] drops: a warning.
  static bool losesPrecision(Object? value) => switch (value) {
    String s => switch (_iso.firstMatch(s)) {
      final m? => _lost(m[7], msPerHour) || _lost(m[9], msPerMinute) || _lost(m[11], msPerSecond),
      null => false,
    },
    Map<Object?, Object?> m => _subMsInt(m['microseconds'], 1000) || _subMsInt(m['nanoseconds'], 1000000),
    _ => false,
  };

  /// A fraction of a unit that is no whole number of milliseconds.
  static bool _lost(String? frac, int unitMs) =>
      frac != null && int.parse(frac.padRight(9, '0')) * unitMs % 1000000000 != 0;
  static bool _subMsInt(Object? v, int per) => v is num && v.toInt() % per != 0;

  // At most 16 digits a field: past that no length fits Temporal's limits,
  // and `int.parse` could overflow.
  static final _iso = RegExp(
    r'^([+-])?P(?:(\d{1,16})Y)?(?:(\d{1,16})M)?(?:(\d{1,16})W)?(?:(\d{1,16})D)?'
    r'(?:T(?:(\d{1,16})(?:[.,](\d{1,9}))?H)?(?:(\d{1,16})(?:[.,](\d{1,9}))?M)?(?:(\d{1,16})(?:[.,](\d{1,9}))?S)?)?$',
    caseSensitive: false,
  );
  static final _bare = RegExp(r'^[+-]?P$', caseSensitive: false);

  /// ISO 8601, as Temporal reads it: a fraction only on the smallest unit
  /// written, "P" alone or "PT" with nothing after refused; digits below the
  /// millisecond dropped (see [losesPrecision]).
  static IsoDuration? tryParse(String text) {
    final m = _iso.firstMatch(text);
    if (m == null || text.endsWith('T') || text.endsWith('t') || _bare.hasMatch(text)) return null;
    int n(int i) => int.parse(m[i] ?? '0');
    // A fraction belongs to the last unit written: "PT1.5H30M" is refused.
    final hFrac = m[7];
    final mFrac = m[9];
    if (hFrac != null && (m[8] != null || m[10] != null)) return null;
    if (mFrac != null && m[10] != null) return null;
    // Checked before any product: 16 digits of hours in milliseconds overflow.
    if (!_fits(n(2), n(3), n(4), n(5) * 86400.0 + n(6) * 3600.0 + n(8) * 60.0 + n(10))) return null;
    var exact = ((n(6) * 60 + n(8)) * 60 + n(10)) * msPerSecond;
    int part(String? frac, int unitMs) => frac == null ? 0 : int.parse(frac.padRight(9, '0')) * unitMs ~/ 1000000000;
    exact += part(hFrac, msPerHour) + part(mFrac, msPerMinute) + part(m[11], msPerSecond);
    final sign = m[1] == '-' ? -1 : 1;
    // Fractions are spread to the smaller units, as Temporal balances them.
    final h = hFrac == null ? n(6) : exact ~/ msPerHour;
    final rest = exact - h * msPerHour;
    final min = mFrac == null && hFrac == null ? n(8) : rest ~/ msPerMinute;
    final rest2 = rest - min * msPerMinute;
    final s = rest2 ~/ msPerSecond;
    final ms = rest2 - s * msPerSecond;
    return IsoDuration._(sign * n(2), sign * n(3), sign * n(4), sign * n(5), sign * h, sign * min, sign * s, sign * ms);
  }

  /// Temporal's limits: years, months and weeks below 2³², and days with the
  /// exact part below 2⁵³ seconds.
  static bool _fits(int years, int months, int weeks, double seconds) =>
      years.abs() < 4294967296 &&
      months.abs() < 4294967296 &&
      weeks.abs() < 4294967296 &&
      seconds.abs() < 9007199254740992;

  static IsoDuration? _checked(int y, int mo, int w, int d, int h, int mi, int s, int ms) {
    final seconds = d * 86400.0 + h * 3600.0 + mi * 60.0 + s + ms / 1000;
    return _fits(y, mo, w, seconds) ? IsoDuration._(y, mo, w, d, h, mi, s, ms) : null;
  }

  static IsoDuration parse(String text) => tryParse(text) ?? (throw FormatException('not an ISO duration', text));

  /// [date] moved by the calendar part (years and months first, the day kept
  /// or brought back to the month's last, then weeks and days).
  PlainDate addCalendarTo(PlainDate date) => date.addMonths(years * 12 + months).addDays(weeks * 7 + days);

  /// Whole and partial days from [start], the calendar part counted on the
  /// calendar and the exact part as 24-hour days — Temporal's
  /// `total({ unit: 'days', relativeTo: start })` with a date.
  double totalDaysFrom(PlainDate start) => start.daysUntil(addCalendarTo(start)) + exactMs / msPerDay;

  @override
  bool operator ==(Object other) =>
      other is IsoDuration &&
      other.years == years &&
      other.months == months &&
      other.weeks == weeks &&
      other.days == days &&
      other.hours == hours &&
      other.minutes == minutes &&
      other.seconds == seconds &&
      other.milliseconds == milliseconds;

  @override
  int get hashCode => Object.hashAll(_fields);

  /// As Temporal writes it: "P1DT2H", "-PT30M", "PT1.5S", "PT0S".
  @override
  String toString() {
    if (isZero) return 'PT0S';
    final a = sign < 0 ? negated() : this;
    final date = StringBuffer();
    if (a.years != 0) date.write('${a.years}Y');
    if (a.months != 0) date.write('${a.months}M');
    if (a.weeks != 0) date.write('${a.weeks}W');
    if (a.days != 0) date.write('${a.days}D');
    final time = StringBuffer();
    if (a.hours != 0) time.write('${a.hours}H');
    if (a.minutes != 0) time.write('${a.minutes}M');
    // Below the second, balanced into seconds as Temporal writes it: 1500 ms is "PT1.5S".
    final secs = a.seconds + a.milliseconds ~/ msPerSecond;
    final millis = a.milliseconds % msPerSecond;
    if (secs != 0 || millis != 0) {
      final frac = millis == 0 ? '' : '.${millis.toString().padLeft(3, '0').replaceFirst(_trailingZeros, '')}';
      time.write('$secs${frac}S');
    }
    return '${sign < 0 ? '-' : ''}P$date${time.isEmpty ? '' : 'T$time'}';
  }
}

final _trailingZeros = RegExp(r'0+$');

bool _mixedSigns(List<int> fields) => fields.any((f) => f > 0) && fields.any((f) => f < 0);
