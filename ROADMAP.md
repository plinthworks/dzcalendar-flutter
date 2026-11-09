# Roadmap

## Resume here (if a session is lost)

- **Phase 19e-2b-2 done (2026-11-09)**, committed ("Phase 19e-2b-2"): the
  keyboard and screen readers (decisions 41–43). See its section below.
  **Next: 19f** — the showcase app (its structural choices to the owner
  first); the "Later" lists of 19e-2b-1 and 19e-2b-2 stay open.
- **Phase 19e-2b-1 done (2026-11-09)**, committed ("Phase 19e-2b-1"): the
  gestures that edit (decisions 37–40).
- **Phase 19e-2a done (2026-11-09)**, committed ("Phase 19e-2a").
- **Phase 19e-1 done (2026-11-09)**, committed ("Phase 19e-1").
- **Phase 19d done (2026-11-08)**, committed ("Phase 19d"); see its section
  below. **Next: 19e** — the Flutter widgets. Before them, in the core: the
  rrule "jump to the window" (long series are slow, and drag feedback
  validates on every move) and the view models the TS core has and the
  port does not yet (see 19d's "Before 19e").
- **Phase 19c done (2026-11-08)**, committed ("Phase 19c").
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
  12. **Two libraries (owner, 2026-11-08)**: `dzcalendar_core.dart` is the
      public API under semver; `internal.dart` re-exports it with the
      engine's working parts (rule editing, iteration, stamping, patching,
      `ZoneRules`, the `Start` typedef…) for the Flutter package and the
      tests, without that promise.
  13. **`History` (owner, 2026-11-08)**: `dispose()` (not the TS's
      `destroy()`); `addListener`/`removeListener`, called when `canUndo` or
      `canRedo` changes (pure Dart, wired to a `ChangeNotifier` by the
      widgets); the command context passed by value (`History(store, ctx)`),
      or read at each command (`History.reading(store, () => ctx)`) — the
      same id generator each time.
  14. **19d's place (owner, 2026-11-08)**: slots, iCal and the timeline
      axis live in `dzcalendar_core`, as public libraries of their own —
      `package:dzcalendar_core/slots.dart`, `ical.dart`, `timeline.dart`
      (the TS's `@dzcalendar/slots`, `@dzcalendar/ical`,
      `@dzcalendar/pro/model`); resources and the calendar rules are in
      `dzcalendar_core.dart`, as in the TS core. One package to version;
      tree shaking drops what an application does not import.
  15. **Typed inputs + `fromJson` (owner, 2026-11-08)**: `SlotQuery`,
      `ResourceInput`, `BusinessHours`, `ConstraintSpec` (sealed) are typed;
      `fromJson` never throws (what cannot be read is a `Problem`), as
      `EventInput` and `Command`. An application's own resource fields stay
      in a `Map` (`fields`).
  16. **iCal: read and write (owner, 2026-11-08)**: `parseICal` and
      `serializeICal`; `icalSource` (fetching) waits for the source manager,
      not ported.
  17. **Timeline: the axis only (owner, 2026-11-08)**: `buildTimelineAxis`
      and the eight views; the model (rows, bars, lanes) comes with a
      timeline widget, none planned in 19e.
  18. **Slot rules apart from the range (owner, 2026-11-08, after the 19d
      review)**: `SlotRules` (availability, durations, buffers, notice,
      horizon, cap, busy) is kept per provider; `findSlots(rules, from:,
      to:)`, `checkSlot(rules, start, {from, to})`; `SlotRequest.fromJson`
      reads the web's whole query.
  19. **`Duration` for the slots' lengths (owner, 2026-11-08)**: duration,
      step, buffers, notice; the JSON keeps the web's minutes.
  20. **`WallTime` (owner, 2026-11-08)**: `WallTime(8, 30)`,
      `WallTime.endOfDay` for 24:00, shared by business hours and the
      slots' windows, named `from`/`to` in both (the JSON keeps
      `start`/`end` for business hours, as the web).
  21. **Before 19e (owner, 2026-11-08)**: value equality on the
      configuration types; one never-throwing shape (`fromJson` →
      `(T?, List<Problem>)` with paths; results as classes, not records);
      the store exported as inputs (`toInput`, `eventInput`, `seriesInput`,
      `exportInputs`, public as in the TS); `CalEvent.movedToTime` /
      `movedToDays` for a drag's preview.
  22. **The kernel in pure Dart (owner, 2026-11-08, for 19e)**:
      `CalendarKernel` in `dzcalendar_core` (view, date, zone, locale,
      options, store, history; testable without Flutter, the web's
      semantics), wrapped by a `CalendarController` (`Listenable`) in the
      Flutter package; Riverpod, Bloc… plug into that.
  23. **19e's views (owner, 2026-11-08)**: month, week, day, mini-month,
      list (agenda), and available slots shown in the time grid (the web's
      `availableSlots`: what sehhaty's slot picker becomes).
  24. **Formatting with `intl` 0.20.2's `DateFormat` (owner, 2026-11-08)**:
      skeletons and the locale's CLDR data, functions the application can
      replace; wording may differ slightly from a browser's.
  25. **The source manager later (owner, 2026-11-08)**: applications feed
      events with `replaceSourceChunk` (sehhaty from its API through
      Riverpod); the manager (periods, retries, live, `icalSource`) comes
      after the widgets.
  26. **Open model and event types (owner, 2026-11-09, 19e-1 review)**:
      `ViewModel` and `KernelEvent` are abstract, not sealed — the timeline
      and sources will add kinds; applications keep a default branch.
  27. **Names that do not collide with Flutter (owner, 2026-11-09)**:
      `KeyIntent` (`MoveKeyIntent`…, `CommandKeyIntent` + `KeyCommand`),
      `KeyStep`, `CalendarSelection`; one `WallPass` (first/second) for the
      time grid, its ticks (`AxisTick.pass`, `skipped`) and the timeline.
  28. **Gregorian now, Hijri later (owner, 2026-11-09)**: `intl` has no
      Islamic calendar; `ar-SA` is written in Arabic on the Gregorian
      calendar (the browser defaults to Umm al-Qura). Umm al-Qura comes in
      a phase of its own (official tables), as a secondary or main calendar.
  29. **Hit-tests and menus in the core (owner, 2026-11-09)**: `slotHitAt`,
      `slotTargetAt`, `allDayHitAt`, `dayHitAt`, `kernel.interactionContext`,
      `actionsFor` (the TS's actions) — the widgets measure, the core reads.
  30. **Widgets (owner, 2026-11-09, 19e-2)**: one `DzCalendar(controller)`
      draws the current view (month, week, day, list), as the web; the
      mini-month and the available-slots picker are widgets of their own,
      usable alone (sehhaty's slot picker without the whole calendar). The
      `CalendarController` is a plain `Listenable` — no Riverpod dependency.
  31. **Words through a Flutter delegate (owner, 2026-11-09)**:
      `DzCalendarLocalizations.delegate`, French, English and Arabic shipped,
      every text replaceable by the application; it follows the app's locale.
  32. **Style as a `ThemeExtension` (owner, 2026-11-09)**: `DzCalendarTheme`,
      derived from the app's `ColorScheme` and `TextTheme` when not set
      (Material 3, light and dark); the app overrides parts in `ThemeData`.
  33. **19e-2 in two parts (owner, 2026-11-09)**: 19e-2a reads (the six
      views, tap, selection, long press → menu, virtualization, RTL, screens
      on iOS and Android); 19e-2b edits (drag and resize with a long press to
      grab, haptics, edge scrolling; keyboard; full screen-reader support).
      Each part has its reviews.
  34. **A chosen export list (owner, 2026-11-09, 19e-2a review)**:
      `package:dzcalendar/dzcalendar.dart` exports what an app uses with the
      widgets (controller, event and time types, problems, commands, menus,
      hits and selections, slots); the whole core stays in
      `package:dzcalendar_core`. A test checks nothing collides with
      `material.dart`.
  35. **Long press grabs (owner, 2026-11-09)**: on touch, a long press on an
      event picks it up to move it (haptics), as Google Calendar; the event's
      menu comes from a tap (selected event, action bar) or a button; a long
      press on an empty slot or day keeps the "New event" menu. Swiping between
      periods is off while an event is held. Built in 19e-2b; until then the
      long press on an event opens its menu.
  36. **`SlotPicker<T>` (owner, 2026-11-09)**: takes the app's own slot
      objects (`startOf`, `endOf`, per-slot `enabledOf` and `seatsOf`);
      `SlotPicker.fromSlots` for the core's `Slot`s.
  37. **Edits applied, then revertable (owner, 2026-11-09, 19e-2b)**: as the
      TS — a gesture's command runs through the history at once, then
      `onEventChange(change)` tells the app; the server refusing,
      `change.revert()` takes back exactly that change (false when the
      events changed since).
  38. **19e-2b in two parts (owner, 2026-11-09)**: 2b-1 the gesture layer
      (long-press grab, move, resize, drag-select, haptics, edge scrolling),
      `onEventChange`, `eventBuilder`, the rebuild granularity; 2b-2 the
      keyboard (`Shortcuts`/`Actions` over the core's `KeyIntent`s) and full
      screen-reader support. Each its reviews and its commit.
  39. **Dragging from outside the calendar later (owner, 2026-11-09)**: an
      app's own items onto the calendar, or between two calendars — after
      19f; `proposeMove` already allows it.
  40. **A short landing motion (owner, 2026-11-09)**: a dropped event slides
      to its place (~200 ms), a refused one back to where it was; none when
      the system asks for less motion (`MediaQuery.disableAnimations`).
  41. **The keyboard's cursor, as the TS (owner, 2026-11-09, 19e-2b-2)**:
      the calendar is one focus point drawing a cursor (a `Hit`) moved by
      the core's `stepHit`; Shift+arrows extend a selection, Tab goes to the
      events; not Flutter's directional traversal over cell widgets (hours
      not built yet would be out of reach, repeated hours and skipped days
      would differ from the TS).
  42. **Screen readers move an event in grab mode (owner, 2026-11-09)**:
      "Move…" holds the event, which becomes adjustable — swipe up/down a
      slot (`onIncrease`/`onDecrease`), custom actions for the day before or
      after, double tap puts it down, "Cancel" lets it go; each step said.
      The same path as the keyboard (`grabStep`), so the same result as a
      finger (refusal, series scope, skipped hour).
  43. **Undo keys only when editable (owner, 2026-11-09)**: Ctrl+Z / ⌘Z and
      Shift+Ctrl+Z work only with `editable: true`, and `keyboardUndo:
      false` turns them off (as the TS); `controller.undo()`/`redo()` are
      never gated — the app calls them.
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

## 19c — recurrence, store, commands, history ✅ (2026-11-08)

- RRULE engine (`lib/src/rrule/`): parse/serialize, iterate (wall-clock
  DAILY and slower, elapsed sub-daily), expand with EXDATE/RDATE and the
  limit, first/last start, rule editing (explicit/implicit, rebase, split,
  union, positions). Series (`lib/src/recurrence/`): occurrence length in
  wall days (`ZonedDateTime.untilInDays`, Temporal's `until` with days —
  checked against the polyfill), materialize with its cache, keys,
  expansion, spans, and editing this / following / all, deleting.
- Store (`lib/src/store/`): persistent AVL, ordered map, interval tree;
  immutable snapshots, revisions stamped by the store, `StoreChange` (dirty
  spans and days, series touched/changed, applied), source chunks with
  ownership, adoption and the local-edit cleanup. Normalize: series,
  overrides (`recurrenceId`), linking.
- Commands (`lib/src/commands/`): the `Command` hierarchy and a total
  `Command.fromJson` (an `InvalidCommand` carrying its problems at their
  paths), `EventPatch` with `clear` (decision 10; set and cleared at once
  refused), `Edge`, `applyCommand` (all or nothing), `History` (merge,
  compact, revert, transactions, running events followed; decision 13).
- Conformance: **205 cases pass** (rrule-expand 102, series-edit 47 and the
  56 before); 96 skipped (19d). Unit tests ported from the TS by Sonnet
  agents, none failing: rrule (19), store (20), diff (5), intervals (6),
  commands (28), series (23), series-edit (50); skipped: what needs the
  calendar rules, the kernel, sources' fetching, view models. 519 tests.
- **Reviews** — fixed, each confirmed by running it first: a sub-daily rule
  dropped DTSTART's milliseconds (the first occurrence vanished;
  Temporal's `with` keeps them); `untilInDays` threw for an event from the
  first pass of a repeated hour to the second (Temporal: the same date is
  exact time, `PT45M`) — one such series in a source chunk would have
  aborted the delivery; `Command.fromJson` read a `series.rule` with an
  unreadable `rrule` as "stop repeating" (the series deleted; the TS
  refuses), a non-string `key` as no key (the whole series deleted), threw
  on a non-string batch label, lost every reason in `null`; a patch both
  setting and clearing a field cleared it in silence; a positional `bool`
  for the resize edge (now `Edge`); `weekStart` unchecked (now throws, a
  context error); `StoreChange` lists mutable and shared by every listener;
  the history's transaction compacting after its emptiness check. My own:
  the conformance adapter made a new id generator per command (two splits
  both made `n-1`) — the reason for `History`'s context by value.
- **Notes for 19d / 19e** (reviews):
  - Rules: `editedOccurrence` and `seriesAllowed` — ported in 19d.
  - Long series are slow to show: 500 open daily/weekly series from 2020,
    a one-week query ≈ 55 ms in 2026, ≈ 155 ms in 2040 (`iterateZoned` walks
    every period from DTSTART). Before 19e scrolls: jump arithmetically to
    the window for rules without COUNT, and/or cache starts per rule set and
    window (check the TS: it likely does the same).
  - `replaceSourceChunks`' local-split cleanup scans every series once per
    changed series (quadratic; the TS does the same).
  - Still open from 19b: one wall+offset helper (`parse_temporal` keeps its
    to-the-minute loop), the POSIX per-year cache, a `ZonedDateTime`
    carrying its rules, `PlainDate.with`/`tryFrom`, `toString(smallestUnit)`,
    rethrowing a port bug under `assert` in `normalizeEvent`.
  - `Command.toJson` (sending edits to a server) — an addition.
  - Small differences, kept: `INTERVAL=1.0` / `COUNT=1E1` refused (the TS
    reads `Number`); an unknown `scope` refused on every command (the TS
    ignores it where no occurrence is reached); `title: null` in a JSON
    patch is "unchanged" (the TS empties the title).
- **To bring back to the main repository** (the TS does the same): wall
  times in EXDATE, RDATE and `recurrenceId` are placed without the
  `wall-time-skipped`/`-ambiguous` warning ("every guess is a warning");
  `orphan-override`'s path uses the index after rejections, not the input's.

## 19d — slots, iCal, resources, rules, timeline axis ✅ (2026-11-08)

- **Timeline** (`lib/src/timeline/axis.dart`, `timeline.dart`):
  `buildTimelineAxis` (elapsed axis, wall-clock slots, the repeated hour
  twice, the skipped one not at all, a day starting after midnight),
  `TimelineScale` (sealed: `minutes(n)` or `day`; `tryMinutes` for data —
  null when it does not divide a day, the web's fallback; an invalid one
  given to `buildTimelineAxis` throws, a programmer's mistake),
  `timelineViews` (eight specs).
- **Resources** (`lib/src/resource/`): `ResourceInput` (+ `fromJson`, the
  application's fields in `fields`), `Resource.field(name)`,
  `buildResourceTree` / `buildResourceTreeFromJson` → `ResourceTreeResult`
  (refused entries, duplicates, unknown parents, cycles, `order` then
  `ResourceOrder` — fields with `-` or a comparison, one that throws said
  once and the tree left in input order), `flattenRows` (`RowState`),
  `columnResources`, `instancesOf`, `unassignedResource`.
- **Rules** (`lib/src/rules/`): `BusinessHours` (+ `fromJson`; a rule with
  a bad weekday, time or zone throws when made — configuration, the web's
  `assertBusinessHours` — never where it is used), `businessIntervals`,
  `ConstraintSpec` (sealed), `validateProposal(snap, Placement,
  RulesContext)`. `Placement` carries the event and the event as proposed
  (a typed `CalEvent`; `OverlapFn` and `allow` see the whole proposed
  event — the web passes `{...event, start, end, resourceIds}`, so a title
  changed by the same edit is seen here and not there);
  `RulesContext.overlap` is an `OverlapFn?` (null: overlaps allowed;
  `RulesContext.noOverlap` is the web's `false`). Wired into
  `applyCommand`: `CommandContext(rules:, external:)`,
  `CommandResult.violations`, `editedOccurrence`, `seriesAllowed` (one
  query for the series' year, `Neighbours`, instead of one per occurrence),
  `EventPatch.movesTime`.
- **Slots** (`lib/src/slots/`, `slots.dart`): `SlotRules`, `findSlots` →
  `SlotsResult`, `checkSlot` (`SlotAccepted` / `SlotRefused`; the start an
  `Instant`, a `ZonedDateTime` or ISO text, so a start written below the
  millisecond is `misaligned` as on the web), `SlotRequest.fromJson`,
  `busyFromEvents`, `readMoment` (strict: an offset the zone does not have
  is refused, as Temporal's `offset: 'reject'`). Buffers and notice keep
  fractions of a millisecond, as the TS; a range past Temporal's dates is
  refused at once.
- **iCal** (`lib/src/ical/`, `ical.dart`): `parseICal`, `serializeICal`
  (VTIMEZONE from our data's transitions, RRULEs when the last year's
  rules hold two more years, 75-octet folding). `EventInput.toJson` (the
  web's shape: copies, time types as ISO text, anything else passed on for
  `jsonEncode` to refuse).
- **Store export** (`lib/src/store/export.dart`): `toInput`, `eventInput`,
  `seriesInput`, `exportInputs` — `serializeICal(exportInputs(snap))`.
- **Also**: `WallTime` (`lib/src/time/wall_time.dart`), `jsText`/`jsRound`
  (`lib/src/util/js.dart`: JavaScript's `String` and `Math.round`, where
  the web's answer depends on them), `deepEquals` (`lib/src/util/
  equality.dart`), `ZoneRules.zoneNames`, `CalEvent.movedToTime` /
  `movedToDays`; value equality on every configuration type.
- **Conformance**: 301 pass, 0 skipped (`slots` 55, `timeline-axis` 11,
  `resource-tree` 10, `resource-rules` 10, `ical-parse` 10 — all first
  run). **Tests**: 738 (TS unit tests ported — iCal 70 with the 32
  fixtures, resources 12, business hours 5, slots 9, timeline axis 9 —
  and `review_19d_test.dart`).
- **Cross-checked against the TS**: `serializeICal` byte for byte (4 557
  octets: Lord Howe's half hour, New York's skipped hour, folding inside
  UTF-8, escapes, a background made transparent, an open series' RRULE
  VTIMEZONE), again after the review fixes; VTIMEZONE matching on four
  custom zones — three agree, the fourth is the finding below.
- **Reviews** (architect, code; each finding reproduced before it was
  fixed — the code reviewer had no shell, so its findings were run here):
  business hours with an unknown zone threw out of `applyCommand` (now
  refused when the rule is made, and by `fromJson`); creating a series
  under overlap rules queried the store once per occurrence (5.1 s with 200
  open daily series, 0.3 s now); zoned moments with a wrong offset accepted
  (slots, `serializeICal`); an empty `UID:` made the event an `invalid-id`;
  an invalid `defaultZone` threw on a UTC time; a start below the
  millisecond accepted by `checkSlot`; a range to +275760 walked 100
  million days (11 s); details `null` for `undefined`, a weekday list not
  as JSON, a non-object rule entry read less far than the web;
  `EventInput.toJson` handing out the input's lists and turning unknown
  values into text; `Math.round` vs Dart's `round` on halves (`fixedZone`,
  `fromPosition`); `jsText` of lists and maps; an invalid timeline scale
  replaced in silence; `jsText` and the zone list in the wrong layer.
  Decisions 18–21 came from the architect review.
- **Differences, kept** (said in the code):
  - The slot query's JSON reader checks in the web's order, but a rule's
    expansion warnings (`too-many-occurrences`) come after the exceptions'
    warnings (the web: between the rules and the exceptions).
  - A `busy` entry that is not an object is a warning (the web throws on
    it, caught as `invalid-slot-query`, and offers nothing).
  - `ConstraintSpec` spans are whole milliseconds (`MsSpan`); the web keeps
    fractions.
  - VTIMEZONE matching ranks Windows' preferred zones by canonical name
    (the table's `Europe/Kiev` is `Europe/Kyiv`).
- **Before 19e** (architect review): the view models the TS core has and
  the widgets need — `buildTimeGridModel`, `buildDayGridModel`,
  `packLanes`/`computeOverflow` ("+N more"), `PrefixSums`/`visibleRange`
  (windowing), `proposeMove`/`proposeResize`/the keymap, formatting and
  week numbers — belong in the core, not the widgets: plan them as the
  first part of 19e. And the rrule jump to the window (drag feedback runs
  `validateProposal` on each move; a 3-day query over 200 open daily series
  takes 35 ms).
- **To bring back to the main repository**:
  - `matchObservances` takes its candidates from
    `Intl.supportedValuesOf('timeZone')`, which in V8 (checked on Node
    24.22) are CLDR's names (`Asia/Calcutta`, `Asia/Katmandu`,
    `Asia/Rangoon`, `America/Godthab`), while the Windows table names
    IANA's (`Asia/Kolkata`, `Asia/Kathmandu`, `Asia/Yangon`,
    `America/Nuuk`): those never rank, and a +05:30 VTIMEZONE ("Mumbai
    office") is guessed `Asia/Colombo` on Node. The port, on IANA names,
    says `Asia/Kolkata`. Proposed: compare canonical names, or carry the
    candidate list.
  - `seriesAllowed` validates each of up to 500 occurrences with its own
    store queries (5 s with 200 open daily series in the port before the
    fix; the TS does the same): one query for the series' year.

## 19e-1 — the core's views, interaction, formatting, kernel ✅ (2026-11-09)

- **Rrule jump** (`_firstPeriod`): a rule without COUNT starts at the
  window's period. A week over 500 open series from 2020: 55 → 7.8 ms
  (2026), 155 → 6.1 ms (2040). Fuzz-checked against a full walk: 600 rules
  in `rrule_jump_test.dart`, 2 644 harder ones by the code review (BYWEEKNO,
  BYYEARDAY, BYSETPOS, ±53 BYDAY, DST hours in six odd zones, 30 years on).
- **Layout**: `packLanes`, `computeOverflow` ("+N"), `PrefixSums`,
  `visibleRange` (an unbounded viewport is fine).
- **View models**: day grid (+ resources, closed days, "+N"), multi-month,
  list, time grid (+ resources, readings on clock-change days, `maxStack`,
  off hours, available slots, `locateNow`), each updated in place after a
  store change (untouched rows and columns keep their objects).
- **Interaction**: `proposeMove`, `proposeResize`, `selectionBetween`,
  `commandFor`, the keymap (`intentFor`, `stepHit`, `eventHit`,
  `grabStep`; keys named as the web names them), hit-tests (the web's own
  reading of a point: the first moment after a skipped hour, the slot of
  the snap grid), `actionsFor` (menus: both readings of a repeated hour, a
  series' delete scope).
- **Formatting** (`intl` 0.20.2): `formatTemporal`, `formatRangeTitle` —
  `intl` has no range formats, so the two ends' shared words are said once
  ("15–21 mars 2026", "Mar 30 – Apr 5, 2026"; German "15–21. März" where a
  browser writes "15.–21. März"); week rules from CLDR as the web reads
  them (`week_data.g.dart`, generated by `tool/week_data.mjs` from Node's
  ICU 78 / CLDR 48: the region's first day, a language's likely region);
  each locale's data added to `intl` only when missing (Flutter's data,
  when loaded, is never replaced); a language `intl` lacks falls back to
  English, said by `kernel.localeProblem`; title skeletons checked.
- **Kernel** (`CalendarKernel`, decision 22): views (built-in + given),
  navigation, zone, locale, first day, titles, `ModelOptions` replaced
  whole (equal → nothing), resources, rules, history, `run(validate:,
  external:)`, `refreshToday`, `refreshOngoing`, `forgetBefore`,
  `viewModel` (memoized, same object when nothing it shows changed),
  `viewProblems`, `stateAt`, `modelAt`, `interactionContext`, `onError`,
  `dispose` (then a `StateError`). Left out: sources, deferred loading,
  the timeline family.
- **Tests**: 874, every TS test of these modules ported (layout, views,
  list, multi-month, maxStack, time-grid model, keymap, interaction, kernel,
  formatting, resources) — none found a port bug; `review_19e1_test.dart`.
- **Reviews** (each finding reproduced first): week rules lost the region
  (`ar-SA` started on Saturday, wrong week numbers — the first thing
  sehhaty would have shown; now CLDR by region, 17 locales equal to the
  TS's); `visibleRange` threw on an infinite viewport; a listener
  subscribed twice told twice; `intl`'s data depended on who loaded first;
  `TitleFormat.skeleton('EEEd')` printed a literal pattern; equal slots in
  a new list rebuilt the model; a new view-model wrapper after every change
  even when nothing changed; no `dispose` guard; errors only to the zone;
  internals exported publicly; names colliding with Flutter; three names
  for one pass. Decisions 26–29 came from the architect review.
- **Workspace**: `intl` overridden to 0.20.2 (what Flutter 3.35 pins), so
  the tests run on the version apps get.
- **For 19e-2** (architect review):
  - The kernel notifies synchronously: a setter called from
    `didUpdateWidget` or `didChangeDependencies` (`setLocale` from
    `Localizations.localeOf`) would notify during build — the controller
    defers `notifyListeners` to after the frame (or uses `silent`).
  - Route `onError` to `FlutterError.reportError` with the library name.
  - `setEvents` of 2 000 events: ~10 ms — watch it for live feeds.
  - Times measured (JIT): a week of 500 events 2.7 ms to model, a month of
    2 000 4.1 ms, 50 resources × 7 days 3.2 ms, one drag frame with rules
    0.17 ms.
- **Kept / to bring back**: titles differ slightly from a browser's (ICU
  range patterns, thin spaces: "Oct 18–24, 2026" vs "Oct 18 – 24, 2026");
  `ar` written with the data loaded first (Flutter's writes Arabic-Indic
  digits).

## 19e-2b-2 — the keyboard and screen readers ✅ (2026-11-09)

Owner's decisions 41–43.

- `CalendarKeyboard` (`lib/src/keyboard.dart`), owned by
  `CalendarInteraction`: the calendar is one `Focus`; the cursor is a core
  `Hit` moved by `stepHit` and kept in the view by `KeySurface` (the TS's
  `KeyboardSurface`: `home`, `fit`, `lineEdge`, `itemsAt`, `items`,
  `itemsAround`, `cursorFor`, `firstSlot`, `stepAcross`, `reveal`),
  implemented by the time grid and the day grid from the controller's
  current model (a period the keyboard just went to is known before it is
  built). Keys are read by the core's `intentFor` (`keyLikeOf` turns a
  Flutter key into the web's name; M, Z, Y also by their physical place, for
  an Arabic layout) — not Flutter `Shortcuts`/`Actions`: the keymap stays
  the same in every port.
- Cursor: arrows (15 min / a day; RTL swaps), Home/End, PageUp/PageDown (the
  view's own step), Shift extends a selection, Enter hands it once, Escape
  clears it; up from the first slot to the all-day row; past hidden or
  skipped days; drawn (`CursorBox`) only in the keyboard's highlight mode. A
  tap places it. Tab goes through the events in reading order, Shift+Tab
  back to the cursor, past the last out of the calendar. On an event: Enter
  opens it (else its menu), M / Alt+Enter holds it, Delete deletes it (scope
  asked for an occurrence), ←/→ the next one of its day, Escape back.
- Grab mode: each arrow a `grabStep` (Shift: its end; Alt: across
  resources; PageUp/Down a week), drawn by the gestures' ghost; Enter puts
  it down through `CalendarInteraction.commit` — now shared by the finger,
  the keyboard and the reader: refusal said and run validated, scope asked,
  history, `onEventChange`, said ("« Bilan » déplacé à 10:00"), landed;
  Escape, Tab, or the focus leaving let go. "Move…" / "Change duration…"
  in the menu (core `onGrab`) hold it too; a tap on the calendar then puts
  it there (WCAG 2.5.7).
- Screen readers (decision 42): an event's custom actions "Déplacer…",
  "Changer la durée…", "Supprimer" (editable only); held, it is adjustable
  (value, increased/decreased value: where a swipe takes it), with actions
  day before/after (a month: week), put down, cancel; double tap puts it
  down. Every step announced (`SemanticsService.announce`). Undo keys only
  when `editable && keyboardUndo` (new `DzCalendar.keyboardUndo`, decision
  43); `controller.undo()` never gated.
- Verified on the Android emulator with real key events (`adb input
  keyevent`): the cursor, Tab + M + ↓ (ghost at 12:00), Enter (placed, told,
  focused), Arabic month RTL (→ the day before). 58 widget tests (13 new).
- Review fixes (code + architect): a grab taken with the focus already there
  was never let go when the focus left; `_commit`'s `finally` and `_letGo`
  wrote to disposed notifiers when the calendar went during the scope menu;
  a navigation that did nothing (a fixed period) left the "own navigation"
  count stale (now counted only when the range moved; no navigation in a
  `visibleRange` view); M/Z/Y on non-Latin layouts; key repeat only for the
  moves; an app callback throwing during a keyboard drop is reported and
  the grab still ends; reader previews only with semantics on, `GrabInfo`
  equality; the reader's day actions hidden while changing a length, an
  all-day event steps by days; one `_letGo` helper in `DzCalendar`.
- **Later**: refocus by the resulting event id after an occurrence edit
  (`commit` returns a bool; the TS returns `eventId`); `held`/`focused`
  rebuild every event's builder at each step (make them per key); let go on
  `AppLifecycleState.inactive` and on a tap outside the calendar (the TS:
  window blur, press elsewhere); the list and year views have no keyboard
  surface (keys ignored there); a free bookable slot under the cursor is not
  said nor booked by Enter (TS `freeSlotAt`); resizing from the start
  (Alt+Shift); `SemanticsService.announce` is deprecated after 3.35 (move to
  `sendAnnouncement`); check on VoiceOver/TalkBack that a step is not said
  twice (announce + value change); tests still missing: a series dropped
  from the keyboard (scope + refocus), Alt+arrows across resources,
  all-day row ↔ slots, hidden/skipped days, a DST gap said, a refused Enter,
  Home/End/PageUp, Shift+Tab, dispose during the scope menu, reader cancel
  and day actions.

## 19e-2b-1 — the gestures that edit ✅ (2026-11-09)

- `CalendarInteraction` (lib/src/interaction.dart), one per `DzCalendar`:
  a long press grabs an event that may move (`editable`, or its own
  `startEditable`), else opens its menu; the finger is then followed through
  the pointer router's global route (the event's widget may be rebuilt or
  dropped meanwhile). Let go without moving: held — outlined, a handle at
  its end (down a column, along an all-day bar), a ⋮ button when there is
  room; a tap on it opens the menu. Tap on an event: `onEventTap`, else the
  menu. Swipe off while held or dragged.
- Each view is a `DragSurface` (`hitAt`, `boxesFor`, `autoscroll`,
  `canResize`): the time grid (body, all-day row, sideways scroll, RTL),
  the day grid (rows, resource columns). The core proposes
  (`proposeMove`, `proposeResize`, `selectionBetween`); the ghost is drawn
  over the calendar in global coordinates, clipped to its area, red-edged
  where the rules refuse. A handle keeps the edge's distance from the
  finger. Edge scrolling up to 900 px/s.
- A drop: unchanged or refused → slides back; an occurrence → "Change which
  events?" (this / following / all; closed: nothing); then
  `controller.run(commandFor(...), validate: true)` and the ghost lands
  (~200 ms, none with `disableAnimations`). Haptics: grab, each new place,
  drop, refusal.
- `selectable`: long press on empty time or a day then drag selects
  (`onSelect`); let go without moving: the menu (decision 35).
- Controller: `onEventChange(EventChange)` for a person's command
  (validated) and their undo/redo — `events`/`series` before/after,
  `revert()` (exactly that change, not told again), `canRevert`;
  `onCommandRefused`. The selection on its own `selectionListenable` (no
  longer notifies the controller's listeners).
- Rebuild granularity: env reads the widget (no copied callbacks); colors
  with their on-color (`colorsOf`); now line and selection from their own
  listenables; virtual columns rebuilt only when the window changes.
- `eventBuilder(context, instance, EventInfo)`; resource group heads drawn;
  a debug placeholder for families not drawn. Menu editing entries only
  when `editable` (as the TS).
- Example: `editable`, `selectable`, a SnackBar with Revert; `DEMO=drag|held|
  drop|select` plays synthetic touches for screenshots.
- Tests: editing_test.dart (17), widgets 28, exports 109 names.
- Review fixes (architect + code): a revert asked inside `onEventChange`
  was told back as an undo (the deferred write now skipped — **to bring
  back to the main repository**: the TS has the same shape,
  calendar.ts ~635–657); `EventInfo.held` stale for `eventBuilder`; the
  drag followed the last pointer down anywhere (now the live pointer
  nearest the press; a second finger's long press is ignored); a gesture
  started during a landing left `lifted` set; a gesture under way is
  cancelled on another view, period, zone, controller, or `editable`
  off; a refused place is run validated so `onCommandRefused` hears the
  violations; edge scrolling waits for the finger to travel; the landing
  target is read again each frame; an equal selection does not notify;
  the refusal color is the theme's error; `revert()` after dispose is
  false; the held event is let go only on navigate/view/zone/resources.
- **For 19e-2b-2**: the keyboard (`Shortcuts`/`Actions` over `KeyIntent`s,
  "Move…"/"Change duration…" entries through `onGrab`); announcements
  (moved, refused, skipped hour) and custom semantics actions on events;
  the held event's handle and button inside the event's semantics.
- **Later**: an immediate drag with a mouse (no long press); asking which
  reading on a repeated hour (`Proposal.ambiguity`, the pass under the
  finger is taken); resizing from the start; an all-day row shown while
  dragging when the week has none; dragging to the edge to change period;
  a handle's touch target under 24 px on short events (needs a hit slop
  outside the event's box); following from the first pixel instead of
  after the slop; a muted ticker (`TickerMode` off) leaves a slide
  unsettled; several controllers on one kernel each tell their own
  `onEventChange` (document); `controller.undo()` not gated on
  `editable` (decide in 2b-2); the day grid's ghost on the top lane, not
  the event's; tests still missing: month resize in RTL, across resource
  columns, autoscroll, pointer cancel, `snapMinutes` ≠ 15, a
  spring-forward drop.

## 19e-2a — the Flutter widgets, reading ✅ (2026-11-09)

The package `packages/dzcalendar` (Flutter), in the workspace with its
example app (`packages/dzcalendar/example`, iOS and Android; what it shows
comes from `--dart-define`: SCREEN, VIEW, LOCALE, DATE, ZONE, DARK,
SCROLL; the clock frozen at DATE 10:20). Owner's decisions 30–36.

- `CalendarController` (a `ChangeNotifier` over the kernel): tells its
  listeners in a microtask — never during a build, including the first one
  `runApp` makes outside any frame (found by a test: a phase check missed
  it); several changes, one notification; `changes` says why. A selection
  (tap on a slot or a day) is cleared by navigation, view, zone, resources.
  `CalendarController.of(kernel)` leaves a kernel handed in running.
- `DzCalendar`: header (previous, next, today, title, views), swipe between
  periods (mirrored right to left), the app's locale followed only when it
  changes, one minute-aligned clock paused in the background. Views:
  - time grid: day heads, all-day row, gutter (the second pass of a
    repeated hour marked, a skipped hour struck through), off hours, the
    clock-change bands drawn over events with their words, readings and
    real lengths on events cut by a change, available slots, "+N", now
    line; hours taller with a larger text size; columns narrower than
    `minColumnWidth` scroll sideways, only those on screen built
    (`visibleRange`), heads, all-day row and body on three synced
    controllers;
  - day grid (month, week, day, resources): lanes fitted to the height
    with the core's `cutDayGridModel` (new, internal: the cut a model
    built with that `maxLanes` has; the calendar's options untouched, an
    app's own `maxLanes` stands), "+N" opens a sheet;
  - list, year (months built as they scroll in, a dot on days with events).
  - Long press: the core's menus (`actionsFor`), delete as a validated
    command (undoable).
- `CalendarHeader(controller)`, `MiniMonth` (alone or on a controller: it
  follows the calendar's date, marks event days), `SlotPicker<T>` on the
  app's own slots (`fromSlots` for the core's), the repeated hour told by
  offset, seats, disabled slots.
- Words: `DzCalendarLocalizations` (fr, en, ar; Arabic plurals by
  `Intl.pluralLogic`, counts in the dates' digits, durations translated;
  a locale `intl` lacks: English numbers, no throw). Style:
  `DzCalendarTheme` (`ThemeExtension`, named `tones`).
- CI on Flutter 3.35.7 (`flutter analyze`, core `dart test`, `flutter test`).
- Checked: screenshots on the iPhone 17 Pro simulator (iOS 26.1) and the
  Pixel 9a emulator — week, month, day on both Paris clock changes, list,
  year, resources, mini month, slots (dark), Arabic week and month. The
  emulator had 371 MB free (other apps installed, left alone): the example
  goes on as a release arm64 APK.
- Reviews (architect, code), fixed: one scroll controller on two views (a
  crash on a phone week with an all-day bar); the widget writing
  `dayGrid.maxLanes` into the shared options after the frame (a call on a
  disposed controller possible); a clock per time grid only; unknown
  skeletons (`EEEEEd`); the top hour unlabelled with `slotMin`; English
  durations; `number()` throwing for a locale intl lacks; the mini month
  not following after browsing; the painter repainting every build;
  resource names missing from heads' labels; the selection never cleared;
  the locale forced at every dependency change; `Slot` and `CalendarEnv`
  missing from the public surface (now a chosen export list, decision 34).
  Tests: 28 widget tests (expectations reasoned: band words, `*`, real
  lengths, 09:12 → the 09:00 slot, lanes from the theme's sizes), 6 core
  tests for `cutDayGridModel`.
- **For 19e-2b** (from the reviews):
  - Gestures through one interaction layer owning the arena: long press
    grabs (decision 35), the event menu from a tap or a button, swipe off
    while an event is held; `Shortcuts`/`Actions` at the root over the
    core's `KeyIntent`s.
  - An `eventBuilder(context, instance, info)` seam (segment, size,
    compact, readings, selected), gestures and semantics kept outside.
  - Rebuild granularity: the selection on its own listenable; the virtual
    columns rebuilt only when the window's first/last change; one config
    object instead of eleven callbacks copied into `CalendarEnv` each
    build; `onColor` not by comparing colors.
  - The now line from a `ValueNotifier<Instant>` instead of a rebuild.
  - Resource group heads (`groupHeads`) are not drawn yet.
  - A placeholder (debug) for families not drawn (the timeline).

