// Phase 19i-1: a calendar fed by a source (owner's decision 54).
import 'dart:async';

import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _zone = 'Africa/Algiers';
final _day = PlainDate(2026, 11, 11);

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(800, 900);
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
}

void main() {
  testWidgets('a source answering later: loading, then its events drawn; the next week asked as it is shown', (
    t,
  ) async {
    final asked = <String>[];
    final answers = <Completer<List<EventInput>>>[];
    final c = CalendarController(
      KernelOptions(
        timeZone: _zone,
        locale: 'fr',
        initialDate: _day,
        initialView: 'timeGridWeek',
        now: () => ZonedDateTime.fromWall(PlainDateTime(_day, PlainTime(8)), _zone)!.instant,
        sources: [
          fnSource('agenda', (r) {
            asked.add('${r.window!.startDate}..${r.window!.endDate}');
            final a = Completer<List<EventInput>>();
            answers.add(a);
            return a.future;
          }, chunk: const ChunkPolicy(ChunkUnit.week)),
        ],
      ),
      followAppLocale: false,
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8));
    expect(asked, ['2026-11-09..2026-11-16']);
    expect(c.loadingListenable.value, isTrue);
    answers[0].complete([EventInput(id: 'a', title: 'Consultation', start: '2026-11-11T09:00[Africa/Algiers]')]);
    await t.pumpAndSettle();
    expect(c.loadingListenable.value, isFalse);
    expect(find.text('Consultation'), findsOneWidget);
    expect(c.kernel.store.snapshot.getEvent('a')?.sourceId, 'agenda');

    c.next();
    await t.pump();
    expect(asked, ['2026-11-09..2026-11-16', '2026-11-16..2026-11-23']);
    expect(c.loadingListenable.value, isTrue);
    answers[1].complete([]);
    await t.pumpAndSettle();
    expect(c.loadingListenable.value, isFalse);
  });

  testWidgets('a source added at run time; removed, its events go', (t) async {
    final c = CalendarController(
      KernelOptions(timeZone: _zone, locale: 'fr', initialDate: _day, initialView: 'timeGridWeek'),
      followAppLocale: false,
    );
    addTearDown(c.dispose);
    await _pump(t, DzCalendar(controller: c, scrollHour: 8));
    c.sources.add(
      arraySource('fixed', [EventInput(id: 'b', title: 'Garde', start: '2026-11-12T09:00[Africa/Algiers]')]),
    );
    await t.pumpAndSettle();
    expect(find.text('Garde'), findsOneWidget);
    c.sources.remove('fixed');
    await t.pumpAndSettle();
    expect(find.text('Garde'), findsNothing);
  });
}
