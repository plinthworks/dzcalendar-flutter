// Editing on the timeline (19j-3): a drag across rows, the end's handle along
// time, the drag scrolling near the edges, the keyboard, a screen reader.
// Positions reasoned by hand, as in timeline_widgets_test.dart: Paris on
// Monday 9 November 2026 is UTC+1; a half hour is 44 px, the time heads
// 52 px, a resource row 86 px, the area 160 px on a 1000 × 700 tablet; the
// scroll opens on 07:00, 14 half hours (616 px) in. Snaps are 15 minutes.

import 'package:dzcalendar/dzcalendar.dart';
import 'package:dzcalendar/src/views/common.dart' show CursorBox;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _zone = 'Europe/Paris';
final _monday = PlainDate(2026, 11, 9);
final _now = _wall(10, 20);

const _tablet = Size(1000, 700);
const _area = 160.0;
const _slot = 44.0;
const _opened = 14 * _slot; // 07:00
const _head = 52.0;
const _row = 86.0;

Instant _wall(int h, int m, [PlainDate? d]) =>
    ZonedDateTime.fromWall(PlainDateTime(d ?? _monday, PlainTime(h, m)), _zone)!.instant;

const _two = [ResourceInput(id: 'ali', title: 'Ali Benali'), ResourceInput(id: 'sara', title: 'Sara')];

CalendarController _controller({
  String view = 'resourceTimelineDay',
  List<EventInput> events = const [],
  List<ResourceInput> resources = _two,
  ModelOptions options = const ModelOptions(),
  String locale = 'fr',
  void Function(EventChange)? onEventChange,
}) => CalendarController(
  KernelOptions(
    timeZone: _zone,
    locale: locale,
    initialDate: _monday,
    initialView: view,
    now: () => _now,
    events: events,
    resources: resources,
    options: options,
  ),
  followAppLocale: false,
  onEventChange: onEventChange,
);

Future<void> _pump(WidgetTester t, Widget w, {String locale = 'fr'}) async {
  t.view.physicalSize = _tablet;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        DzCalendarLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: w),
    ),
  );
  await t.pumpAndSettle();
}

EventInput _ev(String id, String title, String from, String to, {String? resourceId}) => EventInput(
  id: id,
  title: title,
  start: '2026-11-09T$from[Europe/Paris]',
  end: '2026-11-09T$to[Europe/Paris]',
  resourceId: resourceId,
);

/// Where a position (half hours from midnight) is on screen, the scroll opened on 07:00.
double _x(double halfHours) => _area + halfHours * _slot - _opened;

/// The middle of a resource row (0: the first under the heads), unscrolled.
double _y(int row) => _head + row * _row + _row / 2;

/// The middle of a row's first lane (its events' bars: 4 px down, 24 px tall).
double _lane(int row) => _head + row * _row + 4 + 12;

({Instant start, Instant end, List<String> resources}) _stored(CalendarController c, String id) =>
    switch (c.kernel.store.snapshot.getEvent(id)!) {
      TimedEvent(:final start, :final end, :final resourceIds) => (
        start: start.instant,
        end: end.instant,
        resources: resourceIds,
      ),
      AllDayEvent() => throw StateError('all-day'),
    };

/// A long press at [from], the finger moved by [by] in a few steps, held [hold] there, then lifted.
Future<void> _longDrag(WidgetTester t, Offset from, Offset by, {Duration hold = Duration.zero}) async {
  final g = await t.startGesture(from);
  await t.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  for (var k = 1; k <= 4; k++) {
    await g.moveTo(from + by * (k / 4));
    await t.pump(const Duration(milliseconds: 16));
  }
  for (var ms = 0; ms < hold.inMilliseconds; ms += 16) {
    await t.pump(const Duration(milliseconds: 16));
  }
  await g.up();
  await t.pumpAndSettle();
}

/// What the calendar says to screen readers, in order.
List<String> _said(WidgetTester t) {
  final said = <String>[];
  final m = t.binding.defaultBinaryMessenger;
  m.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (msg) async {
    if (msg is Map && msg['type'] == 'announce') said.add((msg['data'] as Map)['message'] as String);
    return null;
  });
  addTearDown(() => m.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
  return said;
}

Future<void> _key(WidgetTester t, LogicalKeyboardKey k, {bool shift = false}) async {
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await t.sendKeyEvent(k);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.pump();
}

void main() {
  testWidgets('dragged one hour on and one row down: later, and on the other resource (told)', (t) async {
    final told = <EventChange>[];
    final c = _controller(
      events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')],
      onEventChange: told.add,
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, editable: true));
    // Taken at 09:30 on Ali's row (the bar's middle), put down at 10:30 on Sara's.
    await _longDrag(t, Offset(_x(19), _lane(0)), const Offset(2 * _slot, _row));
    final a = _stored(c, 'a');
    expect(
      [a.start, a.end, a.resources],
      [
        _wall(10, 0),
        _wall(11, 0),
        ['sara'],
      ],
    );
    expect(told.single.command, isA<MoveEvent>());
  });

  testWidgets('right to left: dragged leftwards is later', (t) async {
    final c = _controller(
      locale: 'ar',
      events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')],
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, editable: true), locale: 'ar');
    // Mirrored: 09:30 is as far from the right edge as it is from the left one left to right.
    await _longDrag(t, Offset(_tablet.width - _x(19), _lane(0)), const Offset(-2 * _slot, _row));
    final a = _stored(c, 'a');
    expect(
      [a.start, a.resources],
      [
        _wall(10, 0),
        ['sara'],
      ],
    );
  });

  testWidgets('held, its end\'s handle pulled 44 px along time: it ends half an hour later', (t) async {
    final c = _controller(events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, editable: true));
    await t.longPress(find.text('Consult'));
    await t.pumpAndSettle();
    final handle = find.byWidgetPredicate((w) => w is GestureDetector && w.onHorizontalDragStart != null);
    expect(handle, findsOneWidget);
    final from = t.getCenter(handle);
    final g = await t.startGesture(from);
    // The end keeps its distance from the finger: 44 px further is half an hour later.
    for (var k = 1; k <= 6; k++) {
      await g.moveTo(from + Offset(_slot * k / 6, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await t.pumpAndSettle();
    final a = _stored(c, 'a');
    expect(
      [a.start, a.end, a.resources],
      [
        _wall(9, 0),
        _wall(10, 30),
        ['ali'],
      ],
    );
  });

  testWidgets('a timeline counted in days: a timed event has no handle, an all-day one has', (t) async {
    final c = _controller(
      view: 'resourceTimelineMonth',
      events: [
        // A day and a half: 54 px of a 36 px day.
        EventInput(
          id: 'a',
          title: 'Consult',
          start: '2026-11-09T00:00[Europe/Paris]',
          end: '2026-11-10T12:00[Europe/Paris]',
          resourceId: 'ali',
        ),
        EventInput(id: 'b', title: 'Congé', start: '2026-11-09', end: '2026-11-11', resourceId: 'sara'),
      ],
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, editable: true));
    final handle = find.byWidgetPredicate((w) => w is GestureDetector && w.onHorizontalDragStart != null);
    await t.longPress(find.text('Consult'));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.more_vert), findsOneWidget, reason: 'held');
    expect(handle, findsNothing);
    await t.longPress(find.text('Congé'));
    await t.pumpAndSettle();
    expect(handle, findsOneWidget);
  });

  testWidgets('held near the end edge, the time scrolls on under it', (t) async {
    final c = _controller(events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, editable: true));
    // Without scrolling, 995 px is 16:29 (32.98 half hours): taken at 09:30, it would start at 16:00.
    final from = Offset(_x(19), _lane(0));
    await _longDrag(t, from, Offset(995 - from.dx, 0), hold: const Duration(milliseconds: 600));
    expect(_stored(c, 'a').start.isAfter(_wall(17, 30)), isTrue, reason: 'it went past what was in view');
  });

  testWidgets('held near the bottom edge, the rows scroll up under it', (t) async {
    final c = _controller(
      events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'r0')],
      resources: [for (var i = 0; i < 12; i++) ResourceInput(id: 'r$i', title: 'Médecin $i')],
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, editable: true));
    // 695 px is row 7 unscrolled ((695 − 52) / 86 = 7.5).
    final from = Offset(_x(19), _lane(0));
    await _longDrag(t, from, Offset(0, 695 - from.dy), hold: const Duration(milliseconds: 800));
    final row = int.parse(_stored(c, 'a').resources.single.substring(1));
    expect(row, greaterThanOrEqualTo(9), reason: 'rows below the view came under the finger');
  });

  testWidgets('the cursor: left and right along time, up and down the rows, each said', (t) async {
    final said = _said(t);
    final c = _controller();
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, selectable: true));
    // 09:10 on Ali's row: the 09:00 half hour.
    await t.tapAt(Offset(_x(18 + 1 / 3), _y(0)));
    await t.pump();
    await _key(t, LogicalKeyboardKey.arrowRight);
    expect(said.last, 'Ali Benali, lundi 9 novembre, 09:15');
    expect(find.byType(CursorBox), findsOneWidget);
    await _key(t, LogicalKeyboardKey.arrowDown);
    expect(said.last, 'Sara, lundi 9 novembre, 09:15');
    await _key(t, LogicalKeyboardKey.arrowDown);
    expect(said.last, 'Impossible d’aller plus loin');
    await _key(t, LogicalKeyboardKey.arrowUp);
    await _key(t, LogicalKeyboardKey.arrowLeft);
    expect(said.last, 'Ali Benali, lundi 9 novembre, 09:00');
    // Shift+→ selects along the row: 09:00–09:30 on Ali.
    await _key(t, LogicalKeyboardKey.arrowRight, shift: true);
    final sel = c.selection! as TimeSelection;
    expect([sel.start.instant, sel.end.instant, sel.resourceId], [_wall(9, 0), _wall(9, 30), 'ali']);
  });

  testWidgets('Tab to an event, M, ↓ to the next row, → twice, Enter: on Sara half an hour later', (t) async {
    final said = _said(t);
    final c = _controller(events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, editable: true));
    await t.tapAt(Offset(_x(26), _y(1)));
    await t.pump();
    await _key(t, LogicalKeyboardKey.tab);
    expect(said.last, 'Consult, de 09:00 à 10:00');
    await _key(t, LogicalKeyboardKey.keyM);
    expect(said.last, startsWith('« Consult » saisi.'));
    await _key(t, LogicalKeyboardKey.arrowDown);
    expect(said.last, 'Sara, lundi 9 novembre, de 09:00 à 10:00');
    await _key(t, LogicalKeyboardKey.arrowRight);
    await _key(t, LogicalKeyboardKey.arrowRight);
    expect(said.last, 'Sara, lundi 9 novembre, de 09:30 à 10:30');
    // Nothing changed before Enter.
    expect(_stored(c, 'a').resources, ['ali']);
    await _key(t, LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    final a = _stored(c, 'a');
    expect(
      [a.start, a.end, a.resources],
      [
        _wall(9, 30),
        _wall(10, 30),
        ['sara'],
      ],
    );
  });

  testWidgets('PageDown with a step of an hour: the time slides by it, the cursor an hour on', (t) async {
    final said = _said(t);
    final c = _controller(
      options: const ModelOptions(timeline: TimelineSettings(step: Duration(hours: 1))),
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false));
    await t.tapAt(Offset(_x(18), _y(0)));
    await t.pump();
    final before = t.getTopLeft(find.text('09 h')).dx;
    await _key(t, LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(said.last, 'Ali Benali, lundi 9 novembre, 10:00');
    expect(c.state.date, _monday, reason: 'the same period');
    expect(t.getTopLeft(find.text('09 h')).dx, closeTo(before - 2 * _slot, 1));
  });

  testWidgets('a screen reader: Move…, Next resource, a swipe up, a double tap', (t) async {
    final handle = t.ensureSemantics();
    final c = _controller(events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, editable: true));
    final event = find.semantics.byLabel('Consult, de 09:00 à 10:00');
    t.semantics.customAction(event, const CustomSemanticsAction(label: 'Déplacer…'));
    await t.pumpAndSettle();
    t.semantics.customAction(event, const CustomSemanticsAction(label: 'Ressource suivante'));
    await t.pump();
    // A swipe up: a snap later (15 minutes) on a timeline counted in time.
    t.semantics.increase(event);
    await t.pump();
    t.semantics.tap(event);
    await t.pumpAndSettle();
    final a = _stored(c, 'a');
    expect(
      [a.start, a.end, a.resources],
      [
        _wall(9, 15),
        _wall(10, 15),
        ['sara'],
      ],
    );
    handle.dispose();
  });

  testWidgets('held: Shift+→ pulls its end a snap along; Escape lets go, nothing changes, the cursor on its row', (
    t,
  ) async {
    final said = _said(t);
    final c = _controller(events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'sara')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, editable: true));
    await t.tapAt(Offset(_x(26), _y(0)));
    await t.pump();
    await _key(t, LogicalKeyboardKey.tab);
    await _key(t, LogicalKeyboardKey.keyM);
    await _key(t, LogicalKeyboardKey.arrowRight, shift: true);
    expect(said.last, 'lundi 9 novembre, de 09:00 à 10:15');
    await _key(t, LogicalKeyboardKey.arrowUp);
    expect(said.last, 'Ali Benali, lundi 9 novembre, de 09:00 à 10:15');
    await _key(t, LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(said.last, 'Déplacement annulé');
    final a = _stored(c, 'a');
    expect(
      [a.start, a.end, a.resources],
      [
        _wall(9, 0),
        _wall(10, 0),
        ['sara'],
      ],
    );
    // Back on the event, then on the cursor: Sara's row, where it was taken.
    await _key(t, LogicalKeyboardKey.escape);
    expect(said.last, 'Sara, lundi 9 novembre, 09:00');
  });

  testWidgets('right to left: ← is later; Shift+← selects along the row', (t) async {
    final c = _controller(locale: 'ar');
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, selectable: true), locale: 'ar');
    // 09:10 on Ali's row, mirrored.
    await t.tapAt(Offset(_tablet.width - _x(18 + 1 / 3), _y(0)));
    await t.pump();
    await _key(t, LogicalKeyboardKey.arrowLeft, shift: true);
    final sel = c.selection! as TimeSelection;
    expect([sel.start.instant, sel.end.instant, sel.resourceId], [_wall(9, 0), _wall(9, 30), 'ali']);
  });

  testWidgets('a timeline counted in days: PageDown opens the next month on the same day', (t) async {
    final said = _said(t);
    final c = _controller(
      view: 'resourceTimelineMonth',
      options: const ModelOptions(timeline: TimelineSettings(step: Duration(hours: 12))),
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false));
    // The 9th is two days in from the area (36 px a day): 232–268 px.
    await t.tapAt(Offset(_area + 2.5 * 36, _y(0)));
    await t.pump();
    await _key(t, LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(c.state.range.start, PlainDate(2026, 12, 1));
    expect(said.last, 'Ali Benali, mercredi 9 décembre');
  });

  testWidgets('End, then → past midnight: the next day at 00:00, said with its own date, in view', (t) async {
    final said = _said(t);
    final c = _controller();
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false));
    await t.tapAt(Offset(_x(18), _y(0)));
    await t.pump();
    await _key(t, LogicalKeyboardKey.end);
    expect(said.last, 'Ali Benali, lundi 9 novembre, 23:45');
    await _key(t, LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(said.last, 'Ali Benali, mardi 10 novembre, 00:00');
    expect(c.state.date, PlainDate(2026, 11, 10));
    // Midnight at the start of the time, not the 07:00 a new day opens on.
    expect(t.getTopLeft(find.text('00 h')).dx, closeTo(_area + 3, 1));
  });

  testWidgets('dragged across a group\'s band: the ghost stays, it lands on the row under it', (t) async {
    final c = _controller(
      events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')],
      resources: const [
        ResourceInput(id: 'ali', title: 'Ali', extendedProps: {'dep': 'Cardio'}),
        ResourceInput(id: 'nour', title: 'Nour', extendedProps: {'dep': 'Pédia'}),
      ],
      options: const ModelOptions(resourceGroupField: 'dep'),
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false, editable: true));
    // Rows: Cardio's band (34 px), Ali (86), Pédia's band (34), Nour. Ali's first lane: 52 + 34 + 16.
    const from = Offset(380, _head + 34 + 16);
    // Let go over Pédia's band (52 + 34 + 86 + 17 = 189).
    await _longDrag(t, from, Offset(0, 189 - from.dy));
    expect(_stored(c, 'a').resources, ['nour']);
  });
}
