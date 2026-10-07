import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:slint_build/slint_build.dart';
import 'package:slint_generator/slint_generator.dart' show introspectSlint;

import 'src/generator.dart';
import 'src/rust_glue.dart';

/// App build hook: AOT-compiles every `ui/**.slint` of the package into one
/// staticlib — slint-build codegen plus generated C ABI glue, no
/// slint-interpreter — and routes it to the app's link hook ([ToLinkHook]),
/// which links the final dylib keeping only the components the app uses (see
/// `aot_link.dart`). One code asset per `.slint` file, with id
/// `package:<app>/<path>.aot.g.dart` matching the wrappers the
/// `slint_compiler` builder generates.
///
/// Wire it up as the app's `hook/build.dart` (with `hook/link.dart` calling
/// `linkSlintAot`):
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:slint_compiler/aot_build.dart';
///
/// void main(List<String> args) => build(args, buildSlintAot);
/// ```
Future<void> buildSlintAot(BuildInput input, BuildOutputBuilder output) async {
  if (!input.config.buildCodeAssets) return;
  // The AOT dylib ships only in release/profile builds; debug builds (incl.
  // `flutter test`) use the slint_interpreter package. In Flutter,
  // linkingEnabled == true exactly for the non-debug (AOT) modes.
  if (!input.config.linkingEnabled) return;

  // `.slint` files live under `ui/`, not `lib/`: they are not Dart, and the
  // release bundle must not ship them — see `slint_generator`'s builder.
  final uiDir = Directory.fromUri(input.packageRoot.resolve('ui/'));
  final slintFiles = !uiDir.existsSync()
      ? <File>[]
      : (uiDir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((f) => f.path.endsWith('.slint'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)));
  if (slintFiles.isEmpty) return;

  final packageConfig = findPackageConfig(input);
  final compilerRoot = packageRootFromConfig(packageConfig, 'slint_compiler');
  final generatorRoot = packageRootFromConfig(packageConfig, 'slint_generator');
  final slintCoreCrate = packageRootFromConfig(
    packageConfig,
    'slint',
  ).resolve('rust/');
  // Cargo reaches the crates through the staged workspace, which works the
  // same from this repo and from the pub cache (see stageCargoWorkspace).
  final introspectManifest = stagedCargoManifest(
    packageConfig,
    'slint_generator',
  );
  final stagedCoreCrate = stagedCargoManifest(
    packageConfig,
    'slint',
  ).resolve('./');

  final files = <SlintAotFile>[];
  final assetNames = <String>[];
  final uiPath = uiDir.uri.toFilePath();
  for (final f in slintFiles) {
    final relative = f.path.substring(uiPath.length);
    final stemBase = relative.substring(0, relative.length - '.slint'.length);
    final stem = stemBase.replaceAll(Platform.pathSeparator, '_');
    // `a/b.slint` and `a_b.slint` map to the same module stem and would
    // silently overwrite each other's generated sources in the AOT crate.
    if (files.any((e) => e.stem == stem)) {
      throw StateError(
        'duplicate AOT module stem "$stem" from "$relative" — '
        'rename one of the .slint files',
      );
    }
    final schema = await introspectSlint(
      f.path,
      introspectManifest: introspectManifest,
    );
    files.add(SlintAotFile(stem: stem, path: f.absolute.path, schema: schema));
    assetNames.add(
      '$stemBase.aot.g.dart'.replaceAll(Platform.pathSeparator, '/'),
    );
  }

  final crateDir = Directory.fromUri(
    input.outputDirectoryShared.resolve('slint_aot/'),
  );
  emitAotCrate(
    crateDir,
    files: files,
    slintCoreCratePath: stagedCoreCrate.toFilePath(),
    // The staged workspace's lock: the tree the introspect tool was just
    // built with, seeded from the repo's when there is one.
    lockfile: File.fromUri(
      stageCargoWorkspace(packageConfig).resolve('Cargo.lock'),
    ),
  );

  final build = await runCargoBuild(
    input,
    output,
    crateName: 'slint-dart-aot',
    manifestPath: crateDir.uri.resolve('Cargo.toml'),
    artifactKind: 'staticlib',
    // Makes rustc print the `native-static-libs:` note — the exact linker
    // line the staticlib needs — which the link hook replays when it links
    // the final dylib.
    extraEnv: const {'RUSTFLAGS': '--print=native-static-libs'},
    sourceDirs: [
      input.packageRoot.resolve('ui/'),
      // Regenerate when the glue generator or the introspect tool change.
      compilerRoot.resolve('lib/'),
      generatorRoot.resolve('lib/'),
      generatorRoot.resolve('rust/'),
      // A path dependency of the generated crate.
      slintCoreCrate,
    ],
    // What the files import or reference from outside ui/ — a UI shared with
    // another package, say.
    extraDependencies: [
      for (final f in files)
        for (final dep in f.schema.files) Uri.file(dep),
    ],
  );

  final linkFlags = _persistedNativeLinkFlags(
    crateDir: crateDir,
    triple: rustTriple(input.config.code),
    cargoOutput: build.cargoOutput,
  );

  // Everything the link hook needs, written next to the routed staticlib.
  final manifest = {
    'assetIds': assetNames,
    'sharedSymbols': aotSharedSymbols,
    'linkFlags': linkFlags,
    'components': [
      for (var i = 0; i < files.length; i++)
        for (final c in files[i].schema.components)
          {
            'name': c.name,
            'library': 'package:${input.packageName}/${assetNames[i]}',
            'newExtern': aotNewExternName(c.name),
            'symbols': aotComponentSymbols(c.name),
          },
    ],
  };
  File.fromUri(input.outputDirectory.resolve(aotLinkManifestName))
      .writeAsStringSync(jsonEncode(manifest));

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: assetNames.first,
      linkMode: StaticLinking(),
      file: build.artifact,
    ),
    routing: ToLinkHook(input.packageName),
  );
}

/// The flag list from rustc's `native-static-libs:` note in [cargoOutput],
/// or null when the note is absent. Quoted segments (`"..."`, `'...'`,
/// with `\` escapes) stay one flag, so SDK paths containing spaces survive
/// the round trip through [_persistedNativeLinkFlags].
List<String>? nativeStaticLibsNote(String cargoOutput) {
  const marker = 'native-static-libs:';
  for (final line in cargoOutput.split('\n').reversed) {
    final i = line.indexOf(marker);
    if (i < 0) continue;
    final flags = line.substring(i + marker.length).trim();
    return flags.isEmpty ? const [] : splitLinkFlags(flags);
  }
  return null;
}

/// Splits a linker flag line on whitespace, keeping quoted segments whole:
/// `"..."` and `'...'` may contain spaces, a backslash escapes the next
/// character. The surrounding quotes are stripped; an unterminated quote
/// runs to the end of the line rather than dropping the flag.
List<String> splitLinkFlags(String line) {
  final flags = <String>[];
  final current = StringBuffer();
  var inFlag = false;
  var quote = '';
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quote.isNotEmpty) {
      if (ch == quote) {
        quote = '';
      } else if (ch == r'\' && i + 1 < line.length) {
        current.write(line[++i]);
      } else {
        current.write(ch);
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
      inFlag = true;
    } else if (ch == r'\' && i + 1 < line.length) {
      current.write(line[++i]);
      inFlag = true;
    } else if (_isFlagSpace(ch)) {
      if (inFlag) {
        flags.add(current.toString());
        current.clear();
        inFlag = false;
      }
    } else {
      current.write(ch);
      inFlag = true;
    }
  }
  if (inFlag) flags.add(current.toString());
  return flags;
}

bool _isFlagSpace(String ch) =>
    ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

/// Returns the linker flags for the staticlib, persisting them under
/// [crateDir] per [triple]: rustc prints the note only when it actually
/// reruns, so cached cargo builds fall back to the stored line.
List<String> _persistedNativeLinkFlags({
  required Directory crateDir,
  required String triple,
  required String cargoOutput,
}) {
  final store = File('${crateDir.path}/native-link-flags.$triple.txt');
  final fresh = nativeStaticLibsNote(cargoOutput);
  if (fresh != null) {
    // JSON round-trips flags containing spaces; joining on spaces would
    // corrupt them when the note is read back.
    store.writeAsStringSync(jsonEncode(fresh));
    return fresh;
  }
  if (store.existsSync()) {
    final stored = store.readAsStringSync().trim();
    if (stored.isEmpty) return const [];
    if (stored.startsWith('[')) {
      return (jsonDecode(stored) as List).cast<String>();
    }
    // Files written before the JSON format: plain space-joined flags.
    return stored.split(RegExp(r'\s+'));
  }
  throw StateError(
    'cargo reported no native-static-libs note and none is stored at '
    '${store.path}; delete ${crateDir.path}/target to force a rebuild',
  );
}
