// Phase 19g: where the tapped thing is (owner's decision 49) — onEventTap,
// onSelect and onCreateRequest are given its global Rect, to anchor a
// popover, from a finger, the menu or the keyboard. Expectations by hand:
// the day view's hour is 48 px (0.8 px a minute); Paris is UTC+1 in November.
import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _zone = 'Europe/Paris';
final _monday = PlainDate(2026, 11, 9);

CalendarController _controller({String view = 'timeGridDay', List<EventInput> events = const []}) => CalendarController(
  KernelOptions(
    timeZone: _zone,
    locale: 'fr',
    initialDate: _monday,
    initialView: view,
    now: () => ZonedDateTime.fromWall(PlainDateTime(_monday, PlainTime(10, 20)), _zone)!.instant,
    events: events,
  ),
);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 800)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
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

final _bilan = EventInput(id: 'a', title: 'Bilan', start: '2026-11-09T09:00', end: '2026-11-09T10:00');

/// The hour line under a gutter label (the label is centred on its hour).
double _hourY(WidgetTester t, String label) => t.getCenter(find.text(label)).dy;

void main() {
  testWidgets('an event tapped: its own box, an hour tall', (t) async {
    Rect? got;
    final c = _controller(events: [_bilan]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, onEventTap: (_, r) => got = r));
    final at = t.getCenter(find.text('Bilan'));
    await t.tap(find.text('Bilan'));
    await t.pump();
    expect(got, isNotNull);
    expect(got!.contains(at), isTrue);
    // 09:00–10:00: 60 minutes at 0.8 px, less the drawn gap.
    expect(got!.height, inInclusiveRange(44, 48));
    expect(got!.top, closeTo(_hourY(t, '09 h'), 2));
  });

  testWidgets('over two days, the piece tapped', (t) async {
    Rect? got;
    final c = _controller(
      view: 'timeGridWeek',
      events: [EventInput(id: 'n', title: 'Garde', start: '2026-11-10T20:00', end: '2026-11-11T08:00')],
    );
    addTearDown(c.dispose);
    await _pump(
      t,
      DzCalendar(controller: c, scrollHour: 0, onEventTap: (_, r) => got = r),
      size: const Size(1000, 1400),
    );
    final pieces = find.text('Garde');
    expect(pieces, findsNWidgets(2));
    final second = t.getCenter(pieces.at(1));
    await t.tapAt(second);
    await t.pump();
    expect(got!.contains(second), isTrue);
    expect(got!.contains(t.getCenter(pieces.at(0))), isFalse);
  });

  testWidgets('a slot tapped: onSelect is told where the selection is', (t) async {
    Rect? got;
    final c = _controller();
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, onSelect: (_, r) => got = r));
    final at = Offset(250, _hourY(t, '09 h') + 10);
    await t.tapAt(at);
    await t.pump();
    expect(got!.contains(at), isTrue);
    expect(got!.width, lessThan(400));
  });

  testWidgets('a day of the month tapped: its cell', (t) async {
    Rect? got;
    final c = _controller(view: 'dayGridMonth');
    addTearDown(c.dispose);
    await _pump(
      t,
      DzCalendar(controller: c, onSelect: (_, r) => got = r),
      size: const Size(700, 700),
    );
    final at = t.getCenter(find.text('18'));
    await t.tapAt(at);
    await t.pump();
    // The bar a one-day event would take on the 18th: that column.
    expect(got!.left, lessThan(at.dx));
    expect(got!.right, greaterThan(at.dx));
    expect(got!.width, lessThan(700 / 7 + 1));
  });

  testWidgets('the menu: "Open" and "New event" are told where', (t) async {
    Rect? opened;
    Rect? created;
    final c = _controller(events: [_bilan]);
    addTearDown(c.dispose);
    await _pump(
      t,
      DzCalendar(
        controller: c,
        scrollHour: 8,
        onEventTap: (_, r) => opened = r,
        onCreateRequest: (_, r) => created = r,
      ),
    );
    final at = t.getCenter(find.text('Bilan'));
    await t.longPress(find.text('Bilan'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ouvrir'));
    await t.pumpAndSettle();
    expect(opened!.contains(at), isTrue);

    final empty = Offset(250, _hourY(t, '13 h') + 5);
    await t.longPressAt(empty);
    await t.pumpAndSettle();
    await t.tap(find.textContaining('Nouvel événement').first);
    await t.pumpAndSettle();
    expect(created, isNotNull);
    // From the moment pressed (the menu's CreateAt is not snapped), one snap (15 minutes) long.
    expect(created!.top, closeTo(empty.dy, 1.5));
    expect(created!.height, closeTo(12, 1.5));
  });

  testWidgets('Enter on an event from the keyboard: its box, no pointer needed', (t) async {
    Rect? got;
    final c = _controller(events: [_bilan]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, onEventTap: (_, r) => got = r));
    await t.tapAt(Offset(300, _hourY(t, '13 h') + 2));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(got, isNotNull);
    expect(got!.contains(t.getCenter(find.text('Bilan'))), isTrue);
  });

  testWidgets('a list has no box of its own for an event: the tapped row', (t) async {
    Rect? got;
    final c = _controller(view: 'listWeek', events: [_bilan]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, onEventTap: (_, r) => got = r));
    final at = t.getCenter(find.text('Bilan'));
    await t.tap(find.text('Bilan'));
    await t.pump();
    expect(got!.contains(at), isTrue);
    expect(got!.width, lessThanOrEqualTo(400));
  });

  testWidgets('review: in a month, "Open" from the menu points at the second lane, not the first', (t) async {
    Rect? got;
    final c = _controller(
      view: 'dayGridMonth',
      events: [
        EventInput(id: 'x', title: 'Premier', start: '2026-11-18', allDay: true),
        EventInput(id: 'y', title: 'Second', start: '2026-11-18', allDay: true),
      ],
    );
    addTearDown(c.dispose);
    await _pump(
      t,
      DzCalendar(controller: c, onEventTap: (_, r) => got = r),
      size: const Size(700, 900),
    );
    final first = t.getRect(find.text('Premier'));
    final second = t.getCenter(find.text('Second'));
    expect(second.dy, greaterThan(first.bottom), reason: 'one lane under the other');
    await t.longPress(find.text('Second'));
    await t.pumpAndSettle();
    await t.tap(find.text('Ouvrir'));
    await t.pumpAndSettle();
    expect(got!.contains(second), isTrue);
    expect(got!.contains(first.center), isFalse);
  });

  testWidgets('review: an event hidden by the filter while the keyboard is on it: Enter opens nothing', (t) async {
    final opened = <String>[];
    final c = _controller(events: [_bilan]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, onEventTap: (i, _) => opened.add(i.event.id)));
    await t.tap(find.text('Bilan'));
    await t.pump();
    expect(opened, ['a']);
    c.setOptions(c.options.copyWith(eventFilter: (e) => e.id != 'a'));
    await t.pumpAndSettle();
    expect(find.text('Bilan'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(opened, ['a'], reason: 'the cursor left the hidden event');
  });
}
