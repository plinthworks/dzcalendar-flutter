/// Calendar arithmetic on the proleptic Gregorian (ISO) calendar, by day
/// number: day 0 is 1970-01-01. Shared by the time types; not exported.
library;

const msPerSecond = 1000;
const msPerMinute = 60 * msPerSecond;
const msPerHour = 60 * msPerMinute;
const msPerDay = 24 * msPerHour;

bool isLeapYear(int year) => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

int monthLength(int year, int month) => switch (month) {
  2 => isLeapYear(year) ? 29 : 28,
  4 || 6 || 9 || 11 => 30,
  _ => 31,
};

/// Days since 1970-01-01 (Howard Hinnant's `days_from_civil`).
int epochDayOf(int year, int month, int day) {
  final y = month <= 2 ? year - 1 : year;
  final era = (y >= 0 ? y : y - 399) ~/ 400;
  final yoe = y - era * 400;
  final mp = (month + 9) % 12;
  final doy = (153 * mp + 2) ~/ 5 + day - 1;
  final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
  return era * 146097 + doe - 719468;
}

/// The inverse of [epochDayOf], as `(year, month, day)`.
(int, int, int) civilOf(int epochDay) {
  final z = epochDay + 719468;
  final era = (z >= 0 ? z : z - 146096) ~/ 146097;
  final doe = z - era * 146097;
  final yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
  final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
  final mp = (5 * doy + 2) ~/ 153;
  final day = doy - (153 * mp + 2) ~/ 5 + 1;
  final month = mp < 10 ? mp + 3 : mp - 9;
  return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day);
}

/// Floor division by a positive [b], for negative epoch values. Dart's `%`
/// with a positive divisor is already the floor remainder.
int floorDiv(int a, int b) => (a - a % b) ~/ b;

String pad2(int n) => n.toString().padLeft(2, '0');

/// ISO 8601's year: four digits, or six with a sign outside 0000–9999.
String yearText(int year) => year >= 0 && year <= 9999
    ? year.toString().padLeft(4, '0')
    : '${year < 0 ? '-' : '+'}${year.abs().toString().padLeft(6, '0')}';

/// "HH:MM:SS", then the milliseconds without trailing zeros, as Temporal writes them.
String clockText(int msOfDay) {
  final h = msOfDay ~/ msPerHour;
  final m = msOfDay ~/ msPerMinute % 60;
  final s = msOfDay ~/ msPerSecond % 60;
  final ms = msOfDay % msPerSecond;
  final base = '${pad2(h)}:${pad2(m)}:${pad2(s)}';
  if (ms == 0) return base;
  return '$base.${ms.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
}

// One form throughout, as Temporal: "2026-03-29" or "20260329", never
// "2026-0329" (the back-references repeat the first separator).
final _date = RegExp(r'^([+-]\d{6}|\d{4})(-?)(\d{2})\2(\d{2})');
final _time = RegExp(r'^(\d{2})(?:(:?)(\d{2})(?:\2(\d{2})(?:[.,](\d{1,9}))?)?)?');

/// Reads a date at the start of [text]: `(year, month, day, rest)`, or null.
(int, int, int, String)? readDate(String text) {
  final m = _date.firstMatch(text);
  if (m == null) return null;
  final yearText = m[1]!;
  if (yearText == '-000000') return null; // ISO 8601: no negative zero
  final year = int.parse(yearText);
  final month = int.parse(m[3]!);
  final day = int.parse(m[4]!);
  if (month < 1 || month > 12 || day < 1 || day > monthLength(year, month)) return null;
  return (year, month, day, text.substring(m.end));
}

/// Reads a time of day at the start of [text]: `(ms of day, rest)`, or null.
/// Fractions past the millisecond are dropped.
(int, String)? readTime(String text) {
  final m = _time.firstMatch(text);
  if (m == null) return null;
  final h = int.parse(m[1]!);
  final min = int.parse(m[3] ?? '0');
  // A leap second (":60") reads as :59, as Temporal does.
  final second = int.parse(m[4] ?? '0');
  final s = second == 60 ? 59 : second;
  final frac = m[5];
  if (h > 23 || min > 59 || s > 59) return null;
  final ms = frac == null ? 0 : int.parse(frac.padRight(3, '0').substring(0, 3));
  return ((h * 3600 + min * 60 + s) * msPerSecond + ms, text.substring(m.end));
}

final _offset = RegExp(r'^([+-])(\d{2})(?:(:?)(\d{2})(?:\3(\d{2})(?:[.,](\d{1,9}))?)?)?$');

/// "+01:00", "+0100" and "+01" are one offset; returned in milliseconds east
/// of UTC, or null. Seconds are allowed (Paris kept +00:09:21 until 1911).
int? parseOffsetMs(String text) {
  final m = _offset.firstMatch(text);
  if (m == null) return null;
  final h = int.parse(m[2]!);
  final min = int.parse(m[4] ?? '0');
  final s = int.parse(m[5] ?? '0');
  if (h > 23 || min > 59 || s > 59) return null;
  final frac = m[6];
  final ms = frac == null ? 0 : int.parse(frac.padRight(3, '0').substring(0, 3));
  final total = (h * 3600 + min * 60 + s) * msPerSecond + ms;
  return m[1] == '-' ? -total : total;
}

/// To the minute, rounded half away from zero: what Temporal writes in a
/// `ZonedDateTime`'s string ("+00:09" for Paris's +00:09:21), while its
/// `offset` keeps the seconds.
String offsetTextToMinute(int offsetMs) {
  final minutes = (offsetMs.abs() + msPerMinute ~/ 2) ~/ msPerMinute;
  return offsetText((offsetMs < 0 ? -minutes : minutes) * msPerMinute);
}

/// "+02:00", "-10:00", "+00:09:21": seconds only when there are some, as Temporal.
String offsetText(int offsetMs) {
  final sign = offsetMs < 0 ? '-' : '+';
  final abs = offsetMs.abs();
  final h = abs ~/ msPerHour;
  final m = abs ~/ msPerMinute % 60;
  final s = abs ~/ msPerSecond % 60;
  final ms = abs % msPerSecond;
  final base = '$sign${pad2(h)}:${pad2(m)}';
  if (s == 0 && ms == 0) return base;
  if (ms == 0) return '$base:${pad2(s)}';
  return '$base:${pad2(s)}.${ms.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
}
