import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:slint_build/slint_build.dart' show stagedCargoManifest;

import 'schema.dart';

/// Runs the `slint-introspect` tool (cargo) on [slintPath] and returns the
/// typed public interface of its exported components.
///
/// [introspectManifest] is slint_generator's crate in the staged Cargo
/// workspace ([stagedCargoManifest]); when null it is staged from this
/// isolate's package config (works under `dart run`, not in AOT-compiled
/// contexts such as build hooks — those must pass it).
Future<SlintSchema> introspectSlint(
  String slintPath, {
  Uri? introspectManifest,
}) async {
  final manifest = introspectManifest ?? _defaultManifest();
  final result = await Process.run(Platform.environment['CARGO'] ?? 'cargo', [
    'run',
    '--quiet',
    '--manifest-path',
    manifest.toFilePath(),
    '--',
    slintPath,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'slint-introspect failed for $slintPath:\n${result.stdout}${result.stderr}',
    );
  }
  return SlintSchema.fromJson(
    jsonDecode(result.stdout as String) as Map<String, Object?>,
  );
}

Uri _defaultManifest() {
  final config = Isolate.packageConfigSync;
  if (config == null) {
    throw StateError('no package config; pass introspectManifest explicitly');
  }
  return stagedCargoManifest(config, 'slint_generator');
}
