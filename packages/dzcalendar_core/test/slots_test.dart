// Ported from the TypeScript slots.test.ts (hand-written expectations,
// copied as values).
//
// Ported: the forum-thread case (1), slots (4), review fixes (Phase 14) (4).
// Skipped: none. Translation notes:
// - The TS gives queries as loose objects, strings for moments; here they go
//   through `SlotRequest.fromJson` (the web's JSON shape) and the problems it
//   reports are put before the engine's, as an application would show them
//   (`find` / `check` below). `checkSlot` takes the start as the TS does: an
//   Instant, a ZonedDateTime or ISO text.
// - 'accepts Instants, ZonedDateTimes and strings alike': Dart's typed rules
//   (`SlotRules`, owner's decision 18) take the range apart, as instants; the
//   test keeps its point (a typed range, and the JSON reader's paths for what
//   is wrong) with an `Instant` and a `ZonedDateTime.instant` as the range and
//   strings in the JSON part. Durations are `Duration`s (decision 19), wall
//   times `WallTime`s (decision 20).
// - `{} as SlotQuery`, `null`, `5`… are passed to `SlotRequest.fromJson`, the
//   one entry that takes untyped input.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

const z = 'Asia/Riyadh';

typedef Found = ({List<Slot> slots, List<Problem> problems});

Found find(Object? json) {
  final (q, read) = SlotRequest.fromJson(json);
  if (q == null) return (slots: const [], problems: read);
  final r = q.find();
  return (slots: r.slots, problems: [...read, ...r.problems]);
}

SlotCheck check(Object? json, Object start) {
  final (q, read) = SlotRequest.fromJson(json, checking: start);
  if (q == null) return SlotRefused(SlotRefusal.invalidQuery, read);
  return q.check(start);
}

Map<String, Object?> withBusy(Map<String, Object?> rules, Object? busy) => {...rules, 'busy': busy};

String minute(ZonedDateTime x) => x.time.toString().substring(0, 5);

void main() {
  group('the case of the forum thread: only the free slots, in ten lines', () {
    test('client and server share one query; the server refuses what the page would not offer', () {
      final rules = <String, Object?>{
        'availability': {
          'timeZone': z,
          'weekly': [
            {
              'days': [7, 1, 2, 3, 4],
              'from': '08:00',
              'to': '12:00',
            },
          ],
        },
        'duration': 30,
      };
      final booked = [
        {'start': '2026-10-21T09:00+03:00[Asia/Riyadh]', 'end': '2026-10-21T09:30+03:00[Asia/Riyadh]'},
      ];
      final slots = find({
        ...withBusy(rules, booked),
        'from': '2026-10-21T00:00+03:00[Asia/Riyadh]',
        'to': '2026-10-22T00:00+03:00[Asia/Riyadh]',
      }).slots;
      final ok = check(withBusy(rules, booked), slots[0].start.instant);
      expect(slots.map((s) => minute(s.start)).toList(), [
        '08:00',
        '08:30',
        '09:30',
        '10:00',
        '10:30',
        '11:00',
        '11:30',
      ]);
      expect(ok.ok, isTrue);
      final refused = check(withBusy(rules, booked), '2026-10-21T09:00+03:00[Asia/Riyadh]');
      expect(refused, isA<SlotRefused>().having((r) => r.reason, 'reason', SlotRefusal.busy));
      // Every slot the page offers, the server accepts.
      expect(slots.every((x) => check(withBusy(rules, booked), x.start.instant).ok), isTrue);
    });
  });

  group('slots', () {
    test('a slot is in the provider’s zone and shows in the client’s by withTimeZone', () {
      final slots = find({
        'availability': {
          'timeZone': z,
          'weekly': [
            {
              'days': [3],
              'from': '08:00',
              'to': '09:00',
            },
          ],
        },
        'from': '2026-10-21T00:00Z',
        'to': '2026-10-22T00:00Z',
        'duration': 60,
      }).slots;
      expect('${slots[0].start}', '2026-10-21T08:00:00+03:00[Asia/Riyadh]');
      // Paris is at +02:00 on 21 October 2026 (summer time until the 25th).
      expect('${slots[0].start.withTimeZone('Europe/Paris')}', '2026-10-21T07:00:00+02:00[Europe/Paris]');
    });

    test('accepts Instants, ZonedDateTimes and strings alike, and says where an input is wrong', () {
      final typed = findSlots(
        SlotRules(
          availability: Availability(
            timeZone: z,
            weekly: [
              WeeklyWindow(days: const [3], window: const Window(WallTime(8), WallTime(9))),
            ],
          ),
          duration: const Duration(minutes: 60),
        ),
        from: Instant.parse('2026-10-21T00:00Z'),
        to: ZonedDateTime.tryParse('2026-10-22T00:00[$z]')!.instant,
      );
      expect(typed.slots, hasLength(1));
      final r = find({
        'availability': {
          'timeZone': z,
          'weekly': [
            {
              'days': [3],
              'from': '08:00',
              'to': '09:00',
            },
          ],
          'exceptions': [
            {'date': 'nope'},
          ],
        },
        'from': '2026-10-21T00:00Z',
        'to': '2026-10-22T00:00[$z]',
        'duration': 60,
        'busy': [
          {'start': 'x', 'end': 'y'},
        ],
      });
      expect(r.slots, hasLength(1));
      expect(r.problems.map((p) => p.path).toList(), ['busy[0]', 'availability.exceptions[0].date']);
    });

    test('never throws, whatever it is given', () {
      expect(() => find(<String, Object?>{}), returnsNormally);
      expect(() => check(<String, Object?>{}, 'garbage'), returnsNormally);
      expect(
        find({
          'availability': {'timeZone': z},
          'from': 'a',
          'to': 'b',
          'duration': 30,
        }).problems.map((p) => p.code.code),
        contains('invalid-slot-query'),
      );
      final bad = find({
        'availability': {
          'timeZone': z,
          'weekly': [
            {
              'days': [3],
              'from': '8h',
              'to': '9h',
            },
          ],
        },
        'from': '2026-10-21T00:00Z',
        'to': '2026-10-22T00:00Z',
        'duration': 30,
      });
      expect(bad.problems.map((p) => p.code.code), contains('invalid-availability'));
    });

    test('the calendar’s own events are busy time: timed ones are bookings, all-day ones block their dates', () {
      final newId = createIdGenerator('s');
      CalEvent norm(EventInput input) {
        final r = normalizeEvent(input, NormalizeContext(displayZone: z, newId: newId));
        final v = r.value;
        if (v is! NormalizedEvent) throw StateError('event');
        return v.event;
      }

      final events = [
        norm(EventInput(id: 'a', start: '2026-10-21T09:00[Asia/Riyadh]', end: '2026-10-21T10:00[Asia/Riyadh]')),
        norm(EventInput(id: 'b', start: '2026-10-22', allDay: true)),
        norm(
          EventInput(
            id: 'c',
            start: '2026-10-21T10:00[Asia/Riyadh]',
            end: '2026-10-21T11:00[Asia/Riyadh]',
            status: EventStatus.cancelled,
          ),
        ),
      ];
      final busy = busyFromEvents(events, z);
      expect(busy, hasLength(2));
      final slots = findSlots(
        SlotRules(
          availability: Availability(
            timeZone: z,
            weekly: [
              WeeklyWindow(days: const [3, 4], window: const Window(WallTime(8), WallTime(12))),
            ],
          ),
          duration: const Duration(minutes: 60),
          maxPerDay: 4,
          busy: busy,
        ),
        from: ZonedDateTime.tryParse('2026-10-21T00:00+03:00[Asia/Riyadh]')!.instant,
        to: ZonedDateTime.tryParse('2026-10-23T00:00+03:00[Asia/Riyadh]')!.instant,
      ).slots;
      // Wednesday: 09:00 booked, the cancelled 10:00 free; Thursday: blocked all day.
      expect(slots.map((s) => s.start.plainDateTime.toString().substring(0, 16)).toList(), [
        '2026-10-21T08:00',
        '2026-10-21T10:00',
        '2026-10-21T11:00',
      ]);
    });
  });

  group('review fixes (Phase 14)', () {
    final av = {
      'timeZone': z,
      'weekly': [
        {
          'days': [3],
          'from': '08:00',
          'to': '12:00',
        },
      ],
    };
    Map<String, Object?> q([Map<String, Object?> over = const {}]) => {
      'availability': av,
      'from': '2026-10-21T00:00+03:00[Asia/Riyadh]',
      'to': '2026-10-22T00:00+03:00[Asia/Riyadh]',
      'duration': 60,
      ...over,
    };

    test('nothing throws, whatever shape the input has (JSON from a database)', () {
      final shapes = <Object?>[
        null,
        5,
        'x',
        {'availability': null},
        q({'maxAdvanceDays': 1.5, 'now': '2026-10-20T00:00Z'}),
        q({'maxAdvanceDays': 1e9, 'now': '2026-10-20T00:00Z'}),
        q({'duration': 1 / 7}),
        q({'step': 1 / 7}),
        q({'duration': -5}),
        q({'duration': double.infinity}),
        q({'duration': double.nan}),
        q({'to': '+275760-09-13T00:00Z'}),
        q({'busy': 5}),
        q({
          'busy': [null],
        }),
        q({
          'availability': {'timeZone': z, 'weekly': 'x'},
        }),
        q({
          'availability': {
            'timeZone': z,
            'weekly': [null],
          },
        }),
        q({
          'availability': {
            'timeZone': z,
            'exceptions': [null],
          },
        }),
        q({
          'availability': {
            'timeZone': z,
            'exceptions': [
              {'date': 5},
            ],
          },
        }),
        q({
          'availability': {
            'timeZone': z,
            'exceptions': [
              {'date': '2026-10-21', 'windows': 'x'},
            ],
          },
        }),
        q({
          'availability': {
            'timeZone': z,
            'rules': [null],
          },
        }),
        q({
          'availability': {
            'timeZone': z,
            'rules': [
              {'from': '08:00', 'to': '09:00', 'start': '2026-10-01'},
            ],
          },
        }),
        q({
          'availability': {
            'timeZone': z,
            'rules': [
              {'rrule': 'FREQ=DAILY', 'from': '08:00', 'to': '09:00', 'start': '2026-10-01', 'exdates': '2026-10-19'},
            ],
          },
        }),
        q({
          'availability': {
            'timeZone': z,
            'weekly': [
              {
                'days': [3],
                'from': 8,
                'to': <String, Object?>{},
              },
            ],
          },
        }),
      ];
      for (final s in shapes) {
        expect(() => find(s), returnsNormally, reason: '$s');
        expect(() => check(s, '2026-10-21T09:00+03:00[Asia/Riyadh]'), returnsNormally, reason: '$s');
      }
    });

    test('refuses what Temporal cannot count: a step under a minute, fractional days or caps', () {
      for (final bad in <Map<String, Object?>>[
        {'step': 0.5},
        {'duration': 0.2},
        {'maxAdvanceDays': 1.5, 'now': '2026-10-20T00:00Z'},
        {'maxPerDay': 2.5},
      ]) {
        expect(find(q(bad)).problems.map((p) => p.code.code), contains('invalid-slot-query'), reason: '$bad');
      }
    });

    test('a tiny step over a long range stops at 10 000 slots, with a warning, instead of hanging', () {
      final r = find({
        'availability': {
          'timeZone': 'UTC',
          'weekly': [
            {
              'days': [1, 2, 3, 4, 5, 6, 7],
              'from': '00:00',
              'to': '24:00',
            },
          ],
        },
        'from': '2026-01-01T00:00Z',
        'to': '2027-01-01T00:00Z',
        'duration': 1,
      });
      expect(r.slots, hasLength(10000));
      expect(r.problems.map((p) => p.code.code), contains('too-many-occurrences'));
    });

    test('checkSlot says why a query is invalid, and refuses a start between milliseconds', () {
      final r = check({
        ...q(),
        'availability': {'timeZone': 'Mars/Olympus'},
      }, '2026-10-21T09:00+03:00[Asia/Riyadh]');
      expect(r.ok, isFalse);
      expect((r as SlotRefused).problems.map((p) => p.code.code).toList(), ['unknown-zone']);
      final between = check(q(), '2026-10-21T09:00:00.0005+03:00[Asia/Riyadh]');
      expect(between, isA<SlotRefused>().having((r) => r.reason, 'reason', SlotRefusal.misaligned));
    });
  });
}
