import 'dart:async';

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'env.dart';
import 'l10n/localizations.dart';
import 'theme.dart';
import 'views/day_grid_view.dart';
import 'views/list_view.dart';
import 'views/multi_month_view.dart';
import 'views/time_grid_view.dart';

/// The calendar: a header (previous, next, today, the title, the views) over
/// the controller's current view — month, week, day, list or year (owner's
/// decision 30, 2026-11-09). A horizontal swipe goes to the previous or next
/// period. The words come from [DzCalendarLocalizations], the style from
/// [DzCalendarTheme].
class DzCalendar extends StatefulWidget {
  const DzCalendar({
    super.key,
    required this.controller,
    this.views = const ['dayGridMonth', 'timeGridWeek', 'timeGridDay', 'listWeek'],
    this.showHeader = true,
    this.swipeToNavigate = true,
    this.scrollHour = 7,
    this.onEventTap,
    this.onDateTap,
    this.onSelect,
    this.onCreateRequest,
    this.onSlotTap,
    this.actionsBuilder,
    this.eventColor,
  });

  final CalendarController controller;

  /// The view switcher's choices, by type; fewer than two: no switcher.
  final List<String> views;
  final bool showHeader;
  final bool swipeToNavigate;

  /// The hour a time grid shows at the top at first.
  final int scrollHour;

  /// An event tapped (and the menu's "Open").
  final void Function(EventInstance instance)? onEventTap;

  /// A slot of a time grid or a day tapped: where, in calendar terms (a
  /// moment, flagged when it fell in a skipped hour, or a date).
  final void Function(Hit hit)? onDateTap;

  /// The selection a tap made (one slot, one day), also on the controller.
  final void Function(CalendarSelection selection)? onSelect;

  /// The menu's "New event here": the app opens its own form.
  final void Function(CreateRequest request)? onCreateRequest;

  /// A bookable slot (`ModelOptions.availableSlots`) tapped.
  final void Function(AvailableSlot slot)? onSlotTap;

  /// The long-press menu's entries, after the built-in ones are made.
  final ActionsBuilder? actionsBuilder;

  /// An event's color; null leaves its tone's or the theme's.
  final EventColor? eventColor;

  @override
  State<DzCalendar> createState() => _DzCalendarState();
}

class _DzCalendarState extends State<DzCalendar> with WidgetsBindingObserver {
  Timer? _clock;
  String? _followed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _followLocale();
  }

  @override
  void didUpdateWidget(DzCalendar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _followed = null;
      _followLocale();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClock(now: true);
    } else {
      _clock?.cancel();
      _clock = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    super.dispose();
  }

  /// One clock for every view: at each minute (and on coming back to the
  /// app), today's date, running events and the now line follow it.
  void _startClock({bool now = false}) {
    _clock?.cancel();
    void tick() {
      if (!mounted) return;
      widget.controller.tick();
      setState(() {}); // the now line
    }

    final ms = widget.controller.now().epochMilliseconds;
    _clock = Timer(Duration(milliseconds: 60000 - ms % 60000), () {
      tick();
      _clock = Timer.periodic(const Duration(minutes: 1), (_) => tick());
    });
    if (now) tick();
  }

  /// The app's locale, when the controller follows it, and only when it
  /// changes: an app that sets the calendar's own in between keeps it. Told
  /// during a build, the controller notifies after it.
  void _followLocale() {
    final c = widget.controller;
    if (!c.followAppLocale) return;
    final tag = Localizations.maybeLocaleOf(context)?.toLanguageTag();
    if (tag == null || tag == _followed) return;
    _followed = tag;
    c.setLocale(tag);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final env = CalendarEnv(
        controller: widget.controller,
        l10n: DzCalendarLocalizations.of(context),
        style: DzCalendarTheme.of(context),
        use24h: MediaQuery.alwaysUse24HourFormatOf(context),
        textDirection: Directionality.of(context),
        onEventTap: widget.onEventTap,
        onDateTap: widget.onDateTap,
        onSelect: widget.onSelect,
        onCreateRequest: widget.onCreateRequest,
        onSlotTap: widget.onSlotTap,
        actionsBuilder: widget.actionsBuilder,
        eventColor: widget.eventColor,
      );
      Widget body = _body(env);
      if (widget.swipeToNavigate) {
        body = GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() < 300) return;
            // A swipe towards the start of the line goes forward (to the left in LTR, to the right in RTL).
            final forward = (v < 0) == (env.textDirection == TextDirection.ltr);
            forward ? widget.controller.next() : widget.controller.previous();
          },
          child: body,
        );
      }
      return Column(
        children: [
          if (widget.showHeader) CalendarHeader(controller: widget.controller, views: widget.views),
          Expanded(child: body),
        ],
      );
    },
  );

  Widget _body(CalendarEnv env) => switch (widget.controller.model) {
    TimeGridViewModel(:final model) => TimeGridView(env: env, model: model, scrollHour: widget.scrollHour),
    DayGridViewModel(:final model) => DayGridView(env: env, model: model),
    ListViewModel(:final model) => CalendarListView(env: env, model: model),
    MultiMonthViewModel(:final model) => MultiMonthView(env: env, model: model),
    // A family these widgets do not draw (the timeline, an app's own).
    _ => const SizedBox.shrink(),
  };
}

/// Previous, next, today, the title, the views: what [DzCalendar] shows on
/// top, usable alone (in an `AppBar`, over a [MiniMonth]).
class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    super.key,
    required this.controller,
    this.views = const ['dayGridMonth', 'timeGridWeek', 'timeGridDay', 'listWeek'],
  });
  final CalendarController controller;

  /// The view switcher's choices; fewer than two: no switcher.
  final List<String> views;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: controller, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final c = controller;
    final l10n = DzCalendarLocalizations.of(context);
    final style = DzCalendarTheme.of(context);
    final state = c.state;
    final known = [
      for (final v in views)
        if (c.kernel.viewSpec(v) != null) v,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(tooltip: l10n.previous, icon: const Icon(Icons.chevron_left), onPressed: c.previous),
          IconButton(tooltip: l10n.next, icon: const Icon(Icons.chevron_right), onPressed: c.next),
          Expanded(
            child: Semantics(
              header: true,
              liveRegion: true,
              child: Text(state.title, style: style.titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          IconButton(tooltip: l10n.today, icon: const Icon(Icons.today), onPressed: c.today),
          if (known.length > 1)
            PopupMenuButton<String>(
              tooltip: l10n.viewSwitcher,
              initialValue: state.view.type,
              onSelected: c.setView,
              itemBuilder: (_) => [for (final v in known) PopupMenuItem(value: v, child: Text(l10n.viewName(v)))],
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, end: 8, top: 8, bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Text(l10n.viewName(state.view.type)), const Icon(Icons.arrow_drop_down)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
