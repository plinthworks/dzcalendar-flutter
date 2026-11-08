# Roadmap

## Resume here (if a session is lost)

- **Phase 19, Dart/Flutter port — not started (2026-11-08).** Repository
  created by the owner; this commit holds no code.
- **Next: the Phase 19 plan, to the owner before any code.** Decisions to put to
  the owner:
  1. What stands for Temporal's `ZonedDateTime` / `PlainDate` / `Instant`
     (Dart's `DateTime` knows only UTC and the device's zone): our own types on
     the `timezone` package?
  2. Where the zone rules come from: the `timezone` package bundles IANA data
     (to keep current), or the platform's rules through a plugin.
  3. Minimum versions: Dart ^3.9 / Flutter 3.35 (sehhaty-mobile's).
  4. Package layout: one `dzcalendar` package (core + widgets) or a pure-Dart
     `dzcalendar_core` plus a Flutter `dzcalendar`.
  5. The conformance copy script and runner (`dart test`).
- Then: the core family by family (zones, recurrence, store and commands,
  projection and layout, slots), then the widgets (month, week, day,
  mini-month), then the showcase app.
