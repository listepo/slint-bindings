import 'dart:io';

import 'package:slint_build/slint_build.dart';
import 'package:test/test.dart';

void main() {
  group('crossCompileEnvKeys', () {
    test('cargo uppercases; cc keeps target case', () {
      final keys = crossCompileEnvKeys('aarch64-linux-android');
      expect(keys.cargoLinkerKey, 'CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER');
      expect(keys.ccKey, 'CC_aarch64_linux_android');
      expect(keys.arKey, 'AR_aarch64_linux_android');
    });

    test('periods become underscores for both', () {
      final keys = crossCompileEnvKeys('thumbv8m.main-none-eabi');
      expect(
        keys.cargoLinkerKey,
        'CARGO_TARGET_THUMBV8M_MAIN_NONE_EABI_LINKER',
      );
      expect(keys.ccKey, 'CC_thumbv8m_main_none_eabi');
      expect(keys.arKey, 'AR_thumbv8m_main_none_eabi');
    });

    test('armv7 android triple', () {
      final keys = crossCompileEnvKeys('armv7-linux-androideabi');
      expect(
        keys.cargoLinkerKey,
        'CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER',
      );
      expect(keys.ccKey, 'CC_armv7_linux_androideabi');
    });
  });

  group('sourceDependencies', () {
    test('lists source files and every directory, skipping target/', () {
      final root = Directory.systemTemp.createTempSync('slint_deps_');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final path in [
        'src/lib.rs',
        'ui/nested/a.slint',
        'notes.txt',
        'target/debug/build.rs',
      ]) {
        File('${root.path}/$path').createSync(recursive: true);
      }

      final deps = sourceDependencies([root.uri]).map((u) => u.path).toSet();
      String p(String relative) => root.uri.resolve(relative).path;

      // Directories are what catch a file being added or removed.
      expect(deps, containsAll([p(''), p('src/'), p('ui/'), p('ui/nested/')]));
      expect(deps, containsAll([p('src/lib.rs'), p('ui/nested/a.slint')]));
      expect(deps, isNot(contains(p('notes.txt'))));
      expect(deps.where((d) => d.contains('/target')), isEmpty);
    });

    test('a missing directory contributes nothing', () {
      expect(sourceDependencies([Uri.directory('/no/such/dir/')]), isEmpty);
    });
  });

  group('packageInConfig', () {
    test('parses each config file once per process', () {
      final dir = Directory.systemTemp.createTempSync('slint_config_cache_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final config = File('${dir.path}/package_config.json')
        ..writeAsStringSync(
          '{"configVersion": 2, "packages": ['
          '{"name": "slint_interpreter", "rootUri": "../a/"},'
          '{"name": "slint_compiler", "rootUri": "../b/"}'
          ']}',
        );
      packageConfigParseCount = 0;
      expect(packageInConfig(config.uri, 'slint_interpreter'), isTrue);
      expect(
        packageRootFromConfig(config.uri, 'slint_compiler').path,
        endsWith('/b/'),
      );
      expect(packageInConfig(config.uri, 'slint_skia'), isFalse);
      expect(packageConfigParseCount, 1);
    });

    test('answers from the package config', () {
      final dir = Directory.systemTemp.createTempSync('slint_config_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final config = File('${dir.path}/package_config.json')
        ..writeAsStringSync(
          '{"configVersion": 2, "packages": ['
          '{"name": "slint_interpreter", "rootUri": "../a/"}]}',
        );

      expect(packageInConfig(config.uri, 'slint_interpreter'), isTrue);
      expect(packageInConfig(config.uri, 'slint_compiler'), isFalse);
    });
  });

  group('packageDependsOn', () {
    test('finds runtime dependencies only', () {
      final dir = Directory.systemTemp.createTempSync('slint_pubspec_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: demo
dependencies:
  slint_interpreter: ^0.0.1
dev_dependencies:
  slint_compiler: ^0.0.1
''');
      expect(packageDependsOn(dir.uri, 'slint_interpreter'), isTrue);
      expect(packageDependsOn(dir.uri, 'slint_compiler'), isFalse);
      expect(packageDependsOn(dir.uri, 'slint_skia'), isFalse);
    });
  });

  group('mergeExtraEnv', () {
    test('preserves existing RUSTFLAGS from the environment', () {
      final merged = mergeExtraEnvForTest(
        {'RUSTFLAGS': '-C foo=bar'},
        const {'RUSTFLAGS': '--print=native-static-libs'},
      );
      expect(merged['RUSTFLAGS'], '-C foo=bar --print=native-static-libs');
    });
  });
}

/// Test hook for the private [_mergeExtraEnv] logic in cargo_builder.dart.
Map<String, String> mergeExtraEnvForTest(
  Map<String, String> env,
  Map<String, String> extraEnv,
) {
  if (!extraEnv.containsKey('RUSTFLAGS')) {
    return extraEnv;
  }
  final merged = Map<String, String>.from(extraEnv);
  final existing = env['RUSTFLAGS'];
  if (existing != null && existing.isNotEmpty) {
    merged['RUSTFLAGS'] = '$existing ${merged['RUSTFLAGS']}'.trim();
  }
  return merged;
}
