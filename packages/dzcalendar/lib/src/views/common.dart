import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../env.dart';
import '../interaction.dart';
import '../keyboard.dart';

/// The segments of [week] over cell [cell], drawn or not.
List<Segment> segmentsOn(DayGridWeek week, int cell) => [
  for (final s in week.segments)
    if (s.dayIndex - week.firstColumn <= cell && cell < s.dayIndex - week.firstColumn + s.dayCount) s,
];

/// A weekday's name in the calendar's locale.
String weekdayName(CalendarEnv env, PlainDate date, NameWidth width) =>
    weekdayNames(env.locale, width, 1)[date.dayOfWeek - 1];

/// A Gregorian month's title in [state]'s display calendar: "novembre
/// 2026", or the Hijri months it spans ("joum. oul.–joum. tha. 1448 AH").
String monthTitleOf(PlainDate month, KernelState state) {
  final first = PlainDate(month.year, month.month, 1);
  final c = state.displayCalendar;
  if (c == null) return formatTemporal(first, 'yMMMM', state.locale);
  final a = c.fromDate(first);
  final b = c.fromDate(first.addMonths(1).addDays(-1));
  return a.year == b.year && a.month == b.month
      ? formatTemporal(a, 'yMMMM', state.locale)
      : formatRangeTitle(a, b, 'yMMM', state.locale);
}

String monthTitle(CalendarEnv env, PlainDate month) => monthTitleOf(month, env.state);

/// A column's head in a one-row grid: "W 21" (narrow), "Wed, Oct 21".
String dayHead(CalendarEnv env, PlainDate date, int days) =>
    days > 3 ? '${weekdayName(env, date, NameWidth.narrow)} ${env.dayNumber(date)}' : env.date(date, 'MMMEd');

/// A bar in a day grid or an all-day row: filled for a day event, a dot and
/// its time for a timed one. Grabbed by a long press; a day event held
/// shows a handle at its end.
class EventBar extends StatelessWidget {
  const EventBar({super.key, required this.env, required this.segment});
  final CalendarEnv env;
  final Segment segment;

  @override
  Widget build(BuildContext context) {
    final i = segment.instance;
    final colors = env.colorsOf(i);
    final color = colors.fill;
    final style = env.style;
    final radius = Radius.circular(style.eventRadius);
    final timed = segment is TimedSegment && segment.dayCount == 1;
    final title = env.title(i);
    final when = env.span(i);
    Widget look(BuildContext context, BoxConstraints box) {
      final own = env.eventBuilder?.call(
        context,
        i,
        EventInfo(
          segment: segment,
          size: box.biggest,
          compact: box.maxWidth < 80,
          color: color,
          onColor: colors.on,
          when: when,
          held: env.interaction.held.value == i.key,
        ),
      );
      if (own != null) return own;
      if (timed) {
        final start = (segment as TimedSegment).from;
        return Row(
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsetsDirectional.only(start: 2, end: 3),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Flexible(
              // A narrow cell (a month on a phone) has room for the title only.
              child: Text(
                segment.startsHere && box.maxWidth >= 80 ? '${env.time(start)} $title' : title,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: style.eventStyle,
              ),
            ),
          ],
        );
      }
      return Container(
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
          style: style.eventStyle.copyWith(color: colors.on),
        ),
      );
    }

    return EventGestures(
      env: env,
      instance: i,
      label: env.l10n.eventLabel(title, when),
      draggable: true,
      resizeAxis: i.event.allDay && segment.endsHere ? Axis.horizontal : null,
      // An app's look hears the held state itself (the gestures' builder reuses this child).
      child: env.eventBuilder == null
          ? LayoutBuilder(builder: look)
          : ValueListenableBuilder<String?>(
              valueListenable: env.interaction.held,
              builder: (context, _, _) => LayoutBuilder(builder: look),
            ),
    );
  }
}

/// An event's gestures and its name for screen readers, around its look.
/// Tap: the app opens it (held, or no app to open it: its menu). Long press:
/// in a grid ([draggable]) it is grabbed when it may move (decision 35),
/// else its menu. Dragged, it is drawn faded where it was; held, its handle
/// ([resizeAxis]: down a column, along a bar) and its menu button show.
class EventGestures extends StatelessWidget {
  const EventGestures({
    super.key,
    required this.env,
    required this.instance,
    required this.label,
    required this.child,
    this.draggable = false,
    this.resizeAxis,
  });
  final CalendarEnv env;
  final EventInstance instance;
  final String label;
  final Widget child;
  final bool draggable;

  /// Which way its end is pulled when held (null: its length is not drawn here).
  final Axis? resizeAxis;

  @override
  Widget build(BuildContext context) => _Drawn(
    x: env.interaction,
    id: instance.key,
    child: Builder(builder: _build),
  );

  Widget _build(BuildContext context) {
    final x = env.interaction;
    final k = x.keyboard;
    final key = instance.key;
    final gestures = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        k.tappedEvent(instance);
        x.tapEvent(instance, d.globalPosition);
      },
      onLongPressStart: (d) => draggable
          ? x.pressEvent(instance, d.globalPosition)
          : env.showActions(context, EventTarget(instance), d.globalPosition),
      child: !draggable
          ? child
          : ListenableBuilder(
              listenable: Listenable.merge([x.lifted, x.held, k.focused]),
              builder: (context, _) {
                final lifted = x.lifted.value == key;
                final held = x.held.value == key;
                Widget look = lifted ? Opacity(opacity: 0.35, child: child) : child;
                if (held) look = _Held(env: env, instance: instance, axis: resizeAxis, child: look);
                if (k.focused.value == key && !held) {
                  look = Stack(
                    fit: StackFit.passthrough,
                    children: [
                      look,
                      Positioned.fill(
                        child: IgnorePointer(child: CursorBox(radius: env.style.eventRadius)),
                      ),
                    ],
                  );
                }
                return look;
              },
            ),
    );
    if (!draggable) {
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: () => x.tapEvent(instance, _center(context)),
        child: gestures,
      );
    }
    // In a grid: the reader's editing actions; held, it is adjustable (decision 42).
    return ValueListenableBuilder<GrabInfo?>(
      valueListenable: k.held,
      child: gestures,
      builder: (context, grab, child) {
        final l = env.l10n;
        if (grab != null && grab.key == key) {
          final time = grab.grid == KeyGrid.time;
          return Semantics(
            label: label,
            value: grab.value,
            increasedValue: grab.increased,
            decreasedValue: grab.decreased,
            hint: l.grabHelpReader,
            excludeSemantics: true,
            onIncrease: () => k.readerStep(1),
            onDecrease: () => k.readerStep(-1),
            onTap: k.readerPutDown,
            customSemanticsActions: {
              if (!k.grabbingLength) ...{
                CustomSemanticsAction(label: time ? l.previousDay : l.previousWeek): () => k.readerDay(-1),
                CustomSemanticsAction(label: time ? l.nextDay : l.nextWeek): () => k.readerDay(1),
              },
              CustomSemanticsAction(label: l.putDown): k.readerPutDown,
              CustomSemanticsAction(label: l.cancelMove): k.readerCancel,
            },
            child: child,
          );
        }
        final ev = instance.event;
        final editable = env.config.editable;
        return Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: () => x.tapEvent(instance, _center(context)),
          onLongPress: () => env.showActions(context, EventTarget(instance), _center(context)),
          customSemanticsActions: {
            if (editable && x.mayMove(ev))
              CustomSemanticsAction(label: l.moveEvent): () => k.grab(instance, GrabKind.move),
            if (editable && x.mayResize(ev))
              CustomSemanticsAction(label: l.resizeEvent): () => k.grab(instance, GrabKind.resize),
            if (editable && x.mayDelete(ev)) CustomSemanticsAction(label: l.deleteEvent): () => k.delete(instance),
          },
          child: child,
        );
      },
    );
  }

  /// The middle of this event on screen (where a menu opens for a reader).
  static Offset _center(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box.localToGlobal(box.size.center(Offset.zero)) : Offset.zero;
  }
}

/// Tells the gestures where an event's widget is, while it is (for the
/// app's popovers: its true lane and width, decision 49).
class _Drawn extends StatefulWidget {
  const _Drawn({required this.x, required this.id, required this.child});
  final CalendarInteraction x;
  final String id;
  final Widget child;

  @override
  State<_Drawn> createState() => _DrawnState();
}

class _DrawnState extends State<_Drawn> {
  @override
  void initState() {
    super.initState();
    widget.x.drawnAt(widget.id, context);
  }

  @override
  void didUpdateWidget(_Drawn old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id || !identical(old.x, widget.x)) {
      old.x.drawnNoMore(old.id, context);
      widget.x.drawnAt(widget.id, context);
    }
  }

  @override
  void dispose() {
    widget.x.drawnNoMore(widget.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A held event: outlined, its end's handle, its menu button.
class _Held extends StatelessWidget {
  const _Held({required this.env, required this.instance, required this.axis, required this.child});
  final CalendarEnv env;
  final EventInstance instance;
  final Axis? axis;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final x = env.interaction;
    final scheme = Theme.of(context).colorScheme;
    final resizable = axis != null && x.mayResize(instance.event);
    return LayoutBuilder(
      builder: (context, box) {
        final vertical = axis == Axis.vertical;
        final grip = vertical ? (box.maxHeight / 2).clamp(6.0, 16.0) : (box.maxWidth / 3).clamp(6.0, 16.0);
        return Stack(
          fit: StackFit.passthrough,
          children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(color: scheme.primary, width: 2),
                borderRadius: BorderRadius.circular(env.style.eventRadius),
              ),
              child: child,
            ),
            if (resizable)
              PositionedDirectional(
                start: vertical ? 0 : null,
                end: 0,
                bottom: 0,
                top: vertical ? null : 0,
                width: vertical ? null : grip,
                height: vertical ? grip : null,
                child: Semantics(
                  label: env.l10n.resizeEvent,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // Where the finger went down: the edge keeps its distance from it.
                    dragStartBehavior: DragStartBehavior.down,
                    onVerticalDragStart: vertical ? (d) => x.pullHandle(instance, d.globalPosition) : null,
                    onHorizontalDragStart: vertical ? null : (d) => x.pullHandle(instance, d.globalPosition),
                    child: Center(
                      child: Container(
                        width: vertical ? 20 : 4,
                        height: vertical ? 4 : 12,
                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                ),
              ),
            if (box.maxHeight >= 24 && box.maxWidth >= 40)
              PositionedDirectional(
                top: 0,
                end: 0,
                width: 24,
                height: 24,
                child: Semantics(
                  label: env.l10n.moreOptions,
                  button: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) => x.openMenu(instance, d.globalPosition),
                    child: Center(
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(color: scheme.surface, shape: BoxShape.circle),
                        child: Icon(Icons.more_vert, size: 16, color: scheme.primary),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The keyboard's cursor: an outline in the theme's primary color.
class CursorBox extends StatelessWidget {
  const CursorBox({super.key, required this.radius});
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
        borderRadius: BorderRadius.circular(radius),
      ),
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

/// Resource groups over the resources' heads: each as wide as its resources' columns.
class ResourceGroupRow extends StatelessWidget {
  const ResourceGroupRow({super.key, required this.env, required this.groups, required this.heads});
  final CalendarEnv env;
  final List<ResourceGroupHead> groups;
  final List<ResourceHead> heads;

  @override
  Widget build(BuildContext context) {
    int cells(int from, int count) =>
        [for (var k = from; k < from + count && k < heads.length; k++) heads[k].count].fold(0, (a, b) => a + b);
    return Row(
      children: [
        for (final g in groups)
          if (cells(g.from, g.count) > 0)
            Expanded(
              flex: cells(g.from, g.count),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    end: BorderSide(color: env.style.gridLineColor, width: 0.5),
                    bottom: BorderSide(color: env.style.gridLineColor, width: 0.5),
                  ),
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    g.value,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: env.style.headerStyle.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
      ],
    );
  }
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
