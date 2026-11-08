// Expectations written by hand from the published rules (IANA tzdata), never
// copied from the implementation's output. Ported from the TypeScript core's
// zone.test.ts, plus what only the port has: its own data and POSIX rules.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

PlainDate d(String s) => PlainDate.parse(s);
PlainTime t(String s) => PlainTime.parse(s);
String? iso(Object? x) => x?.toString();

void main() {
  group('dayInfo', () {
    test('Paris, spring forward (29 March 2026): 23 h, 02:00 → 03:00', () {
      final day = dayInfo(d('2026-03-29'), 'Europe/Paris');
      expect(day.lengthMinutes, 1380);
      expect(day.kind, DayKind.short);
      expect(iso(day.start), '2026-03-28T23:00:00Z');
      expect(day.transitions, hasLength(1));
      final tr = day.transitions.single;
      expect(iso(tr.at), '2026-03-29T01:00:00Z');
      expect(tr.kind, TransitionKind.gap);
      expect(tr.deltaMinutes, 60);
      expect([tr.offsetBefore, tr.offsetAfter], ['+01:00', '+02:00']);
      expect(iso(tr.wallBefore), '2026-03-29T02:00:00');
      expect(iso(tr.wallAfter), '2026-03-29T03:00:00');
    });

    test('Paris, fall back (25 October 2026): 25 h, 03:00 → 02:00', () {
      final day = dayInfo(d('2026-10-25'), 'Europe/Paris');
      expect(day.lengthMinutes, 1500);
      expect(day.kind, DayKind.long);
      final tr = day.transitions.single;
      expect(iso(tr.at), '2026-10-25T01:00:00Z');
      expect(tr.kind, TransitionKind.repeat);
      expect(tr.deltaMinutes, -60);
      expect(iso(tr.wallBefore), '2026-10-25T03:00:00');
      expect(iso(tr.wallAfter), '2026-10-25T02:00:00');
    });

    test('Chicago, both Sundays of 2026', () {
      final spring = dayInfo(d('2026-03-08'), 'America/Chicago');
      expect(spring.kind, DayKind.short);
      expect(iso(spring.transitions.single.at), '2026-03-08T08:00:00Z');
      final fall = dayInfo(d('2026-11-01'), 'America/Chicago');
      expect(fall.kind, DayKind.long);
      expect(iso(fall.transitions.single.at), '2026-11-01T07:00:00Z');
    });

    test('Lord Howe moves by half an hour: 23 h 30 and 24 h 30, both irregular', () {
      final spring = dayInfo(d('2026-10-04'), 'Australia/Lord_Howe');
      expect(spring.lengthMinutes, 1410);
      expect(spring.kind, DayKind.irregular);
      expect(spring.transitions.single.deltaMinutes, 30);
      expect(iso(spring.transitions.single.wallBefore.time), '02:00:00');
      expect(iso(spring.transitions.single.wallAfter.time), '02:30:00');

      final autumn = dayInfo(d('2026-04-05'), 'Australia/Lord_Howe');
      expect(autumn.lengthMinutes, 1470);
      expect(autumn.transitions.single.kind, TransitionKind.repeat);
      expect(iso(autumn.transitions.single.wallAfter.time), '01:30:00');
    });

    test('São Paulo, 4 November 2018: midnight never happened, the day starts at 01:00', () {
      final day = dayInfo(d('2018-11-04'), 'America/Sao_Paulo');
      expect(iso(day.start.inZone('America/Sao_Paulo').time), '01:00:00');
      expect(day.lengthMinutes, 1380);
      // The transition sits exactly on the day's start, and belongs to it.
      expect(day.transitions, hasLength(1));
      expect(iso(day.transitions.single.wallBefore.time), '00:00:00');
    });

    test('Havana, 12 March 2023: a day that begins at 01:00', () {
      final day = dayInfo(d('2023-03-12'), 'America/Havana');
      expect(iso(day.start), '2023-03-12T05:00:00Z');
      expect(day.kind, DayKind.short);
      expect(day.transitions, hasLength(1));
    });

    test('Apia, 30 December 2011: a day that does not exist, and the 31st carries the jump', () {
      final missing = dayInfo(d('2011-12-30'), 'Pacific/Apia');
      expect(missing.lengthMinutes, 0);
      expect(missing.kind, DayKind.skipped);
      expect(missing.transitions, isEmpty);

      final after = dayInfo(d('2011-12-31'), 'Pacific/Apia');
      expect(after.kind, DayKind.normal);
      expect(after.transitions.single.deltaMinutes, 1440);
      expect([after.transitions.single.offsetBefore, after.transitions.single.offsetAfter], ['-10:00', '+14:00']);
      expect(iso(after.transitions.single.wallBefore), '2011-12-30T00:00:00');

      expect(dayInfo(d('2011-12-29'), 'Pacific/Apia').transitions, isEmpty);
      // Owned exactly once across the three days.
      expect(dayInfos(d('2011-12-29'), 3, 'Pacific/Apia').map((x) => x.transitions.length), [0, 0, 1]);
    });

    test('Paris, 1911: mean time (+00:09:21) to +00:00 — an offset with seconds', () {
      final day = dayInfo(d('1911-03-10'), 'Europe/Paris');
      final tr = day.transitions.single;
      expect([tr.offsetBefore, tr.offsetAfter], ['+00:09:21', '+00:00']);
      expect(tr.deltaMinutes, closeTo(-9.35, 1e-10));
      expect(tr.kind, TransitionKind.repeat);
      expect(day.lengthMinutes, closeTo(1440 + 9.35, 1e-10));
      expect(day.kind, DayKind.irregular);
    });

    test('a fixed-offset zone has no transitions', () {
      expect(dayInfo(d('2026-03-29'), '+02:00').transitions, isEmpty);
      expect(iso(dayInfo(d('2026-03-29'), '+02:00').start), '2026-03-28T22:00:00Z');
    });

    test('a zone without daylight saving has only normal days', () {
      expect(dayInfo(d('2026-03-29'), 'Asia/Kolkata').kind, DayKind.normal);
      expect(dayInfo(d('2026-10-25'), 'UTC').transitions, isEmpty);
    });

    test('Dublin, whose rules call winter the exception, still moves +00:00 → +01:00', () {
      final day = dayInfo(d('2026-03-29'), 'Europe/Dublin');
      expect(day.kind, DayKind.short);
      expect([day.transitions.single.offsetBefore, day.transitions.single.offsetAfter], ['+00:00', '+01:00']);
    });

    test('an unknown zone is a programming error here', () {
      expect(() => dayInfo(d('2026-03-29'), 'Mars/Olympus'), throwsArgumentError);
    });
  });

  group('past the last listed transition (the POSIX rule)', () {
    // EU: last Sunday of March and of October at 01:00 UTC. 27 March and
    // 30 October 2050 are those Sundays.
    test('Paris, 2050', () {
      expect(iso(dayInfo(d('2050-03-27'), 'Europe/Paris').transitions.single.at), '2050-03-27T01:00:00Z');
      expect(iso(dayInfo(d('2050-10-30'), 'Europe/Paris').transitions.single.at), '2050-10-30T01:00:00Z');
      expect(dayInfo(d('2050-03-20'), 'Europe/Paris').transitions, isEmpty);
    });

    // US: second Sunday of March at 02:00 standard, first Sunday of November
    // at 02:00 daylight. 14 March and 7 November 2100.
    test('New York, 2100', () {
      expect(iso(dayInfo(d('2100-03-14'), 'America/New_York').transitions.single.at), '2100-03-14T07:00:00Z');
      expect(iso(dayInfo(d('2100-11-07'), 'America/New_York').transitions.single.at), '2100-11-07T06:00:00Z');
    });

    // Lord Howe: first Sunday of October at 02:00 (+10:30) gains half an
    // hour, first Sunday of April at 02:00 (+11:00) gives it back.
    test('Lord Howe, 2045: the half hour, both ways', () {
      final spring = dayInfo(d('2045-10-01'), 'Australia/Lord_Howe');
      expect(iso(spring.transitions.single.at), '2045-09-30T15:30:00Z');
      expect(spring.lengthMinutes, 1410);
      final autumn = dayInfo(d('2045-04-02'), 'Australia/Lord_Howe');
      expect(iso(autumn.transitions.single.at), '2045-04-01T15:00:00Z');
      expect(iso(autumn.transitions.single.wallAfter.time), '01:30:00');
    });

    // The rule governs from the data's last transition, even one that changed
    // no offset: Troll was "-00" (0) until 2005 Feb 12, then +02 from March's
    // last Sunday to October's; Riga kept EET without
    // summer time from 2000 Feb 29 to 2001 Jan 2, Turks and Caicos kept AST
    // (-04) from 2015 Mar 8 to 2018 Mar 11.
    test('never reaches back before the data says it starts', () {
      String offset(String at, String zone) => Instant.parse(at).inZone(zone).offset;
      expect(offset('2000-07-01T12:00:00Z', 'Antarctica/Troll'), '+00:00');
      expect(offset('2006-07-01T12:00:00Z', 'Antarctica/Troll'), '+02:00'); // Mar lastSun – Oct lastSun
      expect(offset('2006-12-01T12:00:00Z', 'Antarctica/Troll'), '+00:00');
      expect(offset('2006-05-01T12:00:00Z', 'Antarctica/Troll'), '+02:00');
      expect(offset('2000-07-11T12:00:00Z', 'Europe/Riga'), '+02:00');
      expect(offset('2001-07-11T12:00:00Z', 'Europe/Riga'), '+03:00');
      expect(offset('2017-03-09T12:00:00Z', 'America/Grand_Turk'), '-04:00');
      expect(offset('2019-01-09T12:00:00Z', 'America/Grand_Turk'), '-05:00');
    });

    test('a whole year has exactly its two changes', () {
      final from = Instant.parse('2060-01-01T00:00:00Z');
      final to = Instant.parse('2061-01-01T00:00:00Z');
      expect(transitionsBetween(from, to, 'Europe/Paris').map((x) => x.kind), [
        TransitionKind.gap,
        TransitionKind.repeat,
      ]);
      expect(transitionsBetween(from, to, 'Asia/Kolkata'), isEmpty);
    });
  });

  group('dayInfos', () {
    test('chains days end to start, and agrees with dayInfo', () {
      final days = dayInfos(d('2026-10-24'), 3, 'Europe/Paris');
      expect(days.map((x) => x.lengthMinutes), [1440, 1500, 1440]);
      expect(days[0].end, days[1].start);
      expect(days[1].end, days[2].start);
      expect(days[1], dayInfo(d('2026-10-25'), 'Europe/Paris'));
    });

    test('agrees with dayInfo day by day over a year, in zones with and without changes', () {
      for (final zone in ['Europe/Paris', 'Australia/Lord_Howe', 'Asia/Kolkata']) {
        final year = dayInfos(d('2026-01-01'), 365, zone);
        for (final day in year) {
          expect(day, dayInfo(day.date, zone));
        }
        expect(year.expand((x) => x.transitions).length, zone == 'Asia/Kolkata' ? 0 : 2);
      }
    });

    test('count 0 or less gives no days', () {
      expect(dayInfos(d('2026-01-01'), 0, 'UTC'), isEmpty);
      expect(dayInfos(d('2026-01-01'), -3, 'UTC'), isEmpty);
    });
  });

  group('transitionsBetween', () {
    test('finds both changes of 2026 in Paris, in order', () {
      final found = transitionsBetween(
        Instant.parse('2026-01-01T00:00:00Z'),
        Instant.parse('2027-01-01T00:00:00Z'),
        'Europe/Paris',
      );
      expect(found.map((x) => x.kind), [TransitionKind.gap, TransitionKind.repeat]);
    });

    test('is half-open: a transition exactly at `to` is not included', () {
      final at = Instant.parse('2026-03-29T01:00:00Z');
      expect(transitionsBetween(at.addMs(-3600000), at, 'Europe/Paris'), isEmpty);
      expect(transitionsBetween(at, at.addMs(3600000), 'Europe/Paris'), hasLength(1));
    });
  });

  group('resolveWall', () {
    final autumn = d('2026-10-25');
    final spring = d('2026-03-29');

    test('the repeated 02:30: earlier is +02:00, later is +01:00', () {
      final earlier = resolveWall(autumn, t('02:30'), 'Europe/Paris', WallPolicy.earlier);
      expect(earlier.ambiguous, isTrue);
      expect(iso(earlier.instant), '2026-10-25T00:30:00Z');
      expect(iso(earlier.other), '2026-10-25T01:30:00Z');
      expect(iso(resolveWall(autumn, t('02:30'), 'Europe/Paris', WallPolicy.later).instant), '2026-10-25T01:30:00Z');
      expect(
        iso(resolveWall(autumn, t('02:30'), 'Europe/Paris', WallPolicy.compatible).instant),
        '2026-10-25T00:30:00Z',
      );
    });

    test('preferOffset picks the reading by its offset', () {
      final r = resolveWall(autumn, t('02:30'), 'Europe/Paris', const WallPolicy.preferOffset('+01:00'));
      expect(iso(r.instant), '2026-10-25T01:30:00Z');
      expect(iso(r.other), '2026-10-25T00:30:00Z');
    });

    test('the skipped 02:30: compatible pushes forward, earlier pushes back, reject refuses', () {
      final fwd = resolveWall(spring, t('02:30'), 'Europe/Paris', WallPolicy.compatible);
      expect(fwd.exists, isFalse);
      expect(iso(fwd.instant), '2026-03-29T01:30:00Z'); // 03:30 +02:00
      expect(iso(resolveWall(spring, t('02:30'), 'Europe/Paris', WallPolicy.earlier).instant), '2026-03-29T00:30:00Z');
      expect(resolveWall(spring, t('02:30'), 'Europe/Paris', WallPolicy.reject).instant, isNull);
      expect(resolveWall(autumn, t('02:30'), 'Europe/Paris', WallPolicy.reject).instant, isNull);
    });

    test('preferOffset compares offsets, not their spelling, and says when none matched', () {
      for (final spelling in ['+01:00', '+0100', '+01']) {
        final r = resolveWall(autumn, t('02:30'), 'Europe/Paris', WallPolicy.preferOffset(spelling));
        expect(iso(r.instant), '2026-10-25T01:30:00Z');
        expect(r.offsetMatched, isTrue);
      }
      final none = resolveWall(autumn, t('02:30'), 'Europe/Paris', const WallPolicy.preferOffset('+05:00'));
      expect(iso(none.instant), '2026-10-25T00:30:00Z');
      expect(none.offsetMatched, isFalse);
      expect(resolveWall(autumn, t('02:30'), 'Europe/Paris', WallPolicy.earlier).offsetMatched, isNull);
    });

    test('Lord Howe: half an hour skipped, half an hour repeated', () {
      final gap = resolveWall(d('2026-10-04'), t('02:15'), 'Australia/Lord_Howe', WallPolicy.compatible);
      expect(gap.exists, isFalse);
      expect(iso(gap.instant!.inZone('Australia/Lord_Howe').time), '02:45:00');
      final rep = resolveWall(d('2026-04-05'), t('01:45'), 'Australia/Lord_Howe', WallPolicy.later);
      expect(rep.ambiguous, isTrue);
      expect(rep.instant!.epochMilliseconds - rep.other!.epochMilliseconds, 30 * 60000);
    });

    test('Apia, 30 December 2011: any time that day is skipped by a whole day', () {
      final noon = resolveWall(d('2011-12-30'), t('12:00'), 'Pacific/Apia', WallPolicy.compatible);
      expect(noon.exists, isFalse);
      expect(iso(noon.instant), '2011-12-30T22:00:00Z'); // read at -10:00: 31 December 12:00 at +14:00
    });

    test('an ordinary time has one reading whatever the policy', () {
      final r = resolveWall(spring, t('10:00'), 'Europe/Paris', WallPolicy.reject);
      expect(iso(r.instant), '2026-03-29T08:00:00Z');
      expect(r.other, isNull);
    });
  });

  group('zones', () {
    test('names, links, case, UTC and whole-minute offsets', () {
      for (final z in [
        'Europe/Paris',
        'Asia/Calcutta',
        'europe/paris',
        'UTC',
        'Etc/UTC',
        '+02:00',
        '+0200',
        '-05',
        'Africa/Algiers',
      ]) {
        expect(isValidZone(z), isTrue, reason: z);
      }
      for (final z in ['', 'Mars/Olympus', '+01:00:30', '+25:00', '02:00', 'Europe/']) {
        expect(isValidZone(z), isFalse, reason: z);
      }
    });

    test('a link reads as its zone', () {
      expect(
        dayInfo(d('2026-03-29'), 'Europe/Monaco').transitions.single.at,
        dayInfo(d('2026-03-29'), 'Europe/Paris').transitions.single.at,
      );
    });

    test('isOffsetZone', () {
      expect(isOffsetZone('+02:00'), isTrue);
      expect(isOffsetZone('Europe/Paris'), isFalse);
    });

    test('isQuietDay: a change the day before or after counts', () {
      expect(isQuietDay(d('2026-03-28'), 'Europe/Paris'), isFalse);
      expect(isQuietDay(d('2026-03-29'), 'Europe/Paris'), isFalse);
      expect(isQuietDay(d('2026-03-30'), 'Europe/Paris'), isFalse);
      expect(isQuietDay(d('2026-03-31'), 'Europe/Paris'), isTrue);
      expect(isQuietDay(d('2026-03-29'), 'Asia/Kolkata'), isTrue);
    });

    test('the bundled data says its release', () {
      expect(zoneDataVersion, matches(RegExp(r'^\d{4}[a-z]$')));
    });
  });
}
