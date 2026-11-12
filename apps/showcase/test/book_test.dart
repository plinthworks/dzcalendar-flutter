import 'package:dzcalendar/dzcalendar.dart';
import 'package:dzcalendar_core/dzcalendar_core.dart' show QueryOptions, TimeGridViewModel, viewWindow;
import 'package:dzcalendar_showcase/src/book.dart';
import 'package:dzcalendar_showcase/src/demo.dart';
import 'package:dzcalendar_showcase/src/draft.dart';
import 'package:flutter_test/flutter_test.dart';

// Wednesday 11 November 2026, 10:20 in Algiers (UTC+1, no clock change).
final today = PlainDate(2026, 11, 11);
final now = ZonedDateTime.fromWall(PlainDateTime(today, PlainTime(10, 20)), 'Africa/Algiers')!.instant;

Future<CalendarBook> demoBook() async {
  final c = CalendarController(
    KernelOptions(timeZone: 'Africa/Algiers', locale: 'fr', initialDate: today, now: () => now),
    followAppLocale: false,
  );
  addTearDown(c.dispose);
  final book = CalendarBook(c);
  await loadDemo(book, today);
  return book;
}

/// The week as the views show it: through the filter the book gave the kernel.
List<EventInstance> week(CalendarBook b) => b.controller.kernel.store.snapshot.queryInstances(
  viewWindow(PlainDate(2026, 11, 8), PlainDate(2026, 11, 15), 'Africa/Algiers'),
  QueryOptions(where: b.controller.options.eventFilter),
);

List<String> titlesIn(CalendarBook b, String calendar) => [
  for (final i in week(b))
    if (b.calendarOf(i.event)?.id == calendar) i.event.title,
]..sort();

EventInstance find(CalendarBook b, String title, [PlainDate? on]) =>
    week(b).firstWhere((i) => i.event.title == title && (on == null || startDate(i.event, 'Africa/Algiers') == on));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the demo: four calendars, the holidays read-only from the .ics', () async {
    final b = await demoBook();
    expect(b.calendars.map((c) => c.id), ['work', 'home', 'sport', 'holidays']);
    // Sunday 8 to Thursday 12: five mornings of consultations.
    expect(titlesIn(b, 'work').where((t) => t == 'Consultations').length, 5);
    // 1 November is a Sunday of the week before; none this week, but the rule is there.
    final snap = b.controller.kernel.store.snapshot;
    final revolution = snap.allSeries.firstWhere((s) => s.base.title == 'Fête de la Révolution');
    expect(revolution.base.perms.start || revolution.base.perms.duration, isFalse);
    expect(b.calendarOf(revolution)?.id, 'holidays');
  });

  test('unticking a calendar hides its events, in the store still; ticking shows them again', () async {
    final b = await demoBook();
    final before = titlesIn(b, 'work');
    final work = b.byId('work')!;
    final stored = b.controller.kernel.store.snapshot.allEvents.length;
    b.setVisible(work, false);
    expect(b.controller.options.eventFilter, isNotNull);
    expect(titlesIn(b, 'work'), isEmpty);
    expect(titlesIn(b, 'home'), isNotEmpty);
    expect(b.controller.kernel.store.snapshot.allEvents.length, stored);
    // The views are filtered too: the week shown has none of them.
    final model = b.controller.kernel.viewModel() as TimeGridViewModel;
    final shown = {
      for (final c in model.model.columns)
        for (final e in c.events) b.calendarOf(e.segment.instance.event)?.id,
    };
    expect(shown, isNot(contains('work')));
    expect(shown, contains('home'));
    b.setVisible(work, true);
    expect(b.controller.options.eventFilter, isNull, reason: 'all ticked: no filter');
    expect(titlesIn(b, 'work'), before);
  });

  test('what was made here (a new event, an override) survives hide and show', () async {
    final b = await demoBook();
    final c = b.controller;
    final fresh = Draft.fresh(
      calendarId: 'home',
      title: 'Plombier',
      start: ZonedDateTime.fromWall(PlainDateTime(today, PlainTime(17)), 'Africa/Algiers')!,
      end: ZonedDateTime.fromWall(PlainDateTime(today, PlainTime(18)), 'Africa/Algiers')!,
    );
    expect(c.run(createCommand(fresh, b), validate: true).ok, isTrue);

    final monday = find(b, 'Consultations', PlainDate(2026, 11, 9));
    final before = Draft.of(monday, b, 'Africa/Algiers');
    final after = before.copy()
      ..title = 'Consultations (remplacement)'
      ..startTime = PlainTime(9);
    expect(asksScope(monday, before, after), isTrue);
    expect(c.run(editCommand(monday, before, after, b, scope: EditScope.single)!, validate: true).ok, isTrue);

    for (final id in ['home', 'work']) {
      b.setVisible(b.byId(id)!, false);
    }
    expect(titlesIn(b, 'home'), isEmpty);
    expect(titlesIn(b, 'work'), isEmpty);
    for (final id in ['home', 'work']) {
      b.setVisible(b.byId(id)!, true);
    }
    expect(titlesIn(b, 'home'), contains('Plombier'));
    final override = find(b, 'Consultations (remplacement)');
    expect(ZonedDateTime((override.event as TimedEvent).start.instant, 'Africa/Algiers').time, PlainTime(9));
    expect(titlesIn(b, 'work').where((t) => t == 'Consultations').length, 4);
  });

  test('an event moved to another calendar stays when its first one is hidden', () async {
    final b = await demoBook();
    final benali = find(b, 'Consultation — M. Benali');
    final before = Draft.of(benali, b, 'Africa/Algiers');
    final after = before.copy()..calendarId = 'home';
    expect(asksScope(benali, before, after), isFalse);
    expect(b.controller.run(editCommand(benali, before, after, b)!, validate: true).ok, isTrue);
    b.setVisible(b.byId('work')!, false);
    expect(titlesIn(b, 'home'), contains('Consultation — M. Benali'));
    b.setVisible(b.byId('home')!, false);
    expect(titlesIn(b, 'home'), isEmpty);
    b.setVisible(b.byId('home')!, true);
    b.setVisible(b.byId('work')!, true);
    expect(titlesIn(b, 'home').where((t) => t == 'Consultation — M. Benali').length, 1);
    expect(titlesIn(b, 'work'), isNot(contains('Consultation — M. Benali')));
  });

  test('review: an event moved to another calendar survives its first one hidden then shown', () async {
    final b = await demoBook();
    final benali = find(b, 'Consultation — M. Benali');
    final before = Draft.of(benali, b, 'Africa/Algiers');
    b.controller.run(editCommand(benali, before, before.copy()..calendarId = 'home', b)!, validate: true);
    b.setVisible(b.byId('work')!, false);
    b.setVisible(b.byId('work')!, true);
    expect(titlesIn(b, 'home'), contains('Consultation — M. Benali'));
    expect(titlesIn(b, 'work'), isNot(contains('Consultation — M. Benali')));
  });

  test('review: an occurrence moved to another calendar takes its whole series', () async {
    final b = await demoBook();
    final tuesday = find(b, 'Footing', PlainDate(2026, 11, 10));
    final before = Draft.of(tuesday, b, 'Africa/Algiers');
    final after = before.copy()..calendarId = 'home';
    expect(asksScope(tuesday, before, after), isFalse);
    expect(b.controller.run(editCommand(tuesday, before, after, b)!, validate: true).ok, isTrue);
    expect(titlesIn(b, 'home').where((t) => t == 'Footing').length, 2);
    expect(titlesIn(b, 'sport'), isNot(contains('Footing')));
    b.setVisible(b.byId('home')!, false);
    expect(titlesIn(b, 'home'), isEmpty);
    expect(week(b).where((i) => i.event.title == 'Footing'), isEmpty);
    b.setVisible(b.byId('home')!, true);
    b.setVisible(b.byId('sport')!, false);
    b.setVisible(b.byId('sport')!, true);
    expect(titlesIn(b, 'home').where((t) => t == 'Footing').length, 2);
  });

  test('review: an override is its series\' calendar; hide and show keep it', () async {
    final b = await demoBook();
    final tuesday = find(b, 'Footing', PlainDate(2026, 11, 10));
    final before = Draft.of(tuesday, b, 'Africa/Algiers');
    b.controller.run(
      editCommand(tuesday, before, before.copy()..title = 'Fractionné', b, scope: EditScope.single)!,
      validate: true,
    );
    expect(b.calendarOf(find(b, 'Fractionné').event)?.id, 'sport');
    b.setVisible(b.byId('sport')!, false);
    expect(week(b).where((i) => i.event.title == 'Fractionné'), isEmpty);
    b.setVisible(b.byId('sport')!, true);
    expect(titlesIn(b, 'sport')..sort(), ['Footing', 'Fractionné', 'Piscine']);
  });

  test('the history stays whole: an edit undone while its calendar is hidden, shown undone', () async {
    final b = await demoBook();
    final benali = find(b, 'Consultation — M. Benali');
    final before = Draft.of(benali, b, 'Africa/Algiers');
    b.controller.run(editCommand(benali, before, before.copy()..title = 'Benali (bilan)', b)!, validate: true);
    b.setVisible(b.byId('work')!, false);
    expect(b.controller.undo(), isTrue);
    expect(titlesIn(b, 'work'), isEmpty);
    b.setVisible(b.byId('work')!, true);
    expect(titlesIn(b, 'work'), contains('Consultation — M. Benali'));
    expect(titlesIn(b, 'work'), isNot(contains('Benali (bilan)')));
    expect(b.controller.redo(), isTrue);
    expect(titlesIn(b, 'work'), contains('Benali (bilan)'));
  });

  test('the repeat presets: a single event made weekly, a series made daily, then never', () async {
    final b = await demoBook();
    final c = b.controller;
    final benali = find(b, 'Consultation — M. Benali');
    final d0 = Draft.of(benali, b, 'Africa/Algiers');
    expect(d0.repeat, RepeatPreset.never);
    expect(c.run(editCommand(benali, d0, d0.copy()..repeat = RepeatPreset.weekly, b)!, validate: true).ok, isTrue);
    final series = c.kernel.store.snapshot.getSeries('w-benali');
    expect(CalendarBook.presetOf(series), RepeatPreset.weekly);

    final team = find(b, "Réunion d'équipe");
    final t0 = Draft.of(team, b, 'Africa/Algiers');
    expect(t0.repeat, RepeatPreset.weekly);
    expect(c.run(editCommand(team, t0, t0.copy()..repeat = RepeatPreset.daily, b)!, validate: true).ok, isTrue);
    expect(titlesIn(b, 'work').where((t) => t == "Réunion d'équipe").length, 6); // Monday 9 to Saturday 14

    // The custom rule of the consultations is shown as such, and kept.
    expect(Draft.of(find(b, 'Consultations'), b, 'Africa/Algiers').repeat, isNull);

    expect(c.undo(), isTrue);
    expect(titlesIn(b, 'work').where((t) => t == "Réunion d'équipe").length, 1);
  });

  test('an event in its own zone keeps it when edited from the calendar', () async {
    final b = await demoBook();
    final visio = find(b, 'Visio avec le CHU de Lyon');
    final d = Draft.of(visio, b, 'Africa/Algiers');
    // 18:00 in Lyon is 18:00 in Algiers in winter (both UTC+1).
    expect(d.startTime, PlainTime(18));
    final after = d.copy()..endTime = PlainTime(19, 30);
    expect(b.controller.run(editCommand(visio, d, after, b)!, validate: true).ok, isTrue);
    final ev = find(b, 'Visio avec le CHU de Lyon').event as TimedEvent;
    expect(ev.start.zone, 'Europe/Paris');
    expect(ev.end.time, PlainTime(19, 30));
  });

  test('deleting an occurrence, then undoing it', () async {
    final b = await demoBook();
    final tuesday = find(b, 'Footing', PlainDate(2026, 11, 10));
    expect(b.controller.run(deleteCommand(tuesday), validate: true).ok, isTrue);
    expect(titlesIn(b, 'sport').where((t) => t == 'Footing').length, 1);
    b.controller.undo();
    expect(titlesIn(b, 'sport').where((t) => t == 'Footing').length, 2);
  });

  test('export then import: the same events, hidden calendars included', () async {
    final b = await demoBook();
    b.setVisible(b.byId('sport')!, false);
    final text = b.exportIcs('Démo')!;
    expect(text, contains('X-WR-CALNAME:Démo'));
    expect(text, contains('SUMMARY:Piscine'));
    expect(text, contains('TZID=Europe/Paris'));

    final other = await demoBook();
    final r = other.importIcs(text, fallbackName: 'x')!;
    expect(r.problems, isEmpty);
    expect(r.calendar.name, isNotNull);
    final imported = titlesIn(other, r.calendar.id);
    expect(imported, contains('Piscine'));
    expect(imported.where((t) => t == 'Consultations').length, 5);
  });

  test('search: by title, place or notes, upcoming first', () async {
    final b = await demoBook();
    expect(b.search('benali', today).single.instance.event.title, 'Consultation — M. Benali');
    expect(b.search('hydra', today).first.date, today); // the consultations of today
    expect(b.search('bilan sanguin', today).single.calendar.id, 'work');
    expect(b.search('  ', today), isEmpty);
    // Hidden calendars are not searched.
    b.setVisible(b.byId('work')!, false);
    expect(b.search('benali', today), isEmpty);
  });
}
