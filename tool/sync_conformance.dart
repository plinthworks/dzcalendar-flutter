// Copies the main repository's conformance cases here, or checks the copy.
//
//   dart run tool/sync_conformance.dart [--from <main repository>] [--check]
//
// The cases are never edited here (CLAUDE.md): a case failing is a port bug
// or a finding for the main repository. `--from` defaults to ../dzcalendar.
// The copy records the commit it came from in conformance/SOURCE. `--check`
// writes nothing and fails when any case differs, is missing or is extra —
// CI runs it against the main repository's current main branch.

import 'dart:io';

void main(List<String> args) {
  final check = args.contains('--check');
  final fromAt = args.indexOf('--from');
  final root = File.fromUri(Platform.script).parent.parent.path;
  final from = fromAt >= 0 && fromAt + 1 < args.length ? args[fromAt + 1] : '$root/../dzcalendar';
  final source = Directory('$from/conformance/cases');
  final target = Directory('$root/conformance/cases');
  if (!source.existsSync()) {
    stderr.writeln('no conformance cases at ${source.path}');
    exit(2);
  }

  Map<String, String> read(Directory dir) => !dir.existsSync()
      ? {}
      : {
          // Every file, not only *.json: a fixture added beside the cases counts.
          for (final f in dir.listSync(recursive: true).whereType<File>())
            if (!f.path.endsWith('.DS_Store')) f.path.substring(dir.path.length + 1): f.readAsStringSync(),
        };

  final wanted = read(source);
  final have = read(target);
  final missing = wanted.keys.where((k) => !have.containsKey(k)).toList()..sort();
  final extra = have.keys.where((k) => !wanted.containsKey(k)).toList()..sort();
  final changed = wanted.keys.where((k) => have.containsKey(k) && have[k] != wanted[k]).toList()..sort();

  if (check) {
    for (final k in missing) {
      stderr.writeln('missing: $k');
    }
    for (final k in extra) {
      stderr.writeln('extra:   $k');
    }
    for (final k in changed) {
      stderr.writeln('changed: $k');
    }
    if (missing.isEmpty && extra.isEmpty && changed.isEmpty) {
      stdout.writeln('conformance copy current: ${wanted.length} cases');
      return;
    }
    stderr.writeln('conformance copy stale: run dart run tool/sync_conformance.dart');
    exit(1);
  }

  if (target.existsSync()) target.deleteSync(recursive: true);
  for (final MapEntry(:key, :value) in wanted.entries) {
    File('${target.path}/$key')
      ..createSync(recursive: true)
      ..writeAsStringSync(value);
  }
  final commit = Process.runSync('git', ['-C', from, 'rev-parse', 'HEAD']);
  final dirty = Process.runSync('git', ['-C', from, 'status', '--porcelain', '--', 'conformance/cases']);
  final head = commit.exitCode == 0 ? (commit.stdout as String).trim() : 'unknown';
  final note = dirty.exitCode == 0 && (dirty.stdout as String).trim().isNotEmpty ? ' (with uncommitted changes)' : '';
  File('$root/conformance/SOURCE').writeAsStringSync(
    'Copied from plinthworks/dzcalendar conformance/cases at $head$note.\n'
    'For information only: --check compares the cases themselves with the main\n'
    "repository's current ones, whatever commit this names.\n"
    'Never edit here: run dart run tool/sync_conformance.dart.\n',
  );
  stdout.writeln(
    '${wanted.length} cases copied from $head$note '
    '(${missing.length} new, ${changed.length} changed, ${extra.length} removed)',
  );
}
