import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:test/test.dart';

void main() {
  group('PlainDate', () {
    test('reads and writes ISO 8601', () {
      expect(PlainDate.parse('2026-03-29').toString(), '2026-03-29');
      expect(PlainDate.parse('20260329'), PlainDate(2026, 3, 29));
      expect(PlainDate.parse('+010000-01-01').toString(), '+010000-01-01');
      expect(PlainDate(-1, 1, 1).toString(), '-000001-01-01');
      expect(PlainDate(5, 6, 7).toString(), '0005-06-07');
    });

    test('refuses what is no date', () {
      for (final s in [
        '2026-02-29',
        '2026-13-01',
        '2026-04-31',
        '2026-3-29',
        '2026-03-29T00:00',
        '',
        '-000000-01-01',
      ]) {
        expect(PlainDate.tryParse(s), isNull, reason: s);
      }
      expect(PlainDate.tryParse('2024-02-29'), PlainDate(2024, 2, 29));
      expect(() => PlainDate(2026, 2, 29), throwsArgumentError);
    });

    test('day numbers and weekdays', () {
      expect(PlainDate(1970, 1, 1).epochDay, 0);
      expect(PlainDate(1969, 12, 31).epochDay, -1);
      expect(PlainDate(2000, 3, 1).epochDay, 11017);
      expect(PlainDate.fromEpochDay(-719528), PlainDate(0, 1, 1));
      expect(PlainDate(2026, 11, 8).dayOfWeek, 7); // a Sunday
      expect(PlainDate(2026, 11, 9).dayOfWeek, 1);
      expect(PlainDate(1900, 1, 1).dayOfWeek, 1);
      for (var n = -800000; n < 800000; n += 997) {
        expect(PlainDate.fromEpochDay(n).epochDay, n);
      }
    });

    test('adding days and months', () {
      expect(PlainDate(2026, 12, 31).addDays(1), PlainDate(2027, 1, 1));
      expect(PlainDate(2024, 3, 1).addDays(-1), PlainDate(2024, 2, 29));
      expect(PlainDate(2026, 1, 31).addMonths(1), PlainDate(2026, 2, 28));
      expect(PlainDate(2024, 1, 31).addMonths(1), PlainDate(2024, 2, 29));
      expect(PlainDate(2026, 1, 15).addMonths(-13), PlainDate(2024, 12, 15));
      expect(PlainDate(2024, 2, 29).addYears(1), PlainDate(2025, 2, 28));
      expect(PlainDate(2026, 1, 1).daysUntil(PlainDate(2027, 1, 1)), 365);
    });

    test('order and equality', () {
      expect(PlainDate(2026, 1, 2).isAfter(PlainDate(2026, 1, 1)), isTrue);
      expect(PlainDate(2025, 12, 31).compareTo(PlainDate(2026, 1, 1)), lessThan(0));
      expect({PlainDate(2026, 1, 1), PlainDate.parse('2026-01-01')}, hasLength(1));
    });
  });

  group('as the Temporal polyfill reads them', () {
    test('one form throughout, a leap second as :59', () {
      for (final s in ['2026-0329', '202603-29']) {
        expect(PlainDate.tryParse(s), isNull, reason: s);
      }
      expect(PlainTime.tryParse('10:3045'), isNull);
      expect(PlainTime.parse('23:59:60').toString(), '23:59:59');
      expect(Instant.tryParse('2026-03-29T03:00+02:0030'), isNull);
    });

    test('a ZonedDateTime writes its offset to the minute, its zone in IANA case', () {
      final z = Instant.parse('1900-01-01T00:00:00Z').inZone('europe/paris');
      expect(z.toString(), '1900-01-01T00:09:21+00:09[Europe/Paris]');
      expect(z.offset, '+00:09:21');
      expect(
        Instant.parse('2026-01-01T00:00:00Z').inZone('Asia/Calcutta').toString(),
        '2026-01-01T05:30:00+05:30[Asia/Calcutta]',
      );
      expect(Instant.parse('2026-01-01T00:00:00Z').inZone('+0200').zone, '+02:00');
    });
  });

  group('PlainTime', () {
    test('reads and writes as Temporal does', () {
      expect(PlainTime.parse('02:30').toString(), '02:30:00');
      expect(PlainTime.parse('0230').toString(), '02:30:00');
      expect(PlainTime.parse('02:30:05.500').toString(), '02:30:05.5');
      expect(PlainTime.parse('23:59:59.999').toString(), '23:59:59.999');
      for (final s in ['24:00', '12:60', '1:00', '', '12:00Z']) {
        expect(PlainTime.tryParse(s), isNull, reason: s);
      }
    });
  });

  group('PlainDateTime', () {
    test('reads, writes, and moves on the clock face', () {
      final p = PlainDateTime.parse('2026-03-29T02:00');
      expect(p.toString(), '2026-03-29T02:00:00');
      expect(p.addMs(-2 * 3600000).toString(), '2026-03-29T00:00:00');
      expect(p.addMs(-3 * 3600000).toString(), '2026-03-28T23:00:00');
      expect(PlainDateTime.parse('2026-03-29').time, PlainTime.midnight);
      expect(PlainDateTime.tryParse('2026-03-29T02:00Z'), isNull);
    });
  });

  group('Instant', () {
    test('reads offsets and annotations, writes UTC', () {
      expect(Instant.parse('2026-03-29T01:00:00Z').toString(), '2026-03-29T01:00:00Z');
      expect(Instant.parse('2026-03-29T03:00+02:00'), Instant.parse('2026-03-29T01:00Z'));
      expect(Instant.parse('2026-03-29T03:00:00+02:00[Europe/Paris]'), Instant.parse('2026-03-29T01:00Z'));
      expect(Instant.parse('1911-03-11T00:00:00+00:09:21').toString(), '1911-03-10T23:50:39Z');
      expect(Instant.fromEpochMilliseconds(-1).toString(), '1969-12-31T23:59:59.999Z');
      for (final s in ['2026-03-29T01:00', '2026-03-29', '2026-03-29T01:00Z[Europe/Paris', 'x']) {
        expect(Instant.tryParse(s), isNull, reason: s);
      }
    });
  });

  group('ZonedDateTime', () {
    test('an instant seen in a zone', () {
      final z = Instant.parse('2026-03-29T01:00:00Z').inZone('Europe/Paris');
      expect(z.toString(), '2026-03-29T03:00:00+02:00[Europe/Paris]');
      expect(z.offset, '+02:00');
      expect(z.date, PlainDate(2026, 3, 29));
      expect(
        Instant.parse('2026-03-29T00:59:59.999Z').inZone('Europe/Paris').toString(),
        '2026-03-29T01:59:59.999+01:00[Europe/Paris]',
      );
    });

    test('a wall time made an instant, and the start of a day', () {
      expect(
        PlainDateTime.parse('2026-03-29T02:30').inZone('Europe/Paris').toString(),
        '2026-03-29T03:30:00+02:00[Europe/Paris]',
      );
      expect(PlainDateTime.parse('2026-03-29T02:30').inZone('Europe/Paris', Disambiguation.reject), isNull);
      expect(PlainDate(2023, 3, 12).startOfDayIn('America/Havana').toString(), '2023-03-12T05:00:00Z');
      expect(PlainDate(2026, 3, 29).startOfDayIn('Europe/Paris').toString(), '2026-03-28T23:00:00Z');
    });
  });
}
