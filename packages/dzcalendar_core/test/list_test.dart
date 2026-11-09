// Ported from the TypeScript core's list.test.ts (hand-written expectations,
// copied as values: from the zones' published rules — Paris falls back on
// 25 Oct 2026 at 03:00 → 02:00; Lord Howe springs from 02:00 to 02:30 on
// 4 Oct 2026; Apia skipped 30 Dec 2011 — never from this code's output).
//
// Ported: buildListModel (9). Skipped: none. Translation notes:
// - `{ ...BUILTIN_VIEWS[view], hiddenDays }` is `spec.copyWith(hiddenDays:)`;
//   `display: 'background'` is `EventDisplay.background`.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

PlainDate d(String s) => PlainDate.parse(s);
final nav = NavContext(firstDay: 1, today: d('2026-10-21'));

ListModel model(
  String zone,
  List<EventInput> events,
  String view,
  String at, {
  bool includeEmpty = false,
  List<int>? hiddenDays,
}) {
  final store = EventStore();
  store.replaceSourceChunk(
    't',
    '*',
    normalizeMany(
      events,
      NormalizeContext(displayZone: zone, newId: createIdGenerator('x')),
      sourceId: 't',
    ).items,
  );
  final base = builtinViews[view]!;
  final spec = hiddenDays == null ? base : base.copyWith(hiddenDays: hiddenDays);
  return buildListModel(
    computeViewRange(d(at), spec, nav),
    store.snapshot,
    ListOptions(displayZone: zone, includeEmpty: includeEmpty),
  );
}

List<Object> rows(ListModel m) => [
  for (final day in m.days)
    [
      '${day.date}',
      [
        for (final e in day.entries)
          '${e.instance.event.id}'
              '${e.allDay ? ' all-day' : ' ${'${e.start}'.substring(11, 22)}–${'${e.end}'.substring(11, 22)}'}'
              '${e.startsHere ? '' : ' <'}${e.endsHere ? '' : ' >'}',
      ],
    ],
];

void main() {
  group('buildListModel', () {
    test('the 25-hour Sunday in Paris: both 02:30s, in the order they happen', () {
      final m = model(
        'Europe/Paris',
        [
          EventInput(id: 'second', start: '2026-10-25T02:30:00+01:00[Europe/Paris]', duration: {'minutes': 15}),
          EventInput(id: 'first', start: '2026-10-25T02:30:00+02:00[Europe/Paris]', duration: {'minutes': 15}),
        ],
        'listDay',
        '2026-10-25',
      );
      expect([for (final x in m.days) x.lengthMinutes], [1500]);
      expect(rows(m), [
        [
          '2026-10-25',
          ['first 02:30:00+02–02:45:00+02', 'second 02:30:00+01–02:45:00+01'],
        ],
      ]);
    });

    test('Lord Howe’s spring day is 23 h 30', () {
      final m = model(
        'Australia/Lord_Howe',
        [EventInput(id: 'a', start: '2026-10-04T09:00[Australia/Lord_Howe]')],
        'listDay',
        '2026-10-04',
      );
      expect(m.days.first.lengthMinutes, 1410);
    });

    test('Apia, December 2011: the 30th does not exist, an event over it shows on the 29th and the 31st', () {
      // 29 Dec 23:00 at −10:00 plus two hours is 31 Dec 01:00 at +14:00.
      final m = model(
        'Pacific/Apia',
        [
          EventInput(id: 'jump', start: '2011-12-29T23:00[Pacific/Apia]', duration: {'hours': 2}),
        ],
        'listWeek',
        '2011-12-28',
      );
      expect(rows(m), [
        [
          '2011-12-29',
          ['jump 23:00:00-10–00:00:00+14 >'],
        ],
        [
          '2011-12-31',
          ['jump 00:00:00+14–01:00:00+14 <'],
        ],
      ]);
    });

    test('a night over midnight is two entries; an end at midnight does not touch the next day', () {
      final m = model(
        'Europe/Paris',
        [
          EventInput(id: 'night', start: '2026-10-20T22:00[Europe/Paris]', end: '2026-10-21T02:00[Europe/Paris]'),
          EventInput(id: 'late', start: '2026-10-20T23:00[Europe/Paris]', end: '2026-10-21T00:00[Europe/Paris]'),
        ],
        'listWeek',
        '2026-10-20',
      );
      expect(rows(m), [
        [
          '2026-10-20',
          ['night 22:00:00+02–00:00:00+02 >', 'late 23:00:00+02–00:00:00+02'],
        ],
        [
          '2026-10-21',
          ['night 00:00:00+02–02:00:00+02 <'],
        ],
      ]);
    });

    test(
      'all-day first; a multi-day event on each of its days; a timed event covering a day counts as all-day there',
      () {
        final m = model(
          'Europe/Paris',
          [
            EventInput(id: 'trip', start: '2026-10-19', end: '2026-10-22'),
            EventInput(id: 'early', start: '2026-10-20T08:00[Europe/Paris]'),
            EventInput(id: 'long', start: '2026-10-20T00:00[Europe/Paris]', end: '2026-10-22T00:00[Europe/Paris]'),
          ],
          'listWeek',
          '2026-10-19',
        );
        expect(rows(m), [
          [
            '2026-10-19',
            ['trip all-day >'],
          ],
          [
            '2026-10-20',
            ['trip all-day < >', 'long all-day >', 'early 08:00:00+02–09:00:00+02'],
          ],
          [
            '2026-10-21',
            ['trip all-day <', 'long all-day <'],
          ],
        ]);
      },
    );

    test('same start: longer first, then by title', () {
      final m = model(
        'UTC',
        [
          EventInput(id: 'b', title: 'Beta', start: '2026-10-20T09:00Z[UTC]', duration: {'minutes': 30}),
          EventInput(id: 'a', title: 'Alpha', start: '2026-10-20T09:00Z[UTC]', duration: {'minutes': 30}),
          EventInput(id: 'c', title: 'Zed', start: '2026-10-20T09:00Z[UTC]', duration: {'hours': 2}),
        ],
        'listDay',
        '2026-10-20',
      );
      expect([for (final e in m.days.first.entries) e.instance.event.id], ['c', 'a', 'b']);
    });

    test('background events are not listed; a zero-length event is', () {
      final m = model(
        'Europe/Paris',
        [
          EventInput(id: 'bg', start: '2026-10-20T08:00[Europe/Paris]', display: EventDisplay.background),
          EventInput(id: 'pin', start: '2026-10-20T10:00[Europe/Paris]', end: '2026-10-20T10:00[Europe/Paris]'),
        ],
        'listDay',
        '2026-10-20',
      );
      expect(rows(m), [
        [
          '2026-10-20',
          ['pin 10:00:00+02–10:00:00+02'],
        ],
      ]);
    });

    test('listYear covers the year; only days with events unless includeEmpty', () {
      final events = [
        EventInput(id: 'jan', start: '2026-01-02T09:00[Europe/Paris]'),
        EventInput(id: 'dec', start: '2026-12-31T09:00[Europe/Paris]'),
      ];
      expect(
        [for (final x in model('Europe/Paris', events, 'listYear', '2026-06-15').days) '${x.date}'],
        ['2026-01-02', '2026-12-31'],
      );
      expect(model('Europe/Paris', events, 'listYear', '2026-06-15', includeEmpty: true).days, hasLength(365));
      // Hidden days are not days of the list.
      final weekdays = model('Europe/Paris', [], 'listWeek', '2026-10-20', includeEmpty: true, hiddenDays: [6, 7]);
      expect(
        [for (final x in weekdays.days) '${x.date}'],
        ['2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22', '2026-10-23'],
      );
    });

    test('listMonth is the month, nothing of its neighbours', () {
      final m = model(
        'Europe/Paris',
        [
          EventInput(id: 'sep', start: '2026-09-30T09:00[Europe/Paris]'),
          EventInput(id: 'oct', start: '2026-10-01T09:00[Europe/Paris]'),
          EventInput(id: 'nov', start: '2026-11-01T09:00[Europe/Paris]'),
        ],
        'listMonth',
        '2026-10-15',
      );
      expect(
        [
          for (final x in m.days)
            for (final e in x.entries) e.instance.event.id,
        ],
        ['oct'],
      );
    });
  });
}
