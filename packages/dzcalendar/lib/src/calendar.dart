import 'dart:async';

import 'package:dzcalendar_core/internal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'env.dart';
import 'interaction.dart';
import 'l10n/localizations.dart';
import 'theme.dart';
import 'views/day_grid_view.dart';
import 'views/list_view.dart';
import 'views/multi_month_view.dart';
import 'views/time_grid_view.dart';
import 'views/timeline_view.dart';

/// The calendar: a header (previous, next, today, the title, the views) over
/// the controller's current view — month, week, day, list, year or timeline
/// (owner's decisions 30 and 61). A horizontal swipe goes to the previous or next
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
    this.eventBuilder,
    this.editable = false,
    this.selectable = false,
    this.snapMinutes = 15,
    this.dayView = 'timeGridDay',
    this.keyboardUndo = true,
    this.resourceAreaColumns = const [],
    this.onResourceToggle,
  }) : assert(snapMinutes > 0);

  final CalendarController controller;

  /// The view switcher's choices, by type; fewer than two: no switcher.
  final List<String> views;
  final bool showHeader;
  final bool swipeToNavigate;

  /// The hour a time grid shows at the top at first.
  final int scrollHour;

  /// An event tapped (and the menu's "Open", Enter on a focused event, a
  /// screen reader's tap). `rect` is where it is drawn, in global
  /// coordinates — the piece tapped, for an event over several days — to
  /// anchor a popover; the calendar's own box when it is not drawn.
  final EventTapCallback? onEventTap;

  /// A slot of a time grid or a day tapped: where, in calendar terms (a
  /// moment, flagged when it fell in a skipped hour, or a date).
  final void Function(Hit hit)? onDateTap;

  /// The selection a tap, a drag or the keyboard made (also on the
  /// controller), and `rect`: where it is drawn (global; the part in view).
  final SelectCallback? onSelect;

  /// The menu's "New event here": the app opens its own form, anchored on
  /// `rect`, the slot or the day (global).
  final CreateRequestCallback? onCreateRequest;

  /// A bookable slot (`ModelOptions.availableSlots`) tapped.
  final void Function(AvailableSlot slot)? onSlotTap;

  /// The long-press menu's entries, after the built-in ones are made.
  final ActionsBuilder? actionsBuilder;

  /// An event's color; null leaves its tone's or the theme's.
  final EventColor? eventColor;

  /// An event's look, built by the app (null: the calendar's own); its
  /// gestures, its name for screen readers and its handles stay the calendar's.
  final EventBuilder? eventBuilder;

  /// Events can be dragged and resized (a long press grabs one), and the
  /// menu offers editing entries. An event's own `editable` overrides it.
  /// Changes are told to the controller's `onEventChange`. Default false.
  final bool editable;

  /// A long press on empty time, then a drag, selects it (`onSelect`).
  /// Default false: the long press offers the menu.
  final bool selectable;

  /// Minutes moves, resizes and selections snap to in a time grid.
  final int snapMinutes;

  /// Where the menu's "Go to this day" leads (when registered).
  final String dayView;

  /// Ctrl+Z / ⌘Z undo and Shift+Ctrl+Z / Ctrl+Y redo, only on an
  /// [editable] calendar (owner's decision 43); false leaves those keys to
  /// the app.
  /// `controller.undo()` is never gated.
  final bool keyboardUndo;

  /// A resource timeline's area: its columns (tablets, desktops; a phone
  /// shows the title alone). Empty: one column, the title.
  final List<ResourceAreaColumn> resourceAreaColumns;

  /// A timeline's row folded or unfolded: what is collapsed now, for an
  /// application that keeps it (`ModelOptions.collapsedResources`,
  /// `collapsedGroups`).
  final ResourceToggleCallback? onResourceToggle;

  @override
  State<DzCalendar> createState() => _DzCalendarState();
}

class _DzCalendarState extends State<DzCalendar> with WidgetsBindingObserver, TickerProviderStateMixin {
  Timer? _clock;
  String? _followed;
  late final CalendarInteraction _interaction = CalendarInteraction(this);
  late final ValueNotifier<Instant> _now = ValueNotifier(widget.controller.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    _startClock();
  }

  /// Another period, view or zone: the held event is let go. Other options
  /// (a filter) or the store changed: once drawn again, what the keyboard is
  /// on or holds is let go if it is no longer drawn.
  void _changed() {
    const lets = {StateCause.navigate, StateCause.view, StateCause.zone, StateCause.resources};
    final changes = widget.controller.changes;
    if (changes.any((e) => e is KernelStateEvent && e.causes.any(lets.contains))) {
      _letGo();
    } else if (changes.any((e) => e is KernelStoreEvent || e is KernelStateEvent)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _interaction.keyboard.dropGone();
      });
    }
  }

  /// Any gesture under way ends, the held event is let go (another period, view, controller…).
  void _letGo() {
    _interaction
      ..release()
      ..cancel();
    _interaction.keyboard.periodChanged();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _followLocale();
  }

  @override
  void didUpdateWidget(DzCalendar old) {
    super.didUpdateWidget(old);
    if (old.editable && !widget.editable) {
      _letGo();
    }
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _letGo();
      _now.value = widget.controller.now();
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
    widget.controller.removeListener(_changed);
    _clock?.cancel();
    _interaction.dispose();
    _now.dispose();
    super.dispose();
  }

  /// One clock for every view: at each minute (and on coming back to the
  /// app), today's date, running events and the now line follow it.
  void _startClock({bool now = false}) {
    _clock?.cancel();
    void tick() {
      if (!mounted) return;
      widget.controller.tick();
      _now.value = widget.controller.now(); // the now line, without a rebuild
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
        config: widget,
        l10n: DzCalendarLocalizations.of(context),
        style: DzCalendarTheme.of(context),
        use24h: MediaQuery.alwaysUse24HourFormatOf(context),
        textDirection: Directionality.of(context),
        interaction: _interaction,
        now: _now,
      );
      _interaction
        ..env = env
        ..context = context;
      Widget body = _body(env);
      // A timeline scrolls sideways itself: no swipe between periods there.
      if (widget.swipeToNavigate && widget.controller.model is! TimelineViewModel) {
        final x = _interaction;
        // No swipe while an event is held or dragged (decision 35).
        body = ListenableBuilder(
          listenable: Listenable.merge([x.held, x.lifted]),
          child: body,
          builder: (context, child) => GestureDetector(
            onHorizontalDragEnd: x.held.value != null || x.busy
                ? null
                : (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v.abs() < 300) return;
                    // A swipe towards the start of the line goes forward (to the left in LTR, to the right in RTL).
                    final forward = (v < 0) == (env.textDirection == TextDirection.ltr);
                    forward ? widget.controller.next() : widget.controller.previous();
                  },
            child: child,
          ),
        );
      }
      return Column(
        children: [
          if (widget.showHeader) CalendarHeader(controller: widget.controller, views: widget.views),
          Expanded(
            // The calendar's one focus point: its keys (decision 41).
            child: Focus(
              focusNode: _interaction.keyboard.node,
              onKeyEvent: _interaction.keyboard.onKey,
              onFocusChange: _interaction.keyboard.focusChanged,
              child: Stack(
                children: [
                  Positioned.fill(child: body),
                  Positioned.fill(
                    child: GhostLayer(
                      interaction: _interaction,
                      radius: env.style.eventRadius,
                      style: env.style.eventStyle.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _body(CalendarEnv env) => switch (widget.controller.model) {
    TimeGridViewModel(:final model) => TimeGridView(env: env, model: model, scrollHour: widget.scrollHour),
    DayGridViewModel(:final model) => DayGridView(env: env, model: model),
    ListViewModel(:final model) => CalendarListView(env: env, model: model),
    MultiMonthViewModel(:final model) => MultiMonthView(env: env, model: model),
    TimelineViewModel(:final model) => TimelineView(
      env: env,
      model: model,
      scrollHour: widget.scrollHour,
      columns: widget.resourceAreaColumns,
      onResourceToggle: widget.onResourceToggle,
    ),
    // A family these widgets do not draw (an app's own): said in debug builds.
    final other =>
      kDebugMode
          ? Center(child: Text('DzCalendar: the ${other.family} family is not drawn', textAlign: TextAlign.center))
          : const SizedBox.shrink(),
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
