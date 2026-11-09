// Ported from the TypeScript core's layout.test.ts (hand-written
// expectations, copied as values).
//
// Ported: the four layoutColumn tests; packLanes and computeOverflow (3);
// PrefixSums and visibleRange (3, in 19e-1).
// Skipped: none. Translation notes:
// - computeOverflow with `maxLanes: 1.5`: Dart's `int` cannot hold it; only
//   the 0 case is kept (it throws an ArgumentError, the TS a RangeError).
// - visibleRange's `{ uniform, count }` is `UniformSizes(size, count)`, whose
//   constructor refuses a size of 0 (ArgumentError) — the TS refused it in
//   visibleRange.

import 'dart:math' as math;

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

/// The TypeScript test's generator, bit for bit (a 32-bit linear congruence).
double Function() rng(int seed) {
  var s = seed;
  return () {
    s = (s * 1103515245 + 12345) & 0xFFFFFFFF;
    return s / 4294967296;
  };
}

/// The largest number of intervals sharing one point: the fewest lanes possible.
int maxClique(List<ColItem> xs) => maxCliqueOf([for (final x in xs) (x.start, x.end)]);

int maxCliqueOf(List<(num, num)> xs) {
  final ev = [
    for (final x in xs) ...[(x.$1, 1), (x.$2, -1)],
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  var cur = 0;
  var best = 0;
  for (final (_, d) in ev) {
    cur += d;
    best = math.max(best, cur);
  }
  return best;
}

void main() {
  group('layoutColumn', () {
    test('on 1000 random columns: lanes = largest overlap, no two items in one lane overlap, widening hits nobody', () {
      final r = rng(3);
      for (var k = 0; k < 1000; k++) {
        final n = 1 + (r() * 25).floor();
        final items = <ColItem>[];
        for (var i = 0; i < n; i++) {
          final start = (r() * 1400).floor();
          items.add(
            ColItem(key: 'e$i', start: start.toDouble(), end: (start + 15 + (r() * 180).floor()).toDouble(), order: i),
          );
        }
        final placed = layoutColumn(items, minVisual: 15);
        expect(placed, hasLength(items.length));
        final byKey = {for (final x in items) x.key: x};
        // Each lanes value equals the max overlap of its cluster; overall max equals overall clique.
        expect(placed.map((p) => p.lanes).reduce(math.max), maxClique(items));
        for (final a in placed) {
          expect(a.left + a.width, lessThanOrEqualTo(1 + 1e-9));
          for (final b in placed) {
            if (identical(a, b)) continue;
            final x = byKey[a.key]!;
            final y = byKey[b.key]!;
            final overlap = x.start < y.end && y.start < x.end;
            final horizontally = a.left < b.left + b.width - 1e-9 && b.left < a.left + a.width - 1e-9;
            if (overlap) expect([a.key, b.key, horizontally], [a.key, b.key, false]);
          }
        }
      }
    });

    test('a short event is laid out as tall as it is drawn', () {
      final placed = layoutColumn([
        const ColItem(key: 'a', start: 0, end: 5, order: 0),
        const ColItem(key: 'b', start: 10, end: 60, order: 1),
      ], minVisual: 30);
      expect([for (final p in placed) p.lanes], [2, 2]);
    });

    test('an item widens over lanes that stay free', () {
      final placed = layoutColumn([
        const ColItem(key: 'long', start: 0, end: 120, order: 0),
        const ColItem(key: 'a', start: 0, end: 30, order: 1),
        const ColItem(key: 'b', start: 0, end: 30, order: 2),
        const ColItem(key: 'late', start: 60, end: 90, order: 3),
      ], minVisual: 15);
      final late = placed.firstWhere((p) => p.key == 'late');
      expect([late.lane, late.lanes, late.width], [1, 3, 2 / 3]);
    });

    test('cascade offsets each level and keeps them in order', () {
      final placed = layoutColumn(
        [const ColItem(key: 'a', start: 0, end: 60, order: 0), const ColItem(key: 'b', start: 10, end: 60, order: 1)],
        minVisual: 15,
        mode: ColumnLayoutMode.cascade,
        indent: 0.2,
      );
      expect(
        [
          for (final p in placed) [p.left, p.width, p.z],
        ],
        [
          [0, 1, 0],
          [0.2, 0.8, 1],
        ],
      );
    });
  });

  group('packLanes and computeOverflow', () {
    test('packs random bars without overlap, in as many lanes as the largest overlap', () {
      final r = rng(5);
      for (var k = 0; k < 500; k++) {
        final n = (r() * 30).floor();
        final items = <RowItem>[];
        for (var i = 0; i < n; i++) {
          final start = (r() * 7).floor();
          items.add(RowItem(key: 'b$i', start: start, end: start + 1 + (r() * 3).floor(), rank: [i]));
        }
        final packed = packLanes(items);
        expect(packed.laneCount, maxCliqueOf([for (final x in items) (x.start, x.end)]));
        for (final a in items) {
          for (final b in items) {
            if (!identical(a, b) && packed.lanes[a.key] == packed.lanes[b.key]) {
              expect(a.start < b.end && b.start < a.end, isFalse);
            }
          }
        }
      }
    });

    test('every bar on every day is either drawn or counted in +N, never both', () {
      final r = rng(8);
      for (var k = 0; k < 500; k++) {
        final n = (r() * 25).floor();
        final items = <RowItem>[];
        for (var i = 0; i < n; i++) {
          final start = (r() * 7).floor();
          items.add(RowItem(key: 'b$i', start: start, end: math.min(7, start + 1 + (r() * 4).floor()), rank: [i]));
        }
        final packed = packLanes(items);
        final max = 1 + (r() * 4).floor();
        final over = computeOverflow(packed.lanes, items, 7, max);
        for (var d = 0; d < 7; d++) {
          final covering = [
            for (final it in items)
              if (it.start <= d && d < it.end) it.key,
          ]..sort();
          final drawn = [
            for (final p in over.pieces)
              if (p.from <= d && d < p.to) p.key,
          ];
          final hidden = over.hiddenKeysPerDay[d];
          expect([...drawn, ...hidden]..sort(), covering);
          expect(over.hiddenPerDay[d], hidden.length);
          // Drawn bars never reach past the lanes left once "+N" takes one.
          final limit = hidden.isNotEmpty ? max - 1 : max;
          for (final p in over.pieces.where((p) => p.from <= d && d < p.to)) {
            expect(p.lane, lessThan(limit));
          }
        }
      }
    });

    test('computeOverflow: maxLanes 1 leaves only "+N" on a crowded day; 0 is refused', () {
      const items = [
        RowItem(key: 'a', start: 0, end: 1, rank: [0]),
        RowItem(key: 'b', start: 0, end: 1, rank: [1]),
      ];
      final packed = packLanes(items);
      final over = computeOverflow(packed.lanes, items, 1, 1);
      expect(over.pieces, isEmpty);
      expect(over.hiddenPerDay, [2]);
      expect(() => computeOverflow(packed.lanes, items, 1, 0), throwsArgumentError);
    });
  });

  group('PrefixSums and visibleRange', () {
    test('agrees with a naive sum after random updates', () {
      final r = rng(11);
      final sizes = [for (var i = 0; i < 200; i++) (r() * 50).floor().toDouble()];
      final ps = PrefixSums(sizes);
      for (var k = 0; k < 300; k++) {
        final i = (r() * 200).floor();
        sizes[i] = (r() * 50).floor().toDouble();
        ps.set(i, sizes[i]);
        final j = (r() * 201).floor();
        expect(ps.offsetOf(j), sizes.sublist(0, j).fold<double>(0, (a, b) => a + b));
      }
      expect(ps.total, sizes.fold<double>(0, (a, b) => a + b));
    });

    test('indexAt finds the item under an offset, skipping zero-size items', () {
      final ps = PrefixSums([10, 0, 10, 30]);
      expect(
        [
          for (final o in [0, 9, 10, 19, 20, 49, 999]) ps.indexAt(o.toDouble()),
        ],
        [0, 0, 2, 2, 3, 3, 3],
      );
      final zero = PrefixSums([0, 2, 3]);
      expect(
        [
          for (final o in [0, 1, 2, -5]) zero.indexAt(o.toDouble()),
        ],
        [1, 1, 2, 1],
      );
    });

    test('visibleRange with overscan, uniform and variable', () {
      expect(visibleRange(UniformSizes(20, 100), 200, 100, 2), const VRange(8, 16));
      expect(visibleRange(VariableSizes(PrefixSums([50, 50, 50, 50])), 60, 50, 0), const VRange(1, 2));
      expect(visibleRange(UniformSizes(20, 0), 0, 100, 2), const VRange(0, -1));
      expect(() => UniformSizes(0, 10), throwsArgumentError);
    });
  });
}
