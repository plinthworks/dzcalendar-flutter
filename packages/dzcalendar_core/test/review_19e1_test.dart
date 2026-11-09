// What the 19e-1 code and architect reviews found, each pinned by a test,
// and the owner's decisions 26–29 (2026-11-09). Expectations by hand: CLDR's
// week data (Saudi Arabia's week starts on Sunday, Algeria's on Saturday),
// the TS's numbers for windowing, Paris's 2026 clock changes.

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

const paris = 'Europe/Paris';

void main() {
  group('week rules come from the region, as the web reads CLDR', () {
    test('the tag’s region, else the language’s likely one', () {
      String r(String l) => '${weekRulesFor(l).firstDay}/${weekRulesFor(l).minimalDays}';
      expect(r('ar-SA'), '7/1');
      expect(r('ar-DZ'), '6/1');
      expect(r('ar-MA'), '1/1');
      expect(r('ar'), '6/1'); // Egypt
      expect(r('fr'), '1/4');
      expect(r('fr-MA'), '1/1');
      expect(r('en'), '7/1'); // the United States
      expect(r('en-GB'), '1/4');
      expect(r('en-DE'), '1/4');
      expect(r('zh-Hant'), '7/1'); // Taiwan
      expect(r('xx-YY'), '1/1');
      // 2 January 2021 is a Saturday: in Saudi Arabia (Sunday, one day) still week 1.
      expect(weekNumber(PlainDate(2021, 1, 2), weekRulesFor('ar-SA')), 1);
    });

    test('a kernel in ar-SA starts its weeks on Sunday', () {
      final k = CalendarKernel(
        KernelOptions(timeZone: 'Asia/Riyadh', locale: 'ar-SA', initialDate: PlainDate(2026, 10, 21)),
      );
      expect(k.state.firstDay, 7);
      expect(k.state.range.start, PlainDate(2026, 10, 18)); // the Sunday before
    });
  });

  group('formatting', () {
    test('a regional locale intl carries is formatted with its own data (Algeria: Western digits)', () {
      expect(formatLocale('ar-DZ'), (used: 'ar_DZ', exact: true));
      expect(formatTemporal(PlainDate(2026, 3, 15), 'yMMMd', 'ar-DZ'), contains('2026'));
      expect(formatLocale('fr-MA').used, anyOf('fr_MA', 'fr'));
    });

    test('a language intl does not know: English, and the kernel says so', () {
      expect(formatLocale('zz'), (used: 'en', exact: false));
      final k = CalendarKernel(KernelOptions(timeZone: paris, locale: 'zz', initialDate: PlainDate(2026, 10, 21)));
      expect(k.localeProblem?.code, ProblemCode.invalidOption);
      expect(k.localeProblem?.severity, Severity.warning);
      expect(CalendarKernel(KernelOptions(timeZone: paris, locale: 'fr')).localeProblem, isNull);
    });

    test('a title skeleton intl does not know is refused when given, not printed as a pattern', () {
      expect(
        () => CalendarKernel(
          KernelOptions(timeZone: paris, locale: 'fr', titleFormat: const TitleFormat.skeleton('EEEd')),
        ),
        throwsArgumentError,
      );
      final k = CalendarKernel(KernelOptions(timeZone: paris, locale: 'fr', initialDate: PlainDate(2026, 10, 21)));
      expect(() => k.setTitleFormat(const TitleFormat.skeleton('yw')), throwsArgumentError);
      k.setTitleFormat(const TitleFormat.skeleton('MMMd'));
      expect(k.state.title, '19–25 oct.');
    });
  });

  group('windowing never throws on what Flutter measures', () {
    test('an unbounded viewport, an infinite or huge scroll (the TS’s answers)', () {
      final u = UniformSizes(20, 10);
      expect(visibleRange(u, 0, double.infinity, 1), const VRange(0, 9));
      expect(visibleRange(u, double.infinity, 100, 1), const VRange(8, 9));
      expect(visibleRange(u, 0, 1e300, 1), const VRange(0, 9));
    });
  });

  group('the kernel as a controller will use it', () {
    CalendarKernel kernel() => CalendarKernel(
      KernelOptions(
        timeZone: paris,
        locale: 'fr',
        initialDate: PlainDate(2026, 10, 21),
        events: [EventInput(id: 'a', start: '2026-10-21T09:00[$paris]', duration: 'PT1H')],
      ),
    );

    test('one function subscribed twice is told once, and one unsubscribe lets it go', () {
      final k = kernel();
      var n = 0;
      void f(KernelEvent _) => n++;
      final off = k.subscribe(f);
      k.subscribe(f);
      k.navigate(NavDirection.next);
      expect(n, 1);
      off();
      k.navigate(NavDirection.next);
      expect(n, 1);
    });

    test('after dispose, a change is a StateError (as a ChangeNotifier)', () {
      final k = kernel()..dispose();
      expect(() => k.navigate(NavDirection.next), throwsStateError);
      k.dispose(); // twice is harmless
    });

    test('a change elsewhere keeps the very same view model object', () {
      final k = kernel();
      final before = k.viewModel();
      // An event a year later, by the application (not a person): off screen.
      k.setEvents([
        EventInput(id: 'a', start: '2026-10-21T09:00[$paris]', duration: 'PT1H'),
        EventInput(id: 'b', start: '2027-10-21T09:00[$paris]', duration: 'PT1H'),
      ]);
      expect(identical(k.viewModel(), before), isTrue);
      // A command that touches nothing shown in an all-day sense still rebuilds only what it must.
      k.run(const MoveEvent('b', '2027-10-22T09:00[$paris]'));
      expect(identical(k.viewModel(), before), isTrue);
    });

    test('the same slots in a new list, and the same title format, change nothing', () {
      final slot = AvailableSlot(
        start: Instant.parse('2026-10-21T08:00:00Z'),
        end: Instant.parse('2026-10-21T08:30:00Z'),
      );
      final k = kernel();
      k.setOptions(k.options.copyWith(availableSlots: [slot]));
      var n = 0;
      k.subscribe((_) => n++);
      k.setOptions(
        k.options.copyWith(
          availableSlots: [
            AvailableSlot(start: Instant.parse('2026-10-21T08:00:00Z'), end: Instant.parse('2026-10-21T08:30:00Z')),
          ],
        ),
      );
      k.setTitleFormat(null);
      k.setTitleFormat(const TitleFormat.skeleton('MMMd'));
      k.setTitleFormat(const TitleFormat.skeleton('MMMd'));
      expect(n, 1);
    });

    test('a listener’s error goes to onError, and the others are still told', () {
      final errors = <Object>[];
      final k = CalendarKernel(KernelOptions(timeZone: paris, locale: 'fr', onError: (e, _) => errors.add(e)));
      var told = false;
      k.subscribe((_) => throw StateError('bug'));
      k.subscribe((_) => told = true);
      k.navigate(NavDirection.next);
      expect(errors.single, isA<StateError>());
      expect(told, isTrue);
    });
  });

  group('hit-tests: a point of the screen in calendar terms (decision 29)', () {
    TimeGridModel day(String date) {
      final k = CalendarKernel(
        KernelOptions(timeZone: paris, locale: 'fr', initialDate: PlainDate.parse(date), initialView: 'timeGridDay'),
      );
      return (k.viewModel() as TimeGridViewModel).model;
    }

    test('a skipped 02:30 (29 March 2026): the first moment after the jump, flagged', () {
      final m = day('2026-03-29');
      final hit = slotHitAt(m, 0, 150, 30)!;
      expect(hit.gap, isTrue);
      expect(hit.instant, Instant.parse('2026-03-29T01:00:00Z')); // 03:00 CEST
      expect(hit.date, PlainDate(2026, 3, 29));
    });

    test('a repeated 02:30 (25 October 2026): the first pass, the other offered to a menu', () {
      final m = day('2026-10-25');
      final hit = slotHitAt(m, 0, 150, 30)!;
      expect(hit.instant, Instant.parse('2026-10-25T00:30:00Z')); // 02:30 CEST
      expect(hit.slotStart, Instant.parse('2026-10-25T00:30:00Z'));
      // A press at 02:37 of the first pass is in the 02:30 slot.
      expect(slotHitAt(m, 0, 157, 30)!.slotStart, Instant.parse('2026-10-25T00:30:00Z'));
      final target = slotTargetAt(m, 0, 150)!;
      expect(target.ambiguous, isTrue);
      expect(target.alternative, Instant.parse('2026-10-25T01:30:00Z')); // 02:30 CET
      expect(slotHitAt(m, 3, 150, 30), isNull);
    });

    test('a month cell and an all-day cell', () {
      final k = CalendarKernel(
        KernelOptions(timeZone: paris, locale: 'fr', initialDate: PlainDate(2026, 10, 21), initialView: 'dayGridMonth'),
      );
      final month = (k.viewModel() as DayGridViewModel).model;
      expect(dayHitAt(month, 0, 0)!.date, PlainDate(2026, 9, 28)); // the Monday opening October's grid
      expect(dayHitAt(month, 9, 0), isNull);
      final week = day('2026-10-21');
      expect(allDayHitAt(week, 0)!.allDayRow, isTrue);
    });

    test('interactionContext carries the zone and the rules', () {
      final k = CalendarKernel(
        KernelOptions(
          timeZone: paris,
          locale: 'fr',
          rules: CalendarRules(overlap: RulesContext.noOverlap),
        ),
      );
      final ctx = k.interactionContext(snapMinutes: 15);
      expect(ctx.displayZone, paris);
      expect(ctx.snapMinutes, 15);
      expect(ctx.rules?.overlap, isNotNull);
    });
  });

  group('menus (actionsFor, decision 29)', () {
    final labels = ActionLabels(
      newEventAt: (t) => 'Nouveau à $t',
      newEventOn: (d) => 'Nouveau le $d',
      goToDay: 'Aller au jour',
      openEvent: 'Ouvrir',
      skippedHour: 'Heure sautée',
      deleteEvent: 'Supprimer',
      moveEvent: 'Déplacer',
      resizeEvent: 'Durée',
      scopeThis: 'Celle-ci',
      scopeFollowing: 'Les suivantes',
      scopeAll: 'Toutes',
    );
    ActionContext ctx({void Function(Command)? onCommand}) => ActionContext(
      displayZone: paris,
      labels: labels,
      formatTime: (i, withOffset) => withOffset ? '${ZonedDateTime(i, paris)}' : 'x',
      formatDate: (d) => '$d',
      onCreateRequest: (_) {},
      onCommand: onCommand,
    );

    test('a repeated hour offers both moments; a skipped one says so', () {
      final both = actionsFor(
        SlotTarget(
          date: PlainDate(2026, 10, 25),
          instant: Instant.parse('2026-10-25T00:30:00Z'),
          exists: true,
          ambiguous: true,
          alternative: Instant.parse('2026-10-25T01:30:00Z'),
        ),
        ctx(),
      );
      expect(both.map((a) => a.id), ['event.create.0', 'event.create.1']);
      final gap = actionsFor(
        SlotTarget(
          date: PlainDate(2026, 3, 29),
          instant: Instant.parse('2026-03-29T01:00:00Z'),
          exists: false,
          ambiguous: false,
        ),
        ctx(),
      );
      expect(gap.single.reason, 'Heure sautée');
    });

    test('delete: at once for an event, a scope sub-menu for an occurrence', () {
      final commands = <Command>[];
      final store = EventStore()
        ..replaceSourceChunk(
          's',
          '*',
          normalizeMany(
            [EventInput(id: 'r', start: '2026-10-19T09:00[$paris]', duration: 'PT1H', rrule: 'FREQ=DAILY')],
            NormalizeContext(displayZone: paris, newId: createIdGenerator('a')),
            sourceId: 's',
          ).items,
        );
      final occ = store.snapshot
          .queryInstances(viewWindow(PlainDate(2026, 10, 21), PlainDate(2026, 10, 22), paris))
          .single;
      final del = actionsFor(EventTarget(occ), ctx(onCommand: commands.add)).last;
      expect(del.children.map((c) => c.id), ['event.delete.this', 'event.delete.following', 'event.delete.all']);
      del.children[1].run!();
      final c = commands.single as DeleteEvent;
      expect(c.id, 'r');
      expect(c.scope, EditScope.following);
    });
  });
}
