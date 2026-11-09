import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:flutter/material.dart';

import '../env.dart';

/// The segments of [week] over cell [cell], drawn or not.
List<Segment> segmentsOn(DayGridWeek week, int cell) => [
  for (final s in week.segments)
    if (s.dayIndex - week.firstColumn <= cell && cell < s.dayIndex - week.firstColumn + s.dayCount) s,
];

/// A weekday's name in the calendar's locale.
String weekdayName(CalendarEnv env, PlainDate date, NameWidth width) =>
    weekdayNames(env.locale, width, 1)[date.dayOfWeek - 1];

/// A column's head in a one-row grid: "W 21" (narrow), "Wed, Oct 21".
String dayHead(CalendarEnv env, PlainDate date, int days) => days > 3
    ? '${weekdayName(env, date, NameWidth.narrow)} ${formatTemporal(date, 'd', env.locale)}'
    : formatTemporal(date, 'MMMEd', env.locale);

/// A bar in a day grid or an all-day row: filled for a day event, a dot and
/// its time for a timed one. Tap opens, long press offers the menu.
class EventBar extends StatelessWidget {
  const EventBar({super.key, required this.env, required this.segment});
  final CalendarEnv env;
  final Segment segment;

  @override
  Widget build(BuildContext context) {
    final i = segment.instance;
    final color = env.colorOf(i);
    final style = env.style;
    final radius = Radius.circular(style.eventRadius);
    final timed = segment is TimedSegment && segment.dayCount == 1;
    final title = env.title(i);
    final Widget body;
    if (timed) {
      final start = (segment as TimedSegment).from;
      body = Row(
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsetsDirectional.only(start: 2, end: 3),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Flexible(
            child: LayoutBuilder(
              // A narrow cell (a month on a phone) has room for the title only.
              builder: (context, box) => Text(
                segment.startsHere && box.maxWidth >= 80 ? '${env.time(start)} $title' : title,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: style.eventStyle,
              ),
            ),
          ),
        ],
      );
    } else {
      body = Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: AlignmentDirectional.centerStart,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadiusDirectional.horizontal(
            start: segment.startsHere ? radius : Radius.zero,
            end: segment.endsHere ? radius : Radius.zero,
          ),
        ),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.clip,
          softWrap: false,
          style: style.eventStyle.copyWith(color: env.onColor(color)),
        ),
      );
    }
    return EventGestures(env: env, instance: i, label: env.l10n.eventLabel(title, env.span(i)), child: body);
  }
}

/// Tap: open; long press: the event's menu. Named for screen readers.
class EventGestures extends StatelessWidget {
  const EventGestures({super.key, required this.env, required this.instance, required this.label, required this.child});
  final CalendarEnv env;
  final EventInstance instance;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: env.onEventTap == null ? null : () => env.onEventTap!(instance),
      onLongPressStart: (d) => env.showActions(context, EventTarget(instance), d.globalPosition),
      child: child,
    ),
  );
}

/// The resources over a resource view's columns, each over its days.
class ResourceHeadRow extends StatelessWidget {
  const ResourceHeadRow({super.key, required this.env, required this.heads, required this.cells});
  final CalendarEnv env;
  final List<ResourceHead> heads;
  final int cells;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final h in heads)
        Expanded(
          flex: h.count,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            decoration: BoxDecoration(
              border: BorderDirectional(end: BorderSide(color: env.style.gridLineColor, width: 0.5)),
            ),
            child: Text(
              h.resource.id == unassignedId ? env.l10n.unassigned : h.resource.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: env.style.headerStyle.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
    ],
  );
}

/// A row of a list: time, color, title. Tap opens, long press: the menu.
class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.env, required this.instance, required this.when});
  final CalendarEnv env;
  final EventInstance instance;

  /// What the time column says ("All day", "09:30 – 10:15").
  final String when;

  @override
  Widget build(BuildContext context) {
    final title = env.title(instance);
    return EventGestures(
      env: env,
      instance: instance,
      label: env.l10n.eventLabel(title, when),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 104, child: Text(when, style: env.style.timeLabelStyle.copyWith(fontSize: 13))),
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsetsDirectional.only(top: 4, end: 10),
              decoration: BoxDecoration(color: env.colorOf(instance), shape: BoxShape.circle),
            ),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

/// A day's events in a bottom sheet (what "+N" stands for).
Future<void> showDaySheet(BuildContext context, CalendarEnv env, PlainDate date, List<Segment> segments) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(env.dateLong(date), style: Theme.of(sheet).textTheme.titleMedium),
            ),
            for (final s in segments)
              EventTile(
                env: env,
                instance: s.instance,
                when: switch (s) {
                  TimedSegment(:final from, :final to) => '${env.time(from)} – ${env.time(to)}',
                  AllDaySegment() => env.l10n.allDay,
                },
              ),
          ],
        ),
      ),
    );
