import 'package:dzcalendar/dzcalendar.dart';
import 'package:dzcalendar_showcase/src/app.dart';
import 'package:dzcalendar_showcase/src/book.dart';
import 'package:dzcalendar_showcase/src/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final today = PlainDate(2026, 11, 11);

Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1280, 820),
  Locale locale = const Locale('fr'),
  String? view,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShowcaseApp(
      today: today,
      view: view,
      settings: Settings(locale: locale, mode: ThemeMode.light),
    ),
  );
  // The holidays are read from the bundled .ics, asynchronously: until the
  // fourth calendar is there.
  final book = (tester.state(find.byType(HomePage)) as dynamic).book as CalendarBook;
  for (var k = 0; k < 100 && book.calendars.length < 4; k++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(book.calendars.length, 4);
  await tester.pumpAndSettle();
}

void main() {
  // rootBundle keeps the future of a load, made in the fake time of the test
  // that started it: each test reads the file again.
  setUp(() => rootBundle.evict('assets/holidays_dz.ics'));

  testWidgets('wide: the sidebar, its calendars, the week of today', (tester) async {
    await pumpApp(tester);
    expect(find.text('9–15 nov. 2026'), findsOneWidget);
    for (final name in ['Cabinet', 'Maison', 'Sport', 'Jours fériés (Algérie)']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Piscine'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('narrow: a drawer and a button for a new event; a day at start', (tester) async {
    await pumpApp(tester, size: const Size(390, 844));
    expect(find.text('Cabinet'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Consultations'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Cabinet'), findsOneWidget);
  });

  testWidgets('unticking Sport takes its events off; ticking brings them back', (tester) async {
    await pumpApp(tester);
    expect(find.text('Piscine'), findsOneWidget);
    await tester.tap(find.text('Sport'));
    await tester.pumpAndSettle();
    expect(find.text('Piscine'), findsNothing);
    await tester.tap(find.text('Sport'));
    await tester.pumpAndSettle();
    expect(find.text('Piscine'), findsOneWidget);
  });

  testWidgets('the inspector: an occurrence renamed for this one, then undone from the menu', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Piscine'));
    await tester.pumpAndSettle();
    expect(find.text('Chaque semaine'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Piscine'), 'Piscine olympique');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    // An occurrence: how far?
    expect(find.text('Modifier quelles occurrences ?'), findsOneWidget);
    await tester.tap(find.text('Celle-ci seulement'));
    await tester.pumpAndSettle();
    expect(find.text('Piscine olympique'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Piscine olympique'), findsNothing);
    expect(find.text('Piscine'), findsOneWidget);
  });

  testWidgets('a holiday is read-only: no save, no delete', (tester) async {
    await pumpApp(tester, view: 'dayGridMonth');
    await tester.tap(find.text('Fête de la Révolution'));
    await tester.pumpAndSettle();
    expect(find.text('Ce calendrier est en lecture seule.'), findsOneWidget);
    expect(find.text('Enregistrer'), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('a new event from the toolbar, then deleted', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Nouvel événement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nouvel événement'), 'Pharmacie');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.text('Pharmacie'), findsOneWidget);

    await tester.tap(find.text('Pharmacie'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('Pharmacie'), findsNothing);
  });

  testWidgets('search: results beside the calendar; one goes to its day', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Rechercher'), 'congrès');
    await tester.pumpAndSettle();
    final hit = find.text('Congrès de cardiologie');
    expect(hit, findsOneWidget);
    await tester.tap(hit);
    await tester.pumpAndSettle();
    expect(find.text('16–22 nov. 2026'), findsOneWidget);
  });

  testWidgets('in Arabic, right to left, wide: built without overflow', (tester) async {
    await pumpApp(tester, locale: const Locale('ar'));
    expect(find.text('التقويمات'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Arabic, a narrow month: built without overflow', (tester) async {
    await pumpApp(tester, locale: const Locale('ar'), size: const Size(390, 844), view: 'dayGridMonth');
    expect(find.text('شهر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review: saving into an unticked calendar ticks it', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Maison'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Piscine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sport').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maison').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    final home = tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Maison'));
    expect(home.value, isTrue);
    expect(find.text('Courses'), findsOneWidget);
    expect(find.text('Piscine'), findsOneWidget);
  });

  testWidgets('review: search results follow a calendar unticked', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Rechercher'), 'piscine');
    await tester.pumpAndSettle();
    expect(find.text('Piscine'), findsWidgets);
    final before = find.text('Piscine').evaluate().length;
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Sport'));
    await tester.pumpAndSettle();
    expect(find.text('Piscine'), findsNothing);
    expect(before, greaterThan(1));
    expect(find.text('Aucun événement trouvé'), findsOneWidget);
  });

  testWidgets('the year: a day tapped opens it', (tester) async {
    await pumpApp(tester, view: 'multiMonthYear');
    expect(find.text('2026'), findsOneWidget);
    // 25 January 2026, the first month's.
    final day = find.descendant(of: find.byType(DzCalendar), matching: find.text('25'));
    await tester.tap(day.first);
    await tester.pumpAndSettle();
    expect(find.textContaining('25 janvier 2026'), findsOneWidget);
  });
}
