# dzcalendar_core

A calendar engine in pure Dart where **every event keeps its own time zone**.
A consultation booked at 10:00 in Paris stays at 10:00 in Paris, wherever the
calendar is read; a day of 23 or 25 hours is as long as it is.

This is the core of [`dzcalendar`](https://pub.dev/packages/dzcalendar), the
Flutter widgets, and works without Flutter: on a server, in a CLI, in tests.
It is the Dart port of [DzCalendar](https://github.com/plinthworks/dzcalendar),
checked against the same language-independent conformance cases, so the web
and the phone give the same answers.

## What is in it

- **Time**: `Instant`, `PlainDate`, `PlainTime`, `PlainDateTime`,
  `ZonedDateTime`, and the IANA zone rules, bundled (no loading step).
  `dayInfo` tells how long a day is; skipped and repeated wall times are
  resolved the way Temporal does.
- **Events** that keep their own zone, read leniently: bad input never
  throws, it becomes a `Problem` (a code and where).
- **Recurrence**: RRULE, EXDATE, RDATE; edit one occurrence, the following
  ones or the whole series.
- **The store, commands, undo and redo.**
- **The kernel** (`CalendarKernel`): views, navigation, resources, business
  hours, constraints, event sources fetched as the calendar moves.
- **Bookable slots** (`package:dzcalendar_core/slots.dart`): weekly hours in
  the provider's zone, minus what is busy, cut into slots with buffers,
  notice and a horizon.
- **iCalendar** import and export (`package:dzcalendar_core/ical.dart`).
- **The Hijri calendar** (Umm al-Qura and tabular).

## Install

```yaml
dependencies:
  dzcalendar_core: ^1.0.0
```

## Example

```dart
import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:dzcalendar_core/slots.dart';

void main() {
  // Paris falls back on 25 October 2026: that day lasts 25 hours.
  print(dayInfo(PlainDate(2026, 10, 25), 'Europe/Paris').lengthMinutes / 60); // 25.0

  // A practice in Algiers open 9–12 on weekdays, 30-minute slots.
  Instant algiers(int hour) =>
      ZonedDateTime.fromWall(PlainDateTime(PlainDate(2026, 11, 16), PlainTime(hour)), 'Africa/Algiers')!.instant;
  final rules = SlotRules(
    availability: Availability(
      timeZone: 'Africa/Algiers',
      weekly: [WeeklyWindow(days: const [1, 2, 3, 4, 5], window: const Window(WallTime(9), WallTime(12)))],
    ),
    duration: const Duration(minutes: 30),
    now: algiers(8),
    busy: [Busy(start: algiers(10), end: algiers(11))],
  );
  for (final slot in findSlots(rules, from: algiers(8), to: algiers(20)).slots) {
    print(slot.start); // 2026-11-16T09:00:00+01:00[Africa/Algiers], then 09:30, 11:00, 11:30
  }
}
```

The whole example is in [`example/example.dart`](example/example.dart).

## Versions

[Semantic versioning](https://semver.org): a fix raises the patch, an
addition the minor, a break the major. `dzcalendar_core` and `dzcalendar`
are released together under the same number.

What may come in a **minor** version, so keep a default branch when you
`switch` on these: a new value of an enum (`ProblemCode`, `ViolationCode`,
`SlotRefusal`…); a new kind of `KernelEvent`, `ViewModel` or `SourceNotice`
(they are `abstract`, not `sealed`). A `sealed` class (`Command`, `Mutation`,
`SourceEdit`, `Hit`, `CalEvent`…) is closed: a new case is a major version, so
a `switch` on it can be exhaustive.

`package:dzcalendar_core/internal.dart` holds the engine's working parts for
the Flutter package and the tests. It is **outside** that promise: anything in
it may change in any version.

## License

MIT.
