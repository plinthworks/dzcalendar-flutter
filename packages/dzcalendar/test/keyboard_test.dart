// Phase 19e-2b-2: the keyboard and screen readers (owner's decisions 41–43).
// Expectations are written by hand: Monday 9 November 2026, Paris (UTC+1);
// the grid's hour is 48 px; the keyboard steps 15 minutes (snapMinutes).
import 'package:dzcalendar/dzcalendar.dart';
import 'package:dzcalendar/src/keyboard.dart' show keyLikeOf;
import 'package:dzcalendar/src/views/common.dart' show CursorBox;
import 'package:dzcalendar_core/internal.dart' show KeyLike;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _zone = 'Europe/Paris';
final _monday = PlainDate(2026, 11, 9);
final _now = _wall(_monday, 10, 20);

Instant _wall(PlainDate d, int h, int m) => ZonedDateTime.fromWall(PlainDateTime(d, PlainTime(h, m)), _zone)!.instant;

CalendarController _controller({
  String view = 'timeGridDay',
  List<EventInput> events = const [],
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
  ),
  followAppLocale: false,
  onEventChange: onEventChange,
);

Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(400, 800), String locale = 'fr'}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MediaQuery(
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
        home: Scaffold(body: w),
      ),
    ),
  );
  await t.pumpAndSettle();
}

EventInput _at(String id, String title, String start, String end, {String? rrule}) =>
    EventInput(id: id, title: title, start: start, end: end, rrule: rrule);

(Instant, Instant) _times(CalendarController c, String id) => switch (c.kernel.store.snapshot.getEvent(id)!) {
  TimedEvent(:final start, :final end) => (start.instant, end.instant),
  AllDayEvent() => throw StateError('all-day'),
};

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

Future<void> _key(WidgetTester t, LogicalKeyboardKey k, {bool shift = false, bool ctrl = false}) async {
  if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(k);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await t.pump();
}

/// A tap on the day view's slot at [hour] (the gutter's label is centred on its hour).
Future<void> _tapHour(WidgetTester t, String label, {double x = 300}) async {
  await t.tapAt(Offset(x, t.getCenter(find.text(label)).dy + 2));
  await t.pump();
}

void main() {
  testWidgets('a tap places the cursor; arrows step 15 minutes and a day, each said', (t) async {
    final said = _said(t);
    final c = _controller(view: 'timeGridWeek');
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8), size: const Size(1000, 800));
    // Monday is the first column after the gutter.
    await _tapHour(t, '09 h', x: 120);
    await _key(t, LogicalKeyboardKey.arrowDown);
    expect(said.last, 'lundi 9 novembre, 09:15');
    await _key(t, LogicalKeyboardKey.arrowRight);
    expect(said.last, 'mardi 10 novembre, 09:15');
    // Drawn once the keyboard is used.
    expect(find.byType(CursorBox), findsOneWidget);
    await _key(t, LogicalKeyboardKey.arrowUp);
    await _key(t, LogicalKeyboardKey.arrowUp);
    expect(said.last, 'mardi 10 novembre, 08:45');
  });

  testWidgets('Shift+arrows select; Enter hands the selection once', (t) async {
    final c = _controller();
    addTearDown(c.dispose);
    final handed = <CalendarSelection>[];
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, selectable: true, onSelect: (s, _) => handed.add(s)));
    await _tapHour(t, '09 h');
    handed.clear(); // the tap's own selection
    for (var k = 0; k < 3; k++) {
      await _key(t, LogicalKeyboardKey.arrowDown, shift: true);
    }
    // From 09:00 to the 09:45 slot: 09:00–10:00.
    final sel = c.selection! as TimeSelection;
    expect(sel.start.instant, _wall(_monday, 9, 0));
    expect(sel.end.instant, _wall(_monday, 10, 0));
    await _key(t, LogicalKeyboardKey.enter);
    await _key(t, LogicalKeyboardKey.enter);
    expect(handed, [sel]);
    // Escape clears it.
    await _key(t, LogicalKeyboardKey.escape);
    expect(c.selection, isNull);
  });

  testWidgets('Tab to an event, M holds it, four ↓ and Enter: one hour later, told and said', (t) async {
    final said = _said(t);
    final told = <EventChange>[];
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')], onEventChange: told.add);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await _tapHour(t, '13 h');
    await _key(t, LogicalKeyboardKey.tab);
    expect(said.last, 'Bilan, de 09:00 à 10:00');
    await _key(t, LogicalKeyboardKey.keyM);
    expect(said.last, startsWith('« Bilan » saisi.'));
    for (var k = 0; k < 4; k++) {
      await _key(t, LogicalKeyboardKey.arrowDown);
    }
    expect(said.last, 'lundi 9 novembre, de 10:00 à 11:00');
    // Nothing changed before Enter.
    expect(_times(c, 'a'), (_wall(_monday, 9, 0), _wall(_monday, 10, 0)));
    await _key(t, LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(_times(c, 'a'), (_wall(_monday, 10, 0), _wall(_monday, 11, 0)));
    expect(told, hasLength(1));
    expect(said, contains('« Bilan » déplacé à 10:00'));
  });

  testWidgets('Shift+↓ while held pulls its end; Escape lets go, nothing changes', (t) async {
    final said = _said(t);
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await _tapHour(t, '13 h');
    await _key(t, LogicalKeyboardKey.tab);
    await _key(t, LogicalKeyboardKey.keyM);
    await _key(t, LogicalKeyboardKey.arrowDown, shift: true);
    expect(said.last, 'lundi 9 novembre, de 09:00 à 10:15');
    await _key(t, LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(said.last, 'Déplacement annulé');
    expect(_times(c, 'a'), (_wall(_monday, 9, 0), _wall(_monday, 10, 0)));
    // Shift+↓ then Enter: it ends 15 minutes later.
    await _key(t, LogicalKeyboardKey.keyM);
    await _key(t, LogicalKeyboardKey.arrowDown, shift: true);
    await _key(t, LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(_times(c, 'a'), (_wall(_monday, 9, 0), _wall(_monday, 10, 15)));
    expect(said, contains('« Bilan » finit maintenant à 10:15'));
  });

  testWidgets('review: held from the keyboard, the focus leaving lets it go', (t) async {
    final said = _said(t);
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await _tapHour(t, '13 h');
    await _key(t, LogicalKeyboardKey.tab);
    await _key(t, LogicalKeyboardKey.keyM);
    await _key(t, LogicalKeyboardKey.arrowDown);
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    expect(said.last, 'Déplacement annulé');
    expect(find.byType(Opacity), findsNothing); // nothing left lifted
    expect(_times(c, 'a'), (_wall(_monday, 9, 0), _wall(_monday, 10, 0)));
  });

  test('review: an Arabic layout\'s key where M is reads as M (and Z, Y)', () {
    KeyLike? of(int logical, PhysicalKeyboardKey physical) => keyLikeOf(
      KeyDownEvent(physicalKey: physical, logicalKey: LogicalKeyboardKey(logical), timeStamp: Duration.zero),
    );
    // The Arabic layout writes "ة" where M is, "ئ" where Z is, "غ" where Y is.
    expect(of(0x0629, PhysicalKeyboardKey.keyM)?.key, 'm');
    expect(of(0x0626, PhysicalKeyboardKey.keyZ)?.key, 'z');
    expect(of(0x063A, PhysicalKeyboardKey.keyY)?.key, 'y');
    expect(of(0x0628, PhysicalKeyboardKey.keyF), isNotNull); // another letter: its own label
  });

  testWidgets('held from the keyboard, a tap on a slot puts it there', (t) async {
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await _tapHour(t, '13 h');
    await _key(t, LogicalKeyboardKey.tab);
    await _key(t, LogicalKeyboardKey.keyM);
    await _tapHour(t, '12 h');
    await t.pumpAndSettle();
    expect(_times(c, 'a'), (_wall(_monday, 12, 0), _wall(_monday, 13, 0)));
  });

  testWidgets('Delete removes the event the keyboard is on, said with the undo key', (t) async {
    final said = _said(t);
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    await _tapHour(t, '13 h');
    await _key(t, LogicalKeyboardKey.tab);
    await _key(t, LogicalKeyboardKey.delete);
    await t.pumpAndSettle();
    expect(c.kernel.store.snapshot.getEvent('a'), isNull);
    expect(said.last, '« Bilan » supprimé. Ctrl+Z pour annuler.');
    // Ctrl+Z brings it back (decision 43: an editable calendar's).
    await _key(t, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(c.kernel.store.snapshot.getEvent('a'), isNotNull);
    expect(said.last, 'Annulé');
  });

  testWidgets('undo keys: not on a read-only calendar, nor with keyboardUndo off', (t) async {
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    final move = MoveEvent('a', ZonedDateTime(_wall(_monday, 11, 0), _zone));
    await _pump(t, DzCalendar(controller: c, scrollHour: 8));
    c.run(move);
    await t.pump();
    await _tapHour(t, '13 h');
    await _key(t, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(_times(c, 'a').$1, _wall(_monday, 11, 0));
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true, keyboardUndo: false));
    await _tapHour(t, '13 h');
    await _key(t, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(_times(c, 'a').$1, _wall(_monday, 11, 0));
    // The app's own undo is never gated.
    expect(c.undo(), isTrue);
    expect(_times(c, 'a').$1, _wall(_monday, 9, 0));
  });

  testWidgets('a month: PageDown goes to the same day next month; Enter walks into its events', (t) async {
    final said = _said(t);
    final c = _controller(view: 'dayGridMonth', events: [_at('a', 'Bilan', '2026-12-09T09:00', '2026-12-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c));
    // Today's cell (10 Nov is not today: 9 Nov is, the clock is frozen at 10:20 that day).
    await t.tap(find.text('9').first);
    await t.pump();
    await _key(t, LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(c.state.range.activeStart, PlainDate(2026, 12, 1));
    expect(said.last, 'mercredi 9 décembre');
    await _key(t, LogicalKeyboardKey.enter);
    expect(said.last, startsWith('Bilan, '));
    await _key(t, LogicalKeyboardKey.escape);
    expect(said.last, 'mercredi 9 décembre');
  });

  testWidgets('right to left: → goes back a day', (t) async {
    final said = _said(t);
    final c = _controller(view: 'dayGridMonth', locale: 'ar');
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c), locale: 'ar');
    await t.tap(find.text('٩').first);
    await t.pump();
    await _key(t, LogicalKeyboardKey.arrowRight);
    expect(said.last, contains('٨'));
  });

  testWidgets('a screen reader: "Move…", swipe up four times, double tap: one hour later', (t) async {
    final handle = t.ensureSemantics();
    final told = <EventChange>[];
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')], onEventChange: told.add);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8, editable: true));
    final event = find.semantics.byLabel('Bilan, de 09:00 à 10:00');
    t.semantics.customAction(event, const CustomSemanticsAction(label: 'Déplacer…'));
    await t.pump();
    for (var k = 0; k < 4; k++) {
      t.semantics.increase(event);
      await t.pump();
    }
    expect(_times(c, 'a').$1, _wall(_monday, 9, 0));
    t.semantics.tap(event);
    await t.pumpAndSettle();
    expect(_times(c, 'a'), (_wall(_monday, 10, 0), _wall(_monday, 11, 0)));
    expect(told, hasLength(1));
    handle.dispose();
  });

  testWidgets('a screen reader: a read-only calendar offers no editing actions', (t) async {
    final handle = t.ensureSemantics();
    final c = _controller(events: [_at('a', 'Bilan', '2026-11-09T09:00', '2026-11-09T10:00')]);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8));
    final node = find.semantics.byLabel('Bilan, de 09:00 à 10:00').evaluate().single;
    expect(node.getSemanticsData().customSemanticsActionIds ?? const [], isEmpty);
    handle.dispose();
  });
}
