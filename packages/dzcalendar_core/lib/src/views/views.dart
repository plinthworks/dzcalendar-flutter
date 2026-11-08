import '../time/duration.dart';
import '../time/plain.dart';

/// What a view's period is aligned on.
enum ViewAlignment { month, week, day, year, none }

/// A fixed period (a congress, 3 to 12 November: [end] exclusive, the 13th):
/// shown whatever the date; navigation does not move it.
final class VisibleRange {
  const VisibleRange(this.start, this.end);
  final PlainDate start;
  final PlainDate end;
}

/// What a view shows, as data: a family (how it is drawn) and a stretch of
/// time (how long, aligned on what). A custom view is a new spec, not a subclass.
final class ViewSpec {
  const ViewSpec({
    required this.type,
    required this.family,
    required this.duration,
    required this.alignment,
    this.dayCount,
    this.fixedWeekCount = true,
    this.hiddenDays = const [],
    this.dateIncrement,
    this.showNonCurrentDates = true,
    this.resources = false,
    this.visibleRange,
  });

  final String type;

  /// `dayGrid`, `timeGrid`, `list`, `multiMonth`, `timeline`, `custom`, or a
  /// family an application registers.
  final String family;

  /// Days, weeks, months or years.
  final IsoDuration duration;
  final ViewAlignment alignment;

  /// Count shown days rather than calendar days: four days skipping hidden weekends.
  final int? dayCount;

  /// Month grids: always six weeks (true), or only the weeks the month touches.
  final bool fixedWeekCount;

  /// ISO weekdays, 1 (Monday) to 7 (Sunday).
  final List<int> hiddenDays;

  /// How far prev/next move. Default: [duration].
  final IsoDuration? dateIncrement;
  final bool showNonCurrentDates;

  /// One column per resource and date (timeGrid, dayGrid).
  final bool resources;
  final VisibleRange? visibleRange;

  ViewSpec copyWith({
    String? type,
    String? family,
    IsoDuration? duration,
    ViewAlignment? alignment,
    int? dayCount,
    bool? fixedWeekCount,
    List<int>? hiddenDays,
    IsoDuration? dateIncrement,
    bool? showNonCurrentDates,
    bool? resources,
    VisibleRange? visibleRange,
  }) => ViewSpec(
    type: type ?? this.type,
    family: family ?? this.family,
    duration: duration ?? this.duration,
    alignment: alignment ?? this.alignment,
    dayCount: dayCount ?? this.dayCount,
    fixedWeekCount: fixedWeekCount ?? this.fixedWeekCount,
    hiddenDays: hiddenDays == null ? this.hiddenDays : List.unmodifiable(hiddenDays),
    dateIncrement: dateIncrement ?? this.dateIncrement,
    showNonCurrentDates: showNonCurrentDates ?? this.showNonCurrentDates,
    resources: resources ?? this.resources,
    visibleRange: visibleRange ?? this.visibleRange,
  );

  bool shows(PlainDate d) => !hiddenDays.contains(d.dayOfWeek);
}

/// The dates a view covers. [start]/[end] include padding days; `active*` is
/// the period itself. Ends are exclusive.
final class ViewRange {
  const ViewRange({
    required this.start,
    required this.end,
    required this.activeStart,
    required this.activeEnd,
    required this.dates,
    required this.weeks,
    this.months,
  });

  final PlainDate start;
  final PlainDate end;
  final PlainDate activeStart;
  final PlainDate activeEnd;

  /// Shown dates in order, hidden days removed.
  final List<PlainDate> dates;

  /// [dates] in rows of one week each (a month grid), or a single row.
  final List<List<PlainDate>> weeks;

  /// A multi-month view: each month's own grid, in order.
  final List<ViewRange>? months;
}

final class NavContext {
  const NavContext({required this.firstDay, required this.today});

  /// ISO weekday the week starts on: 1 (Monday) to 7 (Sunday).
  final int firstDay;
  final PlainDate today;
}

ViewSpec _view(String type, String family, IsoDuration duration, ViewAlignment alignment, {bool resources = false}) =>
    ViewSpec(type: type, family: family, duration: duration, alignment: alignment, resources: resources);

final _month = IsoDuration(months: 1);
final _week = IsoDuration(weeks: 1);
final _day = IsoDuration(days: 1);
final _year = IsoDuration(years: 1);

/// The views every calendar knows. A custom view is a spec added beside these.
final Map<String, ViewSpec> builtinViews = Map.unmodifiable({
  for (final v in [
    _view('dayGridMonth', 'dayGrid', _month, ViewAlignment.month),
    _view('dayGridWeek', 'dayGrid', _week, ViewAlignment.week),
    _view('dayGridDay', 'dayGrid', _day, ViewAlignment.day),
    _view('timeGridWeek', 'timeGrid', _week, ViewAlignment.week),
    _view('timeGridDay', 'timeGrid', _day, ViewAlignment.day),
    _view('listDay', 'list', _day, ViewAlignment.day),
    _view('listWeek', 'list', _week, ViewAlignment.week),
    _view('listMonth', 'list', _month, ViewAlignment.month),
    _view('listYear', 'list', _year, ViewAlignment.year),
    _view('multiMonthYear', 'multiMonth', _year, ViewAlignment.year),
    _view('resourceTimeGridDay', 'timeGrid', _day, ViewAlignment.day, resources: true),
    _view('resourceTimeGridWeek', 'timeGrid', _week, ViewAlignment.week, resources: true),
    _view('resourceDayGridDay', 'dayGrid', _day, ViewAlignment.day, resources: true),
    _view('resourceDayGridWeek', 'dayGrid', _week, ViewAlignment.week, resources: true),
    _view('resourceDayGridMonth', 'dayGrid', _month, ViewAlignment.month, resources: true),
  ])
    v.type: v,
});

PlainDate _startOfWeek(PlainDate d, int firstDay) => d.addDays(-((d.dayOfWeek - firstDay + 7) % 7));

List<PlainDate> _datesBetween(PlainDate start, PlainDate end, ViewSpec spec) => [
  for (var d = start; d.isBefore(end); d = d.addDays(1))
    if (spec.shows(d)) d,
];

/// A view's settings, checked before any range is made — when the calendar
/// is made, for every view. Throws [ArgumentError] naming what is wrong.
void assertViewSpec(ViewSpec spec) {
  void positive(IsoDuration d, String what) {
    if (d.sign <= 0) throw ArgumentError('${spec.type}: $what must be longer than nothing');
    // A view is whole dates: a date plus minutes is the same date, a step that would never move.
    if (d.exactMs != 0) {
      throw ArgumentError('${spec.type}: $what is days, weeks, months or years');
    }
  }

  positive(spec.duration, 'duration');
  final step = spec.dateIncrement;
  if (step != null) positive(step, 'dateIncrement');
  final count = spec.dayCount;
  if (count != null && count < 1) throw ArgumentError('${spec.type}: dayCount is a whole number of days, 1 or more');
  _assertDays(spec);
}

/// Weekdays 1 to 7, not every one hidden, a fixed period that ends after it
/// starts and shows a day.
void _assertDays(ViewSpec spec) {
  if (spec.hiddenDays.any((d) => d < 1 || d > 7)) {
    throw ArgumentError('${spec.type}: hiddenDays are ISO weekdays, 1 to 7');
  }
  if (spec.hiddenDays.toSet().length >= 7) throw ArgumentError('${spec.type}: every day of the week is hidden');
  final r = spec.visibleRange;
  if (r == null) return;
  if (!r.start.isBefore(r.end)) {
    throw ArgumentError('${spec.type}: visibleRange ends before it starts (its end is exclusive)');
  }
  if (_datesBetween(r.start, r.end, spec).isEmpty) {
    throw ArgumentError('${spec.type}: visibleRange shows no day (every one of its days is hidden)');
  }
}

/// The dates a view covers around [anchor]. A month grid starts on the first
/// weekday before the 1st and runs six weeks (or only the weeks the month
/// touches); a week starts on the first weekday; a day view with `dayCount`
/// counts shown days, stepping over hidden ones.
ViewRange computeViewRange(PlainDate anchor, ViewSpec spec, NavContext ctx) {
  // Checked again: a calendar's hidden days may have joined the view's since.
  _assertDays(spec);
  final fixed = spec.visibleRange;
  if (fixed != null) {
    final (start, end) = (fixed.start, fixed.end);
    if (spec.family == 'dayGrid') {
      // A grid's rows are whole weeks: the days around the period pad them.
      final from = _startOfWeek(start, ctx.firstDay);
      final to = _startOfWeek(end.addDays(-1), ctx.firstDay).addDays(7);
      final dates = _datesBetween(from, to, spec);
      return ViewRange(
        start: from,
        end: to,
        activeStart: start,
        activeEnd: end,
        dates: dates,
        weeks: _chunkWeeks(dates, ctx.firstDay),
      );
    }
    final dates = _datesBetween(start, end, spec);
    return ViewRange(start: start, end: end, activeStart: start, activeEnd: end, dates: dates, weeks: [dates]);
  }
  if (spec.family == 'multiMonth') return _multiMonthRange(anchor, spec, ctx);

  switch (spec.alignment) {
    case ViewAlignment.month:
      final first = PlainDate(anchor.year, anchor.month, 1);
      final severalMonths = spec.duration.months > 1;
      // A month grid is one month; a list or several months run for the duration.
      final activeEnd = spec.family == 'dayGrid' && !severalMonths
          ? first.addMonths(1)
          : spec.duration.addCalendarTo(first);
      if (spec.family == 'dayGrid' && severalMonths) {
        // Several months in one grid: the first month's first week to the last's last.
        final start = _startOfWeek(first, ctx.firstDay);
        final end = _startOfWeek(activeEnd.addDays(-1), ctx.firstDay).addDays(7);
        final dates = _datesBetween(start, end, spec);
        return ViewRange(
          start: start,
          end: end,
          activeStart: first,
          activeEnd: activeEnd,
          dates: dates,
          weeks: _chunkWeeks(dates, ctx.firstDay),
        );
      }
      if (spec.family == 'dayGrid') {
        // Six weeks from the first weekday on or before the 1st.
        final gridStart = _startOfWeek(first, ctx.firstDay);
        var grid = [
          for (var w = 0; w < 6; w++) [for (var i = 0; i < 7; i++) gridStart.addDays(w * 7 + i)],
        ];
        if (!spec.fixedWeekCount) {
          grid = grid.where((week) => week.any((d) => d.month == first.month && d.year == first.year)).toList();
        }
        final start = grid.first.first;
        final end = grid.last.last.addDays(1);
        final weeks = [for (final week in grid) week.where(spec.shows).toList()];
        return ViewRange(
          start: start,
          end: end,
          activeStart: first,
          activeEnd: activeEnd,
          dates: [for (final w in weeks) ...w],
          weeks: weeks,
        );
      }
      final dates = _datesBetween(first, activeEnd, spec);
      return ViewRange(
        start: first,
        end: activeEnd,
        activeStart: first,
        activeEnd: activeEnd,
        dates: dates,
        weeks: [dates],
      );
    case ViewAlignment.week:
      final start = _startOfWeek(anchor, ctx.firstDay);
      final end = spec.duration.addCalendarTo(start);
      final dates = _datesBetween(start, end, spec);
      return ViewRange(
        start: start,
        end: end,
        activeStart: start,
        activeEnd: end,
        dates: dates,
        weeks: _chunkWeeks(dates, ctx.firstDay),
      );
    case ViewAlignment.year:
      final start = PlainDate(anchor.year, 1, 1);
      final end = start.addYears(1);
      final dates = _datesBetween(start, end, spec);
      return ViewRange(start: start, end: end, activeStart: start, activeEnd: end, dates: dates, weeks: [dates]);
    case ViewAlignment.day:
    case ViewAlignment.none:
      final count = spec.dayCount;
      if (count != null) {
        final dates = <PlainDate>[];
        for (var d = anchor; dates.length < count; d = d.addDays(1)) {
          if (spec.shows(d)) dates.add(d);
        }
        final start = dates.first;
        final end = dates.last.addDays(1);
        return ViewRange(start: start, end: end, activeStart: start, activeEnd: end, dates: dates, weeks: [dates]);
      }
      // A one-day view anchored on a hidden day shows the next shown day.
      var start = anchor;
      while (!spec.shows(start)) {
        start = start.addDays(1);
      }
      final end = spec.duration.addCalendarTo(start);
      final dates = _datesBetween(start, end, spec);
      return ViewRange(start: start, end: end, activeStart: start, activeEnd: end, dates: dates, weeks: [dates]);
  }
}

/// Rows that each run from the first weekday.
List<List<PlainDate>> _chunkWeeks(List<PlainDate> dates, int firstDay) {
  final rows = <List<PlainDate>>[];
  PlainDate? key;
  for (final d in dates) {
    final k = _startOfWeek(d, firstDay);
    if (k != key) {
      rows.add([]);
      key = k;
    }
    rows.last.add(d);
  }
  return rows;
}

/// Several month grids, one per month of the period. The range runs from the
/// first grid's first day to the last grid's last, so sources fetch what is drawn.
ViewRange _multiMonthRange(PlainDate anchor, ViewSpec spec, NavContext ctx) {
  final first = spec.alignment == ViewAlignment.year
      ? PlainDate(anchor.year, 1, 1)
      : PlainDate(anchor.year, anchor.month, 1);
  final activeEnd = spec.duration.addCalendarTo(first);
  final monthSpec = spec.copyWith(family: 'dayGrid', alignment: ViewAlignment.month, duration: _month);
  final months = [for (var m = first; m.isBefore(activeEnd); m = m.addMonths(1)) computeViewRange(m, monthSpec, ctx)];
  final dates = _datesBetween(first, activeEnd, spec);
  return ViewRange(
    start: months.first.start,
    end: months.last.end,
    activeStart: first,
    activeEnd: activeEnd,
    dates: dates,
    weeks: [dates],
    months: months,
  );
}

/// Where a navigation goes: back, forward, today, or a date.
sealed class NavDirection {
  const NavDirection();
  static const prev = _Step(-1);
  static const next = _Step(1);
  static const today = _Today();
  const factory NavDirection.to(PlainDate date) = _To;
}

final class _Step extends NavDirection {
  const _Step(this.sign);
  final int sign;
}

final class _Today extends NavDirection {
  const _Today();
}

final class _To extends NavDirection {
  const _To(this.date);
  final PlainDate date;
}

/// The anchor after a navigation. Months move from the 1st, so 31 January
/// plus one month is February, not 3 March; a `dayCount` view steps by its
/// shown days, so four weekdays forward from Thursday lands on Wednesday.
PlainDate navigate(PlainDate anchor, ViewSpec spec, NavDirection dir, NavContext ctx) {
  switch (dir) {
    case _To(:final date):
      return date;
    case _Today():
      // A fixed period does not move: today stays on it too.
      return spec.visibleRange != null ? anchor : ctx.today;
    case _Step(:final sign):
      if (spec.visibleRange != null) return anchor;
      if (spec.dayCount != null && spec.dateIncrement == null) {
        final range = computeViewRange(anchor, spec, ctx);
        if (sign == 1) return range.end;
        // Back: the start of the previous run of `dayCount` shown days.
        var d = range.start.addDays(-1);
        for (var n = 0; ; d = d.addDays(-1)) {
          if (spec.shows(d)) n++;
          if (n == spec.dayCount) return d;
        }
      }
      final step = spec.dateIncrement ?? spec.duration;
      final from = switch (spec.alignment) {
        ViewAlignment.month => PlainDate(anchor.year, anchor.month, 1),
        ViewAlignment.year => PlainDate(anchor.year, 1, 1),
        _ => anchor,
      };
      var to = (sign == 1 ? step : step.negated()).addCalendarTo(from);
      // A day view steps over hidden days in the direction of travel: back
      // from Monday with the weekend hidden is Friday.
      if ((spec.alignment == ViewAlignment.day || spec.alignment == ViewAlignment.none) &&
          spec.hiddenDays.isNotEmpty &&
          spec.hiddenDays.length < 7) {
        while (!spec.shows(to)) {
          to = to.addDays(sign);
        }
      }
      return to;
  }
}
