# Roadmap

## Resume here (if a session is lost)

- **1.1.0 (2026-11-14)**: accessibility and large-text fixes found by
  sehhaty-mobile (the SlotPicker) and the audit that followed: buttons a
  screen reader read but could not activate, the header, the month and
  the all-day bars at a large text, 15-minute events (decisions 72–73;
  `packages/dzcalendar/test/accessibility_test.dart`). A minor version
  rather than a patch (owner, 2026-11-14): the widgets behave differently
  (a bounded SlotPicker scrolls, the header's icon switcher).
- **Phase 19k done (2026-11-12)**: usable and published (decisions 65–71).
  1.0.0 is on pub.dev (published by hand, tag v1.0.0); later versions by
  tag through `.github/workflows/publish.yml`.
- **Phase 19j-3 done (2026-11-11)**: editing on the timeline — 19j (the
  timeline, decisions 61–64) is complete. See its section below. **Next:
  to decide with the owner** (decision 64's later items — pinch to zoom,
  `timeline.follow`, `timeline.ticks` — or another phase).
- **Phase 19j-2 done (2026-11-11)**, committed ("Phase 19j-2"): the
  timeline widget, reading (decisions 61–63).
- **Phase 19j-1 done (2026-11-10)**, committed ("Phase 19j-1"): the
  timeline's core (decisions 61–64).
- **Phase 19i done (2026-11-10)**, committed ("Phase 19i-1", "Phase
  19i-2"): the source manager (decisions 54–60). See its section below.
- **Phase 19h done (2026-11-10)**, committed ("Phase 19h"): the Hijri
  calendar (decisions 50–53).
- **Phase 19g done (2026-11-10)**, committed ("Phase 19g"): the event
  filter (decision 48) and the tapped `Rect` (decision 49).
- **Phase 19f done (2026-11-10)**, committed ("Phase 19f"): the showcase
  app `apps/showcase` (decisions 44–47).
- **Phase 19e-2b-2 done (2026-11-09)**, committed ("Phase 19e-2b-2"): the
  keyboard and screen readers (decisions 41–43).
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
- **To bring back to the main repository** (finding, 19j-1): the
  timeline's `hitAt` clamps to `axis.length - 1e-6` slots, which on a
  5-minute scale is 0.3 ms and rounds to `axis.end` — the next midnight, a
  day outside the axis. The port clamps in milliseconds (`end - 1`).
- **To propose to the main repository** (divergences, 19j-3): a timed
  event on a timeline counted in days shows no end handle (the web shows
  one that changes nothing); a screen reader holding an event in a
  resource view has "Previous/Next resource" actions; a held bar's menu
  button at its start (clear of the end handle); the cursor's first place
  is now if in view, else the moment at the view's start edge on the first
  row in view (the web: now, else the axis's start); a drag over a group's
  band lands on the row of events under it (the web: no place); ◀ ▶ slide
  with an animation, PageUp/PageDown at once. **Known limits**: an event on
  several resources is reached by the keyboard on its first row only; the
  row heads cannot take the keyboard's cursor (the web's `pendingHome`);
  at the axis's edge PageDown changes the period by the view's duration
  (the web: the period holding where the step would go).
- **To propose to the main repository** (divergences, 19j-2): a phone's
  resource area of one narrow column with an initials mode (decision 63);
  "+N" opens the day's sheet; the day's name kept in view inside its day;
  slot labels thinned to about 40 px; a period brought in by ◀ ▶
  (`timeline.step`) opens at its start (or its end going back), not where
  the slide would have gone. As the web: `fillLanes` written into the
  options from the view's height.
- **To propose to the main repository** (divergences, 19j-1): folding rows
  in the kernel (`toggleResourceRow`, `toggleGroupRow`; the web's view does
  it); a fold reuses rows only for the same event filter and problem
  reporter; "+N" ties kept in event order (Dart's sort is not stable).
- **To propose to the main repository** (divergences, 19i): a source saves
  a person's changes only (decision 58); a source can take what is made
  here (`createsHere`, decision 59); a live feed's errors and end as a
  notice (`SourceLiveFailed`); a JSON item that is not an object reported
  at `answer[i]`.
- **To propose to the main repository** (divergences, 19g): an event filter
  applied by the views' queries (`eventFilter`, decision 48), and the
  tapped thing's box given to the open/select/create callbacks (decision
  49). Their defaults change nothing: the conformance cases are unaffected.
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
  44. **The showcase is its own app (owner, 2026-11-10, 19f)**:
      `apps/showcase` in the workspace; `packages/dzcalendar/example` stays
      the small pub.dev example and the screenshot app.
  45. **iOS, Android and macOS (owner, 2026-11-10)**: an adaptive layout —
      a fixed sidebar on macOS and tablets, a drawer on phones.
  46. **Events in memory and .ics, no source manager (owner, 2026-11-10)**:
      a few demo calendars in memory, .ics import and export through the
      core; each calendar is a source chunk (`replaceSourceChunk`), and
      unticking one empties its chunk. Nothing is kept between launches.
  47. **A medium inspector (owner, 2026-11-10)**: title, place, all day,
      start and end, calendar, repeat presets (never, daily, weekly,
      monthly, yearly), notes, delete — a popover on macOS and tablets, a
      sheet on phones.
  48. **An event filter in the library (owner, 2026-11-10, 19f review)**:
      `ModelOptions.eventFilter` — a predicate applied when views are
      built — so hiding a calendar is the view's concern and the history
      stays whole; the showcase's stash goes. A divergence from the TS (it
      has none): to propose there too.
  49. **The place of what was tapped (owner, 2026-11-10, 19f review)**:
      `onEventTap`, `onSelect` and `onCreateRequest` are given the global
      `Rect` of the event or slot, to anchor a popover — from the keyboard
      and a screen reader too, where there is no pointer.
  50. **What comes next, simplest first (owner, 2026-11-10)**: the Hijri
      calendar (19h), then the source manager (19i), then the timeline
      view (19j).
  51. **Hijri data: ICU's Umm al-Qura table, arithmetic outside (owner,
      2026-11-10)**: ICU's month lengths for 1300–1600 AH (Unicode
      licence; the year starts follow from them — checked continuous, and
      equal to the civil reckoning at both ends), the tabular `civil`
      reckoning before and after. Tests written by hand from the published
      Umm al-Qura dates.
  52. **Month starts the application corrects (owner, 2026-11-10)**: the
      application may give months' announced first days (1 Ramadan 1447 =
      19 February 2026, Algeria's sighting); they replace the table's. A
      correction that cannot be (out of order, far from the table) is a
      problem, not a throw.
  53. **Both calendars, as the web (owner, 2026-11-10)**: a display
      calendar (titles, day numbers, labels in Hijri; the grids and the
      data stay Gregorian) and a secondary calendar (the Hijri date beside
      the Gregorian: cells, headings, the mini-month).
  54. **The source manager in two steps (owner, 2026-11-10)**: 19i-1, the
      manager (chunks of a week, month or year, prefetch, retries, four
      requests at once, cancelling, stale chunks, the zone, `hold`) with
      function and list sources; 19i-2, optimistic saves (put back when
      the server refuses), live sources, `jsonSource` and `icalSource`.
      Deferred loading of large lists (above 2000) later.
  55. **The application makes the HTTP requests (owner, 2026-11-10)**: no
      HTTP client in the core; `jsonSource` and `icalSource` are given a
      function that makes the request (dio for sehhaty, http…), the core
      builds the URL and parameters and reads the answer.
  56. **Live sources are Dart Streams (owner, 2026-11-10)**:
      `liveSource` takes a `Stream` of messages (created, changed, gone,
      everything anew); the calendar listens and cancels when the source
      goes. (The web: an `open(emit)` callback.)
  57. **A cancel token in each request (owner, 2026-11-10)**: a fetch is
      given a token (`cancelled`, a `Future` that completes on cancel) the
      application ties to its client (dio's `CancelToken`); an answer that
      arrives after a cancel is ignored anyway. (The web: an
      `AbortSignal`.)
  58. **A source saves a person's changes only (owner, 2026-11-10, 19i-2
      review)**: a validated command, an undo, a redo — as
      `onEventChange` hears them; the application's own commands (showing
      a booking it saved itself) are not written back again. The web saves
      every command: to propose there.
  59. **A source can take what is made here (owner, 2026-11-10, 19i-2
      review)**: `EventSourceSpec.createsHere` (one source): an event or a
      series made in the calendar goes to its `save` (`before` null);
      saved, it becomes the source's and the source is fetched again — the
      server's version adopted under the same id, or, under another id,
      replacing the local copy. Without one, the application persists
      creations through `onEventChange`. Not in the web: to propose there.
  60. **`save` writes, `onEventChange` informs (owner, 2026-11-10, 19i-2
      review)**: a source's events with a `save` are written by it (a
      refusal puts them back by itself); `onEventChange` is still told, to
      inform; its `revert()` is an undo, saved in turn. Events of no source
      are persisted through `onEventChange`.
  61. **19j in three parts (owner, 2026-11-10)**: 19j-1, the core (the
      timeline model: rows, lanes, "+N", off hours, the incremental update;
      the kernel's `timeline` options and folded rows; hit-tests); 19j-2,
      the widget reading (axis, resource area, tree, "+N", now,
      virtualization, RTL, iOS and Android screens); 19j-3, editing (move
      and resize across rows, keyboard, screen readers). Each its reviews
      and its commit. `DzCalendar(controller)` draws the family (decision
      30), no widget of its own.
  62. **One scroller both ways (owner, 2026-11-10)**: our own
      `TwoDimensionalViewport` (in the SDK, no dependency) — time heads
      pinned at the top, the resource area at the start, built only where
      seen, as the web's one scroller with sticky heads.
  63. **The resource area on phones (owner, 2026-11-10)**: one narrow
      column (the title), a button to shrink it or widen it; several
      columns (`areaColumns`) and their width handles on tablets and macOS.
  64. **Later (owner, 2026-11-10)**: pinch to zoom (`span`; not in the
      web, to propose there), following the present (`timeline.follow`),
      the ruler's ticks (`timeline.ticks`). Not offered as options until
      built.
  65. **On pub.dev at 1.0.0 (owner, 2026-11-11)**: both packages are
      published on pub.dev, the first version 1.0.0; afterwards every fix
      raises the version as on npm (semver: a fix the patch, an addition
      the minor, a break the major). A version on pub.dev can never be
      deleted, so the public API is reviewed before 1.0.0.
  66. **One version for both (owner, 2026-11-11)**: `dzcalendar_core` and
      `dzcalendar` always carry the same number and are released together;
      `dzcalendar` X.Y.Z asks for exactly `dzcalendar_core: X.Y.Z` (19k
      architect review: the widgets use the core's `internal.dart`, outside
      semver, so a widgets version works with its own core only).
  67. **Published by a git tag, from the owner's account (owner,
      2026-11-11)**: pushing `vX.Y.Z` publishes through GitHub Actions
      (pub.dev's automated publishing, OIDC — no secret): the core first,
      then the widgets. The very first publication is by hand from the
      owner's personal Google account, which then turns automated
      publishing on in each package's admin page. A verified publisher
      later, if wanted (packages can be moved to one).
  68. **A narrow core API at 1.0.0 (owner, 2026-11-11, 19k review)**: the
      engine's parts (model and axis builders, rrule internals, occurrence
      keys, normalization's machinery…) move from `dzcalendar_core.dart`
      to `internal.dart`. Public: what an app uses — time types, events,
      store, commands, history, kernel, resources, rules, sources, slots,
      Hijri, iCal. Re-exporting one later is an addition, not a break.
  69. **Closed classes and the version policy (owner, 2026-11-11)**:
      `final class` for `CalendarController`, `DzCalendarTheme`,
      `DzCalendarStyle`; `abstract final` for `SourceNotice`, `KernelEvent`
      and `ViewModel` (only the library makes their kinds; not sealed, so
      decision 26's default branch stays and a new kind is minor). Every
      public library gives only types a public library names
      (`tool/check_api.dart`, in CI) — so the widgets' barrel names the
      view models, `EventStore`, `ViewRange`… (about 90 names more). A new enum value, a new sealed case or a new word of
      `DzCalendarLocalizations` (with a default text) is a minor version —
      said in the README.
  70. **One rename (owner, 2026-11-11)**: `EditScope.this_` becomes
      `EditScope.single`. Short names (`Slot`, `Window`, `Busy`…) stay (an
      app hides what clashes); view names stay strings, typed constants
      may be added later.
  71. **Sealed stays closed (owner, 2026-11-12, 19k review)**: the public
      `sealed` hierarchies (`Command`, `Mutation`, `SourceEdit`, `Hit`,
      `CalEvent`… 24 of them) gain a case only in a major version, so an
      app's `switch` on them can be exhaustive (an app saving `SourceEdit`s
      cannot miss a new kind). Only `KernelEvent`, `ViewModel`,
      `SourceNotice` (`abstract final`) and enums grow in a minor.
  72. **A bounded SlotPicker scrolls its times (owner, 2026-11-14)**: in
      a scrolling parent it is as tall as its content; given a bounded
      height (a screen's body, a sheet), the days stay on top and the
      times scroll under them, rather than overflowing.
  73. **Wordless backgrounds are hidden from screen readers (owner,
      2026-11-14)**: a time-grid column, an all-day cell and a timeline
      row are `excludeFromSemantics` — their double tap created at a time
      nobody chose. Readers go by the free slots, the events and the
      keyboard cursor.
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
  - 19k — usable and published: pub.dev at 1.0.0 (decisions 65–67).
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

## 19k — usable and published (in progress, 2026-11-11)

Decisions 65–67. Found before starting: `pub publish --dry-run` refuses
both packages only for a missing `LICENSE` (README and CHANGELOG are
warnings); pana scores the core 130/160 (no README, CHANGELOG, licence,
example) and cannot score the widgets until the core is on pub.dev (it
resolves `dzcalendar_core` there). Outside the workspace a git dependency
on `dzcalendar` alone does not resolve: `dzcalendar_core` is looked up on
pub.dev — publication fixes that.

- **Done** (before the reviews):
  - The API reviewed (architect) and narrowed (decision 68): the engine's
    parts in `internal.dart`; the widgets' sources import it. Kept public
    what a public type gives (the view models' data: `ColumnAxis`,
    `TimeGridOptions`, `SeriesWindow`…). `Start` made public
    (`Series.start`).
  - `tool/check_api.dart` (the analyzer, in CI and before publishing):
    every type a public library gives — fields, getters, parameters,
    returns, supertypes, type arguments, aliases — is named by a public
    library (the core's four together; the widgets' barrel by itself).
    The barrel took about 90 names more to close (decision 69).
  - `final class` `CalendarController`, `DzCalendarTheme`,
    `DzCalendarStyle`; `abstract final` `KernelEvent`, `ViewModel`,
    `SourceNotice`; `EditScope.single` (decision 70); the localizations'
    rule written on the class.
  - Each package: `LICENSE`, `README.md` (its code compiled and run),
    `CHANGELOG.md`, version 1.0.0, topics, issue tracker; the core's
    `example/example.dart`; `dartdoc_options.yaml` leaves `internal` out.
    `dart doc`: 0 warnings for both. pana: the core 160/160; the widgets
    cannot be scored before the core is on pub.dev (pana drops overrides).
  - `.github/workflows/publish.yml` (tag `vX.Y.Z`: checks the tag against
    both versions and changelogs, analyzes, tests, publishes the core,
    waits for it on pub.dev, publishes the widgets); `tool/release.dart`
    (tried in a scratch repository: refusals, the commit and the tag).
  - The repository's README: install, the release steps.
- **Reviews** (architect, code), fixed:
  - the widgets pin the core exactly (decision 66 amended): they use its
    `internal.dart`, and a later core could break a published widgets
    version forever;
  - the semver policy in the READMEs said a new `Command` was minor while
    `Command` is sealed: decision 71;
  - publishing skips a version already on pub.dev (a run started again
    after a half-failed release; the hand-made 1.0.0), and the tag must be
    on main;
  - `tool/release.dart` sets the example's and the showcase's constraints
    too (a major version would not resolve), refuses a line it cannot set
    once (a comment after it), and fails cleanly without a version;
  - `tool/api.txt`, a snapshot of every public name and member, checked by
    `tool/check_api.dart` (a name gone is a break; `--update` for an
    addition) — closure alone did not stop a removal;
  - the keyboard's types, `Proposal` and `Ambiguity` moved to
    `internal.dart` (no public type gives them); `Hit`, `DayHit`,
    `SlotHit` and `InteractionContext` stay (`onDateTap`, the kernel);
  - `CalendarController`'s doc was on `timelineSliders` (since 19j-2).
  - Not done: a `.pubignore` (tests and the example's platform folders
    are uploaded, as usual); a member's signature change is not in the
    snapshot (names only).
- **The first publication (the owner, by hand)**, once 19k is committed:
  1. `dart pub login`, then `dart pub publish` in `packages/dzcalendar_core`
     and `flutter pub publish` in `packages/dzcalendar` (in that order).
  2. On pub.dev, each package's Admin → Automated publishing: enable
     GitHub Actions, repository `plinthworks/dzcalendar-flutter`, tag
     pattern `v{{version}}` (and the environment `pub.dev` if required).
  3. `git tag -a v1.0.0 -m "Release 1.0.0"` and push it: the workflow
     tests and skips both publications (already on pub.dev) — a dry run of
     the automation. Later versions go through `tool/release.dart`.

## 19j-3 — the timeline, editing ✅ (2026-11-11)

- **Pointer**: bars are `draggable`; a long press grabs one, moved along
  time and across rows (onto another resource: `proposeMove` swaps the one
  it was taken from); the ghost on the rows it would take (the row's
  height, as the web). Held, its end's handle along time
  (`pullHandle(axis: horizontal)`: the edge keeps its distance from the
  finger); `canResize` — all-day, or a scale in minutes. Near an edge the
  timeline scrolls both ways (`autoscroll`, as the time grid). A held
  bar's ⋮ button at its start (on a 24 px bar it covered the handle).
- **Keyboard** (`KeySurface`, `KeyGrid.timeline`): ← → along time by the
  snap (a day on a day scale), ↑ ↓ the rows, Home/End the row's ends,
  Shift to select, Tab through the events (rows, then time), the cursor
  drawn in its row. Held: ← → move, ↑ ↓ to the next row, Shift+arrows its
  end. PageUp/PageDown with `timeline.step` slide by it, the cursor with
  it; else (and at the axis's edge) the period changes. The keyboard
  navigates periods through the kernel, not the step's slide.
- **Shared changes**: `KeySurface.hitGrid` (an event's edges as moments
  or days, the web's `hitGrid`) beside `keyGrid`; `KeySurface.slide`;
  `_focusEvent` reveals `cursorFor` (where the view draws it); after a
  grab the cursor stays on the resource it was put down on (or taken
  from). **Screen readers**: the held event's swipes step a snap (a day
  on a day scale); "Previous/Next day", and in resource views
  "Previous/Next resource" (`GrabInfo.across`; words fr/en/ar).
- **Reviews**: architect — the cursor kept on its row after a grab; the
  period by the kernel; divergences and limits written above. Code — a
  step past midnight kept the day before (the hit's date now the
  moment's); a period the keyboard went to was placed back on 07:00 after
  its reveal (revealed once placed); a drag over a group's band had no
  place; PageDown that moved the view less than a snap said "no further".
- **Seen**: iPhone 17 Pro simulator (a drag from Ali's row onto Sara's,
  the edge scrolling on; a held bar, its menu and handle), Android
  `DzCalendar_Test` (Arabic, right to left: dragged rightwards is
  earlier). The example's `DEMO_DX` moves the finger along time. The
  keyboard's cursor: widget tests only (no hardware keyboard driven).
- **Tests**: library 109 (+15 `timeline_editing_test`: drags both
  directions, the handle, day scales, autoscroll both ways, the cursor,
  grab across rows, Escape, Shift+arrows, RTL keys, PageDown slide and
  period, past midnight, a group's band, a screen reader); core 1000,
  showcase 27.

## 19j-2 — the timeline widget, reading ✅ (2026-11-11)

- **`TimelineView`** (`lib/src/views/timeline_view.dart`), drawn by
  `DzCalendar` for the `timeline` family (decision 61): our own
  `TwoDimensionalScrollView` and `RenderTwoDimensionalViewport` (decision
  62) — (0, 0) the area's head, (1, 0) the time heads pinned on top,
  (0, r+1) the area cells pinned at the start, (1, r+1) the row bodies;
  paint and hit order put what is pinned over what scrolls; right to left
  through the horizontal axis direction. Rows built where seen (and the
  cache extent); along time, bars, labels and lines only in a window (the
  view and half a view each side, moved by half views; slots found by the
  axis's search, not a walk).
- **What it draws**: days (or months) over slots, the day's name kept in
  view; bars on lanes (title, its start when there is room; markers a line
  and a flag), backgrounds, "+N" (the day's sheet), off hours, the
  selection, the now line; the area — the tree's depth, folds
  (`kernel.toggleResourceRow`/`toggleGroupRow`, then
  `DzCalendar.onResourceToggle`), groups, "Unassigned". Tablets and
  desktops: `resourceAreaColumns` with width handles (40–480 px, the area
  at most 60 % of the width). Under 600 px of the calendar's own width (a
  phone, a narrow pane): one column, a button for initials (decision 63).
  Without resources: one row as tall as the view, `fillLanes` from it.
- **Gestures (reading)**: a tap on empty time selects its slot (a day on a
  day scale), told to `onDateTap`/`onSelect`; a long press the menu (or a
  drag-select with `selectable`); bars open on tap, their menu on a long
  press (moving them: 19j-3). The view is the gestures' `DragSurface`
  (`hitAt`, `boxesFor`); no `autoscroll`, no resize yet.
- **◀ ▶ with `timeline.step`**: the axis slides by it; at the period's
  edge the next (previous) period opens at its start (end). Through an
  unexported registry on the controller (`timelineSliders`, an `Expando`).
  The scroll opens on today's `scrollHour` (a day scale: today, two
  columns in), placed again for another axis, kept at another slot width.
- **Theme**: `timelineSlotWidth` 44, `timelineDayWidth` 36, `laneHeight`
  26, `resourceAreaWidth` 160 (the web's sizes). **Words**: resources,
  show/hide under a row, names/initials; the views named "Chronologie
  (jour)", "Timeline (day)", "خط زمني (يوم)". **Exports**:
  `TimelineSettings`, `TimelineScale`, `DayScale`, `MinuteScale`,
  `timelineViews`, `ResourceAreaColumn`, `ResourceToggleCallback`.
- **Reviews**: code — the scroll never placed when the first drawing had
  no rows (placed only once a scroller exists); every slot walked on each
  row's paint (the window's range by search, day starts once per axis);
  the keyboard not following a tap. Architect — the controller's hook made
  unexported; phone or tablet by the calendar's width; the landing tied to
  the period it left (never used if navigation is refused); the scroll
  kept at another slot width. Kept as the web: `fillLanes` in the options.
  For 19j-3: the ghost at a lane's height, autoscroll, the fold buttons
  (28 px, above the 24 px minimum) to grow with the row heads' semantics.
- **Seen**: iPhone 17 Pro simulator (French day, Arabic dark week: the
  area at the right, time leftwards), Android emulator `DzCalendar_Test`
  (French week). The example app shows the timeline views
  (`VIEW=resourceTimelineDay`: doctors under their departments).
- **Tests**: library 94 (+14 `timeline_widgets_test`: places and lengths
  reasoned in pixels, taps in both directions, folds, the step's slide and
  the next period, fill lanes, "+N", the phone and a narrow pane, 200
  resources windowed, resources arriving late, a resize); core 1000,
  showcase 27.

## 19j-1 — the timeline's core ✅ (2026-11-10)

- **Model** (`lib/src/timeline/model.dart`, exported by `timeline.dart`):
  the port of the Pro's `model.ts` — `buildTimelineModel`,
  `updateTimelineModel` (only the rows of the resources an event left or
  joined; every row on a touched series), `timelineNow`. Rows are sealed
  (`TimelineResourceRow`, `TimelineGroupRow`, `TimelineAllRow`); a row's
  events, background, "+N" (`TimelineMore`) and shading (`TimelineSpan`)
  are in a `TimelineRowBody` kept (same object) when the row did not
  change, and lent across a fold on the same snapshot. Bars carry a
  `TimedSegment` cut to the axis (all-day events too: their dates'
  midnights in the calendar's zone).
- **Hit-test** (decision 29): `timelineHitAt(model, row, position)` — a
  `SlotHit` on a scale of minutes, a `DayHit` on days, the row's resource;
  null on a group head. Clamped in milliseconds to the axis.
- **Kernel**: `ModelOptions.timeline` (`TimelineSettings`: `scale`,
  `maxLanes` 3, `fillLanes` 12, `step` under a day, `span`; checked when
  given), `collapsedResources`, `collapsedGroups` (copied, compared as
  sets), `toggleResourceRow`, `toggleGroupRow`; `TimelineViewModel`; the
  eight timeline views known to every kernel; `modelAt(timeline:)`. The
  kernel's problem reporter is one tear-off, so a fold's reuse holds.
  `follow` and `ticks` not offered (decision 64).
- **Reviews**: architect — toggles in the core, bar and "+N" documented
  (one bar per row, `to` is where it is drawn, not the event's end).
  Code — the right-edge hit on a 5-minute scale fell on the next midnight
  (the TS too: to bring back); a `modelAt` lent its silent rows to the
  shown model (the reporter is now in the build key); "+N" ties made
  stable; the collapsed sets copied. Points kept as the TS: the marker's
  three-slot flag, the quarter-slot minimum in packing, "+N" in the last
  lane, a day shaded only with no open hour, the double in "+N"'s key.
- **Tests**: core 1000 (+20: the TS's 7 model and kernel tests ported, 13
  by hand — markers, backgrounds, the fall-back night's second 02:30, the
  axis's edges, days shaded on a day scale, the filter, `now`, hits, the
  right edge, toggles, fold reuse, settings refused, the silent build);
  library 80, showcase 27 unchanged. The widget still shows its debug
  placeholder for the family until 19j-2.

## 19i — the source manager ✅ (2026-11-10)

- **19i-1, reading ✅ (2026-11-10)** — `source/{chunks,source,manager}.dart`,
  ported from the TS `source/manager.ts` (its reading part) and
  `sources.test.ts`:
  - chunks of a week (from Monday), a month or a year, `prefetch` either
    side; contiguous missing chunks one request, four at once; a request
    no longer shown cancelled (`CancelToken`, decision 57: `cancelled`,
    `whenCancelled`, `onCancel`); answers from before a refetch ignored;
    a multi-chunk answer one store change, an event over two chunks owned
    by both, a series and its overrides by every chunk asked;
  - retries (`RetryPolicy`: `attempts`, `backoff` doubled up to
    `maxBackoff`, `retryIf`); `staleAfter`; `zoneDependent` (asked again
    in another zone, told it: `FetchRequest.zone`); `hold` for prints and
    exports (`ready` names what failed); twelve spare chunks kept;
  - `fnSource`, `arraySource`; `EventSourceSpec.key`: a spec made again
    with an equal key (a provider rebuilt) replaces the old one without
    fetching; `EventInput.withDefaults`;
  - the kernel: `KernelOptions.sources`, `onSource`, `timers`;
    `kernel.sources`; fetched at every state change; `KernelSourceEvent`;
    `forgetBefore` sets the mark a delivery respects. The controller:
    `sources`, `loadingListenable` (set after the build, as its other
    news).
  - Tests: core 949 (+37 `sources_test`), library 80 (+2).
  - Reviews' fixes: the model cleared before a synchronous source lands;
    an answer that cannot be applied is a failed fetch, not a stuck chunk;
    a refetch asked while an answer is applied is kept; the loading flag
    never set during a build; nothing told after `destroy`; a held range
    before anything shown gets a window; no `1 << 62` sentinel (0 on the
    web); a problem's source is always the source's.
  - Room for 19i-2: `save`, `live` (a `Stream`), `forgot` on the spec;
    `SourceSaved` / `SourceSaveFailed` notices (`SourceNotice` is not
    sealed); the manager's store subscription, `pending`/`shielded` tags,
    the save chain counted by `idle`; `forgetBefore` calling `forgot`.
- **19i-2, writing and live ✅ (2026-11-10)** — ported from the TS
  `manager.ts` (saves), `live.ts`, `json-source.ts`, `ical/source.ts` and
  their tests (`sources_write_test`, 31):
  - optimistic saves: `EventSourceSpec.save(SaveRequest)` — edits in
    order, one at a time per source; a refusal puts them back (nothing
    left to undo), or, other changes in between, fetches again; a refetch
    while a save is out keeps the edit, then asks again; a chunk with a
    save out is not evicted. `SourceEdit.kind` and `input` (ready to send:
    `edit.input!.toJson()`). Decisions 58–60 (a person's changes only;
    `createsHere`; `save` writes, `onEventChange` informs).
  - `liveSource(connect: () => Stream<LiveMessage>)` (decision 56):
    created, changed (props merged, the app's own values kept), gone, all
    anew; a burst one delivery; `forgot`; a run said finished ends at the
    calendar's now; the feed's errors and end are `SourceLiveFailed`
    notices; `save` too. `LiveContext` (changed, now, failed). No
    `sseSource` (a browser's; a Dart app gives a Stream).
  - `jsonSource(url, request:)` and `icalSource(url, request: | text:)`
    (decision 55): the application's request function (dio) answers the
    decoded JSON or the text, throws for an HTTP error;
    `SourceHttpRequest` (url, path, queryParameters, method, headers,
    body, cancel); `readEventList`.
  - `forgetBefore` tells the sources what was forgotten.
  - Reviews' fixes: saves of the app's own commands (decision 58);
    creations never saved (decision 59); the two paths undocumented
    (decision 60); a live error reported as a crash; a stream's end
    unseen; a wedged save chain; a removed source's save not counted by
    `idle`; a live spec replaced by key left its feed open; the live
    update merge through JSON lost read problems and turned the app's
    dates into text.
  - Tests: core 980.
  - Later: a reconnecting helper for live streams (backoff, last id);
    partial results of a batch save; a JSON-body POST; deferred loading of
    large lists (above 2000, decision 54); per-source status.
  - Later (19i-1): `sources.setAll` (declarative, by id), a per-source status
    (loading, last error), shown chunks before prefetched ones in the
    queue, `ChunkPolicy.week`/`year` constants.

## 19h — the Hijri calendar ✅ (2026-11-10)

- **19h-1, the core** (decisions 51–53):
  - `HijriCalendar.ummAlQura` (ICU's table 1300–1600 AH in
    `calendars/umalqura.g.dart`, generated from ICU 76-1 `islamcal.cpp`,
    Unicode licence; the civil reckoning outside — the two meet exactly at
    both ends) and `HijriCalendar.civil`; `fromDate`, `toDate` (null for no
    such day), `monthStart`, `monthLength`; `HijriDate` carries its
    Gregorian `date`.
  - `HijriCalendar.withMonthStarts` (decision 52): the months' announced
    first days, never a throw — a start more than two days from the
    reckoning's, out of order, outside the table (or civil 1–9999), or on
    1 Muharram 1300 (where the table meets the civil reckoning) is an
    error and left out; a month made shorter than 29 or longer than 30
    days is a warning, once.
  - Formatting: `formatTemporal` and `formatRangeTitle` take a
    `HijriDate` — the locale's pattern for the skeleton, its digits (found
    as digits: "10日", "١٠"), the Hijri year, month and day, the era after
    the year and what is glued to it ("1447 AH", "١٤٤٧ هـ"); month names
    for en, fr, ar (CLDR's), English for other languages.
    `hijriMonthNames`.
  - Ranges keep an abbreviation's point, for both calendars: "janv.–févr.
    2026" (was "janv–févr."), German "15.–21. März".
  - The kernel: `KernelOptions.displayCalendar` / `secondaryCalendar`,
    `setDisplayCalendar` / `setSecondaryCalendar` (cause `calendar`),
    `KernelState.formatDate` / `formatSecondary`, `formatInCalendar`;
    titles in the display calendar ("chaa.–ram. 1447 AH" for February
    2026: a Gregorian month spans two Hijri ones).
- **19h-2, the widgets**: day numbers in the display calendar, a Hijri
  month's first day marked ("1 ram."); the secondary day beside each
  number (month cells, the time grid's heads) and under it (the
  mini-month), dropped — its month first — where the cell is too narrow;
  the year's and the mini-month's titles; screen readers hear both dates
  ("mercredi 18 février 2026 (1 ramadan 1447 AH)"); `secondaryDateStyle`;
  the controller's setters. The showcase: a "Calendrier hégirien" setting
  (off, beside, main; `--dart-define=HIJRI=`).
- **Verified**: iPad 13" (month, Hijri beside), Android phone (Arabic,
  Hijri main, Arabic-Indic digits from Flutter's data).
- **Tests**: core 912 (+21: `hijri_test`, every day 1290–1610 AH there
  and back, the published Ramadans and Eids, corrections), library 78
  (+10: `hijri_widgets_test`), showcase 27 (the setting).
- **Reviews' fixes** (19h-1): digits read as digits (a `d日` locale got
  garbage); a correction on a list's first month read a day twice (civil
  lists start a year earlier; 1 Muharram 1300 not correctable); civil
  years bounded (a far year built a list of billions); warnings once;
  the era after a glued suffix ("1447年 AH"); `HijriDate ==` includes its
  Gregorian day; patterns and formats cached; mixed range ends refused.
  (19h-2): the keyboard said the day in Gregorian; a day number measured
  narrower than its 24 px circle; every cell measured even without a
  Hijri calendar; the mini-month overflowed with a large text; the year's
  `FittedBox` hid its width, so nothing was ever dropped there.
- **Later**:
  - `TitleFormatArg` with the calendar (an app's own Hijri title);
  - `HijriCalendar.fromId('islamic-umalqura')`, and `toJson`/`fromJson`
    for the corrections (decision 15's typed input plus JSON);
  - an abstract alternate calendar, if another than Hijri is ever asked;
  - Hijri month names for more languages (fa, ur…), a guess reported;
  - Hijri as the display calendar without a secondary: labels read the
    Hijri date only (decision 53) — the Gregorian in parentheses too? (for
    the owner); a shorter visible form than `dateLong` for the list's
    headings and the day sheet's title; one shared long-label function for
    the mini-month and the calendar;
  - check the announcements by ear with TalkBack and VoiceOver.

## 19g — the event filter and the tapped Rect ✅ (2026-11-10)

- **Decision 48**, `ModelOptions.eventFilter` (core): a predicate the
  views' queries apply (`QueryOptions.where`, threaded through the time
  grid, the day grid and the year, the list, the resource columns and
  "Unassigned"), before layout — lanes and "+N" count only what is shown.
  - A series is asked once, with its base; a changed occurrence with its
    own event. Exact for what a series shares (a prop, a resource), the
    base's for a date or a title.
  - Display only: the store, the rules (overlap, constraints), `findSlots`
    and export see everything.
  - Compared with `==` (a closure each change; a method tear-off is the
    same); a new one remakes the model (state cause `options`); one that
    throws is reported once and shows its events.
  - **A divergence from the TS core** (it has none): to propose there.
- **Decision 49**: `onEventTap(instance, rect)`, `onSelect(selection,
  rect)`, `onCreateRequest(request, rect)` (typedefs `EventTapCallback`,
  `SelectCallback`, `CreateRequestCallback`) — breaking, before 1.0.
  - An event: its widget's own box (each `EventGestures` registers with
    the interaction), the piece nearest the finger, clipped to the
    calendar; else where the view would draw it; else the calendar's box.
    The same from a finger, the menu's "Open", Enter and a screen reader.
  - A selection or a "New event here": the boxes the view would draw for
    it (a synthetic event through `boxesFor`), joined.
- **The showcase**: unticking a calendar sets a new filter (none when all
  are ticked); the stash, `_movedOut` and the hand-made removals are gone,
  and the history stays whole (an edit undone while hidden shows undone).
  The pointer `Listener` is gone; the popover sits beside the `Rect`
  (after it in the reading direction, else before, else centered).
- **Verified**: iPad 13" (week, month, Arabic), Android phone (sheet).
  The `Pixel_9a` emulator is full (Android wants ~500 MB free to install):
  a dedicated AVD `DzCalendar_Test` (same system image, 8 GB data) is ours
  for screenshots; `Pixel_9a` and `Sehhaty_Test` are left alone.
- **Tests**: core 891 (+11, `event_filter_test`), library 68 (+9,
  `tapped_rect_test`), showcase 26.
- **Reviews' fixes**, all done:
  - the filter compared by identity (a tear-off remade the model each
    build) → `==`, in `hashCode` too;
  - a throwing filter reported for every event of every column → once;
  - the menu's and the keyboard's rect approximated a month bar's lane
    and an overlap's width → the drawn widget's box;
  - the keyboard could stay on, hold, open or delete an event the filter
    hid → `dropGone` after each store or options change;
  - an empty anchor put the popover in a corner → centered;
  - a stale doc comment.
- **Later**:
  - `onSlotTap` and `onDateTap` with a `Rect` too;
  - a selection's rect from the surface itself (`boxesForSpan`) instead of
    a synthetic event; a day selection anchored on the whole cell;
  - the showcase popover converting with `globalToLocal` (a nested
    navigator), not only the safe area;
  - the filter given the series for an occurrence (`(e, {series})`), or a
    per-occurrence mode, if an app needs dates;
  - a rules option to ignore hidden events (a drop refused by an
    invisible overlap);
  - more rect tests: RTL, the year, resources, a list's menu, a reader's
    tap, a scrolled-away event.

## 19f — the showcase app ✅ (2026-11-10)

- **`apps/showcase`** (decisions 44–47), iOS, Android and macOS:
  - day, week, month and year, a mini-month, today, and search over a year
    around today;
  - calendars to tick in a sidebar (≥ 800 px; a drawer below), an inspector
    (a popover beside the tap, a sheet on phones), and .ics import
    (`file_selector`) and export (a save dialog on macOS, text to copy on
    phones);
  - French, English and Arabic, light and dark, a choice of time zone;
  - demo calendars around today: a practice in Algiers, home, sport, and
    the Algerian public holidays read from a bundled `.ics` (read-only).
- **The calendars** (`CalendarBook`):
  - each one is a source chunk, and an event's calendar is its
    `extendedProps['calendar']` (an occurrence or an override: its
    series');
  - unticking one stashes its items (`exportInputs`) and removes them: the
    source's with the chunk, those made here (new events, overrides, cut
    series) by `store.apply(…, ChangeCause.api)`, as `refreshOngoing`
    does;
  - ticking re-delivers the stash, with what the chunk holds that has
    moved to another calendar;
  - history entries touching removed items are dropped by the history
    (`_heard`), so an undo after a hide refuses and changes nothing
    (tested);
  - imported ids are prefixed by their calendar's id: a file read twice is
    a calendar of its own, not a clash.
- **The inspector** runs validated commands — `CreateEvent`, `UpdateEvent`
  (an occurrence asks this / following / all), `RepeatEvent`, `ChangeRule`,
  `Batch`, `DeleteEvent` — so every save is one step of the undo history.
  An edit keeps the event's own zone. A new rule, or another calendar, is
  for the whole series. Saving into an unticked calendar ticks it.
- **In the library**:
  - the year view is a grid of as many months a row as fit (≥ 240 px each,
    at most four — macOS's 4 × 3), its day numbers scale down rather than
    overflow, and its month titles are headers for screen readers;
  - the docs of `BusinessHoursRule.daysOfWeek` say ISO 1–7 and not 0–6
    (Sehhaty's backend counts PostgreSQL's way: only Sunday differs).
- **Screenshots and tests**:
  - `--dart-define`s for screenshots made again exactly: `TODAY`,
    `LOCALE`, `DARK`, `ZONE`, `VIEW`, and `SHOT` (a tap or a search played
    at start);
  - screenshots on the iPad 13" and 11" and the iPhone 17 Pro simulators
    and the Pixel_9a emulator (an arm64 release build: the emulator's
    storage is nearly full, and its other apps are not ours);
  - macOS was built and run, but not captured (the terminal lacks the
    screen-recording permission);
  - tests: 13 for the model (`book_test`) and 12 for the screens
    (`app_test`), run in CI.
- **Reviews' fixes**, all done:
  - an event moved to another calendar was lost when its first calendar
    was hidden and shown again;
  - an unticked calendar could be chosen in the inspector, its event then
    shown;
  - an override's calendar was its own, not its series';
  - the search results did not follow changes;
  - the toolbar and the inspector's buttons overflowed with larger text;
  - the popover kept the place of an old click when opened from the
    keyboard;
  - the book was touched after it was disposed;
  - a weak Arabic test was split in two.
- **For the owner** (from the reviews) — decided: decisions 48 and 49:
  1. an event filter at query time in the library
     (`ModelOptions.eventFilter` or `setEventFilter`): hiding a calendar
     would be a view's concern, the history kept whole, and the stash
     machinery gone. The TS has none, so it would be a divergence.
  2. the place of what was tapped, given to `onEventTap`, `onSelect` and
     `onCreateRequest` (a global `Rect`), to anchor a popover without
     tracking pointers.
- **Later**:
  - export per calendar (one file now; the calendar is lost on re-import);
  - ~~say when hiding a calendar drops undo steps~~ — gone with 19g: hiding
    no longer touches the store;
  - the refusal's detail in the inspector (a `Violation`, not "refused");
  - a dot under a busy day of the mini-month;
  - the year view's keyboard;
  - a test of the year with Saturday and Monday as first days.

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

