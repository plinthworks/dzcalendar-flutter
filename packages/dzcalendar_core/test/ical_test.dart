// Ported from the main repository's packages/ical/test/ical.test.ts and
// roundtrip.test.ts (hand-written expectations, copied as values). The
// fixtures are in test/fixtures/ical/, copied unchanged.
//
// Ported: lines (3), parseICal (17), into the store (5), serializeICal (4),
// review fixes (4 of 5), store → iCal → store (4), parse → serialize → parse
// (1 + one per fixture).
// Skipped:
// - icalSource (3 tests) and review fixes' "a webcal:// link is fetched over
//   https": the source (fetch, staleAfter, retry) is not ported — it comes with
//   the source manager (owner's decision 16, 2026-11-08).
// Translation notes:
// - `toMatchObject` compares the fields named against `EventInput.toJson()`.
// - unfold/fold/parseLine are imported from src/ical/lines.dart (not exported:
//   the text layer is the package's own).
// - "a long series keeps its zone past the years written" read the written
//   VTIMEZONE with the private `components`/`observances` and called `offsetIn`.
//   Here the same VTIMEZONE is read back by `parseICal` under a TZID no IANA
//   name or path gives ("Written NY"), with events in summer and winter 2034:
//   only its own rules (the RRULEs) can place 2034, and the reading gives
//   −04:00 and −05:00, as the TS expected of `offsetIn`.
// - store → iCal → store: `exportInputs` is not ported; a test helper writes
//   the snapshot back as inputs as the TS export.ts does (series: base + rules,
//   exdates, rdates; events: an override with its seriesId/recurrenceId).
// - A VTIMEZONE matched to an IANA zone: the candidates are our data's IANA
//   canonical zones, the web's are Intl's (CLDR names). No test here depends
//   on a tie between those (the Paris-like fixture is checked by offsets).

import 'dart:convert';
import 'dart:io';

import 'package:dzcalendar_core/internal.dart';
import 'package:dzcalendar_core/src/ical/lines.dart';
import 'package:test/test.dart';

String fixture(String name) => File('test/fixtures/ical/$name.ics').readAsStringSync();
String cal(List<String> lines) => ['BEGIN:VCALENDAR', 'VERSION:2.0', ...lines, 'END:VCALENDAR'].join('\r\n');
List<String> codes(ParsedICal r) => [for (final p in r.problems) p.code.code];
Map<String, Object?> json(EventInput e) => e.toJson();

/// The fields of [expected] as [actual]'s JSON has them (`toMatchObject`).
void matches(EventInput actual, Map<String, Object?> expected) {
  final j = actual.toJson();
  expect({for (final k in expected.keys) k: j[k]}, expected);
}

String startText(CalEvent e) => switch (e) {
  TimedEvent(:final start) => '$start',
  AllDayEvent(:final start) => '$start',
};

String endText(CalEvent e) => switch (e) {
  TimedEvent(:final end) => '$end',
  AllDayEvent(:final end) => '$end',
};

EventStore storeOf(List<EventInput> events, NormalizeContext ctx) {
  final store = EventStore();
  store.replaceSourceChunk('ics', '*', normalizeMany(events, ctx, sourceId: 'ics').items);
  return store;
}

/// The TS export.ts: everything a snapshot holds as inputs, series first.
List<EventInput> exportInputs(StoreSnapshot snap) {
  EventInput seriesInput(Series s) {
    final i = toInput(s.base).toJson();
    final rules = s.set.rules;
    return EventInput.fromJson({
      ...i,
      'id': s.id,
      'rrule': rules.length == 1 ? serializeRRule(rules.first) : [for (final r in rules) serializeRRule(r)],
      if (s.set.exdates.isNotEmpty) 'exdate': [for (final x in s.set.exdates) '$x'],
      if (s.set.rdates.isNotEmpty) 'rdate': [for (final x in s.set.rdates) '$x'],
    });
  }

  EventInput eventInput(CalEvent e) {
    final ref = e.ref;
    if (ref == null) return toInput(e);
    return EventInput.fromJson({...toInput(e).toJson(), 'seriesId': ref.seriesId, 'recurrenceId': ref.key});
  }

  return [for (final s in snap.allSeries) seriesInput(s), for (final e in snap.allEvents) eventInput(e)];
}

void main() {
  group('lines', () {
    test('unfolds a continuation (space or tab), CRLF or LF', () {
      expect([for (final l in unfold('A:1\r\n 2\n\t3\nB:4')) l.text], ['A:123', 'B:4']);
    });
    test('reads quoted parameters with commas and colons', () {
      final l = parseLine('ORGANIZER;CN="Dupont, Marie";X=a,"b:c":mailto:m@x', 1)!;
      expect(l.params['CN'], ['Dupont, Marie']);
      expect(l.params['X'], ['a', 'b:c']);
      expect(l.value, 'mailto:m@x');
    });
    test('folds at 75 octets without cutting a character', () {
      final line = 'SUMMARY:${'é' * 50}🎉${'x' * 40}';
      final out = fold(line);
      for (final part in out.split('\r\n').where((p) => p.isNotEmpty)) {
        expect(utf8.encode(part).length, lessThanOrEqualTo(75));
      }
      expect(unfold(out).first.text, line);
    });
  });

  group('parseICal', () {
    test('reads an IANA TZID as that zone (#7456): Chicago 09:00 stays Chicago 09:00', () {
      final r = parseICal(fixture('05-series-override-7456'));
      matches(r.events[0], {
        'id': 'review@example.com',
        'start': '2026-10-20T09:00:00[America/Chicago]',
        'rrule': 'FREQ=DAILY;COUNT=5',
      });
      matches(r.events[1], {
        'id': 'review@example.com@20261022T090000',
        'seriesId': 'review@example.com',
        'recurrenceId': '2026-10-22T09:00:00[America/Chicago]',
        'start': '2026-10-22T14:00:00[America/Chicago]',
      });
    });

    test('dates are all-day; no end and no duration is one day, or no time for a moment (RFC 5545 §3.6.1)', () {
      matches(parseICal(fixture('23-duration-default-date')).events[0], {
        'allDay': true,
        'start': '2026-10-31',
        'duration': 'P1D',
      });
      matches(parseICal(fixture('24-duration-default-time')).events[0], {'duration': 'PT0S'});
      matches(parseICal(fixture('03-rfc-multiday-allday')).events[0], {
        'start': '2007-06-28',
        'end': '2007-07-09',
        'busy': false,
      });
    });

    test('UTC times are UTC, or the calendar zone’s when the file names one (same moment)', () {
      expect(parseICal(fixture('01-rfc-simple-utc')).events[0].start, '1997-07-14T17:00:00[UTC]');
      // 07:00Z on 21 October 2026 is 09:00 in Paris (CEST, +02:00).
      expect(
        parseICal(fixture('22-utc-with-calendar-zone')).events[0].start,
        '2026-10-21T09:00:00+02:00[Europe/Paris]',
      );
    });

    test('floating times: X-WR-TIMEZONE, then defaultZone, then left floating', () {
      expect(parseICal(fixture('21-apple-wr-timezone')).events[0].start, '2026-10-21T09:00:00[America/Chicago]');
      expect(
        parseICal(fixture('15-bare-lf-floating'), defaultZone: 'Asia/Kolkata').events[0].start,
        '2026-10-21T09:00:00[Asia/Kolkata]',
      );
      expect(parseICal(fixture('15-bare-lf-floating')).events[0].start, '2026-10-21T09:00:00');
    });

    test('Windows names through the CLDR table, a Mozilla path through its IANA tail', () {
      expect(windowsZone('romance standard time'), 'Europe/Paris');
      expect(windowsZone('India Standard Time'), 'Asia/Kolkata');
      expect(windowsZone('Lord Howe Standard Time'), 'Australia/Lord_Howe');
      final outlook = parseICal(fixture('16-outlook-windows'));
      expect(outlook.events[0].start, '2026-10-21T14:00:00[Europe/Paris]');
      expect(outlook.problems, isEmpty);
      expect(outlook.events[0].extendedProps, {
        'organizer': {'name': 'Dupont, Marie', 'email': 'marie@example.com'},
      });
      expect(parseICal(fixture('17-outlook-us-eastern')).events[0].start, '2026-11-02T09:00:00[America/New_York]');
      expect(parseICal(fixture('20-mozilla-tzid')).events[0].start, '2026-10-21T09:00:00[Europe/Paris]');
    });

    test('a custom VTIMEZONE is matched to the IANA zone with the same changes, and says it guessed', () {
      final r = parseICal(fixture('18-custom-vtimezone-paris-like'));
      expect(codes(r), ['zone-guessed']);
      final zone = RegExp(r'\[(.+)\]').firstMatch(r.events[0].start! as String)![1]!;
      // Same offsets as Paris all year round: +01:00 in winter, +02:00 from the last Sunday of March to the last of October.
      for (final at in const [
        '2026-01-15T12:00Z',
        '2026-03-29T00:59:59Z',
        '2026-03-29T01:00Z',
        '2026-10-25T00:59:59Z',
        '2026-10-25T01:00Z',
        '2026-07-15T12:00Z',
      ]) {
        final i = Instant.parse(at);
        expect(ZonedDateTime(i, zone).offset, ZonedDateTime(i, 'Europe/Paris').offset, reason: at);
      }
    });

    test('a VTIMEZONE no IANA zone matches falls back to its fixed offset, and says so', () {
      final r = parseICal(fixture('19-custom-vtimezone-nomatch'));
      expect(codes(r), contains('zone-fixed-offset'));
      expect(r.events[0].start, '2026-10-21T09:00:00+05:17[+05:17]');
    });

    test('…by its own rules: each time gets the offset in force then, summer and winter', () {
      // +05:17 in winter, +06:17 from the last Sunday of March 02:00 to the last Sunday of October 03:00: no IANA zone does that.
      final r = parseICal(
        cal([
          'BEGIN:VTIMEZONE',
          'TZID:Odd',
          'BEGIN:STANDARD',
          'DTSTART:19701025T030000',
          'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU',
          'TZOFFSETFROM:+0617',
          'TZOFFSETTO:+0517',
          'END:STANDARD',
          'BEGIN:DAYLIGHT',
          'DTSTART:19700329T020000',
          'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU',
          'TZOFFSETFROM:+0517',
          'TZOFFSETTO:+0617',
          'END:DAYLIGHT',
          'END:VTIMEZONE',
          'BEGIN:VEVENT',
          'UID:a',
          'DTSTART;TZID=Odd:20260115T090000',
          'END:VEVENT',
          'BEGIN:VEVENT',
          'UID:b',
          'DTSTART;TZID=Odd:20260701T090000',
          'END:VEVENT',
          // 29 March 2026, 02:30 does not exist: read with the offset before the change, as Temporal's 'compatible' would (03:30).
          'BEGIN:VEVENT',
          'UID:c',
          'DTSTART;TZID=Odd:20260329T023000',
          'END:VEVENT',
          // 25 October 2026, 02:30 happens twice: the first pass.
          'BEGIN:VEVENT',
          'UID:d',
          'DTSTART;TZID=Odd:20261025T023000',
          'END:VEVENT',
        ]),
      );
      expect(codes(r), ['zone-fixed-offset']);
      expect(
        [for (final e in r.events) e.start],
        [
          '2026-01-15T09:00:00+05:17[+05:17]',
          '2026-07-01T09:00:00+06:17[+06:17]',
          '2026-03-29T02:30:00+05:17[+05:17]',
          '2026-10-25T02:30:00+06:17[+06:17]',
        ],
      );
    });

    test('old events under older rules do not spoil the match: the latest year decides (US 2005 vs 2007+)', () {
      final r = parseICal(
        cal([
          'BEGIN:VTIMEZONE',
          'TZID:(GMT-05:00) Eastern Time (US & Canada)',
          'BEGIN:STANDARD',
          'DTSTART:16011104T020000',
          'RRULE:FREQ=YEARLY;BYDAY=1SU;BYMONTH=11',
          'TZOFFSETFROM:-0400',
          'TZOFFSETTO:-0500',
          'END:STANDARD',
          'BEGIN:DAYLIGHT',
          'DTSTART:16010311T020000',
          'RRULE:FREQ=YEARLY;BYDAY=2SU;BYMONTH=3',
          'TZOFFSETFROM:-0500',
          'TZOFFSETTO:-0400',
          'END:DAYLIGHT',
          'END:VTIMEZONE',
          'BEGIN:VEVENT',
          'UID:old',
          'DTSTART;TZID="(GMT-05:00) Eastern Time (US & Canada)":20050701T090000',
          'END:VEVENT',
          'BEGIN:VEVENT',
          'UID:new',
          'DTSTART;TZID="(GMT-05:00) Eastern Time (US & Canada)":20260701T090000',
          'END:VEVENT',
        ]),
      );
      expect(codes(r), ['zone-guessed']);
      expect(r.problems[0].detail, '(GMT-05:00) Eastern Time (US & Canada) → America/New_York');
      expect(
        [for (final e in r.events) e.start],
        ['2005-07-01T09:00:00[America/New_York]', '2026-07-01T09:00:00[America/New_York]'],
      );
    });

    test('an unknown TZID without VTIMEZONE is floating, with a warning', () {
      final r = parseICal(cal(['BEGIN:VEVENT', 'UID:u', 'DTSTART;TZID=Nowhere:20261021T090000', 'END:VEVENT']));
      expect(codes(r), ['unknown-zone']);
      expect(r.events[0].start, '2026-10-21T09:00:00');
    });

    test('text is unescaped; categories split on unescaped commas only', () {
      final e = parseICal(fixture('14-escaped-text')).events[0];
      expect(e.title, 'Budget, Q4; final');
      expect(e.extendedProps, {
        'location': 'Salle 2, bâtiment B',
        'categories': ['Work', 'Finance, Q4'],
      });
      expect(parseICal(fixture('13-folded-unicode')).events[0].title, contains('qui doivent être repliés'));
    });

    test('EXDATE and RDATE: several lines, comma lists, each in its zone', () {
      final e = parseICal(fixture('25-rdate-multi')).events[0];
      expect(e.exdate, ['2026-10-12T09:00:00[Europe/Paris]', '2026-10-19T09:00:00[Europe/Paris]']);
      expect(e.rdate, [
        '2026-10-08T09:00:00[Europe/Paris]',
        '2026-10-09T09:00:00[Europe/Paris]',
        '2026-10-30T09:00:00[Europe/Paris]',
      ]);
    });

    test('status, transparency, URL', () {
      final [a, b, ...] = parseICal(fixture('27-status-cancelled-tentative')).events;
      matches(a, {'status': 'cancelled'});
      matches(b, {'status': 'tentative', 'url': 'https://example.com/maybe'});
    });

    test('VTODO and VJOURNAL are skipped with one warning per kind; VALARM is ignored', () {
      final r = parseICal(fixture('29-valarm-and-todo'));
      expect([for (final e in r.events) e.title], ['With alarm']);
      expect(codes(r), ['ical-unsupported']);
    });

    test('EXRULE and RDATE periods are read as far as they go, and said', () {
      final r = parseICal(
        cal([
          'BEGIN:VEVENT',
          'UID:x',
          'DTSTART:20261005T090000Z',
          'RRULE:FREQ=DAILY;COUNT=3',
          'EXRULE:FREQ=WEEKLY',
          'RDATE;VALUE=PERIOD:20261020T090000Z/PT1H',
          'END:VEVENT',
        ]),
      );
      expect(codes(r), ['ical-unsupported', 'ical-unsupported']);
      expect(r.events[0].rdate, ['2026-10-20T09:00:00[UTC]']);
    });

    test('bad lines and bad dates are problems, never exceptions; an event without a start is left out', () {
      final r = parseICal(
        cal([
          'BEGIN:VEVENT',
          'UID:a',
          'this line has no colon',
          'DTSTART:20261321T090000Z',
          'END:VEVENT',
          'BEGIN:VEVENT',
          'UID:b',
          'DTSTART;VALUE=DATE:20261021',
          'END:VTODO',
          'END:VEVENT',
          'BEGIN:VEVENT',
          'UID:c',
        ]),
      );
      // No colon; month 13; END:VTODO never begun; END:VCALENDAR while c is open; c has no DTSTART.
      expect(
        [for (final p in r.problems) '${p.code.code} ${p.path}'],
        [
          'ical-syntax line 5',
          'ical-syntax line 11',
          'ical-syntax line 15',
          'ical-syntax VEVENT[0].DTSTART',
          'ical-syntax VEVENT[2].DTSTART',
        ],
      );
      expect([for (final e in r.events) e.id], ['b']);
      expect(() => parseICal('garbage'), returnsNormally);
      expect(parseICal('').events, isEmpty);
    });

    test('reads the calendar’s name and zone', () {
      final c = parseICal(fixture('04-google-paris-weekly')).calendar;
      expect([c.name, c.zone, c.prodId], ['Équipe', 'Europe/Paris', '-//Test//Fixture//EN']);
    });
  });

  group('into the store', () {
    NormalizeContext ctx() => NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('t'));

    test('an override joins its series under the series’ key; the occurrence it replaces is not drawn twice', () {
      final r = normalizeMany(parseICal(fixture('05-series-override-7456')).events, ctx(), sourceId: 'ics');
      expect(r.report.problems, isEmpty);
      final series = r.items.whereType<NormalizedSeries>().first.series;
      expect(
        [for (final e in series.overrides.entries) (e.key, e.value)],
        [('2026-10-22T09:00:00-05:00[America/Chicago]', 'review@example.com@20261022T090000')],
      );
      final store = EventStore()..replaceSourceChunk('ics', '*', r.items);
      final shown = [
        for (final i in store.snapshot.queryInstances(
          viewWindow(PlainDate.parse('2026-10-19'), PlainDate.parse('2026-10-26'), 'America/Chicago'),
        ))
          '${startText(i.event).substring(0, 16)} ${i.event.title}',
      ];
      expect(shown, [
        '2026-10-20T09:00 Review',
        '2026-10-21T09:00 Review',
        '2026-10-22T14:00 Review (moved)',
        '2026-10-23T09:00 Review',
        '2026-10-24T09:00 Review',
      ]);
    });

    test('EXDATE removes the Monday of 12 October; all-day overrides work the same', () {
      final store = storeOf(parseICal(fixture('04-google-paris-weekly')).events, ctx());
      final days = [
        for (final i in store.snapshot.queryInstances(
          viewWindow(PlainDate.parse('2026-10-05'), PlainDate.parse('2026-10-19'), 'Europe/Paris'),
        ))
          startText(i.event).substring(0, 10),
      ];
      expect(days, ['2026-10-05', '2026-10-07', '2026-10-14']);

      final weekly = storeOf(parseICal(fixture('30-allday-override')).events, ctx());
      expect(
        [
          for (final i in weekly.snapshot.queryInstances(
            viewWindow(PlainDate.parse('2026-10-01'), PlainDate.parse('2026-11-01'), 'Europe/Paris'),
          ))
            startText(i.event),
        ],
        ['2026-10-05', '2026-10-13', '2026-10-19', '2026-10-26'],
      );
    });

    test('Apia 2011: the daily series has no 30 December (that day never happened there)', () {
      final store = storeOf(parseICal(fixture('08-apia-2011')).events, ctx());
      final starts = [
        for (final i in store.snapshot.queryInstances(
          viewWindow(PlainDate.parse('2011-12-28'), PlainDate.parse('2012-01-03'), 'Pacific/Apia'),
        ))
          startText(i.event),
      ];
      // Read in its zone: Thursday 29 at −10:00, then Saturday 31 at +14:00 — nothing on the 30th.
      expect(starts.take(2), ['2011-12-29T10:00:00-10:00[Pacific/Apia]', '2011-12-31T10:00:00+14:00[Pacific/Apia]']);
      expect(starts.any((s) => s.startsWith('2011-12-30')), isFalse);
    });

    test('São Paulo 2018: midnight of 4 November did not exist; the event starts at 01:00 and it is said', () {
      final r = normalizeMany(parseICal(fixture('09-sao-paulo-2018')).events, ctx(), sourceId: 'ics');
      expect([for (final p in r.report.problems) p.code.code], contains('wall-time-skipped'));
      final first = r.items.first;
      expect(first is NormalizedEvent ? startText(first.event) : null, '2018-11-04T01:00:00-02:00[America/Sao_Paulo]');
    });

    test('an override whose series is not in the file stays an event, with a warning', () {
      final r = parseICal(fixture('05-series-override-7456'));
      final n = normalizeMany([r.events[1]], ctx(), sourceId: 'ics');
      expect([for (final p in n.report.problems) p.code.code], contains('orphan-override'));
      final first = n.items.first;
      expect(first, isA<NormalizedEvent>());
      expect((first as NormalizedEvent).event.ref, isNull);
    });
  });

  group('serializeICal', () {
    final stamp = Instant.parse('2026-10-17T00:00:00Z');
    List<String> unfolded(String text) => [for (final l in unfold(text)) l.text];

    test('writes CRLF lines, a VTIMEZONE from Paris’ real changes, TZID times and dates', () {
      final text = serializeICal(
        [
          EventInput(
            id: 'a',
            title: 'Réunion, budget',
            start: '2026-10-21T09:00:00[Europe/Paris]',
            end: '2026-10-21T10:00:00[Europe/Paris]',
          ),
          EventInput(id: 'b', title: 'Off', start: '2026-10-23', end: '2026-10-24', allDay: true),
        ],
        stamp: stamp,
        name: 'Équipe',
      );
      expect(text.endsWith('END:VCALENDAR\r\n'), isTrue);
      expect(text.split('\r\n').every((l) => !l.contains('\n')), isTrue);
      final lines = unfolded(text);
      expect(lines, contains('X-WR-CALNAME:Équipe'));
      expect(lines, contains('DTSTART;TZID=Europe/Paris:20261021T090000'));
      expect(lines, contains(r'SUMMARY:Réunion\, budget'));
      expect(lines, contains('DTSTART;VALUE=DATE:20261023'));
      expect(lines, contains('DTSTAMP:20261017T000000Z'));
      // 2026: summer time from 29 March 02:00 (+01:00 → +02:00) to 25 October 03:00 (+02:00 → +01:00).
      final vtz = lines.sublist(lines.indexOf('TZID:Europe/Paris'), lines.indexOf('END:VTIMEZONE')).join('|');
      expect(vtz, contains('BEGIN:DAYLIGHT|DTSTART:20260329T020000|TZOFFSETFROM:+0100|TZOFFSETTO:+0200'));
      expect(vtz, contains('BEGIN:STANDARD|DTSTART:20261025T030000|TZOFFSETFROM:+0200|TZOFFSETTO:+0100'));
    });

    test('a VTIMEZONE for Lord Howe’s half hour and Kolkata’s fixed +05:30', () {
      final all = unfolded(
        serializeICal([
          EventInput(id: 'l', start: '2026-10-04T09:00:00[Australia/Lord_Howe]'),
          EventInput(id: 'k', start: '2026-10-21T09:00:00[Asia/Kolkata]'),
        ], stamp: stamp),
      ).join('|');
      // Lord Howe: +10:30 → +11:00 at 02:00 on the first Sunday of October (4 October 2026).
      expect(all, contains('DTSTART:20261004T020000|TZOFFSETFROM:+1030|TZOFFSETTO:+1100'));
      expect(
        all,
        contains(
          'TZID:Asia/Kolkata|BEGIN:STANDARD|DTSTART:20250101T000000|TZOFFSETFROM:+0530|TZOFFSETTO:+0530|END:STANDARD|END:VTIMEZONE',
        ),
      );
    });

    test('writes a background as transparent (owner, 2026-11-05) unless said busy; an ordinary event stays opaque', () {
      EventInput at(String id, {EventDisplay? display, bool? busy}) =>
          EventInput(id: id, start: '2026-10-21T09:00:00Z', end: '2026-10-21T10:00:00Z', display: display, busy: busy);
      final blocks = unfolded(
        serializeICal(
          [
            at('bg', display: EventDisplay.background),
            at('busy-bg', display: EventDisplay.background, busy: true),
            at('plain'),
          ],
          stamp: stamp,
          vtimezone: false,
        ),
      ).join('\n').split('BEGIN:VEVENT').sublist(1);
      expect([for (final b in blocks) b.contains('TRANSP:TRANSPARENT')], [true, false, false]);
    });

    test('writes an override under its series’ UID, store objects as well as strings', () {
      final items = normalizeMany(
        parseICal(fixture('05-series-override-7456')).events,
        NormalizeContext(displayZone: 'UTC', newId: createIdGenerator('t')),
        sourceId: 'ics',
      ).items;
      final e = items.whereType<NormalizedEvent>().first.event as TimedEvent;
      final input = EventInput(
        id: e.id,
        start: e.start,
        end: e.end,
        seriesId: e.ref!.seriesId,
        recurrenceId: e.ref!.key,
        title: e.title,
      );
      final lines = unfolded(serializeICal([input], stamp: stamp, vtimezone: false));
      expect(lines, contains('UID:review@example.com'));
      expect(lines, contains('RECURRENCE-ID;TZID=America/Chicago:20261022T090000'));
      expect(lines, contains('DTSTART;TZID=America/Chicago:20261022T140000'));
      expect(lines.any((l) => l.startsWith('BEGIN:VTIMEZONE')), isFalse);
    });
  });

  group('review fixes (Phase 9)', () {
    test('a VEVENT left open is closed by the next one: no later event is lost', () {
      final r = parseICal(
        cal([
          'BEGIN:VEVENT',
          'UID:one',
          'DTSTART:20261021T090000Z',
          'BEGIN:VEVENT',
          'UID:two',
          'DTSTART:20261022T090000Z',
          'END:VEVENT',
          'BEGIN:VEVENT',
          'UID:three',
          'DTSTART:20261023T090000Z',
          'END:VEVENT',
        ]),
      );
      expect([for (final e in r.events) e.id], ['one', 'two', 'three']);
      expect(codes(r), ['ical-syntax']);
      // A VALARM inside an event is not closed by anything: it belongs there.
      final alarm = parseICal(
        cal([
          'BEGIN:VEVENT',
          'UID:a',
          'DTSTART:20261021T090000Z',
          'BEGIN:VALARM',
          'TRIGGER:-PT5M',
          'END:VALARM',
          'END:VEVENT',
        ]),
      );
      expect(codes(alarm), isEmpty);
    });

    test('a UTC start that repeats stays UTC even when the calendar names a zone; a single one moves there', () {
      final r = parseICal(
        cal([
          'X-WR-TIMEZONE:Europe/Paris',
          'BEGIN:VEVENT',
          'UID:s',
          'DTSTART:20261021T080000Z',
          'RRULE:FREQ=DAILY;COUNT=3',
          'EXDATE:20261022T080000Z',
          'END:VEVENT',
          'BEGIN:VEVENT',
          'UID:one',
          'DTSTART:20261021T080000Z',
          'END:VEVENT',
        ]),
      );
      expect(r.events[0].start, '2026-10-21T08:00:00[UTC]');
      expect(r.events[0].exdate, ['2026-10-22T08:00:00[UTC]']);
      expect(r.events[1].start, '2026-10-21T10:00:00+02:00[Europe/Paris]');
    });

    test('RANGE=THISANDFUTURE is read as one override, with a warning; a second VCALENDAR is read too', () {
      final text = [
        cal([
          'BEGIN:VEVENT',
          'UID:s',
          'DTSTART:20261021T080000Z',
          'RRULE:FREQ=DAILY;COUNT=3',
          'END:VEVENT',
          'BEGIN:VEVENT',
          'UID:s',
          'RECURRENCE-ID;RANGE=THISANDFUTURE:20261022T080000Z',
          'DTSTART:20261022T090000Z',
          'END:VEVENT',
        ]),
        cal(['BEGIN:VEVENT', 'UID:other', 'DTSTART:20261025T080000Z', 'END:VEVENT']),
      ].join('\r\n');
      final r = parseICal(text);
      expect(codes(r), contains('ical-unsupported'));
      expect([for (final e in r.events) e.id], ['s', 's@20261022T080000Z', 'other']);
    });

    test('a long series keeps its zone past the years written: the VTIMEZONE ends with rules', () {
      final text = serializeICal([
        EventInput(
          id: 'y',
          start: '2026-07-01T09:00[America/New_York]',
          duration: 'PT1H',
          rrule: 'FREQ=YEARLY;COUNT=10',
        ),
      ], stamp: Instant.parse('2026-10-17T00:00:00Z'));
      expect(text, contains('RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU'));
      expect(text, contains('RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU'));
      // A reader with nothing but this VTIMEZONE: summer 2034 is still −04:00, winter −05:00.
      final lines = [for (final l in unfold(text)) l.text];
      final vtz = lines.sublist(lines.indexOf('BEGIN:VTIMEZONE'), lines.indexOf('END:VTIMEZONE') + 1);
      final own = [for (final l in vtz) l == 'TZID:America/New_York' ? 'TZID:Written NY' : l];
      final r = parseICal(
        cal([
          ...own,
          'BEGIN:VEVENT',
          'UID:summer',
          'DTSTART;TZID=Written NY:20340701T090000',
          'END:VEVENT',
          'BEGIN:VEVENT',
          'UID:winter',
          'DTSTART;TZID=Written NY:20340115T090000',
          'END:VEVENT',
        ]),
      );
      final offsets = [
        for (final e in r.events) RegExp(r'([+-]\d\d:\d\d)\[').firstMatch(_zonedText(e.start! as String))?[1],
      ];
      expect(offsets, ['-04:00', '-05:00']);
      // A zone whose rules changed in between (none after 2016 in Istanbul) writes no rule.
      expect(
        serializeICal([
          EventInput(id: 'i', start: '2026-07-01T09:00[Europe/Istanbul]'),
        ], stamp: Instant.parse('2026-10-17T00:00:00Z')),
        isNot(contains('RRULE')),
      );
    });
  });

  group('store → iCal → store', () {
    NormalizeContext ctx() => NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('r'));
    for (final (name, from, to) in const [
      ('05-series-override-7456', '2026-10-19', '2026-10-26'),
      ('26-allday-series-exdate', '2026-01-01', '2027-01-01'),
      ('31-paris-fall-back-series', '2026-10-01', '2026-11-30'),
      ('16-outlook-windows', '2026-01-01', '2027-01-01'),
    ]) {
      test('$name: the same instances after export and import', () {
        final first = storeOf(parseICal(fixture(name)).events, ctx());
        final text = serializeICal(exportInputs(first.snapshot), stamp: Instant.parse('2026-10-17T00:00:00Z'));
        final again = storeOf(parseICal(text).events, ctx());
        final w = viewWindow(PlainDate.parse(from), PlainDate.parse(to), 'Europe/Paris');
        List<String> list(EventStore s) => [
          for (final i in s.snapshot.queryInstances(w))
            '${i.key} ${startText(i.event)} ${endText(i.event)} ${i.event.title}',
        ];
        expect(list(first), isNotEmpty);
        expect(list(again), list(first));
      });
    }
  });

  group('parse → serialize → parse', () {
    final fixtures = [
      for (final f in Directory('test/fixtures/ical').listSync().whereType<File>())
        if (f.path.endsWith('.ics')) f.uri.pathSegments.last,
    ]..sort();

    test('has at least thirty fixtures', () {
      expect(fixtures.length, greaterThanOrEqualTo(30));
    });

    for (final f in fixtures) {
      test('$f: the same events come back', () {
        final first = parseICal(fixture(f.substring(0, f.length - 4)));
        final text = serializeICal(first.events, stamp: Instant.parse('2026-10-17T00:00:00Z'));
        final again = parseICal(text);
        // What the store would hold is identical…
        expect(_held(again.events), _held(first.events));
        // …and so are the inputs, offsets included — but an offset the wall time
        // implies (no repeated hour there) may come back unwritten: a UTC time
        // read in the calendar's zone returns as that zone's wall time.
        expect(_implied(again.events), _implied(first.events));
        // A file we wrote reads without a single problem.
        expect(again.problems, isEmpty);
      });
    }
  });
}

/// A zoned text with its offset written, as the store would read it.
String _zonedText(String s) => '${ZonedDateTime.tryParse(s)}';

/// What the store would hold, as plain strings.
Map<String, Object?> _held(List<EventInput> events) {
  final r = normalizeMany(
    events,
    NormalizeContext(displayZone: 'UTC', newId: createIdGenerator('t')),
    sourceId: 'ics',
  );
  Map<String, Object?> plain(Normalized n) {
    final e = switch (n) {
      NormalizedEvent(:final event) => event,
      NormalizedSeries(:final series) => series.base,
    };
    return {
      'kind': n is NormalizedEvent ? 'event' : 'series',
      'id': e.id,
      'title': e.title,
      'allDay': e.allDay,
      'start': startText(e),
      'end': endText(e),
      'status': e.status.name,
      'busy': e.busy,
      'url': e.url,
      'props': jsonEncode(e.props),
      'ref': e.ref == null ? null : '${e.ref!.seriesId} ${e.ref!.key}',
      if (n case NormalizedSeries(:final series)) ...{
        'rules': [for (final x in series.set.rules) serializeRRule(x)],
        'exdates': [for (final x in series.set.exdates) '$x'],
        'rdates': [for (final x in series.set.rdates) '$x'],
        'overrides': [for (final x in series.overrides.entries) '${x.key}=${x.value}'],
      },
    };
  }

  return {
    'items': [for (final n in r.items) plain(n)],
    'codes': [for (final p in r.report.problems) p.code.code],
  };
}

final _withOffset = RegExp(r'(\d{4}-\d{2}-\d{2}T[\d:]+)([+-]\d{2}:\d{2})\[([^\]]+)\]');

/// Drops an offset only where the wall time has exactly that one offset in its zone.
Object? _implied(List<EventInput> es) {
  final text = jsonEncode([for (final e in es) e.toJson()]).replaceAllMapped(_withOffset, (m) {
    final wall = PlainDateTime.tryParse(m[1]!);
    final zone = m[3]!;
    if (wall == null || !isValidZone(zone)) return m[0]!;
    final z = ZonedDateTime.fromWall(wall, zone, how: Disambiguation.reject);
    return z != null && z.offset == m[2] ? '${m[1]}[$zone]' : m[0]!;
  });
  return jsonDecode(text);
}
