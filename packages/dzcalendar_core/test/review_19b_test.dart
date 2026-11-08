// What the 19b reviews found, each checked against the Temporal polyfill or
// the owner's decisions 9–11 (2026-11-08) before being fixed.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

NormalizeContext ctx() => NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('t'));
List<String> codes(NormalizeResult r) => [for (final p in r.problems) '${p.code.code} ${p.path}'];

void main() {
  group('IsoDuration past its limits: null, never an exception', () {
    test('Temporal refuses these; so does tryParse, and normalize says invalid-duration where it is', () {
      for (final text in ['PT99999999999999999999S', 'P99999999999999999999D', 'PT5124095576030H']) {
        expect(IsoDuration.tryParse(text), isNull, reason: text);
        expect(codes(normalizeEvent(EventInput(start: '2026-05-01T09:00[UTC]', duration: text), ctx())), [
          'invalid-duration event.duration',
        ]);
        expect(codes(normalizeEvent(EventInput(start: '2026-05-01', duration: text), ctx())), [
          'invalid-duration event.duration',
        ]);
      }
      expect(IsoDuration.tryFrom({'years': 4294967296}), isNull);
      expect(IsoDuration.tryFrom({'hours': 1099511627776}), isNotNull); // Temporal: PT1099511627776H
    });

    test('a map as Temporal reads a DurationLike: unknown keys ignored, below the millisecond read to it', () {
      expect(IsoDuration.tryFrom({'hours': 1, 'foo': 2}), IsoDuration(hours: 1));
      expect(IsoDuration.tryFrom({'foo': 2}), isNull);
      expect(IsoDuration.tryFrom({'microseconds': 1500}), IsoDuration(milliseconds: 1));
      expect(IsoDuration.tryFrom({'hours': 1, 'nanoseconds': 0}), IsoDuration(hours: 1));
    });

    test('written as Temporal writes it: milliseconds balanced into seconds', () {
      expect('${IsoDuration(milliseconds: 1500)}', 'PT1.5S');
      expect('${IsoDuration(seconds: 1, milliseconds: 1500)}', 'PT2.5S');
    });
  });

  group('below the millisecond: kept to it, said (decision 9)', () {
    test('a start written to the nanosecond is read to the millisecond, with precision-truncated', () {
      final r = normalizeEvent(EventInput(start: '2026-03-29T10:00:00.123456789[Europe/Paris]'), ctx());
      expect(codes(r), ['precision-truncated event.start']);
      expect('${(r.value!.event as TimedEvent).start}', '2026-03-29T10:00:00.123+02:00[Europe/Paris]');
      expect(codes(normalizeEvent(EventInput(start: '2026-03-29T10:00:00.123000[Europe/Paris]'), ctx())), isEmpty);
    });

    test('a duration below the millisecond too; a fraction of an hour is not', () {
      expect(codes(normalizeEvent(EventInput(start: '2026-05-01T09:00[UTC]', duration: 'PT0.0015S'), ctx())), [
        'precision-truncated event.duration',
      ]);
      expect(codes(normalizeEvent(EventInput(start: '2026-05-01T09:00[UTC]', duration: 'PT0.0001H'), ctx())), isEmpty);
    });

    test('ids derived from what is written to the millisecond: the same either way', () {
      String id(String start) => normalizeMany(
        [EventInput(start: start, title: 'x')],
        ctx(),
        sourceId: 'api',
      ).items.single.event.id;
      expect(id('2026-03-29T10:00:00.123456789[Europe/Paris]'), id('2026-03-29T10:00:00.123[Europe/Paris]'));
    });
  });

  group('reading moments', () {
    test('offset-mismatch says the text as written', () {
      final r = normalizeEvent(EventInput(start: '2026-07-01T09:00+05:00[Europe/Paris]'), ctx());
      expect(r.problems.single.detail, '2026-07-01T09:00+05:00[Europe/Paris] → +02:00');
    });

    test('a zone that is no zone is said first, whatever else is wrong', () {
      expect(codes(normalizeEvent(EventInput(start: 'garbage[Foo/Bar]'), ctx())), ['unknown-zone event.start']);
      expect(codes(normalizeEvent(EventInput(start: '2026-13-45[Foo/Bar]'), ctx())), ['unknown-zone event.start']);
    });

    test("Temporal's range: dates from -271821-04-19 to +275760-09-13, zoned instants within it", () {
      expect(
        normalizeEvent(
          EventInput(start: '+275760-09-13'),
          ctx(),
        ).problems.where((p) => p.isError).map((p) => p.code.code),
        [
          'invalid-duration', // its exclusive end, the 14th, is past the range
        ],
      );
      expect(codes(normalizeEvent(EventInput(start: '+275760-09-14'), ctx())), ['invalid-start event.start']);
      expect(normalizeEvent(EventInput(start: '-271821-04-19', end: '-271821-04-20'), ctx()).ok, isTrue);
      expect(codes(normalizeEvent(EventInput(start: '-271821-04-18'), ctx())), ['invalid-start event.start']);
      expect(codes(normalizeEvent(EventInput(start: '+275760-09-13T01:00Z[UTC]'), ctx())), [
        'invalid-start event.start',
      ]);
    });

    test('fromJson takes a Map<Object?, Object?>, as platform channels give', () {
      final Map<Object?, Object?> json = {
        'start': '2026-05-01',
        'extendedProps': <Object?, Object?>{'room': 12},
      };
      expect(normalizeEvent(EventInput.fromJson(json), ctx()).value!.event.props, {'room': 12});
    });
  });

  group('ZonedDateTime == (decision 11): a link is its zone, as Temporal.equals', () {
    test('Asia/Calcutta and Asia/Kolkata', () {
      final at = Instant.parse('2026-01-01T00:00:00Z');
      final a = at.inZone('Asia/Calcutta');
      final b = at.inZone('Asia/Kolkata');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.zone, 'Asia/Calcutta'); // the name written is kept
      expect(at.inZone('Europe/Paris') == at.inZone('UTC'), isFalse);
    });
  });

  group('CalEvent: copyWith, identity, revision, eventEquals', () {
    TimedEvent base() =>
        normalizeEvent(
              EventInput(
                start: '2026-05-01T09:00[Europe/Paris]',
                title: 'x',
                tone: 'blue',
                url: 'u',
                groupId: 'g',
                extendedProps: {
                  'a': [
                    1,
                    {'b': 2},
                  ],
                },
              ),
              ctx(),
            ).value!.event
            as TimedEvent;

    test('a nullable field is cleared by null, kept when not given', () {
      final e = base();
      expect(e.copyWith(tone: null).tone, isNull);
      expect(e.copyWith(title: 'y').tone, 'blue');
      expect(e.withIdentity('n', 's').withIdentity('n', null).sourceId, isNull);
      final day = normalizeEvent(EventInput(start: '2026-05-01'), ctx()).value!.event;
      expect(day.withIdentity('n', 's').withIdentity('n', null).sourceId, isNull);
      expect(e.withRevision(7).revision, 7);
    });

    test('eventEquals: revision ignored, props by structure, every other field counts', () {
      final e = base();
      expect(eventEquals(e, e.withRevision(9)), isTrue);
      expect(
        eventEquals(
          e,
          e.copyWith(
            props: {
              'a': [
                1,
                {'b': 2},
              ],
            },
          ),
        ),
        isTrue,
      );
      final other = Instant.parse('2026-05-01T08:00:00Z').inZone('Asia/Tokyo');
      // One change per field of CalEvent and TimedEvent: a field forgotten in
      // eventEquals leaves its line equal, and fails here.
      final changed = <String, TimedEvent>{
        'id': e.copyWith(id: 'z'),
        'groupId': e.copyWith(groupId: null),
        'title': e.copyWith(title: 'z'),
        'resourceIds': e.copyWith(resourceIds: ['r']),
        'display': e.copyWith(display: EventDisplay.block),
        'status': e.copyWith(status: EventStatus.tentative),
        'busy': e.copyWith(busy: false),
        'perms': e.copyWith(perms: const EventPerms(start: false, duration: true, resource: true)),
        'classNames': e.copyWith(classNames: ['c']),
        'tone': e.copyWith(tone: null),
        'url': e.copyWith(url: null),
        'props': e.copyWith(props: {'a': 1}),
        'sourceId': e.copyWith(sourceId: 's'),
        'ref': e.copyWith(ref: const EventRef('s', 'k')),
        'start': e.copyWith(start: other),
        'end': e.copyWith(end: other),
        'zoneGuessed': e.copyWith(zoneGuessed: true),
        'ongoing': e.copyWith(ongoing: true),
        'expectedEnd': e.copyWith(expectedEnd: other),
      };
      for (final MapEntry(:key, :value) in changed.entries) {
        expect(eventEquals(e, value), isFalse, reason: key);
      }
    });
  });
}
