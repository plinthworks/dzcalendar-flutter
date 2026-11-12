# Changelog

Versions follow [semantic versioning](https://semver.org). `dzcalendar` and
`dzcalendar_core` are released together under the same number.

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
