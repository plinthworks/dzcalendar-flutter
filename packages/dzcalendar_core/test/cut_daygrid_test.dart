import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

/// A renderer fitting a month to its height cuts the uncut model itself: the
/// result must be the model the kernel would build with that `maxLanes`.
void main() {
  final kernel = CalendarKernel(
    KernelOptions(
      timeZone: 'Europe/Paris',
      locale: 'fr',
      initialDate: PlainDate(2026, 11, 9),
      initialView: 'dayGridMonth',
      // Tuesday 10 November: four timed events, and a three-day bar Monday–Wednesday.
      events: [
        EventInput(id: 'long', title: 'Congrès', start: '2026-11-09', end: '2026-11-12', allDay: true),
        for (var i = 0; i < 4; i++)
          EventInput(id: 'e$i', title: 'Rdv $i', start: '2026-11-10T0${i + 1}:00', end: '2026-11-10T0${i + 1}:30'),
      ],
    ),
  );

  DayGridModel build(int? max) =>
      (kernel.modelAt('dayGridMonth', PlainDate(2026, 11, 9), dayGrid: DayGridSettings(maxLanes: max))!
              as DayGridViewModel)
          .model;

  for (final max in [1, 2, 3, 5]) {
    test('cut to $max lanes = built with maxLanes $max', () {
      final cut = cutDayGridModel(build(null), max);
      final built = build(max);
      expect(cut.maxLanes, max);
      for (var w = 0; w < built.weeks.length; w++) {
        final a = cut.weeks[w];
        final b = built.weeks[w];
        expect(a.hiddenKeysPerDay, b.hiddenKeysPerDay, reason: 'week $w');
        expect(
          [for (final x in a.bars) (x.segment.key, x.lane, "${x.pieces}")],
          [for (final x in b.bars) (x.segment.key, x.lane, "${x.pieces}")],
          reason: 'week $w',
        );
      }
    });
  }

  test('3 lanes on Tuesday: the long bar and Rdv 0 shown, "+3" for Rdv 1–3', () {
    final cut = cutDayGridModel(build(null), 3);
    final week = cut.weeks.firstWhere((w) => w.dates.contains(PlainDate(2026, 11, 10)));
    final tuesday = week.dates.indexOf(PlainDate(2026, 11, 10));
    // Lanes: the 3-day bar 0, Rdv 0 → 1, Rdv 1 → 2, … ; 3 lanes with a spill keep 2.
    expect(week.hiddenKeysPerDay[tuesday].length, 3);
    // The long bar stays whole: Monday and Wednesday do not spill, Tuesday shows lane 0.
    final long = week.bars.firstWhere((b) => b.segment.instance.event.id == 'long');
    expect(long.pieces, [(from: tuesday - 1, to: tuesday + 2)]);
  });

  test("the application's maxLanes stands; under 1 is configuration", () {
    final appSet = build(4);
    expect(identical(cutDayGridModel(appSet, 2), appSet), isTrue);
    expect(() => cutDayGridModel(build(null), 0), throwsArgumentError);
  });
}
