import '../time/plain.dart';

/// How a source's time is cut into pieces fetched and cached separately.
enum ChunkUnit { none, week, month, year }

/// A source's cut, and the chunks fetched ahead on each side of what is shown.
final class ChunkPolicy {
  const ChunkPolicy(this.unit, {this.prefetch = 0});
  static const none = ChunkPolicy(ChunkUnit.none);
  static const month = ChunkPolicy(ChunkUnit.month);

  final ChunkUnit unit;
  final int prefetch;

  @override
  bool operator ==(Object other) => other is ChunkPolicy && other.unit == unit && other.prefetch == prefetch;

  @override
  int get hashCode => Object.hash(unit, prefetch);
}

/// A piece of a source's time, fetched and cached as one: whole dates, [end]
/// exclusive. [key]: `2026-10-19` (a week), `2026-10` (a month), `2026` (a
/// year), `*` (a source not cut).
final class Chunk {
  const Chunk(this.key, this.start, this.end);
  final String key;
  final PlainDate start;
  final PlainDate end;

  @override
  String toString() => key;
}

/// The chunk [d] falls in. Weeks start on Monday: a chunk is a fetch, not a
/// row on screen. [unit] is not [ChunkUnit.none].
Chunk chunkAt(ChunkUnit unit, PlainDate d) {
  switch (unit) {
    case ChunkUnit.week:
      final start = d.addDays(-(d.dayOfWeek - 1));
      return Chunk('$start', start, start.addDays(7));
    case ChunkUnit.month:
      final start = PlainDate(d.year, d.month, 1);
      return Chunk('$start'.substring(0, '$start'.length - 3), start, start.addMonths(1));
    case ChunkUnit.year:
      final start = PlainDate(d.year, 1, 1);
      return Chunk('${start.year}', start, PlainDate(d.year + 1, 1, 1));
    case ChunkUnit.none:
      throw ArgumentError.value(unit, 'unit', 'a source not cut has no chunks');
  }
}

/// The chunks covering `[start, end)`, with [prefetch] more on each side, in order.
List<Chunk> chunksCovering(ChunkUnit unit, PlainDate start, PlainDate end, [int prefetch = 0]) {
  var first = chunkAt(unit, start);
  for (var i = 0; i < prefetch; i++) {
    first = chunkAt(unit, first.start.addDays(-1));
  }
  final out = [first];
  var extra = 0;
  for (var c = first; ;) {
    c = chunkAt(unit, c.end);
    if (!c.start.isBefore(end) && ++extra > prefetch) break;
    out.add(c);
  }
  return out;
}
