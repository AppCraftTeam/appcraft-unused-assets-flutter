import 'package:appcraft_unused_assets/appcraft_unused_assets.dart';
import 'package:test/test.dart';

void main() {
  test('reads the accessors of the nested style', () {
    final assets = readGeneratedAssets('''
class \$AssetsIconsGen {
  const \$AssetsIconsGen();

  /// File path: assets/icons/logo.png
  AssetGenImage get logo => const AssetGenImage('assets/icons/logo.png');

  /// File path: assets/icons/mark.vec
  SvgGenImage get mark => const SvgGenImage.vec('assets/icons/mark.vec');

  /// List of all assets
  List<dynamic> get values => [logo, mark];
}
''');

    expect(
      assets.map((asset) => '${asset.accessor}:${asset.path}'),
      <String>[
        'logo:assets/icons/logo.png',
        'mark:assets/icons/mark.vec',
      ],
    );
  });

  test('resolves the container to the field the class is reached by', () {
    final assets = readGeneratedAssets('''
class \$AssetsIconsGen {
  const \$AssetsIconsGen();

  AssetGenImage get logo => const AssetGenImage('assets/icons/logo.png');
}

abstract final class Assets {
  static const \$AssetsIconsGen icons = \$AssetsIconsGen();
}
''');

    expect(assets.single.container, 'icons');
  });

  test('resolves the container of a subdirectory to its getter', () {
    final assets = readGeneratedAssets('''
class \$AssetsImagesGen {
  const \$AssetsImagesGen();

  \$AssetsImagesFlagsGen get flags => const \$AssetsImagesFlagsGen();
}

class \$AssetsImagesFlagsGen {
  const \$AssetsImagesFlagsGen();

  AssetGenImage get ru => const AssetGenImage('assets/images/flags/ru.png');

  List<AssetGenImage> get values => [ru];
}

abstract final class Assets {
  static const \$AssetsImagesGen images = \$AssetsImagesGen();
}
''');

    expect(assets.single.container, 'flags');
  });

  test('falls back to the class name when nothing holds the class', () {
    final assets = readGeneratedAssets('''
class \$AssetsIconsGen {
  AssetGenImage get logo => const AssetGenImage('assets/icons/logo.png');
}
''');

    expect(assets.single.container, r'$AssetsIconsGen');
  });

  test('reads the accessors of the flat style', () {
    final assets = readGeneratedAssets('''
class Assets {
  static const AssetGenImage iconsLogo = AssetGenImage('assets/icons/logo.png');
}
''');

    expect(assets.single.accessor, 'iconsLogo');
    expect(assets.single.path, 'assets/icons/logo.png');
  });

  test('leaves out the accessors without a path', () {
    final assets = readGeneratedAssets('''
class AssetGenImage {
  const AssetGenImage(this._assetName);

  final String _assetName;

  String get path => _assetName;
  String get keyName => _assetName;
}
''');

    expect(assets, isEmpty);
  });

  test('drops the package prefix of a path', () {
    final assets = readGeneratedAssets('''
class \$AssetsDataGen {
  String get cities => 'packages/app/assets/data/cities.json';
  String get other => 'packages/other/assets/data/other.json';
}
''', packageName: 'app');

    expect(assets.map((asset) => asset.path), <String>[
      'assets/data/cities.json',
      'packages/other/assets/data/other.json',
    ]);
  });
}
