import '../time/civil.dart';
import '../time/instant.dart';
import '../time/plain.dart';
import '../zone/day_info.dart';
import '../zone/zone_rules.dart';
import '../zone/zoned.dart';

/// How a day column's vertical axis counts.
enum AxisMode {
  /// Positions are clock minutes since midnight, shared by every column so
  /// rows line up. A skipped hour is a band nobody can land in; a repeated
  /// hour is a band where two readings share positions.
  wall,

  /// Positions are real minutes since the column's first instant. A 25-hour
  /// Sunday is 25 hours tall; durations are always true.
  elapsed,
}

final class AxisTick {
  const AxisTick({
    required this.position,
    required this.label,
    required this.instant,
    required this.major,
    this.pass,
    this.skipped = false,
  });

  /// Axis minutes from the top.
  final double position;
  final PlainTime label;

  /// Null where the wall time does not exist. On the wall axis, a repeated
  /// time gives its first reading.
  final Instant? instant;

  /// On a repeated time, which reading this tick marks; null when it happens once.
  final WallPass? pass;

  /// A wall time the clocks skip (its tick marks where the jump is).
  final bool skipped;
  final bool major;
}

final class AxisBand {
  const AxisBand(this.kind, this.from, this.to, this.transition);
  final TransitionKind kind;
  final double from;
  final double to;
  final Transition transition;
}

final class FromPosition {
  const FromPosition({required this.instant, required this.exists, required this.ambiguous, this.alternative});
  final Instant instant;
  final bool exists;
  final bool ambiguous;

  /// The other reading of a repeated wall time.
  final Instant? alternative;
}

/// Which reading [ColumnAxis.fromPosition] gives in a gap or a repeat: the
/// earlier, the later, or the one with an offset. Default: `compatible`.
sealed class AxisPrefer {
  const AxisPrefer();
  static const earlier = _PreferPolicy(WallPolicy.earlier);
  static const later = _PreferPolicy(WallPolicy.later);
  const factory AxisPrefer.offset(String offset) = _PreferOffset;
  WallPolicy get _policy;
}

final class _PreferPolicy extends AxisPrefer {
  const _PreferPolicy(this._policy);
  @override
  final WallPolicy _policy;
}

final class _PreferOffset extends AxisPrefer {
  const _PreferOffset(this.offset);
  final String offset;
  @override
  WallPolicy get _policy => WallPolicy.preferOffset(offset);
}

/// The vertical axis of one day column in a time grid.
sealed class ColumnAxis {
  ColumnAxis._(this.mode, this.day, this.length, this.start, this.end, this.bands);

  final AxisMode mode;
  final DayInfo day;

  /// In axis minutes; 0 for a day the zone skipped.
  final double length;

  /// The stretch of time the axis shows, `[start, end)`.
  final Instant start;
  final Instant end;
  final List<AxisBand> bands;

  /// Clamped to `[0, length]`.
  double toPosition(Instant i);

  /// Where something that *ends* at [i] stops. Differs from [toPosition] only
  /// at a fall-back (an event ending at the change ends at 03:00 of the first
  /// pass, not 02:00 of the second) and at midnight (24:00, not 00:00).
  double toEndPosition(Instant i);

  /// The instant at a position. In a gap the time moves forward (or back,
  /// [AxisPrefer.earlier]); in a repeat, the first reading unless told.
  FromPosition fromPosition(double p, [AxisPrefer? prefer]);

  /// A tick every [stepMinutes]; `major` (labelled) every [labelMinutes] of
  /// the clock (default 60: whole hours). Throws for a step that is not a
  /// positive number: it would never end.
  List<AxisTick> ticks(double stepMinutes, [int labelMinutes = 60]);
}

/// Throws [ArgumentError] for slots that are not `0 ≤ slotMin < slotMax ≤ 24 h`,
/// or an unknown zone: configuration, not data.
ColumnAxis buildColumnAxis(
  PlainDate date,
  ZoneId zone, {
  AxisMode mode = AxisMode.wall,
  Duration slotMin = Duration.zero,
  Duration slotMax = const Duration(hours: 24),
}) {
  final minM = slotMin.inMilliseconds / msPerMinute;
  final maxM = slotMax.inMilliseconds / msPerMinute;
  if (!(minM >= 0 && maxM <= 1440 && minM < maxM)) {
    throw ArgumentError('slotMin/slotMax must satisfy 0 ≤ slotMin < slotMax ≤ 24h (got $minM–$maxM minutes)');
  }
  final day = dayInfo(date, zone);
  if (day.lengthMinutes == 0) return _SkippedAxis(mode, day);

  final ctx = _Ctx(date, zone, minM, maxM);
  final axisStart = minM == 0 ? day.start : ctx.resolveAt(minM, WallPolicy.compatible).instant;
  final axisEnd = maxM == 1440 ? day.end : ctx.resolveAt(maxM, WallPolicy.compatible).instant;
  return mode == AxisMode.wall ? _WallAxis(ctx, day, axisStart, axisEnd) : _ElapsedAxis(ctx, day, axisStart, axisEnd);
}

final class _Ctx {
  _Ctx(this.date, this.zone, this.minM, this.maxM);
  final PlainDate date;
  final ZoneId zone;
  final double minM;
  final double maxM;

  int get midnightWall => date.epochDay * msPerDay;

  /// Clock milliseconds from this date's midnight to [wall], across midnight if needed.
  int wallMsOf(PlainDateTime wall) => wall.wallMs - midnightWall;

  PlainDateTime wallAt(double minutes) => PlainDateTime.fromWallMs(midnightWall + (minutes * msPerMinute).round());

  FromPosition resolveAt(double wallMin, WallPolicy policy) {
    final wall = wallAt(wallMin);
    final r = resolveWall(wall.date, wall.time, zone, policy);
    return FromPosition(instant: r.instant!, exists: r.exists, ambiguous: r.ambiguous, alternative: r.other);
  }
}

/// Labelled: its clock minutes a multiple of [every] (a bad one reads as whole hours).
bool _labelled(PlainDateTime wall, int every) {
  final n = every > 0 ? every : 60;
  return (wall.time.hour * 60 + wall.time.minute) % n == 0 && wall.time.second == 0;
}

void _assertStep(double step) {
  if (!(step > 0) || !step.isFinite) {
    throw ArgumentError('tick step must be a positive number of minutes (got $step)');
  }
}

double _clamp(double p, double length) => p < 0 ? 0 : (p > length ? length : p);

/// Apia, 30 December 2011: nothing to place, nothing to draw but a folded column.
final class _SkippedAxis extends ColumnAxis {
  _SkippedAxis(AxisMode mode, DayInfo day) : super._(mode, day, 0, day.start, day.end, const []);

  @override
  double toPosition(Instant i) => 0;
  @override
  double toEndPosition(Instant i) => 0;
  @override
  FromPosition fromPosition(double p, [AxisPrefer? prefer]) =>
      FromPosition(instant: day.start, exists: false, ambiguous: false);
  @override
  List<AxisTick> ticks(double stepMinutes, [int labelMinutes = 60]) => const [];
}

final class _WallAxis extends ColumnAxis {
  _WallAxis(this._c, DayInfo day, Instant start, Instant end)
    : super._(AxisMode.wall, day, _c.maxM - _c.minM, start, end, _bands(_c, day));

  final _Ctx _c;

  static List<AxisBand> _bands(_Ctx c, DayInfo day) {
    final length = c.maxM - c.minM;
    return [
      for (final t in day.transitions)
        if (_band(c, t, length) case final b?) b,
    ];
  }

  static AxisBand? _band(_Ctx c, Transition t, double length) {
    final a = _clamp(c.wallMsOf(t.wallBefore) / msPerMinute - c.minM, length);
    final b = _clamp(c.wallMsOf(t.wallAfter) / msPerMinute - c.minM, length);
    final (from, to) = a < b ? (a, b) : (b, a);
    return to > from ? AxisBand(t.kind, from, to, t) : null;
  }

  // A day without a clock change keeps one offset from midnight to midnight:
  // a position is a subtraction.
  bool get _quiet => day.transitions.isEmpty;
  double _fast(Instant i) =>
      _clamp((i.epochMilliseconds - day.start.epochMilliseconds) / msPerMinute - _c.minM, length);

  @override
  double toPosition(Instant i) {
    if (_quiet) return _fast(i);
    return _clamp(_c.wallMsOf(i.inZone(_c.zone).plainDateTime) / msPerMinute - _c.minM, length);
  }

  @override
  double toEndPosition(Instant i) {
    if (_quiet) return _fast(i);
    // Read one millisecond earlier, then step that millisecond back.
    final before = i.addMs(-1).inZone(_c.zone).plainDateTime;
    return _clamp((_c.wallMsOf(before) + 1) / msPerMinute - _c.minM, length);
  }

  @override
  FromPosition fromPosition(double p, [AxisPrefer? prefer]) =>
      _c.resolveAt(_c.minM + p, prefer?._policy ?? WallPolicy.compatible);

  @override
  List<AxisTick> ticks(double step, [int every = 60]) {
    _assertStep(step);
    final out = <AxisTick>[];
    // On the clock's multiples of `step`: a grid from 08:30 still labels 09:00.
    final first = (step - (_c.minM % step)) % step;
    for (var p = first; p <= length + 1e-9; p += step) {
      final wall = _c.wallAt(_c.minM + p);
      final r = resolveWall(wall.date, wall.time, _c.zone, WallPolicy.earlier);
      out.add(
        AxisTick(
          position: p,
          label: wall.time,
          instant: r.exists ? r.instant : null,
          skipped: !r.exists,
          pass: r.exists && r.ambiguous ? WallPass.first : null,
          major: _labelled(wall, every),
        ),
      );
    }
    return out;
  }
}

final class _ElapsedAxis extends ColumnAxis {
  _ElapsedAxis(this._c, DayInfo day, Instant start, Instant end)
    : super._(
        AxisMode.elapsed,
        day,
        (end.epochMilliseconds - start.epochMilliseconds) / msPerMinute,
        start,
        end,
        _bands(day, start, (end.epochMilliseconds - start.epochMilliseconds) / msPerMinute),
      );

  final _Ctx _c;

  static double _rawFrom(Instant origin, Instant i) => (i.epochMilliseconds - origin.epochMilliseconds) / msPerMinute;

  static List<AxisBand> _bands(DayInfo day, Instant origin, double length) {
    final out = <AxisBand>[];
    for (final t in day.transitions) {
      if (t.kind != TransitionKind.repeat) continue;
      // The second pass: from the change to where the first pass reached.
      // Clamped only once both ends are known, or a pass entirely before
      // slotMin would come back as a phantom band at the top.
      final from = _clamp(_rawFrom(origin, t.at), length);
      final to = _clamp(_rawFrom(origin, t.at) - t.deltaMinutes, length);
      if (to > from) out.add(AxisBand(TransitionKind.repeat, from, to, t));
    }
    return out;
  }

  double _raw(Instant i) => _rawFrom(start, i);

  @override
  double toPosition(Instant i) => _clamp(_raw(i), length);

  @override
  double toEndPosition(Instant i) => toPosition(i);

  @override
  FromPosition fromPosition(double p, [AxisPrefer? prefer]) {
    final instant = start.addMs((_clamp(p, length) * msPerMinute).round());
    final wall = instant.inZone(_c.zone).plainDateTime;
    final r = resolveWall(wall.date, wall.time, _c.zone, WallPolicy.earlier);
    final alternative = r.ambiguous ? (r.instant == instant ? r.other : r.instant) : null;
    return FromPosition(instant: instant, exists: true, ambiguous: r.ambiguous, alternative: alternative);
  }

  @override
  List<AxisTick> ticks(double step, [int every = 60]) {
    _assertStep(step);
    // Walk the wall clock, not elapsed minutes: every wall multiple of `step`
    // that happens gets a tick, twice when it happens twice. On Lord Howe's
    // 23 h 30 day the hours after the jump still fall on :00.
    final out = <AxisTick>[];
    for (var w = (_c.minM / step).ceil() * step; w <= _c.maxM + 1e-9; w += step) {
      final wall = _c.wallAt(w);
      final r = resolveWall(wall.date, wall.time, _c.zone, WallPolicy.earlier);
      final first = r.instant;
      if (!r.exists || first == null) continue;
      final other = r.other;
      final readings = r.ambiguous && other != null
          ? [(first, WallPass.first), (other, WallPass.second)]
          : [(first, null)];
      for (final (instant, pass) in readings) {
        final p = _raw(instant);
        if (p < -1e-9 || p > length + 1e-9) continue;
        out.add(AxisTick(position: p, label: wall.time, instant: instant, pass: pass, major: _labelled(wall, every)));
      }
    }
    return out..sort((a, b) => a.position.compareTo(b.position));
  }
}
