import 'avl.dart';

/// An immutable sorted map. `set` and `delete` return a new map sharing all
/// but O(log n) nodes with the old one, which stays exactly as it was.
final class PersistentOrderedMap<K, V> {
  const PersistentOrderedMap._(this._ops, this._root);

  factory PersistentOrderedMap.empty(int Function(K a, K b) compare) =>
      PersistentOrderedMap._(AvlOps<K, V>(compare, (_, _) => 0), null);

  /// Code-unit order: what every id and key in the store is compared by.
  static PersistentOrderedMap<String, V> strings<V>() => PersistentOrderedMap.empty((a, b) => a.compareTo(b));

  final AvlOps<K, V> _ops;
  final AvlNode<K, V>? _root;

  int get length => avlSize(_root);
  bool get isEmpty => _root == null;

  V? operator [](K k) => avlGet(_ops, _root, k).$1;
  bool containsKey(K k) => avlGet(_ops, _root, k).$2;

  PersistentOrderedMap<K, V> set(K k, V v) => PersistentOrderedMap._(_ops, avlSet(_ops, _root, k, v));

  PersistentOrderedMap<K, V> remove(K k) {
    final root = avlDelete(_ops, _root, k);
    return identical(root, _root) ? this : PersistentOrderedMap._(_ops, root);
  }

  Iterable<(K, V)> get entries => avlEntries(_root);
  Iterable<K> get keys => entries.map((e) => e.$1);
  Iterable<V> get values => entries.map((e) => e.$2);
}

final class _IKey {
  const _IKey(this.s, this.id);
  final int s;
  final String id;
}

final _intervalOps = AvlOps<_IKey, int>((a, b) {
  final c = a.s.compareTo(b.s);
  return c != 0 ? c : a.id.compareTo(b.id);
}, (_, e) => e);

/// Persistent half-open intervals `[s, e)` on integers, each tagged with an
/// id, ordered by `(s, id)` so two entries with the same start never collide.
/// Callers index a zero-length span as `[t, t + 1)`: a milestone must still
/// be found by a window that contains its instant.
final class PersistentIntervalTree {
  const PersistentIntervalTree._(this._root);

  static const empty = PersistentIntervalTree._(null);

  final AvlNode<_IKey, int>? _root;

  int get length => avlSize(_root);

  PersistentIntervalTree insert(int s, int e, String id) =>
      PersistentIntervalTree._(avlSet(_intervalOps, _root, _IKey(s, id), e));

  /// [s] must be the start it was inserted with: it is half of the key.
  PersistentIntervalTree remove(int s, String id) {
    final root = avlDelete(_intervalOps, _root, _IKey(s, id));
    return identical(root, _root) ? this : PersistentIntervalTree._(root);
  }

  /// Every entry with `s < qe && e > qs`, in start order. O(log n + k): a
  /// subtree whose largest end is ≤ qs is skipped, and so is everything right
  /// of a node that starts at or after qe.
  void overlapping(int qs, int qe, void Function(String id, int s, int e) visit) {
    void walk(AvlNode<_IKey, int>? n) {
      if (n == null || n.max <= qs) return;
      walk(n.l);
      if (n.k.s < qe) {
        if (n.v > qs) visit(n.k.id, n.k.s, n.v);
        walk(n.r);
      }
    }

    walk(_root);
  }
}
