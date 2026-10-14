import 'dart:io';

import 'package:appcraft_unused_assets/appcraft_unused_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _generated = '''
class \$AssetsIconsGen {
  const \$AssetsIconsGen();

  AssetGenImage get appIcon => const AssetGenImage('assets/icons/app_icon.png');
  AssetGenImage get byAccessor => const AssetGenImage('assets/icons/by_accessor.png');
  AssetGenImage get byPath => const AssetGenImage('assets/icons/by_path.png');
  AssetGenImage get orphan => const AssetGenImage('assets/icons/orphan.png');
  AssetGenImage get ignored => const AssetGenImage('assets/legacy/ignored.png');

  List<AssetGenImage> get values => [appIcon, byAccessor, byPath, orphan, ignored];
}

class \$AssetsFlagsGen {
  const \$AssetsFlagsGen();

  AssetGenImage get ru => const AssetGenImage('assets/flags/ru.png');

  List<AssetGenImage> get values => [ru];
}

abstract final class Assets {
  static const \$AssetsIconsGen icons = \$AssetsIconsGen();
  static const \$AssetsFlagsGen flags = \$AssetsFlagsGen();
}
''';

const String _pubspec = '''
name: app

appcraft_unused_assets:
  generated: lib/gen/assets.gen.dart
  ignore:
    - assets/legacy

flutter:
  assets:
    - assets/icons/

flutter_launcher_icons:
  image_path: "assets/icons/app_icon.png"
''';

void main() {
  late Directory root;
  late UnusedAssetsFinder finder;

  setUp(() {
    root = Directory.systemTemp.createTempSync('unused_assets_finder');

    void write(String relative, String content) {
      final file = File(p.join(root.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    write('pubspec.yaml', _pubspec);
    write(p.join('lib', 'gen', 'assets.gen.dart'), _generated);
    write(p.join('lib', 'screen.dart'), '''
void build() {
  Image.asset(Assets.icons.byAccessor.path);
  Image.asset('assets/icons/by_path.png');

  for (final flag in Assets.flags.values) {
    precache(flag);
  }
}
''');

    for (final asset in <String>[
      p.join('assets', 'icons', 'app_icon.png'),
      p.join('assets', 'icons', 'by_accessor.png'),
      p.join('assets', 'icons', 'by_path.png'),
      p.join('assets', 'icons', 'orphan.png'),
      p.join('assets', 'flags', 'ru.png'),
      p.join('assets', 'legacy', 'ignored.png'),
    ]) {
      write(asset, 'binary');
    }

    finder = UnusedAssetsFinder(
      config: UnusedAssetsConfig.fromPubspec(_pubspec),
      root: root.path,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('reports only the asset nothing refers to', () {
    expect(
      finder.find().unused.map((asset) => asset.path),
      <String>['assets/icons/orphan.png'],
    );
  });

  test('keeps an asset reached only through the values of its class', () {
    final report = finder.find();

    expect(
      report.unused.map((asset) => asset.path),
      isNot(contains('assets/flags/ru.png')),
    );
    expect(
      report.reachedByValues.map((asset) => asset.path),
      <String>['assets/flags/ru.png'],
    );
    expect(report.containersReachedByValues, <String>['flags']);
  });

  test('leaves a named asset out of the values blind spot', () {
    File(p.join(root.path, 'lib', 'flag.dart'))
        .writeAsStringSync('final ru = Assets.flags.ru.path;');

    expect(finder.find().reachedByValues, isEmpty);
  });

  test('plans the deletion of the variants without deleting anything', () {
    final variant = File(
      p.join(root.path, 'assets', 'icons', '2.0x', 'orphan.png'),
    );
    variant.parent.createSync(recursive: true);
    variant.writeAsStringSync('binary');

    final plan = finder.plan(finder.find().unused);

    expect(plan.assets.map((asset) => asset.path), <String>['assets/icons/orphan.png']);
    expect(plan.variants, <String>['assets/icons/2.0x/orphan.png']);
    expect(variant.existsSync(), isTrue);
  });

  test('deletes the resolution variants of a reported asset', () {
    final variant = File(
      p.join(root.path, 'assets', 'icons', '2.0x', 'orphan.png'),
    );
    variant.parent.createSync(recursive: true);
    variant.writeAsStringSync('binary');

    final report = finder.delete(finder.find().unused);

    expect(report.variants, <String>['assets/icons/2.0x/orphan.png']);
    expect(variant.existsSync(), isFalse);
  });

  test('deletes the reported files and leaves the rest alone', () {
    final deleted = finder.delete(finder.find().unused).assets;

    expect(deleted.map((asset) => asset.path), <String>['assets/icons/orphan.png']);
    expect(
      File(p.join(root.path, 'assets', 'icons', 'orphan.png')).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(root.path, 'assets', 'icons', 'app_icon.png')).existsSync(),
      isTrue,
    );
  });

  test('survives an asset that is already gone from disk', () {
    File(p.join(root.path, 'assets', 'icons', 'orphan.png')).deleteSync();

    expect(finder.delete(finder.find().unused).assets, isEmpty);
  });
}
