# Changelog

Versions follow [semantic versioning](https://semver.org). `dzcalendar_core`
and `dzcalendar` are released together under the same number.

## 1.1.0

No change in the core: released with `dzcalendar` 1.1.0 (both packages
carry the same number).

## 1.0.0

First release: the Dart port of [DzCalendar](https://github.com/plinthworks/dzcalendar)'s
core, checked against its language-independent conformance cases.

- Time types (`Instant`, `PlainDate`, `PlainTime`, `PlainDateTime`,
  `ZonedDateTime`) and the IANA zone rules, bundled: days of 23, 25 or 23½
  hours, skipped and repeated wall times.
- Events that keep their own zone, read leniently: bad input becomes a
  `Problem`, never an exception.
- Recurrence (RRULE, EXDATE, RDATE), series edited for one occurrence, the
  following ones or all.
- The event store, commands, undo and redo.
- The calendar kernel: views (time grid, day grid, list, multi-month,
  resource timeline), navigation, resources, business hours, constraints.
- Event sources fetched as the calendar moves: functions, JSON over HTTP,
  live feeds, writing edits back.
- Bookable slots (`package:dzcalendar_core/slots.dart`), iCalendar import and
  export (`ical.dart`), the Hijri calendar.
