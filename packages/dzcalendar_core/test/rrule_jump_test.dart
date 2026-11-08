// The rrule iterators jump to the window's period when the rule has no
// COUNT (19e-1). What they give must not change: for rules of every kind,
// the occurrences in a window years after DTSTART are the same with the
// jump (a `from` hint) as from a walk from DTSTART (no hint). A 32-bit LCG
// keeps the draw the same on every run.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

void main() {
  var seed = 19;
  int next(int n) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % n;
  }

  const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  String rule() {
    final freq = ['DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY'][next(4)];
    final parts = ['FREQ=$freq', 'INTERVAL=${1 + next(3)}'];
    if (next(2) == 0) parts.add('BYDAY=${days[next(7)]}${next(2) == 0 ? ',${days[next(7)]}' : ''}');
    if (freq == 'MONTHLY' && next(3) == 0) parts.add('BYMONTHDAY=${[1, 15, 31, -1][next(4)]}');
    if (freq == 'YEARLY' && next(2) == 0) parts.add('BYMONTH=${1 + next(12)}');
    if ((freq == 'MONTHLY' || freq == 'YEARLY') && parts.any((p) => p.startsWith('BYDAY')) && next(2) == 0) {
      parts.add('BYSETPOS=${[1, -1, 2][next(3)]}');
    }
    if (next(4) == 0) parts.add('WKST=${days[next(7)]}');
    if (next(5) == 0) parts.add('UNTIL=20${40 + next(20)}0101T000000Z');
    return parts.join(';');
  }

  test('timed rules: the window years later is the same with the jump as without', () {
    const zones = ['Europe/Paris', 'America/New_York', 'Australia/Lord_Howe', 'Asia/Riyadh'];
    for (var n = 0; n < 300; n++) {
      final text = rule();
      final r = parseRRule(text).rule!;
      final zone = zones[next(zones.length)];
      final start = ZonedDateTime.fromWall(
        PlainDateTime(PlainDate(2018 + next(5), 1 + next(12), 1 + next(28)), PlainTime(next(24), 30)),
        zone,
      )!;
      final from = start.instant.addMs((365 * (2 + next(25)) + next(365)) * 86400000);
      final to = from.addMs(70 * 86400000);
      List<String> inWindow(Iterable<ZonedDateTime> it) => [
        for (final z in it.takeWhile((z) => z.instant.isBefore(to)))
          if (!z.instant.isBefore(from)) '$z',
      ];
      expect(inWindow(iterateZoned(start, r, from)), inWindow(iterateZoned(start, r)), reason: '$text from $start');
    }
  });

  test('all-day rules: the same', () {
    for (var n = 0; n < 300; n++) {
      final text = rule();
      final r = parseRRule(text).rule!;
      final start = PlainDate(2018 + next(5), 1 + next(12), 1 + next(28));
      final from = start.addDays(365 * (2 + next(25)) + next(365));
      final to = from.addDays(70);
      List<String> inWindow(Iterable<PlainDate> it) => [
        for (final d in it.takeWhile((d) => d.isBefore(to)))
          if (!d.isBefore(from)) '$d',
      ];
      expect(
        inWindow(iterateDates(start, r, from.epochDay)),
        inWindow(iterateDates(start, r)),
        reason: '$text from $start',
      );
    }
  });
}
