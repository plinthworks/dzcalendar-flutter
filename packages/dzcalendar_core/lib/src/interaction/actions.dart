import '../commands/types.dart';
import '../event/types.dart';
import '../store/instance.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/zone_rules.dart';

/// Where a context menu (a long press, a right click) was opened: a moment
/// in a time grid, a whole day, or an event. A moment carries its reading,
/// so a menu on the repeated 02:30 can offer both, and one in a skipped hour
/// can say where it lands.
sealed class ActionTarget {
  const ActionTarget();
}

final class SlotTarget extends ActionTarget {
  const SlotTarget({
    required this.date,
    required this.instant,
    required this.exists,
    required this.ambiguous,
    this.alternative,
    this.resourceId,
  });
  final PlainDate date;
  final Instant instant;
  final bool exists;
  final bool ambiguous;

  /// The other reading of a repeated wall time.
  final Instant? alternative;
  final String? resourceId;
}

final class DayTarget extends ActionTarget {
  const DayTarget({required this.date, this.resourceId});
  final PlainDate date;
  final String? resourceId;
}

final class EventTarget extends ActionTarget {
  const EventTarget(this.instance);
  final EventInstance instance;
}

/// One menu entry, as data: the widgets render it (themed, RTL,
/// accessible); the application may keep, reorder, replace or add entries.
/// Disabled entries stay visible with their reason.
final class ActionItem {
  const ActionItem({
    required this.id,
    required this.label,
    this.enabled = true,
    this.reason,
    this.shortcut,
    this.icon,
    this.children = const [],
    this.command,
    this.run,
  });
  final String id;
  final String label;
  final bool enabled;
  final String? reason;
  final String? shortcut;

  /// A name the theme can draw an icon for.
  final String? icon;
  final List<ActionItem> children;

  /// The edit this entry stands for, when it is one: validated and undoable like any command.
  final Command? command;

  /// What runs. The built-ins call back into the calendar; an app's own entries carry their own.
  final void Function()? run;
}

/// "New event here", as the application receives it: a moment in a time
/// grid, a date in a month — a whole day is not "midnight", which some days
/// do not have (São Paulo, 4 November 2018).
sealed class CreateRequest {
  const CreateRequest({this.resourceId});
  final String? resourceId;
}

final class CreateAt extends CreateRequest {
  const CreateAt(this.start, {super.resourceId});
  final Instant start;
}

final class CreateOn extends CreateRequest {
  const CreateOn(this.date, {super.resourceId});
  final PlainDate date;
}

/// The words for the built-in entries (the widgets' translated messages).
final class ActionLabels {
  const ActionLabels({
    required this.newEventAt,
    required this.newEventOn,
    required this.goToDay,
    required this.openEvent,
    required this.skippedHour,
    required this.deleteEvent,
    required this.moveEvent,
    required this.resizeEvent,
    required this.scopeThis,
    required this.scopeFollowing,
    required this.scopeAll,
  });
  final String Function(String time) newEventAt;

  /// A whole-day event, from a month cell.
  final String Function(String date) newEventOn;
  final String goToDay;
  final String openEvent;
  final String skippedHour;
  final String deleteEvent;

  /// Grab mode (the keyboard's drag) on the event.
  final String moveEvent;
  final String resizeEvent;

  /// The recurrence scope sub-menu.
  final String scopeThis;
  final String scopeFollowing;
  final String scopeAll;
}

enum GrabKind { move, resize }

final class ActionContext {
  const ActionContext({
    required this.displayZone,
    required this.labels,
    required this.formatTime,
    required this.formatDate,
    this.onCreateRequest,
    this.onGoToDay,
    this.onOpen,
    this.onCommand,
    this.onGrab,
    this.canResize,
    this.canMove,
  });
  final ZoneId displayZone;
  final ActionLabels labels;

  /// Formats a moment for an entry, with its offset when it needs telling apart.
  final String Function(Instant at, bool withOffset) formatTime;
  final String Function(PlainDate date) formatDate;
  final void Function(CreateRequest request)? onCreateRequest;
  final void Function(PlainDate date)? onGoToDay;
  final void Function(EventInstance instance)? onOpen;

  /// Runs an editing entry's command (through the calendar's history). Without it, no editing entries.
  final void Function(Command command)? onCommand;

  /// "Move…" and "Change duration…": the calendar holds the event for the keyboard. Without it, no such entries.
  final void Function(EventInstance instance, GrabKind kind)? onGrab;

  /// Whether the view lets this event's length change (a month draws a timed event's day). Default yes.
  final bool Function(EventInstance instance)? canResize;

  /// Whether "Move…" is offered (default: the event's start is editable).
  final bool Function(EventInstance instance)? canMove;
}

/// The built-in entries for a target: what reads (open, go to the day), the
/// requests an application handles itself (new event here), and editing as
/// commands (move, change duration, delete, a series' scope).
List<ActionItem> actionsFor(ActionTarget target, ActionContext ctx) {
  final out = <ActionItem>[];
  final create = ctx.onCreateRequest;
  final goTo = ctx.onGoToDay;
  switch (target) {
    case SlotTarget(:final instant, :final alternative, :final ambiguous, :final exists, :final resourceId):
      if (create != null) {
        // A repeated hour has two moments: offer both, told apart by offset.
        final moments = ambiguous && alternative != null ? [instant, alternative] : [instant];
        for (var i = 0; i < moments.length; i++) {
          final m = moments[i];
          out.add(
            ActionItem(
              id: moments.length > 1 ? 'event.create.$i' : 'event.create',
              label: ctx.labels.newEventAt(ctx.formatTime(m, moments.length > 1)),
              reason: exists ? null : ctx.labels.skippedHour,
              run: () => create(CreateAt(m, resourceId: resourceId)),
            ),
          );
        }
      }
      if (goTo != null) {
        out.add(ActionItem(id: 'view.goToDay', label: ctx.labels.goToDay, run: () => goTo(target.date)));
      }
    case DayTarget(:final date, :final resourceId):
      if (create != null) {
        out.add(
          ActionItem(
            id: 'event.create',
            label: ctx.labels.newEventOn(ctx.formatDate(date)),
            run: () => create(CreateOn(date, resourceId: resourceId)),
          ),
        );
      }
      if (goTo != null) out.add(ActionItem(id: 'view.goToDay', label: ctx.labels.goToDay, run: () => goTo(date)));
    case EventTarget(:final instance):
      final open = ctx.onOpen;
      if (open != null) {
        out.add(ActionItem(id: 'event.open', label: ctx.labels.openEvent, run: () => open(instance)));
      }
      final ev = instance.event;
      final grab = ctx.onGrab;
      if (grab != null && ev.display != EventDisplay.background) {
        if (ctx.canMove?.call(instance) ?? ev.perms.start) {
          out.add(
            ActionItem(
              id: 'event.move',
              label: ctx.labels.moveEvent,
              shortcut: 'M',
              run: () => grab(instance, GrabKind.move),
            ),
          );
        }
        if (ev.perms.duration && (ctx.canResize?.call(instance) ?? true)) {
          out.add(
            ActionItem(id: 'event.resize', label: ctx.labels.resizeEvent, run: () => grab(instance, GrabKind.resize)),
          );
        }
      }
      final onCommand = ctx.onCommand;
      if (onCommand != null) out.add(_deleteEntry(instance, ctx.labels, onCommand));
  }
  return out;
}

/// "Delete": at once for an event; for an occurrence, a sub-menu says how far.
ActionItem _deleteEntry(EventInstance instance, ActionLabels labels, void Function(Command) onCommand) {
  final ref = instance.event.ref;
  if (ref == null) {
    final command = DeleteEvent(instance.event.id);
    return ActionItem(
      id: 'event.delete',
      label: labels.deleteEvent,
      icon: 'delete',
      command: command,
      run: () => onCommand(command),
    );
  }
  ActionItem scoped(EditScope scope, String name, String label) {
    final command = DeleteEvent(ref.seriesId, key: ref.key, scope: scope);
    return ActionItem(id: 'event.delete.$name', label: label, command: command, run: () => onCommand(command));
  }

  return ActionItem(
    id: 'event.delete',
    label: labels.deleteEvent,
    icon: 'delete',
    children: [
      scoped(EditScope.this_, 'this', labels.scopeThis),
      scoped(EditScope.following, 'following', labels.scopeFollowing),
      scoped(EditScope.all, 'all', labels.scopeAll),
    ],
  );
}
