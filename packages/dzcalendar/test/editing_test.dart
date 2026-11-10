// Phase 19e-2b-1: the gestures that edit (owner's decisions 35, 37, 40).
// Expectations are written by hand: Paris is UTC+1 in November; the grid's
// hour is 48 px (0.8 px a minute), so 48 px down is one hour later.
import 'package:dzcalendar/dzcalendar.dart';
import 'package:dzcalendar_core/dzcalendar_core.dart' show datesWindow;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _zone = 'Europe/Paris';
final _monday = PlainDate(2026, 11, 9);
final _now = _wall(_monday, 10, 20);

Instant _wall(PlainDate d, int h, int m) => ZonedDateTime.fromWall(PlainDateTime(d, PlainTime(h, m)), _zone)!.instant;

CalendarController _controller({
  String view = 'timeGridDay',
  List<EventInput> events = const [],
  CalendarRules? rules,
  void Function(EventChange)? onEventChange,
  void Function(CommandResult, Command)? onCommandRefused,
}) => CalendarController(
  KernelOptions(
    timeZone: _zone,
    locale: 'fr',
    initialDate: _monday,
    initialView: view,
    now: () => _now,
    events: events,
    rules: rules,
  ),
  onEventChange: onEventChange,
  onCommandRefused: onCommandRefused,
);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 800), bool reduceMotion = false}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size, disableAnimations: reduceMotion),
      child: MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
        localizationsDelegates: const [
          DzCalendarLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: w),
      ),
    ),
  );
  await t.pumpAndSettle();
}

EventInput _at(String id, String title, String start, String end, {String? rrule, bool? allDay}) =>
    EventInput(id: id, title: title, start: start, end: end, rrule: rrule, allDay: allDay);

/// The event's start and end as stored.
(Instant, Instant) _times(CalendarController c, String id) => switch (c.kernel.store.snapshot.getEvent(id)!) {
  TimedEvent(:final start, :final end) => (start.instant, end.instant),
  AllDayEvent() => throw StateError('all-day'),
};

/// A long press at [from], then the finger moved by [by] in a few steps, then lifted.
Future<void> _longDrag(WidgetTester t, Offset from, Offset by) async {
  final g = await t.startGesture(from);
  await t.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  for (var k = 1; k <= 4; k++) {
    await g.moveTo(from + by * (k / 4));
    await t.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await t.pumpAndSettle();
}

void main() {
  testWidgets('a long press grabs an event; dragged one hour down, it moves (told, revertable)', (t) async {
    final told = <EventChange>[];
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')], onEventChange: told.add);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await _longDrag(t, t.getCenter(find.text('Bilan')), const Offset(0, 48));
    expect(_times(c, 'a'), (_wall(_monday, 10, 0), _wall(_monday, 11, 0)));
    // Told once, as a person's command, before and after.
    expect(told, hasLength(1));
    final change = told.single;
    expect(change.cause, EventChangeCause.command);
    expect(change.command, isA<MoveEvent>());
    expect((change.before! as TimedEvent).start.instant, _wall(_monday, 9, 0));
    expect((change.after! as TimedEvent).start.instant, _wall(_monday, 10, 0));
    // The server refused it: exactly that change taken back, not told again.
    expect(change.canRevert, isTrue);
    expect(change.revert(), isTrue);
    await t.pumpAndSettle();
    expect(_times(c, 'a'), (_wall(_monday, 9, 0), _wall(_monday, 10, 0)));
    expect(told, hasLength(1));
    expect(change.revert(), isFalse, reason: 'already taken back');
  });

  testWidgets('a drag snaps to 15 minutes: 20 px down (25 min) starts at 09:30', (t) async {
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    // 25 minutes later than 09:00 is 09:25: on the wall clock's quarter hours, the nearest is 09:30.
    await _longDrag(t, t.getCenter(find.text('Bilan')), const Offset(0, 20));
    final (start, end) = _times(c, 'a');
    expect(end.epochMilliseconds - start.epochMilliseconds, 3600000, reason: 'a move keeps the length');
    expect(start.epochMilliseconds % (15 * 60000), 0, reason: 'on the 15-minute grid');
    expect(start, _wall(_monday, 9, 30));
  });

  testWidgets('not editable: a long press offers the menu, without editing entries', (t) async {
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, onEventTap: (_, _) {}));
    await t.longPress(find.text('Bilan'));
    await t.pumpAndSettle();
    expect(find.text('Ouvrir'), findsOneWidget);
    expect(find.text('Supprimer'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing, reason: 'nothing held');
  });

  testWidgets('held, its handle pulled 24 px down: it ends 30 minutes later', (t) async {
    final told = <EventChange>[];
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')], onEventChange: told.add);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await t.longPress(find.text('Bilan'));
    await t.pumpAndSettle();
    final handle = find.byWidgetPredicate((w) => w is GestureDetector && w.onVerticalDragStart != null);
    expect(handle, findsOneWidget);
    final from = t.getCenter(handle);
    final g = await t.startGesture(from);
    // The end keeps its distance from the finger: 24 px further is 30 minutes later.
    for (var k = 1; k <= 6; k++) {
      await g.moveTo(from + Offset(0, 24.0 * k / 6));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pumpAndSettle();
    expect(_times(c, 'a'), (_wall(_monday, 9, 0), _wall(_monday, 10, 30)));
    expect(told.single.command, isA<MoveEvent>().having((m) => m.end, 'end', isNotNull));
  });

  testWidgets('a place the rules refuse: the event goes back, nothing told, the refusal said', (t) async {
    final told = <EventChange>[];
    final refused = <CommandResult>[];
    final c = _controller(
      events: [
        _at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00'),
        _at('b', 'Garde', '2026-11-09T10:00', '2026-11-09T11:00'),
      ],
      // No two events at once.
      rules: CalendarRules(overlap: (still, moving) => false),
      onEventChange: told.add,
      onCommandRefused: (r, cmd) => refused.add(r),
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await _longDrag(t, t.getCenter(find.text('Bilan')), const Offset(0, 48));
    expect(_times(c, 'a'), (_wall(_monday, 9, 0), _wall(_monday, 10, 0)));
    expect(told, isEmpty);
    expect(refused.single.violations, isNotEmpty, reason: "the app hears why (the rules' violations)");
    expect(find.text('Bilan'), findsOneWidget);
  });

  testWidgets('an occurrence of a series: asked how far; "this event" moves that one only', (t) async {
    final told = <EventChange>[];
    final c = _controller(
      events: [_at('s', 'Kiné', '2026-11-09T09:00', '2026-11-09T10:00', rrule: 'FREQ=DAILY;COUNT=5')],
      onEventChange: told.add,
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true), reduceMotion: true);
    await _longDrag(t, t.getCenter(find.text('Kiné')), const Offset(0, 48));
    expect(find.text('Modifier quels événements ?'), findsOneWidget);
    await t.tap(find.text('Cet événement'));
    await t.pumpAndSettle();
    expect(told, hasLength(1));
    expect(told.single.series, isNotEmpty, reason: 'the occurrence becomes an override of its series');
    // Tomorrow's occurrence has not moved.
    c.next();
    await t.pumpAndSettle();
    final tomorrow = c.kernel.store.snapshot
        .queryInstances(datesWindow(PlainDate(2026, 11, 10), PlainDate(2026, 11, 11), _zone))
        .singleWhere(
          (i) => ZonedDateTime((i.event as TimedEvent).start.instant, _zone).date == PlainDate(2026, 11, 10),
        );
    expect((tomorrow.event as TimedEvent).start.instant, _wall(PlainDate(2026, 11, 10), 9, 0));
  });

  testWidgets('a series scope menu closed without a choice: nothing changes', (t) async {
    final c = _controller(
      events: [_at('s', 'Kiné', '2026-11-09T09:00', '2026-11-09T10:00', rrule: 'FREQ=DAILY;COUNT=5')],
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await _longDrag(t, t.getCenter(find.text('Kiné')), const Offset(0, 48));
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(c.history.canUndo, isFalse);
  });

  testWidgets('a month: an all-day event dragged one cell along moves one day', (t) async {
    final c = _controller(view: 'dayGridMonth', events: [_at('d', 'Congé', '2026-11-10', '2026-11-11', allDay: true)]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, editable: true));
    final bar = t.getCenter(find.text('Congé'));
    await _longDrag(t, bar, const Offset(400 / 7, 0));
    final ev = c.kernel.store.snapshot.getEvent('d')! as AllDayEvent;
    expect(ev.start, PlainDate(2026, 11, 11));
    expect(ev.end, PlainDate(2026, 11, 12));
  });

  testWidgets('selectable: a long press on empty time and a drag select 09:00–10:30', (t) async {
    CalendarSelection? got;
    final c = _controller();
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, selectable: true, onSelect: (s, _) => got = s));
    // Find 09:00's line from the gutter's label, then press a little under it.
    final nine = t.getTopLeft(find.text('09 h'));
    final from = Offset(250, nine.dy + 7 + 5);
    // 9:05 to about 10:20: the slots from 09:00 to 10:30 (the slot the finger is in, included).
    await _longDrag(t, from, const Offset(0, 60));
    expect(got, isA<TimeSelection>());
    final sel = got! as TimeSelection;
    expect(sel.start.instant, _wall(_monday, 9, 0));
    expect(sel.end.instant, _wall(_monday, 10, 30));
    expect(c.selection, same(got));
  });

  testWidgets('not selectable: a long press on empty time offers "New event"', (t) async {
    final c = _controller();
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, onCreateRequest: (_, _) {}));
    final nine = t.getTopLeft(find.text('09 h'));
    await t.longPressAt(Offset(250, nine.dy + 7 + 5));
    await t.pumpAndSettle();
    expect(find.textContaining('Nouvel événement'), findsWidgets);
  });

  testWidgets('an undo is told as an undo; selecting does not notify the controller', (t) async {
    final told = <EventChange>[];
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')], onEventChange: told.add);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await _longDrag(t, t.getCenter(find.text('Bilan')), const Offset(0, 48));
    expect(c.undo(), isTrue);
    expect(told.map((e) => e.cause), [EventChangeCause.command, EventChangeCause.undo]);
    // The app's own command is not a person's: not told.
    c.run(DeleteEvent('a'));
    expect(told, hasLength(2));
    await t.pump(); // what those changes notify, delivered

    var notified = 0;
    var selected = 0;
    c.addListener(() => notified++);
    c.selectionListenable.addListener(() => selected++);
    c.select(DaySelection(start: _monday, end: _monday.addDays(1)));
    await t.pump();
    expect((notified, selected), (0, 1));
  });

  testWidgets('a person refused (an event gone): onCommandRefused says why', (t) async {
    final refused = <Command>[];
    final c = _controller(onCommandRefused: (r, cmd) => refused.add(cmd));
    addTearDown(c.dispose);
    final r = c.run(DeleteEvent('nothing'), validate: true);
    expect(r.ok, isFalse);
    expect(refused, hasLength(1));
  });

  testWidgets('no swipe to another week while an event is held', (t) async {
    final c = _controller(view: 'timeGridWeek', events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    final title = c.state.title;
    await t.longPress(find.text('Bilan'));
    await t.pumpAndSettle();
    await t.fling(find.text('09 h'), const Offset(-300, 0), 1500);
    await t.pumpAndSettle();
    expect(c.state.title, title);
    // A tap elsewhere lets it go; then a swipe goes on.
    await t.tapAt(Offset(300, t.getTopLeft(find.text('13 h')).dy + 20));
    await t.pumpAndSettle();
    await t.fling(find.text('09 h'), const Offset(-300, 0), 1500);
    await t.pumpAndSettle();
    expect(c.state.title, isNot(title));
  });

  testWidgets("eventBuilder: the app's look, the calendar's gestures", (t) async {
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    EventInfo? seen;
    await _pump(
      t,
      DzCalendar(
        controller: c,
        scrollHour: 8,
        editable: true,
        eventBuilder: (context, i, info) {
          seen = info;
          return ColoredBox(color: info.color, child: Text('★ ${i.event.title}'));
        },
      ),
    );
    expect(find.text('★ Bilan'), findsOneWidget);
    expect(seen!.when, 'de 09:00 à 10:00');
    expect(seen!.size.height, closeTo(47, 1));
    await _longDrag(t, t.getCenter(find.text('★ Bilan')), const Offset(0, 48));
    expect(_times(c, 'a').$1, _wall(_monday, 10, 0));
  });

  testWidgets('a drop with less motion asked lands at once (no slide left running)', (t) async {
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true), reduceMotion: true);
    final g = await t.startGesture(t.getCenter(find.text('Bilan')));
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await g.moveBy(const Offset(0, 24));
    await t.pump();
    await g.moveBy(const Offset(0, 24));
    await t.pump();
    await g.up();
    await t.pump();
    expect(t.hasRunningAnimations, isFalse);
    expect(_times(c, 'a').$1, _wall(_monday, 10, 0));
    // Nothing left faded or floating.
    expect(find.byType(Opacity), findsNothing);
  });

  testWidgets('review: a revert asked inside onEventChange takes it back and is not told again', (t) async {
    final told = <EventChange>[];
    late CalendarController c;
    c = _controller(
      events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')],
      onEventChange: (e) {
        told.add(e);
        expect(e.revert(), isTrue); // a refusal known at once
      },
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await _longDrag(t, t.getCenter(find.text('Bilan')), const Offset(0, 48));
    expect(_times(c, 'a'), (_wall(_monday, 9, 0), _wall(_monday, 10, 0)));
    expect(told, hasLength(1));
  });

  testWidgets('review: an app\'s look hears that its event is held', (t) async {
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(
      t,
      DzCalendar(
        controller: c,
        scrollHour: 8,
        editable: true,
        eventBuilder: (context, i, info) => Text(info.held ? 'tenu' : 'libre'),
      ),
    );
    expect(find.text('libre'), findsOneWidget);
    await t.longPress(find.text('libre'));
    await t.pumpAndSettle();
    expect(find.text('tenu'), findsOneWidget);
  });
}
