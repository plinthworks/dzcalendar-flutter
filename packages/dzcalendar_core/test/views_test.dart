// Ported from the TypeScript core's views.test.ts (hand-written expectations,
// copied as values).
//
// Ported: the computeViewRange tests (5) and the navigate tests (4).
// Skipped, not in the port yet:
// - 'view models' (7 tests: buildTimeGridModel, buildDayGridModel, the event store)
// - 'formatting' (6 tests: formatRangeTitle, formatTemporal, weekdayNames,
//   monthNames, weekNumber, weekRulesFor, which need Intl-like formatting)

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:test/test.dart';

PlainDate d(String s) => PlainDate.parse(s);

final mon = NavContext(firstDay: 1, today: d('2026-10-16'));
final sun = NavContext(firstDay: 7, today: d('2026-10-16'));

List<String> str(Iterable<Object> xs) => [for (final x in xs) '$x'];

ViewSpec view(String type) => builtinViews[type]!;

void main() {
  group('computeViewRange', () {
    test('a month grid: six weeks from the locale’s first weekday', () {
      final r = computeViewRange(d('2026-02-14'), view('dayGridMonth'), mon);
      expect(['${r.start}', '${r.end}', r.weeks.length], ['2026-01-26', '2026-03-09', 6]);
      expect(['${r.activeStart}', '${r.activeEnd}'], ['2026-02-01', '2026-03-01']);
      expect('${computeViewRange(d('2026-02-14'), view('dayGridMonth'), sun).start}', '2026-02-01');
    });

    test('fixedWeekCount: false keeps only the weeks the month touches (February 2026 from Sunday: four)', () {
      final spec = view('dayGridMonth').copyWith(fixedWeekCount: false);
      expect(computeViewRange(d('2026-02-14'), spec, sun).weeks.length, 4);
    });

    test('a week starts on the first weekday; hidden days are left out', () {
      final spec = view('timeGridWeek').copyWith(hiddenDays: [6, 7]);
      final r = computeViewRange(d('2026-10-25'), spec, mon);
      expect(str(r.dates), ['2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22', '2026-10-23']);
      expect('${computeViewRange(d('2026-10-25'), view('timeGridWeek'), sun).start}', '2026-10-25');
    });

    test('dayCount counts shown days', () {
      final spec = view(
        'timeGridDay',
      ).copyWith(type: 'fourWorkDays', duration: IsoDuration(days: 4), dayCount: 4, hiddenDays: [6, 7]);
      expect(str(computeViewRange(d('2026-10-15'), spec, mon).dates), [
        '2026-10-15',
        '2026-10-16',
        '2026-10-19',
        '2026-10-20',
      ]);
    });

    test('every day hidden is a configuration error, said once', () {
      expect(
        () => computeViewRange(d('2026-10-15'), view('timeGridWeek').copyWith(hiddenDays: [1, 2, 3, 4, 5, 6, 7]), mon),
        throwsArgumentError,
      );
    });
  });

  group('navigate', () {
    test('months step from the 1st: 31 January → February', () {
      expect('${navigate(d('2026-01-31'), view('dayGridMonth'), NavDirection.next, mon)}', '2026-02-01');
      expect('${navigate(d('2026-03-31'), view('dayGridMonth'), NavDirection.prev, mon)}', '2026-02-01');
    });

    test('weeks, days, today, to', () {
      expect('${navigate(d('2026-10-21'), view('timeGridWeek'), NavDirection.next, mon)}', '2026-10-28');
      expect('${navigate(d('2026-10-21'), view('timeGridDay'), NavDirection.prev, mon)}', '2026-10-20');
      expect('${navigate(d('2020-01-01'), view('timeGridDay'), NavDirection.today, mon)}', '2026-10-16');
      expect('${navigate(d('2020-01-01'), view('timeGridDay'), NavDirection.to(d('2026-12-25')), mon)}', '2026-12-25');
    });

    test('a one-day view steps over hidden days both ways', () {
      final spec = view('timeGridDay').copyWith(hiddenDays: [6, 7]);
      expect('${navigate(d('2026-10-19'), spec, NavDirection.prev, mon)}', '2026-10-16'); // Monday → Friday
      expect('${navigate(d('2026-10-16'), spec, NavDirection.next, mon)}', '2026-10-19'); // Friday → Monday
    });

    test('a dayCount view steps by shown days, both ways', () {
      final spec = view('timeGridDay').copyWith(duration: IsoDuration(days: 4), dayCount: 4, hiddenDays: [6, 7]);
      final next = navigate(d('2026-10-15'), spec, NavDirection.next, mon);
      expect('$next', '2026-10-21');
      expect('${navigate(next, spec, NavDirection.prev, mon)}', '2026-10-15');
    });
  });
}
