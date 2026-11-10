import 'dart:async';

import 'calendars/hijri.dart';
import 'commands/history.dart';
import 'commands/types.dart';
import 'event/normalize.dart';
import 'event/problem.dart';
import 'event/types.dart';
import 'format/format.dart';
import 'interaction/propose.dart';
import 'project/time_axis.dart';
import 'resource/rows.dart';
import 'resource/tree.dart';
import 'rules/business_hours.dart';
import 'source/manager.dart';
import 'source/source.dart';
import 'rules/constraint.dart';
import 'rules/validate.dart';
import 'store/changes.dart';
import 'store/store.dart';
import 'time/instant.dart';
import 'time/plain.dart';
import 'util/equality.dart';
import 'views/daygrid.dart';
import 'views/list.dart';
import 'views/timegrid.dart';
import 'views/views.dart' hide navigate;
import 'views/views.dart' as views show navigate;
import 'zone/day_info.dart';
import 'zone/zone_rules.dart';
import 'zone/zoned.dart';

/// A time grid's settings (the kernel adds the zone, business hours, slots
/// and resources).
final class TimeGridSettings {
  const TimeGridSettings({
    this.axis = AxisMode.wall,
    this.slotMin = Duration.zero,
    this.slotMax = const Duration(hours: 24),
    this.minEventMinutes = 15,
    this.slotMinutes = 60,
    this.labelMinutes = 60,
    this.maxStack,
  });

  final AxisMode axis;
  final Duration slotMin;
  final Duration slotMax;
  final double minEventMinutes;

  /// Whole minutes, 1 to 1440.
  final int slotMinutes;
  final int labelMinutes;
  final int? maxStack;

  /// Throws an [ArgumentError] on settings no grid can draw: configuration,
  /// said when it is given, never while drawing.
  void check() {
    for (final (k, v) in [('slotMinutes', slotMinutes), ('labelMinutes', labelMinutes)]) {
      if (v < 1 || v > 1440) throw ArgumentError.value(v, k, 'whole minutes from 1 to 1440');
    }
    if (slotMin.isNegative || slotMax > const Duration(hours: 24) || slotMin >= slotMax) {
      throw ArgumentError('timeGrid: 0 ≤ slotMin < slotMax ≤ 24 h (got $slotMin–$slotMax)');
    }
  }

  TimeGridSettings copyWith({
    AxisMode? axis,
    Duration? slotMin,
    Duration? slotMax,
    double? minEventMinutes,
    int? slotMinutes,
    int? labelMinutes,
    int? maxStack,
  }) => TimeGridSettings(
    axis: axis ?? this.axis,
    slotMin: slotMin ?? this.slotMin,
    slotMax: slotMax ?? this.slotMax,
    minEventMinutes: minEventMinutes ?? this.minEventMinutes,
    slotMinutes: slotMinutes ?? this.slotMinutes,
    labelMinutes: labelMinutes ?? this.labelMinutes,
    maxStack: maxStack ?? this.maxStack,
  );

  @override
  bool operator ==(Object other) =>
      other is TimeGridSettings &&
      other.axis == axis &&
      other.slotMin == slotMin &&
      other.slotMax == slotMax &&
      other.minEventMinutes == minEventMinutes &&
      other.slotMinutes == slotMinutes &&
      other.labelMinutes == labelMinutes &&
      other.maxStack == maxStack;

  @override
  int get hashCode => Object.hash(axis, slotMin, slotMax, minEventMinutes, slotMinutes, labelMinutes, maxStack);
}

/// A day grid's settings: the lanes a day shows before "+N" (null: all).
final class DayGridSettings {
  const DayGridSettings({this.maxLanes});
  final int? maxLanes;

  void check() {
    final m = maxLanes;
    if (m != null && m < 1) throw ArgumentError.value(m, 'maxLanes', 'at least 1');
  }

  @override
  bool operator ==(Object other) => other is DayGridSettings && other.maxLanes == maxLanes;

  @override
  int get hashCode => maxLanes.hashCode;
}

/// What shapes the models; replaced whole with [CalendarKernel.setOptions]
/// (`kernel.options.copyWith(...)`): equal options change nothing.
final class ModelOptions {
  const ModelOptions({
    this.timeGrid = const TimeGridSettings(),
    this.dayGrid = const DayGridSettings(),
    this.businessHours,
    this.availableSlots = const [],
    this.hiddenDays = const [],
    this.resourceOrder,
    this.resourceGroupField,
    this.showUnassigned = false,
    this.eventFilter,
  });

  final TimeGridSettings timeGrid;
  final DayGridSettings dayGrid;

  /// The hours a place is open: shaded outside in the time grid and checked by the rules.
  final BusinessHours? businessHours;

  /// Bookable slots drawn in the time grid.
  final List<AvailableSlot> availableSlots;

  /// Weekdays no view shows (ISO: 6 and 7 for the weekend), unless a view names its own.
  final List<int> hiddenDays;

  /// How sibling resources are ordered after their `order`.
  final ResourceOrder? resourceOrder;

  /// Resource views group their columns by this field.
  final String? resourceGroupField;

  /// Resource views add an "Unassigned" column first, for events on no known resource.
  final bool showUnassigned;

  /// Only the events it keeps are shown, in every view: calendars ticked
  /// off, a practitioner's own patients. A series is asked once, with its
  /// base event — its occurrences go or stay together; a changed occurrence
  /// is asked with its own event (its `ref` names the series). So a test on
  /// what all of a series shares (a prop, a resource, a tone) is exact; one
  /// on a date or a title is the base's for every unchanged occurrence.
  ///
  /// It hides, nothing more: the store keeps every event, and the rules
  /// (overlap, constraints) and slot searches still see them all — a drop on
  /// a hidden event can be refused as an overlap. Compared with `==`: a new
  /// closure when what it keeps changes; the same function (or a tear-off of
  /// the same method) again changes nothing. One that throws is reported
  /// once (`onError`) and shows its events: it is not a way to keep secrets.
  final bool Function(CalEvent event)? eventFilter;

  ModelOptions copyWith({
    TimeGridSettings? timeGrid,
    DayGridSettings? dayGrid,
    BusinessHours? businessHours,
    bool clearBusinessHours = false,
    List<AvailableSlot>? availableSlots,
    List<int>? hiddenDays,
    ResourceOrder? resourceOrder,
    String? resourceGroupField,
    bool? showUnassigned,
    bool Function(CalEvent event)? eventFilter,
    bool clearEventFilter = false,
  }) => ModelOptions(
    timeGrid: timeGrid ?? this.timeGrid,
    dayGrid: dayGrid ?? this.dayGrid,
    businessHours: clearBusinessHours ? null : businessHours ?? this.businessHours,
    availableSlots: availableSlots ?? this.availableSlots,
    hiddenDays: hiddenDays ?? this.hiddenDays,
    resourceOrder: resourceOrder ?? this.resourceOrder,
    resourceGroupField: resourceGroupField ?? this.resourceGroupField,
    showUnassigned: showUnassigned ?? this.showUnassigned,
    eventFilter: clearEventFilter ? null : eventFilter ?? this.eventFilter,
  );

  bool _sameDays(List<int> a, List<int> b) => deepEquals([...a]..sort(), [...b]..sort());

  /// Slots compare by content: the same slots in a new list (a widget's next
  /// build) change nothing.
  @override
  bool operator ==(Object other) =>
      other is ModelOptions &&
      other.timeGrid == timeGrid &&
      other.dayGrid == dayGrid &&
      other.businessHours == businessHours &&
      deepEquals(other.availableSlots, availableSlots) &&
      _sameDays(other.hiddenDays, hiddenDays) &&
      other.resourceOrder == resourceOrder &&
      other.resourceGroupField == resourceGroupField &&
      other.showUnassigned == showUnassigned &&
      other.eventFilter == eventFilter;

  @override
  int get hashCode => Object.hash(timeGrid, dayGrid, businessHours, resourceGroupField, showUnassigned, eventFilter);
}

/// What a title written by the application is given: the first and last days shown.
final class TitleFormatArg {
  const TitleFormatArg({required this.start, required this.end, required this.view, required this.locale});
  final PlainDate start;

  /// The last day shown.
  final PlainDate end;
  final String view;
  final String locale;
}

/// How the title is written: an ICU skeleton (a range when the first and
/// last days differ), or a function.
sealed class TitleFormat {
  const TitleFormat();
  const factory TitleFormat.skeleton(String skeleton) = TitleSkeleton;
  const factory TitleFormat.builder(String Function(TitleFormatArg arg) build) = TitleBuilder;
}

final class TitleSkeleton extends TitleFormat {
  const TitleSkeleton(this.skeleton);
  final String skeleton;
}

final class TitleBuilder extends TitleFormat {
  const TitleBuilder(this.build);
  final String Function(TitleFormatArg arg) build;
}

/// What edits are checked against (the zone, business hours and resources
/// come from the kernel).
final class CalendarRules {
  const CalendarRules({this.constraint, this.overlap, this.allow, this.validRange});
  final ConstraintSpec? constraint;
  final OverlapFn? overlap;
  final bool Function(Placement p)? allow;
  final ValidRange? validRange;
}

final class KernelOptions {
  const KernelOptions({
    required this.timeZone,
    required this.locale,
    this.firstDay,
    this.titleFormat,
    this.initialDate,
    this.initialView = 'timeGridWeek',
    this.views = const {},
    this.store,
    this.events,
    this.now,
    this.rules,
    this.historyLimit = 200,
    this.resources = const [],
    this.options = const ModelOptions(),
    this.onError,
    this.displayCalendar,
    this.secondaryCalendar,
    this.sources = const [],
    this.onSource,
    this.timers = const SystemTimers(),
  });

  /// Fetched as the calendar moves (owner's decision 54); `kernel.sources`
  /// adds, removes, fetches again. Read once: what a source says while the
  /// kernel is being made (a synchronous source's problems) reaches
  /// [onSource], not subscribers — there are none yet.
  final List<EventSourceSpec> sources;

  /// Loading, fetch errors, problems in a delivery (also a
  /// [KernelSourceEvent] to subscribers).
  final void Function(SourceNotice notice)? onSource;

  /// For retries; injectable for tests.
  final Timers timers;

  /// The calendar dates are written in (owner's decision 53): titles, day
  /// numbers, labels. The data and the grids stay Gregorian. Null: the
  /// Gregorian calendar.
  final HijriCalendar? displayCalendar;

  /// A second calendar written beside the dates (a cell's day, a heading).
  /// Null: none.
  final HijriCalendar? secondaryCalendar;

  /// Where a subscriber's or a title builder's error goes (it never stops
  /// the others). Default: the current zone's uncaught-error handler; the
  /// Flutter controller routes it to `FlutterError.reportError`.
  final void Function(Object error, StackTrace stack)? onError;

  final ZoneId timeZone;

  /// A BCP 47 tag (`fr`, `en-US`, `ar-DZ`): titles, names, the week.
  final String locale;

  /// ISO weekday the week starts on. Default: the locale's.
  final int? firstDay;
  final TitleFormat? titleFormat;

  /// Default: today in [timeZone].
  final PlainDate? initialDate;
  final String initialView;

  /// Added to (and overriding) the built-in views, by type.
  final Map<String, ViewSpec> views;

  /// A store to share: four kernels on one store show the same events in four zones.
  final EventStore? store;

  /// Loaded as the source "events"; replaced with [CalendarKernel.setEvents].
  final List<EventInput>? events;

  /// Injectable for tests. Default: the system clock.
  final Instant Function()? now;
  final CalendarRules? rules;

  /// Undo entries kept.
  final int historyLimit;

  /// What resource views show as columns ([CalendarKernel.setResources] replaces them).
  final List<ResourceInput> resources;
  final ModelOptions options;
}

final class KernelState {
  const KernelState({
    required this.date,
    required this.view,
    required this.range,
    required this.timeZone,
    required this.locale,
    required this.firstDay,
    required this.title,
    required this.today,
    this.displayCalendar,
    this.secondaryCalendar,
  });
  final PlainDate date;
  final ViewSpec view;
  final ViewRange range;
  final ZoneId timeZone;
  final String locale;
  final int firstDay;
  final String title;
  final PlainDate today;

  /// The calendar dates are written in; null: Gregorian.
  final HijriCalendar? displayCalendar;

  /// The calendar written beside; null: none.
  final HijriCalendar? secondaryCalendar;

  /// [date] in the display calendar, by [skeleton] ("d", "yMMMM"…).
  String formatDate(PlainDate date, String skeleton) => formatInCalendar(date, skeleton, locale, displayCalendar);

  /// [date] in the secondary calendar; null when there is none.
  String? formatSecondary(PlainDate date, String skeleton) {
    final c = secondaryCalendar;
    return c == null ? null : formatInCalendar(date, skeleton, locale, c);
  }
}

/// [date] by [skeleton] in [locale], in [calendar] (null: Gregorian).
String formatInCalendar(PlainDate date, String skeleton, String locale, HijriCalendar? calendar) =>
    formatTemporal(calendar == null ? date : calendar.fromDate(date), skeleton, locale);

enum StateCause { navigate, view, zone, locale, options, today, resources, calendar }

enum StateDirection { prev, next, other }

/// What the kernel tells its subscribers. Not sealed (owner's decision 26):
/// sources and the timeline will add kinds — keep a default branch.
abstract class KernelEvent {
  const KernelEvent();
}

final class KernelStateEvent extends KernelEvent {
  const KernelStateEvent(this.state, this.causes, [this.direction]);
  final KernelState state;

  /// Every cause since the last event: a batch of three changes is one event with three causes.
  final List<StateCause> causes;

  /// Which way the dates moved, when they moved.
  final StateDirection? direction;
}

/// What the sources say: loading, a failed fetch, problems in a delivery.
final class KernelSourceEvent extends KernelEvent {
  const KernelSourceEvent(this.notice);
  final SourceNotice notice;
}

final class KernelStoreEvent extends KernelEvent {
  const KernelStoreEvent(this.change, {this.offscreen = false, this.command, this.validated = false});
  final StoreChange change;

  /// Nothing it touched is in the period shown (nor any series): nothing to redraw.
  final bool offscreen;

  /// The command that made it ([CalendarKernel.run]); [validated]: checked as a person's gesture.
  final Command? command;
  final bool validated;
}

/// The model of the current view, by family. Not sealed (owner's decision
/// 26): the timeline and custom families will add kinds — keep a default
/// branch.
abstract class ViewModel {
  const ViewModel();
  String get family;
}

final class TimeGridViewModel extends ViewModel {
  const TimeGridViewModel(this.model);
  final TimeGridModel model;
  @override
  String get family => 'timeGrid';
}

final class DayGridViewModel extends ViewModel {
  const DayGridViewModel(this.model);
  final DayGridModel model;
  @override
  String get family => 'dayGrid';
}

final class ListViewModel extends ViewModel {
  const ListViewModel(this.model);
  final ListModel model;
  @override
  String get family => 'list';
}

final class MultiMonthViewModel extends ViewModel {
  const MultiMonthViewModel(this.model);
  final MultiMonthModel model;
  @override
  String get family => 'multiMonth';
}

/// The families the kernel draws models for.
const kernelFamilies = {'timeGrid', 'dayGrid', 'list', 'multiMonth'};

Instant _systemNow() => Instant.fromEpochMilliseconds(DateTime.now().millisecondsSinceEpoch);

/// The calendar without a screen: date, view, zone, locale, options,
/// navigation, title, and the view model kept in step with the store
/// (owner's decision 22). Pure Dart: the Flutter `CalendarController` wraps
/// it. It has no timer of its own (`refreshToday`, `refreshOngoing` are
/// called by whoever has one).
///
/// Configuration errors (an unknown zone or view, settings no grid can
/// draw) throw an [ArgumentError] when given; data never does.
final class CalendarKernel {
  CalendarKernel(KernelOptions o)
    : _now = o.now ?? _systemNow,
      store = o.store ?? EventStore(),
      _timeZone = o.timeZone,
      _locale = o.locale,
      _firstDayGiven = o.firstDay,
      _titleFormat = o.titleFormat,
      _displayCalendar = o.displayCalendar,
      _secondaryCalendar = o.secondaryCalendar,
      _rulesGiven = o.rules,
      _options = o.options,
      _onErrorGiven = o.onError,
      _resourceInputs = o.resources {
    if (!isValidZone(o.timeZone)) throw ArgumentError.value(o.timeZone, 'timeZone', 'not a time zone');
    _checkOptions(o.options);
    final title = o.titleFormat;
    if (title is TitleSkeleton) checkSkeleton(title.skeleton);
    final given = o.firstDay;
    if (given != null && (given < 1 || given > 7)) throw ArgumentError.value(given, 'firstDay', 'an ISO weekday 1–7');
    _views = {...builtinViews};
    for (final MapEntry(key: type, value: spec) in o.views.entries) {
      final named = spec.type == type ? spec : spec.copyWith(type: type);
      assertViewSpec(named);
      _views[type] = named;
    }
    _firstDay = _firstDayGiven ?? weekRulesFor(_locale).firstDay;
    _date = o.initialDate ?? _todayIn(_timeZone);
    _raw = _viewOf(o.initialView);
    _view = _effectiveOf(_raw);
    _buildResources();
    _history = History.reading(store, _commandContext, limit: o.historyLimit);
    _state = _computeState(_date, _view);
    final onSource = o.onSource;
    sources = SourceManager(
      store: store,
      normalize: () => NormalizeContext(displayZone: _timeZone, newId: _idGen, now: _now),
      now: _now,
      timers: o.timers,
      forgotten: () => _forgottenBefore,
      // The `events` option is its own source, loaded apart.
      reserved: const ['events'],
      notify: (n) {
        if (onSource != null) {
          try {
            onSource(n);
          } catch (e, st) {
            _onError(e, st);
          }
        }
        _emit(KernelSourceEvent(n));
      },
    );
    final events = o.events;
    if (events != null) _loadEvents(events);
    _unsubscribe = store.subscribe(_onStore);
    for (final spec in o.sources) {
      sources.add(spec);
    }
    _fetchShown();
  }

  final Instant Function() _now;
  final void Function(Object, StackTrace)? _onErrorGiven;

  /// The zone current when the error happens, as the web reports in its own turn.
  void _onError(Object e, StackTrace st) => (_onErrorGiven ?? Zone.current.handleUncaughtError)(e, st);
  var _disposed = false;
  final EventStore store;
  ZoneId _timeZone;
  String _locale;
  int? _firstDayGiven;
  late int _firstDay;
  TitleFormat? _titleFormat;
  HijriCalendar? _displayCalendar;
  HijriCalendar? _secondaryCalendar;
  CalendarRules? _rulesGiven;
  ModelOptions _options;
  late final Map<String, ViewSpec> _views;
  late PlainDate _date;
  late ViewSpec _raw;
  late ViewSpec _view;
  List<ResourceInput> _resourceInputs;
  late ResourceTree _resourceTree;
  late List<Problem> _resourceProblems;
  late ColumnResources _columns;
  late final History _history;

  /// The sources: fetched for what the view shows, kept in step with the store.
  late final SourceManager sources;
  int? _forgottenBefore;
  late KernelState _state;
  late final void Function() _unsubscribe;
  final _idGen = createIdGenerator('ev');
  NormalizationReport? _problems;
  ViewModel? _model;
  var _cut = <String, Problem>{};
  final _listeners = <void Function(KernelEvent)>{};
  var _held = 0;
  var _pending = <StateCause>[];
  StateDirection? _direction;
  var _validating = false;
  var _externalRun = false;
  Command? _running;
  final _effective = Expando<({String key, ViewSpec spec})>();
  ({bool Function(CalEvent) given, bool Function(CalEvent) safe})? _filter;

  // ——— reading ———

  KernelState get state => _state;
  ModelOptions get options => _options;
  ResourceTree get resources => _resourceTree;
  List<Problem> get resourceProblems => _resourceProblems;

  /// What the last `events` / [setEvents] load reported.
  NormalizationReport? get problems => _problems;
  History get history => _history;
  Instant now() => _now();

  /// The spec registered under [type], so a renderer can refuse a family
  /// before anything changes.
  ViewSpec? viewSpec(String type) => _views[type];

  /// What a gesture needs from the calendar now: the store's snapshot, the
  /// zone, the rules — for `proposeMove`, `proposeResize`, `selectionBetween`.
  InteractionContext interactionContext({
    required int snapMinutes,
    bool keepAllDay = false,
    String? movingSeries,
    bool external = false,
  }) => InteractionContext(
    snap: store.snapshot,
    displayZone: _timeZone,
    snapMinutes: snapMinutes,
    rules: rules(),
    keepAllDay: keepAllDay,
    movingSeries: movingSeries,
    external: external,
  );

  /// A guess the formatting made: the locale's language is not one `intl`
  /// knows, so titles and names are written in English (a warning, at
  /// `locale`). Null when the locale is known.
  Problem? get localeProblem {
    final f = formatLocale(_locale);
    return f.exact ? null : Problem(ProblemCode.invalidOption, Severity.warning, 'locale', '$_locale → ${f.used}');
  }

  /// What gestures are checked against now: the zone, business hours,
  /// resources, the rules given.
  RulesContext rules() {
    final r = _rulesGiven;
    return RulesContext(
      displayZone: _timeZone,
      businessHours: _options.businessHours,
      resources: _resourceTree.order.isEmpty ? null : _resourceTree,
      constraint: r?.constraint,
      overlap: r?.overlap,
      allow: r?.allow,
      validRange: r?.validRange,
    );
  }

  // ——— internals ———

  PlainDate _todayIn(ZoneId zone) => ZonedDateTime(_now(), zone).date;
  NavContext _nav() => NavContext(firstDay: _firstDay, today: _todayIn(_timeZone));

  ViewSpec _viewOf(String type) {
    final spec = _views[type];
    if (spec == null) throw ArgumentError.value(type, 'view', 'unknown view');
    if (!kernelFamilies.contains(spec.family)) throw ArgumentError.value(type, 'view', 'no model for ${spec.family}');
    return spec;
  }

  /// The spec in force: the calendar's hidden days laid on a view that names
  /// none. Cached, so its identity holds.
  ViewSpec _effectiveOf(ViewSpec spec) {
    if (spec.hiddenDays.isNotEmpty || _options.hiddenDays.isEmpty) return spec;
    final hidden = [..._options.hiddenDays]..sort();
    final key = hidden.join(',');
    final hit = _effective[spec];
    if (hit != null && hit.key == key) return hit.spec;
    final made = spec.copyWith(hiddenDays: hidden);
    _effective[spec] = (key: key, spec: made);
    return made;
  }

  void _checkOptions(ModelOptions o) {
    o.timeGrid.check();
    o.dayGrid.check();
    if (o.hiddenDays.toSet().length >= 7) throw ArgumentError('hiddenDays: every day of the week is hidden');
    for (final d in o.hiddenDays) {
      if (d < 1 || d > 7) throw ArgumentError.value(o.hiddenDays, 'hiddenDays', 'ISO weekdays 1–7');
    }
  }

  void _buildResources() {
    final built = buildResourceTree(_resourceInputs, orderBy: _options.resourceOrder);
    _resourceTree = built.tree;
    _resourceProblems = built.problems;
    _columns = columnResources(_resourceTree, _options.resourceGroupField);
  }

  CommandContext _commandContext() => CommandContext(
    normalize: NormalizeContext(displayZone: _timeZone, newId: _idGen, now: _now),
    weekStart: _firstDay,
    rules: _validating ? rules() : null,
    external: _validating && _externalRun,
  );

  NormalizationReport _loadEvents(List<EventInput> events) {
    final r = normalizeMany(
      events,
      NormalizeContext(displayZone: _timeZone, newId: _idGen, now: _now),
      sourceId: 'events',
    );
    store.replaceSourceChunk('events', '*', r.items);
    return _problems = r.report;
  }

  /// [d] as the display calendar writes it: itself (Gregorian), or its Hijri day.
  Object _inCalendar(PlainDate d) => _displayCalendar?.fromDate(d) ?? d;

  String _title(ViewRange range, ViewSpec spec) {
    // A month's or a year's period is its own days, not the grid's padding ones.
    final own =
        spec.alignment == ViewAlignment.month || spec.alignment == ViewAlignment.year || spec.visibleRange != null;
    final first = own || range.dates.isEmpty ? range.activeStart : range.dates.first;
    final last = own || range.dates.isEmpty ? range.activeEnd.addDays(-1) : range.dates.last;
    final fmt = _titleFormat;
    if (fmt != null) {
      try {
        switch (fmt) {
          case TitleBuilder(:final build):
            return build(TitleFormatArg(start: first, end: last, view: spec.type, locale: _locale));
          case TitleSkeleton(:final skeleton):
            return first == last
                ? formatTemporal(_inCalendar(first), skeleton, _locale)
                : formatRangeTitle(_inCalendar(first), _inCalendar(last), skeleton, _locale);
        }
      } catch (e, st) {
        // The application's bug is reported; the title is written as by default.
        _onError(e, st);
      }
    }
    // In the display calendar: a Gregorian month is two Hijri ones ("Shaʻ.–Ram. 1447 AH").
    final start = _inCalendar(range.activeStart);
    switch (spec.alignment) {
      case ViewAlignment.month:
        final end = _inCalendar(range.activeEnd.addDays(-1));
        final one = formatTemporal(start, 'yMMMM', _locale);
        return one == formatTemporal(end, 'yMMMM', _locale) ? one : formatRangeTitle(start, end, 'yMMM', _locale);
      case ViewAlignment.year:
        final end = _inCalendar(range.activeEnd.addDays(-1));
        final one = formatTemporal(start, 'y', _locale);
        return one == formatTemporal(end, 'y', _locale) ? one : formatRangeTitle(start, end, 'y', _locale);
      default:
        return first == last
            ? formatTemporal(_inCalendar(first), 'yMMMMEEEEd', _locale)
            : formatRangeTitle(_inCalendar(first), _inCalendar(last), 'yMMMd', _locale);
    }
  }

  KernelState _computeState(PlainDate at, ViewSpec spec) {
    final ctx = _nav();
    final range = computeViewRange(at, spec, ctx);
    return KernelState(
      date: at,
      view: spec,
      range: range,
      timeZone: _timeZone,
      locale: _locale,
      firstDay: _firstDay,
      title: _title(range, spec),
      today: ctx.today,
      displayCalendar: _displayCalendar,
      secondaryCalendar: _secondaryCalendar,
    );
  }

  /// One subscriber that throws must not starve the others: its error is
  /// reported, after the round.
  void _emit(KernelEvent e) {
    for (final fn in [..._listeners]) {
      try {
        fn(e);
      } catch (err, st) {
        _onError(err, st);
      }
    }
  }

  void _flush() {
    if (_held > 0 || _pending.isEmpty) return;
    final causes = {..._pending}.toList();
    _pending = [];
    final dir = _direction;
    _direction = null;
    _emit(KernelStateEvent(_state, List.unmodifiable(causes), dir));
  }

  /// The sources fetch what the view shows now.
  void _fetchShown() => sources.setRange(_state.range.start, _state.range.end, _timeZone);

  void _changeState(StateCause cause) {
    _state = _computeState(_date, _view);
    // The model first: a source answering at once lands on the new period's.
    _model = null;
    _pending.add(cause);
    _fetchShown();
    _flush();
  }

  /// Whether a change touches nothing of the period shown (a day wider each side).
  bool _offscreen(StoreChange change) {
    if (change.seriesTouched.isNotEmpty) return false;
    final lo = _state.range.start.startOfDayIn(_timeZone).epochMilliseconds - 86400000;
    final hi = _state.range.end.startOfDayIn(_timeZone).epochMilliseconds + 86400000;
    final loDay = (lo / 86400000).floor();
    final hiDay = (hi / 86400000).ceil();
    return change.dirtySpans.every((x) => x.e <= lo || x.s >= hi) &&
        change.dirtyDays.every((x) => x.e <= loDay || x.s >= hiDay);
  }

  void _onStore(StoreChange change) {
    final person =
        change.cause == ChangeCause.command || change.cause == ChangeCause.undo || change.cause == ChangeCause.redo;
    // Elsewhere than shown: the model stands, the view need not redraw.
    if (!person && _model != null && _offscreen(change)) {
      _emit(KernelStoreEvent(change, offscreen: true));
      return;
    }
    final m = _model;
    // The same wrapper when the model is the same object: nothing downstream redraws.
    _model = switch (m) {
      TimeGridViewModel(:final model) => () {
        final next = updateTimeGridModel(model, store.snapshot, change);
        return identical(next, model) ? m : TimeGridViewModel(next);
      }(),
      DayGridViewModel(:final model) => () {
        final next = updateDayGridModel(model, store.snapshot, change);
        return identical(next, model) ? m : DayGridViewModel(next);
      }(),
      MultiMonthViewModel(:final model) => () {
        final next = updateMultiMonthModel(model, store.snapshot, change);
        return identical(next, model) ? m : MultiMonthViewModel(next);
      }(),
      _ => null,
    };
    final running = _running;
    _emit(
      change.cause == ChangeCause.command && running != null
          ? KernelStoreEvent(change, command: running, validated: _validating)
          : KernelStoreEvent(change),
    );
  }

  ({List<Resource>? resources, List<ResourceGroupHead> groups}) _resourceOpts(ViewSpec view) {
    if (!view.resources) return (resources: null, groups: const []);
    final groups = groupHeadsOf(_columns);
    if (!_options.showUnassigned) return (resources: _columns.resources, groups: groups);
    return (
      resources: [unassignedResource, ..._columns.resources],
      groups: [for (final g in groups) ResourceGroupHead(value: g.value, from: g.from + 1, count: g.count)],
    );
  }

  /// The application's filter, its first error reported and the event
  /// kept. The same wrapper while the filter is the same.
  bool Function(CalEvent)? _filterOf(ModelOptions o) {
    final f = o.eventFilter;
    if (f == null) return null;
    final hit = _filter;
    if (hit != null && hit.given == f) return hit.safe;
    var reported = false;
    bool safe(CalEvent e) {
      try {
        return f(e);
      } catch (err, st) {
        // Once: a bad filter would say it for every event of every column.
        if (!reported) {
          reported = true;
          _onError(err, st);
        }
        return true;
      }
    }

    _filter = (given: f, safe: safe);
    return safe;
  }

  ViewModel _build(ViewRange range, ViewSpec view, ModelOptions o, void Function(Problem)? onProblem) {
    final snap = store.snapshot;
    final res = _resourceOpts(view);
    final filter = _filterOf(o);
    switch (view.family) {
      case 'timeGrid':
        final t = o.timeGrid;
        return TimeGridViewModel(
          buildTimeGridModel(
            range,
            snap,
            TimeGridOptions(
              displayZone: _timeZone,
              axis: t.axis,
              slotMin: t.slotMin,
              slotMax: t.slotMax,
              minEventMinutes: t.minEventMinutes,
              slotMinutes: t.slotMinutes.toDouble(),
              labelMinutes: t.labelMinutes,
              maxStack: t.maxStack,
              businessHours: o.businessHours,
              availableSlots: o.availableSlots,
              resources: res.resources,
              resourceGroups: res.groups,
              onProblem: onProblem,
              eventFilter: filter,
            ),
          ),
        );
      case 'dayGrid':
        return DayGridViewModel(
          buildDayGridModel(
            range,
            snap,
            DayGridOptions(
              displayZone: _timeZone,
              maxLanes: o.dayGrid.maxLanes,
              showNonCurrentDates: view.showNonCurrentDates,
              businessHours: o.businessHours,
              resources: res.resources,
              resourceGroups: res.groups,
              onProblem: onProblem,
              eventFilter: filter,
            ),
          ),
        );
      case 'multiMonth':
        return MultiMonthViewModel(
          buildMultiMonthModel(
            range,
            snap,
            DayGridOptions(
              displayZone: _timeZone,
              maxLanes: o.dayGrid.maxLanes,
              businessHours: o.businessHours,
              onProblem: onProblem,
              eventFilter: filter,
            ),
          ),
        );
      default:
        return ListViewModel(
          buildListModel(range, snap, ListOptions(displayZone: _timeZone, onProblem: onProblem, eventFilter: filter)),
        );
    }
  }

  // ——— changing ———

  void setView(String type, [PlainDate? at]) {
    _live();
    final spec = _viewOf(type);
    if (identical(spec, _raw) && (at == null || at == _date)) return;
    // The next state first: a view whose range cannot be made changes nothing.
    final next = _effectiveOf(spec);
    _computeState(at ?? _date, next);
    _raw = spec;
    _view = next;
    if (at != null) _date = at;
    _direction ??= StateDirection.other;
    _changeState(StateCause.view);
  }

  void navigate(NavDirection dir) {
    _live();
    final next = views.navigate(_date, _view, dir, _nav());
    if (next == _date) return;
    _direction ??= identical(dir, NavDirection.prev)
        ? StateDirection.prev
        : identical(dir, NavDirection.next)
        ? StateDirection.next
        : StateDirection.other;
    _date = next;
    _changeState(StateCause.navigate);
  }

  void setTimeZone(ZoneId zone) {
    _live();
    if (!isValidZone(zone)) throw ArgumentError.value(zone, 'zone', 'not a time zone');
    if (zone == _timeZone) return;
    // Not a store change: every column's days are different days now.
    _timeZone = zone;
    _changeState(StateCause.zone);
  }

  /// Titles, and the first weekday unless one was given, follow the new locale.
  void setLocale(String locale) {
    _live();
    if (locale == _locale) return;
    _locale = locale;
    if (_firstDayGiven == null) _firstDay = weekRulesFor(locale).firstDay;
    _changeState(StateCause.locale);
  }

  /// The week's first day (ISO); null: the locale's again.
  void setFirstDay(int? day) {
    _live();
    if (day != null && (day < 1 || day > 7)) throw ArgumentError.value(day, 'firstDay', 'an ISO weekday 1–7');
    _firstDayGiven = day;
    final next = day ?? weekRulesFor(_locale).firstDay;
    if (next == _firstDay) return;
    _firstDay = next;
    _changeState(StateCause.options);
  }

  /// The calendar dates are written in from now on (null: Gregorian): the
  /// title follows (a state event, cause `calendar`).
  void setDisplayCalendar(HijriCalendar? calendar) {
    _live();
    if (calendar == _displayCalendar) return;
    _displayCalendar = calendar;
    _changeState(StateCause.calendar);
  }

  /// The calendar written beside the dates (null: none).
  void setSecondaryCalendar(HijriCalendar? calendar) {
    _live();
    if (calendar == _secondaryCalendar) return;
    _secondaryCalendar = calendar;
    _changeState(StateCause.calendar);
  }

  /// How the title is written from now on (null: the default again).
  void setTitleFormat(TitleFormat? format) {
    _live();
    final was = _titleFormat;
    final same = switch ((was, format)) {
      (null, null) => true,
      (TitleSkeleton(skeleton: final a), TitleSkeleton(skeleton: final b)) => a == b,
      (TitleBuilder(build: final a), TitleBuilder(build: final b)) => identical(a, b),
      _ => false,
    };
    if (same) return;
    if (format is TitleSkeleton) checkSkeleton(format.skeleton);
    _titleFormat = format;
    _changeState(StateCause.options);
  }

  /// The rules gestures and checked commands are held to: read at every
  /// gesture and command, nothing to redraw.
  void setRules(CalendarRules? rules) => _rulesGiven = rules;

  /// The options in force from now on. Equal options change nothing and say
  /// nothing; [silent]: the model is made again but no state event is told
  /// (a renderer adjusting options while it handles one).
  void setOptions(ModelOptions next, {bool silent = false}) {
    _live();
    if (next == _options) return;
    _checkOptions(next);
    final was = _options;
    _options = next;
    // The view as these options make it, tried first: a fixed period whose days all become hidden changes nothing.
    final nextView = _effectiveOf(_raw);
    try {
      _computeState(_date, nextView);
    } catch (_) {
      _options = was;
      rethrow;
    }
    if (next.resourceOrder != was.resourceOrder || next.resourceGroupField != was.resourceGroupField) {
      _buildResources();
    }
    _view = nextView;
    if (silent) {
      _state = _computeState(_date, _view);
      _model = null;
      _fetchShown();
    } else {
      _changeState(StateCause.options);
    }
  }

  /// Replaces the "events" source. Unchanged events keep their objects and
  /// revisions (the store diffs), so the same content again redraws nothing.
  NormalizationReport setEvents(List<EventInput> events) {
    _live();
    return _loadEvents(events);
  }

  /// Several changes, one state event at the end.
  void batch(void Function() fn) {
    _held++;
    try {
      fn();
    } finally {
      _held--;
      _flush();
    }
  }

  /// Re-reads today from the clock (call it from a timer). True when it changed.
  bool refreshToday() {
    _live();
    if (_todayIn(_timeZone) == _state.today) return false;
    _changeState(StateCause.today);
    return true;
  }

  /// The events still running brought up to now: their ends moved (a store
  /// change, cause `api` — no undo). True when one moved.
  bool refreshOngoing() {
    _live();
    final at = _now();
    final moved = <Mutation>[];
    for (final e in store.snapshot.allEvents) {
      if (e is! TimedEvent || !e.ongoing || e.end.epochMilliseconds >= at.epochMilliseconds) continue;
      moved.add(
        EventMutation(
          before: e,
          after: e.copyWith(end: ZonedDateTime(at, e.end.zone)),
        ),
      );
    }
    if (moved.isEmpty) return false;
    store.apply(moved, ChangeCause.api);
    return true;
  }

  /// The events that ended before [at] leave the store (cause `api`: no
  /// undo) — single events and a series' changed occurrences; a series
  /// itself, and an event still running, stay. How many went.
  int forgetBefore(Instant at) {
    _live();
    // A source's next delivery does not bring them back.
    final ms = at.epochMilliseconds;
    final was = _forgottenBefore;
    _forgottenBefore = was == null || ms > was ? ms : was;
    final gone = <Mutation>[];
    for (final e in store.snapshot.allEvents) {
      if (e is TimedEvent && e.ongoing) continue;
      final end = switch (e) {
        AllDayEvent(:final end) => end.startOfDayIn(_timeZone).epochMilliseconds,
        TimedEvent(:final end) => end.epochMilliseconds,
      };
      if (end > at.epochMilliseconds) continue;
      gone.add(EventMutation(before: e));
    }
    if (gone.isNotEmpty) store.apply(gone, ChangeCause.api);
    return gone.length;
  }

  /// Memoized; after a store change only what changed is rebuilt.
  ViewModel viewModel() {
    final m = _model;
    if (m != null) return m;
    _cut = {};
    return _model = _build(_state.range, _view, _options, (p) => _cut[p.path] = p);
  }

  /// What building the shown model had to say: a series cut short there.
  List<Problem> get viewProblems => List.unmodifiable(_cut.values);

  /// Another view or date, as it would be shown — without changing what is
  /// shown (printing, exports). Null for an unknown view.
  KernelState? stateAt(String type, PlainDate at) {
    final raw = _views[type];
    return raw == null ? null : _computeState(at, _effectiveOf(raw));
  }

  /// Its model; [timeGrid] / [dayGrid] laid over the settings in force (a
  /// print lifts the "+N" caps). Not memoized.
  ViewModel? modelAt(String type, PlainDate at, {TimeGridSettings? timeGrid, DayGridSettings? dayGrid}) {
    final raw = _views[type];
    if (raw == null || !kernelFamilies.contains(raw.family)) return null;
    final spec = _effectiveOf(raw);
    final range = _computeState(at, spec).range;
    final o = _options.copyWith(timeGrid: timeGrid, dayGrid: dayGrid);
    return _build(range, spec, o, null);
  }

  /// Replaces the resources (a state event, cause `resources`). Returns what
  /// could not be read — never throws.
  List<Problem> setResources(List<ResourceInput> next) {
    _live();
    _resourceInputs = next;
    _buildResources();
    _changeState(StateCause.resources);
    return _resourceProblems;
  }

  void Function() subscribe(void Function(KernelEvent) fn) {
    _live();
    _listeners.add(fn);
    return () => _listeners.remove(fn);
  }

  /// Runs a command through the history: undoable; series created here take
  /// the locale's first day as WKST. [validate] checks it against the rules
  /// (constraint, overlap, allow, editable) — what a person's gesture asks
  /// for; the application's own calls and server pushes are not refused by
  /// them. [external]: it comes from outside this calendar (told to `allow`).
  RunResult run(Command cmd, {bool validate = false, bool external = false}) {
    _live();
    _validating = validate;
    _externalRun = external;
    _running = cmd;
    try {
      return _history.run(cmd);
    } finally {
      _validating = false;
      _externalRun = false;
      _running = null;
    }
  }

  /// Throws a [StateError] once disposed (as a `ChangeNotifier` does).
  void _live() {
    if (_disposed) throw StateError('CalendarKernel used after dispose()');
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    sources.destroy();
    _unsubscribe();
    _history.dispose();
    _listeners.clear();
  }
}
