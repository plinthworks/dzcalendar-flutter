/// A persistent AVL tree: every update returns a new root and shares every
/// untouched node with the old one (path copying). An old root is never
/// changed, so a snapshot stays valid as long as anyone holds it — undo, an
/// optimistic revert, a render reading while the store moves on.
///
/// Each node carries `max`: the largest `end` in its subtree. A plain map
/// sets every end to 0; the interval tree uses it to skip whole subtrees that
/// finish before a query starts.
library;

final class AvlNode<K, V> {
  AvlNode(this.k, this.v, this.l, this.r, this.h, this.size, this.max);
  final K k;
  final V v;
  final AvlNode<K, V>? l;
  final AvlNode<K, V>? r;
  final int h;
  final int size;
  final int max;
}

final class AvlOps<K, V> {
  const AvlOps(this.compare, this.end);
  final int Function(K a, K b) compare;

  /// The end of the span this entry covers; 0 for a plain map.
  final int Function(K k, V v) end;
}

int _h(AvlNode<Object?, Object?>? n) => n?.h ?? 0;
int _sz(AvlNode<Object?, Object?>? n) => n?.size ?? 0;
const _minInt = -0x20000000000000;
int _mx(AvlNode<Object?, Object?>? n) => n?.max ?? _minInt;
int _max3(int a, int b, int c) => a > b ? (a > c ? a : c) : (b > c ? b : c);

AvlNode<K, V> _node<K, V>(AvlOps<K, V> ops, K k, V v, AvlNode<K, V>? l, AvlNode<K, V>? r) =>
    AvlNode(k, v, l, r, (_h(l) > _h(r) ? _h(l) : _h(r)) + 1, _sz(l) + _sz(r) + 1, _max3(ops.end(k, v), _mx(l), _mx(r)));

AvlNode<K, V> _balance<K, V>(AvlOps<K, V> ops, K k, V v, AvlNode<K, V>? l, AvlNode<K, V>? r) {
  final bf = _h(l) - _h(r);
  if (bf > 1) {
    final ll = l!;
    if (_h(ll.l) >= _h(ll.r)) return _node(ops, ll.k, ll.v, ll.l, _node(ops, k, v, ll.r, r));
    final lr = ll.r!;
    return _node(ops, lr.k, lr.v, _node(ops, ll.k, ll.v, ll.l, lr.l), _node(ops, k, v, lr.r, r));
  }
  if (bf < -1) {
    final rr = r!;
    if (_h(rr.r) >= _h(rr.l)) return _node(ops, rr.k, rr.v, _node(ops, k, v, l, rr.l), rr.r);
    final rl = rr.l!;
    return _node(ops, rl.k, rl.v, _node(ops, k, v, l, rl.l), _node(ops, rr.k, rr.v, rl.r, rr.r));
  }
  return _node(ops, k, v, l, r);
}

/// Inserts or replaces. O(log n).
AvlNode<K, V> avlSet<K, V>(AvlOps<K, V> ops, AvlNode<K, V>? n, K k, V v) {
  if (n == null) return _node(ops, k, v, null, null);
  final c = ops.compare(k, n.k);
  if (c < 0) return _balance(ops, n.k, n.v, avlSet(ops, n.l, k, v), n.r);
  if (c > 0) return _balance(ops, n.k, n.v, n.l, avlSet(ops, n.r, k, v));
  return _node(ops, k, v, n.l, n.r);
}

(AvlNode<K, V>, AvlNode<K, V>?) _popMin<K, V>(AvlOps<K, V> ops, AvlNode<K, V> n) {
  final l = n.l;
  if (l == null) return (n, n.r);
  final (min, rest) = _popMin(ops, l);
  return (min, _balance(ops, n.k, n.v, rest, n.r));
}

/// Removes [k] if present; returns the same root when it is absent. O(log n).
AvlNode<K, V>? avlDelete<K, V>(AvlOps<K, V> ops, AvlNode<K, V>? n, K k) {
  if (n == null) return null;
  final c = ops.compare(k, n.k);
  if (c < 0) {
    final l = avlDelete(ops, n.l, k);
    return identical(l, n.l) ? n : _balance(ops, n.k, n.v, l, n.r);
  }
  if (c > 0) {
    final r = avlDelete(ops, n.r, k);
    return identical(r, n.r) ? n : _balance(ops, n.k, n.v, n.l, r);
  }
  final l = n.l;
  final r = n.r;
  if (l == null) return r;
  if (r == null) return l;
  final (min, rest) = _popMin(ops, r);
  return _balance(ops, min.k, min.v, l, rest);
}

/// The value at [k], and whether there is one.
(V?, bool) avlGet<K, V>(AvlOps<K, V> ops, AvlNode<K, V>? n, K k) {
  var at = n;
  while (at != null) {
    final c = ops.compare(k, at.k);
    if (c == 0) return (at.v, true);
    at = c < 0 ? at.l : at.r;
  }
  return (null, false);
}

/// In key order, without recursion depth limits.
Iterable<(K, V)> avlEntries<K, V>(AvlNode<K, V>? root) sync* {
  final stack = <AvlNode<K, V>>[];
  var n = root;
  while (n != null || stack.isNotEmpty) {
    while (n != null) {
      stack.add(n);
      n = n.l;
    }
    final top = stack.removeLast();
    yield (top.k, top.v);
    n = top.r;
  }
}

int avlSize(AvlNode<Object?, Object?>? n) => _sz(n);
