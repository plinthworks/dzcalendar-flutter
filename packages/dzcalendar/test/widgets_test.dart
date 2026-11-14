import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _zone = 'Europe/Paris';
final _monday = PlainDate(2026, 11, 9);
final _now = ZonedDateTime.fromWall(PlainDateTime(_monday, PlainTime(10, 20)), _zone)!.instant;

CalendarController _controller({
  String view = 'timeGridWeek',
  List<EventInput> events = const [],
  List<ResourceInput> resources = const [],
  String locale = 'fr',
}) => CalendarController(
  KernelOptions(
    timeZone: _zone,
    locale: locale,
    initialDate: _monday,
    initialView: view,
    now: () => _now,
    events: events,
    resources: resources,
  ),
);

Widget _app(Widget child, {String locale = 'fr', Size size = const Size(400, 800)}) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp(
    locale: Locale(locale),
    supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
    localizationsDelegates: const [
      DzCalendarLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  ),
);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 800), String locale = 'fr'}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(_app(w, locale: locale, size: size));
  await t.pumpAndSettle();
}

EventInput _at(String id, String title, String start, String end, {String? resourceId}) =>
    EventInput(id: id, title: title, start: start, end: end, resourceId: resourceId);

void main() {
  group('CalendarController', () {
    testWidgets('a change made during a build is told after it, once', (t) async {
      final c = _controller();
      addTearDown(c.dispose);
      var told = 0;
      c.addListener(() => told++);
      // The first build happens outside any frame (as `runApp`'s): the phase cannot tell it.
      await t.pumpWidget(
        Builder(
          builder: (context) {
            // What DzCalendar does in didChangeDependencies: setters during a build.
            c.setLocale('en');
            c.setView('dayGridMonth');
            expect(told, 0, reason: 'not during the build');
            return const SizedBox();
          },
        ),
      );
      await t.pump();
      expect(told, 1, reason: 'one notification for both changes');
      expect(c.state.locale, 'en');
      expect(c.state.view.type, 'dayGridMonth');
      expect(c.changes.length, 2);
    });

    testWidgets('a listener may rebuild what it likes: no "setState during build"', (t) async {
      final c = _controller();
      addTearDown(c.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: c,
          builder: (context, _) => Builder(
            builder: (context) {
              c.setLocale('en');
              return Text(c.state.locale, textDirection: TextDirection.ltr);
            },
          ),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('en'), findsOneWidget);
    });

    testWidgets('outside a build, before the next frame', (t) async {
      final c = _controller();
      addTearDown(c.dispose);
      var told = 0;
      c.addListener(() => told++);
      c.next();
      c.next();
      await t.pump();
      expect(told, 1);
      expect(c.state.date, PlainDate(2026, 11, 23));
    });

    test('a kernel handed in is left running', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final k = CalendarKernel(KernelOptions(timeZone: _zone, locale: 'fr', initialDate: _monday, now: () => _now));
      CalendarController.of(k).dispose();
      k.navigate(NavDirection.next); // would throw on a disposed kernel
      expect(k.state.date, PlainDate(2026, 11, 16));
      k.dispose();
    });
  });

  group('DzCalendar', () {
    testWidgets('a week: the title in French, the events, the week number', (t) async {
      final c = _controller(events: [_at('a', 'Consultation', '2026-11-09T09:00', '2026-11-09T09:30')]);
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c));
      expect(find.text('9–15 nov. 2026'), findsOneWidget);
      expect(find.text('Consultation'), findsOneWidget);
      expect(find.text('S46'), findsOneWidget);
    });

    testWidgets('a tap at 09:12 in a day selects the 09:00 slot (30 min)', (t) async {
      final c = _controller(view: 'timeGridDay');
      c.setOptions(c.options.copyWith(timeGrid: const TimeGridSettings(slotMinutes: 30)));
      addTearDown(c.dispose);
      Hit? hit;
      CalendarSelection? selected;
      await _pump(
        t,
        DzCalendar(controller: c, scrollHour: 8, onDateTap: (h) => hit = h, onSelect: (s, _) => selected = s),
      );
      // The gutter's "09 h" is centred on 09:00 (hours are 48 px tall); 12 minutes = 9.6 px below.
      final nine = t.getCenter(find.text('09 h'));
      await t.tapAt(Offset(300, nine.dy + 9.6));
      await t.pump();
      expect(hit, isA<SlotHit>());
      final s = hit! as SlotHit;
      expect(ZonedDateTime(s.slotStart!, _zone).plainDateTime, PlainDateTime(_monday, PlainTime(9)));
      final sel = selected! as TimeSelection;
      expect(sel.start.plainDateTime, PlainDateTime(_monday, PlainTime(9)));
      expect(sel.end.plainDateTime, PlainDateTime(_monday, PlainTime(9, 30)));
      expect(c.selection, sel);
    });

    testWidgets('a crowded day in a short month says "+N autres", which lists them', (t) async {
      final c = _controller(
        view: 'dayGridMonth',
        events: [
          for (var i = 0; i < 6; i++)
            _at(
              'e$i',
              'Rdv $i',
              '2026-11-10T${(8 + i).toString().padLeft(2, '0')}:00',
              '2026-11-10T${(8 + i).toString().padLeft(2, '0')}:30',
            ),
        ],
      );
      addTearDown(c.dispose);
      // 600 px: the header (56) and weekday names (~30) leave ~514 px for six rows of ~86 px;
      // under the 24 px day number, lanes of 18 + 2 px: (86 − 24) / 20 → 3 lanes, the "+N" in the last.
      await _pump(t, DzCalendar(controller: c), size: const Size(400, 600));
      expect(c.options.dayGrid.maxLanes, isNull, reason: "the widget fits without touching the calendar's options");
      // Two bars, then "+4" in the third lane.
      expect(find.text('+4 autres'), findsOneWidget);
      await t.tap(find.text('+4 autres'));
      await t.pumpAndSettle();
      expect(find.text('mardi 10 novembre 2026'), findsOneWidget);
      // The sheet lists all six (scrolled to the last).
      await t.scrollUntilVisible(find.text('Rdv 5'), 40, scrollable: find.byType(Scrollable).last);
      expect(find.text('Rdv 5'), findsWidgets);
    });

    testWidgets('editable: a long press holds an event, a tap then offers Delete (undoable)', (t) async {
      final c = _controller(events: [_at('a', 'Bilan', '2026-11-10T09:00', '2026-11-10T10:00')]);
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
      await t.longPress(find.text('Bilan'));
      await t.pumpAndSettle();
      // Held (decision 35): no menu yet, the handle and the menu button show.
      expect(find.text('Supprimer'), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      await t.tap(find.text('Bilan'));
      await t.pumpAndSettle();
      expect(find.text('Supprimer'), findsOneWidget);
      await t.tap(find.text('Supprimer'));
      await t.pumpAndSettle();
      expect(find.text('Bilan'), findsNothing);
      c.undo();
      await t.pumpAndSettle();
      expect(find.text('Bilan'), findsOneWidget);
    });

    testWidgets('right to left in Arabic: "previous" on the right, Saturday first', (t) async {
      final c = _controller(locale: 'ar', view: 'dayGridMonth');
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c), locale: 'ar');
      // Both at the start of the line (the right), "previous" first: further right than "next".
      final previous = t.getCenter(find.byTooltip('السابق')).dx;
      final next = t.getCenter(find.byTooltip('التالي')).dx;
      expect(previous, greaterThan(200));
      expect(previous, greaterThan(next));
      // `ar` (Egypt's week): Saturday first, drawn on the right.
      expect(t.getCenter(find.text('السبت')).dx, greaterThan(t.getCenter(find.text('الجمعة')).dx));
    });

    testWidgets('a year: as many months a row as fit, one on a phone', (t) async {
      final c = _controller(view: 'multiMonthYear');
      addTearDown(c.dispose);
      Offset at(String month) => t.getTopLeft(find.text(month));
      await _pump(t, DzCalendar(controller: c, showHeader: false), size: const Size(1000, 900));
      // 1000 px: four months of 240 px or more a row (macOS Calendar's 4 × 3).
      expect(at('janvier 2026').dy, at('avril 2026').dy);
      expect(at('mai 2026').dy, greaterThan(at('avril 2026').dy));
      await _pump(t, DzCalendar(controller: c, showHeader: false), size: const Size(400, 900));
      expect(at('février 2026').dy, greaterThan(at('janvier 2026').dy));
      expect(at('février 2026').dx, at('janvier 2026').dx);
    });

    testWidgets('a time grid narrower than its columns builds only those on screen', (t) async {
      final resources = [for (var i = 0; i < 30; i++) ResourceInput(id: 'r$i', title: 'R$i')];
      final c = _controller(
        view: 'resourceTimeGridDay',
        resources: resources,
        events: [
          for (var i = 0; i < 30; i++) _at('e$i', 'E$i', '2026-11-09T09:00', '2026-11-09T10:00', resourceId: 'r$i'),
        ],
      );
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c, scrollHour: 8));
      // 400 px − 48 gutter = 352 px; columns of 44 px: 8 on screen, one more built.
      expect(find.text('E0'), findsOneWidget);
      expect(find.text('E8'), findsOneWidget);
      expect(find.text('E9'), findsNothing);
      expect(find.text('E29'), findsNothing);
    });
  });

  group('review 19e-2a', () {
    testWidgets('a week too narrow for its columns, with an all-day bar, scrolls sideways (no crash)', (t) async {
      final c = _controller(
        events: [
          EventInput(id: 'd', title: 'Congrès', start: '2026-11-10', end: '2026-11-12', allDay: true),
          _at('a', 'Bilan', '2026-11-15T09:00', '2026-11-15T10:00'),
        ],
      );
      addTearDown(c.dispose);
      // 300 px − 48 gutter = 252 px for 7 columns of at least 44 px: 308 px, so they scroll.
      await _pump(t, DzCalendar(controller: c, scrollHour: 8), size: const Size(300, 700));
      await t.drag(find.text('Congrès'), const Offset(-150, 0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // The body followed the heads: Sunday's event is now on screen.
      expect(find.text('Bilan'), findsOneWidget);
    });

    testWidgets('a grid starting at 08:00 labels 08:00', (t) async {
      final c = _controller(view: 'timeGridDay');
      c.setOptions(c.options.copyWith(timeGrid: const TimeGridSettings(slotMin: Duration(hours: 8))));
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c));
      expect(find.text('08 h'), findsOneWidget);
    });

    testWidgets('Paris, 29 March 2026: the skipped hour is a band, 02:00 struck through', (t) async {
      final c = CalendarController(
        KernelOptions(
          timeZone: _zone,
          locale: 'fr',
          initialDate: PlainDate(2026, 3, 29),
          initialView: 'timeGridDay',
          now: () => _now,
          events: [_at('n', 'Garde', '2026-03-29T01:30', '2026-03-29T03:30')],
        ),
      );
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c, scrollHour: 0));
      expect(find.text("02:00–03:00 n'existe pas"), findsOneWidget);
      final two = t.widget<Text>(find.text('02 h'));
      expect(two.style?.decoration, TextDecoration.lineThrough);
      // 01:30 → 03:30 CEST is one real hour.
      expect(find.textContaining('1 h réelles'), findsOneWidget);
    });

    testWidgets('Paris, 25 October 2026: the repeated hour; 02:30 of the second pass marked *', (t) async {
      final c = CalendarController(
        KernelOptions(
          timeZone: _zone,
          locale: 'fr',
          initialDate: PlainDate(2026, 10, 25),
          initialView: 'timeGridDay',
          now: () => _now,
          // 02:30 CET (+01:00) is the second 02:30, an hour after the first.
          events: [_at('n', 'Ronde', '2026-10-25T02:30+01:00', '2026-10-25T04:00+01:00')],
        ),
      );
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c, scrollHour: 0));
      expect(find.text('02:00–03:00 a lieu deux fois'), findsOneWidget);
      expect(find.textContaining('02:30* – 04:00'), findsOneWidget);
    });

    testWidgets('the mini month browsed by hand follows the calendar again when it moves', (t) async {
      final c = _controller(view: 'timeGridDay');
      addTearDown(c.dispose);
      await _pump(t, MiniMonth.controller(c));
      await t.tap(find.byTooltip('Suivant'));
      await t.pump();
      await t.tap(find.byTooltip('Suivant'));
      await t.pump();
      expect(find.text('janvier 2027'), findsOneWidget);
      c.goTo(PlainDate(2026, 12, 3));
      await t.pump();
      expect(find.text('décembre 2026'), findsOneWidget);
    });

    testWidgets('a month on screen, then the controller disposed: nothing runs on it after', (t) async {
      final c = _controller(view: 'dayGridMonth');
      await _pump(t, DzCalendar(controller: c));
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.pump(const Duration(minutes: 2));
      expect(t.takeException(), isNull);
    });

    testWidgets('navigating clears the selection', (t) async {
      final c = _controller(view: 'dayGridMonth');
      addTearDown(c.dispose);
      await _pump(t, DzCalendar(controller: c));
      await t.tap(find.text('18'));
      await t.pump();
      expect(c.selection, isA<DaySelection>());
      c.next();
      await t.pump();
      expect(c.selection, isNull);
    });

    testWidgets("SlotPicker<T> on the app's own objects: seats said, a full slot not tappable", (t) async {
      final at = ZonedDateTime.fromWall(PlainDateTime(_monday, PlainTime(9)), _zone)!.instant;
      final items = [
        (start: at, seats: 2),
        (start: Instant.fromEpochMilliseconds(at.epochMilliseconds + 1800000), seats: 0),
      ];
      ({Instant start, int seats})? picked;
      await _pump(
        t,
        SlotPicker<({Instant start, int seats})>(
          items: items,
          startOf: (i) => i.start,
          endOf: (i) => Instant.fromEpochMilliseconds(i.start.epochMilliseconds + 1800000),
          displayZone: _zone,
          seatsOf: (i) => i.seats,
          enabledOf: (i) => i.seats > 0,
          onSelected: (i) => picked = i,
        ),
      );
      expect(find.text('09:00 · 2 places'), findsOneWidget);
      await t.tap(find.text('09:30 · 0 place'));
      expect(picked, isNull);
      await t.tap(find.text('09:00 · 2 places'));
      expect(picked, items.first);
    });
  });

  group('words', () {
    test('Arabic counts: plural forms and the dates\' digits', () {
      const ar = DzCalendarLocalizationsAr();
      expect(ar.slotCount(1), 'موعد واحد');
      expect(ar.slotCount(2), 'موعدان');
      expect(ar.slotCount(3), '٣ مواعيد');
      expect(ar.slotCount(11), '١١ موعدًا');
      expect(ar.slotCount(100), '١٠٠ موعد');
      expect(ar.weekShort(46), 'أ٤٦');
      expect(ar.duration(150), '٢ س ٣٠');
      expect(const DzCalendarLocalizationsFr().duration(65), '1 h 05');
      expect(const DzCalendarLocalizationsEn().duration(45), '45 min');
      // A locale intl has no data for: English numbers, no throw.
      expect(const DzCalendarLocalizationsEn('tlh').weekShort(7), 'W7');
    });

    test('French: 0 and 1 singular', () {
      const fr = DzCalendarLocalizationsFr();
      expect(fr.slotCount(0), '0 créneau');
      expect(fr.slotCount(1), '1 créneau');
      expect(fr.slotCount(2), '2 créneaux');
      expect(fr.viewName('timeGridWeek'), 'Semaine');
      expect(fr.viewName('resourceDayGridMonth'), 'Mois');
      expect(fr.viewName('custom'), 'custom');
    });

    testWidgets('without the delegate: English, no throw', (t) async {
      late DzCalendarLocalizations l;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              l = DzCalendarLocalizations.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(l.today, 'Today');
    });

    testWidgets('a delegate can change a word', (t) async {
      late DzCalendarLocalizations l;
      await t.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          supportedLocales: const [Locale('fr')],
          localizationsDelegates: [
            DzCalendarLocalizationsDelegate(customize: (locale, shipped) => _Clinic(locale.toLanguageTag())),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Builder(
            builder: (context) {
              l = DzCalendarLocalizations.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(l.noSlots, 'Aucun rendez-vous disponible');
      expect(l.today, "Aujourd'hui");
    });
  });

  group('SlotPicker', () {
    List<Slot> slots(PlainDate from, int days, ZoneId zone) {
      final rules = SlotRules(
        availability: Availability(
          timeZone: zone,
          weekly: [
            WeeklyWindow(days: const [1, 2, 3, 4, 5, 6, 7], window: const Window(WallTime(1), WallTime(4))),
          ],
        ),
        duration: const Duration(minutes: 30),
      );
      return findSlots(
        rules,
        from: ZonedDateTime.fromWall(PlainDateTime(from, PlainTime.midnight), zone)!.instant,
        to: ZonedDateTime.fromWall(PlainDateTime(from.addDays(days), PlainTime.midnight), zone)!.instant,
      ).slots;
    }

    testWidgets('the repeated hour of a fall-back night: each 02:30 with its offset', (t) async {
      // Paris, Sunday 25 October 2026: 03:00 CEST → 02:00 CET; 01:00–04:00 is four hours.
      Slot? picked;
      await _pump(
        t,
        SlotPicker.fromSlots(slots: slots(PlainDate(2026, 10, 25), 1, _zone), onSelected: (s) => picked = s),
      );
      expect(find.text('02:30 (UTC+02:00)'), findsOneWidget);
      expect(find.text('02:30 (UTC+01:00)'), findsOneWidget);
      expect(find.text('01:30'), findsOneWidget);
      expect(find.text('8 créneaux'), findsOneWidget);
      await t.tap(find.text('02:30 (UTC+01:00)'));
      expect(picked!.start.offset, '+01:00');
    });

    testWidgets('days to choose from; another day shows its times', (t) async {
      await _pump(t, SlotPicker.fromSlots(slots: slots(PlainDate(2026, 11, 9), 2, _zone)));
      expect(find.text('lundi 9 novembre 2026'), findsOneWidget);
      await t.tap(find.text('10'));
      await t.pump();
      expect(find.text('mardi 10 novembre 2026'), findsOneWidget);
    });

    // A screen reader activates what it reads. `excludeSemantics` around an InkWell or
    // a button drops the child's tap action with its label: VoiceOver and TalkBack said
    // "Monday 9 November, 6 slots, button", and a double tap did nothing — neither a
    // day nor a time could be chosen without sight (found 2026-11-14).
    testWidgets('a screen reader can choose a day and a time', (t) async {
      final handle = t.ensureSemantics();
      Slot? picked;
      await _pump(
        t,
        SlotPicker.fromSlots(slots: slots(PlainDate(2026, 11, 9), 2, _zone), onSelected: (s) => picked = s),
      );
      final day = find.bySemanticsLabel(RegExp(r'^mardi 10 novembre 2026, '));
      expect(t.getSemantics(day), containsSemantics(isButton: true, hasTapAction: true));
      t.getSemantics(day).owner!.performAction(t.getSemantics(day).id, SemanticsAction.tap);
      await t.pump();
      expect(find.text('mardi 10 novembre 2026'), findsOneWidget);

      final time = find.bySemanticsLabel(RegExp(r'^Créneau libre, de 01:00 à 01:30'));
      expect(t.getSemantics(time), containsSemantics(isButton: true, hasTapAction: true));
      t.getSemantics(time).owner!.performAction(t.getSemantics(time).id, SemanticsAction.tap);
      await t.pump();
      expect(picked, isNotNull);
      handle.dispose();
    });

    // A dialog asks its content for an intrinsic width: no LayoutBuilder in the way.
    testWidgets('in a dialog', (t) async {
      await _pump(t, AlertDialog(content: SlotPicker.fromSlots(slots: slots(PlainDate(2026, 11, 9), 2, _zone))));
      expect(t.takeException(), isNull);
      expect(find.text('lundi 9 novembre 2026'), findsOneWidget);
    });

    testWidgets('no slot: says so', (t) async {
      await _pump(t, SlotPicker.fromSlots(slots: const []));
      expect(find.text('Aucun créneau libre'), findsOneWidget);
    });

    // The largest accessibility text (iOS goes to about ×3.1) on the narrowest phone
    // shipped (320 points): a day strip of fixed height overflowed from ×1.35 on — found
    // by the first app to use the picker (2026-11-14). Arabic has taller lines too.
    // Both in a scrolling parent and as a screen's body: there the times scroll under
    // the days (owner, 2026-11-14), and the last one can be reached.
    for (final scrolled in const [true, false]) {
      for (final locale in const ['fr', 'ar']) {
        for (final scale in const [1.35, 2.0, 3.0]) {
          final where = scrolled ? 'in a scroll view' : 'as a body';
          testWidgets('a large text at 320 points does not overflow ($where, $locale, ×$scale)', (t) async {
            final picker = SlotPicker.fromSlots(slots: slots(PlainDate(2026, 11, 9), 3, _zone));
            await _pump(
              t,
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: scrolled ? SingleChildScrollView(child: picker) : picker,
                ),
              ),
              size: const Size(320, 640),
              locale: locale,
            );
            expect(t.takeException(), isNull);
            if (!scrolled) {
              final times = find.byType(OutlinedButton);
              await t.scrollUntilVisible(times.last, 100, scrollable: find.byType(Scrollable).last);
              expect(t.takeException(), isNull);
            }
          });
        }
      }
    }
  });

  group('MiniMonth', () {
    testWidgets('on a calendar: a tap goes to the day', (t) async {
      final c = _controller(view: 'timeGridDay');
      addTearDown(c.dispose);
      await _pump(t, MiniMonth.controller(c));
      expect(find.text('novembre 2026'), findsOneWidget);
      await t.tap(find.text('20'));
      await t.pump();
      expect(c.state.date, PlainDate(2026, 11, 20));
    });

    testWidgets('alone: the week starts on the locale\'s day, a tap is told', (t) async {
      PlainDate? got;
      await _pump(t, MiniMonth(selected: _monday, today: _monday, onDateSelected: (d) => got = d));
      // French: Monday first; November 2026 starts on a Sunday, so 26 October opens the grid.
      final first = find.text('26');
      expect(first, findsWidgets);
      await t.tap(find.text('17'));
      expect(got, PlainDate(2026, 11, 17));
    });
  });
}

class _Clinic extends DzCalendarLocalizationsFr {
  const _Clinic(super.localeName);
  @override
  String get noSlots => 'Aucun rendez-vous disponible';
}
