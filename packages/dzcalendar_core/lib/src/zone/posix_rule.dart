import '../time/civil.dart';

/// A POSIX TZ rule (the footer of a TZif file, RFC 8536 §3.3):
/// `CET-1CEST,M3.5.0,M10.5.0/3`. It gives a zone's clock changes after its
/// last listed transition, for every year to come.
final class PosixRule {
  PosixRule._(this.stdOffsetMs, this.dstOffsetMs, this._start, this._end);

  /// Offsets east of UTC (POSIX writes them west of it: `CET-1` is +01:00).
  final int stdOffsetMs;

  /// Null when the zone keeps one offset.
  final int? dstOffsetMs;
  final _When? _start;
  final _When? _end;

  /// Null for an empty footer or one this reader does not understand; the
  /// zone then keeps its last listed offset, as the TZif rules say.
  static PosixRule? tryParse(String text) {
    if (text.isEmpty) return null;
    final r = _Reader(text);
    if (!r.name()) return null;
    final std = r.offset();
    if (std == null) return null;
    if (r.done) return PosixRule._(-std, null, null, null);
    if (!r.name()) return null;
    var dst = std - msPerHour;
    if (!r.done && r.peek != ',') {
      final o = r.offset();
      if (o == null) return null;
      dst = o;
    }
    if (!r.take(',')) return null;
    final start = r.when();
    if (start == null || !r.take(',')) return null;
    final end = r.when();
    if (end == null || !r.done) return null;
    return PosixRule._(-std, -dst, start, end);
  }

  /// This year's changes as `(instant ms, offset after)`, in order: daylight
  /// time starts at a wall time read in standard time, ends at one read in
  /// daylight time.
  List<(int, int)> changesIn(int year) {
    final dst = dstOffsetMs;
    if (dst == null) return const [];
    final on = _start!.wallMs(year) - stdOffsetMs;
    final off = _end!.wallMs(year) - dst;
    return on <= off ? [(on, dst), (off, stdOffsetMs)] : [(off, stdOffsetMs), (on, dst)];
  }
}

/// A rule's date and time of day: `M3.5.0/3`, `J60`, `59/-1`.
final class _When {
  _When(this.kind, this.a, this.b, this.c, this.timeMs);

  /// 'M' (month, week, weekday), 'J' (1–365, 29 February never counted),
  /// 'n' (0–365, 29 February counted).
  final String kind;
  final int a;
  final int b;
  final int c;

  /// From the day's midnight; may be negative or past 24 h (RFC 8536 §3.3.1).
  final int timeMs;

  int wallMs(int year) => _epochDay(year) * msPerDay + timeMs;

  int _epochDay(int year) {
    switch (kind) {
      case 'J':
        final jan1 = epochDayOf(year, 1, 1);
        return jan1 + a - 1 + (isLeapYear(year) && a >= 60 ? 1 : 0);
      case 'n':
        return epochDayOf(year, 1, 1) + a;
      default:
        // Month a, week b (5 = the last), weekday c (0 = Sunday).
        final first = epochDayOf(year, a, 1);
        final firstWeekday = (first + 4) % 7; // 1970-01-01 was a Thursday (4)
        var day = first + (c - firstWeekday) % 7 + (b - 1) * 7;
        final last = first + monthLength(year, a) - 1;
        while (day > last) {
          day -= 7;
        }
        return day;
    }
  }
}

final class _Reader {
  _Reader(this.text);
  final String text;
  int at = 0;

  bool get done => at >= text.length;
  String get peek => text[at];

  bool take(String c) {
    if (done || text[at] != c) return false;
    at++;
    return true;
  }

  /// `CET`, or `<+0330>`; at least three characters, as POSIX asks.
  bool name() {
    if (take('<')) {
      final close = text.indexOf('>', at);
      if (close < 0) return false;
      at = close + 1;
      return true;
    }
    final from = at;
    while (!done && RegExp('[A-Za-z]').hasMatch(text[at])) {
      at++;
    }
    return at - from >= 3;
  }

  /// `[+-]hh[:mm[:ss]]`, in milliseconds as written (west positive).
  int? offset() {
    var sign = 1;
    if (take('-')) {
      sign = -1;
    } else {
      take('+');
    }
    final h = _number();
    if (h == null) return null;
    var total = h * 3600;
    if (take(':')) {
      final m = _number();
      if (m == null) return null;
      total += m * 60;
      if (take(':')) {
        final s = _number();
        if (s == null) return null;
        total += s;
      }
    }
    return sign * total * msPerSecond;
  }

  _When? when() {
    String kind;
    int a;
    var b = 0;
    var c = 0;
    if (take('M')) {
      kind = 'M';
      final m = _number();
      if (m == null || !take('.')) return null;
      final w = _number();
      if (w == null || !take('.')) return null;
      final d = _number();
      if (d == null || m < 1 || m > 12 || w < 1 || w > 5 || d > 6) return null;
      (a, b, c) = (m, w, d);
    } else if (take('J')) {
      kind = 'J';
      final n = _number();
      if (n == null || n < 1 || n > 365) return null;
      a = n;
    } else {
      kind = 'n';
      final n = _number();
      if (n == null || n > 365) return null;
      a = n;
    }
    var time = 2 * msPerHour;
    if (take('/')) {
      final t = offset();
      if (t == null) return null;
      time = t;
    }
    return _When(kind, a, b, c, time);
  }

  int? _number() {
    final from = at;
    while (!done && text.codeUnitAt(at) >= 0x30 && text.codeUnitAt(at) <= 0x39) {
      at++;
    }
    return at == from ? null : int.parse(text.substring(from, at));
  }
}
