// What a person using a screen reader or a large text meets, view by view.
// Found by the first app on the widgets (sehhaty-mobile) and the audit that
// followed (2026-11-14): buttons read but not activated, a header whose title
// was pushed to nothing, day numbers drawn over the next day, a short event's
// title overflowing its block.
import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _zone = 'Europe/Paris';
final _monday = PlainDate(2026, 11, 9);
final _now = ZonedDateTime.fromWall(PlainDateTime(_monday, PlainTime(10, 20)), _zone)!.instant;

Instant _at(int h, int m) =>
    ZonedDateTime.fromWall(PlainDateTime(PlainDate(2026, 11, 10), PlainTime(h, m)), _zone)!.instant;

/// Six events at the same hour on Tuesday 10 (more than a day shows: a "+N"),
/// an all-day one, a free slot at 14:00; two resources.
CalendarController _controller(String view, {String locale = 'fr', List<EventInput>? events}) => CalendarController(
  KernelOptions(
    timeZone: _zone,
    locale: locale,
    initialDate: view.contains('Day') ? PlainDate(2026, 11, 10) : _monday,
    initialView: view,
    now: () => _now,
    events:
        events ??
        [
          for (var k = 0; k < 6; k++)
            EventInput(
              id: 'e$k',
              title: 'Consultation $k',
              start: '2026-11-10T09:00',
              end: '2026-11-10T10:00',
              resourceId: k.isEven ? 'ali' : 'sara',
            ),
          EventInput(id: 'ad', title: 'Congé', start: '2026-11-11', end: '2026-11-12', allDay: true),
        ],
    resources: const [
      ResourceInput(id: 'ali', title: 'Ali Benali'),
      ResourceInput(id: 'sara', title: 'Sara Haddad'),
    ],
    options: ModelOptions(
      dayGrid: const DayGridSettings(maxLanes: 2),
      timeGrid: const TimeGridSettings(maxStack: 1),
      timeline: const TimelineSettings(maxLanes: 1),
      availableSlots: [
        AvailableSlot(start: _at(14, 0), end: _at(14, 30), seats: 2),
        AvailableSlot(start: _at(14, 0), end: _at(14, 30), seats: 2, resourceId: 'ali'),
      ],
    ),
  ),
  followAppLocale: false,
);

Future<void> _pump(
  WidgetTester t,
  Widget w, {
  Size size = const Size(400, 800),
  String locale = 'fr',
  double scale = 1,
}) async {
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
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: w),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

/// Every node on screen.
List<SemanticsData> _nodes(WidgetTester t) {
  final out = <SemanticsData>[];
  void visit(SemanticsNode n) {
    if (!n.isInvisible) out.add(n.getSemanticsData());
    n.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  visit(t.binding.rootPipelineOwner.semanticsOwner?.rootSemanticsNode ?? t.getSemantics(find.byType(Scaffold)));
  return out;
}

/// A reader's double tap on the node [label] starts with.
Future<void> _readerTap(WidgetTester t, Pattern label) async {
  final node = t.getSemantics(
    find.bySemanticsLabel(label is String ? RegExp('^${RegExp.escape(label)}') : label).first,
  );
  node.owner!.performAction(node.id, SemanticsAction.tap);
  await t.pumpAndSettle();
}

/// The errors a build reports (overflows among them), several a frame.
Future<List<String>> _errorsOf(Future<void> Function() body) async {
  final errors = <String>[];
  final before = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
  try {
    await body();
  } finally {
    FlutterError.onError = before;
  }
  return errors;
}

const _views = [
  'dayGridMonth',
  'timeGridWeek',
  'timeGridDay',
  'listWeek',
  'multiMonthYear',
  'resourceTimeGridDay',
  'resourceTimelineDay',
];

void main() {
  group('a screen reader does what a finger does', () {
    // Every button said can be activated, and no node can be activated without
    // words. A `Semantics(excludeSemantics: true)` around an InkWell drops its tap.
    for (final v in [..._views, 'MiniMonth']) {
      testWidgets('$v: every button can be activated; nothing wordless can', (t) async {
        final handle = t.ensureSemantics();
        final c = _controller(v == 'MiniMonth' ? 'dayGridMonth' : v);
        addTearDown(c.dispose);
        await _pump(
          t,
          v == 'MiniMonth'
              ? MiniMonth(selected: _monday, today: _monday, onDateSelected: (_) {})
              : DzCalendar(controller: c, editable: true, onSlotTap: (_) {}, onDateTap: (_) {}),
          size: v.startsWith('resource') ? const Size(1000, 800) : const Size(400, 800),
        );
        final nodes = _nodes(t);
        final mute = [
          for (final d in nodes)
            if (d.flagsCollection.isButton &&
                !(d.flagsCollection.hasEnabledState && !d.flagsCollection.isEnabled) &&
                !d.hasAction(SemanticsAction.tap))
              d.label,
        ];
        expect(mute, isEmpty, reason: 'buttons a reader cannot activate');
        final wordless = [
          for (final d in nodes)
            if (d.hasAction(SemanticsAction.tap) && d.label.isEmpty && d.tooltip.isEmpty) d.rect,
        ];
        expect(wordless, isEmpty, reason: 'nodes that act but say nothing');
        handle.dispose();
      });
    }

    testWidgets('a MiniMonth day is chosen', (t) async {
      final handle = t.ensureSemantics();
      PlainDate? got;
      await _pump(t, MiniMonth(selected: _monday, today: _monday, onDateSelected: (d) => got = d));
      await _readerTap(t, 'mardi 10 novembre 2026');
      expect(got, PlainDate(2026, 11, 10));
      handle.dispose();
    });

    testWidgets('a month day is told, its "+N" opens the day, its long press the menu', (t) async {
      final handle = t.ensureSemantics();
      final c = _controller('dayGridMonth');
      addTearDown(c.dispose);
      Hit? tapped;
      await _pump(t, DzCalendar(controller: c, editable: true, onDateTap: (h) => tapped = h));
      await _readerTap(t, 'jeudi 12 novembre 2026');
      expect(tapped, isA<DayHit>().having((h) => h.date, 'date', PlainDate(2026, 11, 12)));

      await _readerTap(t, RegExp(r'^\d+ autres événements, mardi 10 novembre 2026'));
      expect(find.byType(BottomSheet), findsOneWidget);
      // In the sheet, an event's menu is a long press away, as in the grid.
      final inSheet = t.getSemantics(find.bySemanticsLabel(RegExp(r'^Consultation 5')).last);
      expect(inSheet, containsSemantics(hasTapAction: true, hasLongPressAction: true));
      handle.dispose();
    });

    testWidgets('a free slot is booked; the time grid\'s "+N" opens the day', (t) async {
      final handle = t.ensureSemantics();
      final c = _controller('timeGridDay');
      addTearDown(c.dispose);
      AvailableSlot? booked;
      await _pump(t, DzCalendar(controller: c, scrollHour: 8, onSlotTap: (s) => booked = s));
      await _readerTap(t, 'Créneau libre, de 14:00 à 14:30');
      expect(booked?.start, _at(14, 0));
      await _readerTap(t, RegExp(r'^\d+ autres événements, mardi 10 novembre 2026'));
      expect(find.byType(BottomSheet), findsOneWidget);
      handle.dispose();
    });

    testWidgets('without onSlotTap a free slot is said, not offered', (t) async {
      final handle = t.ensureSemantics();
      final c = _controller('timeGridDay');
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c, scrollHour: 8));
      expect(
        t.getSemantics(find.bySemanticsLabel(RegExp(r'^Créneau libre, de 14:00'))),
        isNot(containsSemantics(isButton: true)),
      );
      handle.dispose();
    });

    testWidgets('the timeline\'s "+N" opens the day', (t) async {
      final handle = t.ensureSemantics();
      final c = _controller('resourceTimelineDay');
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c, scrollHour: 8), size: const Size(1000, 800));
      await _readerTap(t, RegExp(r'^\d+ autres événements'));
      expect(find.byType(BottomSheet), findsOneWidget);
      handle.dispose();
    });

    testWidgets('in a year, a month\'s title opens it, a day is told', (t) async {
      final handle = t.ensureSemantics();
      final c = _controller('multiMonthYear');
      addTearDown(c.dispose);
      Hit? tapped;
      await _pump(t, DzCalendar(controller: c, onDateTap: (h) => tapped = h));
      // January, on screen at the top of the year.
      await _readerTap(t, RegExp(r'^jeudi 15 janvier 2026'));
      expect(tapped, isA<DayHit>().having((h) => h.date, 'date', PlainDate(2026, 1, 15)));
      await _readerTap(t, RegExp(r'^janvier 2026, '));
      expect(c.state.view.type, 'dayGridMonth');
      expect(c.state.date.month, 1);
      handle.dispose();
    });

    testWidgets('a list event has its menu', (t) async {
      final handle = t.ensureSemantics();
      final c = _controller('listWeek');
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c, editable: true, onEventTap: (_, _) {}));
      expect(
        t.getSemantics(find.bySemanticsLabel(RegExp(r'^Consultation 0')).first),
        containsSemantics(hasTapAction: true, hasLongPressAction: true),
      );
      handle.dispose();
    });
  });

  group('a large text on the narrowest phone', () {
    // iOS goes to about ×3.1. Every view, MiniMonth and the header alone, at 320
    // points: no overflow, in French and in Arabic.
    for (final v in [..._views, 'MiniMonth', 'CalendarHeader']) {
      for (final locale in const ['fr', 'ar']) {
        for (final scale in const [1.35, 2.0, 3.0]) {
          testWidgets('$v, $locale, ×$scale: nothing overflows', (t) async {
            final c = _controller(v == 'MiniMonth' || v == 'CalendarHeader' ? 'dayGridMonth' : v, locale: locale);
            addTearDown(c.dispose);
            final w = switch (v) {
              'MiniMonth' => MiniMonth(selected: _monday, today: _monday, locale: locale),
              'CalendarHeader' => CalendarHeader(controller: c),
              _ => DzCalendar(controller: c, editable: true, onSlotTap: (_) {}),
            };
            final errors = await _errorsOf(() => _pump(t, w, size: const Size(320, 640), locale: locale, scale: scale));
            expect(errors, isEmpty);
          });
        }
      }
    }

    // The switcher's words pushed the period's title to 0 wide from ×1.35 on: with
    // too little room it becomes an icon, and the title keeps its place.
    for (final scale in const [1.0, 1.35, 3.0]) {
      testWidgets('the header keeps its title (×$scale)', (t) async {
        final c = _controller('resourceTimelineDay');
        addTearDown(c.dispose);
        await _pump(
          t,
          CalendarHeader(controller: c, views: const ['resourceTimelineDay', 'timeGridDay']),
          size: const Size(320, 640),
          scale: scale,
        );
        expect(t.getSize(find.text(c.state.title)).width, greaterThan(60));
        expect(find.byTooltip('Affichage'), findsOneWidget);
        if (scale > 1) expect(find.text('Jour'), findsNothing);
      });
    }

    // At ×3 the day number is three times taller: the bars start under it, not
    // over it, and every column still names its day.
    testWidgets('a month at ×3: bars under the numbers, every day named', (t) async {
      final c = _controller('dayGridMonth');
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c, showHeader: false), size: const Size(320, 900), scale: 3);
      final number = t.getRect(find.text('11').first);
      final bar = t.getRect(find.ancestor(of: find.text('Congé'), matching: find.byType(Positioned)).first);
      expect(bar.top, greaterThanOrEqualTo(number.bottom - 1));
      for (final letter in const ['L', 'J', 'V', 'S', 'D']) {
        expect(find.text(letter), findsOneWidget);
      }
      expect(find.text('M'), findsNWidgets(2));
    });

    testWidgets('an all-day bar at ×2 is as tall as its words', (t) async {
      final c = _controller('timeGridWeek');
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c, showHeader: false), size: const Size(320, 640), scale: 2);
      // An 11-point label (Material's labelSmall) at ×2 is 22 points of type, 26
      // with its line height; the theme's bar alone is 18.
      final bar = t.getSize(find.ancestor(of: find.text('Congé'), matching: find.byType(Positioned)).first);
      expect(bar.height, greaterThanOrEqualTo(26));
    });

    testWidgets('with room, the switcher says the view', (t) async {
      final c = _controller('timeGridDay');
      addTearDown(c.dispose);
      await _pump(t, CalendarHeader(controller: c), size: const Size(800, 600));
      expect(find.text('Jour'), findsOneWidget);
    });
  });

  // A practice booking every 15 minutes: a block of 12 points at 48 an hour,
  // shorter than a line. Its title is cut, not overflowing (sehhaty-mobile).
  for (final locale in const ['fr', 'ar']) {
    testWidgets('15-minute events in a day ($locale): no overflow', (t) async {
      final c = _controller(
        'timeGridDay',
        locale: locale,
        events: [
          for (var k = 0; k < 4; k++)
            EventInput(
              id: 'q$k',
              title: 'Consultation de suivi $k',
              start: '2026-11-10T08:${(k * 15).toString().padLeft(2, '0')}',
              end: k == 3 ? '2026-11-10T09:00' : '2026-11-10T08:${((k + 1) * 15).toString().padLeft(2, '0')}',
            ),
        ],
      );
      addTearDown(c.dispose);
      final errors = await _errorsOf(
        () => _pump(
          t,
          DzCalendar(controller: c, scrollHour: 7),
          size: const Size(320, 640),
          locale: locale,
        ),
      );
      expect(errors, isEmpty);
      expect(find.textContaining('Consultation de suivi'), findsNWidgets(4));
    });
  }
}
