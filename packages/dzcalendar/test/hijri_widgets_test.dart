// Phase 19h-2: the Hijri calendar in the widgets (owner's decision 53).
// Expectations by hand from the published Umm al-Qura calendar: 1 Ramadan
// 1447 is Wednesday 18 February 2026, 1 Shaban 20 January 2026, 1 Rajab 21
// December 2025.
import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _zone = 'Africa/Algiers';
final _day = PlainDate(2026, 2, 18);

CalendarController _controller({
  String view = 'dayGridMonth',
  HijriCalendar? display,
  HijriCalendar? secondary,
  String locale = 'fr',
}) => CalendarController(
  KernelOptions(
    timeZone: _zone,
    locale: locale,
    initialDate: _day,
    initialView: view,
    now: () => ZonedDateTime.fromWall(PlainDateTime(_day, PlainTime(10)), _zone)!.instant,
    displayCalendar: display,
    secondaryCalendar: secondary,
  ),
  followAppLocale: false,
);

// The tests' font (Ahem) draws every glyph a square: wide cells, so "1 ram." fits beside "18".
Future<void> _pump(WidgetTester t, Widget w, {Size size = const Size(1400, 900), String locale = 'fr'}) async {
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

final _uq = HijriCalendar.ummAlQura;

void main() {
  testWidgets('display Hijri: the month titled by the Hijri months it spans, a month\'s first day marked', (t) async {
    final c = _controller(display: _uq);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c));
    // February 2026: 13 Shaban to 11 Ramadan.
    expect(find.text('chaa.–ram. 1447 AH'), findsOneWidget);
    // 18 February is 1 Ramadan; 19 February, 2.
    expect(find.text('1 ram.'), findsOneWidget);
  });

  testWidgets('secondary Hijri: the Gregorian number, the Hijri day beside it', (t) async {
    final c = _controller(secondary: _uq);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c));
    expect(find.text('février 2026'), findsOneWidget);
    final ramadan = find.text('1 ram.');
    expect(ramadan, findsOneWidget);
    // The 18th's number, in the same row as 1 Ramadan.
    final eighteen = find.descendant(
      of: find.ancestor(of: ramadan, matching: find.byType(Row)).first,
      matching: find.text('18'),
    );
    expect(eighteen, findsOneWidget);
    // Beside it, on its line, after it (left to right).
    expect(t.getCenter(ramadan).dy, closeTo(t.getCenter(eighteen).dy, 2));
    expect(t.getTopLeft(ramadan).dx, greaterThan(t.getTopRight(eighteen).dx - 1));
    // A screen reader hears both.
    expect(find.bySemanticsLabel(RegExp(r'mercredi 18 février 2026 \(1 ramadan 1447 AH\)')), findsOneWidget);
  });

  testWidgets('the week\'s heads: each day\'s Hijri date under its number', (t) async {
    final c = _controller(view: 'timeGridWeek', secondary: _uq);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c));
    // Monday 16 to Sunday 22 February: 28, 29 Shaban, 1 to 5 Ramadan.
    for (final h in ['28', '29', '1 ram.', '2', '3', '4', '5']) {
      expect(find.text(h), findsWidgets, reason: h);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('the year: each Gregorian month titled in Hijri', (t) async {
    final c = _controller(view: 'multiMonthYear', display: _uq);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c), size: const Size(1400, 900));
    // January 2026: 12 Rajab to 12 Shaban.
    expect(find.text('raj.–chaa. 1447 AH'), findsOneWidget);
    expect(find.text('1447–1448 AH'), findsWidgets);
  });

  testWidgets('the mini-month on a calendar: its numbers and its secondary days', (t) async {
    final c = _controller(secondary: _uq);
    addTearDown(c.dispose);
    await _pump(t, MiniMonth.controller(c));
    expect(find.text('février 2026'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'18 février 2026 \(1 ramadan 1447 AH\)')), findsOneWidget);
  });

  testWidgets('a phone, a month, Arabic, both calendars: built without overflow', (t) async {
    final c = _controller(locale: 'ar', display: _uq, secondary: HijriCalendar.civil);
    addTearDown(c.dispose);
    await _pump(
      t,
      DzCalendar(controller: c),
      size: const Size(360, 700),
      locale: 'ar',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('the controller switches calendars at run time', (t) async {
    final c = _controller();
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c));
    expect(find.text('1 ram.'), findsNothing);
    c.setSecondaryCalendar(_uq);
    await t.pumpAndSettle();
    expect(find.text('1 ram.'), findsOneWidget);
    c.setSecondaryCalendar(null);
    c.setDisplayCalendar(_uq);
    await t.pumpAndSettle();
    expect(find.text('chaa.–ram. 1447 AH'), findsOneWidget);
  });

  testWidgets('review: a phone\'s narrow cells drop the marker, then the secondary; nothing overflows', (t) async {
    final c = _controller(secondary: _uq);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c), size: const Size(360, 700));
    expect(t.takeException(), isNull);
    // 360 / 7 is about 51 px: "18" and "1 ram." (Ahem squares) do not fit together.
    expect(find.text('1 ram.'), findsNothing);
  });

  testWidgets('review: the keyboard says the day in the display calendar, the secondary after it', (t) async {
    final said = <String>[];
    t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
      final data = (m as Map)['data'] as Map?;
      final text = data?['message'];
      if (text is String) said.add(text);
      return null;
    });
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null),
    );
    final c = _controller(display: _uq, secondary: HijriCalendar.civil);
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c));
    await t.tap(find.text('1 ram.').first);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(said.last, startsWith('jeudi 2 ramadan ('));
  });

  testWidgets('review: the mini-month with a large text and a secondary date: no overflow, the date shown', (t) async {
    final c = _controller(secondary: _uq);
    addTearDown(c.dispose);
    t.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(t, SizedBox(width: 320, child: MiniMonth.controller(c)), size: const Size(400, 800));
    expect(t.takeException(), isNull);
    // Under the 18th, 1 Ramadan's "1".
    final cell = find.bySemanticsLabel(RegExp(r'18 février 2026 \(1 ramadan 1447 AH\)'));
    expect(find.descendant(of: cell, matching: find.text('18')), findsOneWidget);
    expect(find.descendant(of: cell, matching: find.text('1')), findsOneWidget);
  });
}
