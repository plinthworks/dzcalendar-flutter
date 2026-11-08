# Roadmap

## Resume here (if a session is lost)

- **Phase 19, Dart/Flutter port — 19a done (2026-11-08)**, committed
  ("Phase 19a"); see its section below. **Next: 19b**, starting with
  `IsoDuration` (decision 6), then normalize (with the `Problem` type), time
  axis, segments, column layout, navigation — and 19a's notes for 19b.
- **Owner's decisions (2026-11-08)**, the plan accepted:
  1. **Our own time types** stand for Temporal's (`Instant`, `PlainDate`,
     `PlainTime`, `PlainDateTime`, `ZonedDateTime`, immutable, ISO calendar);
     instants in epoch milliseconds (what the TypeScript indexes sort on; the
     cases are to the second).
  2. **Zone rules: no runtime dependency.** `timezone` 0.11+ (2026 data) needs
     Dart ^3.10 and sehhaty-mobile is on 3.9.2; `timezone`'s loader fills a
     process-wide database (two users in one app overwrite each other) and a
     `^0.10` constraint would lock out apps on 0.11. So a script fetches IANA's
     current release, compiles it with that release's own `zic`, reads the
     TZif files and writes our compact data (a generated Dart file, the POSIX
     footer kept for the years past the last transition); a small reader of
     ours. Pure Dart, deterministic on iOS and Android.
  3. **Dart ^3.9 / Flutter 3.35** (sehhaty-mobile's); `intl` compatible with
     the 0.20.2 that `flutter_localizations` pins.
  4. **Two packages in a pub workspace**: `dzcalendar_core` (pure Dart,
     `dart test`) and `dzcalendar` (Flutter widgets, from 19e).
  5. **Conformance**: `tool/sync_conformance.dart` copies the main
     repository's `conformance/cases` and records its commit
     (`conformance/SOURCE`); CI clones the main repository and fails when the
     copy differs. The runner (`dart test`) dispatches each case by suite; a
     suite not ported yet is skipped, counted.
  6. **Durations (owner, 2026-11-08): one `IsoDuration` type**, as
     Temporal's `Duration`: years, months, weeks, days, hours, minutes,
     seconds, milliseconds; ISO read and written (`P1DT2H`, `PT0S`);
     `ZonedDateTime.add` applies the calendar part on the clock face
     (`compatible`), then the exact part. `Instant.add`/`until` keep
     `dart:core`'s `Duration` (exact time only, as Temporal's `Instant`).
- **Plan**, each sub-phase closed by an architect review and a code review:
  - 19a — scaffold (workspace, CI, copy script, runner), time types, zone
    rules and data: `zone-dayinfo`, `zone-resolve`.
  - 19b — normalize, time axis, segments, column layout, navigation.
  - 19c — recurrence, store, commands, history: `rrule-expand`, `series-edit`.
  - 19d — slots, iCal, resources, timeline axis.
  - 19e — Flutter widgets: month, week, day, mini-month (iOS simulator and
    Android emulator screenshots).
  - 19f — the showcase app, in the spirit of macOS Calendar.
- **Open for 19e**: Dart's `intl` has no Hijri calendar — the web's secondary
  calendar (`-u-ca-islamic`) has no direct equivalent.

## 19a — scaffold, time types, zones ✅ (2026-11-08)

- Workspace (`pubspec.yaml`, `packages/dzcalendar_core`), strict analysis,
  `dart format` at 120 columns, CI (`.github/workflows/ci.yml`: format,
  analyze, test; the conformance copy checked against the main repository).
- Time types (`lib/src/time/`): `PlainDate`, `PlainTime`, `PlainDateTime`,
  `Instant`, `ZonedDateTime`; ISO 8601 read and written as Temporal writes it.
- Zones (`lib/src/zone/`): `ZoneRules` (IANA names, links, case, fixed
  offsets), POSIX footers, wall-time resolution (`Disambiguation`), and the
  port of the TS `zone.ts` (`dayInfo`, `dayInfos`, `transitionsBetween`,
  `resolveWall`, `isValidZone`, `isOffsetZone`, `isQuietDay`).
- Data: IANA **2026f** (344 zones, 253 links, ~200 kB of source),
  `tool/refresh_tzdata.sh [release]` rebuilds it with that release's own zic.
- Conformance: 299 cases copied from main `212eab6`; `zone-dayinfo` and
  `zone-resolve` (17) pass; the other 282 skipped with their sub-phase.
- **Cross-checked** against Python's `zoneinfo` (an independent reader of the
  system's TZif files): with our data rebuilt from 2026c (the system's
  release), 0 offset differences on 179 100 instants over 1850–2150 in 597
  zones. This found one bug, fixed: the POSIX rule governs from the file's
  last transition even when that one changed no offset (Troll before 2005,
  Riga 2000, Turks and Caicos 2015–2018 were given summer time). With 2026f
  the remaining differences are exactly 2026d–f's changes (Manitoba,
  Northwest Territories, Cuba, the POSIX-style zones).
- **Every refresh is checked against IANA's own reader**: `refresh_tzdata.sh`
  builds the release's `zdump` and `tool/check_tzdata.dart` compares every
  offset change from 1800 to 2150 in all 597 names, both ways (2026f: 82 834
  changes, no difference; given 2026c's files it fails, 2 581 differences).
  The archives' sha256 are written in the generated file's header.
- **Reviews.** Code review — fixed: mixed basic/extended ISO forms accepted
  (`2026-0329`, `10:3045`), `:60` refused (Temporal reads :59), a
  `ZonedDateTime` written with an offset's seconds (Temporal writes it to the
  minute, `+00:09[Europe/Paris]`; `.offset` keeps them), a zone id kept in its
  input's case (now IANA's: `europe/paris` → `Europe/Paris`, a link stays a
  link, `+0200` → `+02:00` — all checked against the Temporal polyfill), the
  refresh's output not formatted as CI checks it, GNU `mktemp`, the copy
  limited to `*.json`. Architect review — fixed: `PlainDateTime.inZone`
  returned an `Instant` (now a `ZonedDateTime`, as `toZonedDateTime`), no
  independent check of a refresh (zdump, above), `isQuietDay` cached invalid
  zone names, a stale comment; `conformance/SOURCE` said to be informational.
  Not a defect: the main repository has no local remote, but
  `plinthworks/dzcalendar` is public and `212eab6` is its `main`.
- **Notes for 19b and later** (from the architect review):
  - `PlainDate.tryParse` refuses `2026-03-29T10:00` (Temporal's
    `PlainDate.from` takes it): normalize decides — read, or a warning.
  - One shared ISO grammar for normalize: zone annotations, the `!` flag,
    `u-ca` (convert or a Problem); a range check (Temporal refuses years past
    ±271 821, instants past ±8.64e15 ms); digits past the millisecond dropped
    → a warning ("every guess is a warning").
  - A `ZonedDateTime` built from a wall time with an offset preference (rrule's
    `with(…, { offset: 'prefer' })`, normalize's offset cases).
  - Additions, none breaking: `ZonedDateTime.add/subtract/with/withTimeZone/
    startOfDay/epochMilliseconds`, `PlainDate.with`/`tryFrom(y, m, d)`,
    `toString(smallestUnit)`, `PlainYearMonth` (19e).
  - Before 19c keys anything by zone: `ZonedDateTime ==` sees a link and its
    zone as different (`Asia/Calcutta`, `Asia/Kolkata`; Temporal's `equals`
    does not).
  - Before publishing: keep `ZoneRules` internal or give it `Instant`s (its
    methods take raw milliseconds).
  - Before rrule and the timeline (19c/19d): cache a POSIX rule's changes per
    year (`_ruleOffsetAt` recomputes them each call).
  - CI: a scheduled refresh-and-diff job would flag new IANA releases; the
    cases are not validated against `conformance/schema/case.schema.json`.
