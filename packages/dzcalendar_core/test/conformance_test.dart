// Runs every case of conformance/cases (copied from the main repository by
// tool/sync_conformance.dart, never edited here). Each suite has an adapter
// that turns the port's answer into the case's plain JSON; the comparison is
// then exact, as in the TypeScript runner. A suite not ported yet is skipped
// with its family, so the count stays in sight.

import 'dart:convert';
import 'dart:io';

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:test/test.dart';

typedef Json = Map<String, Object?>;

String? _str(Object? x) => x?.toString();

WallPolicy _policy(Object? p) => switch (p) {
  'compatible' => WallPolicy.compatible,
  'earlier' => WallPolicy.earlier,
  'later' => WallPolicy.later,
  'reject' => WallPolicy.reject,
  {'preferOffset': final String offset} => WallPolicy.preferOffset(offset),
  _ => throw ArgumentError.value(p, 'policy'),
};

final Map<String, Object? Function(Json)> _adapters = {
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
  'normalize': '19b',
  'time-axis': '19b',
  'segment': '19b',
  'layout-column': '19b',
  'navigation': '19b',
  'rrule-expand': '19c',
  'series-edit': '19c',
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
