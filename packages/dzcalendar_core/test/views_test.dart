// Ported from the TypeScript core's views.test.ts (hand-written expectations,
// copied as values).
//
// Ported: the computeViewRange tests (5), the navigate tests (4), the
// 'view models' tests (7, in 19e-1) and 'formatting' (6, in 19e-1).
// Skipped: none.
// Translation notes for 'formatting': the TS's `Intl.DateTimeFormat` options
// are ICU skeletons here (`{ day, month: 'long', year }` is `yMMMMd`,
// `{ hour: '2-digit', minute: '2-digit' }` is `Hm`), formatted by intl's
// CLDR data (decision 24). The strings asserted are the same as the web's
// (after its thin spaces are read as spaces). `x.weekOfYear` (Temporal's ISO
// week) is computed by the Thursday rule — the week holds its Thursday's
// year, counted from that year's first Thursday — independently of
// `weekNumber`. Other notes: `slotMin: 'PT8H'` is `Duration(hours: 8)`; the events'
// `display: 'background'` is `EventDisplay.background`; `duration: {minutes:
// 30}` is kept as the map EventInput reads.

import 'package:dzcalendar_core/internal.dart';
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

  group('view models', () {
    StoreSnapshot store(List<EventInput> inputs) {
      final s = EventStore();
      s.replaceSourceChunk(
        't',
        'all',
        normalizeMany(
          inputs,
          NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('v')),
          sourceId: 't',
        ).items,
      );
      return s.snapshot;
    }

    String offsetOf(CalEvent e) => e is TimedEvent ? e.start.offset : '';

    test('time grid, the 25-hour Sunday: the two 02:30s sit side by side, each with its offset', () {
      final snap = store([
        EventInput(id: 'first', start: '2026-10-25T02:30+02:00[Europe/Paris]', duration: {'minutes': 30}),
        EventInput(id: 'second', start: '2026-10-25T02:30+01:00[Europe/Paris]', duration: {'minutes': 30}),
      ]);
      final model = buildTimeGridModel(
        computeViewRange(d('2026-10-25'), view('timeGridDay'), mon),
        snap,
        const TimeGridOptions(displayZone: 'Europe/Paris'),
      );
      final col = model.columns.first;
      expect([for (final b in col.axis.bands) b.kind], [TransitionKind.repeat]);
      expect(
        [
          for (final e in col.events)
            [e.segment.instance.key, e.top, e.height, e.left, e.width, offsetOf(e.segment.instance.event)],
        ],
        [
          ['first', 150, 30, 0, 0.5, '+02:00'],
          ['second', 150, 30, 0.5, 0.5, '+01:00'],
        ],
      );
    });

    test('time grid, elapsed axis: the same two events do not overlap', () {
      final snap = store([
        EventInput(id: 'first', start: '2026-10-25T02:30+02:00[Europe/Paris]', duration: {'minutes': 30}),
        EventInput(id: 'second', start: '2026-10-25T02:30+01:00[Europe/Paris]', duration: {'minutes': 30}),
      ]);
      final model = buildTimeGridModel(
        computeViewRange(d('2026-10-25'), view('timeGridDay'), mon),
        snap,
        const TimeGridOptions(displayZone: 'Europe/Paris', axis: AxisMode.elapsed),
      );
      expect(
        [
          for (final e in model.columns.first.events) [e.top, e.width],
        ],
        [
          [150, 1],
          [210, 1],
        ],
      );
    });

    test('time grid: an event across the fall-back is drawn in two parts, both the right way up', () {
      final snap = store([
        EventInput(id: 'x', start: '2026-10-25T02:50+02:00[Europe/Paris]', end: '2026-10-25T02:10+01:00[Europe/Paris]'),
      ]);
      final model = buildTimeGridModel(
        computeViewRange(d('2026-10-25'), view('timeGridDay'), mon),
        snap,
        const TimeGridOptions(displayZone: 'Europe/Paris', minEventMinutes: 0),
      );
      expect(
        [
          for (final e in model.columns.first.events) [e.top, e.height],
        ],
        [
          [120, 10],
          [170, 10],
        ],
      );
    });

    test('time grid 08:00–20:00: events outside are not drawn; one cut by the edge loses that rounded end', () {
      final snap = store([
        EventInput(id: 'night', start: '2026-05-04T22:00[Europe/Paris]'),
        EventInput(id: 'early', start: '2026-05-04T07:00[Europe/Paris]', end: '2026-05-04T09:00[Europe/Paris]'),
        EventInput(id: 'edge', start: '2026-05-04T08:00[Europe/Paris]', end: '2026-05-04T08:00[Europe/Paris]'),
      ]);
      final model = buildTimeGridModel(
        computeViewRange(d('2026-05-04'), view('timeGridDay'), mon),
        snap,
        const TimeGridOptions(displayZone: 'Europe/Paris', slotMin: Duration(hours: 8), slotMax: Duration(hours: 20)),
      );
      expect(
        [
          for (final e in model.columns.first.events)
            [e.segment.instance.key, e.top, e.height, e.segment.startsHere, e.segment.endsHere],
        ],
        [
          ['early', 0, 60, false, true],
          ['edge', 0, 0, true, true],
        ],
      );
    });

    test('background events take no lane and never push a real event behind "+N"', () {
      final snap = store([
        EventInput(id: 'bgAllDay', start: '2026-10-20', end: '2026-10-23', display: EventDisplay.background),
        EventInput(
          id: 'bgTimed',
          start: '2026-10-21T09:00[Europe/Paris]',
          end: '2026-10-21T11:00[Europe/Paris]',
          display: EventDisplay.background,
        ),
        EventInput(id: 'normal', start: '2026-10-21'),
      ]);
      final range = computeViewRange(d('2026-10-21'), view('dayGridWeek'), mon);
      final week = buildDayGridModel(
        range,
        snap,
        const DayGridOptions(displayZone: 'Europe/Paris', maxLanes: 2),
      ).weeks.first;
      expect(
        [
          for (final b in week.bars) [b.segment.instance.key, b.lane],
        ],
        [
          ['normal', 0],
        ],
      );
      expect(week.hiddenPerDay.every((n) => n == 0), isTrue);
      expect([for (final s in week.background) s.instance.key]..sort(), ['bgAllDay', 'bgTimed']);
      final tg = buildTimeGridModel(
        computeViewRange(d('2026-10-21'), view('timeGridWeek'), mon),
        snap,
        const TimeGridOptions(displayZone: 'Europe/Paris'),
      );
      expect(
        [
          tg.allDay.lanes,
          [for (final b in tg.allDay.bars) b.segment.instance.key],
          [for (final b in tg.allDay.background) b.segment.instance.key],
        ],
        [
          1,
          ['normal'],
          ['bgAllDay'],
        ],
      );
    });

    test('time grid: all-day events go to the row above, packed in lanes', () {
      final snap = store([
        EventInput(id: 'a', start: '2026-10-19', end: '2026-10-22'),
        EventInput(id: 'b', start: '2026-10-20'),
      ]);
      final model = buildTimeGridModel(
        computeViewRange(d('2026-10-20'), view('timeGridWeek'), mon),
        snap,
        const TimeGridOptions(displayZone: 'Europe/Paris'),
      );
      expect(
        [
          model.allDay.lanes,
          [
            for (final b in model.allDay.bars) [b.segment.instance.key, b.segment.dayIndex, b.segment.dayCount, b.lane],
          ],
        ],
        [
          2,
          [
            ['a', 0, 3, 0],
            ['b', 1, 1, 1],
          ],
        ],
      );
    });

    test('day grid with +N: what does not fit is counted per day, nothing lost', () {
      final inputs = [
        for (var i = 0; i < 5; i++) EventInput(id: 'e$i', title: '$i', start: '2026-10-21T0${i + 1}:00[Europe/Paris]'),
      ];
      final model = buildDayGridModel(
        computeViewRange(d('2026-10-21'), view('dayGridMonth'), mon),
        store(inputs),
        const DayGridOptions(displayZone: 'Europe/Paris', maxLanes: 3),
      );
      final week = model.weeks.firstWhere((w) => w.dates.any((x) => '$x' == '2026-10-21'));
      final col = week.dates.indexWhere((x) => '$x' == '2026-10-21');
      expect(week.hiddenPerDay[col], 3); // lanes 0,1 drawn; the 3rd lane gives way to "+3"
      expect(week.bars.where((b) => b.pieces.any((p) => p.from <= col && col < p.to)), hasLength(2));
    });
  });

  group('formatting', () {
    test('titles use range formatting', () {
      expect(formatRangeTitle(d('2026-03-15'), d('2026-03-21'), 'yMMMMd', 'fr-FR'), '15–21 mars 2026');
      expect(formatRangeTitle(d('2026-03-30'), d('2026-04-05'), 'yMMMd', 'en-US'), 'Mar 30 – Apr 5, 2026');
    });

    test('ends given the wrong way round still make the right title', () {
      expect(formatRangeTitle(d('2026-03-21'), d('2026-03-15'), 'yMMMMd', 'fr-FR'), '15–21 mars 2026');
    });

    test('a zoned time prints in its own zone, a plain date never shifts', () {
      expect(formatTemporal(ZonedDateTime.tryParse('2026-10-25T02:30+01:00[Europe/Paris]')!, 'Hm', 'fr-FR'), '02:30');
      expect(formatTemporal(d('2026-01-01'), 'MMMMd', 'en-US'), 'January 1');
      expect(formatTemporal(PlainTime(9, 5), 'Hm', 'en-GB'), '09:05');
    });

    test('weekday and month names follow the locale and the first day', () {
      expect(weekdayNames('en-US', NameWidth.short, 7), ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']);
      expect(monthNames('fr-FR', NameWidth.long)[0], 'janvier');
    });

    test('week numbers: 1 January 2027 is ISO week 53 of 2026, but week 1 in the US', () {
      final fri = d('2027-01-01');
      expect(weekNumber(fri, weekRulesFor('fr-FR')), isoWeek(fri));
      expect(weekNumber(fri, weekRulesFor('fr-FR')), 53);
      expect(weekNumber(fri, weekRulesFor('en-US')), 1);
      // US: the week holding 1 January is week 1, and it starts Sunday 27 December.
      expect(weekNumber(d('2026-12-27'), weekRulesFor('en-US')), 1);
      expect(weekNumber(d('2026-12-26'), weekRulesFor('en-US')), 52);
    });

    test('week numbers agree with ISO weeks over ten years', () {
      const iso = WeekRules(firstDay: 1, minimalDays: 4);
      for (var x = d('2020-01-01'); x.isBefore(d('2030-01-01')); x = x.addDays(1)) {
        expect(weekNumber(x, iso), isoWeek(x), reason: '$x');
      }
    });
  });
}

/// ISO 8601's week number by its Thursday rule: a week belongs to the year
/// of its Thursday, and is counted from that year's first one.
int isoWeek(PlainDate x) {
  final thursday = x.addDays(4 - x.dayOfWeek);
  return PlainDate(thursday.year, 1, 1).daysUntil(thursday) ~/ 7 + 1;
}
