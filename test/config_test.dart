import 'package:appcraft_unused_assets/appcraft_unused_assets.dart';
import 'package:test/test.dart';

const String _pubspec = '''
name: app
flutter_gen:
  output: lib/resources/
''';

String _build(String builder, String options) => '''
targets:
  \$default:
    builders:
      $builder:
        options:
$options
''';

void main() {
  group('generated', () {
    test('defaults when flutter_gen is not configured', () {
      expect(
        UnusedAssetsConfig.fromPubspec('name: app').generated,
        UnusedAssetsConfig.defaultGenerated,
      );
    });

    test('follows the output of the flutter_gen section', () {
      expect(
        UnusedAssetsConfig.fromPubspec(_pubspec).generated,
        'lib/resources/assets.gen.dart',
      );
    });

    test('follows the output of the builder in build.yaml first', () {
      for (final builder in ['flutter_gen_runner', 'flutter_gen']) {
        final config = UnusedAssetsConfig.fromPubspec(
          _pubspec,
          build: _build(builder, '          output: lib/gen_build/'),
        );

        expect(config.generated, 'lib/gen_build/assets.gen.dart');
      }
    });

    test('keeps the pubspec output when the builder sets none', () {
      final config = UnusedAssetsConfig.fromPubspec(
        _pubspec,
        build: _build('flutter_gen_runner', '          line_length: 120'),
      );

      expect(config.generated, 'lib/resources/assets.gen.dart');
    });

    test('reads the builder under every key build_runner accepts', () {
      for (final builder in [
        'flutter_gen_runner:flutter_gen_runner',
        'flutter_gen_runner|flutter_gen_runner',
      ]) {
        final config = UnusedAssetsConfig.fromPubspec(
          _pubspec,
          build: _build(builder, '          output: lib/gen_build/'),
        );

        expect(config.generated, 'lib/gen_build/assets.gen.dart');
      }
    });

    test('reads the default target under the name of the package', () {
      final config = UnusedAssetsConfig.fromPubspec(
        _pubspec,
        build: _build('flutter_gen_runner', '          output: lib/gen_build/')
            .replaceFirst(r'$default', 'app'),
      );

      expect(config.generated, 'lib/gen_build/assets.gen.dart');
    });

    test('takes global and dev options over the target options', () {
      final config = UnusedAssetsConfig.fromPubspec(_pubspec, build: '''
targets:
  \$default:
    builders:
      flutter_gen_runner:
        options:
          output: lib/target/
        dev_options:
          output: lib/target_dev/
global_options:
  flutter_gen_runner:
    options:
      output: lib/global/
''');

      expect(config.generated, 'lib/global/assets.gen.dart');
    });

    test('ignores the options of another builder', () {
      final config = UnusedAssetsConfig.fromPubspec(
        'name: app',
        build: _build('json_serializable', '          output: lib/json/'),
      );

      expect(config.generated, UnusedAssetsConfig.defaultGenerated);
    });

    test('prefers its own setting to any flutter_gen option', () {
      final config = UnusedAssetsConfig.fromPubspec(
        '$_pubspec\nappcraft_unused_assets:\n  generated: lib/a.gen.dart\n',
        build: _build('flutter_gen_runner', '          output: lib/b/'),
      );

      expect(config.generated, 'lib/a.gen.dart');
    });
  });

  test('takes an empty entry_points for none', () {
    final config = UnusedAssetsConfig.fromPubspec('''
name: app
appcraft_unused_assets:
  entry_points: []
''');

    expect(config.entryPoints, isNull);
  });
}
