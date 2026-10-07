import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:slint_build/slint_build.dart' show stagedCargoManifest;

import 'src/emitter.dart';
import 'src/introspect.dart';
import 'src/package_config.dart';

/// Entry point for build_runner (wired up in `build.yaml`): turns every
/// `ui/**.slint` into `lib/**.g.dart` of typed wrappers.
///
/// The `.slint` files live outside `lib/` so they are plainly not Dart
/// sources and never part of the package's public API; the generated Dart
/// goes under `lib/` because that is the only place app code can import it
/// from. `ui/` is a build_runner source only when the app's `build.yaml`
/// lists it (see `examples/todo/build.yaml`).
Builder slintBuilder(BuilderOptions options) => _SlintBuilder();

/// `ui/<stem>.slint` → `<stem>`; the builder only ever sees such inputs.
String slintStem(AssetId input) =>
    input.path.substring('ui/'.length, input.path.length - '.slint'.length);

class _SlintBuilder implements Builder {
  Uri? _introspectManifest;

  Uri _introspectManifestPath() => _introspectManifest ??= stagedCargoManifest(
    findPackageConfigFrom(Directory.current),
    'slint_generator',
  );

  @override
  final Map<String, List<String>> buildExtensions = const {
    '^ui/{{}}.slint': ['lib/{{}}.g.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final input = buildStep.inputId;
    final source = await buildStep.readAsString(input);

    // Which backends the wrapper can default to depends on what the package
    // actually depends on. Reading the pubspec through the build step keeps it
    // a tracked input, so adding a backend rebuilds the wrappers.
    final deps = runtimeDependencies(
      await buildStep.readAsString(AssetId(input.package, 'pubspec.yaml')),
    );

    // build_runner runs from the package root; the introspect tool builds in
    // the Cargo workspace staged for its package config (the isolate's own is
    // unavailable in the AOT-compiled build script).
    final schema = await introspectSlint(
      File(input.path).absolute.path,
      introspectManifest: _introspectManifestPath(),
    );

    // Imports and images, by path relative to the `.slint`, for the
    // interpreter: it compiles the embedded source, not the file.
    final mainDir = p.dirname(
      File(input.path).absolute.resolveSymbolicLinksSync(),
    );
    final packageRoot = Directory.current.resolveSymbolicLinksSync();
    final packageConfig = findPackageConfigFrom(Directory.current);
    final files = <String, List<int>>{};
    for (final path in schema.files) {
      final id = p.isWithin(packageRoot, path)
          ? AssetId(
              input.package,
              p.split(p.relative(path, from: packageRoot)).join('/'),
            )
          : null;
      final key = p.split(p.relative(path, from: mainDir)).join('/');
      if (id != null && await buildStep.canRead(id)) {
        files[key] = await buildStep.readAsBytes(id);
        continue;
      }
      final externalId = assetIdForAbsolutePath(packageConfig, path);
      if (externalId != null && await buildStep.canRead(externalId)) {
        files[key] = await buildStep.readAsBytes(externalId);
      } else {
        // Last resort: untracked read (e.g. a path outside the workspace).
        files[key] = File(path).readAsBytesSync();
      }
    }

    final stem = slintStem(input);
    await buildStep.writeAsString(
      AssetId(input.package, 'lib/$stem.g.dart'),
      generateWrapperLibrary(
        schema,
        sourceName: input.pathSegments.last,
        // The name `load` answers to; the wrapper never reads it.
        assetPath: input.path,
        slintSource: source,
        aotLibrary: deps.contains('slint_compiler')
            ? '${stem.split('/').last}.aot.g.dart'
            : null,
        interpreter: deps.contains('slint_interpreter'),
        slintFiles: files,
      ),
    );
  }
}
