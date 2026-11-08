import 'civil.dart';

/// A date on the ISO calendar, with no time and no zone: an all-day event's
/// day, a view's first day. Stands for Temporal's `PlainDate`.
final class PlainDate implements Comparable<PlainDate> {
  /// Throws [ArgumentError] for a date that does not exist (2026-02-30):
  /// a programming error. Data from outside goes through [tryParse].
  factory PlainDate(int year, int month, int day) {
    if (month < 1 || month > 12) throw ArgumentError.value(month, 'month');
    if (day < 1 || day > monthLength(year, month)) throw ArgumentError.value(day, 'day');
    return PlainDate._(year, month, day);
  }

  const PlainDate._(this.year, this.month, this.day);

  factory PlainDate.fromEpochDay(int epochDay) {
    final (y, m, d) = civilOf(epochDay);
    return PlainDate._(y, m, d);
  }

  /// "2026-03-29" (also "20260329", and "+010000-01-01"), nothing after it.
  static PlainDate? tryParse(String text) {
    final r = readDate(text);
    if (r == null || r.$4.isNotEmpty) return null;
    return PlainDate._(r.$1, r.$2, r.$3);
  }

  static PlainDate parse(String text) => tryParse(text) ?? (throw FormatException('not an ISO date', text));

  final int year;
  final int month;
  final int day;

  /// Days since 1970-01-01.
  int get epochDay => epochDayOf(year, month, day);

  /// 1 for Monday … 7 for Sunday, as Temporal and ISO 8601.
  int get dayOfWeek => (epochDay + 3) % 7 + 1;

  int get daysInMonth => monthLength(year, month);
  bool get inLeapYear => isLeapYear(year);

  PlainDate addDays(int days) => days == 0 ? this : PlainDate.fromEpochDay(epochDay + days);

  /// Months added, the day kept or brought back to the month's last
  /// (Temporal's `constrain`): 31 January + 1 month is 28 or 29 February.
  PlainDate addMonths(int months) {
    if (months == 0) return this;
    final index = year * 12 + (month - 1) + months;
    final y = floorDiv(index, 12);
    final m = index - y * 12 + 1;
    final last = monthLength(y, m);
    return PlainDate._(y, m, day > last ? last : day);
  }

  PlainDate addYears(int years) => addMonths(years * 12);

  /// Whole days from this date to [other]; negative when [other] is earlier.
  int daysUntil(PlainDate other) => other.epochDay - epochDay;

  PlainDateTime at(PlainTime time) => PlainDateTime(this, time);

  bool isBefore(PlainDate other) => compareTo(other) < 0;
  bool isAfter(PlainDate other) => compareTo(other) > 0;

  @override
  int compareTo(PlainDate other) => year != other.year
      ? year.compareTo(other.year)
      : month != other.month
      ? month.compareTo(other.month)
      : day.compareTo(other.day);

  @override
  bool operator ==(Object other) =>
      other is PlainDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '${yearText(year)}-${pad2(month)}-${pad2(day)}';
}

/// A time of day, to the millisecond, with no date and no zone. Stands for
/// Temporal's `PlainTime`.
final class PlainTime implements Comparable<PlainTime> {
  factory PlainTime(int hour, [int minute = 0, int second = 0, int millisecond = 0]) {
    if (hour < 0 || hour > 23) throw ArgumentError.value(hour, 'hour');
    if (minute < 0 || minute > 59) throw ArgumentError.value(minute, 'minute');
    if (second < 0 || second > 59) throw ArgumentError.value(second, 'second');
    if (millisecond < 0 || millisecond > 999) throw ArgumentError.value(millisecond, 'millisecond');
    return PlainTime._(((hour * 60 + minute) * 60 + second) * msPerSecond + millisecond);
  }

  const PlainTime._(this.msOfDay);

  /// Milliseconds since midnight, 0 ≤ ms < 86 400 000.
  factory PlainTime.fromMsOfDay(int ms) {
    if (ms < 0 || ms >= msPerDay) throw ArgumentError.value(ms, 'ms');
    return PlainTime._(ms);
  }

  static const midnight = PlainTime._(0);

  /// "02:30", "02:30:00", "0230", "02:30:00.5"; nothing after it.
  static PlainTime? tryParse(String text) {
    final r = readTime(text);
    if (r == null || r.$2.isNotEmpty) return null;
    return PlainTime._(r.$1);
  }

  static PlainTime parse(String text) => tryParse(text) ?? (throw FormatException('not an ISO time', text));

  final int msOfDay;

  int get hour => msOfDay ~/ msPerHour;
  int get minute => msOfDay ~/ msPerMinute % 60;
  int get second => msOfDay ~/ msPerSecond % 60;
  int get millisecond => msOfDay % msPerSecond;

  @override
  int compareTo(PlainTime other) => msOfDay.compareTo(other.msOfDay);

  @override
  bool operator ==(Object other) => other is PlainTime && other.msOfDay == msOfDay;

  @override
  int get hashCode => msOfDay.hashCode;

  /// "02:30:00", as Temporal writes it.
  @override
  String toString() => clockText(msOfDay);
}

/// A date and a time of day with no zone: a clock face. Stands for Temporal's
/// `PlainDateTime`.
final class PlainDateTime implements Comparable<PlainDateTime> {
  const PlainDateTime(this.date, this.time);

  /// From milliseconds since 1970-01-01T00:00 *on the clock face*: the wall
  /// time read as if it were UTC. How wall arithmetic is done.
  factory PlainDateTime.fromWallMs(int wallMs) {
    final day = floorDiv(wallMs, msPerDay);
    return PlainDateTime(PlainDate.fromEpochDay(day), PlainTime._(wallMs - day * msPerDay));
  }

  /// "2026-03-29T02:30", "2026-03-29T02:30:00"; also a bare date (midnight).
  static PlainDateTime? tryParse(String text) {
    final d = readDate(text);
    if (d == null) return null;
    final date = PlainDate._(d.$1, d.$2, d.$3);
    if (d.$4.isEmpty) return PlainDateTime(date, PlainTime.midnight);
    if (d.$4[0] != 'T' && d.$4[0] != 't' && d.$4[0] != ' ') return null;
    final t = readTime(d.$4.substring(1));
    if (t == null || t.$2.isNotEmpty) return null;
    return PlainDateTime(date, PlainTime._(t.$1));
  }

  static PlainDateTime parse(String text) => tryParse(text) ?? (throw FormatException('not an ISO date-time', text));

  final PlainDate date;
  final PlainTime time;

  /// See [PlainDateTime.fromWallMs].
  int get wallMs => date.epochDay * msPerDay + time.msOfDay;

  /// Moves the clock face; no zone, so every day is 24 h here.
  PlainDateTime addMs(int ms) => ms == 0 ? this : PlainDateTime.fromWallMs(wallMs + ms);

  @override
  int compareTo(PlainDateTime other) => wallMs.compareTo(other.wallMs);

  @override
  bool operator ==(Object other) => other is PlainDateTime && other.date == date && other.time == time;

  @override
  int get hashCode => Object.hash(date, time);

  /// "2026-03-29T02:00:00", as Temporal writes it.
  @override
  String toString() => '${date}T$time';
}
