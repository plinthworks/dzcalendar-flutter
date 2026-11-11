// The widgets on a phone. What is shown comes from --dart-define, so a
// screenshot can be made again exactly:
//   SCREEN=calendar|mini|slots  VIEW=timeGridWeek  LOCALE=fr|en|ar
//   DATE=2026-11-09  ZONE=Europe/Paris  DARK=true  SCROLL=7 (the hour at the top)
//   VIEW=resourceTimelineDay|resourceTimelineWeek: the doctors under their departments
//   DEMO=drag|held|drop|select  DEMO_ON=<title start>  DEMO_BY=96 (down)  DEMO_DX=0 (along)
// The clock is frozen at DATE 10:20 in ZONE.
import 'package:dzcalendar/dzcalendar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const _screen = String.fromEnvironment('SCREEN', defaultValue: 'calendar');
const _view = String.fromEnvironment('VIEW', defaultValue: 'timeGridWeek');
const _locale = String.fromEnvironment('LOCALE', defaultValue: 'fr');
const _date = String.fromEnvironment('DATE', defaultValue: '2026-11-09');
const _zone = String.fromEnvironment('ZONE', defaultValue: 'Europe/Paris');
const _dark = bool.fromEnvironment('DARK');
const _scroll = int.fromEnvironment('SCROLL', defaultValue: 7);

/// A gesture played at start, for screenshots: 'drag' (grabbed, held mid-move),
/// 'held' (let go where taken: its handles), 'drop' (moved and let go), 'select'.
const _demo = String.fromEnvironment('DEMO');
const _demoOn = String.fromEnvironment('DEMO_ON', defaultValue: 'Consultation');
const _demoBy = int.fromEnvironment('DEMO_BY', defaultValue: 96);

/// How far the finger goes sideways (a timeline: along time).
const _demoDx = int.fromEnvironment('DEMO_DX');

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
    onEventChange: (change) {
      final title = change.after?.title ?? change.before?.title ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${change.cause.name} · $title'),
          action: SnackBarAction(label: 'Revert', onPressed: () => change.revert()),
        ),
      );
    },
    onCommandRefused: (r, cmd) => _say('Refused: ${cmd.label}'),
    KernelOptions(
      timeZone: _zone,
      locale: _locale,
      initialDate: _day,
      initialView: _view,
      now: () => _now,
      events: _events(_day),
      resources: _view.contains('imeline')
          ? const [
              ResourceInput(id: 'cardio', title: 'Cardiologie'),
              ResourceInput(id: 'ali', title: 'Dr Ali Benali', parentId: 'cardio'),
              ResourceInput(id: 'sara', title: 'Dr Sara Haddad', parentId: 'cardio'),
              ResourceInput(id: 'pedia', title: 'Pédiatrie'),
              ResourceInput(id: 'nour', title: 'Dr Nour Kaci', parentId: 'pedia'),
            ]
          : const [
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
          'resourceTimelineDay',
          'resourceTimelineWeek',
        ],
        editable: true,
        selectable: true,
        onEventTap: (i, _) => _say(i.event.title),
        onCreateRequest: (r, _) => _say('$r'),
        onSelect: (s, _) => _say('$s'),
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

  @override
  void initState() {
    super.initState();
    if (_demo.isNotEmpty) Future<void>.delayed(const Duration(seconds: 2), _play);
  }

  /// Plays [_demo] with synthetic touches, as a finger would.
  Future<void> _play() async {
    Offset? at;
    void visit(Element e) {
      final w = e.widget;
      if (at == null && w is Text && (w.data ?? '').startsWith(_demoOn)) {
        final box = e.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) at = box.localToGlobal(box.size.center(Offset.zero));
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    if (_demo == 'select') at = const Offset(260, 420);
    final from = at;
    if (from == null) return;
    final binding = GestureBinding.instance;
    var t = Duration.zero;
    void send(PointerEvent e) => binding.handlePointerEvent(e);
    Future<void> wait(int ms) async {
      await Future<void>.delayed(Duration(milliseconds: ms));
      t += Duration(milliseconds: ms);
    }

    send(PointerDownEvent(pointer: 7, position: from, timeStamp: t));
    await wait(700);
    if (_demo == 'held') {
      send(PointerUpEvent(pointer: 7, position: from, timeStamp: t));
      return;
    }
    var p = from;
    for (var k = 1; k <= 12; k++) {
      final next = from + Offset(_demoDx * k / 12, _demoBy * k / 12);
      send(PointerMoveEvent(pointer: 7, position: next, delta: next - p, timeStamp: t));
      p = next;
      await wait(30);
    }
    if (_demo == 'drop' || _demo == 'select') send(PointerUpEvent(pointer: 7, position: p, timeStamp: t));
  }
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
