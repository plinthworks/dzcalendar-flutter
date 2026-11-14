# Changelog

Versions follow [semantic versioning](https://semver.org). `dzcalendar` and
`dzcalendar_core` are released together under the same number.

## 1.1.0

Screen readers and large text, found by the first app on the widgets.

- A screen reader can now activate what it reads: a `SlotPicker` day and
  time, a `MiniMonth` day, a month or year day, a year's month title, the
  "+N" links of the month, week and timeline, a free slot (when
  `onSlotTap` is set). An event in a list or a day's sheet has its menu
  on a long press, as in the grids.
- The wordless backgrounds (a time-grid column, an all-day cell, a
  timeline row) are hidden from screen readers: a double tap there
  created at a time nobody chose.
- `SlotPicker`: the day strip grows with the text instead of
  overflowing; given a bounded height, the days stay on top and the
  times scroll under them.
- `CalendarHeader`: when the title and the view's name do not both fit,
  the view switcher shows an icon only, and the title keeps its room.
- Month: the day numbers and event bars grow with the text (fewer bars,
  then "+N"), a day number too wide for its column shrinks, and the
  weekday names become single letters when nothing else fits.
- Week and day: all-day bars grow with the text; an event shorter than a
  line (15 minutes) is cut instead of overflowing.

## 1.0.0

First release: Flutter widgets over `dzcalendar_core`.

- `DzCalendar`: month, week, day, list, year, resource columns and the
  resource timeline, driven by a `CalendarController`.
- Editing by touch, mouse and keyboard: move, resize, create by selection,
  menus, undo; a landing motion; refusals said.
- Screen readers: every event and slot is said, and can be moved without a
  drag.
- `MiniMonth`, `CalendarHeader` and `SlotPicker` (pick a bookable slot,
  usable without a calendar).
- French, English and Arabic (right to left), a secondary Hijri calendar,
  light and dark themes through `DzCalendarTheme`.
