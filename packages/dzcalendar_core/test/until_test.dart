// ZonedDateTime.untilInDays against Temporal's until({ largestUnit: 'days' }),
// each expectation read from the Temporal polyfill (temporal-polyfill 1.0.x).

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

ZonedDateTime z(String text) =>
    (normalizeEvent(
              EventInput(start: text),
              NormalizeContext(displayZone: 'UTC', newId: createIdGenerator('z')),
            ).value!.event
            as TimedEvent)
        .start;

void main() {
  test('days on the clock face, then the exact rest, as Temporal counts them', () {
    for (final (a, b, want) in [
      ('2026-03-28T09:00:00+01:00[Europe/Paris]', '2026-03-29T09:00:00+02:00[Europe/Paris]', 'P1D'),
      ('2026-03-28T09:00:00+01:00[Europe/Paris]', '2026-03-29T08:30:00+02:00[Europe/Paris]', 'PT22H30M'),
      ('2026-10-24T23:30:00+02:00[Europe/Paris]', '2026-10-25T02:30:00+01:00[Europe/Paris]', 'PT4H'),
      ('2026-10-25T02:30:00+02:00[Europe/Paris]', '2026-10-25T02:30:00+01:00[Europe/Paris]', 'PT1H'),
      ('2026-06-01T10:00:00+02:00[Europe/Paris]', '2026-06-01T22:00:00+02:00[Europe/Paris]', 'PT12H'),
      ('2026-06-05T10:00:00+02:00[Europe/Paris]', '2026-06-01T09:00:00+02:00[Europe/Paris]', '-P4DT1H'),
      ('2011-12-29T12:00:00-10:00[Pacific/Apia]', '2011-12-31T12:00:00+14:00[Pacific/Apia]', 'P2D'),
      ('2026-03-29T03:30:00+02:00[Europe/Paris]', '2026-04-01T02:30:00+02:00[Europe/Paris]', 'P2DT23H'),
      // The same date, the end in the second pass of the repeated hour (code review, 19c).
      ('2026-10-25T02:30:00+02:00[Europe/Paris]', '2026-10-25T02:15:00+01:00[Europe/Paris]', 'PT45M'),
    ]) {
      expect('${z(a).untilInDays(z(b))}', want, reason: '$a → $b');
    }
  });

  test('a sub-daily rule keeps DTSTART\'s milliseconds, as Temporal\'s with() (code review, 19c)', () {
    final s = Instant.parse('2026-03-01T09:00:00.250Z').inZone('UTC');
    final r = expandZoned(s, RRuleSet([parseRRule('FREQ=HOURLY;COUNT=3').rule!]), s.instant, s.instant.addMs(86400000));
    expect(
      [for (final z in r.starts) '${z.instant}'],
      ['2026-03-01T09:00:00.25Z', '2026-03-01T10:00:00.25Z', '2026-03-01T11:00:00.25Z'],
    );
  });
}
