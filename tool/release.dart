// Makes a release, as `npm version` does (owner's decisions 65–67):
//
//   dart run tool/release.dart 1.0.1
//
// Sets X.Y.Z in both pubspecs — the widgets ask for exactly `dzcalendar_core:
// X.Y.Z`, since they use its internal.dart — and `^X.Y.Z` in the example's and
// the showcase's; checks both CHANGELOG.md have a `## X.Y.Z` section, commits
// "Release X.Y.Z" and tags vX.Y.Z. It pushes nothing: pushing the tag publishes (publish.yml).
//
// Refuses a dirty tree, a branch other than main, a version not above the
// current one, or a missing changelog section.
// ignore_for_file: avoid_print
import 'dart:io';

const _packages = ['packages/dzcalendar_core', 'packages/dzcalendar'];

/// The workspace's apps on the packages: their constraints follow, or a major
/// version would not resolve.
const _apps = ['packages/dzcalendar/example', 'apps/showcase'];

void main(List<String> args) {
  if (args.length != 1 || _parse(args.single) == null) _fail('usage: dart run tool/release.dart X.Y.Z');
  final next = args.single;
  final current = RegExp(
    r'^version: (\S+)$',
    multiLine: true,
  ).firstMatch(File('${_packages.first}/pubspec.yaml').readAsStringSync())?.group(1);
  final from = current == null ? null : _parse(current);
  if (from == null) _fail('${_packages.first}/pubspec.yaml has no "version: X.Y.Z" line');
  if (_compare(_parse(next)!, from) <= 0) _fail('$next is not above $current');

  if (_git(['rev-parse', '--abbrev-ref', 'HEAD']) != 'main') _fail('not on main');
  if (_git(['status', '--porcelain']).isNotEmpty) _fail('the working tree has changes: commit them first');
  if (_git(['tag', '--list', 'v$next']).isNotEmpty) _fail('the tag v$next exists');

  for (final p in _packages) {
    if (!RegExp('^## ${RegExp.escape(next)}\$', multiLine: true).hasMatch(File('$p/CHANGELOG.md').readAsStringSync())) {
      _fail('$p/CHANGELOG.md has no "## $next" section: write what changed first');
    }
  }
  // Each pubspec, and the lines it must have after the change.
  final edits = <String, Map<RegExp, String>>{
    '${_packages[0]}/pubspec.yaml': {_line('version'): 'version: $next'},
    '${_packages[1]}/pubspec.yaml': {
      _line('version'): 'version: $next',
      _line('  dzcalendar_core'): '  dzcalendar_core: $next',
    },
    for (final app in _apps)
      '$app/pubspec.yaml': {
        _line('  dzcalendar'): '  dzcalendar: ^$next',
        _line('  dzcalendar_core'): '  dzcalendar_core: ^$next',
      },
  };
  for (final MapEntry(key: path, value: lines) in edits.entries) {
    var text = File(path).readAsStringSync();
    for (final MapEntry(key: line, value: wanted) in lines.entries) {
      if (line.allMatches(text).length != 1) _fail('$path: no single line to set to "$wanted"');
      text = text.replaceFirst(line, wanted);
    }
    File(path).writeAsStringSync(text);
  }
  _git(['commit', '-q', '-m', 'Release $next', '--', ...edits.keys]);
  _git(['tag', '-a', 'v$next', '-m', 'Release $next']);
  print('Release $next committed and tagged v$next. To publish:');
  print('  git push git@github.com:plinthworks/dzcalendar-flutter.git main v$next');
}

/// `key: value` alone on its line (no comment after it).
RegExp _line(String key) => RegExp('^$key: [^\\s#]+\$', multiLine: true);

List<int>? _parse(String v) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(v);
  return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
}

int _compare(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

String _git(List<String> args) {
  final r = Process.runSync('git', args);
  if (r.exitCode != 0) _fail('git ${args.join(' ')}: ${r.stderr}');
  return (r.stdout as String).trim();
}

Never _fail(String why) {
  stderr.writeln('release: $why');
  exit(1);
}
