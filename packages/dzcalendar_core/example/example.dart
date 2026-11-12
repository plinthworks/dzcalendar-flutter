// dzcalendar_core without Flutter: days that are not 24 hours long, and the
// bookable slots of a practice, in its own zone.
//
//   dart run example/example.dart
import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:dzcalendar_core/slots.dart';

void main() {
  // Days as long as they are: Paris falls back on 25 October 2026.
  for (final date in [PlainDate(2026, 10, 24), PlainDate(2026, 10, 25)]) {
    final day = dayInfo(date, 'Europe/Paris');
    print('$date in Paris: ${day.lengthMinutes ~/ 60} h');
  }

  // A practice in Algiers open 9–12 on weekdays, 30-minute slots, one busy
  // hour, booked at least an hour ahead.
  Instant algiers(PlainTime time) =>
      ZonedDateTime.fromWall(PlainDateTime(PlainDate(2026, 11, 16), time), 'Africa/Algiers')!.instant;
  final now = algiers(PlainTime(8));
  final rules = SlotRules(
    availability: Availability(
      timeZone: 'Africa/Algiers',
      weekly: [
        WeeklyWindow(days: const [1, 2, 3, 4, 5], window: const Window(WallTime(9), WallTime(12))),
      ],
    ),
    duration: const Duration(minutes: 30),
    now: now,
    minNotice: const Duration(hours: 1),
    busy: [Busy(start: algiers(PlainTime(10)), end: algiers(PlainTime(11)))],
  );
  final result = findSlots(rules, from: now, to: now.add(const Duration(days: 1)));
  for (final slot in result.slots) {
    print('free: ${slot.start.plainDateTime.time}–${slot.end.plainDateTime.time} (${slot.start.zone})');
  }

  // Bad input never throws: it is reported.
  final report = normalizeEvent(
    EventInput(title: 'No start'),
    NormalizeContext(displayZone: 'Africa/Algiers', newId: createIdGenerator()),
  );
  for (final problem in report.problems) {
    print('problem: ${problem.code.name} at ${problem.path}');
  }
}
