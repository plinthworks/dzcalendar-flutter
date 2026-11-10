import 'package:dzcalendar/dzcalendar.dart';
import 'package:dzcalendar_core/dzcalendar_core.dart'
    show NormalizeContext, QueryOptions, createIdGenerator, datesWindow, exportInputs, normalizeMany, serializeRRule;
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
/// unticking it hides its events with the views' filter
/// (`ModelOptions.eventFilter`, decision 48) — they stay in the store, so
/// the history stays whole: an edit undone while its calendar is hidden
/// comes back when it is ticked again.
class CalendarBook extends ChangeNotifier {
  CalendarBook(this.controller);

  final CalendarController controller;
  final List<ShowCalendar> calendars = [];
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

  /// Adds a calendar and delivers its events (its source's one chunk).
  /// Returns what reading them said: normalizing, and the store (an id
  /// another calendar holds).
  List<Problem> add(ShowCalendar calendar, List<EventInput> inputs, {String? idPrefix}) {
    // A file read after the page closed (the bundled holidays, an import).
    if (_disposed) return const [];
    calendars.add(calendar);
    final kernel = controller.kernel;
    final r = normalizeMany(
      [for (final i in inputs) tagged(i, calendar, idPrefix: idPrefix)],
      NormalizeContext(displayZone: kernel.state.timeZone, newId: _newId, now: kernel.now),
      sourceId: calendar.id,
    );
    final change = kernel.store.replaceSourceChunk(calendar.id, '*', r.items);
    notifyListeners();
    return [...r.report.problems, ...change.problems];
  }

  /// Whether [e] is in a ticked calendar (an event in none is shown).
  bool isShown(CalEvent e) => calendarOf(e)?.visible ?? true;

  void setVisible(ShowCalendar calendar, bool visible) {
    if (_disposed || calendar.visible == visible) return;
    calendar.visible = visible;
    // A new function: the views are remade with it (the same one would change
    // nothing). All ticked: no filter at all.
    final all = calendars.every((c) => c.visible);
    controller.setOptions(
      all
          ? controller.options.copyWith(clearEventFilter: true)
          : controller.options.copyWith(eventFilter: (e) => isShown(e)),
    );
    notifyListeners();
  }

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
    final all = exportInputs(controller.kernel.store.snapshot, keep: (o) => calendarOf(o) != null);
    if (all.isEmpty) return null;
    return serializeICal(all, prodId: '-//DzCalendar showcase//EN', name: name);
  }

  /// Occurrences in ticked calendars whose title, place or notes hold
  /// [query], a year around [around], soonest first from [around].
  List<Found> search(String query, PlainDate around) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final zone = controller.state.timeZone;
    final hits = controller.kernel.store.snapshot.queryInstances(
      datesWindow(around.addDays(-366), around.addDays(366), zone),
      QueryOptions(where: isShown),
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
