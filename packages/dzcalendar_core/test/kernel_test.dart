// Ported from the TypeScript core's kernel.test.ts and the kernel part of
// actions-kernel.test.ts (hand-written expectations, copied as values; the
// titles' wording checked by hand against intl's CLDR patterns, decision 24).
//
// Ported from kernel.test.ts: kernel (6), another view or date (1), modelAt
// after the 16b review (1), titleFormat (1), visibleRange and views (4 of
// 4), after the 18f-3 review (4 of 5).
// Skipped from kernel.test.ts:
// - 'a setting left undefined (a framework’s unset input) keeps the
//   default': Dart has no `undefined` — a `ViewSpec` field is given or takes
//   its default.
// - In 'bad settings are refused', the case "a range of strings": a Dart
//   `VisibleRange` holds `PlainDate`s, so it cannot be written.
// Ported from actions-kernel.test.ts: kernel options, events, batches (4),
// 'the kernel runs commands through its history' (1).
// Skipped from actions-kernel.test.ts: actionsFor (5) and 'delete: at once
// for an event, a sub-menu for an occurrence' (1) — the menu's actions
// (`actionsFor`) are not ported (they belong with the widgets, 19e-2).
// Translation notes:
// - `createKernel({...})` is `CalendarKernel(KernelOptions(...))`; options a
//   kernel holds (`hiddenDays`, `dayGrid`, `businessHours`…) go in
//   `options: ModelOptions(...)`; `setOptions({ x })` is
//   `setOptions(k.options.copyWith(x: ...))`; `RangeError` is `ArgumentError`.
// - `createHistory(store, ctx).run({ type: 'event.create', ... })` is
//   `History(store, CommandContext(...)).run(CreateEvent(...))`.
// - `viewModel().model as TimeGridModel` is `(viewModel() as TimeGridViewModel).model`;
//   `toBe` on models and columns is `identical`.
// - `views: { c: { family, visibleRange } }` (settings filled in by the
//   kernel) is a whole `ViewSpec` here (Dart has no partial spec): the
//   family's duration and `ViewAlignment.none`, as the TS fills them.
// - Titles: intl joins a range with a bare en dash where both ends differ in
//   one field ("Oct 18–24, 2026"); ICU (the web) writes "Oct 18 – 24, 2026"
//   with thin spaces. A numeric skeleton (`Md`, "19/10") collapses the shared
//   month: "19–25/10" (the web: "19/10 – 25/10").
// - A title format that throws is reported to the zone (the web: an
//   unhandled rejection): caught with `runZonedGuarded`.

import 'dart:async';

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

Instant now() => Instant.parse('2026-10-21T08:00:00Z');
PlainDate d(String s) => PlainDate.parse(s);
const paris = 'Europe/Paris';

TimeGridModel tg(CalendarKernel k) => (k.viewModel() as TimeGridViewModel).model;

void main() {
  group('kernel', () {
    test('starts on today in its zone, with the locale’s week and a title', () {
      final k = CalendarKernel(KernelOptions(timeZone: paris, locale: 'fr-FR', now: now));
      final s = k.state;
      expect(
        ['${s.today}', s.firstDay, '${s.range.start}', s.title],
        ['2026-10-21', 1, '2026-10-19', '19–25 oct. 2026'],
      );
    });

    test('navigates, changes view, and retitles', () {
      final k = CalendarKernel(KernelOptions(timeZone: paris, locale: 'en-US', now: now, initialView: 'dayGridMonth'));
      expect(k.state.title, 'October 2026');
      k.navigate(NavDirection.next);
      expect(k.state.title, 'November 2026');
      k.setView('timeGridDay', d('2026-10-25'));
      expect(k.state.title, 'Sunday, October 25, 2026');
    });

    test('memoizes the model, and after a store change rebuilds only what changed', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: now,
          events: [EventInput(id: 'a', start: '2026-10-21T09:00$_p')],
        ),
      );
      final m1 = k.viewModel();
      expect(identical(k.viewModel(), m1), isTrue);
      final events = <KernelEvent>[];
      k.subscribe(events.add);
      History(
        k.store,
        CommandContext(
          normalize: NormalizeContext(displayZone: paris, newId: createIdGenerator('x')),
        ),
      ).run(CreateEvent(EventInput(id: 'b', start: '2026-10-23T09:00$_p')));
      final m2 = k.viewModel();
      expect(identical(m2, m1), isFalse);
      expect([m1.family, m2.family], ['timeGrid', 'timeGrid']);
      final a = (m1 as TimeGridViewModel).model;
      final b = (m2 as TimeGridViewModel).model;
      expect(
        [for (var i = 0; i < b.columns.length; i++) identical(b.columns[i], a.columns[i])],
        [true, true, true, true, false, true, true],
      );
      expect([for (final e in events) e is KernelStoreEvent ? 'store' : 'state'], ['store']);
    });

    test('four kernels on one store show the same instant on each zone’s own day', () {
      final store = EventStore();
      final kernels = [
        for (final tz in ['Europe/Paris', 'America/Chicago', 'Australia/Lord_Howe', 'Australia/Sydney'])
          CalendarKernel(
            KernelOptions(timeZone: tz, locale: 'en-GB', now: now, store: store, initialDate: d('2026-10-21')),
          ),
      ];
      History(
        store,
        CommandContext(
          normalize: NormalizeContext(displayZone: 'UTC', newId: createIdGenerator('s')),
        ),
      ).run(CreateEvent(EventInput(id: 'call', start: '2026-10-21T23:30[UTC]')));
      final dayOfCall = [for (final k in kernels) tg(k).columns.firstWhere((c) => c.events.isNotEmpty).key];
      expect(dayOfCall, ['2026-10-22', '2026-10-21', '2026-10-22', '2026-10-22']);
    });

    test('reports what loading events found, and refuses a bad zone at once', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: 'UTC',
          locale: 'en',
          now: now,
          events: [EventInput(start: 'nope')],
        ),
      );
      expect(k.problems!.rejected, 1);
      expect(
        () => CalendarKernel(KernelOptions(timeZone: 'Mars/Olympus', locale: 'en', now: now)),
        throwsArgumentError,
      );
      expect(() => k.setTimeZone('Nowhere'), throwsArgumentError);
    });

    test('setTimeZone rebuilds the model from scratch: every day is another day', () {
      final k = CalendarKernel(KernelOptions(timeZone: paris, locale: 'en', now: now));
      final m1 = k.viewModel();
      k.setTimeZone('Asia/Tokyo');
      expect(identical(k.viewModel(), m1), isFalse);
      expect(k.state.timeZone, 'Asia/Tokyo');
    });
  });

  group('another view or date, without changing what is shown (printing, exports)', () {
    test(
      'stateAt / modelAt: 25 October 2026 in Paris (25 h: 02:00–03:00 twice, a repeat band on the wall axis); the shown week stays',
      () {
        final k = CalendarKernel(
          KernelOptions(
            timeZone: paris,
            locale: 'en-US',
            now: now,
            events: [
              EventInput(id: 'a', start: '2026-10-25T09:00$_p'),
              EventInput(id: 'b', start: '2026-12-01T09:00$_p'),
            ],
          ),
        );
        final shown = k.viewModel();
        final s = k.stateAt('timeGridDay', d('2026-10-25'))!;
        final m = (k.modelAt('timeGridDay', d('2026-10-25'))! as TimeGridViewModel).model;
        final month = k.modelAt('dayGridMonth', d('2026-12-10'))!;
        final ax = m.columns[0].axis;
        expect(
          [
            s.title,
            m.columns.length,
            ax.day.kind.name,
            [
              for (final b in ax.bands) [b.kind.name, b.from, b.to],
            ],
            [for (final e in m.columns[0].events) e.segment.instance.event.id],
          ],
          [
            'Sunday, October 25, 2026',
            1,
            'long',
            [
              ['repeat', 120, 180],
            ],
            ['a'],
          ],
        );
        expect([month.family, k.stateAt('dayGridMonth', d('2026-12-10'))!.title], ['dayGrid', 'December 2026']);
        // The web: 'Oct 18 – 24, 2026' (ICU's thin spaces); intl's range is built by hand: 'Oct 18–24, 2026'.
        expect(
          [k.state.title, identical(k.viewModel(), shown), k.modelAt('nope', d('2026-10-25'))],
          ['Oct 18–24, 2026', true, null],
        );
      },
    );
  });

  group('modelAt after the 16b review: the view as shown, and the caps paper lifts', () {
    test(
      'weekends hidden: the week has five columns there too; `over` lifts the month’s cap, the shown one keeps it',
      () {
        final many = [for (var i = 0; i < 6; i++) EventInput(id: 'e$i', start: '2026-10-21', allDay: true)];
        final k = CalendarKernel(
          KernelOptions(
            timeZone: paris,
            locale: 'fr-FR',
            now: now,
            events: many,
            options: const ModelOptions(hiddenDays: [6, 7], dayGrid: DayGridSettings(maxLanes: 2)),
          ),
        );
        final week = (k.modelAt('timeGridWeek', d('2026-10-21'))! as TimeGridViewModel).model;
        expect([for (final c in week.columns) c.date.day], [19, 20, 21, 22, 23]);
        final capped = (k.modelAt('dayGridMonth', d('2026-10-21'))! as DayGridViewModel).model;
        final lifted =
            (k.modelAt('dayGridMonth', d('2026-10-21'), dayGrid: const DayGridSettings())! as DayGridViewModel).model;
        expect([capped.maxLanes, lifted.maxLanes, k.options.dayGrid.maxLanes], [2, null, 2]);
      },
    );
  });

  group('titleFormat (18f-3)', () {
    test(
      'a function is given the first and last days shown; options write a range; one that throws leaves the default',
      () {
        final k = CalendarKernel(
          KernelOptions(
            timeZone: paris,
            locale: 'fr-FR',
            now: now,
            initialView: 'timeGridWeek',
            titleFormat: TitleFormat.builder((t) => '${t.start}/${t.end}/${t.view}'),
          ),
        );
        final fn = k.state.title;
        k.setTitleFormat(const TitleFormat.skeleton('Md'));
        final opts = k.state.title;
        k.setTitleFormat(null);
        final byDefault = k.state.title;
        final seen = <Object>[];
        late String kept;
        runZonedGuarded(() {
          k.setTitleFormat(TitleFormat.builder((_) => throw StateError('app bug')));
          kept = k.state.title;
        }, (e, _) => seen.add(e));
        // Monday 19 to Sunday 25 October 2026; fr-FR writes day/month "19/10" — the shared month said once
        // here, "19–25/10" (the web: "19/10 – 25/10").
        expect([fn, opts, kept == byDefault, seen.length], ['2026-10-19/2026-10-25/timeGridWeek', '19–25/10', true, 1]);
      },
    );
  });

  group('visibleRange and views by settings (18f-3)', () {
    final congress = VisibleRange(d('2026-11-03'), d('2026-11-13'));
    ViewSpec fixed(String type, String family, {VisibleRange? range}) => ViewSpec(
      type: type,
      family: family,
      duration: IsoDuration(days: 1),
      alignment: ViewAlignment.none,
      visibleRange: range ?? congress,
    );

    test('a congress, 3 to 12 November 2026: ten days whatever the date; previous, next and today stay on it', () {
      expect(['${congress.start}', '${congress.end}'], ['2026-11-03', '2026-11-13']);
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: now,
          initialView: 'congres',
          views: {'congres': fixed('congres', 'timeGrid')},
        ),
      );
      ViewRange r() => k.state.range;
      final first = ['${r().start}', '${r().end}', r().dates.length, k.state.view.type];
      k.navigate(NavDirection.next);
      k.navigate(NavDirection.today);
      k.navigate(NavDirection.prev);
      expect(
        [...first, '${r().start}', '${r().end}'],
        ['2026-11-03', '2026-11-13', 10, 'congres', '2026-11-03', '2026-11-13'],
      );
    });

    test(
      'in a day grid its rows are whole weeks: Monday 2 to Sunday 8, Monday 9 to Sunday 15; the period itself 3 to 12',
      () {
        final k = CalendarKernel(
          KernelOptions(
            timeZone: paris,
            locale: 'fr-FR',
            now: now,
            initialView: 'c',
            views: {'c': fixed('c', 'dayGrid')},
          ),
        );
        final r = k.state.range;
        expect(
          [
            [for (final w in r.weeks) '${w.first}..${w.last}'],
            '${r.activeStart}',
            '${r.activeEnd}',
          ],
          [
            ['2026-11-02..2026-11-08', '2026-11-09..2026-11-15'],
            '2026-11-03',
            '2026-11-13',
          ],
        );
      },
    );

    test('a range that ends before it starts is refused', () {
      expect(
        () => CalendarKernel(
          KernelOptions(
            timeZone: paris,
            locale: 'fr-FR',
            now: now,
            initialView: 'c',
            views: {'c': fixed('c', 'timeGrid', range: VisibleRange(congress.end, congress.start))},
          ),
        ),
        throwsArgumentError,
      );
    });

    test('settings are filled in: the type is the key, three days from the date given', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: now,
          initialView: 'trois',
          views: {
            // Given under another type: the key names it.
            'trois': ViewSpec(
              type: 'x',
              family: 'timeGrid',
              duration: IsoDuration(days: 3),
              alignment: ViewAlignment.none,
            ),
          },
        ),
      );
      expect(
        [
          k.state.view.type,
          [for (final x in k.state.range.dates) '$x'],
        ],
        [
          'trois',
          ['2026-10-21', '2026-10-22', '2026-10-23'],
        ],
      );
    });
  });

  group('after the 18f-3 review (kernel)', () {
    test('a month title in options is the month, not the grid’s padding days (28 September – 8 November)', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: now,
          initialView: 'dayGridMonth',
          titleFormat: const TitleFormat.skeleton('yMMMM'),
        ),
      );
      final seen = <String>[];
      k.setTitleFormat(
        TitleFormat.builder((t) {
          seen.add('${t.start}..${t.end}');
          return 'x';
        }),
      );
      expect([seen[0]], ['2026-10-01..2026-10-31']);
      k.setTitleFormat(const TitleFormat.skeleton('yMMMM'));
      expect(k.state.title, 'octobre 2026');
    });

    test('a day grid of two months shows both: 28 September to 6 December, aligned on the weeks', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: now,
          initialView: 'deux',
          views: {
            'deux': ViewSpec(
              type: 'deux',
              family: 'dayGrid',
              duration: IsoDuration(months: 2),
              alignment: ViewAlignment.month,
            ),
          },
        ),
      );
      final r = k.state.range;
      expect(
        ['${r.start}', '${r.end}', '${r.activeStart}', '${r.activeEnd}'],
        ['2026-09-28', '2026-12-07', '2026-10-01', '2026-12-01'],
      );
    });

    test('a view that cannot be made is refused whole: the kernel stays on the one it showed', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr-FR',
          now: now,
          initialView: 'timeGridWeek',
          views: {
            'weekend': ViewSpec(
              type: 'weekend',
              family: 'timeGrid',
              duration: IsoDuration(days: 1),
              alignment: ViewAlignment.none,
              visibleRange: VisibleRange(d('2026-10-24'), d('2026-10-26')),
            ),
          },
        ),
      );
      k.setView('weekend');
      // Saturday 24 and Sunday 25 hidden: the fixed period has no day left.
      expect(() => k.setOptions(k.options.copyWith(hiddenDays: [6, 7])), throwsArgumentError);
      k.navigate(NavDirection.next);
      expect([k.state.view.type, '${k.state.range.start}', k.options.hiddenDays], ['weekend', '2026-10-24', <int>[]]);
    });

    test('bad settings are refused when the kernel is made: a day count of 0, a duration of nothing', () {
      String make(ViewSpec v) {
        try {
          CalendarKernel(KernelOptions(timeZone: paris, locale: 'fr-FR', now: now, views: {'v': v}));
          return 'made';
        } on ArgumentError {
          return 'refused';
        } catch (_) {
          return 'threw';
        }
      }

      expect(
        [
          make(
            ViewSpec(
              type: 'v',
              family: 'timeGrid',
              duration: IsoDuration(days: 1),
              alignment: ViewAlignment.none,
              dayCount: 0,
            ),
          ),
          make(ViewSpec(type: 'v', family: 'timeGrid', duration: IsoDuration(days: 0), alignment: ViewAlignment.none)),
        ],
        ['refused', 'refused'],
      );
    });
  });

  group('kernel options, events, batches (actions-kernel.test.ts)', () {
    test('batch: three changes, one state event with three causes', () {
      final k = CalendarKernel(KernelOptions(timeZone: paris, locale: 'fr-FR', now: now));
      final events = <KernelEvent>[];
      k.subscribe(events.add);
      k.batch(() {
        k.setTimeZone('Asia/Tokyo');
        k.setLocale('en-US');
        k.navigate(NavDirection.next);
      });
      expect(events, hasLength(1));
      final e = events[0] as KernelStateEvent;
      expect(
        [e.causes, e.direction],
        [
          [StateCause.zone, StateCause.locale, StateCause.navigate],
          StateDirection.next,
        ],
      );
    });

    test('no-ops emit nothing', () {
      final k = CalendarKernel(KernelOptions(timeZone: paris, locale: 'fr-FR', now: now));
      var n = 0;
      k.subscribe((_) => n++);
      k.setTimeZone(paris);
      k.setLocale('fr-FR');
      k.setView('timeGridWeek');
      expect(n, 0);
    });

    test('setOptions reshapes the model: business hours, lanes', () {
      final k = CalendarKernel(KernelOptions(timeZone: 'UTC', locale: 'en', now: now, initialView: 'timeGridDay'));
      expect(tg(k).columns[0].offHours, isEmpty);
      k.setOptions(k.options.copyWith(businessHours: BusinessHours.standard));
      expect(
        [
          for (final o in tg(k).columns[0].offHours) [o.top, o.height],
        ],
        [
          [0, 540],
          [1020, 420],
        ],
      );
      k.setView('dayGridMonth');
      k.setOptions(k.options.copyWith(dayGrid: const DayGridSettings(maxLanes: 2)));
      expect((k.viewModel() as DayGridViewModel).model.maxLanes, 2);
    });

    test('setEvents with the same content changes nothing; with different content, only that', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: 'UTC',
          locale: 'en',
          now: now,
          events: [
            EventInput(id: 'a', start: '2026-10-21'),
            EventInput(id: 'b', start: '2026-10-22'),
          ],
        ),
      );
      var changes = 0;
      k.subscribe((e) {
        if (e is KernelStoreEvent) changes++;
      });
      k.setEvents([EventInput(id: 'a', start: '2026-10-21'), EventInput(id: 'b', start: '2026-10-22')]);
      expect(changes, 0);
      k.setEvents([EventInput(id: 'a', start: '2026-10-21')]);
      expect(changes, 1);
      expect(k.store.snapshot.getEvent('b'), isNull);
    });

    test('the kernel runs commands through its history; a series created there takes the locale’s first day', () {
      final k = CalendarKernel(
        KernelOptions(timeZone: 'America/New_York', locale: 'en-US', initialDate: d('2026-10-21')),
      );
      expect(
        k
            .run(
              CreateEvent(EventInput(id: 's', start: '2026-10-21T09:00', rrule: 'FREQ=WEEKLY;INTERVAL=2;BYDAY=TU,SU')),
            )
            .ok,
        isTrue,
      );
      expect(k.store.snapshot.getSeries('s')!.set.rules[0].wkst, 7);
      expect([k.history.canUndo, k.history.undo(), k.store.snapshot.counts.series], [true, true, 0]);
      k.dispose();
    });
  });
}

const _p = '[Europe/Paris]';
