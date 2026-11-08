// Ported from the TypeScript core's intervals.test.ts (hand-written
// expectations, copied as values).
//
// Ported: all six tests. `normalizeIntervals` is `normalizeSpans`;
// `spansToIntervals` is `spanInstants` (not exported by the library, imported
// from src).
// Note: the TS random generator multiplies in doubles, which lose precision
// above 2^53; here the same recurrence is exact in 64-bit integers, so the
// random sets differ. The check is against a brute-force oracle either way.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

List<MsSpan> s(List<(int, int)> pairs) => [for (final (a, b) in pairs) MsSpan(a, b)];

void main() {
  group('interval algebra on [start, end)', () {
    test('normalize sorts, drops empty spans, merges overlapping and touching ones', () {
      expect(normalizeSpans(s([(5, 7), (1, 3), (3, 4), (6, 9), (10, 10)])), s([(1, 4), (5, 9)]));
    });

    test('union', () {
      expect(unionSpans(s([(1, 3), (8, 9)]), s([(2, 5), (9, 12)])), s([(1, 5), (8, 12)]));
    });

    test('intersect keeps only shared stretches; touching is not sharing', () {
      expect(intersectSpans(s([(1, 5), (8, 12)]), s([(3, 9), (12, 14)])), s([(3, 5), (8, 9)]));
    });

    test('subtract cuts holes and trims edges', () {
      expect(subtractSpans(s([(0, 10), (20, 30)]), s([(2, 3), (5, 22), (29, 40)])), s([(0, 2), (3, 5), (22, 29)]));
      expect(subtractSpans(s([(0, 10)]), []), s([(0, 10)]));
      expect(subtractSpans(s([(0, 10)]), s([(0, 10)])), isEmpty);
    });

    test('agrees with a brute-force minute-by-minute check on random sets', () {
      var seed = 7;
      int rnd(int n) {
        seed = (seed * 1103515245 + 12345) % (1 << 31);
        return seed % n;
      }

      List<MsSpan> set() => normalizeSpans([
        for (var i = 0; i < 6; i++)
          () {
            final a = rnd(100);
            return MsSpan(a, a + rnd(20));
          }(),
      ]);
      bool has(List<MsSpan> xs, int m) => xs.any((x) => m >= x.s && m < x.e);
      for (var k = 0; k < 200; k++) {
        final a = set();
        final b = set();
        final u = unionSpans(a, b);
        final i = intersectSpans(a, b);
        final d = subtractSpans(a, b);
        for (var m = 0; m < 130; m++) {
          expect(has(u, m), has(a, m) || has(b, m));
          expect(has(i, m), has(a, m) && has(b, m));
          expect(has(d, m), has(a, m) && !has(b, m));
        }
      }
    });

    test('spansToIntervals gives instants', () {
      expect('${spanInstants(s([(0, 60000)])[0]).end}', '1970-01-01T00:01:00Z');
    });
  });
}
