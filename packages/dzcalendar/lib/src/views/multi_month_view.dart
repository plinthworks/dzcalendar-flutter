import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:flutter/material.dart';

import '../env.dart';
import 'common.dart';
import 'day_grid_view.dart' show DayNumber;

/// A year (`multiMonth*`): months one under another, built as they scroll
/// into view; a dot under a day with events. A month's title goes to it.
class MultiMonthView extends StatelessWidget {
  const MultiMonthView({super.key, required this.env, required this.model, this.monthView = 'dayGridMonth'});
  final CalendarEnv env;
  final MultiMonthModel model;

  /// Where a month's title leads (when registered).
  final String monthView;

  @override
  Widget build(BuildContext context) {
    final months = model.months;
    final names = weekdayNames(env.locale, NameWidth.narrow, env.state.firstDay);
    final canGo = env.controller.kernel.viewSpec(monthView) != null;
    return ListView.builder(
      itemCount: months.length,
      itemBuilder: (context, i) {
        final m = months[i];
        final title = formatTemporal(m.month, 'yMMMM', env.locale);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
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
                if (m.model.weeks[w].outside.contains(false)) _MonthWeek(env: env, model: m.model, week: w),
            ],
          ),
        );
      },
    );
  }
}

class _MonthWeek extends StatelessWidget {
  const _MonthWeek({required this.env, required this.model, required this.week});
  final CalendarEnv env;
  final DayGridModel model;
  final int week;

  @override
  Widget build(BuildContext context) {
    final w = model.weeks[week];
    return Row(
      children: [
        for (var c = 0; c < w.dates.length; c++)
          Expanded(child: w.outside[c] ? const SizedBox(height: 36) : _day(context, w, c)),
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
          height: 36,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DayNumber(env: env, date: date, today: env.isToday(date)),
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
