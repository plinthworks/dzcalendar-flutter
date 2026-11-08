import '../event/problem.dart';
import '../intervals.dart';
import '../util/equality.dart';
import '../util/js.dart';

/// Where an event may go: inside business hours, inside a group's events,
/// inside given spans (epoch milliseconds: spans are instants, in no zone).
sealed class ConstraintSpec {
  const ConstraintSpec();

  static const businessHours = BusinessHoursConstraint();
  const factory ConstraintSpec.group(String groupId) = GroupConstraint;
  factory ConstraintSpec.spans(List<MsSpan> spans) = SpansConstraint;

  /// The web's spellings: `"businessHours"`, `{"groupId": "x"}`,
  /// `{"spans": [{"s": 0, "e": 1}]}` (a span's ends to the millisecond: the
  /// web keeps fractions). Never throws: null and an `invalid-option` error
  /// at [path] for anything else.
  static (ConstraintSpec?, List<Problem>) fromJson(Object? json, [String path = 'constraint']) {
    final spec = _read(json);
    return spec != null
        ? (spec, const [])
        : (null, [Problem(ProblemCode.invalidOption, Severity.error, path, jsText(json))]);
  }

  static ConstraintSpec? _read(Object? json) {
    if (json == 'businessHours') return businessHours;
    if (json is! Map) return null;
    final group = json['groupId'];
    if (group is String) return ConstraintSpec.group(group);
    final spans = json['spans'];
    if (spans is! List) return null;
    final out = <MsSpan>[];
    for (final x in spans) {
      if (x is! Map) return null;
      final s = x['s'];
      final e = x['e'];
      if (s is! num || e is! num || !s.isFinite || !e.isFinite) return null;
      out.add(MsSpan(jsRound(s), jsRound(e)));
    }
    return ConstraintSpec.spans(out);
  }
}

final class BusinessHoursConstraint extends ConstraintSpec {
  const BusinessHoursConstraint();

  @override
  bool operator ==(Object other) => other is BusinessHoursConstraint;

  @override
  int get hashCode => (BusinessHoursConstraint).hashCode;
}

final class GroupConstraint extends ConstraintSpec {
  const GroupConstraint(this.groupId);
  final String groupId;

  @override
  bool operator ==(Object other) => other is GroupConstraint && other.groupId == groupId;

  @override
  int get hashCode => groupId.hashCode;
}

final class SpansConstraint extends ConstraintSpec {
  SpansConstraint(List<MsSpan> spans) : spans = List.unmodifiable(spans);
  final List<MsSpan> spans;

  @override
  bool operator ==(Object other) => other is SpansConstraint && deepEquals(other.spans, spans);

  @override
  int get hashCode => deepHash(spans);
}
