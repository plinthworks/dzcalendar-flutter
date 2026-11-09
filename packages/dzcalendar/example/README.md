# dzcalendar_example

The widgets of `dzcalendar` on a phone, for screenshots on the iOS simulator
and an Android emulator. What is shown comes from `--dart-define`:

```
flutter run --dart-define=VIEW=timeGridDay --dart-define=DATE=2026-10-25 --dart-define=SCROLL=0
```

`SCREEN=calendar|mini|slots`, `VIEW` (a view type), `LOCALE=fr|en|ar`,
`DATE`, `ZONE`, `DARK=true`, `SCROLL` (the hour at the top). The clock is
frozen at DATE 10:20 in ZONE.
