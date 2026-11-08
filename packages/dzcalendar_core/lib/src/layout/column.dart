/// Side-by-side placement of overlapping events in one time column.
///
/// Positions are axis units (minutes on the column's axis), never pixels:
/// the widgets turn fractions into sizes, and this stays testable alone.
library;

final class ColItem {
  const ColItem({required this.key, required this.start, required this.end, required this.order});
  final String key;
  final double start;
  final double end;

  /// Tie-breaker after start and length: the calendar's event order.
  final int order;
}

final class ColPlacement {
  const ColPlacement({
    required this.key,
    required this.lane,
    required this.lanes,
    required this.left,
    required this.width,
    required this.z,
  });

  final String key;
  final int lane;

  /// Lanes in this item's cluster of overlapping events.
  final int lanes;

  /// Fractions of the column width, 0..1.
  final double left;
  final double width;
  final int z;
}

enum ColumnLayoutMode { sideBySide, cascade }

final class _Item {
  _Item(this.key, this.start, this.end, this.order);
  final String key;
  final double start;
  final double end;
  final int order;
  int lane = 0;
}

/// Sweep, then greedy interval colouring: sorted by start, each item takes
/// the first lane whose last item has ended — optimal for intervals. Then
/// each item widens rightwards over lanes free for its whole span.
///
/// [minVisual]: the smallest height an event is drawn at, in axis units. A
/// ten-minute event drawn as thirty is laid out as thirty, or it is drawn on
/// top of its neighbour. [indent]: cascade only, each level's offset.
List<ColPlacement> layoutColumn(
  List<ColItem> items, {
  required double minVisual,
  ColumnLayoutMode mode = ColumnLayoutMode.sideBySide,
  double indent = 0.1,
}) {
  final sorted =
      [for (final x in items) _Item(x.key, x.start, x.end > x.start + minVisual ? x.end : x.start + minVisual, x.order)]
        ..sort((a, b) {
          final byStart = a.start.compareTo(b.start);
          if (byStart != 0) return byStart;
          final byEnd = b.end.compareTo(a.end);
          if (byEnd != 0) return byEnd;
          final byOrder = a.order.compareTo(b.order);
          return byOrder != 0 ? byOrder : a.key.compareTo(b.key);
        });

  final out = <ColPlacement>[];
  var i = 0;
  while (i < sorted.length) {
    // One cluster: items connected by overlap.
    final cluster = <_Item>[];
    var clusterEnd = double.negativeInfinity;
    while (i < sorted.length && (cluster.isEmpty || sorted[i].start < clusterEnd)) {
      final it = sorted[i++];
      cluster.add(it);
      if (it.end > clusterEnd) clusterEnd = it.end;
    }

    final laneEnds = <double>[];
    final byLane = <List<_Item>>[];
    for (final it in cluster) {
      var lane = laneEnds.indexWhere((end) => end <= it.start);
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(it.end);
        byLane.add([]);
      } else {
        laneEnds[lane] = it.end;
      }
      byLane[lane].add(it);
      it.lane = lane;
    }
    final lanes = laneEnds.length;

    if (mode == ColumnLayoutMode.cascade) {
      for (var z = 0; z < cluster.length; z++) {
        final it = cluster[z];
        final at = it.lane * indent;
        final left = at < 1 - indent ? at : 1 - indent;
        out.add(ColPlacement(key: it.key, lane: it.lane, lanes: lanes, left: left, width: 1 - left, z: z));
      }
      continue;
    }

    for (final it in cluster) {
      var span = 1;
      for (var l = it.lane + 1; l < lanes && !_overlapsLane(byLane[l], it.start, it.end); l++) {
        span++;
      }
      out.add(
        ColPlacement(key: it.key, lane: it.lane, lanes: lanes, left: it.lane / lanes, width: span / lanes, z: it.lane),
      );
    }
  }
  return out;
}

/// A lane's items are sorted by start and disjoint: the last one starting
/// before [end] is the only candidate.
bool _overlapsLane(List<_Item> lane, double start, double end) {
  var lo = 0;
  var hi = lane.length - 1;
  var found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lane[mid].start < end) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found >= 0 && lane[found].end > start;
}
