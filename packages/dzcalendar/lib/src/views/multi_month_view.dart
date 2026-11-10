import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:flutter/material.dart';

import '../env.dart';
import 'common.dart';
import 'day_grid_view.dart' show DayNumber;

/// A year (`multiMonth*`): months in rows of as many as fit ([monthWidth]
/// each, at most four — macOS Calendar's 4 × 3 on a wide screen, one under
/// another on a phone), built as they scroll into view; a dot under a day
/// with events. A month's title goes to it.
class MultiMonthView extends StatelessWidget {
  const MultiMonthView({super.key, required this.env, required this.model, this.monthView = 'dayGridMonth'});
  final CalendarEnv env;
  final MultiMonthModel model;

  /// Where a month's title leads (when registered).
  final String monthView;

  /// The least width of a month; below twice it, one month a row.
  static const monthWidth = 240.0;

  @override
  Widget build(BuildContext context) {
    final months = model.months;
    final names = weekdayNames(env.locale, NameWidth.narrow, env.state.firstDay);
    final canGo = env.controller.kernel.viewSpec(monthView) != null;
    return LayoutBuilder(
      builder: (context, box) {
        final perRow = (box.maxWidth / monthWidth).floor().clamp(1, 4);
        final rows = (months.length + perRow - 1) ~/ perRow;
        return ListView.builder(
          itemCount: rows,
          itemBuilder: (context, r) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = r * perRow; k < (r + 1) * perRow; k++)
                Expanded(
                  child: k < months.length
                      ? _month(months[k], names, canGo, compact: perRow > 1)
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _month(({PlainDate month, DayGridModel model}) m, List<String> names, bool canGo, {required bool compact}) {
    final title = monthTitle(env, m.month);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, compact ? 8 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            button: canGo,
            label: canGo ? '$title, ${env.l10n.goToMonth}' : title,
            excludeSemantics: true,
            child: InkWell(
              onTap: canGo ? () => env.controller.setView(monthView, m.month) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(title, style: env.style.titleStyle.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          Row(
            children: [
              for (final n in names)
                Expanded(
                  child: Text(n, textAlign: TextAlign.center, style: env.style.headerStyle),
                ),
            ],
          ),
          for (var w = 0; w < m.model.weeks.length; w++)
            // A row of the next month's days only (a fixed six-week grid) is left out.
            if (m.model.weeks[w].outside.contains(false))
              _MonthWeek(env: env, model: m.model, week: w, height: compact ? 30 : 36),
        ],
      ),
    );
  }
}

class _MonthWeek extends StatelessWidget {
  const _MonthWeek({required this.env, required this.model, required this.week, required this.height});
  final CalendarEnv env;
  final DayGridModel model;
  final int week;
  final double height;

  @override
  Widget build(BuildContext context) {
    final w = model.weeks[week];
    return Row(
      children: [
        for (var c = 0; c < w.dates.length; c++)
          Expanded(child: w.outside[c] ? SizedBox(height: height) : _day(context, w, c)),
      ],
    );
  }

  Widget _day(BuildContext context, DayGridWeek w, int c) {
    final date = w.dates[c];
    final count = segmentsOn(w, c).length;
    return Semantics(
      button: true,
      label: env.l10n.dayLabel(env.dateLong(date), count),
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          final hit = dayHitAt(model, week, c);
          if (hit != null) env.onDateTap?.call(hit);
        },
        child: SizedBox(
          height: height,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // A narrow month (four a row) or a large text: the number shrinks, never overflows.
              Flexible(
                child: LayoutBuilder(
                  builder: (context, box) => FittedBox(
                    fit: BoxFit.scaleDown,
                    // Its width told: a long "1 Ram." is dropped, not every digit shrunk.
                    child: DayNumber(env: env, date: date, today: env.isToday(date), maxWidth: box.maxWidth),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: count > 0 ? env.style.todayColor : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
