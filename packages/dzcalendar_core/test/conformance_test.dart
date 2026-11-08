// Runs every case of conformance/cases (copied from the main repository by
// tool/sync_conformance.dart, never edited here). Each suite has an adapter
// that turns the port's answer into the case's plain JSON; the comparison is
// then exact, as in the TypeScript runner. A suite not ported yet is skipped
// with its family, so the count stays in sight.

import 'dart:convert';
import 'dart:io';

import 'package:dzcalendar_core/internal.dart';
import 'package:test/test.dart';

typedef Json = Map<String, Object?>;

String? _str(Object? x) => x?.toString();

const defaultLimit = 10000;

String _startText(CalEvent e) => switch (e) {
  TimedEvent(:final start) => '$start',
  AllDayEvent(:final start) => '$start',
};

String _endText(CalEvent e) => switch (e) {
  TimedEvent(:final end) => '$end',
  AllDayEvent(:final end) => '$end',
};

/// A zoned string as Temporal.ZonedDateTime.from reads it, through the port's own parser.
ZonedDateTime _zoned(String text) {
  final r = normalizeEvent(
    EventInput(start: text),
    NormalizeContext(displayZone: 'UTC', newId: createIdGenerator('z')),
  );
  final e = r.value?.event;
  if (e is! TimedEvent || r.problems.isNotEmpty) throw StateError('not a plain zoned string: $text ${r.problems}');
  return e.start;
}

WallPolicy _policy(Object? p) => switch (p) {
  'compatible' => WallPolicy.compatible,
  'earlier' => WallPolicy.earlier,
  'later' => WallPolicy.later,
  'reject' => WallPolicy.reject,
  {'preferOffset': final String offset} => WallPolicy.preferOffset(offset),
  _ => throw ArgumentError.value(p, 'policy'),
};

final _dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');

final Map<String, Object? Function(Json)> _adapters = {
  'series-edit': (input) {
    final zone = input['zone']! as String;
    final store = EventStore();
    // One context, one id generator for the whole run, as the TS runner's.
    final context = CommandContext(
      normalize: NormalizeContext(displayZone: zone, newId: createIdGenerator('n')),
    );
    final h = History.reading(store, () => context);
    List<String> errors(RunResult r) => [for (final p in r.result.problems.where((p) => p.isError)) p.code.code];
    final created = h.run(CreateEvent(EventInput.fromJson(input['event']! as Json)));
    if (!created.ok) return {'error': errors(created)};
    for (final op in (input['ops']! as List).cast<Json>()) {
      switch (op['type']) {
        case 'undo':
          h.undo();
        case 'redo':
          h.redo();
        default:
          final r = h.run(Command.fromJson(op));
          if (!r.ok) return {'error': errors(r)};
      }
    }
    final w = input['window']! as Json;
    final snap = store.snapshot;
    final shown = [
      for (final i in snap.queryInstances(
        viewWindow(PlainDate.parse(w['from']! as String), PlainDate.parse(w['to']! as String), zone),
      ))
        '${i.origin.name}|${i.event.title}|${_startText(i.event)}|${_endText(i.event)}',
    ];
    final series = snap.allSeries.toList()
      ..sort(
        (a, b) => switch ((a.start, b.start)) {
          (PlainDate x, PlainDate y) => x.compareTo(y),
          (ZonedDateTime x, ZonedDateTime y) => x.compareTo(y),
          _ => 0,
        },
      );
    return {
      'shown': shown,
      'series': [
        for (final sr in series)
          sr.set.rules.map(serializeRRule).join(',') +
              (sr.set.exdates.isNotEmpty ? '|EXDATE=${sr.set.exdates.join(',')}' : ''),
      ],
    };
  },
  'rrule-expand': (input) {
    final parsed = parseRRule(input['rrule']! as String);
    final rule = parsed.rule;
    if (rule == null) return {'problem': parsed.problem!.code};
    final dtstart = input['dtstart']! as String;
    final window = input['window'] as Json?;
    final limit = input['limit'] as int? ?? defaultLimit;
    final exdates = (input['exdates'] as List?)?.cast<String>() ?? const [];
    final rdates = (input['rdates'] as List?)?.cast<String>() ?? const [];
    final withProblems = input['withProblems'] == true;
    Object out(List<String> starts, List<RRuleProblem> problems) => withProblems
        ? {
            'starts': starts,
            'problems': [for (final p in problems) p.code],
          }
        : starts;
    if (_dateOnly.hasMatch(dtstart)) {
      final start = PlainDate.parse(dtstart);
      final set = RRuleSet(
        [rule],
        exdates: [for (final x in exdates) ExDate.date(PlainDate.parse(x))],
        rdates: [for (final x in rdates) RDate.date(PlainDate.parse(x))],
      );
      final r = window == null
          ? expandDates(start, set, start, start.addYears(200), limit)
          : expandDates(
              start,
              set,
              PlainDate.parse(window['from']! as String),
              PlainDate.parse(window['to']! as String),
              limit,
            );
      return out([for (final d in r.starts) '$d'], r.problems);
    }
    final start = _zoned(dtstart);
    final set = RRuleSet(
      [rule],
      exdates: [
        for (final x in exdates) x.contains('T') ? ExDate.instant(Instant.parse(x)) : ExDate.date(PlainDate.parse(x)),
      ],
      rdates: [for (final x in rdates) RDate.zoned(_zoned(x))],
    );
    final r = window == null
        ? expandZoned(start, set, start.instant, start.instant.addMs(365 * 400 * 86400000), limit)
        : expandZoned(
            start,
            set,
            Instant.parse(window['from']! as String),
            Instant.parse(window['to']! as String),
            limit,
          );
    return out([for (final z in r.starts) '${z.instant}'], r.problems);
  },
  'time-axis': (input) {
    final axis = buildColumnAxis(
      PlainDate.parse(input['date']! as String),
      input['zone']! as String,
      mode: AxisMode.values.byName(input['mode']! as String),
    );
    return {
      'length': axis.length,
      'bands': [
        for (final b in axis.bands) [b.kind.name, b.from, b.to],
      ],
    };
  },
  'segment': (input) {
    final zone = input['zone']! as String;
    final r = normalizeEvent(
      EventInput.fromJson({'id': 'e', ...input['event']! as Json}),
      NormalizeContext(displayZone: zone, newId: createIdGenerator('k')),
    );
    if (!r.ok) throw StateError('${r.problems}');
    final days = dayInfos(PlainDate.parse(input['firstDate']! as String), input['days']! as int, zone);
    final segs = segmentTimed(
      EventInstance('e', r.value!.event, InstanceOrigin.single),
      days,
      cutAtRepeat: input['cutAtRepeat']! as bool,
    );
    return [
      for (final s in segs) [s.dayIndex, s.part, '${s.from}', '${s.to}'],
    ];
  },
  'layout-column': (input) {
    final items = [
      for (final x in (input['items']! as List).cast<Json>())
        ColItem(
          key: x['key']! as String,
          start: (x['start']! as num).toDouble(),
          end: (x['end']! as num).toDouble(),
          order: x['order']! as int,
        ),
    ];
    return [
      for (final p in layoutColumn(items, minVisual: (input['minVisual']! as num).toDouble()))
        [p.key, p.lane, p.lanes, p.left, p.width],
    ];
  },
  'navigation': (input) {
    var spec = builtinViews[input['view']! as String]!;
    final over = input['overrides'] as Json?;
    if (over != null) {
      spec = spec.copyWith(
        hiddenDays: (over['hiddenDays'] as List?)?.cast<int>(),
        fixedWeekCount: over['fixedWeekCount'] as bool?,
      );
      final unknown = over.keys.where((k) => k != 'hiddenDays' && k != 'fixedWeekCount');
      if (unknown.isNotEmpty) throw UnimplementedError('override $unknown');
    }
    final ctx = NavContext(
      firstDay: input['firstDay']! as int,
      today: PlainDate.parse(input['today'] as String? ?? '2026-01-01'),
    );
    final dir = switch (input['dir']) {
      'prev' => NavDirection.prev,
      'next' => NavDirection.next,
      'today' => NavDirection.today,
      {'to': final String to} => NavDirection.to(PlainDate.parse(to)),
      final other => throw ArgumentError.value(other, 'dir'),
    };
    final next = navigate(PlainDate.parse(input['anchor']! as String), spec, dir, ctx);
    final range = computeViewRange(next, spec, ctx);
    return {'anchor': '$next', 'start': '${range.start}', 'end': '${range.end}', 'dates': range.dates.length};
  },
  'normalize': (input) {
    final c = input['context']! as Json;
    final r = normalizeEvent(
      EventInput.fromJson(input['event']! as Json),
      NormalizeContext(
        displayZone: c['displayZone']! as String,
        defaultEventZone: c['defaultEventZone'] as String?,
        strictZones: c['strictZones'] as bool? ?? false,
        newId: createIdGenerator('k'),
      ),
    );
    final value = r.value;
    if (value == null) {
      return {
        'ok': false,
        'errors': [for (final p in r.problems.where((p) => p.isError)) p.code.code],
      };
    }
    final e = value.event;
    return {
      'ok': true,
      'allDay': e.allDay,
      'start': switch (e) {
        TimedEvent(:final start) => '$start',
        AllDayEvent(:final start) => '$start',
      },
      'end': switch (e) {
        TimedEvent(:final end) => '$end',
        AllDayEvent(:final end) => '$end',
      },
      'warnings': [for (final p in r.problems) p.code.code],
      if (e is TimedEvent) 'zoneGuessed': e.zoneGuessed,
    };
  },
  'zone-dayinfo': (input) {
    final d = dayInfo(PlainDate.parse(input['date']! as String), input['zone']! as String);
    return {
      'start': _str(d.start),
      'end': _str(d.end),
      'lengthMinutes': d.lengthMinutes,
      'kind': d.kind.name,
      'transitions': [
        for (final t in d.transitions)
          {
            'at': _str(t.at),
            'offsetBefore': t.offsetBefore,
            'offsetAfter': t.offsetAfter,
            'deltaMinutes': t.deltaMinutes,
            'wallBefore': _str(t.wallBefore),
            'wallAfter': _str(t.wallAfter),
            'kind': t.kind.name,
          },
      ],
    };
  },
  'zone-resolve': (input) {
    final r = resolveWall(
      PlainDate.parse(input['date']! as String),
      PlainTime.parse(input['time']! as String),
      input['zone']! as String,
      _policy(input['policy']),
    );
    return {
      'instant': _str(r.instant),
      'other': _str(r.other),
      'exists': r.exists,
      'ambiguous': r.ambiguous,
      'offsetMatched': r.offsetMatched,
    };
  },
};

/// Where each suite not yet ported will be (ROADMAP.md, Phase 19).
const _pending = {
  'slots': '19d',
  'ical-parse': '19d',
  'resource-tree': '19d',
  'resource-rules': '19d',
  'timeline-axis': '19d',
};

void main() {
  // `dart test` runs from the package; the cases sit at the repository's root.
  final dir = Directory('../../conformance/cases');
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.json')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('the copy holds cases', () => expect(files, isNotEmpty));

  final bySuite = <String, List<Json>>{};
  for (final f in files) {
    final c = jsonDecode(f.readAsStringSync()) as Json;
    bySuite.putIfAbsent(c['suite']! as String, () => []).add(c);
  }

  test('every suite is ported or planned', () {
    expect(bySuite.keys.where((s) => !_adapters.containsKey(s) && !_pending.containsKey(s)), isEmpty);
  });

  for (final MapEntry(key: suite, value: cases) in bySuite.entries) {
    final adapter = _adapters[suite];
    group(suite, () {
      for (final c in cases) {
        test(
          '${c['id']}: ${c['description']}',
          () => expect(adapter!(c['input']! as Json), equals(c['expected'])),
          skip: adapter == null ? 'ported in ${_pending[suite]}' : false,
        );
      }
    });
  }
}
