// Expectations from ISO 8601 and Temporal's documented behaviour, checked
// against the Temporal polyfill where noted.

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:test/test.dart';

void main() {
  group('IsoDuration', () {
    test('reads and writes ISO 8601 as Temporal does', () {
      for (final (text, written) in [
        ('P1D', 'P1D'),
        ('PT0S', 'PT0S'),
        ('P0D', 'PT0S'),
        ('PT1H30M', 'PT1H30M'),
        ('PT90M', 'PT90M'),
        ('-P1W', '-P1W'),
        ('P1Y2M3W4DT5H6M7.008S', 'P1Y2M3W4DT5H6M7.008S'),
        ('PT1.5H', 'PT1H30M'),
        ('PT0.5S', 'PT0.5S'),
        ('pt2h', 'PT2H'),
      ]) {
        expect(IsoDuration.parse(text).toString(), written, reason: text);
      }
      for (final bad in ['P', 'PT', 'P1DT', '1D', 'P1.5D', 'PT1.5H30M', 'P-1D', '']) {
        expect(IsoDuration.tryParse(bad), isNull, reason: bad);
      }
    });

    test('from a map, as an API writes it', () {
      expect(IsoDuration.tryFrom({'hours': 1}), IsoDuration(hours: 1));
      expect(IsoDuration.tryFrom({'days': 2.0}), IsoDuration(days: 2));
      expect(IsoDuration.tryFrom({'hours': 1, 'minutes': -5}), isNull);
      expect(IsoDuration.tryFrom({'hour': 1}), isNull);
      expect(IsoDuration.tryFrom(<String, Object?>{}), isNull);
      expect(IsoDuration.tryFrom(3600), isNull);
      expect(() => IsoDuration(days: 1, hours: -1), throwsArgumentError);
      expect(IsoDuration.parse('-PT1H').sign, -1);
    });

    test('days on the calendar from a date', () {
      expect(IsoDuration(days: 3).totalDaysFrom(PlainDate(2026, 5, 1)), 3);
      expect(IsoDuration(months: 1).totalDaysFrom(PlainDate(2026, 2, 1)), 28);
      expect(IsoDuration(hours: 36).totalDaysFrom(PlainDate(2026, 2, 1)), 1.5);
    });
  });

  group('ZonedDateTime.add', () {
    ZonedDateTime z(String instant) => Instant.parse(instant).inZone('Europe/Paris');

    test('a day is the same time the next day: 23 hours across the spring change', () {
      final sat = z('2026-03-28T08:00:00Z'); // 09:00 +01:00
      expect(sat.add(IsoDuration(days: 1)).toString(), '2026-03-29T09:00:00+02:00[Europe/Paris]');
      expect(sat.add(IsoDuration(hours: 24)).toString(), '2026-03-29T10:00:00+02:00[Europe/Paris]');
    });

    test('a day landing in the gap moves forward (compatible)', () {
      final sat = z('2026-03-28T01:30:00Z'); // 02:30 +01:00
      expect(sat.add(IsoDuration(days: 1)).toString(), '2026-03-29T03:30:00+02:00[Europe/Paris]');
    });

    test('a month keeps the day or takes the last one', () {
      expect(
        z('2026-01-31T11:00:00Z').add(IsoDuration(months: 1)).toString(),
        '2026-02-28T12:00:00+01:00[Europe/Paris]',
      );
      expect(
        z('2026-03-31T10:00:00Z').subtract(IsoDuration(months: 1)).toString(),
        '2026-02-28T12:00:00+01:00[Europe/Paris]',
      );
    });

    test('the repeated hour: one exact hour after the first 02:30 is the second', () {
      final first = Instant.parse('2026-10-25T00:30:00Z').inZone('Europe/Paris');
      expect(first.add(IsoDuration(hours: 1)).toString(), '2026-10-25T02:30:00+01:00[Europe/Paris]');
    });
  });
}
