import 'dart:io';

import 'package:slint_compiler/slint_compiler.dart';
import 'package:slint_generator/slint_generator.dart';

/// Usage: `dart run slint_compiler ui/<name>.slint`
///
/// Writes both generated libraries into the package's `lib/`: the typed
/// wrapper `lib/<name>.g.dart` and the AOT backend `lib/<name>.aot.g.dart`.
/// The input must live under the package's `ui/` — the tree the app's build
/// hook compiles, and the path the wrapper's `load()` answers to — and the
/// AOT backend binds to the code asset `package:<package>/<name>.aot.g.dart`
/// built by that hook.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run slint_compiler ui/<name>.slint');
    exit(64);
  }
  final input = File(args[0]);
  if (!input.existsSync()) {
    stderr.writeln('not found: ${input.path}');
    exit(66);
  }

  // Locate the enclosing package: walk up from the input to pubspec.yaml.
  final sep = Platform.pathSeparator;
  var dir = input.absolute.parent;
  Directory? packageRoot;
  while (true) {
    if (File('${dir.path}${sep}pubspec.yaml').existsSync()) {
      packageRoot = dir;
      break;
    }
    if (dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  if (packageRoot == null) {
    stderr.writeln(
      '${input.path}: not inside a Dart package (no pubspec.yaml found)',
    );
    exit(64);
  }
  final pubspec = File('${packageRoot.path}${sep}pubspec.yaml')
      .readAsStringSync();
  final packageName = RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);
  if (packageName == null) {
    stderr.writeln('${packageRoot.path}${sep}pubspec.yaml: no `name:` entry');
    exit(64);
  }
  final uiDir = '${packageRoot.path}${sep}ui$sep';
  if (!input.absolute.path.startsWith(uiDir) ||
      !input.path.endsWith('.slint')) {
    stderr.writeln('${input.path}: input must be a .slint under $uiDir');
    exit(64);
  }
  // `ui/a/b.slint` → `a/b`: the same stem the build_runner builders use.
  final stem = input.absolute.path
      .substring(uiDir.length, input.absolute.path.length - '.slint'.length)
      .replaceAll(sep, '/');
  final libDir = '${packageRoot.path}${sep}lib$sep';
  final output = File('$libDir$stem.g.dart');
  final aotOutput = File('$libDir$stem.aot.g.dart');
  output.parent.createSync(recursive: true);

  final schema = await introspectSlint(input.absolute.path);
  final sourceName = input.uri.pathSegments.last;

  output.writeAsStringSync(
    generateWrapperLibrary(
      schema,
      sourceName: sourceName,
      slintSource: input.readAsStringSync(),
      assetPath: 'ui/$stem.slint',
      // The AOT backend is always written next to the wrapper here; the
      // interpreter is only a default when the package can import it.
      aotLibrary: aotOutput.uri.pathSegments.last,
      interpreter: runtimeDependencies(pubspec).contains('slint_interpreter'),
    ),
  );

  aotOutput.writeAsStringSync(
    generateDartFromSchema(
      schema,
      packageName: packageName,
      assetLibraryPath: '$stem.aot.g.dart',
      sourceName: sourceName,
    ),
  );
  stdout.writeln('generated ${output.path} and ${aotOutput.path}');
}
