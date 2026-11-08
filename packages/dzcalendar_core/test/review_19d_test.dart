// What the 19d architect and code reviews found, each pinned by a test, and
// the owner's decisions 18–21 (2026-11-08). Expectations written by hand
// from the TS's behaviour (checked against it where it says so) and the
// zones' published rules.

import 'dart:convert';

import 'package:dzcalendar_core/internal.dart';
import 'package:dzcalendar_core/src/ical/zones.dart' show fixedZone;
import 'package:test/test.dart';

const z = 'Asia/Riyadh';

CalEvent norm(EventInput input, [String zone = z]) {
  final r = normalizeEvent(input, NormalizeContext(displayZone: zone, newId: createIdGenerator('t')));
  return (r.value! as NormalizedEvent).event;
}

Map<String, Object?> query([Map<String, Object?> over = const {}]) => {
  'availability': {
    'timeZone': z,
    'weekly': [
      {
        'days': [3],
        'from': '08:00',
        'to': '12:00',
      },
    ],
  },
  'from': '2026-10-21T00:00+03:00[Asia/Riyadh]',
  'to': '2026-10-22T00:00+03:00[Asia/Riyadh]',
  'duration': 60,
  ...over,
};

void main() {
  group('business hours never throw where they are used', () {
    test('a zone that is none is refused when the rule is made, not in the middle of a move', () {
      expect(
        () => BusinessHoursRule(
          daysOfWeek: const [1],
          from: const WallTime(9),
          to: const WallTime(17),
          timeZone: 'Nope/Zone',
        ),
        throwsArgumentError,
      );
      expect(
        () => BusinessHoursRule(daysOfWeek: const [1], from: const WallTime(25), to: const WallTime(17)),
        throwsArgumentError,
      );
      final (hours, problems) = BusinessHours.fromJson({
        'daysOfWeek': [1],
        'start': '09:00',
        'end': '17:00',
        'timeZone': 'Nope/Zone',
      }, 'resources[0].businessHours');
      expect(hours, isNull);
      expect(problems.single.code, ProblemCode.invalidOption);
      expect(problems.single.path, 'resources[0].businessHours');
    });

    test('a resource read from JSON with such hours drops them; the move is then checked without them', () {
      final tree = buildResourceTreeFromJson([
        {
          'id': 'dr',
          'eventConstraint': 'businessHours',
          'businessHours': {
            'daysOfWeek': [1],
            'start': '09:00',
            'end': '17:00',
            'timeZone': 'Nope/Zone',
          },
        },
      ]);
      expect(tree.problems.map((p) => '${p.code.code}@${p.path}'), ['invalid-resource@resources[0].businessHours']);
      final store = EventStore();
      store.replaceSourceChunk(
        'c',
        'all',
        normalizeMany(
          [EventInput(id: 'a', start: '2026-10-21T08:00[$z]', duration: 'PT1H', resourceId: 'dr')],
          NormalizeContext(displayZone: z, newId: createIdGenerator('c')),
          sourceId: 'c',
        ).items,
      );
      final ctx = CommandContext(
        normalize: NormalizeContext(displayZone: z, newId: createIdGenerator('n')),
        rules: RulesContext(displayZone: z, resources: tree.tree),
      );
      final r = applyCommand(store.snapshot, MoveEvent('a', '2026-10-21T13:00[$z]', end: '2026-10-21T14:00[$z]'), ctx);
      // No hours at all: the constraint constrains nothing (as on the web).
      expect(r.ok, isTrue);
    });
  });

  group('series meet the rules in one query', () {
    test('a new daily series against 200 open ones: refused on its first clash, the same one as before', () {
      final store = EventStore();
      final ctx = NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('b'));
      store.replaceSourceChunk(
        'src',
        'all',
        normalizeMany(
          [
            for (var i = 0; i < 200; i++)
              EventInput(
                id: 's$i',
                start: '2026-01-05T${(8 + i % 10).toString().padLeft(2, '0')}:00[Europe/Paris]',
                duration: 'PT30M',
                rrule: 'FREQ=DAILY',
                resourceId: 'r${i % 50}',
              ),
          ],
          ctx,
          sourceId: 'src',
        ).items,
      );
      final cctx = CommandContext(
        normalize: ctx,
        rules: const RulesContext(displayZone: 'Europe/Paris', overlap: RulesContext.noOverlap),
      );
      final sw = Stopwatch()..start();
      final r = applyCommand(
        store.snapshot,
        CreateEvent(
          EventInput(
            id: 'm',
            start: '2026-11-09T08:00[Europe/Paris]',
            duration: 'PT30M',
            rrule: 'FREQ=DAILY',
            resourceId: 'r0',
          ),
        ),
        cctx,
      );
      expect(r.ok, isFalse);
      // s0 starts at 08:00 on r0: the series' first occurrence meets it.
      expect(r.violations.single.code, ViolationCode.overlap);
      expect(r.violations.single.detail, startsWith('s0@2026-11-09T08:00'));
      // 5.1 s before the fix (one query per occurrence); well under a second now.
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('moments are read as the web reads them', () {
    test('an offset the zone does not have there is refused (Temporal’s offset: reject)', () {
      expect(readMoment('2026-10-21T08:00:00+05:00[Asia/Riyadh]'), isNull);
      expect(readMoment('2026-10-21T08:00:00+03:00[Asia/Riyadh]'), Instant.parse('2026-10-21T05:00:00Z'));
      final (req, problems) = SlotRequest.fromJson(query({'from': '2026-10-21T08:00:00+05:00[Asia/Riyadh]'}));
      expect(req, isNull);
      expect(problems.single.path, 'from');
      expect(problems.single.code, ProblemCode.invalidSlotQuery);
    });

    test('a range past what Temporal holds is refused at once, not walked day by day', () {
      final sw = Stopwatch()..start();
      final (req, read) = SlotRequest.fromJson(query({'to': '+275760-09-13T00:00Z'}));
      final r = req!.find();
      expect([...read, ...r.problems].map((p) => p.code.code), ['invalid-slot-query']);
      expect(r.slots, isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('a missing field is said "undefined", a weekday list as JSON (the web’s details)', () {
      final (_, missing) = SlotRequest.fromJson({...query()}..remove('duration'));
      expect(missing.single.detail, 'undefined');
      final (_, days) = SlotRequest.fromJson(
        query({
          'availability': {
            'timeZone': z,
            'weekly': [
              {
                'days': [0, 8],
                'from': '08:00',
                'to': '09:00',
              },
            ],
          },
        }),
      );
      expect(days.single.detail, '[0,8]');
    });

    test('a non-object availability rule is read on as the web reads its missing fields', () {
      final (_, problems) = SlotRequest.fromJson(
        query({
          'availability': {
            'timeZone': z,
            'rules': [5],
          },
        }),
      );
      expect(problems.map((p) => '${p.code.code}@${p.path}:${p.detail}'), [
        'invalid-availability@availability.rules[0]:undefined–undefined',
        'invalid-availability@availability.rules[0].start:undefined',
        'invalid-rrule@availability.rules[0].rrule:undefined',
      ]);
    });
  });

  group('iCal', () {
    String cal(List<String> body) => ['BEGIN:VCALENDAR', ...body, 'END:VCALENDAR'].join('\r\n');

    test('an empty UID is none: the event is kept, and an override without one is a plain event', () {
      final r = parseICal(
        cal(['BEGIN:VEVENT', 'UID:   ', 'RECURRENCE-ID:20261006T090000Z', 'DTSTART:20261006T110000Z', 'END:VEVENT']),
      );
      final e = r.events.single;
      expect(e.id, isNull);
      expect(e.seriesId, isNull);
      expect(e.recurrenceId, isNull);
    });

    test('a default zone that is none never throws; an empty one is none', () {
      final text = cal(['BEGIN:VEVENT', 'UID:a', 'DTSTART:20261006T090000Z', 'END:VEVENT']);
      final bad = parseICal(text, defaultZone: 'Mars/Olympus');
      expect(bad.events, isEmpty);
      expect(bad.problems.map((p) => p.code.code), ['ical-syntax']);
      final empty = parseICal(text, defaultZone: '');
      expect(empty.events.single.start, '2026-10-06T09:00:00[UTC]');
    });

    test('a moment whose offset the zone does not have is left out of the file', () {
      final text = serializeICal([
        EventInput(id: 'a', start: '2026-10-21T08:00+05:00[Asia/Riyadh]', end: '2026-10-21T09:00+03:00[Asia/Riyadh]'),
      ], stamp: Instant.parse('2026-11-08T10:00:00Z'));
      // The start is unreadable (event skipped), as the web's Temporal.ZonedDateTime.from refuses it.
      expect(text, isNot(contains('BEGIN:VEVENT')));
    });

    test('a VTIMEZONE at -00:44:30 (Monrovia before 1972) is written to the minute as JavaScript rounds', () {
      // -44.5 minutes: Math.round gives -44, Dart's round -45.
      expect(fixedZone(-2670), '-00:44');
    });
  });

  group('JavaScript’s text and rounding', () {
    test('String(x) for lists and objects, Math.round for halves', () {
      expect(jsText(['a', 'b']), 'a,b');
      expect(jsText({'a': 1}), '[object Object]');
      expect(jsText(2.0), '2');
      expect(jsRound(-44.5), -44);
      expect(jsRound(44.5), 45);
    });
  });

  group('EventInput.toJson hands out copies, and no guesses', () {
    test('changing the JSON leaves the input as it was; a time type is its ISO text', () {
      final input = EventInput(
        id: 'a',
        start: ZonedDateTime(Instant.parse('2026-10-21T05:00:00Z'), z),
        duration: IsoDuration(hours: 1),
        resourceIds: ['r1'],
        extendedProps: {
          'tags': ['x'],
        },
      );
      final json = input.toJson();
      (json['resourceIds']! as List).add('r2');
      ((json['extendedProps']! as Map)['tags']! as List).add('y');
      expect(input.resourceIds, ['r1']);
      expect(input.extendedProps!['tags'], ['x']);
      expect(json['start'], '2026-10-21T08:00:00+03:00[Asia/Riyadh]');
      expect(json['duration'], 'PT1H');
    });

    test('a value that is no JSON is passed on for jsonEncode to refuse, not turned into text', () {
      final when = DateTime.utc(2026);
      final json = EventInput(id: 'a', start: '2026-10-21', extendedProps: {'when': when}).toJson();
      expect((json['extendedProps']! as Map)['when'], same(when));
      expect(() => jsonEncode(json), throwsA(isA<JsonUnsupportedObjectError>()));
    });
  });

  group('the store exported as inputs (decision 21)', () {
    test('series and events, normalized again, give the same store', () {
      final ctx = NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('e'));
      final store = EventStore();
      store.replaceSourceChunk(
        'src',
        'all',
        normalizeMany(
          [
            EventInput(
              id: 's',
              title: 'Consultation',
              start: '2026-10-05T09:00[Europe/Paris]',
              duration: 'PT30M',
              rrule: 'FREQ=WEEKLY;BYDAY=MO',
              exdate: ['2026-10-12T09:00[Europe/Paris]'],
            ),
            EventInput(id: 'x', title: 'Garde', start: '2026-10-07', allDay: true),
          ],
          ctx,
          sourceId: 'src',
        ).items,
      );
      final inputs = exportInputs(store.snapshot);
      expect(inputs.map((i) => i.id), ['s', 'x']);
      expect(inputs.first.rrule, 'FREQ=WEEKLY;BYDAY=MO');
      expect(inputs.first.exdate, hasLength(1));
      final again = EventStore()..replaceSourceChunk('src', 'all', normalizeMany(inputs, ctx, sourceId: 'src').items);
      final w = viewWindow(PlainDate(2026, 10, 1), PlainDate(2026, 11, 1), 'Europe/Paris');
      String shown(EventStore s) => [
        for (final i in s.snapshot.queryInstances(w))
          '${i.event.title} ${switch (i.event) {
            TimedEvent(:final start) => '$start',
            AllDayEvent(:final start) => '$start',
          }}',
      ].join('\n');
      expect(shown(again), shown(store));
      // 5, 19, 26 October (the 12th excluded) and the all-day 7th.
      expect(shown(store).split('\n'), hasLength(4));
      // And the whole file, the way an app shares it: the store keeps an EXDATE as an instant, written in
      // UTC as the web writes it (09:00 in Paris on 12 October, summer time, is 07:00Z).
      expect(serializeICal(inputs, stamp: Instant.parse('2026-11-08T10:00:00Z')), contains('EXDATE:20261012T070000Z'));
    });
  });

  group('CalEvent.movedTo (decision 21)', () {
    test('a timed event dragged to the all-day row and back keeps everything but its time', () {
      final e = norm(
        EventInput(id: 'a', title: 'Visite', start: '2026-10-21T08:00[$z]', duration: 'PT1H', resourceIds: ['r1']),
      );
      final days = e.movedToDays(PlainDate(2026, 10, 22), PlainDate(2026, 10, 23), resourceIds: ['r2']);
      expect(days.allDay, isTrue);
      expect(days.title, 'Visite');
      expect(days.resourceIds, ['r2']);
      final back = days.movedToTime(
        ZonedDateTime(Instant.parse('2026-10-22T06:00:00Z'), z),
        ZonedDateTime(Instant.parse('2026-10-22T07:00:00Z'), z),
      );
      expect('${back.start}', '2026-10-22T09:00:00+03:00[Asia/Riyadh]');
      expect(back.id, 'a');
      expect(back.resourceIds, ['r2']);
      expect(() => e.movedToDays(PlainDate(2026, 10, 22), PlainDate(2026, 10, 21)), throwsArgumentError);
    });
  });

  group('value equality (decision 21)', () {
    test('equal configurations are equal, so a widget can tell nothing changed', () {
      Availability av() => Availability(
        timeZone: z,
        weekly: [
          WeeklyWindow(days: [3], window: const Window(WallTime(8), WallTime.endOfDay)),
        ],
      );
      expect(av(), av());
      expect(
        SlotRules(availability: av(), duration: const Duration(minutes: 30)),
        SlotRules(availability: av(), duration: const Duration(minutes: 30)),
      );
      expect(
        SlotRules(availability: av(), duration: const Duration(minutes: 30)),
        isNot(SlotRules(availability: av(), duration: const Duration(minutes: 45))),
      );
      expect(BusinessHours.fromJson(true).$1, BusinessHours.standard);
      expect(ConstraintSpec.fromJson({'groupId': 'g'}).$1, ConstraintSpec.group('g'));
      expect(const DayScale(), TimelineScale.day);
      expect(
        const RulesContext(displayZone: z, overlap: RulesContext.noOverlap),
        const RulesContext(displayZone: z, overlap: RulesContext.noOverlap),
      );
      expect(ResourceInput.fromJson({'id': 'a', 'unit': 'B'}).$1, ResourceInput.fromJson({'id': 'a', 'unit': 'B'}).$1);
    });

    test('WallTime: 24:00 is the next midnight, and nothing past it', () {
      expect(WallTime.tryParse('24:00'), WallTime.endOfDay);
      expect(WallTime.tryParse('24:30'), isNull);
      expect(WallTime.tryParse('08:30'), const WallTime(8, 30));
      expect(const WallTime(25).isValid, isFalse);
      expect(WallTime.endOfDay.msOfDay, 86400000);
    });
  });
}
