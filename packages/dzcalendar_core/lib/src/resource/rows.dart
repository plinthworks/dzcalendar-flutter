import '../event/types.dart';
import '../store/instance.dart';
import '../store/store.dart';
import '../util/js.dart';
import 'tree.dart';

/// A row of a resource list: a resource, or a group's head above its resources.
sealed class ResourceRow {
  const ResourceRow();

  /// Stable across rebuilds: `r:<id>` or `g:<value>`.
  String get rowKey;
}

final class ResourceItemRow extends ResourceRow {
  const ResourceItemRow({required this.resource, required this.depth, required this.expanded});

  final Resource resource;
  final int depth;

  /// Null: no children; else whether they are shown.
  final bool? expanded;

  @override
  String get rowKey => 'r:${resource.id}';
}

final class GroupRow extends ResourceRow {
  const GroupRow({required this.value, required this.count, required this.expanded});

  /// The field's value, as text (`''` when the resource has none).
  final String value;

  /// Resources in it, whatever is collapsed.
  final int count;
  final bool expanded;

  @override
  String get rowKey => 'g:$value';
}

/// What is open and how the roots are grouped.
final class RowState {
  const RowState({this.expanded, this.collapsed, this.groupBy, this.collapsedGroups = const {}});

  /// Resources whose children are shown; null (the default) shows every one.
  final Set<ResourceId>? expanded;

  /// Or the other way: resources whose children are hidden (the rest shown).
  /// Wins over [expanded].
  final Set<ResourceId>? collapsed;

  /// Groups the roots by this field; each root's subtree stays in its root's group.
  final String? groupBy;

  /// Groups shut (by value).
  final Set<String> collapsedGroups;
}

/// A field's value as a group's name.
String groupValue(Resource r, String field) {
  final v = r.field(field);
  return v == null ? '' : jsText(v);
}

/// The rows a list of resources shows, in O(n): depth first, collapsed
/// subtrees left out, groups (by [RowState.groupBy], in the order their
/// first resource comes) as rows above their resources. [filter] drops a
/// resource and its subtree.
List<ResourceRow> flattenRows(ResourceTree tree, [RowState state = const RowState(), bool Function(Resource)? filter]) {
  bool open(ResourceId id) {
    final collapsed = state.collapsed;
    if (collapsed != null) return !collapsed.contains(id);
    final expanded = state.expanded;
    return expanded == null || expanded.contains(id);
  }

  void walk(ResourceNode node, List<ResourceRow> out) {
    if (filter != null && !filter(node.resource)) return;
    final expanded = node.children.isEmpty ? null : open(node.resource.id);
    out.add(ResourceItemRow(resource: node.resource, depth: node.depth, expanded: expanded));
    if (expanded ?? false) {
      for (final c in node.children) {
        walk(c, out);
      }
    }
  }

  final field = state.groupBy;
  final out = <ResourceRow>[];
  if (field == null || field.isEmpty) {
    for (final r in tree.roots) {
      walk(r, out);
    }
    return out;
  }
  final groups = <String, List<ResourceNode>>{};
  for (final r in tree.roots) {
    if (filter != null && !filter(r.resource)) continue;
    (groups[groupValue(r.resource, field)] ??= []).add(r);
  }
  for (final MapEntry(key: value, value: roots) in groups.entries) {
    final inside = <ResourceRow>[];
    for (final r in roots) {
      walk(r, inside);
    }
    final count = roots.fold(0, (n, r) => n + _size(r, filter));
    final expanded = !state.collapsedGroups.contains(value);
    out.add(GroupRow(value: value, count: count, expanded: expanded));
    if (expanded) out.addAll(inside);
  }
  return out;
}

int _size(ResourceNode node, bool Function(Resource)? filter) {
  if (filter != null && !filter(node.resource)) return 0;
  return 1 + node.children.fold(0, (n, c) => n + _size(c, filter));
}

/// The columns of a resource view: every resource in order, and the groups
/// above them.
final class ColumnResources {
  const ColumnResources(this.resources, this.groups);
  final List<Resource> resources;

  /// Consecutive resources sharing the field's value: `from` is the first's
  /// index. Empty without a `groupBy`.
  final List<({String value, int from, int count})> groups;
}

ColumnResources columnResources(ResourceTree tree, [String? groupBy]) {
  final resources = <Resource>[];
  final groups = <({String value, int from, int count})>[];
  for (final row in flattenRows(tree, RowState(groupBy: groupBy))) {
    switch (row) {
      case GroupRow(:final value, :final count):
        groups.add((value: value, from: resources.length, count: count));
      case ResourceItemRow(:final resource):
        resources.add(resource);
    }
  }
  return ColumnResources(List.unmodifiable(resources), List.unmodifiable(groups));
}

final _known = Expando<Set<ResourceId>>();

/// What one resource's column (or row) shows in a window: its events from
/// the per-resource index; for [unassignedResource], every event none of
/// whose resources is in [all].
List<EventInstance> instancesOf(
  StoreSnapshot snap,
  ViewWindow w,
  Resource resource,
  List<Resource> all, [
  QueryOptions opts = const QueryOptions(),
]) {
  if (resource.id != unassignedId) {
    return snap.queryInstances(
      w,
      QueryOptions(
        resourceId: resource.id,
        includeBackground: opts.includeBackground,
        onProblem: opts.onProblem,
        where: opts.where,
      ),
    );
  }
  final known = _known[all] ??= {for (final r in all) r.id};
  return [
    for (final i in snap.queryInstances(w, opts))
      if (!i.event.resourceIds.any(known.contains)) i,
  ];
}
