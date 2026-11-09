import '../project/time_axis.dart';
import '../views/daygrid.dart';
import '../views/timegrid.dart';
import '../zone/day_info.dart';
import 'actions.dart';
import 'propose.dart';

/// A point of a time grid as calendar terms: [column] (an index of the
/// model's columns) and [minutes] down its axis, as the widgets measure it —
/// as the web reads a pointer. In a skipped hour, the first moment after it,
/// flagged (`gap`: what lands there is announced); a repeated hour gives the
/// reading [prefer] asks for (the earlier by default). `slotStart`: the slot
/// the point is in on the [snapMinutes] grid of the axis (a press at 10:37
/// means the 10:30 slot), when that moment exists. Null for a folded column
/// (a day the zone skipped) or an index outside the model.
SlotHit? slotHitAt(TimeGridModel model, int column, double minutes, int snapMinutes, {AxisPrefer? prefer}) {
  if (column < 0 || column >= model.columns.length) return null;
  final col = model.columns[column];
  final axis = col.axis;
  if (col.folded || axis.length == 0) return null;
  final m = minutes.isNaN ? 0.0 : minutes.clamp(0.0, axis.length - 1e-6);
  final at = axis.fromPosition(m, prefer);
  final step = snapMinutes > 0 ? snapMinutes : 1;
  final slot = axis.fromPosition((m / step).floor() * step.toDouble(), prefer);
  if (at.exists) {
    return SlotHit(
      date: col.date,
      instant: at.instant,
      resourceId: col.resource?.id,
      slotStart: slot.exists ? slot.instant : null,
    );
  }
  // In a skipped hour: the first moment after it (03:00), flagged so the drop is announced.
  final band = axis.bands.where((x) => x.kind == TransitionKind.gap && m >= x.from && m < x.to).firstOrNull;
  return SlotHit(
    date: col.date,
    instant: band != null ? axis.fromPosition(band.to).instant : at.instant,
    gap: true,
    resourceId: col.resource?.id,
  );
}

/// The same point as a context menu's target: the reading and the other one
/// of a repeated wall time, so a menu can offer both.
SlotTarget? slotTargetAt(TimeGridModel model, int column, double minutes, {AxisPrefer? prefer}) {
  if (column < 0 || column >= model.columns.length) return null;
  final col = model.columns[column];
  if (col.folded) return null;
  final p = minutes.isNaN ? 0.0 : minutes.clamp(0.0, col.axis.length);
  final at = col.axis.fromPosition(p, prefer);
  return SlotTarget(
    date: col.date,
    instant: at.instant,
    exists: at.exists,
    ambiguous: at.ambiguous,
    alternative: at.alternative,
    resourceId: col.resource?.id,
  );
}

/// A cell of a time grid's all-day row: [column] counts every resource's
/// days (as the model's columns do).
DayHit? allDayHitAt(TimeGridModel model, int column) {
  if (column < 0 || column >= model.columns.length) return null;
  final col = model.columns[column];
  return DayHit(date: col.date, allDayRow: true, resourceId: col.resource?.id);
}

/// A cell of a day grid: row [week], cell [cell] (in a resource view, every
/// resource's days side by side). Null outside the model.
DayHit? dayHitAt(DayGridModel model, int week, int cell) {
  if (week < 0 || week >= model.weeks.length) return null;
  final w = model.weeks[week];
  if (cell < 0 || cell >= w.dates.length) return null;
  return DayHit(date: w.dates[cell], resourceId: w.resources[cell]?.id);
}
