import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'calendar.dart';
import 'controller.dart';
import 'interaction.dart';
import 'l10n/localizations.dart';
import 'theme.dart';

/// The application's say over the menus: the built-in entries for a target
/// in, the entries shown out (kept, reordered, replaced, added to).
typedef ActionsBuilder = List<ActionItem> Function(ActionTarget target, List<ActionItem> builtIn);

/// An event's color: null leaves the theme's (its tone, else the default).
typedef EventColor = Color? Function(EventInstance instance);

/// What an app's [EventBuilder] draws an event from. Gestures, semantics
/// and the held event's handles stay the calendar's, around what it builds.
final class EventInfo {
  const EventInfo({
    required this.segment,
    required this.size,
    required this.compact,
    required this.color,
    required this.onColor,
    required this.when,
    required this.held,
  });

  /// The piece drawn (a day's part of a longer event, its readings).
  final Segment segment;
  final Size size;

  /// Too narrow or too short for more than the title.
  final bool compact;

  /// The event's color (the app's, its tone's or the theme's), and text over it.
  final Color color;
  final Color onColor;

  /// Its times as the calendar writes them ("09:30 – 10:15", "All day").
  final String when;

  /// Held after a long press: its handles show.
  final bool held;
}

/// An event's look, built by the app (null: the calendar's own).
typedef EventBuilder = Widget? Function(BuildContext context, EventInstance instance, EventInfo info);

/// What the views share, made at each [DzCalendar] build: the widget's
/// settings and callbacks (read from it, not copied), the words, the style,
/// the formats in the calendar's locale and zone, the gestures.
class CalendarEnv {
  CalendarEnv({
    required this.config,
    required this.l10n,
    required this.style,
    required this.use24h,
    required this.textDirection,
    required this.interaction,
    required this.now,
  });

  final DzCalendar config;
  final DzCalendarLocalizations l10n;
  final DzCalendarStyle style;

  /// The device's 24-hour setting (`MediaQuery.alwaysUse24HourFormat`).
  final bool use24h;
  final TextDirection textDirection;

  /// The gestures that edit (held, dragged events; a drag selecting time).
  final CalendarInteraction interaction;

  /// The clock the now line follows (each minute), without a rebuild.
  final ValueListenable<Instant> now;

  CalendarController get controller => config.controller;
  void Function(EventInstance instance)? get onEventTap => config.onEventTap;
  void Function(Hit hit)? get onDateTap => config.onDateTap;
  void Function(CalendarSelection selection)? get onSelect => config.onSelect;
  void Function(CreateRequest request)? get onCreateRequest => config.onCreateRequest;
  ActionsBuilder? get actionsBuilder => config.actionsBuilder;
  EventColor? get eventColor => config.eventColor;
  EventBuilder? get eventBuilder => config.eventBuilder;

  /// A bookable slot (`availableSlots`) tapped.
  void Function(AvailableSlot slot)? get onSlotTap => config.onSlotTap;

  /// Where "Go to this day" leads (when registered).
  String get dayView => config.dayView;

  KernelState get state => controller.state;
  String get locale => state.locale;
  ZoneId get zone => state.timeZone;

  /// A moment's clock time in the calendar's zone ("09:30", "9:30 AM"), with
  /// its offset when two readings must be told apart.
  String time(Instant at, {bool withOffset = false}) {
    final z = ZonedDateTime(at, zone);
    final text = formatTemporal(z, use24h ? 'Hm' : 'jm', locale);
    return withOffset ? '$text (UTC${z.offset})' : text;
  }

  /// A wall clock time ("02:00"), as the gutter writes it.
  String clock(PlainTime t, {bool short = false}) =>
      formatTemporal(t, use24h ? 'Hm' : (short && t.minute == 0 ? 'j' : 'jm'), locale);

  /// "Wednesday 21 October 2026".
  String dateLong(PlainDate d) => formatTemporal(d, 'yMMMMEEEEd', locale);

  String title(EventInstance i) => i.event.title.isEmpty ? l10n.untitled : i.event.title;

  /// An event's color: the app's, else its tone's, else the theme's.
  Color colorOf(EventInstance i) => colorsOf(i).fill;

  /// An event's color and readable text over it: the theme's pair when the
  /// color is the theme's, else measured.
  ({Color fill, Color on}) colorsOf(EventInstance i) {
    final tone = i.event.tone;
    final fill = eventColor?.call(i) ?? (tone != null ? style.tones[tone] : null);
    if (fill == null) return (fill: style.eventColor, on: style.onEventColor);
    return (fill: fill, on: _readableOn(fill));
  }

  static Color _readableOn(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark ? Colors.white : Colors.black87;

  /// A timed event's span in the calendar's zone: "09:30 – 10:15".
  String span(EventInstance i) {
    final ev = i.event;
    return switch (ev) {
      TimedEvent(:final start, :final end) => l10n.range(time(start.instant), time(end.instant)),
      AllDayEvent() => l10n.allDay,
    };
  }

  bool isToday(PlainDate d) => d == state.today;

  ActionLabels get _labels => ActionLabels(
    newEventAt: l10n.newEventAt,
    newEventOn: l10n.newEventOn,
    goToDay: l10n.goToDay,
    openEvent: l10n.openEvent,
    skippedHour: l10n.skippedHour,
    deleteEvent: l10n.deleteEvent,
    moveEvent: l10n.moveEvent,
    resizeEvent: l10n.resizeEvent,
    scopeThis: l10n.scopeThis,
    scopeFollowing: l10n.scopeFollowing,
    scopeAll: l10n.scopeAll,
  );

  /// The menu's entries for [target]: the core's, then the app's say.
  List<ActionItem> menuFor(ActionTarget target) {
    final open = onEventTap;
    final create = onCreateRequest;
    final hasDayView = controller.kernel.viewSpec(dayView) != null;
    final builtIn = actionsFor(
      target,
      ActionContext(
        displayZone: zone,
        labels: _labels,
        formatTime: (at, withOffset) => time(at, withOffset: withOffset),
        formatDate: dateLong,
        onCreateRequest: create,
        onGoToDay: hasDayView && state.view.type != dayView ? (d) => controller.setView(dayView, d) : null,
        onOpen: open,
        // Editing entries only where a person may edit (as the TS: `editable`).
        onCommand: config.editable ? (c) => controller.run(c, validate: true) : null,
      ),
    );
    final b = actionsBuilder;
    return b == null ? builtIn : b(target, builtIn);
  }

  /// Opens the menu for [target] at [position] (global), if it has entries.
  Future<void> showActions(BuildContext context, ActionTarget target, Offset position) async {
    final items = menuFor(target);
    if (items.isEmpty) return;
    await _showItems(context, items, position, l10n.actions);
  }

  Future<void> _showItems(BuildContext context, List<ActionItem> items, Offset position, String label) async {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    final rect = RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size);
    final chosen = await showMenu<ActionItem>(
      context: context,
      position: rect,
      semanticLabel: label,
      items: [
        for (final item in items)
          PopupMenuItem<ActionItem>(
            value: item,
            enabled: item.enabled,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: item.icon == 'delete' ? const Icon(Icons.delete_outline) : null,
              title: Text(item.label),
              subtitle: item.reason != null ? Text(item.reason!) : null,
              trailing: item.children.isNotEmpty ? const Icon(Icons.arrow_right) : null,
            ),
          ),
      ],
    );
    if (chosen == null || !context.mounted) return;
    if (chosen.children.isNotEmpty) {
      await _showItems(context, chosen.children, position, chosen.id == 'event.delete' ? l10n.deleteWhich : label);
      return;
    }
    chosen.run?.call();
  }
}
