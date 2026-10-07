/// Bazel persistent worker that runs cargo builds for the slint_dart hooks.
///
/// Spawned by `buildCargoCrate` with `--persistent_worker` (Bazel worker
/// protocol over stdio). Without the flag it runs the request given on the
/// command line once — handy for debugging:
///
///     dart run slint_build:cargo_worker '<request json>'
library;

import 'dart:convert';
import 'dart:io';

import 'package:bazel_worker/bazel_worker.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--persistent_worker')) {
    await CargoWorker().run();
  } else {
    final response = await runCargoRequest(args);
    stderr.writeln(response.output);
    exit(response.exitCode);
  }
}

class CargoWorker extends AsyncWorkerLoop {
  @override
  Future<WorkResponse> performRequest(WorkRequest request) =>
      runCargoRequest(request.arguments);
}

Future<WorkResponse> runCargoRequest(List<String> args) async {
  try {
    if (args.length != 1) {
      return WorkResponse(
        exitCode: 64,
        output: 'expected exactly one JSON request argument, got: $args',
      );
    }
    final spec = jsonDecode(args.single) as Map<String, Object?>;
    final manifestPath = spec['manifestPath'] as String;
    final crateName = spec['crateName'] as String;
    final targetTriple = spec['targetTriple'] as String;
    final cargoProfile = spec['cargoProfile'] as String;
    final artifactKind = spec['artifactKind'] as String? ?? 'cdylib';
    final extraEnv = (spec['extraEnv'] as Map<String, Object?>? ?? {}).map(
      (k, v) => MapEntry(k, v as String),
    );

    final cargo = Platform.environment['CARGO'] ?? 'cargo';
    // Merge — Process.run's environment: replaces the whole env, so a
    // bare extraEnv would drop PATH and cargo would not resolve.
    final environment = Map<String, String>.of(Platform.environment)
      ..addAll(extraEnv);
    final result = await Process.run(cargo, [
      'build',
      '--manifest-path',
      manifestPath,
      '-p',
      crateName,
      '--target',
      targetTriple,
      '--profile',
      cargoProfile,
      '--message-format=json-render-diagnostics',
    ], environment: environment);

    final log = StringBuffer(result.stderr as String);
    if (result.exitCode != 0) {
      if ((result.stderr as String).contains('may not be installed')) {
        log.writeln('\nhint: rustup target add $targetTriple');
      }
      return WorkResponse(exitCode: result.exitCode, output: log.toString());
    }

    final artifact = _findArtifact(
      result.stdout as String,
      crateName,
      artifactKind,
    );
    if (artifact == null) {
      return WorkResponse(
        exitCode: 1,
        output:
            '$log\nno $artifactKind artifact reported by cargo for $crateName',
      );
    }
    log.writeln('ARTIFACT:$artifact');
    return WorkResponse(exitCode: 0, output: log.toString());
  } on ProcessException catch (e) {
    return WorkResponse(
      exitCode: 66,
      output:
          'failed to run ${e.executable}: ${e.message}\n'
          'hint: install Rust via rustup (https://rustup.rs) and make sure '
          'cargo is on PATH.',
    );
  } catch (e, st) {
    return WorkResponse(exitCode: 65, output: 'cargo worker error: $e\n$st');
  }
}

String? _findArtifact(String cargoJsonOutput, String crateName, String kind) {
  final exts = kind == 'staticlib'
      ? const ['.a', '.lib']
      : const ['.dylib', '.so', '.dll'];
  final snake = crateName.replaceAll('-', '_');
  for (final line in const LineSplitter().convert(cargoJsonOutput)) {
    if (line.isEmpty || !line.startsWith('{')) continue;
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (message is! Map<String, Object?>) continue;
    if (message['reason'] != 'compiler-artifact') continue;
    final target = message['target'] as Map<String, Object?>?;
    final name = target?['name'] as String?;
    if (name != crateName && name != snake) continue;
    final filenames =
        (message['filenames'] as List?)?.cast<String>() ?? const [];
    for (final f in filenames) {
      if (exts.any(f.endsWith)) return f;
    }
  }
  return null;
}
