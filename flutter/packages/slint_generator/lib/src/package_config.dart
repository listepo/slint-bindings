import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The regular (non-dev) dependencies declared in [pubspecYaml].
///
/// Codegen consults this to decide which backends a package can actually
/// import at runtime — a dev dependency would not survive into an app build.
Set<String> runtimeDependencies(String pubspecYaml) {
  final doc = loadYaml(pubspecYaml);
  final deps = doc is YamlMap ? doc['dependencies'] : null;
  return deps is YamlMap
      ? {for (final key in deps.keys) '$key'}
      : const <String>{};
}

/// Locates the `.dart_tool/package_config.json` governing [from], walking up
/// so that members of a pub workspace find the shared config at the workspace
/// root rather than expecting one in their own directory.
///
/// build_runner runs the build script from the package root, so builders can
/// call this with `Directory.current`; `Isolate.resolvePackageUriSync` is
/// unavailable there (the script is AOT-compiled).
Uri findPackageConfigFrom(Directory from) {
  var dir = from.absolute;
  while (true) {
    final candidate = File.fromUri(
      dir.uri.resolve('.dart_tool/package_config.json'),
    );
    if (candidate.existsSync()) {
      return candidate.uri;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'no .dart_tool/package_config.json found from ${from.path} upwards — '
        'run `dart pub get` first',
      );
    }
    dir = parent;
  }
}

/// Maps an on-disk [absolutePath] to a build_runner [AssetId] when it lives
/// inside a package from [packageConfig].
AssetId? assetIdForAbsolutePath(Uri packageConfig, String absolutePath) {
  final normalized = p.normalize(File(absolutePath).resolveSymbolicLinksSync());
  for (final entry in _readPackageConfig(packageConfig)) {
    final name = entry['name'] as String;
    final rootPath = p.normalize(
      File.fromUri(packageRootFromConfig(packageConfig, name))
          .resolveSymbolicLinksSync(),
    );
    if (!p.isWithin(rootPath, normalized)) {
      continue;
    }
    final relative = p.split(p.relative(normalized, from: rootPath)).join('/');
    return AssetId(name, relative);
  }
  return null;
}

Uri packageRootFromConfig(Uri packageConfig, String packageName) {
  final entry = _readPackageConfig(packageConfig).firstWhere(
    (pkg) => pkg['name'] == packageName,
    orElse: () => throw StateError(
      '$packageName not found in ${packageConfig.toFilePath()}',
    ),
  );
  var rootUri = entry['rootUri'] as String;
  if (!rootUri.endsWith('/')) rootUri = '$rootUri/';
  return packageConfig.resolve(rootUri);
}

List<Map<String, Object?>> _readPackageConfig(Uri packageConfig) {
  final json = jsonDecode(
    File.fromUri(packageConfig).readAsStringSync(),
  ) as Map<String, Object?>;
  return (json['packages'] as List).cast<Map<String, Object?>>();
}
