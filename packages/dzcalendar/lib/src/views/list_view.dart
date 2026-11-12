import 'package:dzcalendar_core/internal.dart';
import 'package:flutter/material.dart';

import '../env.dart';
import 'common.dart';

/// A list (`list*`): the period's events day by day, built as they scroll
/// into view. A 25-hour day says so: its length is in the model.
class CalendarListView extends StatelessWidget {
  const CalendarListView({super.key, required this.env, required this.model});
  final CalendarEnv env;
  final ListModel model;

  @override
  Widget build(BuildContext context) {
    final days = model.days;
    if (days.isEmpty) {
      return Center(child: Text(env.l10n.noEvents, style: Theme.of(context).textTheme.bodyMedium));
    }
    // One row per day head and per entry, flattened so the builder makes only what shows.
    final rows = <Object>[
      for (final d in days) ...[d, ...d.entries],
    ];
    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) => switch (rows[i]) {
        final ListDay d => _DayHead(env: env, day: d),
        final ListEntry e => EventTile(env: env, instance: e.instance, when: _when(e)),
        _ => const SizedBox.shrink(),
      },
    );
  }

  String _when(ListEntry e) {
    if (e.allDay) return env.l10n.allDay;
    final s = e.start;
    final end = e.end;
    if (s == null || end == null) return env.l10n.allDay;
    return '${env.time(s.instant)} – ${e.endsHere ? env.time(end.instant) : '…'}';
  }
}

class _DayHead extends StatelessWidget {
  const _DayHead({required this.env, required this.day});
  final CalendarEnv env;
  final ListDay day;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final today = env.isToday(day.date);
    final odd = day.lengthMinutes != 1440;
    return Semantics(
      header: true,
      child: Container(
        color: s.surfaceContainerHigh,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                env.dateLong(day.date),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: today ? env.style.todayColor : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // A day that is not 24 hours long in the zone (a clock change).
            if (odd) Text(env.l10n.duration(day.lengthMinutes.round()), style: env.style.timeLabelStyle),
          ],
        ),
      ),
    );
  }
}
