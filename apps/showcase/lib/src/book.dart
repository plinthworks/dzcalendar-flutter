import 'package:dzcalendar/dzcalendar.dart';
import 'package:dzcalendar_core/dzcalendar_core.dart'
    show
        ChangeCause,
        EventMutation,
        Mutation,
        NormalizeContext,
        Normalized,
        SeriesMutation,
        createIdGenerator,
        datesWindow,
        exportInputs,
        normalizeMany,
        serializeRRule;
import 'package:dzcalendar_core/ical.dart';
import 'package:flutter/material.dart';

/// The key, in an event's `extendedProps`, of the calendar it belongs to.
/// An event keeps it through every edit (moves, overrides, a series cut in
/// two), whoever holds it in the store — a source or the app.
const calendarKey = 'calendar';
const placeKey = 'location';
const notesKey = 'notes';

/// One calendar of the sidebar.
class ShowCalendar {
  ShowCalendar({required this.id, required this.name, required this.color, this.readOnly = false});

  final String id;

  /// Its name in the app's words (a demo calendar) or as a file gave it.
  final String Function(BuildContext context) name;
  final Color color;
  final bool readOnly;
  bool visible = true;
}

/// A search hit: one occurrence.
class Found {
  const Found(this.instance, this.calendar, this.date);
  final EventInstance instance;
  final ShowCalendar calendar;
  final PlainDate date;
}

/// The showcase's calendars over one [CalendarController] (owner's decision
/// 46): each calendar is a source of its own (`replaceSourceChunk`), and
/// unticking it takes its events out of the store, kept aside as inputs
/// until it is ticked again. While shown, the store is the truth: moves,
/// edits, undo and redo all happen there.
class CalendarBook extends ChangeNotifier {
  CalendarBook(this.controller);

  final CalendarController controller;
  final List<ShowCalendar> calendars = [];
  final Map<String, List<EventInput>> _hidden = {};
  // Not the kernel's prefix: ids made here never meet the ones it makes.
  final _newId = createIdGenerator('show');
  var _imports = 0;

  static const palette = [
    Color(0xFF0E7C66), // DZ green
    Color(0xFF3F6FD8),
    Color(0xFFE0752D),
    Color(0xFF9C4FC4),
    Color(0xFFD23F57),
    Color(0xFF2B9AA8),
    Color(0xFF8A6D3B),
  ];

  ShowCalendar? byId(String? id) {
    for (final c in calendars) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// The calendar an event or a series is in. An occurrence and an
  /// override are their series' (a series is in one calendar).
  ShowCalendar? calendarOf(Object eventOrSeries) {
    final props = switch (eventOrSeries) {
      CalEvent(ref: final ref?) =>
        controller.kernel.store.snapshot.getSeries(ref.seriesId)?.base.props ?? eventOrSeries.props,
      CalEvent e => e.props,
      Series s => s.base.props,
      _ => const <String, Object?>{},
    };
    return byId(props[calendarKey] as String?);
  }

  Iterable<ShowCalendar> get writable => calendars.where((c) => !c.readOnly);

  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Adds a calendar and delivers its events. Returns what reading them
  /// said: normalizing, and the store (an id another calendar holds).
  List<Problem> add(ShowCalendar calendar, List<EventInput> inputs, {String? idPrefix}) {
    // A file read after the page closed (the bundled holidays, an import).
    if (_disposed) return const [];
    calendars.add(calendar);
    final problems = _deliver(calendar, [for (final i in inputs) tagged(i, calendar, idPrefix: idPrefix)]);
    notifyListeners();
    return problems;
  }

  /// Delivers [inputs] as [calendar]'s chunk — with what that chunk holds
  /// that has moved to another calendar since (a delivery is the whole
  /// chunk: left out, it would be withdrawn from the calendar it is in now).
  List<Problem> _deliver(ShowCalendar calendar, List<EventInput> inputs) {
    final r = _normalize(calendar.id, [for (final i in inputs) tagged(i, calendar), ..._movedOut(calendar)]);
    final change = controller.kernel.store.replaceSourceChunk(calendar.id, '*', r.items);
    return [...r.report.problems, ...change.problems];
  }

  /// What [calendar]'s chunk delivered that is in another calendar now.
  List<EventInput> _movedOut(ShowCalendar calendar) => exportInputs(
    controller.kernel.store.snapshot,
    keep: (o) => calendarOf(o) != calendar && _sourceIdOf(o) == calendar.id,
  );

  ({List<Normalized> items, NormalizationReport report}) _normalize(String sourceId, List<EventInput> inputs) {
    final kernel = controller.kernel;
    return normalizeMany(
      inputs,
      NormalizeContext(displayZone: kernel.state.timeZone, newId: _newId, now: kernel.now),
      sourceId: sourceId,
    );
  }

  void setVisible(ShowCalendar calendar, bool visible) {
    if (_disposed || calendar.visible == visible) return;
    calendar.visible = visible;
    if (visible) {
      _deliver(calendar, _hidden.remove(calendar.id) ?? const []);
    } else {
      final store = controller.kernel.store;
      final snap = store.snapshot;
      bool mine(Object o) => calendarOf(o) == calendar;
      _hidden[calendar.id] = exportInputs(snap, keep: mine);
      // What the source delivered goes with its chunk; what was made here
      // (a new event, an override, the part of a cut series) goes by hand.
      // Delivered by this source but moved to another calendar since: stays.
      final moved = _normalize(calendar.id, _movedOut(calendar)).items;
      final local = <Mutation>[
        for (final s in snap.allSeries)
          if (mine(s) && s.sourceId != calendar.id) SeriesMutation(before: s),
        for (final e in snap.allEvents)
          if (mine(e) && e.sourceId != calendar.id) EventMutation(before: e),
      ];
      controller.batch(() {
        store.replaceSourceChunk(calendar.id, '*', moved);
        if (local.isNotEmpty) store.apply(local, ChangeCause.api);
      });
    }
    notifyListeners();
  }

  static String? _sourceIdOf(Object o) => switch (o) {
    CalEvent e => e.sourceId,
    Series s => s.sourceId,
    _ => null,
  };

  /// An .ics text as a new calendar (named as the file says, else
  /// [fallbackName]). Null when it holds no event.
  ({ShowCalendar calendar, int count, List<Problem> problems})? importIcs(
    String text, {
    String fallbackName = 'iCalendar',
    String? id,
    String Function(BuildContext context)? name,
    Color? color,
    bool readOnly = false,
  }) {
    final parsed = parseICal(text, defaultZone: controller.state.timeZone);
    if (parsed.events.isEmpty) return null;
    final fileName = parsed.calendar.name ?? fallbackName;
    final calendar = ShowCalendar(
      id: id ?? 'import-${++_imports}',
      name: name ?? (_) => fileName,
      color: color ?? palette[calendars.length % palette.length],
      readOnly: readOnly,
    );
    // Its own ids: a file read twice, or one written from here, is a calendar
    // of its own, not a clash with the events it was made from.
    final problems = add(calendar, parsed.events, idPrefix: '${calendar.id}/');
    return (calendar: calendar, count: parsed.events.length, problems: [...parsed.problems, ...problems]);
  }

  /// Every calendar, shown or not, as one .ics text; null when empty.
  String? exportIcs(String name) {
    final shown = exportInputs(controller.kernel.store.snapshot, keep: (o) => calendarOf(o) != null);
    final all = [...shown, for (final list in _hidden.values) ...list];
    if (all.isEmpty) return null;
    return serializeICal(all, prodId: '-//DzCalendar showcase//EN', name: name);
  }

  /// Occurrences whose title, place or notes hold [query], a year around
  /// [around], soonest first from [around].
  List<Found> search(String query, PlainDate around) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final zone = controller.state.timeZone;
    final hits = controller.kernel.store.snapshot.queryInstances(
      datesWindow(around.addDays(-366), around.addDays(366), zone),
    );
    bool matches(CalEvent e) =>
        e.title.toLowerCase().contains(q) ||
        '${e.props[placeKey] ?? ''}'.toLowerCase().contains(q) ||
        '${e.props[notesKey] ?? ''}'.toLowerCase().contains(q);
    final found = <Found>[];
    for (final i in hits) {
      final cal = calendarOf(i.event);
      if (cal == null || !matches(i.event)) continue;
      found.add(Found(i, cal, startDate(i.event, zone)));
    }
    int distance(Found f) => around.daysUntil(f.date);
    found.sort((a, b) {
      final da = distance(a), db = distance(b);
      // Upcoming first, by date; then the past, most recent first.
      if ((da >= 0) != (db >= 0)) return da >= 0 ? -1 : 1;
      return da >= 0 ? da.compareTo(db) : db.compareTo(da);
    });
    return found.take(100).toList();
  }

  /// The rule of a series as a preset of the inspector, or null (custom).
  static RepeatPreset? presetOf(Series? s) {
    if (s == null) return RepeatPreset.never;
    final rules = s.set.rules;
    if (rules.length != 1 || s.set.rdates.isNotEmpty) return null;
    final text = serializeRRule(rules.first).replaceAll(RegExp(r';?WKST=[A-Z]{2}'), '');
    for (final p in RepeatPreset.values) {
      if (p.rule == text) return p;
    }
    return null;
  }
}

enum RepeatPreset {
  never(null),
  daily('FREQ=DAILY'),
  weekly('FREQ=WEEKLY'),
  monthly('FREQ=MONTHLY'),
  yearly('FREQ=YEARLY');

  const RepeatPreset(this.rule);
  final String? rule;
}

PlainDate startDate(CalEvent e, ZoneId zone) => switch (e) {
  TimedEvent(:final start) => ZonedDateTime(start.instant, zone).date,
  AllDayEvent(:final start) => start,
};

/// [i] marked as [calendar]'s; read-only when the calendar is. [idPrefix]
/// goes before its ids (its own and its series').
EventInput tagged(EventInput i, ShowCalendar calendar, {String? idPrefix}) => EventInput(
  id: i.id == null || idPrefix == null ? i.id : '$idPrefix${i.id}',
  groupId: i.groupId,
  title: i.title,
  start: i.start,
  end: i.end,
  duration: i.duration,
  allDay: i.allDay,
  timeZone: i.timeZone,
  resourceId: i.resourceId,
  resourceIds: i.resourceIds,
  rrule: i.rrule,
  exdate: i.exdate,
  rdate: i.rdate,
  seriesId: i.seriesId == null || idPrefix == null ? i.seriesId : '$idPrefix${i.seriesId}',
  recurrenceId: i.recurrenceId,
  display: i.display,
  status: i.status,
  busy: i.busy,
  editable: calendar.readOnly ? false : i.editable,
  startEditable: i.startEditable,
  durationEditable: i.durationEditable,
  resourceEditable: i.resourceEditable,
  classNames: i.classNames,
  tone: i.tone,
  url: i.url,
  extendedProps: {...?i.extendedProps, calendarKey: calendar.id},
  ongoing: i.ongoing,
);
