// Phase 19h-1: the Hijri calendar (owner's decisions 51–52). Expectations
// written by hand from the Umm al-Qura calendar as Saudi Arabia publishes
// it (Ramadan, the two Eids, the new years), and from the civil
// reckoning's definition (its epoch: Friday 16 July 622 Julian, 19 July
// proleptic Gregorian).
import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

PlainDate d(int y, int m, int day) => PlainDate(y, m, day);
String h(HijriDate x) => '${x.year}-${x.month}-${x.day}';

void main() {
  final uq = HijriCalendar.ummAlQura;

  group('Umm al-Qura', () {
    test('the published days', () {
      expect(h(uq.fromDate(d(2026, 2, 18))), '1447-9-1'); // 1 Ramadan 1447
      expect(h(uq.fromDate(d(2026, 3, 20))), '1447-10-1'); // Eid al-Fitr 1447
      expect(h(uq.fromDate(d(2025, 6, 26))), '1447-1-1'); // 1 Muharram 1447
      expect(h(uq.fromDate(d(2025, 6, 6))), '1446-12-10'); // Eid al-Adha 1446
      expect(h(uq.fromDate(d(2025, 3, 1))), '1446-9-1'); // 1 Ramadan 1446
      expect(h(uq.fromDate(d(2025, 3, 30))), '1446-10-1'); // Eid al-Fitr 1446
      expect(h(uq.fromDate(d(2024, 3, 11))), '1445-9-1'); // 1 Ramadan 1445
      expect(h(uq.fromDate(d(2026, 2, 17))), '1447-8-29'); // the eve of Ramadan
    });

    test('and back', () {
      expect(uq.toDate(1447, 9, 1), d(2026, 2, 18));
      expect(uq.monthStart(1447, 10), d(2026, 3, 20));
      expect(uq.monthLength(1447, 9), 30); // 18 February to 19 March
      expect(uq.toDate(1447, 9, 31), isNull);
      expect(uq.toDate(1447, 13, 1), isNull);
      expect(uq.toDate(1447, 9, 0), isNull);
    });

    test('the table starts on 1 Muharram 1300, 12 November 1882', () {
      expect(h(uq.fromDate(d(1882, 11, 12))), '1300-1-1');
      expect(h(uq.fromDate(d(1882, 11, 11))), '1299-12-29');
    });

    test('every day from 1290 to 1610 AH: one date, and back; months of 29 or 30 days, in a row', () {
      var day = uq.monthStart(1290, 1);
      final end = uq.monthStart(1611, 1);
      HijriDate? before;
      while (day.isBefore(end)) {
        final x = uq.fromDate(day);
        expect(uq.toDate(x.year, x.month, x.day), day, reason: '$day');
        if (before != null) {
          final next = before.day == uq.monthLength(before.year, before.month)
              ? (before.month == 12 ? '${before.year + 1}-1-1' : '${before.year}-${before.month + 1}-1')
              : '${before.year}-${before.month}-${before.day + 1}';
          expect(h(x), next, reason: '$day');
        }
        before = x;
        day = day.addDays(1);
      }
      for (var y = 1290; y <= 1610; y++) {
        for (var m = 1; m <= 12; m++) {
          expect(uq.monthLength(y, m), inInclusiveRange(29, 30), reason: '$y-$m');
        }
      }
    });
  });

  group('civil', () {
    final civil = HijriCalendar.civil;
    test('1 Muharram 1 is 19 July 622 (proleptic Gregorian), a Friday', () {
      final x = civil.fromDate(d(622, 7, 19));
      expect(h(x), '1-1-1');
      expect(x.date.dayOfWeek, 5);
      expect(h(civil.fromDate(d(622, 7, 18))), '0-12-29');
    });

    test('months of 30 and 29 days in turn; Dhu al-Hijjah 30 in the 11 leap years of 30', () {
      expect([for (var m = 1; m <= 12; m++) civil.monthLength(1447, m)].take(11), [
        30, 29, 30, 29, 30, 29, 30, 29, 30, 29, 30, //
      ]);
      // Leap years of the cycle: 2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29.
      final leap = [
        for (var y = 1; y <= 30; y++)
          if (civil.monthLength(y, 12) == 30) y,
      ];
      expect(leap, [2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29]);
    });

    test('Umm al-Qura is civil outside its table: 1299 and 1601', () {
      expect(uq.monthStart(1299, 5), civil.monthStart(1299, 5));
      expect(uq.monthStart(1601, 7), civil.monthStart(1601, 7));
    });
  });

  group('month starts an application corrects (decision 52)', () {
    test('Ramadan 1447 announced a day later in Algeria: Shaban one day longer, Ramadan one shorter', () {
      final (dz, problems) = HijriCalendar.withMonthStarts({(year: 1447, month: 9): d(2026, 2, 19)});
      expect(problems, isEmpty);
      expect(h(dz.fromDate(d(2026, 2, 18))), '1447-8-${uq.monthLength(1447, 8) + 1}');
      expect(h(dz.fromDate(d(2026, 2, 19))), '1447-9-1');
      expect(dz.monthLength(1447, 9), uq.monthLength(1447, 9) - 1);
      // Shawwal as published: Eid the same day.
      expect(h(dz.fromDate(d(2026, 3, 20))), '1447-10-1');
      expect(dz.toDate(1447, 9, 1), d(2026, 2, 19));
      expect(dz, isNot(uq));
      expect(HijriCalendar.withMonthStarts({(year: 1447, month: 9): d(2026, 2, 19)}).$1, dz);
    });

    test('what cannot be is left out, an error each; a month made 32 days long is a warning', () {
      final (cal, problems) = HijriCalendar.withMonthStarts({
        (year: 1447, month: 9): d(2026, 2, 25), // a week off
        (year: 1447, month: 13): d(2026, 3, 1), // no such month
        (year: 1700, month: 1): d(2276, 1, 1), // past the table
        (year: 1447, month: 10): d(2026, 3, 22), // two days late: Ramadan 32 days
      });
      expect(
        [for (final p in problems) '${p.severity.name} ${p.path}'],
        [
          'error monthStarts[1447-09]',
          'error monthStarts[1447-13]',
          'error monthStarts[1700-01]',
          'warning monthStarts[1447-09]',
          'warning monthStarts[1447-10]', // and Shawwal two days shorter
        ],
      );
      expect(cal.monthStart(1447, 9), d(2026, 2, 18));
      expect(cal.monthLength(1447, 9), 32);
    });

    test('two starts the wrong way round: the second is left out', () {
      final (cal, problems) = HijriCalendar.withMonthStarts({
        (year: 1447, month: 9): d(2026, 2, 20),
        (year: 1447, month: 10): d(2026, 2, 20),
      });
      expect([for (final p in problems) p.path], contains('monthStarts[1447-10]'));
      expect(cal.monthStart(1447, 10), d(2026, 3, 20));
    });
  });

  group('formatting (decision 53)', () {
    test('a day, a month, the era after the year; English names for a language without them', () {
      final x = uq.fromDate(d(2026, 2, 18));
      expect(formatTemporal(x, 'yMMMMEEEEd', 'en'), 'Wednesday, Ramadan 1, 1447 AH');
      expect(formatTemporal(x, 'yMMMMd', 'fr'), '1 ramadan 1447 AH');
      expect(formatTemporal(x, 'yMMMM', 'ar'), 'رمضان 1447 هـ');
      expect(formatTemporal(x, 'd', 'fr'), '1');
      expect(formatTemporal(x, 'MMMd', 'de'), '1. Ram.');
    });

    test('ranges: what both ends share said once; an abbreviation keeps its point', () {
      final a = uq.fromDate(d(2026, 2, 18));
      expect(formatRangeTitle(a, uq.fromDate(d(2026, 2, 24)), 'yMMMd', 'fr'), '1–7 ram. 1447 AH');
      expect(formatRangeTitle(a, uq.fromDate(d(2026, 3, 22)), 'yMMMd', 'fr'), '1 ram. – 3 chaw. 1447 AH');
      // The same for the Gregorian calendar: "janv.–févr.", no longer "janv–févr.".
      expect(formatRangeTitle(d(2026, 1, 5), d(2026, 2, 3), 'yMMM', 'fr'), 'janv.–févr. 2026');
      expect(formatRangeTitle(d(2026, 1, 5), d(2026, 2, 3), 'yMMMd', 'en'), 'Jan 5 – Feb 3, 2026');
    });
  });

  group('the kernel: titles in the display calendar, the secondary beside', () {
    CalendarKernel kernel(String view, PlainDate at, {String locale = 'fr'}) => CalendarKernel(
      KernelOptions(
        timeZone: 'Africa/Algiers',
        locale: locale,
        initialView: view,
        initialDate: at,
        displayCalendar: uq,
      ),
    );

    test('a week, a month, a day, a year', () {
      // Monday 16 February 2026 is 28 Shaban; Sunday 22 is 5 Ramadan.
      expect(kernel('timeGridWeek', d(2026, 2, 18)).state.title, '28 chaa. – 5 ram. 1447 AH');
      // February 2026: 13 Shaban to 11 Ramadan.
      expect(kernel('dayGridMonth', d(2026, 2, 18)).state.title, 'chaa.–ram. 1447 AH');
      expect(kernel('timeGridDay', d(2026, 2, 18), locale: 'en').state.title, 'Wednesday, Ramadan 1, 1447 AH');
      // 2026 runs from 12 Rajab 1447 into 1448.
      expect(kernel('multiMonthYear', d(2026, 2, 18)).state.title, '1447–1448 AH');
    });

    test('set and cleared: the title follows, one state event (cause calendar); the same again says nothing', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: 'Africa/Algiers',
          locale: 'fr',
          initialView: 'timeGridDay',
          initialDate: d(2026, 2, 18),
        ),
      );
      final causes = <StateCause>[];
      k.subscribe((e) {
        if (e is KernelStateEvent) causes.addAll(e.causes);
      });
      expect(k.state.title, 'mercredi 18 février 2026');
      k.setDisplayCalendar(uq);
      expect(k.state.title, 'mercredi 1 ramadan 1447 AH');
      k.setDisplayCalendar(HijriCalendar.withMonthStarts({}).$1);
      expect(causes, [StateCause.calendar]);
      k.setDisplayCalendar(null);
      expect(k.state.title, 'mercredi 18 février 2026');
      k.setSecondaryCalendar(uq);
      expect(k.state.formatDate(d(2026, 2, 18), 'd'), '18');
      expect(k.state.formatSecondary(d(2026, 2, 18), 'd'), '1');
      expect(k.state.formatSecondary(d(2026, 2, 18), 'MMMd'), '1 ram.');
      expect(causes, [StateCause.calendar, StateCause.calendar, StateCause.calendar]);
    });

    test('Algeria\'s Ramadan a day later: the title says so', () {
      final (dz, _) = HijriCalendar.withMonthStarts({(year: 1447, month: 9): d(2026, 2, 19)});
      final k = kernel('timeGridDay', d(2026, 2, 19));
      k.setDisplayCalendar(dz);
      expect(k.state.title, 'jeudi 1 ramadan 1447 AH');
    });
  });

  group('after the 19h-1 reviews', () {
    test('a locale whose day has a suffix keeps its digits; the era after what is glued to the year', () {
      final x = uq.fromDate(d(2026, 2, 18));
      final ja = formatTemporal(x, 'yMMMMd', 'ja');
      expect(ja, contains('1447年'));
      expect(ja, contains('9月1日'));
      expect(ja, isNot(contains('AH年')));
      expect(formatRangeTitle(d(2026, 3, 15), d(2026, 3, 21), 'yMMMd', 'de'), '15.–21. März 2026');
    });

    test('1 Muharram 1300, where the table meets the civil reckoning, cannot be moved', () {
      final (cal, problems) = HijriCalendar.withMonthStarts({(year: 1300, month: 1): d(1882, 11, 13)});
      expect([for (final p in problems) p.path], ['monthStarts[1300-01]']);
      expect(cal, uq);
    });

    test('a civil calendar corrected on a year\'s first month: one day, one date, both ways', () {
      final civil = HijriCalendar.civil;
      final moved = civil.monthStart(1447, 1).addDays(1);
      final (cal, problems) = HijriCalendar.withMonthStarts({
        (year: 1447, month: 1): moved,
      }, reckoning: HijriReckoning.civil);
      expect(problems.where((p) => p.severity == Severity.error), isEmpty);
      for (var day = moved.addDays(-40); day.isBefore(moved.addDays(40)); day = day.addDays(1)) {
        final x = cal.fromDate(day);
        expect(cal.toDate(x.year, x.month, x.day), day, reason: '$day');
      }
      expect(h(cal.fromDate(moved)), '1447-1-1');
      expect(cal.monthLength(1446, 12), civil.monthLength(1446, 12) + 1);
    });

    test('a civil year far away is refused, not a list of billions', () {
      final (cal, problems) = HijriCalendar.withMonthStarts({
        (year: 1000000000, month: 1): d(2026, 1, 1),
      }, reckoning: HijriReckoning.civil);
      expect(problems.single.path, 'monthStarts[1000000000-01]');
      expect(cal, HijriCalendar.civil);
    });

    test('two corrected months in a row: one warning per month', () {
      final (_, problems) = HijriCalendar.withMonthStarts({
        (year: 1447, month: 9): d(2026, 2, 20),
        (year: 1447, month: 10): d(2026, 3, 18),
      });
      final paths = [for (final p in problems) p.path];
      expect(paths.toSet().length, paths.length);
    });

    test('a Hijri day equal only on the same Gregorian day; a bad month for monthStart is the caller\'s', () {
      final (dz, _) = HijriCalendar.withMonthStarts({(year: 1447, month: 9): d(2026, 2, 19)});
      expect(uq.fromDate(d(2026, 2, 18)), isNot(dz.fromDate(d(2026, 2, 19))));
      expect(uq.fromDate(d(2026, 2, 18)), uq.fromDate(d(2026, 2, 18)));
      expect(() => uq.monthStart(1447, 13), throwsArgumentError);
      expect(() => formatRangeTitle(uq.fromDate(d(2026, 2, 18)), d(2026, 2, 19), 'yMMMd', 'fr'), throwsArgumentError);
    });
  });
}
