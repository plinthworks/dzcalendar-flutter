# dzcalendar-flutter — context for Claude Code

The Dart/Flutter port of DzCalendar (`/Users/nadou/Dev/dzcalendar`, the
reference implementation in TypeScript). Decision K.14 (owner, 2026-11-08):
hand-written ports driven by the conformance cases; Dart/Flutter first because
sehhaty-mobile (`/Users/nadou/Dev/sehhaty-mobile`, Flutter, Dart ^3.9.2) is the
first user. Read the main repository's `CLEANROOM.md`, `ARCHITECTURE.md`
(validated decisions at its top) and `ROADMAP.md` (Phase 19).

## Working rules (same as the main repository)

- **Validate structural decisions with the owner before coding.** Talk to the
  owner in French.
- The TypeScript code is the behaviour reference; FullCalendar is never read
  (CLEANROOM). Port the behaviour, write idiomatic Dart.
- `conformance/cases` is copied from the main repository by a script, never
  edited here; CI checks the copy is current. A case failing here is a port bug
  or a finding to bring back to the main repository — never "fixed" by editing
  the case.
- Test expectations are written by hand from published zone rules, never copied
  from the implementation's output.
- Bad input never throws: it becomes a `Problem` (code + detail). Every guess
  is a warning.
- Verify before saying done; look at widgets on the iOS simulator and an
  Android emulator (screenshots), not only in widget tests.
- Every phase ends with an architect review and a code review; findings fixed
  before the phase is called done. Keep `ROADMAP.md`'s "Resume here" current.
- Another session may work in the same repository: stage only your own files.

## Tooling

Flutter 3.35.7 / Dart 3.9.2 at `~/tools/flutter/bin`. Xcode 26.1.1, iOS 26.1
simulator. Push with `git push git@github.com:plinthworks/dzcalendar-flutter.git main`.
