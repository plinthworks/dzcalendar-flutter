/// Window maths for virtual scrolling: which rows or columns are on screen.
/// Pure numbers; the widgets measure, this decides.
library;

import 'dart:typed_data';

/// Offsets of items of varying size, updatable in O(log n) (a Fenwick tree).
final class PrefixSums {
  PrefixSums(List<double> sizes) : _sizes = Float64List.fromList(sizes), _tree = Float64List(sizes.length + 1) {
    final n = _sizes.length;
    for (var i = 0; i < n; i++) {
      _tree[i + 1] += _sizes[i];
      final parent = i + 1 + ((i + 1) & -(i + 1));
      if (parent <= n) _tree[parent] += _tree[i + 1];
    }
  }

  final Float64List _sizes;
  final Float64List _tree;

  int get count => _sizes.length;
  double get total => offsetOf(_sizes.length);
  double sizeOf(int i) => _sizes[i];

  void set(int i, double size) {
    final delta = size - _sizes[i];
    _sizes[i] = size;
    for (var j = i + 1; j < _tree.length; j += j & -j) {
      _tree[j] += delta;
    }
  }

  /// Where item [i] starts: the sum of the sizes before it.
  double offsetOf(int i) {
    var sum = 0.0;
    for (var j = i; j > 0; j -= j & -j) {
      sum += _tree[j];
    }
    return sum;
  }

  /// The item covering [offset] (clamped to the first and last). O(log n).
  int indexAt(double offset) {
    final n = _sizes.length;
    if (n == 0) return 0;
    // Descend to the last position whose prefix is ≤ offset: leading items of
    // size zero are passed over, so offset 0 lands on the first real item.
    var pos = 0;
    var rest = offset < 0 ? 0.0 : offset;
    var step = 1;
    while (step * 2 <= n) {
      step *= 2;
    }
    for (; step > 0; step >>= 1) {
      final next = pos + step;
      if (next <= n && _tree[next] <= rest) {
        pos = next;
        rest -= _tree[next];
      }
    }
    return pos < n - 1 ? pos : n - 1;
  }
}

/// Inclusive. Empty when `last < first`.
final class VRange {
  const VRange(this.first, this.last);
  final int first;
  final int last;
  bool get isEmpty => last < first;

  @override
  bool operator ==(Object other) => other is VRange && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);

  @override
  String toString() => '[$first, $last]';
}

/// Item sizes: measured ([VariableSizes]) or all alike ([UniformSizes]).
sealed class Sizes {
  const Sizes();
  int get count;
}

final class VariableSizes extends Sizes {
  const VariableSizes(this.sums);
  final PrefixSums sums;
  @override
  int get count => sums.count;
}

final class UniformSizes extends Sizes {
  /// Throws an [ArgumentError] unless [size] > 0.
  UniformSizes(this.size, this.count) {
    if (!(size > 0)) throw ArgumentError.value(size, 'size', 'must be > 0');
  }
  final double size;
  @override
  final int count;
}

/// The items on screen for a scroll position and a viewport, with
/// [overscan] items more each side.
VRange visibleRange(Sizes sizes, double scroll, double viewport, int overscan) {
  final count = sizes.count;
  if (count == 0) return const VRange(0, -1);
  final int first;
  final int last;
  switch (sizes) {
    case VariableSizes(:final sums):
      first = sums.indexAt(scroll);
      last = sums.indexAt(scroll + viewport - 1e-9 > scroll ? scroll + viewport - 1e-9 : scroll);
    case UniformSizes(:final size):
      // Bounded before `floor`: Flutter's unbounded constraints give an infinite viewport,
      // and a double past 2^63 does not fit an int.
      int index(double x) {
        final q = (x < 0 ? 0 : x) / size;
        return q < count ? q.floor() : count - 1;
      }
      first = index(scroll);
      last = index(scroll + viewport - 1e-9);
  }
  final f = (first < count - 1 ? first : count - 1) - overscan;
  final l = last + overscan;
  return VRange(f < 0 ? 0 : f, l < count - 1 ? l : count - 1);
}

({VRange rows, VRange cols}) visible2D(
  Sizes rows,
  Sizes cols,
  double scrollTop,
  double scrollLeft,
  double width,
  double height,
  int overscan,
) => (rows: visibleRange(rows, scrollTop, height, overscan), cols: visibleRange(cols, scrollLeft, width, overscan));
