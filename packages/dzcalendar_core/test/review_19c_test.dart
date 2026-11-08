// What the 19c reviews found, each confirmed by running it before the fix,
// and the owner's decisions 12–13 (2026-11-08).

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

const p = '[Europe/Paris]';

({EventStore store, History history}) withSeries() {
  final store = EventStore();
  final h = History(
    store,
    CommandContext(
      normalize: NormalizeContext(displayZone: 'Europe/Paris', newId: createIdGenerator('n')),
    ),
  );
  h.run(CreateEvent(EventInput(id: 's', start: '2026-10-05T09:00$p', rrule: 'FREQ=WEEKLY;COUNT=4')));
  return (store: store, history: h);
}

List<String> errors(RunResult r) => [
  for (final x in r.result.problems.where((x) => x.isError)) '${x.code.code} ${x.path}',
];

void main() {
  group('Command.fromJson is total: what it cannot read is said, never guessed', () {
    test('an unreadable rrule never stops a series repeating (the TS refuses it)', () {
      final (:store, history: h) = withSeries();
      for (final json in [
        {'type': 'series.rule', 'id': 's', 'rrule': 42},
        {'type': 'series.rule', 'id': 's'},
      ]) {
        expect(errors(h.run(Command.fromJson(json))), ['invalid-rrule command.rrule']);
      }
      expect(store.snapshot.getSeries('s'), isNotNull);
      // Only a null written out stops it.
      expect(h.run(Command.fromJson({'type': 'series.rule', 'id': 's', 'rrule': null})).ok, isTrue);
      expect(store.snapshot.getSeries('s'), isNull);
    });

    test('a key that is not a string never reaches the whole series', () {
      final (:store, history: h) = withSeries();
      expect(errors(h.run(Command.fromJson({'type': 'event.delete', 'id': 's', 'key': 123}))), [
        'invalid-edit command.key',
      ]);
      expect(store.snapshot.getSeries('s'), isNotNull);
    });

    test('wrong types are problems at their paths, nested ones included; null is absent', () {
      expect(Command.fromJson({'type': 'batch', 'label': 5, 'commands': <Object>[]}), isA<InvalidCommand>());
      expect(Command.fromJson({'type': 'event.delete', 'id': 'x', 'scope': null}), isA<DeleteEvent>());
      final bad = Command.fromJson({
        'type': 'batch',
        'commands': [
          {
            'type': 'event.move',
            'id': 'x',
            'start': '2026-10-05T09:00',
            'resourceIds': ['a', 1],
          },
          {
            'type': 'event.update',
            'id': 'x',
            'patch': {'title': 3, 'rrule': 'FREQ=DAILY'},
          },
          {'type': 'nope'},
        ],
      });
      expect(
        [for (final x in (bad as InvalidCommand).problems) '${x.code.code} ${x.path}'],
        [
          'invalid-event command.commands[0].resourceIds',
          'invalid-event command.commands[1].patch.title',
          'invalid-rrule command.commands[1].patch.rrule',
          'invalid-edit command.commands[2].type',
        ],
      );
    });
  });

  test('a field both set and cleared is refused, not cleared in silence', () {
    final store = EventStore();
    final h = History(
      store,
      CommandContext(
        normalize: NormalizeContext(displayZone: 'UTC', newId: createIdGenerator('n')),
      ),
    );
    h.run(CreateEvent(EventInput(id: 'e', start: '2026-10-05T09:00[UTC]', tone: 'blue')));
    final r = h.run(UpdateEvent('e', const EventPatch(tone: 'red', clear: {EventField.tone})));
    expect(errors(r), ['invalid-edit command.patch.tone']);
    expect(store.snapshot.getEvent('e')!.tone, 'blue');
  });

  test('a weekStart that is no weekday is the programmer\'s: it throws, once', () {
    final ctx = CommandContext(
      normalize: NormalizeContext(displayZone: 'UTC', newId: createIdGenerator('n')),
      weekStart: 8,
    );
    expect(
      () => applyCommand(StoreSnapshot.empty, CreateEvent(EventInput(start: '2026-10-05')), ctx),
      throwsArgumentError,
    );
  });

  test('History tells its listeners when Undo or Redo becomes possible or not, and lets go on dispose', () {
    final store = EventStore();
    final h = History(
      store,
      CommandContext(
        normalize: NormalizeContext(displayZone: 'UTC', newId: createIdGenerator('n')),
      ),
    );
    final heard = <(bool, bool)>[];
    void listener() => heard.add((h.canUndo, h.canRedo));
    h.addListener(listener);
    h.run(CreateEvent(EventInput(id: 'a', start: '2026-10-05T09:00[UTC]')));
    h.run(CreateEvent(EventInput(id: 'b', start: '2026-10-06T09:00[UTC]')));
    h.undo();
    h.undo();
    h.redo();
    expect(heard, [(true, false), (true, true), (false, true), (true, true)]);
    h.dispose();
    h.redo();
    expect(heard, hasLength(4));
  });
}
