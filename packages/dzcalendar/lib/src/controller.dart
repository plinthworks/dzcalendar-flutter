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
  CalendarController(KernelOptions options, {this.followAppLocale = true})
    : kernel = CalendarKernel(_withErrors(options)),
      _ownsKernel = true {
    _unsubscribe = kernel.subscribe(_onKernel);
  }

  /// Wraps a kernel made elsewhere (shared with a server-side model, a test).
  /// Its `onError` is the kernel's own, and [dispose] leaves it running.
  CalendarController.of(this.kernel, {this.followAppLocale = false}) : _ownsKernel = false {
    _unsubscribe = kernel.subscribe(_onKernel);
  }

  final CalendarKernel kernel;

  /// The calendar takes the app's locale (`Localizations.localeOf`) when a
  /// [DzCalendar] is built; false: [setLocale] only.
  final bool followAppLocale;
  final bool _ownsKernel;

  late final void Function() _unsubscribe;
  final _pending = <KernelEvent>[];
  var _scheduled = false;
  var _disposed = false;
  CalendarSelection? _selection;

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

  /// What the user has selected (a tap on a slot or a day), shared by every
  /// widget on this controller.
  CalendarSelection? get selection => _selection;

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
  NormalizationReport setEvents(List<EventInput> events) => kernel.setEvents(events);
  List<Problem> setResources(List<ResourceInput> next) => kernel.setResources(next);

  /// Several changes, one notification.
  void batch(void Function() fn) => kernel.batch(fn);

  /// Runs an edit through the history (undoable). [validate]: checked
  /// against the rules first, refused with its violations.
  RunResult run(Command cmd, {bool validate = false}) => kernel.run(cmd, validate: validate);
  bool undo() => kernel.history.undo();
  bool redo() => kernel.history.redo();

  /// Selects (null: clears). Listeners are told.
  void select(CalendarSelection? selection) {
    if (_selection == selection) return;
    _selection = selection;
    _schedule();
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
    if (e is KernelStateEvent && e.causes.any(_clears.contains)) _selection = null;
    _pending.add(e);
    _schedule();
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
    if (_ownsKernel) kernel.dispose();
    super.dispose();
  }
}
