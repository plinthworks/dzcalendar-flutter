/// Stacking bars into rows (lanes) — the month grid and the timeline.
/// Positions are column indexes (days) or any unit; `end` is exclusive.
library;

final class RowItem {
  const RowItem({required this.key, required this.start, required this.end, this.rank = const []});
  final String key;
  final int start;
  final int end;

  /// Compared element by element after start and length: all-day first,
  /// then the event order.
  final List<int> rank;
}

final class Packed {
  const Packed(this.lanes, this.laneCount);
  final Map<String, int> lanes;
  final int laneCount;
}

final class _MinHeap<T> {
  _MinHeap(this.less);
  final bool Function(T a, T b) less;
  final _xs = <T>[];

  int get size => _xs.length;
  T get peek => _xs.first;

  void push(T x) {
    _xs.add(x);
    var i = _xs.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (!less(_xs[i], _xs[p])) break;
      final t = _xs[i];
      _xs[i] = _xs[p];
      _xs[p] = t;
      i = p;
    }
  }

  T pop() {
    final top = _xs.first;
    final last = _xs.removeLast();
    if (_xs.isNotEmpty) {
      _xs[0] = last;
      var i = 0;
      for (;;) {
        final l = 2 * i + 1;
        final r = l + 1;
        var m = i;
        if (l < _xs.length && less(_xs[l], _xs[m])) m = l;
        if (r < _xs.length && less(_xs[r], _xs[m])) m = r;
        if (m == i) break;
        final t = _xs[i];
        _xs[i] = _xs[m];
        _xs[m] = t;
        i = m;
      }
    }
    return top;
  }
}

int _compareRank(List<int> a, List<int> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

/// Each bar takes the lowest free lane. Sorted by start, longer first, then
/// rank, then key; a heap of occupied lanes by end frees them as bars
/// finish, a heap of free lanes hands out the lowest. O(n log n).
Packed packLanes(List<RowItem> items) {
  final sorted = [...items]
    ..sort((a, b) {
      var c = a.start - b.start;
      if (c != 0) return c;
      c = (b.end - b.start) - (a.end - a.start);
      if (c != 0) return c;
      c = _compareRank(a.rank, b.rank);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  final busy = _MinHeap<({int end, int lane})>((a, b) => a.end < b.end || (a.end == b.end && a.lane < b.lane));
  final free = _MinHeap<int>((a, b) => a < b);
  final lanes = <String, int>{};
  var laneCount = 0;
  for (final it in sorted) {
    while (busy.size > 0 && busy.peek.end <= it.start) {
      free.push(busy.pop().lane);
    }
    final lane = free.size > 0 ? free.pop() : laneCount++;
    lanes[it.key] = lane;
    busy.push((end: it.end > it.start + 1 ? it.end : it.start + 1, lane: lane));
  }
  return Packed(Map.unmodifiable(lanes), laneCount);
}

/// The stretch of a bar that stays visible: day indexes, [to] exclusive.
final class OverflowPiece {
  const OverflowPiece({required this.key, required this.lane, required this.from, required this.to});
  final String key;
  final int lane;
  final int from;
  final int to;

  @override
  bool operator ==(Object other) =>
      other is OverflowPiece && other.key == key && other.lane == lane && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(key, lane, from, to);

  @override
  String toString() => '$key@$lane[$from,$to)';
}

final class OverflowResult {
  const OverflowResult(this.pieces, this.hiddenKeysPerDay);
  final List<OverflowPiece> pieces;

  /// For each day, the keys its "+N" stands for.
  final List<List<String>> hiddenKeysPerDay;
  List<int> get hiddenPerDay => [for (final k in hiddenKeysPerDay) k.length];
}

/// What fits in [maxLanes] rows, day by day. On a day where anything spills
/// over, the last visible lane gives way to the "+N" link, so its bar is
/// hidden there too and counted in N. A bar that is hidden on some days is
/// cut into the visible stretches either side. O(items × days). Throws an
/// [ArgumentError] when [maxLanes] is under 1 (configuration).
OverflowResult computeOverflow(Map<String, int> lanes, List<RowItem> items, int dayCount, int maxLanes) {
  // With 1, a day that overflows shows only its "+N" link: the one lane gives way.
  if (maxLanes < 1) throw ArgumentError.value(maxLanes, 'maxLanes', 'an integer ≥ 1');
  final spills = List.filled(dayCount, false);
  for (final it in items) {
    if ((lanes[it.key] ?? 0) < maxLanes) continue;
    for (var d = it.start < 0 ? 0 : it.start; d < (dayCount < it.end ? dayCount : it.end); d++) {
      spills[d] = true;
    }
  }
  int limit(int d) => spills[d] ? maxLanes - 1 : maxLanes;
  final hidden = [for (var i = 0; i < dayCount; i++) <String>[]];
  final pieces = <OverflowPiece>[];
  for (final it in items) {
    final lane = lanes[it.key] ?? 0;
    var runStart = -1;
    final from = it.start < 0 ? 0 : it.start;
    final end = it.end > it.start + 1 ? it.end : it.start + 1;
    final to = dayCount < end ? dayCount : end;
    for (var d = from; d <= to; d++) {
      final visible = d < to && lane < limit(d);
      if (d < to && !visible) hidden[d].add(it.key);
      if (visible && runStart == -1) runStart = d;
      if (!visible && runStart != -1) {
        pieces.add(OverflowPiece(key: it.key, lane: lane, from: runStart, to: d));
        runStart = -1;
      }
    }
  }
  return OverflowResult(pieces, hidden);
}
