# DzCalendar showcase

A calendar app in the spirit of macOS Calendar, built on `dzcalendar` to
show what the library does. It is not a calendar product: no sync, no
reminders, nothing kept between launches (owner's decisions 44–47 in
`ROADMAP.md`).

- Day, week, month and year; a mini-month; today; search over a year
  around today.
- Calendars to tick in a sidebar (a drawer on phones). Each calendar is a
  source of the store, and unticking one takes its events out until it is
  ticked again.
- An inspector to create and edit events: title, place, all day, start and
  end, calendar, repeat presets, notes. It is a popover on macOS and
  tablets and a sheet on phones. Every edit is a validated command, so it
  can be undone. An occurrence asks how far a change reaches.
- Edit gestures and the keyboard come from the library: long press and
  drag, ⌘Z, arrows, Tab.
- .ics import (`file_selector`) and export. On macOS the export goes
  through a save dialog; on phones the text is shown to copy. The Algerian
  public holidays come from a bundled `.ics`, read-only.
- French, English and Arabic (right to left); light and dark; a choice of
  time zone (Algiers, Paris, Montreal, Tokyo). The event "Visio avec le
  CHU de Lyon" keeps its own zone.

```sh
flutter run -d macos            # or an iOS simulator, an Android emulator
flutter test                    # the model (book_test) and the screens (app_test)
```

For screenshots made again exactly, the clock can be frozen and a gesture
played at start (see `lib/main.dart` and `lib/src/shots.dart`):

```sh
flutter run --dart-define=TODAY=2026-11-11 --dart-define=LOCALE=ar \
  --dart-define=VIEW=dayGridMonth --dart-define=SHOT=tap:Piscine
```
