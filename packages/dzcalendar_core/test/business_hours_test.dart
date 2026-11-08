// Ported from the TypeScript core's business-hours.test.ts (hand-written
// expectations, copied as values).
//
// Ported: businessIntervals (5). Skipped: none. Translation notes:
// - The TS inputs (`true`, `false`, a rule, a list) are read with
//   `BusinessHours.fromJson`, the web's spellings.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

PlainDate d(String s) => PlainDate.parse(s);
String iso(int ms) => '${Instant.fromEpochMilliseconds(ms)}';
double hours(MsSpan s) => (s.e - s.s) / 3600000;
BusinessHours bh(Object? json) => BusinessHours.fromJson(json).$1!;

void main() {
  group('businessIntervals', () {
    test('true is Monday–Friday 09:00–17:00 in the display zone', () {
      final spans = businessIntervals(d('2026-10-19'), d('2026-10-26'), bh(true), 'Europe/Paris');
      expect(spans, hasLength(5));
      expect(iso(spans[0].s), '2026-10-19T07:00:00Z');
      expect(spans.every((x) => hours(x) == 8), isTrue);
    });

    test('a Paris shop seen from Chicago: Paris hours, in Chicago’s week', () {
      final spans = businessIntervals(
        d('2026-10-19'),
        d('2026-10-20'),
        bh({
          'daysOfWeek': [1],
          'start': '09:00',
          'end': '18:00',
          'timeZone': 'Europe/Paris',
        }),
        'America/Chicago',
      );
      expect(
        [
          for (final x in spans) [iso(x.s), iso(x.e)],
        ],
        [
          ['2026-10-19T07:00:00Z', '2026-10-19T16:00:00Z'],
        ],
      );
    });

    test('a night shift across the 25-hour night is nine real hours', () {
      final spans = businessIntervals(
        d('2026-10-24'),
        d('2026-10-26'),
        bh({
          'daysOfWeek': [6],
          'start': '22:00',
          'end': '06:00',
        }),
        'Europe/Paris',
      );
      expect(spans.map(hours).toList(), [9]);
    });

    test('24:00 is the next midnight; a 23-hour Sunday open all day is 23 hours', () {
      final spans = businessIntervals(
        d('2026-03-29'),
        d('2026-03-30'),
        bh({
          'daysOfWeek': [7],
          'start': '00:00',
          'end': '24:00',
        }),
        'Europe/Paris',
      );
      expect(spans.map(hours).toList(), [23]);
    });

    test('overlapping rules merge; false is nothing', () {
      final rules = bh([
        {
          'daysOfWeek': [1],
          'start': '09:00',
          'end': '12:00',
        },
        {
          'daysOfWeek': [1],
          'start': '11:00',
          'end': '14:00',
        },
      ]);
      expect(businessIntervals(d('2026-10-19'), d('2026-10-20'), rules, 'UTC').map(hours).toList(), [5]);
      expect(businessIntervals(d('2026-10-19'), d('2026-10-26'), bh(false), 'UTC'), isEmpty);
    });
  });
}
