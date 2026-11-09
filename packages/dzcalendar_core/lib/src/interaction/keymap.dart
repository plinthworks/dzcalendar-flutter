import '../commands/types.dart' show Edge;
import '../event/types.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';
import 'propose.dart';

/// A key press, as any toolkit reports it: [key] is the web's name
/// (`ArrowLeft`, `Enter`, `Escape`, ` `, `z`…) — the Flutter widgets turn a
/// `LogicalKeyboardKey` into it, so the keymap is the same on every platform.
final class KeyLike {
  const KeyLike(this.key, {this.shift = false, this.alt = false, this.ctrl = false, this.meta = false});
  final String key;
  final bool shift;
  final bool alt;
  final bool ctrl;
  final bool meta;
}

/// Where the keyboard is: on the grid's cursor (a day, a slot), on an
/// event, or holding an event (grab mode — the keyboard's drag).
enum KeyMode { cursor, event, grab }

/// How the grid reads the arrows: a time grid's columns are days and its
/// rows slots; a day grid's rows are weeks; a timeline runs along time with
/// a resource per row.
enum KeyGrid { time, day, timeline }

/// How far one press goes: days, and slots of `snapMinutes`.
final class KeyStep {
  const KeyStep({this.days = 0, this.slots = 0});
  final int days;
  final int slots;

  @override
  bool operator ==(Object other) => other is KeyStep && other.days == days && other.slots == slots;

  @override
  int get hashCode => Object.hash(days, slots);

  @override
  String toString() => 'KeyStep($days d, $slots slots)';
}

/// What a key means.
sealed class KeyIntent {
  const KeyIntent();
}

/// Cursor: to the next day or slot ([extend]: Shift, the selection grows). Grab: the event moves.
final class MoveKeyIntent extends KeyIntent {
  const MoveKeyIntent(this.step, {this.extend = false});
  final KeyStep step;
  final bool extend;
}

/// A resource view, Alt+Left/Right (a timeline: Up/Down): to the next or
/// previous resource, the same day and time.
final class AcrossKeyIntent extends KeyIntent {
  const AcrossKeyIntent(this.delta);
  final int delta;
}

/// Grab: one edge moves (Shift: the end; Alt+Shift: the start).
final class ResizeKeyIntent extends KeyIntent {
  const ResizeKeyIntent(this.edge, this.step);
  final Edge edge;
  final KeyStep step;
}

/// Cursor: to the first or last place of its line (Home, End).
final class LineKeyIntent extends KeyIntent {
  const LineKeyIntent(this.edge, {this.extend = false});
  final Edge edge;
  final bool extend;
}

/// Cursor: the previous or next period (PageUp, PageDown).
final class PeriodKeyIntent extends KeyIntent {
  const PeriodKeyIntent({required this.next});
  final bool next;
}

/// Event: the previous or next event of the same day.
final class ItemKeyIntent extends KeyIntent {
  const ItemKeyIntent(this.delta);
  final int delta;
}

/// The other intents, which carry nothing.
enum KeyCommand {
  /// Cursor, Enter: into the day's events (a month), else as [activate].
  enter,

  /// Cursor, Space: the date click, or the selection made.
  activate,

  /// Event: Enter or Space.
  open,

  /// Event: M or Alt+Enter.
  grab,

  /// Grab: Enter or Space puts the event down.
  commit,

  /// Escape: lets go (grab), clears the selection (cursor), back to the day (event). Tab in grab mode too.
  cancel,

  /// Event: Delete or Backspace.
  delete,
  undo,
  redo,
}

final class CommandKeyIntent extends KeyIntent {
  const CommandKeyIntent(this.kind);
  final KeyCommand kind;

  @override
  bool operator ==(Object other) => other is CommandKeyIntent && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => kind.name;
}

KeyStep? _arrow(String key, KeyGrid grid, bool rtl) {
  final ahead = rtl ? -1 : 1;
  if (grid == KeyGrid.timeline) {
    return key == 'ArrowLeft'
        ? KeyStep(slots: -ahead)
        : key == 'ArrowRight'
        ? KeyStep(slots: ahead)
        : null;
  }
  return switch (key) {
    'ArrowLeft' => KeyStep(days: -ahead),
    'ArrowRight' => KeyStep(days: ahead),
    'ArrowUp' => grid == KeyGrid.time ? const KeyStep(slots: -1) : const KeyStep(days: -7),
    'ArrowDown' => grid == KeyGrid.time ? const KeyStep(slots: 1) : const KeyStep(days: 7),
    _ => null,
  };
}

/// What a key means where the keyboard is (ARCHITECTURE D.3). Null: not the
/// calendar's — the page keeps it. Pure, so the keymap is the same in every
/// renderer and port. [rtl]: right to left, the horizontal arrows swap.
KeyIntent? intentFor(KeyLike k, {required KeyMode mode, required KeyGrid grid, bool rtl = false}) {
  final mod = k.ctrl || k.meta;
  final key = k.key.length == 1 ? k.key.toLowerCase() : k.key;
  if (mode != KeyMode.grab && mod && !k.alt) {
    if (key == 'z') return CommandKeyIntent(k.shift ? KeyCommand.redo : KeyCommand.undo);
    if (key == 'y' && !k.shift) return const CommandKeyIntent(KeyCommand.redo);
    return null;
  }
  if (mod) return null;
  final step = _arrow(key, grid, rtl);
  KeyIntent? across() => step != null && step.days != 0 ? AcrossKeyIntent(step.days > 0 ? 1 : -1) : null;
  // A timeline: up and down are the resources (in grab mode too: the event goes to the next row).
  final vertical = key == 'ArrowUp'
      ? -1
      : key == 'ArrowDown'
      ? 1
      : 0;
  if (grid == KeyGrid.timeline && vertical != 0 && !k.alt && !k.shift && mode != KeyMode.event) {
    return AcrossKeyIntent(vertical);
  }
  switch (mode) {
    case KeyMode.grab:
      if (step != null) {
        if (k.shift) return ResizeKeyIntent(k.alt ? Edge.start : Edge.end, step);
        return k.alt ? across() : MoveKeyIntent(step);
      }
      if (key == 'PageUp' || key == 'PageDown') return MoveKeyIntent(KeyStep(days: key == 'PageUp' ? -7 : 7));
      if (key == 'Enter' || key == ' ') return const CommandKeyIntent(KeyCommand.commit);
      if (key == 'Escape' || key == 'Tab') return const CommandKeyIntent(KeyCommand.cancel);
      return null;
    case KeyMode.event:
      if (key == 'Enter' && k.alt) return const CommandKeyIntent(KeyCommand.grab);
      if (k.alt) return null;
      if (key == 'Enter' || key == ' ') return const CommandKeyIntent(KeyCommand.open);
      if (key == 'm' && !k.shift) return const CommandKeyIntent(KeyCommand.grab);
      if (key == 'Delete' || key == 'Backspace') return const CommandKeyIntent(KeyCommand.delete);
      if (key == 'Escape') return const CommandKeyIntent(KeyCommand.cancel);
      if (step != null) return ItemKeyIntent(step.days + step.slots > 0 ? 1 : -1);
      // A timeline's vertical arrows on an event: the previous or next one, as the horizontal ones.
      if (grid == KeyGrid.timeline && vertical != 0) return ItemKeyIntent(vertical);
      return null;
    case KeyMode.cursor:
      if (k.alt) return k.shift ? null : across();
      if (step != null) return MoveKeyIntent(step, extend: k.shift);
      if (key == 'Home' || key == 'End') return LineKeyIntent(key == 'Home' ? Edge.start : Edge.end, extend: k.shift);
      if (key == 'PageUp' || key == 'PageDown') return PeriodKeyIntent(next: key == 'PageDown');
      if (key == 'Enter') return const CommandKeyIntent(KeyCommand.enter);
      if (key == ' ') return const CommandKeyIntent(KeyCommand.activate);
      if (key == 'Escape') return const CommandKeyIntent(KeyCommand.cancel);
      return null;
  }
}

/// A hit moved by a step, as the keyboard moves the cursor or a held event.
/// Days keep the wall time (read again in the zone, the pass kept; a gap
/// moves on, flagged like a pointer in it). Slots step in elapsed time, so
/// every real slot is visited once: both passes of a repeated hour, none of
/// a skipped one. A slot hit keeps its column's date: the view keeps it
/// inside its hours.
Hit stepHit(ZoneId displayZone, int snapMinutes, Hit hit, KeyStep step) {
  switch (hit) {
    case DayHit():
      // A day hit takes slots as days: a timeline counted in days steps along them.
      final n = step.days + step.slots;
      return n == 0 ? hit : DayHit(date: hit.date.addDays(n), allDayRow: hit.allDayRow, resourceId: hit.resourceId);
    case SlotHit():
      var instant = hit.instant;
      var date = hit.date;
      var gap = false;
      if (step.days != 0) {
        final z = ZonedDateTime(instant, displayZone);
        final wall = z.plainDateTime;
        final target = wall.date.addDays(step.days);
        final r = resolveWall(target, wall.time, displayZone, WallPolicy.preferOffset(z.offset));
        gap = !r.exists;
        // In a skipped hour: the first moment after it (03:00), as a pointer in the gap gives — not the time pushed on.
        final back = gap ? resolveWall(target, wall.time, displayZone, WallPolicy.earlier).instant : null;
        final pushed = r.instant;
        final after = back != null && pushed != null
            ? transitionsBetween(back, pushed, displayZone).firstOrNull?.at
            : null;
        instant = after ?? pushed ?? instant;
        date = date.addDays(step.days);
      }
      if (step.slots != 0) {
        instant = instant.addMs(step.slots * (snapMinutes < 1 ? 1 : snapMinutes) * 60000);
        gap = false;
      }
      return SlotHit(date: date, instant: instant, resourceId: hit.resourceId, gap: gap);
  }
}

/// Where an event's edge stands, as a hit in this grid — what a pointer
/// pressed there would give: a timed event's moment in a time grid, its day
/// in a month, the all-day row for a day event in a time grid. The end of an
/// event is exclusive: its hit is the last day it covers, or the moment it
/// ends in the column of its last minute.
Hit eventHit(CalEvent ev, Edge edge, {required ZoneId displayZone, required KeyGrid grid}) {
  switch (ev) {
    case AllDayEvent(:final start, :final end):
      final date = edge == Edge.start ? start : end.addDays(-1);
      final last = date.isBefore(start) ? start : date;
      return DayHit(date: last, allDayRow: grid == KeyGrid.time);
    case TimedEvent(:final start, :final end):
      final at = edge == Edge.start ? start : end;
      // The column an end belongs to is the one of its last minute: an end at midnight closes the day before.
      final ms = edge == Edge.end && '$end' != '$start' ? at.epochMilliseconds - 1 : at.epochMilliseconds;
      final date = ZonedDateTime(at.instant.addMs(ms - at.epochMilliseconds), displayZone).date;
      return grid == KeyGrid.time ? SlotHit(date: date, instant: at.instant) : DayHit(date: date);
  }
}

/// The event as a proposal would leave it: what grab mode holds between two presses.
CalEvent heldEvent(Proposal p) => p.proposed;

/// One press in grab mode: the held event moved ([edge] null) or one edge
/// resized by [step], through the hits a pointer would give and the same
/// proposals — so a key sequence lands where the mouse would. [fit] is the
/// view's say on the stepped hit (`from` is where the edge was): kept inside
/// what it draws, or null — nowhere to go, nothing is proposed.
/// [resourceId]: in a resource view, the column the event is held in.
Proposal? grabStep(
  InteractionContext ctx,
  KeyGrid grid,
  CalEvent held,
  KeyStep step, {
  Edge? edge,
  Hit? Function(Hit to, Hit from)? fit,
  String? resourceId,
}) {
  final at = eventHit(held, edge ?? Edge.start, displayZone: ctx.displayZone, grid: grid);
  final from = resourceId == null
      ? at
      : switch (at) {
          SlotHit() => SlotHit(date: at.date, instant: at.instant, gap: at.gap, resourceId: resourceId),
          DayHit() => DayHit(date: at.date, allDayRow: at.allDayRow, resourceId: resourceId),
        };
  final stepped = stepHit(ctx.displayZone, ctx.snapMinutes, from, step);
  final to = fit == null ? stepped : fit(stepped, from);
  if (to == null) return null;
  return edge == null ? proposeMove(ctx, held, from, to) : proposeResize(ctx, held, edge, to);
}
