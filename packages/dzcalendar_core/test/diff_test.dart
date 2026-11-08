// Ported from the TypeScript core's diff.test.ts (hand-written expectations,
// copied as values).
//
// Ported: all five tests.
// Translation notes:
// - The first test cannot list the keys of a CalEvent by reflection, so its
//   "every key has a variant" check (`keys.filter(k => !(k in variants))`) is
//   not written; the variants are listed by hand instead, with the Dart-only
//   fields (ref, ongoing, expectedEnd) added.
// - `perms.own` (TS) is `perms.ownStart` / `perms.ownDuration` here.
// - sameValue: `{a: 1, b: undefined}` has no Dart counterpart; `{a: 1, b: null}`
//   stands for it (a key present is a key present).

import 'dart:convert';

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

NormalizeContext ctx() => NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('d'));

CalEvent ev(EventInput input) {
  final r = normalizeEvent(input, ctx());
  if (!r.ok) fail('${r.problems}');
  return r.value!.event;
}

EventInput full() => EventInput(
  id: 'full',
  groupId: 'g',
  title: 't',
  start: '2026-05-01T09:00[Europe/Paris]',
  end: '2026-05-01T10:00[Europe/Paris]',
  resourceIds: ['r1'],
  display: EventDisplay.block,
  status: EventStatus.tentative,
  busy: true,
  startEditable: true,
  durationEditable: false,
  resourceEditable: true,
  classNames: ['a'],
  tone: 'blue',
  url: 'https://example.com',
  extendedProps: {
    'room': {'floor': 2},
  },
);

class Box {
  const Box(this.v);
  final int v;
}

void main() {
  group('eventEquals', () {
    test('is false when any one field of CalEvent differs — a field added and forgotten fails here', () {
      final base = ev(full()) as TimedEvent;
      final variants = <String, CalEvent>{
        'id': base.copyWith(id: 'other'),
        'groupId': base.copyWith(groupId: 'h'),
        'title': base.copyWith(title: 'u'),
        'allDay': AllDayEvent(
          id: base.id,
          title: base.title,
          resourceIds: base.resourceIds,
          display: base.display,
          status: base.status,
          busy: base.busy,
          perms: base.perms,
          classNames: base.classNames,
          props: base.props,
          revision: base.revision,
          start: PlainDate.parse('2026-05-01'),
          end: PlainDate.parse('2026-05-02'),
          groupId: base.groupId,
          tone: base.tone,
          url: base.url,
        ),
        'start': base.copyWith(start: ZonedDateTime(Instant.parse('2026-05-01T07:30:00Z'), 'Europe/Paris')),
        'end': base.copyWith(end: ZonedDateTime(Instant.parse('2026-05-01T09:00:00Z'), 'Europe/Paris')),
        'resourceIds': base.copyWith(resourceIds: ['r2']),
        'display': base.copyWith(display: EventDisplay.auto),
        'status': base.copyWith(status: EventStatus.confirmed),
        'busy': base.copyWith(busy: false),
        'perms': base.copyWith(perms: const EventPerms(start: false, duration: false, resource: true)),
        'classNames': base.copyWith(classNames: ['b']),
        'tone': base.copyWith(tone: 'red'),
        'url': base.copyWith(url: 'https://example.org'),
        'props': base.copyWith(
          props: {
            'room': {'floor': 3},
          },
        ),
        'sourceId': base.copyWith(sourceId: 'api'),
        'zoneGuessed': base.copyWith(zoneGuessed: true),
        'ref': base.copyWith(ref: const EventRef('s', '2026-05-01T09:00')),
        'ongoing': base.copyWith(ongoing: true),
        'expectedEnd': base.copyWith(expectedEnd: ZonedDateTime(Instant.parse('2026-05-01T09:00:00Z'), 'Europe/Paris')),
      };
      for (final MapEntry(key: k, value: changed) in variants.entries) {
        expect([k, eventEquals(base, changed)], [k, false]);
      }
      expect(eventEquals(base, base.copyWith(revision: 99)), true);
    });

    test('nested props from a fresh JSON fetch are equal, so a refetch changes nothing', () {
      CalEvent fresh() => ev(
        EventInput.fromJson({
          ...jsonDecode('{"id":"full","start":"2026-05-01T09:00[Europe/Paris]","end":"2026-05-01T10:00[Europe/Paris]"}')
              as Map<String, Object?>,
          'extendedProps': jsonDecode('{"room":{"floor":2,"tags":["x"]}}'),
        }),
      );
      final a = fresh();
      final b = fresh();
      expect(a.props, isNot(same(b.props)));
      expect(eventEquals(a, b), true);
    });

    test('sameValue: structure for plain data, identity for anything else', () {
      expect(
        sameValue(
          {
            'a': [
              1,
              {'b': 2},
            ],
          },
          {
            'a': [
              1,
              {'b': 2},
            ],
          },
        ),
        true,
      );
      expect(sameValue({'a': 1}, {'a': 1, 'b': null}), false);
      expect(sameValue([1, 2], [2, 1]), false);
      expect(sameValue(Box(1), Box(1)), false);
      int f() => 1;
      expect(sameValue(f, f), true);
      final nan = 0.0 / 0.0;
      expect(sameValue(nan, nan), true);
    });

    test('an update that restates every field of a full event changes nothing (toInput loses nothing)', () {
      final store = EventStore();
      store.apply([EventMutation(after: ev(full()))], ChangeCause.api);
      final r = applyCommand(store.snapshot, UpdateEvent('full', const EventPatch()), CommandContext(normalize: ctx()));
      expect(r.ok, true);
      expect(r.mutations, isEmpty);
    });
  });

  group('an event editable by its own say (18k review)', () {
    test('gaining or losing its own true is a change; a no-op patch keeps it; revoking one keeps the other', () {
      final store = EventStore();
      CalEvent n(EventInput input) {
        final r = normalizeEvent(input, ctx());
        if (!r.ok || r.value is! NormalizedEvent) fail('bad');
        return r.value!.event;
      }

      store.apply([
        EventMutation(
          after: n(EventInput(id: 'a', start: '2026-05-01T09:00Z', duration: {'minutes': 30})),
        ),
      ], ChangeCause.api);
      final c = CommandContext(normalize: ctx());
      var r = applyCommand(store.snapshot, UpdateEvent('a', const EventPatch(durationEditable: true)), c);
      expect(r.ok, true);
      expect(r.mutations.length, 1);
      store.apply(r.ok ? r.mutations : [], ChangeCause.command);
      final own = store.snapshot.getEvent('a')!.perms;
      expect([own.ownStart, own.ownDuration], [false, true]);
      r = applyCommand(store.snapshot, UpdateEvent('a', const EventPatch()), c);
      expect(r.ok, true);
      expect(r.mutations, isEmpty);
      r = applyCommand(store.snapshot, UpdateEvent('a', const EventPatch(durationEditable: false)), c);
      store.apply(r.ok ? r.mutations : [], ChangeCause.command);
      final after = store.snapshot.getEvent('a')!.perms;
      expect([after.ownStart, after.ownDuration], [false, false]);
    });
  });
}
