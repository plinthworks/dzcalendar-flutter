import 'dart:async';

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:flutter/foundation.dart';

/// A calendar as Flutter listens to it: a [ChangeNotifier] over a
/// [CalendarKernel] (owner's decisions 22 and 30, 2026-11-09). One
/// controller can drive a [DzCalendar], a mini-month and the app's own
/// toolbar; it does not depend on any state-management package (wrap it in
/// a Riverpod provider, a `ChangeNotifierProvider`… as the app does).
///
/// The kernel tells its subscribers at once; listeners here are told in a
/// microtask — after what is running (a build that changed the locale from
/// `Localizations`, a gesture), before the next frame — so no widget is
/// marked dirty during a build. Several changes make one notification.
///
/// Configuration errors (an unknown zone or view) throw an [ArgumentError]
/// when given, as the kernel's; data never does.
class CalendarController extends ChangeNotifier {
  CalendarController(KernelOptions options, {this.followAppLocale = true, this.onEventChange, this.onCommandRefused})
    : kernel = CalendarKernel(_withErrors(options)),
      _ownsKernel = true {
    _unsubscribe = kernel.subscribe(_onKernel);
  }

  /// Wraps a kernel made elsewhere (shared with a server-side model, a test).
  /// Its `onError` is the kernel's own, and [dispose] leaves it running.
  CalendarController.of(this.kernel, {this.followAppLocale = false, this.onEventChange, this.onCommandRefused})
    : _ownsKernel = false {
    _unsubscribe = kernel.subscribe(_onKernel);
  }

  /// A person changed events (a drag, a resize, the menu: a command run with
  /// `validate: true`), or undid or redid one: persist it. Told at once, as
  /// the change is made (owner's decision 37); the server refusing it,
  /// [EventChange.revert] takes exactly that change back. The app's own
  /// commands (`run` without `validate`) and [setEvents] are not told.
  void Function(EventChange change)? onEventChange;

  /// A person's command was refused (the rules, an event that is gone): why.
  void Function(CommandResult result, Command command)? onCommandRefused;

  final CalendarKernel kernel;

  /// The calendar takes the app's locale (`Localizations.localeOf`) when a
  /// [DzCalendar] is built; false: [setLocale] only.
  final bool followAppLocale;
  final bool _ownsKernel;

  late final void Function() _unsubscribe;
  final _pending = <KernelEvent>[];
  var _scheduled = false;
  var _disposed = false;
  var _reverting = false;
  var _telling = false;

  /// A revert asked inside `onEventChange` is written once the change's own
  /// write is over: that next undo or redo is the revert's, not told.
  var _skipRevertWrite = false;
  final _selection = ValueNotifier<CalendarSelection?>(null);

  static KernelOptions _withErrors(KernelOptions o) => KernelOptions(
    timeZone: o.timeZone,
    locale: o.locale,
    firstDay: o.firstDay,
    titleFormat: o.titleFormat,
    initialDate: o.initialDate,
    initialView: o.initialView,
    views: o.views,
    store: o.store,
    events: o.events,
    now: o.now,
    rules: o.rules,
    historyLimit: o.historyLimit,
    resources: o.resources,
    options: o.options,
    onError: o.onError ?? _report,
    displayCalendar: o.displayCalendar,
    secondaryCalendar: o.secondaryCalendar,
  );

  static void _report(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'dzcalendar',
      context: ErrorDescription('while a calendar told its listeners'),
    ),
  );

  // ——— reading ———

  KernelState get state => kernel.state;

  /// The current view's model, made again only for what changed.
  ViewModel get model => kernel.viewModel();
  ModelOptions get options => kernel.options;
  History get history => kernel.history;
  Instant now() => kernel.now();

  /// The kernel's events since the last notification: why it changed
  /// (navigation and its direction, a store change, a validated command).
  /// Read them in a listener; they are cleared at the next change.
  List<KernelEvent> get changes => List.unmodifiable(_delivered);
  var _delivered = const <KernelEvent>[];

  /// What the user has selected (a tap on a slot or a day, a drag across
  /// time), shared by every widget on this controller.
  CalendarSelection? get selection => _selection.value;

  /// The selection, listened to on its own: selecting does not notify the
  /// controller's listeners (nothing else changed), only this one's — a
  /// widget showing [selection] listens here (changed in 19e-2b-1).
  ValueListenable<CalendarSelection?> get selectionListenable => _selection;

  // ——— changing ———

  void setView(String type, [PlainDate? at]) => kernel.setView(type, at);
  void previous() => kernel.navigate(NavDirection.prev);
  void next() => kernel.navigate(NavDirection.next);
  void today() => kernel.navigate(NavDirection.today);
  void goTo(PlainDate date) => kernel.navigate(NavDirection.to(date));
  void setTimeZone(ZoneId zone) => kernel.setTimeZone(zone);
  void setLocale(String locale) => kernel.setLocale(locale);
  void setFirstDay(int? day) => kernel.setFirstDay(day);
  void setTitleFormat(TitleFormat? format) => kernel.setTitleFormat(format);
  void setRules(CalendarRules? rules) => kernel.setRules(rules);
  void setOptions(ModelOptions next) => kernel.setOptions(next);

  /// The calendar dates are written in (null: Gregorian), and the one
  /// written beside them (null: none) — owner's decision 53.
  void setDisplayCalendar(HijriCalendar? calendar) => kernel.setDisplayCalendar(calendar);
  void setSecondaryCalendar(HijriCalendar? calendar) => kernel.setSecondaryCalendar(calendar);
  NormalizationReport setEvents(List<EventInput> events) => kernel.setEvents(events);
  List<Problem> setResources(List<ResourceInput> next) => kernel.setResources(next);

  /// Several changes, one notification.
  void batch(void Function() fn) => kernel.batch(fn);

  /// Runs an edit through the history (undoable). [validate]: a person's
  /// command — checked against the rules first, refused with its violations
  /// ([onCommandRefused]), and once made told to [onEventChange].
  RunResult run(Command cmd, {bool validate = false}) {
    final r = kernel.run(cmd, validate: validate);
    if (validate && !r.ok) {
      final refused = onCommandRefused;
      if (refused != null) _guard(() => refused(r.result, cmd));
    }
    return r;
  }

  static bool _sameSelection(CalendarSelection? a, CalendarSelection? b) => switch ((a, b)) {
    (null, null) => true,
    (DaySelection x, DaySelection y) => x.start == y.start && x.end == y.end && x.resourceId == y.resourceId,
    (TimeSelection x, TimeSelection y) =>
      x.start.instant == y.start.instant &&
          x.end.instant == y.end.instant &&
          x.resourceId == y.resourceId &&
          x.skipped == y.skipped,
    _ => false,
  };

  /// Undoes the last change (told to [onEventChange] as an undo).
  bool undo() => kernel.history.undo();
  bool redo() => kernel.history.redo();

  /// Selects (null: clears). [selectionListenable]'s listeners are told.
  void select(CalendarSelection? selection) {
    if (_disposed || _sameSelection(_selection.value, selection)) return;
    _selection.value = selection;
  }

  /// Today's date and running events follow the clock: the widgets call
  /// it each minute while shown.
  void tick() {
    kernel.refreshToday();
    kernel.refreshOngoing();
  }

  void _onKernel(KernelEvent e) {
    // A selection belongs to the days it was made on: another period, view,
    // zone or set of resources clears it.
    if (e is KernelStateEvent && e.causes.any(_clears.contains)) _selection.value = null;
    if (e is KernelStoreEvent) _tell(e);
    _pending.add(e);
    _schedule();
  }

  /// A person's change, said at once (a revert asked inside the callback is
  /// done as soon as the write is over); never one a revert itself made.
  void _tell(KernelStoreEvent e) {
    final tell = onEventChange;
    if (tell == null || _reverting) return;
    final c0 = e.change.cause;
    if (_skipRevertWrite && (c0 == ChangeCause.undo || c0 == ChangeCause.redo)) {
      _skipRevertWrite = false;
      return;
    }
    final cause = switch (e.change.cause) {
      ChangeCause.command when e.validated && e.command != null => EventChangeCause.command,
      ChangeCause.undo => EventChangeCause.undo,
      ChangeCause.redo => EventChangeCause.redo,
      _ => null,
    };
    final applied = e.change.applied;
    if (cause == null || applied.isEmpty) return;
    _telling = true;
    try {
      _tellNow(tell, cause, e, applied);
    } finally {
      _telling = false;
    }
  }

  void _tellNow(void Function(EventChange) tell, EventChangeCause cause, KernelStoreEvent e, List<Mutation> applied) {
    _guard(
      () => tell(
        EventChange._(
          cause: cause,
          command: cause == EventChangeCause.command ? e.command : null,
          applied: applied,
          revert: () {
            if (_disposed) return false;
            _reverting = true;
            try {
              final done = kernel.history.revert(applied);
              // Asked during the change's own announcement: deferred, written after it.
              if (done && _telling) _skipRevertWrite = true;
              return done;
            } finally {
              _reverting = false;
            }
          },
          canRevert: () => !_disposed && kernel.history.canRevert(applied),
        ),
      ),
    );
  }

  /// An app callback that throws is reported; the calendar goes on.
  void _guard(void Function() fn) {
    try {
      fn();
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  static const _clears = {StateCause.navigate, StateCause.view, StateCause.zone, StateCause.resources};

  void _schedule() {
    if (_disposed || _scheduled) return;
    // In a microtask: after whatever runs now — a build (a frame's, or the
    // first one `runApp` makes outside any frame), a layout, a gesture —
    // and before the next frame. Several changes, one notification.
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      _deliver();
    });
  }

  void _deliver() {
    if (_disposed) return;
    _delivered = List.of(_pending);
    _pending.clear();
    notifyListeners();
  }

  /// Stops listening; disposes the kernel it made (which leaves a shared
  /// store as it is), not one handed to [CalendarController.of].
  @override
  void dispose() {
    _disposed = true;
    _unsubscribe();
    _selection.dispose();
    if (_ownsKernel) kernel.dispose();
    super.dispose();
  }
}

/// Why an [EventChange] happened.
enum EventChangeCause {
  /// A command a person asked for (a gesture, the menu).
  command,

  /// Their undo of one.
  undo,

  /// Their redo of one.
  redo,
}

/// One event or series as a change left it: [before] null when it was
/// created, [after] null when it was removed.
final class ChangedItem<T> {
  const ChangedItem(this.before, this.after);
  final T? before;
  final T? after;
}

/// A person's change to the calendar, for the app to persist (owner's
/// decision 37): what it touched, and how to take exactly it back.
final class EventChange {
  EventChange._({
    required this.cause,
    required this.command,
    required List<Mutation> applied,
    required bool Function() revert,
    required bool Function() canRevert,
  }) : _revert = revert,
       _canRevert = canRevert,
       events = List.unmodifiable([
         for (final m in applied)
           if (m is EventMutation) ChangedItem<CalEvent>(m.before, m.after),
       ]),
       series = List.unmodifiable([
         for (final m in applied)
           if (m is SeriesMutation) ChangedItem<Series>(m.before, m.after),
       ]);

  final EventChangeCause cause;

  /// The command (null for an undo or a redo).
  final Command? command;

  /// Every event it touched (an occurrence edited becomes an override: its
  /// series is in [series]).
  final List<ChangedItem<CalEvent>> events;
  final List<ChangedItem<Series>> series;

  final bool Function() _revert;
  final bool Function() _canRevert;

  /// The first event touched, before and after (most commands touch one).
  CalEvent? get before => events.isEmpty ? null : events.first.before;
  CalEvent? get after => events.isEmpty ? null : events.first.after;

  /// Takes back exactly this change (not "the last one"): the server refused
  /// it. False, and nothing done, when the events changed again since. An
  /// undo's revert redoes it. Not told itself as a change.
  bool revert() => _revert();

  /// Whether [revert] would take it back now, nothing done.
  bool get canRevert => _canRevert();
}
