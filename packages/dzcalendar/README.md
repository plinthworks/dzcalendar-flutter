# dzcalendar

Flutter calendar widgets where **every event keeps its own time zone**: month,
week, day, list, year, resource columns, a resource timeline, a mini month and
a slot picker. Days of 23 or 25 hours are drawn as they are: the skipped hour
as a band, the repeated one twice.

Built on [`dzcalendar_core`](https://pub.dev/packages/dzcalendar_core), the
Dart port of [DzCalendar](https://github.com/plinthworks/dzcalendar), so the
phone and the web give the same answers.

- Edit by touch, mouse and keyboard: long press to hold an event, then move
  it, resize it, or use its menu; select a span to create; undo and redo.
- Screen readers: every event and slot is said, and can be moved without a
  drag.
- French, English and Arabic (right to left); a secondary Hijri calendar.
- Light and dark from the app's `ColorScheme`, tuned with `DzCalendarTheme`.
- Events from memory, from a function, JSON over HTTP, a live feed or
  iCalendar, fetched as the calendar moves.

## Install

```yaml
dependencies:
  dzcalendar: ^1.0.0
  flutter_localizations:
    sdk: flutter
```

## A calendar

```dart
import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    localizationsDelegates: [
      DzCalendarLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: [Locale('fr'), Locale('en'), Locale('ar')],
    home: Agenda(),
  );
}

class Agenda extends StatefulWidget {
  const Agenda({super.key});

  @override
  State<Agenda> createState() => _AgendaState();
}

class _AgendaState extends State<Agenda> {
  late final _controller = CalendarController(
    KernelOptions(
      timeZone: 'Africa/Algiers', // where the calendar is read
      locale: 'fr', // then follows the app's locale
      initialView: 'timeGridWeek',
      events: [
        EventInput(id: 'c1', title: 'Consultation', start: '2026-11-16T09:00', end: '2026-11-16T09:30'),
        // Keeps its own zone: 10:00 in Paris is 10:00 in Algiers in winter, 09:00 in summer.
        EventInput(
          id: 'v1',
          title: 'Visio',
          start: '2026-11-17T10:00',
          end: '2026-11-17T11:00',
          timeZone: 'Europe/Paris',
        ),
      ],
    ),
    onEventChange: (change) {
      // A person moved or resized an event: send change.after to the server,
      // or call change.revert() if it refuses.
    },
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: DzCalendar(controller: _controller, editable: true)),
  );
}
```

`DzCalendar(views: [...])` picks the views offered: `dayGridMonth`,
`timeGridWeek`, `timeGridDay`, `listWeek`, `multiMonthYear`,
`resourceTimeGridDay`, `resourceTimelineDay`, `resourceTimelineWeek`… Resources
are given with `KernelOptions(resources: [ResourceInput(...)])`.

## Picking a slot

`SlotPicker` works alone, on the app's own objects: say when each one starts
and ends, and in which zone the days are read.

```dart
class FreeSlot {
  const FreeSlot(this.date, this.startTime, this.endTime);
  final String date; // '2026-11-16'
  final String startTime; // '09:00'
  final String endTime; // '09:30'
}

Instant at(String date, String time) =>
    ZonedDateTime.fromWall(PlainDateTime(PlainDate.parse(date), PlainTime.parse(time)), 'Africa/Algiers')!.instant;

Widget picker(List<FreeSlot> slots, FreeSlot? picked, ValueChanged<FreeSlot> onPicked) => SlotPicker<FreeSlot>(
  items: slots,
  startOf: (s) => at(s.date, s.startTime),
  endOf: (s) => at(s.date, s.endTime),
  displayZone: 'Africa/Algiers',
  selected: picked,
  onSelected: onPicked,
);
```

To compute the slots on the phone instead, `findSlots` (exported here) cuts a
provider's weekly hours, minus what is busy, into slots;
`SlotPicker.fromSlots` shows them.

## The example

[`example/`](example) is a phone app showing every view, for the iOS
simulator and an Android emulator.

## Versions

[Semantic versioning](https://semver.org): a fix raises the patch, an
addition the minor, a break the major. `dzcalendar` and `dzcalendar_core` are
released together under the same number.

What may come in a **minor** version: a new word in
`DzCalendarLocalizations` (with its English text, so a class extending it
still compiles), a new enum value, a new kind of `KernelEvent`, `ViewModel` or
`SourceNotice` — keep a default branch when you `switch` on them. A `sealed`
class (`Command`, `Hit`, `CalEvent`…) is closed: a new case is a major
version.

`dzcalendar` asks for exactly its own version of `dzcalendar_core`. Most apps
need only `dzcalendar`, which exports what goes with the widgets; to use more
of the core (`package:dzcalendar_core/ical.dart`, …), add `dzcalendar_core`
with the same version.

## License

MIT.
