import 'time/instant.dart';

/// Half-open spans `[s, e)` of epoch milliseconds and the set algebra over
/// them: business hours, constraints and free slots all reduce to "these
/// stretches of time, minus those".
///
/// Every function taking a list expects it sorted and disjoint (what
/// [normalizeSpans] makes), and gives the same. Empty spans are dropped.
final class MsSpan {
  const MsSpan(this.s, this.e);
  final int s;
  final int e;

  @override
  bool operator ==(Object other) => other is MsSpan && other.s == s && other.e == e;
  @override
  int get hashCode => Object.hash(s, e);
  @override
  String toString() => '[$s, $e)';
}

/// Sorts, drops empty spans, merges those that overlap or touch. O(n log n).
List<MsSpan> normalizeSpans(List<MsSpan> xs) {
  final sorted = xs.where((x) => x.e > x.s).toList()
    ..sort((a, b) {
      final c = a.s.compareTo(b.s);
      return c != 0 ? c : a.e.compareTo(b.e);
    });
  final out = <MsSpan>[];
  for (final x in sorted) {
    if (out.isNotEmpty && x.s <= out.last.e) {
      if (x.e > out.last.e) out.last = MsSpan(out.last.s, x.e);
    } else {
      out.add(x);
    }
  }
  return out;
}

/// O(a + b).
List<MsSpan> unionSpans(List<MsSpan> a, List<MsSpan> b) {
  final merged = <MsSpan>[];
  var i = 0;
  var j = 0;
  while (i < a.length || j < b.length) {
    final x = j >= b.length || (i < a.length && a[i].s <= b[j].s) ? a[i++] : b[j++];
    if (merged.isNotEmpty && x.s <= merged.last.e) {
      if (x.e > merged.last.e) merged.last = MsSpan(merged.last.s, x.e);
    } else {
      merged.add(x);
    }
  }
  return merged;
}

/// O(a + b).
List<MsSpan> intersectSpans(List<MsSpan> a, List<MsSpan> b) {
  final out = <MsSpan>[];
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    final x = a[i];
    final y = b[j];
    final s = x.s > y.s ? x.s : y.s;
    final e = x.e < y.e ? x.e : y.e;
    if (e > s) out.add(MsSpan(s, e));
    if (x.e < y.e) {
      i++;
    } else {
      j++;
    }
  }
  return out;
}

/// What of [a] is not covered by [b]. O(a + b).
List<MsSpan> subtractSpans(List<MsSpan> a, List<MsSpan> b) {
  final out = <MsSpan>[];
  var j = 0;
  for (final x in a) {
    var s = x.s;
    while (j < b.length && b[j].e <= s) {
      j++;
    }
    for (var k = j; k < b.length && b[k].s < x.e; k++) {
      final y = b[k];
      if (y.s > s) out.add(MsSpan(s, y.s));
      if (y.e > s) s = y.e;
    }
    if (x.e > s) out.add(MsSpan(s, x.e));
  }
  return out;
}

/// A span as two instants.
({Instant start, Instant end}) spanInstants(MsSpan x) =>
    (start: Instant.fromEpochMilliseconds(x.s), end: Instant.fromEpochMilliseconds(x.e));
