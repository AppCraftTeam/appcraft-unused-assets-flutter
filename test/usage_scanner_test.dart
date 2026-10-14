import 'dart:io';

import 'package:appcraft_unused_assets/appcraft_unused_assets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('scanUsages', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('unused_assets'));
    tearDown(() => root.deleteSync(recursive: true));

    void write(String relative, String content) {
      final file = File(p.join(root.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    UsageIndex scan() => scanUsages(
      root: root.path,
      directories: const <String>['lib'],
      skip: p.join('lib', 'gen', 'assets.gen.dart'),
    );

    test('collects a name read as a property', () {
      write(p.join('lib', 'screen.dart'), '''
Widget build() => Image.asset(Assets.icons.logo.path);
''');

      expect(scan().accessors, contains('logo'));
    });

    test('ignores a local name that is not read as a property', () {
      write(p.join('lib', 'screen.dart'), '''
void build() {
  final logo = 1;
  print(logo);
}
''');

      expect(scan().accessors, isNot(contains('logo')));
    });

    test('collects the string literals', () {
      write(p.join('lib', 'screen.dart'), '''
const path = 'assets/icons/logo.png';
''');

      expect(scan().strings, contains('assets/icons/logo.png'));
    });

    test('skips the generated file', () {
      write(p.join('lib', 'gen', 'assets.gen.dart'), '''
class \$AssetsIconsGen {
  AssetGenImage get logo => const AssetGenImage('assets/icons/logo.png');
}
''');

      final usages = scan();
      expect(usages.accessors, isNot(contains('logo')));
      expect(usages.strings, isEmpty);
    });

    group('with entry points', () {
      UsageIndex scanFromMain() => scanUsages(
        root: root.path,
        directories: const <String>['lib', 'test'],
        skip: p.join('lib', 'gen', 'assets.gen.dart'),
        packageName: 'app',
        entryPoints: [p.join('lib', 'main.dart')],
      );

      test('follows imports, exports, parts and conditional imports', () {
        write(p.join('lib', 'main.dart'), '''
import 'package:app/screens/home.dart';
import 'package:other/other.dart';
import 'stub.dart' if (dart.library.io) 'io.dart';
export 'screens/settings.dart';
part 'main.g.dart';
''');
        write(p.join('lib', 'screens', 'home.dart'), '''
import '../widgets/logo.dart';
''');
        write(p.join('lib', 'widgets', 'logo.dart'), 'final a = A.logo;');
        write(p.join('lib', 'screens', 'settings.dart'), 'final a = A.gear;');
        write(p.join('lib', 'main.g.dart'), 'final a = A.splash;');
        write(p.join('lib', 'stub.dart'), 'final a = A.stub;');
        write(p.join('lib', 'io.dart'), 'final a = A.io;');

        expect(
          scanFromMain().accessors,
          containsAll(<String>['logo', 'gear', 'splash', 'stub', 'io']),
        );
      });

      test('leaves out what a file nothing imports refers to', () {
        write(p.join('lib', 'main.dart'), 'void main() {}');
        write(p.join('lib', 'old', 'screen.dart'), '''
final a = A.logo;
const path = 'assets/icons/old.png';
''');

        final usages = scanFromMain();
        expect(usages.accessors, isNot(contains('logo')));
        expect(usages.strings, isNot(contains('assets/icons/old.png')));
        expect(usages.deadFiles, ['lib/old/screen.dart']);
      });

      test('starts from every file under lib that declares main', () {
        write(p.join('lib', 'main.dart'), 'void main() {}');
        write(p.join('lib', 'flavors', 'main_prod.dart'), '''
import '../prod_only.dart';

void main() {}
''');
        write(p.join('lib', 'prod_only.dart'), 'final a = A.prodLogo;');
        write(p.join('lib', 'old.dart'), 'final a = A.old;');

        final usages = scanUsages(
          root: root.path,
          directories: const <String>['lib'],
          skip: p.join('lib', 'gen', 'assets.gen.dart'),
          packageName: 'app',
        );
        expect(usages.accessors, contains('prodLogo'));
        expect(usages.deadFiles, ['lib/old.dart']);
      });

      test('counts every file of a package, which declares no main', () {
        write(p.join('lib', 'widget.dart'), 'final a = A.logo;');

        final usages = scanUsages(
          root: root.path,
          directories: const <String>['lib'],
          skip: p.join('lib', 'gen', 'assets.gen.dart'),
          packageName: 'app',
        );
        expect(usages.accessors, contains('logo'));
        expect(usages.deadFiles, isEmpty);
      });

      test('counts every file when a reached import is missing', () {
        write(p.join('lib', 'main.dart'), '''
import 'di.config.dart';

void main() {}
''');
        write(p.join('lib', 'screen.dart'), 'final a = A.logo;');

        final usages = scanFromMain();
        expect(usages.accessors, contains('logo'));
        expect(usages.deadFiles, isEmpty);
        expect(usages.missingFiles, ['lib/di.config.dart']);
      });

      test('stops a .. too many at the root of lib, as Dart does', () {
        write(p.join('lib', 'main.dart'), '''
import 'gen/assets.gen.dart';
import '../app/home.dart';

void main() {}
''');
        write(p.join('lib', 'gen', 'assets.gen.dart'), 'class Assets {}');
        write(p.join('lib', 'app', 'home.dart'), 'final a = A.logo;');

        final usages = scanFromMain();
        expect(usages.accessors, contains('logo'));
        expect(usages.deadFiles, isEmpty);
        expect(usages.missingFiles, isEmpty);
      });

      test('counts every file when an entry point is not scanned', () {
        write(p.join('lib', 'src', 'home.dart'), 'final a = A.logo;');

        final usages = scanUsages(
          root: root.path,
          directories: const <String>['lib/src'],
          skip: p.join('lib', 'gen', 'assets.gen.dart'),
          packageName: 'app',
          entryPoints: const <String>['lib/main.dart'],
        );
        expect(usages.accessors, contains('logo'));
        expect(usages.missingFiles, ['lib/main.dart']);
      });

      test('counts the files outside lib and what they import', () {
        write(p.join('lib', 'main.dart'), 'void main() {}');
        write(p.join('lib', 'tested.dart'), 'final a = A.logo;');
        write(p.join('test', 'tested_test.dart'), '''
import 'package:app/tested.dart';

final b = A.icon;
''');

        final usages = scanFromMain();
        expect(usages.accessors, containsAll(<String>['logo', 'icon']));
        expect(usages.deadFiles, isEmpty);
      });
    });
  });

  group('configReferences', () {
    test('keeps the references of the tooling', () {
      final references = configReferences('''
name: app
flutter_launcher_icons:
  image_path: "assets/icons/app_icon.png"
flutter_native_splash:
  image: assets/images/splash_logo.png
''');

      expect(references, containsAll(<String>[
        'assets/icons/app_icon.png',
        'assets/images/splash_logo.png',
      ]));
    });

    test('leaves out the declared asset directories of a pubspec', () {
      final references = configReferences('''
name: app
flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/icons/
  fonts:
    - family: Roboto
      fonts:
        - asset: assets/fonts/Roboto-Regular.ttf
''', skipDeclaredAssets: true);

      expect(references, isNot(contains('assets/images/')));
      expect(references, contains('assets/fonts/Roboto-Regular.ttf'));
    });

    test('reads a config of the tooling that lives in its own file', () {
      final references = configReferences('''
flutter_native_splash:
  image: assets/images/splash_logo.png
  image_dark: assets/images/splash_logo.png
''');

      expect(references, contains('assets/images/splash_logo.png'));
    });

    test('reads every document of a multi-document file', () {
      final references = configReferences('''
kind: Service
---
icon: assets/icons/app_icon.png
''');

      expect(references, contains('assets/icons/app_icon.png'));
    });
  });
}
