// Ported from the TypeScript Pro's timeline.test.ts (hand-written
// expectations, copied as values).
//
// Ported: 'timeline axis: elapsed, cut on the wall clock' (9).
// Skipped: 'timeline model' (6: buildTimelineModel / updateTimelineModel —
// the model is not ported, owner's decision 17) and 'timeline in the kernel'
// (1: no kernel). Translation notes:
// - `{ slot: 60 }` / `{ slot: 'day' }` / `{ slot: 7 }` are
//   `scale: TimelineScale.minutes(60)` / `TimelineScale.day` /
//   `TimelineScale.tryMinutes(7)` — null for a length that does not divide a
//   day, so the default is taken, as the web does with `slot: 7`; given
//   directly, `TimelineScale.minutes(7)` is a programmer's mistake and
//   `buildTimelineAxis` throws (checked below too).
// - `toBeCloseTo(x, 9)` is `closeTo(x, 1e-9)`.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

PlainDate d(String s) => PlainDate.parse(s);
final nav = NavContext(firstDay: 1, today: d('2026-10-21'));
ViewRange range(String type, String at) => computeViewRange(d(at), timelineViews[type]!, nav);
String label(TimelineSlot s) {
  final t = s.time;
  return '${t != null ? t.toString().substring(0, 5) : '${s.date}'}${s.pass == WallPass.second ? '*' : ''}${s.offset}';
}

Instant i(String s) => Instant.parse(s);

void main() {
  group('timeline axis: elapsed, cut on the wall clock', () {
    test('Paris, 25 October 2026 (fall back at 03:00 to 02:00): 50 half hours, 02:00 and 02:30 twice', () {
      final a = buildTimelineAxis(range('timelineDay', '2026-10-25'), 'Europe/Paris');
      expect([a.unit, a.slotMinutes, a.slots.length, a.length], [TimelineUnit.time, 30, 50, 50]);
      expect(a.slots.sublist(3, 9).map(label).toList(), [
        '01:30+02:00',
        '02:00+02:00',
        '02:30+02:00',
        '02:00*+01:00',
        '02:30*+01:00',
        '03:00+01:00',
      ]);
      expect(a.slots[4].pass, WallPass.first);
      // Every slot is 30 real minutes: the second 02:00 starts an hour after the first.
      expect(a.slots[6].start.epochMilliseconds - a.slots[4].start.epochMilliseconds, 3600000);
    });

    test('Paris, 29 March 2026 (02:00 becomes 03:00): 46 half hours, 01:30 is followed by 03:00', () {
      final a = buildTimelineAxis(range('timelineDay', '2026-03-29'), 'Europe/Paris');
      expect([a.slots.length, a.length], [46, 46]);
      expect(a.slots.sublist(2, 5).map(label).toList(), ['01:00+01:00', '01:30+01:00', '03:00+02:00']);
      expect('${a.slots[3].end}', '2026-03-29T01:00:00Z');
    });

    test('a week of hours: 24, 24, … and 25 on the Sunday the clocks fall back — 169 hours wide', () {
      final a = buildTimelineAxis(range('timelineWeek', '2026-10-21'), 'Europe/Paris');
      expect(
        [
          a.slotMinutes,
          [for (final g in a.groups) g.lengthMinutes / 60],
          a.length,
        ],
        [
          60,
          [24, 24, 24, 24, 24, 24, 25],
          169,
        ],
      );
      // Sunday starts 144 hours in; its 25 hours run to 169.
      expect([a.toPosition(a.groups[6].start), a.toPosition(a.groups[6].end)], [144, 169]);
    });

    test('Lord Howe: spring skips half an hour (47 slots), autumn repeats one (49, 01:30 twice)', () {
      // 4 October 2026: 02:00 (+10:30) becomes 02:30 (+11:00).
      final spring = buildTimelineAxis(range('timelineDay', '2026-10-04'), 'Australia/Lord_Howe');
      expect([spring.slots.length, spring.groups[0].lengthMinutes], [47, 1410]);
      expect(spring.slots.sublist(3, 5).map(label).toList(), ['01:30+10:30', '02:30+11:00']);
      // 5 April 2026: 02:00 (+11:00) becomes 01:30 (+10:30).
      final autumn = buildTimelineAxis(range('timelineDay', '2026-04-05'), 'Australia/Lord_Howe');
      expect([autumn.slots.length, autumn.groups[0].lengthMinutes], [49, 1470]);
      expect(autumn.slots.sublist(2, 6).map(label).toList(), [
        '01:00+11:00',
        '01:30+11:00',
        '01:30*+10:30',
        '02:00+10:30',
      ]);
    });

    test('São Paulo, 4 November 2018: the day starts at 01:00 (midnight skipped), 23 hours', () {
      final a = buildTimelineAxis(
        range('timelineDay', '2018-11-04'),
        'America/Sao_Paulo',
        scale: const TimelineScale.minutes(60),
      );
      expect([a.slots.length, label(a.slots[0]), '${a.slots[0].start}'], [23, '01:00-02:00', '2018-11-04T03:00:00Z']);
    });

    test('Kolkata: no clock change, 48 half hours at +05:30', () {
      final a = buildTimelineAxis(range('timelineDay', '2026-10-25'), 'Asia/Kolkata');
      expect([a.slots.length, a.slots[0].offset], [48, '+05:30']);
    });

    test('a month of days: each as wide as its hours (25 October is 25/24 of a day), months above', () {
      final a = buildTimelineAxis(range('timelineMonth', '2026-10-21'), 'Europe/Paris');
      expect([a.unit, a.slotMinutes, a.slots.length, a.groups.length], [TimelineUnit.day, 1440, 31, 1]);
      final sunday = a.slots[24];
      expect('${sunday.date}', '2026-10-25');
      expect(a.toPosition(sunday.end) - a.toPosition(sunday.start), closeTo(25 / 24, 1e-9));
      expect(a.length, closeTo(31 + 1 / 24, 1e-9));
    });

    test('positions: clamped, back and forth; the slot of an instant', () {
      final a = buildTimelineAxis(range('timelineDay', '2026-10-25'), 'Europe/Paris');
      final second0200 = i('2026-10-25T01:00:00Z');
      expect([a.toPosition(second0200), a.slotAt(second0200), '${a.fromPosition(6)}'], [6, 6, '2026-10-25T01:00:00Z']);
      expect(
        [
          a.toPosition(i('2026-10-20T00:00:00Z')),
          a.toPosition(i('2026-11-20T00:00:00Z')),
          a.slotAt(i('2026-11-20T00:00:00Z')),
        ],
        [0, 50, -1],
      );
    });

    test('a slot length that does not divide a day falls back to the default', () {
      expect(
        buildTimelineAxis(range('timelineDay', '2026-10-21'), 'UTC', scale: TimelineScale.tryMinutes(7)).slotMinutes,
        30,
      );
      expect(
        () => buildTimelineAxis(range('timelineDay', '2026-10-21'), 'UTC', scale: const TimelineScale.minutes(7)),
        throwsArgumentError,
      );
      expect(buildTimelineAxis(range('timelineWeek', '2026-10-21'), 'UTC', scale: TimelineScale.day).slots.length, 7);
    });
  });
}
