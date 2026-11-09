// The widgets on a phone. What is shown comes from --dart-define, so a
// screenshot can be made again exactly:
//   SCREEN=calendar|mini|slots  VIEW=timeGridWeek  LOCALE=fr|en|ar
//   DATE=2026-11-09  ZONE=Europe/Paris  DARK=true  SCROLL=7 (the hour at the top)
// The clock is frozen at DATE 10:20 in ZONE.
import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const _screen = String.fromEnvironment('SCREEN', defaultValue: 'calendar');
const _view = String.fromEnvironment('VIEW', defaultValue: 'timeGridWeek');
const _locale = String.fromEnvironment('LOCALE', defaultValue: 'fr');
const _date = String.fromEnvironment('DATE', defaultValue: '2026-11-09');
const _zone = String.fromEnvironment('ZONE', defaultValue: 'Europe/Paris');
const _dark = bool.fromEnvironment('DARK');
const _scroll = int.fromEnvironment('SCROLL', defaultValue: 7);

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7C66), brightness: b),
      extensions: const [
        DzCalendarTheme(tones: {'blue': Color(0xFF90CAF9), 'amber': Color(0xFFFFD180), 'rose': Color(0xFFF8BBD0)}),
      ],
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(_locale),
      supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        DzCalendarLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final PlainDate _day = PlainDate.tryParse(_date) ?? PlainDate(2026, 11, 9);
  late final Instant _now = ZonedDateTime.fromWall(PlainDateTime(_day, PlainTime(10, 20)), _zone)!.instant;
  late final CalendarController _controller = CalendarController(
    KernelOptions(
      timeZone: _zone,
      locale: _locale,
      initialDate: _day,
      initialView: _view,
      now: () => _now,
      events: _events(_day),
      resources: const [
        ResourceInput(id: 'ali', title: 'Dr Ali'),
        ResourceInput(id: 'sara', title: 'Dr Sara'),
        ResourceInput(id: 'nour', title: 'Dr Nour'),
      ],
      options: ModelOptions(
        timeGrid: const TimeGridSettings(slotMinutes: 30),
        businessHours: BusinessHours([
          BusinessHoursRule(daysOfWeek: const [1, 2, 3, 4, 5], from: const WallTime(8), to: const WallTime(18)),
        ]),
      ),
    ),
  );
  late int _tab = switch (_screen) {
    'mini' => 1,
    'slots' => 2,
    _ => 0,
  };
  Slot? _picked;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      1 => ListView(
        children: [
          MiniMonth.controller(_controller),
          const Divider(),
          MiniMonth(selected: _day, today: _day, marked: {_day, _day.addDays(2), _day.addDays(5)}),
        ],
      ),
      2 => SlotPicker.fromSlots(
        slots: _slots(_day, _now),
        selected: _picked,
        onSelected: (s) => setState(() => _picked = s),
      ),
      _ => DzCalendar(
        controller: _controller,
        scrollHour: _scroll,
        views: const [
          'dayGridMonth',
          'timeGridWeek',
          'timeGridDay',
          'listWeek',
          'multiMonthYear',
          'resourceTimeGridDay',
        ],
        onEventTap: (i) => _say(i.event.title),
        onCreateRequest: (r) => _say('$r'),
      ),
    };
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_view_week), label: 'DzCalendar'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'MiniMonth'),
          NavigationDestination(icon: Icon(Icons.schedule), label: 'SlotPicker'),
        ],
      ),
    );
  }

  void _say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// A practice's week around [day]: consultations, a meeting that overlaps,
/// a congress over three days, a weekly series.
List<EventInput> _events(PlainDate day) {
  final monday = day.addDays(1 - day.dayOfWeek);
  String at(int d, int h, [int m = 0]) =>
      '${monday.addDays(d)}T${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  return [
    EventInput(id: 'c1', title: 'Consultation — M. Benali', start: at(0, 9), end: at(0, 9, 30), resourceId: 'ali'),
    EventInput(
      id: 'c2',
      title: 'Consultation — Mme Haddad',
      start: at(0, 9, 30),
      end: at(0, 10, 15),
      resourceId: 'sara',
      tone: 'blue',
    ),
    EventInput(id: 'm1', title: "Réunion d'équipe", start: at(0, 11), end: at(0, 12), resourceId: 'ali', tone: 'amber'),
    EventInput(
      id: 'm2',
      title: 'Appel labo',
      start: at(0, 11, 30),
      end: at(0, 12, 15),
      resourceId: 'nour',
      tone: 'rose',
    ),
    EventInput(id: 'c3', title: 'Téléconsultation', start: at(1, 14), end: at(1, 14, 45), resourceId: 'sara'),
    EventInput(id: 'c4', title: 'Bilan annuel', start: at(2, 8, 30), end: at(2, 10), resourceId: 'nour', tone: 'blue'),
    EventInput(id: 'c5', title: 'Vaccination', start: at(3, 16), end: at(3, 16, 20), resourceId: 'ali'),
    EventInput(id: 'g1', title: 'Garde', start: at(4, 18), end: at(4, 23), resourceId: 'sara', tone: 'rose'),
    // Across Sunday night's clock change, when the week has one (Paris: 25 October, 29 March).
    EventInput(id: 'nuit', title: 'Garde de nuit', start: at(6, 1, 30), end: at(6, 3, 30), tone: 'rose'),
    EventInput(
      id: 'cg',
      title: 'Congrès de cardiologie',
      start: '${monday.addDays(2)}',
      end: '${monday.addDays(5)}',
      allDay: true,
      tone: 'amber',
    ),
    EventInput(
      id: 'rv',
      title: 'Visite à domicile',
      start: at(0, 15),
      end: at(0, 16),
      rrule: 'FREQ=WEEKLY;BYDAY=MO,TH',
      resourceId: 'ali',
    ),
  ];
}

/// Slots of a practice open 9–12 and 14–17 on weekdays, every 30 minutes,
/// two weeks from [now].
List<Slot> _slots(PlainDate day, Instant now) {
  final rules = SlotRules(
    availability: Availability(
      timeZone: _zone,
      weekly: [
        WeeklyWindow(days: const [1, 2, 3, 4, 5], window: const Window(WallTime(9), WallTime(12))),
        WeeklyWindow(days: const [1, 2, 3, 4, 5], window: const Window(WallTime(14), WallTime(17))),
      ],
    ),
    duration: const Duration(minutes: 30),
    now: now,
    minNotice: const Duration(hours: 1),
  );
  final from = ZonedDateTime.fromWall(PlainDateTime(day, PlainTime.midnight), _zone)!.instant;
  final to = ZonedDateTime.fromWall(PlainDateTime(day.addDays(14), PlainTime.midnight), _zone)!.instant;
  return findSlots(rules, from: from, to: to).slots;
}
