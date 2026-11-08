// Checks the bundled zone data against IANA's own reader, zdump, of the same
// release: every offset change zdump lists from 1800 to 2150 must be one of
// ours, with the same offsets on both sides, and we must have no other.
//
//   dart run tool/check_tzdata.dart <zdump> <zoneinfo dir>
//
// tool/refresh_tzdata.sh runs it after every rebuild; any difference fails.

import 'dart:io';

import 'package:dzcalendar_core/dzcalendar_core.dart';
import 'package:dzcalendar_core/src/zone/tzdata.g.dart';

const _from = 1800;
const _to = 2151; // zdump's -c upper year is exclusive
const _months = {
  'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6, //
  'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
};
// "… Sun Mar 29 00:59:59 2026 UT = Sun Mar 29 01:59:59 2026 CET isdst=0 gmtoff=3600"
final _line = RegExp(r' \w{3} (\w{3}) +(\d+) (\d\d):(\d\d):(\d\d) (-?\d+) UT = .* gmtoff=(-?\d+)$');

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: dart run tool/check_tzdata.dart <zdump> <zoneinfo dir>');
    exit(64);
  }
  final [zdump, zoneinfo] = args;
  final names = [...tzdataZones.keys, ...tzdataLinks.keys]..sort();
  final from = Instant.parse('$_from-01-01T00:00:00Z');
  final to = Instant.parse('$_to-01-01T00:00:00Z');
  final failures = <String>[];
  var changes = 0;

  for (final name in names) {
    final run = Process.runSync(zdump, ['-v', '-c', '$_from,$_to', '$zoneinfo/$name']);
    if (run.exitCode != 0) {
      failures.add('$name: zdump failed: ${run.stderr}');
      continue;
    }
    final rules = ZoneRules.of(name)!;
    // zdump prints each change as two lines: its last second, then its first.
    final points = <(int, int)>[];
    for (final text in (run.stdout as String).split('\n')) {
      final m = _line.firstMatch(text);
      if (m == null) continue;
      // -v also prints the representable extremes, whatever -c says.
      final year = int.parse(m[6]!);
      if (year < _from || year >= _to) continue;
      final day = PlainDate(year, _months[m[1]]!, int.parse(m[2]!));
      final ms = (day.epochDay * 86400 + int.parse(m[3]!) * 3600 + int.parse(m[4]!) * 60 + int.parse(m[5]!)) * 1000;
      points.add((ms, int.parse(m[7]!) * 1000));
    }
    final theirs = <int>[];
    for (final (at, offset) in points) {
      final ours = rules.offsetAt(at);
      if (ours != offset) {
        failures.add('$name at ${Instant.fromEpochMilliseconds(at)}: zdump $offset ms, ours $ours ms');
      }
    }
    for (var i = 1; i < points.length; i++) {
      final (before, offBefore) = points[i - 1];
      final (at, offAfter) = points[i];
      if (at - before == 1000 && offBefore != offAfter) theirs.add(at);
    }
    final ours = [for (final t in transitionsBetween(from, to, name)) t.at.epochMilliseconds];
    final missing = theirs.toSet().difference(ours.toSet());
    final extra = ours.toSet().difference(theirs.toSet());
    for (final t in missing) {
      failures.add('$name: change at ${Instant.fromEpochMilliseconds(t)} missing');
    }
    for (final t in extra) {
      failures.add('$name: change at ${Instant.fromEpochMilliseconds(t)} that zdump does not have');
    }
    changes += theirs.length;
  }

  if (failures.isNotEmpty) {
    failures.take(40).forEach(stderr.writeln);
    stderr.writeln('${failures.length} differences from zdump');
    exit(1);
  }
  stdout.writeln('tzdata $tzdataVersion agrees with zdump: ${names.length} names, $changes changes, $_from–${_to - 1}');
}
