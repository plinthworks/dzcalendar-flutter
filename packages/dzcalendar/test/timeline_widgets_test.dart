// The timeline widget (19j-2). Positions reasoned by hand: Paris on Monday
// 9 November 2026 is UTC+1, no clock change; a day is 48 half hours of 44 px
// (the theme's slot), the time heads 52 px, a resource row 3 lanes of 26 px
// and 8 px (86 px), the area 160 px on a tablet. The scroll opens on 07:00
// (`scrollHour`), 14 half hours in: 616 px. French writes a whole hour
// "07 h" (the device's 12/24-hour setting off, as the gutter writes it).

import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _zone = 'Europe/Paris';
final _monday = PlainDate(2026, 11, 9);
final _now = ZonedDateTime.fromWall(PlainDateTime(_monday, PlainTime(10, 20)), _zone)!.instant;

const _tablet = Size(1000, 700);
const _area = 160.0;
const _slot = 44.0;
const _opened = 14 * _slot; // 07:00
const _head = 52.0;
const _row = 86.0;

CalendarController _controller({
  String view = 'resourceTimelineDay',
  List<EventInput> events = const [],
  List<ResourceInput> resources = const [
    ResourceInput(id: 'ali', title: 'Ali Benali'),
    ResourceInput(id: 'sara', title: 'Sara'),
  ],
  String locale = 'fr',
  ModelOptions options = const ModelOptions(),
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
);

Future<void> _pump(WidgetTester t, Widget w, {Size size = _tablet, String locale = 'fr'}) async {
  t.view.physicalSize = size;
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

/// Where a position (half hours from midnight) is on screen, with the scroll opened on 07:00.
double _x(double halfHours) => _area + halfHours * _slot - _opened;

void main() {
  testWidgets('rows of resources, the heads, an event at its true place and length', (t) async {
    final c = _controller(events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false));
    expect(find.text('Ali Benali'), findsOneWidget);
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Ressources'), findsOneWidget);
    // The day's head, and 07:00 at the start of the time: the area's edge.
    expect(find.text('lun. 9 nov.'), findsOneWidget);
    expect(t.getTopLeft(find.text('07 h')).dx, closeTo(_area + 3, 1));
    // 09:00 is 18 half hours in, an hour two slots; on Ali's row (the first under the heads).
    final bar = t.getRect(find.ancestor(of: find.text('Consult'), matching: find.byType(Container)).first);
    expect(bar.left, closeTo(_x(18), 1));
    expect(bar.width, closeTo(2 * _slot - 1, 1));
    expect(bar.top, closeTo(_head + 4, 1));
  });

  testWidgets('a tap on empty time: the slot it is in, selected; told with its resource', (t) async {
    final c = _controller();
    addTearDown(c.dispose);
    Hit? tapped;
    CalendarSelection? selected;
    await _pump(
      t,
      DzCalendar(controller: c, showHeader: false, onDateTap: (h) => tapped = h, onSelect: (s, _) => selected = s),
    );
    // 11:10 on Sara's row (the second): the 11:00 half hour, 10:00Z.
    await t.tapAt(Offset(_x(22 + 1 / 3), _head + _row + _row / 2));
    final hit = tapped! as SlotHit;
    expect(['${hit.instant}', hit.resourceId], ['2026-11-09T10:00:00Z', 'sara']);
    final sel = selected! as TimeSelection;
    expect(
      ['${sel.start.instant}', '${sel.end.instant}', sel.resourceId],
      ['2026-11-09T10:00:00Z', '2026-11-09T10:30:00Z', 'sara'],
    );
  });

  testWidgets('a fold hides a resource\'s children; the application is told', (t) async {
    final c = _controller(
      resources: const [
        ResourceInput(id: 'dep', title: 'Cardiologie'),
        ResourceInput(id: 'ali', title: 'Ali', parentId: 'dep'),
      ],
    );
    addTearDown(c.dispose);
    Set<String>? told;
    await _pump(t, DzCalendar(controller: c, showHeader: false, onResourceToggle: (r, _) => told = r));
    expect(find.text('Ali'), findsOneWidget);
    await t.tap(find.byTooltip('Replier Cardiologie'));
    await t.pumpAndSettle();
    expect(find.text('Ali'), findsNothing);
    expect(told, {'dep'});
    expect(c.options.collapsedResources, {'dep'});
    await t.tap(find.byTooltip('Déplier Cardiologie'));
    await t.pumpAndSettle();
    expect(find.text('Ali'), findsOneWidget);
  });

  testWidgets('◀ ▶ with a step slide the axis, then bring in the next period at its start', (t) async {
    final c = _controller(
      events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')],
      options: const ModelOptions(timeline: TimelineSettings(step: Duration(hours: 1))),
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false));
    double barLeft() => t.getRect(find.ancestor(of: find.text('Consult'), matching: find.byType(Container)).first).left;
    final before = barLeft();
    c.next();
    await t.pumpAndSettle();
    // An hour is two slots: the bar comes 88 px nearer the start.
    expect(barLeft(), closeTo(before - 2 * _slot, 1));
    expect(c.state.date, _monday);
    // The end of the day is 160 + 48 × 44 − 1000 = 1272 px along; from 704, seven presses reach it.
    for (var k = 0; k < 7; k++) {
      c.next();
      await t.pumpAndSettle();
    }
    expect(c.state.date, _monday);
    c.next();
    await t.pumpAndSettle();
    // The next day, opened at its start: 00:00 at the area's edge.
    expect(c.state.date, _monday.addDays(1));
    expect(t.getTopLeft(find.text('00 h')).dx, closeTo(_area + 3, 1));
  });

  testWidgets('right to left: the area at the right, time running leftwards', (t) async {
    final c = _controller(
      locale: 'ar',
      events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')],
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false), locale: 'ar');
    expect(t.getTopLeft(find.text('Ali Benali')).dx, greaterThan(_tablet.width - _area));
    final bar = t.getRect(find.ancestor(of: find.text('Consult'), matching: find.byType(Container)).first);
    // Mirrored: 09:00's start edge is at the right of the bar.
    expect(bar.right, closeTo(_tablet.width - _x(18), 1));
  });

  testWidgets('without resources: one row as tall as the view, its lanes counted from it', (t) async {
    final c = _controller(view: 'timelineDay', resources: const []);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false));
    // 700 − 52 = 648 px below the heads: (648 − 8) / 26 → 24 lanes.
    expect(c.options.timeline.fillLanes, 24);
    expect(find.text('Ressources'), findsNothing);
  });

  testWidgets('"+N" past the row\'s lanes, its events in a sheet', (t) async {
    final c = _controller(
      events: [for (var k = 0; k < 4; k++) _ev('e$k', 'Rdv $k', '09:00', '10:00', resourceId: 'ali')],
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false));
    // Three lanes: two drawn, the third holds "+2".
    expect(find.text('Rdv 0'), findsOneWidget);
    expect(find.text('Rdv 2'), findsNothing);
    await t.tap(find.text('+2 autres'));
    await t.pumpAndSettle();
    expect(find.text('Rdv 2'), findsOneWidget);
    expect(find.text('Rdv 3'), findsOneWidget);
  });

  testWidgets('a phone: one narrow column, a button for initials', (t) async {
    final c = _controller();
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false), size: const Size(400, 800));
    expect(find.text('Ali Benali'), findsOneWidget);
    // The phone's area is 112 px: 07:00 starts after it.
    expect(t.getTopLeft(find.text('07 h')).dx, closeTo(112 + 3, 1));
    await t.tap(find.byTooltip('Initiales seulement'));
    await t.pumpAndSettle();
    expect(find.text('AB'), findsOneWidget);
    expect(t.getTopLeft(find.text('07 h')).dx, closeTo(44 + 3, 1));
  });

  testWidgets('two hundred resources: only the rows in view are built', (t) async {
    final c = _controller(
      resources: [for (var k = 0; k < 200; k++) ResourceInput(id: 'r$k', title: 'R$k')],
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false));
    expect(find.text('R0'), findsOneWidget);
    expect(find.text('R150'), findsNothing);
  });

  testWidgets('the views have their names in the switcher', (t) async {
    final c = _controller();
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, views: const ['resourceTimelineDay', 'resourceTimelineWeek']));
    expect(find.text('Chronologie (jour)'), findsWidgets);
  });

  testWidgets('resources that come after the first drawing: the scroll is placed then', (t) async {
    final c = _controller(resources: const []);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false));
    expect(find.text('Aucune ressource à afficher'), findsOneWidget);
    c.setResources(const [ResourceInput(id: 'ali', title: 'Ali Benali')]);
    await t.pumpAndSettle();
    expect(find.text('Ali Benali'), findsOneWidget);
    expect(t.getTopLeft(find.text('07 h')).dx, closeTo(_area + 3, 1));
  });

  testWidgets('a narrow pane on a tablet is laid out as a phone', (t) async {
    final c = _controller();
    addTearDown(c.dispose);
    await _pump(
      t,
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 500, child: DzCalendar(controller: c, showHeader: false)),
      ),
    );
    expect(find.byTooltip('Initiales seulement'), findsOneWidget);
    expect(find.text('Ressources'), findsNothing);
  });

  testWidgets('right to left, a tap is read from the right edge', (t) async {
    final c = _controller(locale: 'ar');
    addTearDown(c.dispose);
    Hit? tapped;
    await _pump(
      t,
      DzCalendar(controller: c, showHeader: false, onDateTap: (h) => tapped = h),
      locale: 'ar',
    );
    // 11:10 on Sara's row, mirrored: as far from the right edge as it is from the left in LTR.
    await t.tapAt(Offset(_tablet.width - _x(22 + 1 / 3), _head + _row + _row / 2));
    final hit = tapped! as SlotHit;
    expect(['${hit.instant}', hit.resourceId], ['2026-11-09T10:00:00Z', 'sara']);
  });

  testWidgets('a resize redraws without an error, the time still from the area', (t) async {
    final c = _controller(events: [_ev('a', 'Consult', '09:00', '10:00', resourceId: 'ali')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, showHeader: false));
    t.view.physicalSize = const Size(800, 600);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Consult'), findsOneWidget);
    expect(t.getTopLeft(find.text('07 h')).dx, closeTo(_area + 3, 1));
  });
}
