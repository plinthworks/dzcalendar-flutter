import 'package:dzcalendar_core/internal.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'l10n/localizations.dart';
import 'theme.dart';
import 'views/common.dart' show monthTitleOf;

/// A small month to pick a date: alone (a date field, a booking screen) or
/// on a [CalendarController] — then it shows the calendar's period, marks
/// the days with events and a tap goes there (owner's decision 30).
class MiniMonth extends StatefulWidget {
  /// Alone: [selected] is circled, [onDateSelected] told of a tap.
  const MiniMonth({
    super.key,
    this.initialMonth,
    this.selected,
    this.onDateSelected,
    this.today,
    this.firstDay,
    this.locale,
    this.marked = const {},
    this.isEnabled,
  }) : controller = null;

  /// On a calendar: follows its date; a tap goes to the day.
  const MiniMonth.controller(CalendarController this.controller, {super.key, this.onDateSelected, this.isEnabled})
    : initialMonth = null,
      selected = null,
      today = null,
      firstDay = null,
      locale = null,
      marked = const {};

  final CalendarController? controller;

  /// The month shown first (default: [selected]'s, else today's).
  final PlainDate? initialMonth;
  final PlainDate? selected;
  final ValueChanged<PlainDate>? onDateSelected;

  /// Default: the device's date.
  final PlainDate? today;

  /// ISO weekday the week starts on. Default: the locale's.
  final int? firstDay;

  /// Default: the app's locale.
  final String? locale;

  /// Days drawn with a dot.
  final Set<PlainDate> marked;

  /// Days that can be picked (default: all).
  final bool Function(PlainDate date)? isEnabled;

  @override
  State<MiniMonth> createState() => _MiniMonthState();
}

class _MiniMonthState extends State<MiniMonth> {
  /// The month browsed with the chevrons; null: the anchor's.
  PlainDate? _shown;

  /// The calendar's date last drawn: when it moves, the mini month follows.
  PlainDate? _followed;

  static PlainDate _deviceToday() {
    final n = DateTime.now();
    return PlainDate(n.year, n.month, n.day);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return c == null
        ? _build(context, null)
        : ListenableBuilder(listenable: c, builder: (context, _) => _build(context, c));
  }

  Widget _build(BuildContext context, CalendarController? c) {
    final l10n = DzCalendarLocalizations.of(context);
    final style = DzCalendarTheme.of(context);
    final locale = c?.state.locale ?? widget.locale ?? Localizations.maybeLocaleOf(context)?.toLanguageTag() ?? 'en';
    final firstDay = c?.state.firstDay ?? widget.firstDay ?? weekRulesFor(locale).firstDay;
    final today = c?.state.today ?? widget.today ?? _deviceToday();
    final anchor = c?.state.date ?? widget.selected ?? today;
    if (c != null && anchor != _followed) {
      _followed = anchor;
      _shown = null;
    }
    final shown = _shown ?? widget.initialMonth ?? anchor;
    final month = PlainDate(shown.year, shown.month, 1);
    final start = month.addDays(-((month.dayOfWeek - firstDay + 7) % 7));
    final names = weekdayNames(locale, NameWidth.narrow, firstDay);
    final marked = c != null ? _eventDays(c, month) : widget.marked;
    final range = c?.state.range;
    bool selected(PlainDate d) =>
        range != null ? !d.isBefore(range.activeStart) && d.isBefore(range.activeEnd) : d == widget.selected;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: Text(
                  c == null ? formatTemporal(month, 'yMMMM', locale) : monthTitleOf(month, c.state),
                  style: style.titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.previous,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(() => _shown = month.addMonths(-1)),
            ),
            IconButton(
              tooltip: l10n.next,
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(() => _shown = month.addMonths(1)),
            ),
          ],
        ),
        Row(
          children: [
            for (final n in names)
              Expanded(
                child: Text(n, textAlign: TextAlign.center, style: style.headerStyle),
              ),
          ],
        ),
        for (var w = 0; w < 6; w++)
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _day(
                    context,
                    start.addDays(w * 7 + i),
                    month,
                    today,
                    selected,
                    marked,
                    locale,
                    l10n,
                    style,
                    c?.state,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Set<PlainDate> _eventDays(CalendarController c, PlainDate month) {
    final m = c.kernel.modelAt('dayGridMonth', month);
    if (m is! DayGridViewModel) return const {};
    return {
      for (final w in m.model.weeks)
        for (final s in w.segments)
          for (var k = 0; k < s.dayCount; k++)
            if (s.dayIndex - w.firstColumn + k < w.dates.length) w.dates[s.dayIndex - w.firstColumn + k],
    };
  }

  Widget _day(
    BuildContext context,
    PlainDate d,
    PlainDate month,
    PlainDate today,
    bool Function(PlainDate) selected,
    Set<PlainDate> marked,
    String locale,
    DzCalendarLocalizations l10n,
    DzCalendarStyle style,
    KernelState? state,
  ) {
    // On a calendar: its display calendar's numbers, its secondary's beside.
    final number = state == null ? formatTemporal(d, 'd', locale) : state.formatDate(d, 'd');
    final second = state?.formatSecondary(d, 'd');
    final long = state == null ? formatTemporal(d, 'yMMMMEEEEd', locale) : state.formatDate(d, 'yMMMMEEEEd');
    final longSecond = state?.formatSecondary(d, 'yMMMMd');
    final outside = d.month != month.month;
    final enabled = widget.isEnabled?.call(d) ?? true;
    final isSel = selected(d);
    final isToday = d == today;
    final color = isToday
        ? style.onTodayColor
        : !enabled || outside
        ? style.outsideDayColor
        : null;
    final VoidCallback? tap = !enabled
        ? null
        : () {
            setState(() => _shown = null);
            widget.controller?.goTo(d);
            widget.onDateSelected?.call(d);
          };
    // `excludeSemantics` drops the InkWell's tap with its words: given back here,
    // or a screen reader reads the day and cannot choose it.
    return Semantics(
      button: enabled,
      selected: isSel,
      enabled: enabled,
      label: l10n.dayLabel(longSecond == null ? long : '$long ($longSecond)', 0),
      onTap: tap,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: tap,
        child: Container(
          height: 40,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: isToday ? style.todayColor : (isSel ? style.selectionColor : null),
            shape: BoxShape.circle,
          ),
          // A larger text or a secondary date: the column shrinks, never overflows the circle.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(number, style: style.dayNumberStyle.copyWith(color: color)),
                if (second != null)
                  Text(
                    second,
                    maxLines: 1,
                    style: style.secondaryDateStyle.copyWith(
                      color: isToday ? style.onTodayColor : (outside ? style.outsideDayColor : null),
                      fontSize: (style.secondaryDateStyle.fontSize ?? 10) * 0.9,
                      height: 1,
                    ),
                  ),
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: marked.contains(d) ? (isToday ? style.onTodayColor : style.todayColor) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
