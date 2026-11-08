/// Value equality for the immutable configuration types (lists and maps
/// compared item by item, deeply).
library;

bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!b.containsKey(e.key) || !deepEquals(e.value, b[e.key])) return false;
    }
    return true;
  }
  if (a is Set && b is Set) return a.length == b.length && a.containsAll(b);
  return a == b;
}

int deepHash(Object? v) => switch (v) {
  final List<Object?> l => Object.hashAll(l.map(deepHash)),
  final Map<Object?, Object?> m => Object.hashAllUnordered(m.entries.map((e) => Object.hash(e.key, deepHash(e.value)))),
  final Set<Object?> s => Object.hashAllUnordered(s.map(deepHash)),
  _ => v.hashCode,
};
