// Ported from the TypeScript core's keymap.test.ts (hand-written
// expectations, copied as values).
//
// Ported: intentFor (7), stepHit (4), eventHit (2), keyboard and mouse
// propose the same thing (6). Skipped: none.
// Translation notes:
// - `{ key, shiftKey, altKey… }` is `KeyLike(key, shift:, alt:, ctrl:, meta:)`;
//   a KeyContext `{ mode, rtl, grid }` is `intentFor(k, mode:, grid:, rtl:)`.
// - The TS compares intents as objects; here each is written as text by
//   `show` (`across 1`, `move 0 1 false`…), the same fields.
// - `stepHit(ctx, hit, step)` takes the zone and the snap minutes directly;
//   `grabStep(ctx, grid, held, { kind: 'move' | 'resize', edge, step }, fit)`
//   is `grabStep(ctx, grid, held, step, edge: (null for a move), fit:)`.
// - A hit's absent `gap` (`undefined`) is `false` here.
// - `p.start` / `p.end` are the proposed event's.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

const p = '[Europe/Paris]';
const paris = 'Europe/Paris';

CalEvent ev(EventInput input) {
  final r = normalizeEvent(input, NormalizeContext(displayZone: paris, newId: createIdGenerator('k')));
  final v = r.value;
  if (v is! NormalizedEvent) throw StateError('${r.problems}');
  return v.event;
}

InteractionContext ctx() => InteractionContext(snap: EventStore().snapshot, displayZone: paris, snapMinutes: 15);

Hit slot(String iso) {
  final z = ZonedDateTime.tryParse(iso)!;
  return SlotHit(date: z.date, instant: z.instant);
}

String at(Hit h) => switch (h) {
  SlotHit(:final instant) => '${ZonedDateTime(instant, paris)}',
  DayHit(:final date) => '$date',
};

String _text(CalEvent e, {required bool start}) => switch (e) {
  TimedEvent() => '${start ? e.start : e.end}',
  AllDayEvent() => '${start ? e.start : e.end}',
};

List<String>? span(Proposal? x) => x == null ? null : [_text(x.proposed, start: true), _text(x.proposed, start: false)];

String? show(KeyIntent? i) => switch (i) {
  null => null,
  MoveKeyIntent(:final step, :final extend) => 'move ${step.days} ${step.slots} $extend',
  AcrossKeyIntent(:final delta) => 'across $delta',
  ResizeKeyIntent(:final edge, :final step) => 'resize ${edge.name} ${step.days} ${step.slots}',
  LineKeyIntent(:final edge, :final extend) => 'line ${edge.name} $extend',
  PeriodKeyIntent(:final next) => 'period ${next ? 'next' : 'prev'}',
  ItemKeyIntent(:final delta) => 'item $delta',
  CommandKeyIntent(:final kind) => kind.name,
};

void main() {
  group('intentFor', () {
    String? time(KeyLike k, {KeyMode mode = KeyMode.cursor, bool rtl = false, KeyGrid grid = KeyGrid.time}) =>
        show(intentFor(k, mode: mode, grid: grid, rtl: rtl));

    test(
      'Alt+left/right: to the next or previous resource (reading direction applied), cursor and grab; Alt+up/down are not ours',
      () {
        expect(time(const KeyLike('ArrowRight', alt: true)), 'across 1');
        expect(time(const KeyLike('ArrowRight', alt: true), rtl: true), 'across -1');
        expect(time(const KeyLike('ArrowLeft', alt: true), mode: KeyMode.grab), 'across -1');
        expect(time(const KeyLike('ArrowUp', alt: true)), isNull);
        // Alt+Shift in grab mode is still the start's edge; on an event, Alt+arrows stay the page's.
        expect(time(const KeyLike('ArrowRight', alt: true, shift: true), mode: KeyMode.grab), 'resize start 1 0');
        expect(time(const KeyLike('ArrowRight', alt: true), mode: KeyMode.event), isNull);
      },
    );

    test('cursor in a time grid: left/right are days, up/down are slots, Shift extends', () {
      expect(time(const KeyLike('ArrowRight')), 'move 1 0 false');
      expect(time(const KeyLike('ArrowUp')), 'move 0 -1 false');
      expect(time(const KeyLike('ArrowDown', shift: true)), 'move 0 1 true');
    });

    test('cursor in a month: up/down are weeks; Home/End the line; PageUp/PageDown the period', () {
      String? month(KeyLike k) => time(k, grid: KeyGrid.day);
      expect(month(const KeyLike('ArrowDown')), 'move 7 0 false');
      expect(month(const KeyLike('End')), 'line end false');
      expect(month(const KeyLike('PageUp')), 'period prev');
      expect(month(const KeyLike('Enter')), 'enter');
      expect(month(const KeyLike(' ')), 'activate');
    });

    test('right to left: the left arrow goes to the next day', () {
      expect(time(const KeyLike('ArrowLeft'), rtl: true), 'move 1 0 false');
      expect(time(const KeyLike('ArrowRight'), mode: KeyMode.grab, rtl: true, grid: KeyGrid.day), 'move -1 0 false');
    });

    test('on an event: Enter opens, M or Alt+Enter grabs, Delete deletes, arrows go through the day', () {
      String? e(KeyLike k) => time(k, mode: KeyMode.event, grid: KeyGrid.day);
      expect(e(const KeyLike('Enter')), 'open');
      expect(e(const KeyLike('M')), 'grab');
      expect(e(const KeyLike('Enter', alt: true)), 'grab');
      expect(e(const KeyLike('Backspace')), 'delete');
      expect(e(const KeyLike('ArrowDown')), 'item 1');
      expect(e(const KeyLike('ArrowUp')), 'item -1');
    });

    test(
      'grab mode: arrows move, Shift resizes the end, Alt+Shift the start, PageUp a week back, Enter commits, Escape or Tab lets go',
      () {
        String? g(KeyLike k) => time(k, mode: KeyMode.grab);
        expect(g(const KeyLike('ArrowDown')), 'move 0 1 false');
        expect(g(const KeyLike('ArrowDown', shift: true)), 'resize end 0 1');
        expect(g(const KeyLike('ArrowUp', shift: true, alt: true)), 'resize start 0 -1');
        expect(g(const KeyLike('PageUp')), 'move -7 0 false');
        expect(g(const KeyLike(' ')), 'commit');
        expect(g(const KeyLike('Tab')), 'cancel');
        // No undo while holding an event: Ctrl+Z is not the calendar's then.
        expect(g(const KeyLike('z', ctrl: true)), isNull);
      },
    );

    test('undo and redo: Ctrl or Cmd with Z, Shift for redo, Ctrl+Y too; other keys are the page’s', () {
      expect(time(const KeyLike('z', meta: true)), 'undo');
      expect(time(const KeyLike('Z', ctrl: true, shift: true)), 'redo');
      expect(time(const KeyLike('y', ctrl: true), mode: KeyMode.event), 'redo');
      expect(time(const KeyLike('a')), isNull);
      expect(time(const KeyLike('c', ctrl: true)), isNull);
      expect(time(const KeyLike('ArrowDown', alt: true)), isNull);
    });
  });

  group('stepHit', () {
    test('slots step in elapsed time: the fall-back night visits both 02:00–03:00 passes (Paris, 25 Oct 2026)', () {
      var h = slot('2026-10-25T02:30+02:00$p');
      final seen = <String>[];
      for (var n = 0; n < 7; n++) {
        h = stepHit(paris, 15, h, const KeyStep(slots: 1));
        seen.add(at(h));
      }
      expect(seen, [
        '2026-10-25T02:45:00+02:00$p',
        '2026-10-25T02:00:00+01:00$p',
        '2026-10-25T02:15:00+01:00$p',
        '2026-10-25T02:30:00+01:00$p',
        '2026-10-25T02:45:00+01:00$p',
        '2026-10-25T03:00:00+01:00$p',
        '2026-10-25T03:15:00+01:00$p',
      ]);
      expect('${h.date}', '2026-10-25');
    });

    test('a slot step over the spring-forward gap goes from 01:45 straight to 03:00 (Paris, 29 Mar 2026)', () {
      final h = stepHit(paris, 15, slot('2026-03-29T01:45+01:00$p'), const KeyStep(slots: 1));
      expect([at(h), (h as SlotHit).gap], ['2026-03-29T03:00:00+02:00$p', false]);
    });

    test('a day step keeps the wall time and the pass; into a gap it lands on the first moment after it, flagged', () {
      expect(
        at(stepHit(paris, 15, slot('2026-10-24T02:30+02:00$p'), const KeyStep(days: 1))),
        '2026-10-25T02:30:00+02:00$p',
      );
      expect(
        at(stepHit(paris, 15, slot('2026-10-26T02:30+01:00$p'), const KeyStep(days: -1))),
        '2026-10-25T02:30:00+01:00$p',
      );
      final g = stepHit(paris, 15, slot('2026-03-28T02:30+01:00$p'), const KeyStep(days: 1));
      expect([at(g), '${g.date}', (g as SlotHit).gap], ['2026-03-29T03:00:00+02:00$p', '2026-03-29', true]);
    });

    test('a slot step keeps its column (the view keeps it inside its hours); a day hit moves by days', () {
      expect('${stepHit(paris, 15, slot('2026-10-21T23:45+02:00$p'), const KeyStep(slots: 1)).date}', '2026-10-21');
      expect(
        stepHit(paris, 15, DayHit(date: PlainDate(2026, 10, 28), allDayRow: true), const KeyStep(days: 7)),
        isA<DayHit>().having((h) => h.allDayRow, 'allDayRow', true),
      );
      expect(at(stepHit(paris, 15, DayHit(date: PlainDate(2026, 10, 28)), const KeyStep(days: 7))), '2026-11-04');
    });
  });

  group('eventHit', () {
    test('a timed event ending at midnight ends in the column of its last minute', () {
      final e = ev(EventInput(start: '2026-10-21T22:00$p', end: '2026-10-22T00:00$p'));
      final end = eventHit(e, Edge.end, displayZone: paris, grid: KeyGrid.time);
      expect(['${end.date}', at(end)], ['2026-10-21', '2026-10-22T00:00:00+02:00$p']);
      expect(eventHit(e, Edge.start, displayZone: paris, grid: KeyGrid.day), isA<DayHit>());
    });

    test('a day event: its first and last day; on the all-day row in a time grid', () {
      final e = ev(EventInput(start: '2026-10-21', end: '2026-10-24', allDay: true));
      expect(at(eventHit(e, Edge.end, displayZone: paris, grid: KeyGrid.day)), '2026-10-23');
      expect(
        eventHit(e, Edge.start, displayZone: paris, grid: KeyGrid.time),
        isA<DayHit>().having((h) => h.allDayRow, 'allDayRow', true),
      );
    });
  });

  group('keyboard and mouse propose the same thing (sequence parity)', () {
    test('grab, six slots down and one day on = a drop 1 h 30 later the next day', () {
      final e = ev(EventInput(start: '2026-10-21T09:00$p', end: '2026-10-21T10:00$p'));
      var held = e;
      Proposal? x;
      for (final step in [for (var i = 0; i < 6; i++) const KeyStep(slots: 1), const KeyStep(days: 1)]) {
        x = grabStep(ctx(), KeyGrid.time, held, step);
        held = heldEvent(x!);
      }
      final mouse = proposeMove(ctx(), e, slot('2026-10-21T09:00$p'), slot('2026-10-22T10:30$p'));
      expect(span(x), span(mouse));
      expect(span(x), ['2026-10-22T10:30:00+02:00$p', '2026-10-22T11:30:00+02:00$p']);
    });

    test('an unsnapped start: the first step snaps it, as the mouse does', () {
      final e = ev(EventInput(start: '2026-10-21T09:07$p', end: '2026-10-21T09:52$p'));
      var held = e;
      Proposal? x;
      for (var n = 0; n < 3; n++) {
        x = grabStep(ctx(), KeyGrid.time, held, const KeyStep(slots: 1));
        held = heldEvent(x!);
      }
      expect(span(x), span(proposeMove(ctx(), e, slot('2026-10-21T09:07$p'), slot('2026-10-21T09:52$p'))));
    });

    test('Shift+↓ twice = the end pulled 30 minutes; then a move carries the new length', () {
      final e = ev(EventInput(start: '2026-10-21T09:00$p', end: '2026-10-21T10:00$p'));
      final r1 = grabStep(ctx(), KeyGrid.time, e, const KeyStep(slots: 1), edge: Edge.end)!;
      final r2 = grabStep(ctx(), KeyGrid.time, heldEvent(r1), const KeyStep(slots: 1), edge: Edge.end)!;
      expect(span(r2), span(proposeResize(ctx(), e, Edge.end, slot('2026-10-21T10:30$p'))));
      final m = grabStep(ctx(), KeyGrid.time, heldEvent(r2), const KeyStep(slots: 1))!;
      expect(span(m), ['2026-10-21T09:15:00+02:00$p', '2026-10-21T10:45:00+02:00$p']);
    });

    test('a day event in a month: one week later, and its end a day longer', () {
      final e = ev(EventInput(start: '2026-10-21', end: '2026-10-23', allDay: true)) as AllDayEvent;
      final moved = grabStep(ctx(), KeyGrid.day, e, const KeyStep(days: 7))!;
      expect(span(moved), span(proposeMove(ctx(), e, DayHit(date: e.start), DayHit(date: PlainDate(2026, 10, 28)))));
      final longer = grabStep(ctx(), KeyGrid.day, heldEvent(moved), const KeyStep(days: 1), edge: Edge.end)!;
      expect(span(longer), ['2026-10-28', '2026-10-31']);
    });

    test('the view says where the hit may go: nowhere, and nothing is proposed', () {
      final e = ev(EventInput(start: '2026-10-21T09:00$p', end: '2026-10-21T10:00$p'));
      expect(grabStep(ctx(), KeyGrid.time, e, const KeyStep(days: 1), fit: (to, from) => null), isNull);
    });

    test('into the repeated hour by keyboard: the pass stepped into, the other offered (as under the pointer)', () {
      final e = ev(EventInput(start: '2026-10-25T01:30+02:00$p', end: '2026-10-25T02:00+02:00$p'));
      var held = e;
      Proposal? x;
      // 01:30 +02:00 → six slots of elapsed time → 02:00 +01:00 (the second pass).
      for (var n = 0; n < 6; n++) {
        x = grabStep(ctx(), KeyGrid.time, held, const KeyStep(slots: 1));
        held = heldEvent(x!);
      }
      expect([span(x)![0], '${x!.ambiguity?.alternative}'], ['2026-10-25T02:00:00+01:00$p', '2026-10-25T00:00:00Z']);
    });
  });
}
