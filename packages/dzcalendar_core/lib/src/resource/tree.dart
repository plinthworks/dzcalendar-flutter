import '../event/problem.dart';
import '../event/types.dart';
import '../rules/business_hours.dart';
import '../rules/constraint.dart';
import '../util/equality.dart';
import '../util/js.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';

/// A resource as an application gives it: a person, a room, a machine —
/// whatever events are booked on. [fields] holds the application's own
/// (`unit`, `floor`…), read for grouping, ordering and columns.
final class ResourceInput {
  const ResourceInput({
    required this.id,
    this.title,
    this.parentId,
    this.order,
    this.timeZone,
    this.businessHours,
    this.eventConstraint,
    this.eventOverlap,
    this.classNames = const [],
    this.extendedProps = const {},
    this.fields = const {},
  });

  final ResourceId id;
  final String? title;

  /// Its parent in the tree (a department above its doctors).
  final ResourceId? parentId;

  /// Siblings are drawn by this number first (lowest first), then as given.
  final num? order;

  /// Where its business hours are read (a doctor in Riyadh): the calendar's
  /// zone when absent.
  final ZoneId? timeZone;

  /// Its own hours, over the calendar's.
  final BusinessHours? businessHours;

  /// Where its events may go, over the calendar's constraint.
  final ConstraintSpec? eventConstraint;

  /// False: no two events on it overlap, whatever the calendar's rule; true:
  /// they may, whatever the calendar's rule.
  final bool? eventOverlap;
  final List<String> classNames;
  final Map<String, Object?> extendedProps;
  final Map<String, Object?> fields;

  @override
  bool operator ==(Object other) =>
      other is ResourceInput &&
      other.id == id &&
      other.title == title &&
      other.parentId == parentId &&
      other.order == order &&
      other.timeZone == timeZone &&
      other.businessHours == businessHours &&
      other.eventConstraint == eventConstraint &&
      other.eventOverlap == eventOverlap &&
      deepEquals(other.classNames, classNames) &&
      deepEquals(other.extendedProps, extendedProps) &&
      deepEquals(other.fields, fields);

  @override
  int get hashCode => Object.hash(id, title, parentId, order, timeZone, businessHours, eventConstraint, eventOverlap);

  static const _known = {
    'id',
    'title',
    'parentId',
    'order',
    'timeZone',
    'businessHours',
    'eventConstraint',
    'eventOverlap',
    'classNames',
    'extendedProps',
  };

  /// Reads the web's shape. Never throws: an entry that is not an object or
  /// has no id is refused (null, an error); a field that cannot be read is
  /// dropped with a warning at `[path].field`; the other keys go to [fields].
  static (ResourceInput?, List<Problem>) fromJson(Object? json, [String path = 'resource']) {
    final problems = <Problem>[];
    if (json is! Map) return (null, [Problem(ProblemCode.invalidResource, Severity.error, path)]);
    final id = json['id'];
    if (id is! String || id.isEmpty) return (null, [Problem(ProblemCode.invalidResource, Severity.error, '$path.id')]);
    T? read<T>(String field, T? Function(Object v) parse, {ProblemCode code = ProblemCode.invalidResource}) {
      final Object? v = json[field];
      // null is "none" for a parent; elsewhere a value that cannot be read.
      if (v == null && (field == 'parentId' || !json.containsKey(field))) return null;
      final out = v == null ? null : parse(v);
      if (out == null) problems.add(Problem(code, Severity.warning, '$path.$field', v is String ? v : null));
      return out;
    }

    final title = read('title', (v) => v is String ? v : null);
    final parentId = read('parentId', (v) => v is String ? v : null);
    final order = read('order', (v) => v is num && v.isFinite ? v : null);
    final timeZone = read('timeZone', (v) => v is String && isValidZone(v) ? v : null, code: ProblemCode.unknownZone);
    final hours = read('businessHours', (v) => BusinessHours.fromJson(v).$1);
    final constraint = read('eventConstraint', (v) => ConstraintSpec.fromJson(v).$1);
    final overlap = read('eventOverlap', (v) => v is bool ? v : null);
    final classNames = read('classNames', (v) => v is List && v.every((x) => x is String) ? v.cast<String>() : null);
    final props = read('extendedProps', (v) => v is Map ? v.map((k, v) => MapEntry('$k', v)) : null);
    return (
      ResourceInput(
        id: id,
        title: title,
        parentId: parentId,
        order: order,
        timeZone: timeZone,
        businessHours: hours,
        eventConstraint: constraint,
        eventOverlap: overlap,
        classNames: List.unmodifiable(classNames ?? const <String>[]),
        extendedProps: Map.unmodifiable(props ?? const <String, Object?>{}),
        fields: Map.unmodifiable({
          for (final e in json.entries)
            if (!_known.contains(e.key)) '${e.key}': e.value,
        }),
      ),
      problems,
    );
  }
}

/// A resource as the calendar keeps it: checked, with what was given beside it.
final class Resource {
  const Resource._({
    required this.id,
    required this.title,
    required this.parentId,
    required this.order,
    required this.timeZone,
    required this.businessHours,
    required this.eventConstraint,
    required this.eventOverlap,
    required this.classNames,
    required this.extendedProps,
    required this.fields,
  });

  final ResourceId id;
  final String title;

  /// Null for a root, and for one whose parent is unknown or in a cycle (reported).
  final ResourceId? parentId;
  final num? order;
  final ZoneId? timeZone;
  final BusinessHours? businessHours;
  final ConstraintSpec? eventConstraint;
  final bool? eventOverlap;
  final List<String> classNames;
  final Map<String, Object?> extendedProps;
  final Map<String, Object?> fields;

  /// A field by name: its own (`title`, `order`…), else the application's
  /// ([fields]), else its [extendedProps]; null when it has none.
  Object? field(String name) => switch (name) {
    'id' => id,
    'title' => title,
    'parentId' => parentId,
    'order' => order,
    'timeZone' => timeZone,
    'businessHours' => businessHours,
    'eventConstraint' => eventConstraint,
    'eventOverlap' => eventOverlap,
    'classNames' => classNames,
    'extendedProps' => extendedProps,
    _ => fields.containsKey(name) ? fields[name] : extendedProps[name],
  };

  Resource _withoutParent() => Resource._(
    id: id,
    title: title,
    parentId: null,
    order: order,
    timeZone: timeZone,
    businessHours: businessHours,
    eventConstraint: eventConstraint,
    eventOverlap: eventOverlap,
    classNames: classNames,
    extendedProps: extendedProps,
    fields: fields,
  );
}

/// The id of the "Unassigned" column or row: events on no resource, or only
/// on resources the calendar does not know. It starts with a NUL, so it never
/// meets an application's id.
const unassignedId = '\u0000unassigned';

/// The "Unassigned" pseudo-resource; its words are the widgets'.
const unassignedResource = Resource._(
  id: unassignedId,
  title: '',
  parentId: null,
  order: null,
  timeZone: null,
  businessHours: null,
  eventConstraint: null,
  eventOverlap: null,
  classNames: [],
  extendedProps: {},
  fields: {},
);

final class ResourceNode {
  ResourceNode._(this.resource, this.parent)
    : depth = parent == null ? 0 : parent.depth + 1,
      path = List.unmodifiable([...?parent?.path, resource.id]);

  final Resource resource;

  /// 0 for a root.
  final int depth;

  /// Ids from the root down to this one, itself included.
  final List<ResourceId> path;
  final ResourceNode? parent;
  List<ResourceNode> get children => _children;
  List<ResourceNode> _children = const [];
}

final class ResourceTree {
  ResourceTree._(this.roots, this.byId, this.order);

  /// No resources.
  static final empty = ResourceTree._(const [], const {}, const []);

  final List<ResourceNode> roots;
  final Map<ResourceId, ResourceNode> byId;

  /// Every resource, depth first, siblings in order: the columns' order, a
  /// timeline's rows all expanded.
  final List<Resource> order;
}

/// What [buildResourceTree] gives: the tree, and what was refused or dropped.
final class ResourceTreeResult {
  const ResourceTreeResult(this.tree, this.problems);
  final ResourceTree tree;
  final List<Problem> problems;
}

/// How siblings are ordered: field names (`-` first: descending), or a comparison.
sealed class ResourceOrder {
  const ResourceOrder();

  /// `["unit", "-title"]`.
  factory ResourceOrder.fields(List<String> fields) = FieldOrder;

  /// `"unit, -title"`.
  factory ResourceOrder.parse(String fields) => FieldOrder(fields.split(','));
  const factory ResourceOrder.compare(int Function(Resource a, Resource b) compare) = CompareOrder;

  /// A string or a list of strings; null for anything else.
  static ResourceOrder? fromJson(Object? json) => switch (json) {
    final String s => ResourceOrder.parse(s),
    final List<Object?> l when l.every((x) => x is String) => ResourceOrder.fields(l.cast<String>()),
    _ => null,
  };
}

final class FieldOrder extends ResourceOrder {
  FieldOrder(List<String> fields) : fields = List.unmodifiable(fields.map((f) => f.trim()).where((f) => f.isNotEmpty));
  final List<String> fields;

  @override
  bool operator ==(Object other) => other is FieldOrder && deepEquals(other.fields, fields);

  @override
  int get hashCode => deepHash(fields);
}

final class CompareOrder extends ResourceOrder {
  const CompareOrder(this.compare);
  final int Function(Resource a, Resource b) compare;
}

/// Two values of a field: numbers as numbers, the rest as text in a stable,
/// locale-free order (UTF-16 code units, as the web); absent last.
int _compareValues(Object? a, Object? b) {
  if (a == b) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  if (a is num && b is num) return a.compareTo(b);
  return jsText(a).compareTo(jsText(b));
}

int Function(Resource, Resource)? _comparator(ResourceOrder? order) => switch (order) {
  null => null,
  CompareOrder(:final compare) => compare,
  FieldOrder(:final fields) => (a, b) {
    for (final f in fields) {
      final desc = f.startsWith('-');
      final name = desc ? f.substring(1) : f;
      final x = a.field(name);
      final y = b.field(name);
      // Absent last whichever the direction: only what both have is turned round.
      if (x == null || y == null) {
        if ((x == null) != (y == null)) return x == null ? 1 : -1;
        continue;
      }
      final c = _compareValues(x, y);
      if (c != 0) return desc ? -c : c;
    }
    return 0;
  },
};

/// The resources as a tree, checked. Siblings go by `order` (lowest first,
/// then those without), then by [orderBy], then as given. Never throws: an
/// entry without an id is refused (`invalid-resource`), a second one with
/// the same id too (`duplicate-id`); an unknown parent makes a root
/// (`unknown-resource`), and so does the resource that closes a cycle
/// (`resource-cycle`); a zone that is not one is dropped (`unknown-zone`).
ResourceTreeResult buildResourceTree(List<ResourceInput> inputs, {ResourceOrder? orderBy}) =>
    _build([for (final x in inputs) (x, const <Problem>[])], orderBy);

/// [buildResourceTree] over the web's JSON (a list of objects), read entry
/// by entry with [ResourceInput.fromJson]: problems come in the input's order.
ResourceTreeResult buildResourceTreeFromJson(Object? json, {ResourceOrder? orderBy}) {
  if (json == null) return _build(const [], orderBy);
  if (json is! List) {
    final r = _build(const [], orderBy);
    return ResourceTreeResult(r.tree, [
      Problem(ProblemCode.invalidResource, Severity.error, 'resources'),
      ...r.problems,
    ]);
  }
  return _build([for (var i = 0; i < json.length; i++) ResourceInput.fromJson(json[i], 'resources[$i]')], orderBy);
}

ResourceTreeResult _build(List<(ResourceInput?, List<Problem>)> entries, ResourceOrder? orderBy) {
  final problems = <Problem>[];
  final read = <Resource>[];
  // Each kept resource's place in the input: what problems point at.
  final at = <int>[];
  final index = <ResourceId, int>{};
  for (var i = 0; i < entries.length; i++) {
    final (x, found) = entries[i];
    problems.addAll(found);
    if (x == null) continue;
    final r = _check(x, 'resources[$i]', problems);
    if (r == null) continue;
    if (index.containsKey(r.id)) {
      problems.add(Problem(ProblemCode.duplicateId, Severity.error, 'resources[$i].id', r.id));
      continue;
    }
    index[r.id] = read.length;
    read.add(r);
    at.add(i);
  }

  // Parents: unknown ones and cycles are cut, the resource becomes a root.
  final parentOf = <ResourceId, ResourceId?>{};
  for (var i = 0; i < read.length; i++) {
    final r = read[i];
    var p = r.parentId;
    if (p != null && !index.containsKey(p)) {
      problems.add(Problem(ProblemCode.unknownResource, Severity.warning, 'resources[${at[i]}].parentId', p));
      p = null;
    }
    parentOf[r.id] = p;
  }
  for (var i = 0; i < read.length; i++) {
    final r = read[i];
    final seen = {r.id};
    for (var p = parentOf[r.id]; p != null; p = parentOf[p]) {
      if (seen.contains(p)) {
        // Back to itself: the first of a cycle (in input order) becomes a root. A cycle
        // further up is not this one's to break: its own first member will be.
        if (p == r.id) {
          problems.add(
            Problem(ProblemCode.resourceCycle, Severity.warning, 'resources[${at[i]}].parentId', r.parentId),
          );
          parentOf[r.id] = null;
        }
        break;
      }
      seen.add(p);
    }
  }
  final fixed = [for (final r in read) parentOf[r.id] == r.parentId ? r : r._withoutParent()];

  final cmp = _comparator(orderBy);
  final pos = {for (var i = 0; i < fixed.length; i++) fixed[i].id: i};
  // An application's comparison that throws: input order, said once (bad input never throws).
  var failed = false;
  int safe(Resource a, Resource b) {
    if (failed) return 0;
    try {
      return cmp!(a, b);
    } catch (_) {
      failed = true;
      problems.add(const Problem(ProblemCode.invalidResource, Severity.warning, 'resourceOrder'));
      return 0;
    }
  }

  void sortWith(List<Resource> xs, int Function(Resource, Resource)? by) => xs.sort((a, b) {
    final ao = a.order;
    final bo = b.order;
    if (ao != bo) {
      if (ao == null) return 1;
      if (bo == null) return -1;
      final c = ao.compareTo(bo);
      if (c != 0) return c;
    }
    final c = by == null ? 0 : by(a, b);
    return c != 0 ? c : pos[a.id]!.compareTo(pos[b.id]!);
  });
  final kids = <ResourceId?, List<Resource>>{};
  for (final r in fixed) {
    (kids[r.parentId] ??= []).add(r);
  }
  // Every group of siblings sorted first; once a comparison has thrown, the whole tree in
  // input order (by `order` first) — not half of it sorted by the comparison and half not.
  for (final xs in kids.values) {
    sortWith(xs, cmp == null ? null : safe);
  }
  if (failed) {
    for (final xs in kids.values) {
      sortWith(xs, null);
    }
  }

  final byId = <ResourceId, ResourceNode>{};
  final order = <Resource>[];
  ResourceNode make(Resource r, ResourceNode? parent) {
    final node = ResourceNode._(r, parent);
    byId[r.id] = node;
    order.add(r);
    node._children = List.unmodifiable([for (final c in kids[r.id] ?? const <Resource>[]) make(c, node)]);
    return node;
  }

  final roots = [for (final r in kids[null] ?? const <Resource>[]) make(r, null)];
  return ResourceTreeResult(
    ResourceTree._(List.unmodifiable(roots), Map.unmodifiable(byId), List.unmodifiable(order)),
    problems,
  );
}

/// One typed input checked: an empty id is refused; a zone that is not one
/// and an order that is not a number are dropped with a warning.
Resource? _check(ResourceInput x, String path, List<Problem> problems) {
  if (x.id.isEmpty) {
    problems.add(Problem(ProblemCode.invalidResource, Severity.error, '$path.id'));
    return null;
  }
  var order = x.order;
  if (order != null && !order.isFinite) {
    problems.add(Problem(ProblemCode.invalidResource, Severity.warning, '$path.order'));
    order = null;
  }
  var zone = x.timeZone;
  if (zone != null && !isValidZone(zone)) {
    problems.add(Problem(ProblemCode.unknownZone, Severity.warning, '$path.timeZone', zone));
    zone = null;
  }
  return Resource._(
    id: x.id,
    title: x.title ?? '',
    parentId: x.parentId,
    order: order,
    timeZone: zone,
    businessHours: x.businessHours,
    eventConstraint: x.eventConstraint,
    eventOverlap: x.eventOverlap,
    classNames: List.unmodifiable(x.classNames),
    extendedProps: Map.unmodifiable(x.extendedProps),
    fields: Map.unmodifiable(x.fields),
  );
}
