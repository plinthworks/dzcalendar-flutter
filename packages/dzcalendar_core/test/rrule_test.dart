// Expectations copied as values from the TypeScript core's rrule.test.ts
// (hand-written, or from python-dateutil 2.9), never from this port's output.
// Instants are milliseconds here (nanoseconds in TypeScript).
//
// Skipped: none of the tests of rrule.test.ts. The tests of edit.ts
// (rebaseRule, splitRule, countBefore, explicitRule, implicitRule,
// iterateUnion, indexOfStart, nthStart) live in another file and are not
// ported yet.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

RRule rule(String text) {
  final r = parseRRule(text);
  if (r.rule == null) throw StateError(r.problem!.detail);
  return r.rule!;
}

RRuleSet setOf(List<String> texts) => RRuleSet([for (final t in texts) rule(t)]);

/// `2026-10-19T09:00` in `Europe/Paris` at `+02:00`: wall, offset in hours, zone.
ZonedDateTime z(String wall, int offsetHours, String zone) =>
    ZonedDateTime.fromWall(PlainDateTime.parse(wall), zone, preferOffsetMs: offsetHours * 3600000)!;

Instant i(String s) => Instant.parse(s);
PlainDate d(String s) => PlainDate.parse(s);

void main() {
  group('parse and serialize', () {
    test('round-trips a rule in a fixed order', () {
      for (final text in [
        'FREQ=WEEKLY;INTERVAL=2;COUNT=8;BYDAY=TU,TH;WKST=SU',
        'FREQ=MONTHLY;BYDAY=-1FR',
        'FREQ=YEARLY;UNTIL=20280131T140000Z;BYMONTH=1;BYDAY=MO',
        'FREQ=DAILY;UNTIL=20261231',
        'FREQ=MONTHLY;BYMONTHDAY=1,-1;BYHOUR=9;BYMINUTE=0,30;BYSETPOS=1',
      ]) {
        expect(serializeRRule(rule(text)), text);
      }
    });

    test('never throws: every malformed part is named', () {
      for (final (text, part) in [
        ('FREQ=DAILY;COUNT=0', 'COUNT'),
        ('FREQ=DAILY;BYHOUR=24', 'BYHOUR'),
        ('FREQ=DAILY;FREQ=WEEKLY', 'twice'),
        ('FREQ=DAILY;UNTIL=2026-12-31', 'UNTIL'),
        ('nonsense', 'NAME=VALUE'),
        ('', 'empty'),
      ]) {
        final r = parseRRule(text);
        expect(r.rule, isNull, reason: text);
        expect(r.problem, isNotNull, reason: text);
        expect(r.problem!.detail, contains(part), reason: text);
      }
    });
  });

  group('expansion edges', () {
    test('a rule that can never happen ends, fast, with nothing', () {
      final start = z('2026-01-01T09:00', 0, 'UTC');
      final watch = Stopwatch()..start();
      final got = iterateZoned(start, rule('FREQ=MONTHLY;BYMONTH=2;BYMONTHDAY=31')).toList();
      expect(got, isEmpty);
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });

    test('a window far after the start still finds what is in it', () {
      final start = z('2000-01-03T09:00', 1, 'Europe/Paris');
      final got = expandZoned(
        start,
        setOf(['FREQ=WEEKLY;BYDAY=MO,WE']),
        i('2026-10-19T00:00:00Z'),
        i('2026-10-26T00:00:00Z'),
      );
      expect(got.starts.map((s) => s.toString()), [
        '2026-10-19T09:00:00+02:00[Europe/Paris]',
        '2026-10-21T09:00:00+02:00[Europe/Paris]',
      ]);
    });

    test('two rules merge, in order, without duplicates', () {
      final start = z('2026-10-19T09:00', 2, 'Europe/Paris');
      final got = expandZoned(
        start,
        setOf(['FREQ=WEEKLY;BYDAY=MO,WE', 'FREQ=WEEKLY;BYDAY=WE,FR']),
        start.instant,
        start.add(IsoDuration(days: 7)).instant,
      );
      expect(got.starts.map((s) => s.date.toString()), ['2026-10-19', '2026-10-21', '2026-10-23']);
    });

    test('the limit says so', () {
      final start = z('2026-10-19T09:00', 0, 'UTC');
      final got = expandZoned(
        start,
        setOf(['FREQ=SECONDLY']),
        start.instant,
        start.add(IsoDuration(days: 1)).instant,
        100,
      );
      expect(
        [got.starts.length, got.problems.map((p) => p.code).toList()],
        [
          100,
          ['too-many-occurrences'],
        ],
      );
    });
  });

  group('lastStart', () {
    final start = z('2026-10-19T09:00', 2, 'Europe/Paris');
    test('COUNT walks to the last one; UNTIL bounds it; endless is null', () {
      expect(
        lastStartZoned(start, setOf(['FREQ=DAILY;COUNT=3']))?.toString(),
        '2026-10-21T09:00:00+02:00[Europe/Paris]',
      );
      final u = lastStartZoned(start, setOf(['FREQ=DAILY;UNTIL=20261231T000000Z']));
      expect(u?.toString(), '2026-12-31T01:00:00+01:00[Europe/Paris]');
      expect(lastStartZoned(start, setOf(['FREQ=DAILY'])), isNull);
    });
  });

  group('skipping ahead to a window changes nothing', () {
    final cases = <(ZonedDateTime, String)>[
      (z('2024-03-01T09:30', 1, 'Europe/Paris'), 'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=200'),
      (z('2024-03-01T09:30', 1, 'Europe/Paris'), 'FREQ=DAILY;UNTIL=20260320T083000Z'),
      (z('2024-01-31T02:30', 1, 'Europe/Paris'), 'FREQ=MONTHLY;BYMONTHDAY=-1'),
      (z('2024-11-03T01:30', -4, 'America/New_York'), 'FREQ=YEARLY;BYMONTH=3,11;BYDAY=1SU'),
      (z('2024-01-01T00:00', 0, 'UTC'), 'FREQ=HOURLY;INTERVAL=7'),
      (z('2024-01-01T00:00', 0, 'UTC'), 'FREQ=MINUTELY;INTERVAL=45;COUNT=40000'),
    ];
    for (final (start, text) in cases) {
      test(text, () {
        final from = i('2026-03-16T00:00:00Z');
        final to = i('2026-04-06T00:00:00Z');
        final naive = <String>[];
        for (final s in iterateZoned(start, rule(text))) {
          if (s.instant.compareTo(to) >= 0) break;
          if (s.instant.compareTo(from) >= 0) naive.add(s.toString());
        }
        final got = expandZoned(start, setOf([text]), from, to, 10000).starts.map((s) => s.toString()).toList();
        expect(got, naive);
      });
    }

    test('all-day, with COUNT', () {
      final got = expandDates(
        d('2024-01-31'),
        setOf(['FREQ=MONTHLY;BYMONTHDAY=-1;COUNT=30']),
        d('2026-01-01'),
        d('2027-01-01'),
      ).starts.map((s) => s.toString());
      expect(got, ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31', '2026-06-30']);
    });
  });

  group('limit', () {
    test('exactly the limit is not too many; one more is', () {
      final start = z('2026-10-19T09:00', 0, 'UTC');
      final from = start.instant;
      final to = start.add(IsoDuration(days: 10)).instant;
      RRuleSet set(int n) => setOf(['FREQ=DAILY;COUNT=$n']);
      expect(expandZoned(start, set(5), from, to, 5).problems, isEmpty);
      expect(expandZoned(start, set(6), from, to, 5).problems.map((p) => p.code), ['too-many-occurrences']);
    });
  });

  group('fixed after the code review', () {
    final utc = z('2026-01-01T09:00', 0, 'UTC');
    List<String> all(String text, [ZonedDateTime? start]) => [
      for (final s in iterateZoned(start ?? utc, rule(text))) s.instant.toString(),
    ];

    // Expectations from python-dateutil 2.9 (UTC, so wall and elapsed agree).
    test('sub-daily rules with BY parts reach their COUNT (no step budget cut)', () {
      final a = all('FREQ=SECONDLY;BYHOUR=9;BYMINUTE=0;BYSECOND=0;COUNT=40');
      expect([a.length, a.last], [40, '2026-02-09T09:00:00Z']);
      final b = all('FREQ=MINUTELY;BYHOUR=9;BYMINUTE=0;COUNT=2000');
      expect([b.length, b.last], [2000, '2031-06-23T09:00:00Z']);
    });

    test('an endless SECONDLY rule fills a month window', () {
      final r = expandZoned(
        utc,
        setOf(['FREQ=SECONDLY;BYHOUR=9;BYMINUTE=0;BYSECOND=0']),
        i('2026-03-01T00:00:00Z'),
        i('2026-04-01T00:00:00Z'),
      );
      expect(r.starts.length, 31);
      expect(r.problems, isEmpty);
    });

    test('skipping hours keeps both passes of a repeated hour (elapsed time)', () {
      final start = z('2026-10-25T01:00', 2, 'Europe/Paris');
      expect(all('FREQ=MINUTELY;INTERVAL=15;BYHOUR=2;BYMINUTE=0,30;COUNT=4', start), [
        '2026-10-25T00:00:00Z',
        '2026-10-25T00:30:00Z',
        '2026-10-25T01:00:00Z',
        '2026-10-25T01:30:00Z',
      ]);
    });

    test('several rules: the limit keeps the earliest of the union', () {
      final start = z('2026-10-01T09:00', 0, 'UTC');
      final r = expandZoned(
        start,
        setOf(['FREQ=DAILY', 'FREQ=DAILY;BYHOUR=10']),
        start.instant,
        start.add(IsoDuration(days: 10)).instant,
        5,
      );
      expect(r.starts.map((s) => s.instant.toString()), [
        '2026-10-01T09:00:00Z',
        '2026-10-01T10:00:00Z',
        '2026-10-02T09:00:00Z',
        '2026-10-02T10:00:00Z',
        '2026-10-03T09:00:00Z',
      ]);
    });
  });
}
