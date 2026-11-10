import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/services.dart';

import 'book.dart';
import 'strings.dart';

/// The demo calendars, around [today] (a practice in Algiers, home, sport)
/// and the public holidays read from the bundled .ics.
Future<void> loadDemo(CalendarBook book, PlainDate today) async {
  String at(int days, int h, [int m = 0]) => '${today.addDays(days)}T${_two(h)}:${_two(m)}';
  String on(int days) => '${today.addDays(days)}';
  // The week's working days in Algeria: Sunday to Thursday.
  final sunday = today.addDays(-(today.dayOfWeek % 7));
  // From today to a weekday (ISO: 1 Monday … 7 Sunday) of this Sunday-first week.
  int toDay(int weekday) => weekday % 7 - today.dayOfWeek % 7;

  book.add(ShowCalendar(id: 'work', name: (c) => S.of(c).calendarWork, color: CalendarBook.palette[0]), [
    EventInput(
      id: 'w-consult',
      title: 'Consultations',
      start: '${sunday}T08:30',
      end: '${sunday}T12:00',
      rrule: 'FREQ=WEEKLY;BYDAY=SU,MO,TU,WE,TH',
      extendedProps: const {placeKey: 'Cabinet, Hydra'},
    ),
    EventInput(
      id: 'w-team',
      title: "Réunion d'équipe",
      start: '${sunday.addDays(1)}T13:00',
      end: '${sunday.addDays(1)}T14:00',
      rrule: 'FREQ=WEEKLY',
    ),
    EventInput(
      id: 'w-benali',
      title: 'Consultation — M. Benali',
      start: at(0, 14),
      end: at(0, 14, 30),
      extendedProps: const {placeKey: 'Cabinet, Hydra', notesKey: 'Bilan sanguin à revoir.'},
    ),
    EventInput(
      id: 'w-haddad',
      title: 'Visite à domicile — Mme Haddad',
      start: at(1, 16),
      end: at(1, 17),
      extendedProps: const {placeKey: 'Bab Ezzouar'},
    ),
    EventInput(id: 'w-night', title: 'Garde de nuit', start: at(toDay(3), 20), end: at(toDay(3) + 1, 8)),
    EventInput(
      id: 'w-visio',
      title: 'Visio avec le CHU de Lyon',
      // Its own zone: 18:00 in Lyon, wherever the calendar is shown.
      start: '${today.addDays(2)}T18:00',
      end: '${today.addDays(2)}T19:00',
      timeZone: 'Europe/Paris',
    ),
    EventInput(
      id: 'w-congress',
      title: 'Congrès de cardiologie',
      start: on(9),
      end: on(12),
      allDay: true,
      extendedProps: const {placeKey: 'Oran'},
    ),
  ]);

  book.add(ShowCalendar(id: 'home', name: (c) => S.of(c).calendarHome, color: CalendarBook.palette[1]), [
    EventInput(id: 'h-market', title: 'Courses', start: at(toDay(6), 10), end: at(toDay(6), 11)),
    EventInput(id: 'h-dinner', title: 'Dîner chez les parents', start: at(toDay(5), 19, 30), end: at(toDay(5), 22)),
    EventInput(
      id: 'h-birthday',
      title: 'Anniversaire de Yasmine',
      start: on(4),
      end: on(5),
      allDay: true,
      rrule: 'FREQ=YEARLY',
    ),
  ]);

  book.add(ShowCalendar(id: 'sport', name: (c) => S.of(c).calendarSport, color: CalendarBook.palette[2]), [
    EventInput(
      id: 's-run',
      title: 'Footing',
      start: '${sunday.addDays(2)}T07:00',
      end: '${sunday.addDays(2)}T07:45',
      rrule: 'FREQ=WEEKLY;BYDAY=TU,TH',
    ),
    EventInput(
      id: 's-pool',
      title: 'Piscine',
      start: '${sunday.addDays(6)}T09:00',
      end: '${sunday.addDays(6)}T10:00',
      rrule: 'FREQ=WEEKLY',
    ),
  ]);

  final ics = await rootBundle.loadString('assets/holidays_dz.ics');
  book.importIcs(
    ics,
    id: 'holidays',
    name: (c) => S.of(c).calendarHolidays,
    color: CalendarBook.palette[4],
    readOnly: true,
  );
}

String _two(int n) => n < 10 ? '0$n' : '$n';
