import '../event/normalize.dart';
import '../event/problem.dart';
import '../event/types.dart';
import '../rules/validate.dart';
import '../store/changes.dart';

/// How far an edit of one occurrence reaches.
enum EditScope { this_, following, all }

EditScope? _scope(Object? v) => switch (v) {
  'this' => EditScope.this_,
  'following' => EditScope.following,
  'all' => EditScope.all,
  _ => null,
};

/// The fields a patch can take away (owner, 2026-11-08, decision 10).
enum EventField { end, groupId, tone, url }

/// Everything an update may change. A field left `null` is kept; [clear]
/// names the fields taken away (an end back to the default length, no tone,
/// no url, no group) — `null` cannot say it, it means "unchanged".
final class EventPatch {
  const EventPatch({
    this.title,
    this.start,
    this.end,
    this.duration,
    this.allDay,
    this.timeZone,
    this.resourceId,
    this.resourceIds,
    this.display,
    this.status,
    this.busy,
    this.editable,
    this.startEditable,
    this.durationEditable,
    this.resourceEditable,
    this.classNames,
    this.tone,
    this.url,
    this.groupId,
    this.extendedProps,
    this.ongoing,
    this.clear = const {},
  });

  /// From JSON, never throwing: a field written `null` among [EventField] is
  /// taken away (`null` elsewhere: unchanged); a field of the wrong type, or
  /// one an update cannot change (`id`, `rrule`, `exdate`…), is a problem at
  /// `path.field` and the patch is null.
  static ({EventPatch? patch, List<Problem> problems}) fromJson(Map<Object?, Object?> json, [String path = 'patch']) {
    final input = EventInput.fromJson(json);
    final problems = [
      for (final (code, field, detail) in readProblemsOf(input)) Problem(code, Severity.error, '$path.$field', detail),
      for (final k in const ['id', 'rrule', 'exdate', 'rdate', 'seriesId', 'recurrenceId'])
        if (json[k] != null)
          Problem(
            k == 'rrule' ? ProblemCode.invalidRrule : ProblemCode.invalidEdit,
            Severity.error,
            '$path.$k',
            k == 'rrule' ? 'an update cannot add a rule' : 'not changed by an update',
          ),
    ];
    if (problems.isNotEmpty) return (patch: null, problems: problems);
    final patch = EventPatch(
      title: input.title,
      start: input.start,
      end: input.end,
      duration: input.duration,
      allDay: input.allDay,
      timeZone: input.timeZone,
      resourceId: input.resourceId,
      resourceIds: input.resourceIds,
      display: input.display,
      status: input.status,
      busy: input.busy,
      editable: input.editable,
      startEditable: input.startEditable,
      durationEditable: input.durationEditable,
      resourceEditable: input.resourceEditable,
      classNames: input.classNames,
      tone: input.tone,
      url: input.url,
      groupId: input.groupId,
      extendedProps: input.extendedProps,
      ongoing: input.ongoing,
      clear: {
        for (final f in EventField.values)
          if (json.containsKey(f.name) && json[f.name] == null) f,
      },
    );
    return (patch: patch, problems: const []);
  }

  /// Whether it touches where the event sits (start, end, length, all-day,
  /// resources): what the calendar's rules check.
  bool get movesTime =>
      start != null ||
      end != null ||
      duration != null ||
      allDay != null ||
      resourceId != null ||
      resourceIds != null ||
      clear.contains(EventField.end);

  /// The fields both set and cleared: a patch cannot say both.
  List<EventField> get conflicts => [
    for (final f in clear)
      if (switch (f) {
        EventField.end => end != null,
        EventField.groupId => groupId != null,
        EventField.tone => tone != null,
        EventField.url => url != null,
      })
        f,
  ];

  final String? title;
  final Object? start;
  final Object? end;
  final Object? duration;
  final bool? allDay;
  final String? timeZone;
  final ResourceId? resourceId;
  final List<ResourceId>? resourceIds;
  final EventDisplay? display;
  final EventStatus? status;
  final bool? busy;
  final bool? editable;
  final bool? startEditable;
  final bool? durationEditable;
  final bool? resourceEditable;
  final List<String>? classNames;
  final String? tone;
  final String? url;
  final String? groupId;
  final Map<String, Object?>? extendedProps;
  final bool? ongoing;
  final Set<EventField> clear;

  bool get hasStart => start != null;
  bool get hasEnd => end != null || clear.contains(EventField.end);
  bool get hasDuration => duration != null;
  bool get hasTimeZone => timeZone != null;
  bool get hasAllDay => allDay != null;
  bool get hasResources => resourceId != null || resourceIds != null;

  /// True when the patch says nothing at all.
  bool get isEmpty =>
      title == null &&
      start == null &&
      end == null &&
      duration == null &&
      allDay == null &&
      timeZone == null &&
      resourceId == null &&
      resourceIds == null &&
      display == null &&
      status == null &&
      busy == null &&
      editable == null &&
      startEditable == null &&
      durationEditable == null &&
      resourceEditable == null &&
      classNames == null &&
      tone == null &&
      url == null &&
      groupId == null &&
      extendedProps == null &&
      ongoing == null &&
      clear.isEmpty;
}

/// Which occurrence of a series a command is about. [key]: the occurrence's
/// original start, when `id` is the series': as the series writes it, the
/// wall time without its offset, or an instant.
sealed class Command {
  const Command();

  /// A command as JSON writes it (the TS's `Command`). Never throws and
  /// never fails to answer: what cannot be read is an [InvalidCommand]
  /// carrying its problems, at their paths (`command.patch.title`,
  /// `command.commands[2].id`), which `applyCommand` reports.
  static Command fromJson(Map<Object?, Object?> json, [String path = 'command']) {
    final problems = <Problem>[];
    void bad(ProblemCode code, String field, Object? detail) =>
        problems.add(Problem(code, Severity.error, '$path.$field', '$detail'));
    String? text(String field, {bool required = false}) {
      final v = json[field];
      if (v is String) return v;
      if (v != null || required) bad(ProblemCode.invalidEdit, field, v ?? 'missing');
      return null;
    }

    final type = json['type'];
    final scopeRaw = json['scope'];
    final scope = scopeRaw == null ? null : _scope(scopeRaw);
    if (scopeRaw != null && scope == null) bad(ProblemCode.invalidEdit, 'scope', scopeRaw);
    final key = text('key');
    EventPatch? patch(String field, {bool required = true}) {
      final p = json[field];
      if (p == null && !required) return null;
      if (p is! Map) {
        bad(ProblemCode.invalidEdit, field, p ?? 'missing');
        return null;
      }
      final r = EventPatch.fromJson(p, '$path.$field');
      problems.addAll(r.problems);
      return r.patch;
    }

    Object? moment(String field) {
      final v = json[field];
      if (v == null) bad(ProblemCode.invalidEdit, field, 'missing');
      return v;
    }

    Command? command;
    switch (type) {
      case 'event.create':
        final e = json['event'];
        if (e is Map) {
          command = CreateEvent(EventInput.fromJson(e));
        } else {
          bad(ProblemCode.invalidEvent, 'event', e ?? 'missing');
        }
      case 'event.update':
        final id = text('id', required: true);
        final p = patch('patch');
        if (id != null && p != null) command = UpdateEvent(id, p, scope: scope, key: key);
      case 'event.move':
        final id = text('id', required: true);
        final start = moment('start');
        final ids = json['resourceIds'];
        if (ids != null && (ids is! List || ids.any((x) => x is! String))) {
          bad(ProblemCode.invalidEvent, 'resourceIds', 'expected a list of strings');
        }
        if (id != null && start != null) {
          command = MoveEvent(
            id,
            start,
            end: json['end'],
            resourceIds: ids is List ? ids.cast<String>() : null,
            scope: scope,
            key: key,
          );
        }
      case 'event.resize':
        final id = text('id', required: true);
        final edge = switch (json['edge']) {
          'start' => Edge.start,
          'end' => Edge.end,
          final e => (() {
            bad(ProblemCode.invalidEdit, 'edge', e ?? 'missing');
            return null;
          })(),
        };
        final to = moment('to');
        if (id != null && edge != null && to != null) command = ResizeEvent(id, edge, to, scope: scope, key: key);
      case 'event.delete':
        final id = text('id', required: true);
        if (id != null) command = DeleteEvent(id, scope: scope, key: key);
      case 'series.delete':
        final id = text('id', required: true);
        if (id != null) command = DeleteSeries(id);
      case 'series.split':
        final id = text('id', required: true);
        final at = text('at', required: true);
        final p = patch('patch', required: false);
        if (id != null && at != null) command = SplitSeries(id, at, patch: p);
      case 'series.rule':
        final id = text('id', required: true);
        final r = json['rrule'];
        // Only a `null` written out stops the series repeating; anything unreadable is refused.
        final ok =
            (r == null && json.containsKey('rrule')) || r is String || (r is List && r.every((x) => x is String));
        if (!ok) bad(ProblemCode.invalidRrule, 'rrule', r ?? 'missing');
        if (id != null && ok) command = ChangeRule(id, r);
      case 'event.repeat':
        final id = text('id', required: true);
        final r = json['rrule'];
        final ok = r is String || (r is List && r.every((x) => x is String));
        if (!ok) bad(ProblemCode.invalidRrule, 'rrule', r ?? 'missing');
        if (id != null && ok) command = RepeatEvent(id, r!);
      case 'batch':
        final label = text('label');
        final cs = json['commands'];
        if (cs is! List) {
          bad(ProblemCode.invalidEdit, 'commands', cs ?? 'missing');
          break;
        }
        final commands = <Command>[];
        for (var i = 0; i < cs.length; i++) {
          final c = cs[i];
          if (c is! Map) {
            bad(ProblemCode.invalidEdit, 'commands[$i]', c);
            continue;
          }
          final sub = Command.fromJson(c, '$path.commands[$i]');
          if (sub is InvalidCommand) problems.addAll(sub.problems);
          commands.add(sub);
        }
        command = Batch(commands, label: label);
      default:
        bad(ProblemCode.invalidEdit, 'type', type ?? 'missing');
    }
    return problems.isEmpty && command != null ? command : InvalidCommand(problems);
  }

  /// What the history calls an entry: `event.move`, or a batch's label.
  String get label;
}

/// A command [Command.fromJson] could not read: refused, its problems said.
final class InvalidCommand extends Command {
  const InvalidCommand(this.problems);
  final List<Problem> problems;
  @override
  String get label => 'invalid';
}

/// Which edge a resize moves.
enum Edge { start, end }

/// `event.create`; with an `rrule` it creates a series.
final class CreateEvent extends Command {
  const CreateEvent(this.event);
  final EventInput event;
  @override
  String get label => 'event.create';
}

/// The fields of a command that may name an occurrence.
abstract interface class Reach {
  EditScope? get scope;
  String? get key;
}

final class UpdateEvent extends Command implements Reach {
  const UpdateEvent(this.id, this.patch, {this.scope, this.key});
  final EventId id;
  final EventPatch patch;
  @override
  final EditScope? scope;
  @override
  final String? key;
  @override
  String get label => 'event.update';
}

/// A new start; the length is kept unless [end] is given.
final class MoveEvent extends Command implements Reach {
  const MoveEvent(this.id, this.start, {this.end, this.resourceIds, this.scope, this.key});
  final EventId id;
  final Object start;
  final Object? end;
  final List<ResourceId>? resourceIds;
  @override
  final EditScope? scope;
  @override
  final String? key;
  @override
  String get label => 'event.move';
}

/// One edge to a new moment; the other stays.
final class ResizeEvent extends Command implements Reach {
  const ResizeEvent(this.id, this.edge, this.to, {this.scope, this.key});
  final EventId id;
  final Edge edge;
  final Object to;
  @override
  final EditScope? scope;
  @override
  final String? key;
  @override
  String get label => 'event.resize';
}

final class DeleteEvent extends Command implements Reach {
  const DeleteEvent(this.id, {this.scope, this.key});
  final EventId id;
  @override
  final EditScope? scope;
  @override
  final String? key;
  @override
  String get label => 'event.delete';
}

/// The whole series, every occurrence and every override.
final class DeleteSeries extends Command {
  const DeleteSeries(this.id);
  final SeriesId id;
  @override
  String get label => 'series.delete';
}

/// "This and following" without the drag: the series cut at [at], the patch applied from there.
final class SplitSeries extends Command {
  const SplitSeries(this.id, this.at, {this.patch});
  final SeriesId id;
  final RecurrenceKey at;
  final EventPatch? patch;
  @override
  String get label => 'series.split';
}

/// A new rule for the whole series (a string or a list of them); `null`: it
/// stops repeating — its first occurrence becomes the event, each moved
/// occurrence an event of its own.
final class ChangeRule extends Command {
  const ChangeRule(this.id, this.rrule);
  final SeriesId id;
  final Object? rrule;
  @override
  String get label => 'series.rule';
}

/// A single event made to repeat: the same id, every field kept, now a series.
final class RepeatEvent extends Command {
  const RepeatEvent(this.id, this.rrule);
  final EventId id;
  final Object rrule;
  @override
  String get label => 'event.repeat';
}

final class Batch extends Command {
  const Batch(this.commands, {String? label}) : _label = label;
  final List<Command> commands;
  final String? _label;
  @override
  String get label => _label ?? 'batch';
}

final class CommandContext {
  const CommandContext({required this.normalize, this.weekStart, this.rules, this.external = false});
  final NormalizeContext normalize;

  /// The locale's first day of the week (ISO), written as WKST into a rule
  /// created without one (a rule read from elsewhere keeps RFC's Monday).
  final int? weekStart;

  /// When given, moves, edits and new series are checked against it
  /// (editable, valid range, constraint, overlap, allow): a refusal is in
  /// [CommandResult.violations].
  final RulesContext? rules;

  /// What is checked comes from outside the calendar (a drop from the page,
  /// another calendar): said to the rules' `allow`.
  final bool external;
}

/// The mutations that carry a command out (nothing applied yet), or why not.
final class CommandResult {
  const CommandResult.ok(this.mutations, this.problems) : ok = true, violations = const [];
  const CommandResult.failed(this.problems, [this.violations = const []]) : ok = false, mutations = const [];
  final bool ok;
  final List<Mutation> mutations;
  final List<Problem> problems;

  /// Why the calendar's rules refused it ([CommandContext.rules]); empty otherwise.
  final List<Violation> violations;
}
