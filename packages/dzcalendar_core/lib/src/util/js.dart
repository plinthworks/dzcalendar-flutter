/// JavaScript's ways with numbers and text, where the web's answer depends
/// on them: grouping and ordering by a field's text, rounding.
library;

/// A value as JavaScript's `String(x)` writes it: `1.0` is `1`, a list is
/// its items joined by commas, an object `[object Object]`, `null` "null".
String jsText(Object? v) => switch (v) {
  final double d when d.isFinite && d == d.truncateToDouble() && d.abs() < 1e21 => d.toInt().toString(),
  final double d when d.isNaN => 'NaN',
  final double d when d.isInfinite => d > 0 ? 'Infinity' : '-Infinity',
  final List<Object?> l => l.map((x) => x == null ? '' : jsText(x)).join(','),
  Map() => '[object Object]',
  _ => '$v',
};

/// `Math.round`: halves go up (towards +∞), where Dart's `round` goes away from zero.
int jsRound(num x) => (x + 0.5).floor();
