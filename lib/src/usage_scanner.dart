import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// What the code of a project refers to.
final class UsageIndex {
  /// Creates an index.
  const UsageIndex({
    required this.accessors,
    required this.strings,
    required this.valuesTargets,
    required this.deadFiles,
    required this.missingFiles,
  });

  /// Names read as a property of something, as in `Assets.images.logo`.
  ///
  /// Only property reads are collected: a local variable that happens to carry
  /// the name of an accessor does not make the asset used.
  final Set<String> accessors;

  /// Values of the string literals met in the code.
  ///
  /// They cover the assets addressed by a path instead of an accessor.
  final Set<String> strings;

  /// What a `values` was read on, as in `images` for `Assets.images.values`.
  ///
  /// Such a read names no asset of its own but uses every asset of the class it
  /// belongs to, which is how a project precaches or lists a whole directory.
  final Set<String> valuesTargets;

  /// Files under `lib` no entry point reaches, relative to the project root.
  ///
  /// What they refer to is not collected.
  final List<String> deadFiles;

  /// Project files the search for dead code needs and the scan does not hold,
  /// relative to the project root: an entry point, or a file that a reached
  /// file imports — typically generated code not built yet.
  ///
  /// Without them nothing can be told dead, so when there are any, every file
  /// counts and [deadFiles] is empty.
  final List<String> missingFiles;
}

/// Collects the usages from every Dart file under [directories].
///
/// [skip] is the generated file itself — it names every accessor and holds
/// every path, so scanning it would hide all the unused assets.
///
/// A file under `lib` counts only when an entry point or a file outside `lib`
/// reaches it through imports, exports and parts; `package:` imports of
/// [packageName] resolve into `lib`. [entryPoints] default to the files under
/// `lib` that declare a top-level `main`. Without any, the project is a
/// package, and every file counts.
UsageIndex scanUsages({
  required String root,
  required List<String> directories,
  required String skip,
  String? packageName,
  List<String>? entryPoints,
}) {
  final projectRoot = p.canonicalize(root);
  final lib = p.join(projectRoot, 'lib');
  final skipped = p.canonicalize(p.join(root, skip));
  final units = <String, CompilationUnit>{};
  final names = <String, String>{};

  for (final directory in directories) {
    final entities = Directory(p.join(root, directory));
    if (!entities.existsSync()) continue;

    for (final entity in entities.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (p.extension(entity.path) != '.dart') continue;

      final path = p.canonicalize(entity.path);
      if (path == skipped) continue;

      units[path] = parseString(
        content: entity.readAsStringSync(),
        throwIfDiagnostics: false,
      ).unit;
      names[path] = _posix(p.relative(entity.path, from: root));
    }
  }

  final seeds = entryPoints == null
      ? <String>[
          for (final MapEntry(key: path, value: unit) in units.entries)
            if (p.isWithin(lib, path) && _declaresMain(unit)) path,
        ]
      : <String>[
          for (final entryPoint in entryPoints)
            p.canonicalize(p.join(root, _posix(entryPoint))),
        ];

  var live = units.keys.toSet();
  var missing = <String>{};
  if (seeds.isNotEmpty) {
    final reach = _reachable(
      units,
      seeds: <String>[
        ...seeds,
        for (final path in units.keys)
          if (!p.isWithin(lib, path)) path,
      ],
      skipped: skipped,
      projectRoot: projectRoot,
      lib: lib,
      packageName: packageName,
    );
    missing = reach.missing;
    if (missing.isEmpty) live = reach.live;
  }

  final visitor = _UsageVisitor();
  final deadFiles = <String>[];
  for (final MapEntry(key: path, value: unit) in units.entries) {
    if (live.contains(path)) {
      unit.visitChildren(visitor);
    } else {
      deadFiles.add(names[path]!);
    }
  }
  deadFiles.sort();

  return UsageIndex(
    accessors: visitor.accessors,
    strings: visitor.strings,
    valuesTargets: visitor.valuesTargets,
    deadFiles: deadFiles,
    missingFiles: <String>[
      for (final path in missing) _posix(p.relative(path, from: projectRoot)),
    ]..sort(),
  );
}

String _posix(String path) => path.replaceAll(r'\', '/');

bool _declaresMain(CompilationUnit unit) => unit.declarations.any(
  (declaration) =>
      declaration is FunctionDeclaration && declaration.name.lexeme == 'main',
);

/// Files of [units] reached from [seeds], and the project files on the way
/// that [units] does not hold, apart from the [skipped] generated file.
({Set<String> live, Set<String> missing}) _reachable(
  Map<String, CompilationUnit> units, {
  required List<String> seeds,
  required String skipped,
  required String projectRoot,
  required String lib,
  required String? packageName,
}) {
  final pending = List<String>.of(seeds);
  final live = <String>{};
  final missing = <String>{};

  while (pending.isNotEmpty) {
    final path = pending.removeLast();
    if (live.contains(path)) continue;

    final unit = units[path];
    if (unit == null) {
      if (path != skipped && p.isWithin(projectRoot, path)) missing.add(path);
      continue;
    }

    live.add(path);
    for (final uri in _referencedUris(unit)) {
      final target = _resolve(
        uri,
        from: path,
        lib: lib,
        packageName: packageName,
      );
      if (target != null) pending.add(target);
    }
  }

  return (live: live, missing: missing);
}

/// URIs of the imports, exports and parts of [unit], conditional ones included.
Iterable<String> _referencedUris(CompilationUnit unit) sync* {
  for (final directive in unit.directives.whereType<UriBasedDirective>()) {
    if (directive.uri.stringValue case final uri?) yield uri;
    if (directive is! NamespaceDirective) continue;

    for (final configuration in directive.configurations) {
      if (configuration.uri.stringValue case final uri?) yield uri;
    }
  }
}

/// Canonical path of the project file [uri] points to, or `null` for a file of
/// the SDK or of another package.
///
/// A file under [lib] is a library of the package, so a relative [uri] is
/// resolved against its `package:` URI, as Dart does: a `..` too many stops at
/// the root of `lib` instead of leaving it.
String? _resolve(
  String uri, {
  required String from,
  required String lib,
  required String? packageName,
}) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return null;

  final base = packageName != null && p.isWithin(lib, from)
      ? Uri(
          scheme: 'package',
          path: '$packageName/${_posix(p.relative(from, from: lib))}',
        )
      : p.toUri(from);
  final resolved = base.resolveUri(parsed);

  switch (resolved.scheme) {
    case 'file':
      return p.canonicalize(p.fromUri(resolved));
    case 'package':
      final segments = resolved.pathSegments;
      if (segments.isEmpty || segments.first != packageName) return null;

      return p.canonicalize(p.joinAll([lib, ...segments.skip(1)]));
  }

  return null;
}

/// Strings of a configuration file that address an asset.
///
/// Assets are referenced from outside the Dart code as well: the launcher icon
/// and the splash image live in `pubspec.yaml` or in a config of their own,
/// such as `flutter_native_splash.yaml`, and nothing in the code ever mentions
/// them.
///
/// With [skipDeclaredAssets] the `flutter: assets:` list is left out — it
/// declares directories, and a declared directory would otherwise cover every
/// asset inside it, hiding all of them. Pass it for a `pubspec.yaml` and only
/// for it.
///
/// Every document of a multi-document file is read. [sourceUrl] names the file
/// in the [YamlException] a malformed one throws.
Set<String> configReferences(
  String yaml, {
  bool skipDeclaredAssets = false,
  Uri? sourceUrl,
}) {
  final references = <String>{};

  void walk(Object? node) {
    switch (node) {
      case String value:
        references.add(value);
      case YamlList list:
        list.nodes.forEach(walk);
      case YamlMap map:
        for (final entry in map.nodes.entries) {
          walk(entry.value);
        }
      case YamlScalar scalar:
        walk(scalar.value);
    }
  }

  for (final document in loadYamlStream(yaml, sourceUrl: sourceUrl)) {
    if (document is! YamlMap) {
      walk(document);
      continue;
    }

    for (final entry in document.nodes.entries) {
      final isDeclaration =
          skipDeclaredAssets && entry.key.toString() == 'flutter';
      if (!isDeclaration) {
        walk(entry.value);
        continue;
      }

      final flutter = entry.value;
      if (flutter is! YamlMap) continue;

      for (final flutterEntry in flutter.nodes.entries) {
        if (flutterEntry.key.toString() == 'assets') continue;
        walk(flutterEntry.value);
      }
    }
  }

  return references;
}

final class _UsageVisitor extends RecursiveAstVisitor<void> {
  final Set<String> accessors = <String>{};
  final Set<String> strings = <String>{};
  final Set<String> valuesTargets = <String>{};

  @override
  void visitPropertyAccess(PropertyAccess node) {
    super.visitPropertyAccess(node);
    _read(
      name: node.propertyName.name,
      target: node.target,
    );
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    super.visitPrefixedIdentifier(node);
    _read(
      name: node.identifier.name,
      target: node.prefix,
    );
  }

  void _read({
    required String name,
    required Expression? target,
  }) {
    accessors.add(name);
    if (name != 'values') return;

    final owner = _nameOf(target);
    if (owner != null) valuesTargets.add(owner);
  }

  static String? _nameOf(Expression? target) => switch (target) {
    SimpleIdentifier(:final name) => name,
    PrefixedIdentifier(:final identifier) => identifier.name,
    PropertyAccess(:final propertyName) => propertyName.name,
    _ => null,
  };

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    super.visitSimpleStringLiteral(node);
    strings.add(node.value);
  }
}
