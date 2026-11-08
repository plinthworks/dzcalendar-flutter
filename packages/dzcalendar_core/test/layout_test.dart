// Ported from the TypeScript core's layout.test.ts (hand-written
// expectations, copied as values).
//
// Ported: the four layoutColumn tests.
// Skipped, not in the port yet:
// - 'packs random bars without overlap...' (packLanes, row layout)
// - 'every bar on every day is either drawn or counted in +N...' (packLanes, computeOverflow)
// - 'computeOverflow: maxLanes 1 leaves only "+N"...' (computeOverflow)
// - 'agrees with a naive sum after random updates' (PrefixSums, virtualisation)
// - 'indexAt finds the item under an offset...' (PrefixSums)
// - 'visibleRange with overscan, uniform and variable' (visibleRange, PrefixSums)

import 'dart:math' as math;

import 'package:dzcalendar_core/dzcalendar_core.dart';
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
int maxClique(List<ColItem> xs) {
  final ev = [
    for (final x in xs) ...[(x.start, 1), (x.end, -1)],
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
}
