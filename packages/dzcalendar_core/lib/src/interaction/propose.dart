import '../commands/types.dart';
import '../event/types.dart';
import '../resource/tree.dart' show unassignedId;
import '../rules/validate.dart';
import '../store/instance.dart';
import '../store/store.dart';
import '../time/duration.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../util/js.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';

/// What is under the pointer (or the keyboard cursor), in calendar terms.
/// The view turns a point into a [Hit]; everything after is pure, so the
/// mouse, a finger, a pen and the keyboard propose exactly the same thing.
sealed class Hit {
  const Hit();
  PlainDate get date;
  ResourceId? get resourceId;
}

/// A moment in a time-grid column (the axis already read the position,
/// repeated hour included).
final class SlotHit extends Hit {
  const SlotHit({required this.date, required this.instant, this.gap = false, this.resourceId, this.slotStart});
  @override
  final PlainDate date;
  final Instant instant;

  /// The pointer is in a skipped hour: [instant] is the first moment after
  /// it, and what lands there is announced.
  final bool gap;
  @override
  final ResourceId? resourceId;

  /// The start of the slot the point is in (on `snapMinutes`): what a click says.
  final Instant? slotStart;
}

/// A whole day: a month cell, or the all-day row of a time grid ([allDayRow]).
final class DayHit extends Hit {
  const DayHit({required this.date, this.allDayRow = false, this.resourceId});
  @override
  final PlainDate date;
  final bool allDayRow;
  @override
  final ResourceId? resourceId;
}

final class InteractionContext {
  const InteractionContext({
    required this.snap,
    required this.displayZone,
    required this.snapMinutes,
    this.rules,
    this.defaultTimedDuration,
    this.movingSeries,
    this.keepAllDay = false,
    this.external = false,
  });

  final StoreSnapshot snap;
  final ZoneId displayZone;

  /// Minutes moves and resizes snap to, on the wall clock of the calendar.
  final int snapMinutes;

  /// When given, each proposal says whether it may go (and why not).
  final RulesContext? rules;

  /// The length a day event gets when dropped into a time grid. Default one hour.
  final IsoDuration? defaultTimedDuration;

  /// A series moving as a whole does not collide with itself.
  final String? movingSeries;

  /// The view has no all-day row (a timeline): an all-day event dropped on
  /// a moment stays all-day and moves by whole days.
  final bool keepAllDay;

  /// What is proposed comes from outside this calendar: said to the rules' `allow`.
  final bool external;
}

/// A wall time that happens twice: the reading chosen (the pass under the
/// pointer) and the other one, for the widgets to offer.
final class Ambiguity {
  const Ambiguity({required this.chosen, required this.alternative, required this.edge});
  final Instant chosen;
  final Instant alternative;
  final Edge edge;
}

/// Where an event would go, and whether it may. The same for every input device.
final class Proposal {
  const Proposal({required this.placement, required this.violations, this.ambiguity, this.skipped = false});

  final Placement placement;
  final List<Violation> violations;
  final Ambiguity? ambiguity;

  /// The wall time does not exist (a spring-forward gap): moved to the next
  /// moment that does, to be announced.
  final bool skipped;

  CalEvent get event => placement.event;

  /// The event as it would be.
  CalEvent get proposed => placement.proposed;
  bool get allDay => proposed.allDay;
  bool get valid => violations.isEmpty;
  List<ResourceId> get resourceIds => proposed.resourceIds;
}

final _defaultTimed = IsoDuration(hours: 1);

/// A moment snapped to the calendar's wall clock, read again in the zone.
({Instant instant, Ambiguity? ambiguity, bool skipped}) _snapped(
  Instant i,
  InteractionContext ctx, [
  Edge edge = Edge.start,
]) {
  final z = ZonedDateTime(i, ctx.displayZone);
  final step = ctx.snapMinutes < 1 ? 1 : ctx.snapMinutes;
  final t = z.time;
  final minutes = jsRound((t.hour * 60 + t.minute + t.second / 60) / step) * step;
  final date = minutes >= 1440 ? z.date.addDays(1) : z.date;
  final m = minutes % 1440;
  // The pass the pointer is in decides which of two readings: the offset it shows.
  final r = resolveWall(date, PlainTime(m ~/ 60, m % 60), ctx.displayZone, WallPolicy.preferOffset(z.offset));
  final instant = r.instant ?? i;
  final other = r.other;
  return (
    instant: instant,
    skipped: !r.exists,
    ambiguity: r.ambiguous && other != null ? Ambiguity(chosen: instant, alternative: other, edge: edge) : null,
  );
}

int _elapsedMs(CalEvent e) => switch (e) {
  TimedEvent(:final start, :final end) => end.epochMilliseconds - start.epochMilliseconds,
  AllDayEvent() => 0,
};

Proposal _finish(InteractionContext ctx, CalEvent ev, CalEvent proposed, {Ambiguity? ambiguity, bool skipped = false}) {
  final p = Placement(event: ev, proposed: proposed, external: ctx.external);
  final rules = ctx.rules;
  final violations = rules == null
      ? const <Violation>[]
      : validateProposal(ctx.snap, p, rules, movingSeries: ctx.movingSeries);
  return Proposal(placement: p, violations: violations, ambiguity: ambiguity, skipped: skipped);
}

/// The resources after a move: the one grabbed on is swapped for the one
/// under the pointer, the others kept (an event on two doctors, dragged from
/// one to a third, stays on the other). Grabbed outside a resource column,
/// it goes onto the one it is dropped on.
List<ResourceId> _resourcesFor(CalEvent ev, Hit grab, Hit over) {
  final to = over.resourceId;
  if (to == null || to == grab.resourceId) return ev.resourceIds;
  final from = grab.resourceId;
  // Onto "Unassigned": the resource it was taken from goes (the others stay). Out of it: onto the one it is dropped on.
  if (to == unassignedId) {
    return from == null
        ? const []
        : [
            for (final r in ev.resourceIds)
              if (r != from) r,
          ];
  }
  if (from == unassignedId) return [to];
  if (from == null || !ev.resourceIds.contains(from)) return [to];
  final out = <ResourceId>[];
  for (final r in ev.resourceIds) {
    final x = r == from ? to : r;
    if (!out.contains(x)) out.add(x);
  }
  return out;
}

/// Where [ev] goes when the point that grabbed it ([grab]) is over [over].
/// A timed event keeps its elapsed length and its zone; its new start is the
/// grabbed offset applied, snapped on the wall clock and read again in the
/// zone (a gap moves it forward, flagged; a repeat keeps the pass under the
/// pointer, flagged with the other). A day event moves by whole days.
/// Dropped on the all-day row, a timed event becomes a day; dropped in a
/// time grid, a day event becomes timed.
Proposal proposeMove(InteractionContext ctx, CalEvent ev, Hit grab, Hit over) {
  if (ev.allDay && ctx.keepAllDay && over is SlotHit) {
    // No all-day row to drop it on: the day under the pointer, as in a month.
    Hit day(Hit h) => h is SlotHit ? DayHit(date: h.date, resourceId: h.resourceId) : h;
    return proposeMove(ctx, ev, day(grab), day(over));
  }
  final resourceIds = _resourcesFor(ev, grab, over);
  switch (over) {
    case SlotHit(:final instant, :final gap):
      switch (ev) {
        case AllDayEvent():
          // A day event into the time grid: timed, at the snapped moment, default length.
          final s = _snapped(instant, ctx);
          final start = ZonedDateTime(s.instant, ctx.displayZone);
          final end = start.add(ctx.defaultTimedDuration ?? _defaultTimed);
          return _finish(
            ctx,
            ev,
            ev.movedToTime(start, end, resourceIds: resourceIds),
            ambiguity: s.ambiguity,
            skipped: s.skipped || gap,
          );
        case TimedEvent(start: final zs, end: final ze):
          final offset = grab is SlotHit ? grab.instant.epochMilliseconds - zs.epochMilliseconds : 0;
          final s = _snapped(instant.addMs(-offset), ctx);
          final start = ZonedDateTime(s.instant, zs.zone);
          final end = ZonedDateTime(start.instant.addMs(_elapsedMs(ev)), ze.zone);
          // Skipped: the snapped wall start did not exist, or the pointer itself was in the skipped hour.
          return _finish(
            ctx,
            ev,
            ev.movedToTime(start, end, resourceIds: resourceIds),
            ambiguity: s.ambiguity,
            skipped: s.skipped || gap,
          );
      }
    case DayHit(date: final overDate, :final allDayRow):
      final days = grab.date.daysUntil(overDate);
      switch (ev) {
        case AllDayEvent(:final start, :final end):
          return _finish(ctx, ev, ev.movedToDays(start.addDays(days), end.addDays(days), resourceIds: resourceIds));
        case TimedEvent(start: final zs, end: final ze):
          if (allDayRow) {
            // A timed event onto the all-day row: the day it lands on.
            return _finish(ctx, ev, ev.movedToDays(overDate, overDate.addDays(1), resourceIds: resourceIds));
          }
          // A timed event moved between month cells: the same wall time, so many days later, in its own zone.
          final wall = zs.plainDateTime;
          final r = resolveWall(wall.date.addDays(days), wall.time, zs.zone, WallPolicy.preferOffset(zs.offset));
          final start = ZonedDateTime(r.instant ?? zs.instant, zs.zone);
          final end = ZonedDateTime(start.instant.addMs(_elapsedMs(ev)), ze.zone);
          final chosen = r.instant;
          final other = r.other;
          return _finish(
            ctx,
            ev,
            ev.movedToTime(start, end, resourceIds: resourceIds),
            skipped: !r.exists,
            ambiguity: r.ambiguous && other != null && chosen != null
                ? Ambiguity(chosen: chosen, alternative: other, edge: Edge.start)
                : null,
          );
      }
  }
}

/// One [edge] of [ev] to the point [over]. The other edge stays; an event is
/// never shorter than one snap step (a day for a day event). A timed event's
/// edge snaps on the wall clock like a move.
Proposal proposeResize(InteractionContext ctx, CalEvent ev, Edge edge, Hit over) {
  switch (ev) {
    case AllDayEvent(start: final s, end: final e):
      final date = over.date;
      if (edge == Edge.end) {
        // The cell under the pointer is the last day: the end is the day after.
        var end = date.addDays(1);
        if (!end.isAfter(s)) end = s.addDays(1);
        return _finish(ctx, ev, ev.movedToDays(s, end));
      }
      var start = date;
      if (!start.isBefore(e)) start = e.addDays(-1);
      return _finish(ctx, ev, ev.movedToDays(start, e));
    case TimedEvent(start: final zs, end: final ze):
      if (over is! SlotHit) return _finish(ctx, ev, ev);
      final s = _snapped(over.instant, ctx, edge);
      final gap = s.skipped || over.gap;
      final minMs = (ctx.snapMinutes < 1 ? 1 : ctx.snapMinutes) * 60000;
      if (edge == Edge.end) {
        final end = ZonedDateTime(s.instant, ze.zone);
        // Clamped to the shortest length: the edge is no longer the snapped moment, nor its flags.
        if (end.epochMilliseconds - zs.epochMilliseconds < minMs) {
          return _finish(ctx, ev, ev.movedToTime(zs, ZonedDateTime(zs.instant.addMs(minMs), ze.zone)));
        }
        return _finish(ctx, ev, ev.movedToTime(zs, end), skipped: gap, ambiguity: s.ambiguity);
      }
      final start = ZonedDateTime(s.instant, zs.zone);
      if (ze.epochMilliseconds - start.epochMilliseconds < minMs) {
        return _finish(ctx, ev, ev.movedToTime(ZonedDateTime(ze.instant.addMs(-minMs), zs.zone), ze));
      }
      return _finish(ctx, ev, ev.movedToTime(start, ze), skipped: gap, ambiguity: s.ambiguity);
  }
}

String _momentText(CalEvent e, bool start) => switch (e) {
  TimedEvent() => '${start ? e.start : e.end}',
  AllDayEvent() => '${start ? e.start : e.end}',
};

bool _sameIds(List<String> a, List<String> b) =>
    a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);

/// True when a proposal puts the event where it already is.
bool isUnchanged(Proposal p) {
  final ev = p.event;
  final to = p.proposed;
  return ev.allDay == to.allDay &&
      _momentText(ev, true) == _momentText(to, true) &&
      _momentText(ev, false) == _momentText(to, false) &&
      _sameIds(ev.resourceIds, to.resourceIds);
}

/// A selection of time, as a person dragged it: days, or moments snapped on
/// the wall clock.
sealed class CalendarSelection {
  const CalendarSelection({this.resourceId});
  final ResourceId? resourceId;
  bool get allDay;
}

final class DaySelection extends CalendarSelection {
  const DaySelection({required this.start, required this.end, super.resourceId});
  final PlainDate start;

  /// Exclusive.
  final PlainDate end;
  @override
  bool get allDay => true;
}

final class TimeSelection extends CalendarSelection {
  const TimeSelection({required this.start, required this.end, super.resourceId, this.skipped = false});
  final ZonedDateTime start;
  final ZonedDateTime end;

  /// A moment of it fell in a gap and was moved on.
  final bool skipped;
  @override
  bool get allDay => false;
}

/// The stretch between two hits, in either order: whole days over days,
/// snapped moments over slots.
CalendarSelection selectionBetween(InteractionContext ctx, Hit a, Hit b) {
  // "Unassigned" is the view's, not a resource: a selection there is on none.
  final resource = a.resourceId != null && a.resourceId != unassignedId ? a.resourceId : null;
  if (a is! SlotHit || b is! SlotHit) {
    final (d1, d2) = a.date.isAfter(b.date) ? (b.date, a.date) : (a.date, b.date);
    return DaySelection(start: d1, end: d2.addDays(1), resourceId: resource);
  }
  final (x, y) = a.instant.isAfter(b.instant) ? (b.instant, a.instant) : (a.instant, b.instant);
  final step = ctx.snapMinutes < 1 ? 1 : ctx.snapMinutes;
  // Slots are wall-clock slots: from the start of the first to the end of the last, read in the pass under the pointer.
  ({Instant instant, bool skipped}) wallSlot(Instant i, int plus) {
    final z = ZonedDateTime(i, ctx.displayZone);
    final m = ((z.time.hour * 60 + z.time.minute) / step).floor() * step + plus;
    final date = m >= 1440 ? z.date.addDays(1) : z.date;
    final mm = m % 1440;
    final r = resolveWall(date, PlainTime(mm ~/ 60, mm % 60), ctx.displayZone, WallPolicy.preferOffset(z.offset));
    return (instant: r.instant ?? i, skipped: !r.exists);
  }

  final s = wallSlot(x, 0);
  final e = wallSlot(y, 0);
  var end = wallSlot(y, step).instant;
  // Never ending at or before the pointer (a repeated or skipped half hour can fold the wall slot onto itself).
  if (!end.isAfter(y)) end = y.addMs(step * 60000);
  // And the pointer is inside: a start read in the other pass comes back to the slot's real start.
  final startI = s.instant.isAfter(x) ? x : s.instant;
  return TimeSelection(
    start: ZonedDateTime(startI, ctx.displayZone),
    end: ZonedDateTime(end, ctx.displayZone),
    resourceId: resource,
    skipped: s.skipped || e.skipped,
  );
}

/// The command that carries a proposal out. An occurrence is addressed
/// through its series ([scope] says how far — the widgets ask). A change
/// between timed and all-day is an update; the rest is a move.
Command commandFor(EventInstance instance, Proposal p, [EditScope scope = EditScope.this_]) {
  final ev = instance.event;
  final ref = ev.ref;
  final id = ref?.seriesId ?? ev.id;
  final key = ref?.key;
  final reachScope = ref != null ? scope : null;
  final to = p.proposed;
  final resources = _sameIds(to.resourceIds, ev.resourceIds) ? null : to.resourceIds;
  final Object start = switch (to) {
    TimedEvent(:final start) => start,
    AllDayEvent(:final start) => start,
  };
  final Object end = switch (to) {
    TimedEvent(:final end) => end,
    AllDayEvent(:final end) => end,
  };
  if (to.allDay != ev.allDay) {
    return UpdateEvent(
      id,
      EventPatch(allDay: to.allDay, start: start, end: end, resourceIds: resources),
      scope: reachScope,
      key: key,
    );
  }
  return MoveEvent(id, start, end: end, resourceIds: resources, scope: reachScope, key: key);
}
