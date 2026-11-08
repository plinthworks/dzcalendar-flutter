# Roadmap

## Resume here (if a session is lost)

- **Phase 19c in progress (2026-11-08).** 19c-1 committed ("Phase 19c-1"):
  the RRULE engine (`lib/src/rrule/`: parse, serialize, iterate, expand,
  first/last start), the 102 `rrule-expand` cases pass, `rrule_test.dart`
  (19, from the TS) passes; the store's persistent structures (AVL, ordered
  map, interval tree) and span algebra (`intervals.dart`) are written,
  untested yet. `ZonedDateTime.fromWall` (an offset preference: the one
  helper the 19b review asked for). **Next: 19c-2** — series
  (`occurrenceLength` needs `until` with days, materialize, keys), the
  store, commands, history, series editing; `series-edit` cases; then the
  reviews of the whole of 19c.
- **19b done (2026-11-08)**, committed ("Phase 19b"). **19c** — recurrence (rrule parse/expand, series),
  the store (persistent interval indexes, revisions, `eventEquals` is there),
  commands with `EventPatch` (decision 10), the undo history; the
  `rrule-expand` and `series-edit` cases. Read the notes for 19c below first.
- **To bring back to the main repository** (a finding, not edited here):
  derived ids hash a moment's text; the TS keeps nanoseconds, the port the
  millisecond (decision 9), so a source writing past the millisecond gets
  different ids on web and mobile. Proposed there: hash the moment to the
  millisecond, and say `precision-truncated`.
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
  7. **`EventInput` (owner, 2026-11-08): a typed class** (nullable fields,
     the TS names) **and `EventInput.fromJson(Map)`** for an API's data: a
     field of the wrong type becomes a `Problem` at its path, never an
     exception; `null` means absent.
  8. **A Dart `DateTime` is refused (owner, 2026-11-08)**, as the web refuses
     `Date` (K.15): `date-object-rejected`, the detail giving the conversion
     (`Instant.fromEpochMilliseconds(value.millisecondsSinceEpoch)`).
  9. **Below the millisecond (owner, 2026-11-08)**: kept to the millisecond
     and said — `precision-truncated` (warning, a code the TS does not have
     yet); derived ids hash the moment to the millisecond.
  10. **`EventPatch` (owner, 2026-11-08, for 19c)**: `null` means unchanged,
      and a `clear: {EventField.tone, …}` set names the fields taken away.
  11. **`ZonedDateTime ==` (owner, 2026-11-08)**: a link and its zone are one
      zone (`Asia/Calcutta` = `Asia/Kolkata`), as Temporal's `equals`; the
      name written is kept for display.
  - Not a question (Dart): recurrence will be part of the core — Dart's tree
    shaking makes the TS's separate entry (`@dzcalendar/core/recurrence`,
    size) pointless, so `recurrence-not-loaded` has no equivalent. No
    `foreign-temporal` either (no polyfill copies in Dart).
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

## 19b — normalize, time axis, segments, column layout, navigation ✅ (2026-11-08)

- `IsoDuration` (decision 6): ISO read and written, maps (`{"hours": 1}`),
  `ZonedDateTime.add/subtract` (calendar part on the clock face, then exact
  time), `totalDaysFrom`; every case checked against the Temporal polyfill.
- `Problem` (`ProblemCode` with the TS spelling, `Severity`), `EventInput`
  (+ `fromJson`), `CalEvent` (`TimedEvent`, `AllDayEvent`), `parseTemporal`
  (one ISO grammar: annotations, `!` critical ones refused, `u-ca` dropped as
  the model is ISO, Temporal's range limits), `placeWall`, `normalizeEvent`,
  `normalizeMany` (derived ids: cyrb53 identical to the TS's, checked on
  ASCII, accents and emoji — an event of a source has the same id on the web
  and on mobile). Rules, exdates, rdates and overrides are refused with a
  "19c" detail until the recurrence engine is ported.
- `buildColumnAxis` (wall and elapsed axes, bands, ticks), `segmentTimed`,
  `segmentAllDay`, `splitByWeek`, `layoutColumn`, `ViewSpec`,
  `builtinViews`, `computeViewRange`, `navigate`, `assertViewSpec`.
- Conformance: 54 cases pass (zones 17, normalize 15, time-axis 6, segment 7,
  layout-column 3, navigation 6); 245 skipped (19c, 19d).
- Unit tests: normalize (57, from the TS), durations, and project / layout /
  views (32, ported from the TS by a Sonnet agent, none failing; skipped:
  row layout, overflow, view models, formatting — not ported yet).
- **Reviews.** Code review (every claim checked against the polyfill first)
  and architect review — fixed: `IsoDuration.tryParse` threw past 63 bits
  and wrapped around past Temporal's limits (an all-day event was accepted
  with a wrong end, in silence) — now null past Temporal's limits, never an
  exception; `toString` of 1500 ms (`PT1.5S`); the map form as Temporal's
  (unknown keys ignored, micro/nanoseconds); sub-millisecond digits dropped
  in silence (decision 9); the `offset-mismatch` detail rebuilt instead of
  the text written; an unknown zone said after a syntax error; Temporal's
  date range off by one at both ends, a zoned instant past it accepted;
  `CalEvent` without `ref`, a partial `copyWith` that could not clear a
  field, `withIdentity(…, null)` keeping the source on timed events only,
  no `withRevision` and no `eventEquals` (now beside the type, with the
  test that fails when a field is forgotten); regexes, permissions and empty
  lists made per event (now shared: `normalizeMany` 10 000 ≈ 51 ms before);
  `fromJson` refusing a `Map<Object?, Object?>`; `ViewSpec.hiddenDays` not
  copied; `Problem`'s `sourceId` set only through `withSource`.
- **Notes for 19c** (architect review):
  - `EventInstance.key` must be built by the store with the TS's `escapeId`
    / `occurrenceKey`, so an id holding `@` or `|` cannot collide.
  - `Normalized` gets `NormalizedSeries` (its `event` is the series' base):
    a breaking change for exhaustive switches — fine while unpublished.
  - One helper for a wall time with an offset preference (`parse_temporal`'s
    to-the-minute matching, rrule's `with(…, { offset: 'prefer' })`).
  - The POSIX rule's changes cached per year; a `ZonedDateTime` constructor
    carrying its rules (two lookups per construction today).
  - `PlainDate.with`/`tryFrom`, `ZonedDateTime.with`, `toString(smallestUnit)`.
  - A port bug inside `normalizeEvent` becomes `invalid-event` (as the TS):
    consider rethrowing under `assert` so tests see it.
- **Notes for later**: `ViewSpec ==` and a `copyWith` that can clear
  (the kernel's "update() with the same values is a no-op", 19e); `CalEvent`
  constructors are public and check nothing — only `normalizeEvent` and the
  store build events; `ZoneRules` still exported with raw milliseconds.
- Known difference: digits past the millisecond are dropped (decision 1),
  said by `precision-truncated` (decision 9).
