// The public API is closed (owner's decisions 68 and 69): every type a public
// library's names give — fields, getters, parameters, returns, supertypes,
// type arguments — is exported by that same library, so an app never needs
// `internal.dart`, `src/`, or a second package to name it.
//
// And it changes only on purpose (decision 65): `tool/api.txt` lists every
// public name and member; a name gone is a break (a major version), a name
// added is written there with `--update` (a minor version).
//
//   dart run tool/check_api.dart [--update]
//
// Exit code 1 lists each type missing, with where it is given, and each
// difference with tool/api.txt.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';

/// Each public library, with the packages whose types it must give a name
/// for, and the libraries that name them: the core's four libraries are
/// used together; the widgets' barrel names everything itself (decision 69).
const _core = [
  'package:dzcalendar_core/dzcalendar_core.dart',
  'package:dzcalendar_core/ical.dart',
  'package:dzcalendar_core/slots.dart',
  'package:dzcalendar_core/timeline.dart',
];
final _libraries = {
  for (final uri in _core) uri: (packages: ['dzcalendar_core'], namedBy: _core),
  'package:dzcalendar/dzcalendar.dart': (
    packages: ['dzcalendar', 'dzcalendar_core'],
    namedBy: ['package:dzcalendar/dzcalendar.dart'],
  ),
};

Future<void> main(List<String> args) async {
  final root = Directory.current.absolute.path;
  final collection = AnalysisContextCollection(
    includedPaths: ['$root/packages/dzcalendar_core/lib', '$root/packages/dzcalendar/lib'],
  );
  final session = collection.contextFor('$root/packages/dzcalendar/lib').currentSession;
  var missing = 0;
  final surface = <String>{};
  Future<LibraryElement2> load(String uri) async =>
      (await session.getLibraryByUri(uri) as LibraryElementResult).element2;
  for (final MapEntry(key: uri, value: (:packages, :namedBy)) in _libraries.entries) {
    final library = await load(uri);
    final exported = {for (final other in namedBy) ...(await load(other)).exportNamespace.definedNames2.values};
    final gaps = <Element2, Set<String>>{};
    void need(DartType? type, String where) {
      for (final element in _named(type)) {
        final package = _packageOf(element);
        if (package == null || !packages.contains(package) || exported.contains(element)) continue;
        if (element.name3 == null || element.name3!.startsWith('_')) continue;
        (gaps[element] ??= {}).add(where);
      }
    }

    for (final MapEntry(key: name, value: element) in library.exportNamespace.definedNames2.entries) {
      _walk(element, name, need);
      surface.addAll(_surface(uri, name, element));
    }
    for (final MapEntry(key: element, value: where) in gaps.entries) {
      missing++;
      final shown = where.take(3).join(', ');
      print('$uri: ${element.name3} (${_packageOf(element)}) — given by $shown${where.length > 3 ? ', …' : ''}');
    }
  }
  if (missing > 0) print('\n$missing types given by a public library are not exported by a public library.');

  final file = File('$root/tool/api.txt');
  final lines = surface.toList()..sort();
  if (args.contains('--update')) {
    file.writeAsStringSync('$_header${lines.join('\n')}\n');
    print('tool/api.txt: ${lines.length} names written.');
  } else {
    final known = file.existsSync()
        ? file.readAsLinesSync().where((l) => l.isNotEmpty && !l.startsWith('#')).toSet()
        : <String>{};
    final gone = known.difference(surface).toList()..sort();
    final added = surface.difference(known).toList()..sort();
    for (final l in gone) {
      print('gone: $l — a break: a major version, then --update');
    }
    for (final l in added) {
      print('new: $l — a minor version: run with --update');
    }
    if (gone.isNotEmpty || added.isNotEmpty) missing++;
  }
  if (missing > 0) exit(1);
  print('The public libraries export every type they give, and match tool/api.txt.');
}

const _header = '''# The public API (tool/check_api.dart --update): a name gone from here is a
# break, so a major version (owner's decision 65).
''';

/// The public names [element] brings to [uri]: itself, and its members.
Iterable<String> _surface(String uri, String name, Element2 element) sync* {
  final library = uri.replaceFirst('package:', '').replaceFirst('.dart', '');
  yield '$library $name';
  if (element is InterfaceElement2) {
    for (final c in element.constructors2) {
      if (c.isPublic) yield '$library $name(${c.name3 == 'new' ? '' : c.name3})';
    }
    final members = <Element2>[
      ...element.fields2.where((f) => !f.isSynthetic),
      ...element.getters2,
      ...element.setters2,
      ...element.methods2,
    ];
    for (final m in members) {
      final member = m.name3;
      if (member != null && !member.startsWith('_')) yield '$library $name.$member${m is SetterElement ? '=' : ''}';
    }
  }
}

String? _packageOf(Element2 element) {
  final uri = element.library2?.uri;
  if (uri == null || !uri.isScheme('package')) return null;
  return uri.pathSegments.first;
}

void _walk(Element2 element, String name, void Function(DartType?, String) need) {
  void params(List<FormalParameterElement> ps, String where) {
    for (final p in ps) {
      if (p.name3?.startsWith('_') ?? false) continue;
      need(p.type, where);
    }
  }

  void typeParams(List<TypeParameterElement2> ts, String where) {
    for (final t in ts) {
      need(t.bound, where);
    }
  }

  switch (element) {
    case InterfaceElement2():
      typeParams(element.typeParameters2, name);
      need(element.supertype, name);
      for (final t in [...element.interfaces, ...element.mixins]) {
        need(t, name);
      }
      if (element is MixinElement2) {
        for (final t in element.superclassConstraints) {
          need(t, name);
        }
      }
      for (final c in element.constructors2) {
        if (!c.isPublic) continue;
        params(c.formalParameters, '$name(${c.name3 == 'new' ? '' : c.name3})');
      }
      for (final f in element.fields2) {
        if (!f.isPublic || f.isSynthetic) continue;
        need(f.type, '$name.${f.name3}');
      }
      for (final g in [...element.getters2, ...element.setters2]) {
        if (!g.isPublic) continue;
        need(g.returnType, '$name.${g.name3}');
        params(g.formalParameters, '$name.${g.name3}');
      }
      for (final m in element.methods2) {
        if (!m.isPublic) continue;
        typeParams(m.typeParameters2, '$name.${m.name3}');
        need(m.returnType, '$name.${m.name3}');
        params(m.formalParameters, '$name.${m.name3}');
      }
    case ExtensionElement2():
      need(element.extendedType, name);
      for (final m in element.methods2) {
        if (!m.isPublic) continue;
        need(m.returnType, '$name.${m.name3}');
        params(m.formalParameters, '$name.${m.name3}');
      }
      for (final g in element.getters2) {
        if (g.isPublic) need(g.returnType, '$name.${g.name3}');
      }
    case TopLevelFunctionElement():
      typeParams(element.typeParameters2, name);
      need(element.returnType, name);
      params(element.formalParameters, name);
    case GetterElement():
      need(element.returnType, name);
    case SetterElement():
      params(element.formalParameters, name);
    case TopLevelVariableElement2():
      need(element.type, name);
    case TypeAliasElement2():
      typeParams(element.typeParameters2, name);
      need(element.aliasedType, name);
    default:
  }
}

/// The declared types [type] names, through type arguments, function types
/// and records.
Iterable<Element2> _named(DartType? type) sync* {
  if (type == null) return;
  if (type.alias case final alias?) {
    yield alias.element2;
    for (final t in alias.typeArguments) {
      yield* _named(t);
    }
    return;
  }
  switch (type) {
    case InterfaceType():
      yield type.element3;
      for (final t in type.typeArguments) {
        yield* _named(t);
      }
    case FunctionType():
      yield* _named(type.returnType);
      for (final p in type.formalParameters) {
        yield* _named(p.type);
      }
    case RecordType():
      for (final f in [...type.positionalFields, ...type.namedFields]) {
        yield* _named(f.type);
      }
    default:
  }
}
