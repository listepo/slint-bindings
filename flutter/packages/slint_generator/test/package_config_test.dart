import 'dart:io';

import 'package:build/build.dart';
import 'package:slint_generator/src/package_config.dart';
import 'package:test/test.dart';

/// The builder decides which backends a wrapper may default to from this. A
/// dev dependency leaking through would generate an import that resolves in
/// tests but breaks the app build, so the regular/dev split is load-bearing.
void main() {
  group('runtimeDependencies', () {
    test('returns the regular dependencies', () {
      final deps = runtimeDependencies('''
name: todo_example
dependencies:
  flutter:
    sdk: flutter
  slint: ^0.0.1
  slint_interpreter: ^0.0.1
''');
      expect(deps, containsAll(['flutter', 'slint', 'slint_interpreter']));
    });

    test('ignores dev_dependencies', () {
      final deps = runtimeDependencies('''
name: todo_example
dependencies:
  slint: ^0.0.1
dev_dependencies:
  slint_compiler: ^0.0.1
''');
      expect(deps, contains('slint'));
      expect(deps, isNot(contains('slint_compiler')));
    });

    test('an empty pubspec has no dependencies', () {
      expect(runtimeDependencies('name: bare\nversion: 1.0.0\n'), isEmpty);
    });

    test('dependencies: with no entries is empty', () {
      expect(runtimeDependencies('name: bare\ndependencies:\n'), isEmpty);
    });

    test('is not fooled by the word appearing elsewhere', () {
      final deps = runtimeDependencies('''
name: todo_example
description: uses slint_compiler for the AOT path
dependencies:
  slint: ^0.0.1
''');
      expect(deps, isNot(contains('slint_compiler')));
    });
  });

  group('assetIdForAbsolutePath', () {
    test('maps a file in another package to its AssetId', () {
      final root = Directory.systemTemp.createTempSync('slint_pkgmap_');
      addTearDown(() => root.deleteSync(recursive: true));
      final sharedRoot = Directory('${root.path}/shared')..createSync();
      File('${sharedRoot.path}/ui/view.slint').createSync(recursive: true);
      final config = File('${root.path}/package_config.json')
        ..writeAsStringSync(
          '{"configVersion": 2, "packages": ['
          '{"name": "todo_shared", "rootUri": "shared/"}'
          ']}',
        );
      final id = assetIdForAbsolutePath(
        config.uri,
        '${sharedRoot.path}/ui/view.slint',
      );
      expect(id, AssetId('todo_shared', 'ui/view.slint'));
    });
  });
}
