import 'civil.dart';
import 'plain.dart';

/// A wall-clock time of an opening: 00:00 to 24:00 inclusive, where
/// [endOfDay] (`24:00`) is the next midnight — what an opening "until
/// midnight" ends at, which a [PlainTime] cannot say (owner's decision 20,
/// 2026-11-08). Used by business hours and by the slots' windows alike.
final class WallTime implements Comparable<WallTime> {
  /// Hours 0–23 (or 24 with nothing after it), minutes and seconds 0–59.
  /// Not checked here, so it can be `const`: a value out of range is said
  /// where it is used ([isValid]).
  const WallTime(this.hour, [this.minute = 0, this.second = 0]);

  static const midnight = WallTime(0);

  /// `24:00`: the next midnight.
  static const endOfDay = WallTime(24);

  /// `08:30`, `08:30:00`, `0830`, `24:00`; null for anything else.
  static WallTime? tryParse(String text) {
    if (text == '24:00' || text == '24:00:00' || text == '2400') return endOfDay;
    final t = PlainTime.tryParse(text);
    if (t == null || t.millisecond != 0) return null;
    return WallTime(t.hour, t.minute, t.second);
  }

  static WallTime fromPlainTime(PlainTime t) => WallTime(t.hour, t.minute, t.second);

  final int hour;
  final int minute;
  final int second;

  bool get isValid =>
      (hour == 24 && minute == 0 && second == 0) ||
      (hour >= 0 && hour < 24 && minute >= 0 && minute < 60 && second >= 0 && second < 60);

  bool get isEndOfDay => hour == 24;

  /// Milliseconds since midnight: 86 400 000 for [endOfDay].
  int get msOfDay => hour * msPerHour + minute * msPerMinute + second * msPerSecond;

  /// The clock reading; midnight for [endOfDay] (of the next day).
  PlainTime get time => isEndOfDay ? PlainTime.midnight : PlainTime.fromMsOfDay(msOfDay);

  @override
  int compareTo(WallTime other) => msOfDay.compareTo(other.msOfDay);

  @override
  bool operator ==(Object other) => other is WallTime && other.msOfDay == msOfDay;

  @override
  int get hashCode => msOfDay.hashCode;

  @override
  String toString() => '${pad2(hour)}:${pad2(minute)}${second == 0 ? '' : ':${pad2(second)}'}';
}
