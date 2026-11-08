import '../time/civil.dart';
import 'zone_rules.dart';

/// How a wall time that happens twice, or never, becomes one instant —
/// Temporal's `disambiguation`.
enum Disambiguation {
  /// The first reading of a repeated time; a skipped time pushed forward by
  /// the gap's length. What Temporal and the platforms do by default.
  compatible,

  /// The first reading; a skipped time pushed back.
  earlier,

  /// The second reading; a skipped time pushed forward.
  later,

  /// No instant unless there is exactly one.
  reject,
}

/// Offsets differ by at most 26 h and a change moves the clock by at most a
/// day (Apia, 2011): every instant that can read as a wall time lies within
/// this distance of it.
const _reach = 50 * msPerHour;

/// Every instant whose clock in [rules] reads [wallMs] (see
/// `PlainDateTime.wallMs`), earliest first: one, two for a repeated time,
/// none for a skipped one.
List<int> possibleInstants(int wallMs, ZoneRules rules) {
  if (rules is FixedOffset) return [wallMs - rules.offsetMs];
  final offsets = <int>{rules.offsetAt(wallMs - _reach)};
  for (var t = rules.nextTransition(wallMs - _reach); t != null && t <= wallMs + _reach; t = rules.nextTransition(t)) {
    offsets.add(rules.offsetAt(t));
  }
  final out = <int>{
    for (final o in offsets)
      if (rules.offsetAt(wallMs - o) == o) wallMs - o,
  }.toList()..sort();
  return out;
}

/// The clock change that skips [wallMs]: its instant and the offsets on each
/// side. Null when the time is not skipped.
({int at, int before, int after})? gapAround(int wallMs, ZoneRules rules) {
  for (var t = rules.nextTransition(wallMs - _reach); t != null && t <= wallMs + _reach; t = rules.nextTransition(t)) {
    final before = rules.offsetAt(t - 1);
    final after = rules.offsetAt(t);
    if (wallMs - before >= t && wallMs - after < t) return (at: t, before: before, after: after);
  }
  return null;
}

/// [wallMs] made one instant under [how]; null only for [Disambiguation.reject]
/// on a time that is repeated or skipped.
int? resolveWallMs(int wallMs, ZoneRules rules, Disambiguation how) {
  final all = possibleInstants(wallMs, rules);
  if (all.length == 1) return all.first;
  if (how == Disambiguation.reject) return null;
  if (all.isNotEmpty) return how == Disambiguation.later ? all.last : all.first;
  final gap = gapAround(wallMs, rules);
  // Unreachable with consistent rules; read with today's offset rather than fail.
  if (gap == null) return wallMs - rules.offsetAt(wallMs);
  // Read with the offset from before the change, the time lands past the gap;
  // with the one after, before it.
  return how == Disambiguation.earlier ? wallMs - gap.after : wallMs - gap.before;
}

/// The first instant of the day that starts at wall [wallMs] (a midnight).
/// Not always midnight: where midnight is skipped (São Paulo 2018, Havana)
/// the day starts on the change that skips it — Temporal's `startOfDay`.
int startOfDayMs(int wallMs, ZoneRules rules) {
  final all = possibleInstants(wallMs, rules);
  if (all.isNotEmpty) return all.first;
  final gap = gapAround(wallMs, rules);
  return gap?.at ?? wallMs - rules.offsetAt(wallMs);
}
