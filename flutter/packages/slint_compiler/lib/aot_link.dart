import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:record_use/record_use.dart';

import 'src/generator.dart' show aotLibraryName, aotLinkManifestName;

/// App link hook: links the final `slint-dart-aot` dylib from the staticlib
/// the build hook (`aot_build.dart`) routed here, keeping only the components
/// the app's Dart code actually uses.
///
/// Liveness comes from `@RecordUse()` on each component's generated `_new`
/// extern: the AOT compiler records tear-offs that survive Dart tree-shaking,
/// and this hook drops the native code of every component without one. When
/// the toolchain provides no recordings ([LinkInput.recordedUses] is null),
/// every component is kept — the link then matches what a plain cdylib build
/// would have produced.
///
/// Wire it up as the app's `hook/link.dart`:
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:slint_compiler/aot_link.dart';
///
/// void main(List<String> args) => link(args, linkSlintAot);
/// ```
Future<void> linkSlintAot(LinkInput input, LinkOutputBuilder output) async {
  final staticLibs = [
    for (final a in input.assets.code)
      if (a.linkMode is StaticLinking && a.file != null) a,
  ];
  if (staticLibs.isEmpty) return; // nothing routed (e.g. debug build)
  if (staticLibs.length > 1) {
    throw StateError(
      'expected one routed slint staticlib, got '
      '${[for (final a in staticLibs) a.id]}',
    );
  }
  final staticLib = staticLibs.single;

  final manifest = jsonDecode(
    File.fromUri(staticLib.file!.resolve(aotLinkManifestName))
        .readAsStringSync(),
  ) as Map<String, Object?>;
  final components = (manifest['components'] as List)
      .cast<Map<String, Object?>>();
  final assetIds = (manifest['assetIds'] as List).cast<String>();
  final sharedSymbols = (manifest['sharedSymbols'] as List).cast<String>();
  final linkFlags = (manifest['linkFlags'] as List).cast<String>();

  final used = usedComponentNames(input.recordedUses, components);
  final dropped = [
    for (final c in components)
      if (!used.contains(c['name'])) c['name'] as String,
  ];
  stderr.writeln(
    'slint_aot link: keeping ${used.length}/${components.length} components'
    '${dropped.isEmpty ? '' : ', dropping $dropped'}'
    '${input.recordedUses == null ? ' (no recorded usages from toolchain)' : ''}',
  );

  final keepSymbols = [
    ...sharedSymbols,
    for (final c in components)
      if (used.contains(c['name'])) ...(c['symbols'] as List).cast<String>(),
  ];
  final flags = partitionLinkFlags(linkFlags);
  final os = input.config.code.targetOS;

  await CLinker.library(
    name: aotLibraryName,
    sources: [staticLib.file!.toFilePath()],
    // RunCBuilder only emits `-framework` flags for Language.objectiveC
    // (documented on CTool.frameworks); it changes nothing else about a
    // pure link step, and without it the rustc-reported frameworks are
    // silently dropped — undefined CoreText/CoreFoundation symbols.
    language: Language.objectiveC,
    frameworks: flags.frameworks,
    libraries: flags.libraries,
    flags: flags.other,
    linkerOptions: LinkerOptions.treeshake(
      symbolsToKeep: keepSymbols,
      // ld's -x drops local symbols — the moral equivalent of cargo's
      // strip = "symbols" on the old cdylib path (2 MB per arch on the
      // example). Not a flag MSVC's LINK.exe knows.
      flags: [if (os != OS.windows) '-x'],
    ),
  ).run(input: input, output: output);

  // CLinker linked one dylib; every .slint file's asset id points at it.
  final libUri = input.outputDirectory.resolve(
    os.libraryFileName(aotLibraryName, DynamicLoadingBundled()),
  );
  for (final id in assetIds) {
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: id,
        linkMode: DynamicLoadingBundled(),
        file: libUri,
      ),
    );
  }
  output.dependencies.add(staticLib.file!.resolve(aotLinkManifestName));
}

/// Names of the components to keep, per the recorded usages.
///
/// Null [recordings] (the toolchain recorded nothing) keeps everything. So
/// does a recording that references none of the generated `_new` externs:
/// an app that uses no component at all would not depend on this package, so
/// that pattern means the recording missed the FFI tear-offs — dropping every
/// component on that evidence would break the app.
Set<String> usedComponentNames(
  Recordings? recordings,
  List<Map<String, Object?>> components,
) {
  final all = {for (final c in components) c['name'] as String};
  if (recordings == null) return all;
  final referenced = {
    for (final d in recordings.calls.keys) '${d.library.uri}#${d.name}',
  };
  final used = {
    for (final c in components)
      if (referenced.contains('${c['library']}#${c['newExtern']}'))
        c['name'] as String,
  };
  return used.isEmpty ? all : used;
}

/// Split of rustc's `native-static-libs` line for [CLinker]'s parameters.
typedef LinkFlagGroups = ({
  List<String> frameworks,
  List<String> libraries,
  List<String> other,
});

/// Splits a rustc `native-static-libs:` flag list into `-framework` names,
/// `-l` library names, and everything else (passed to the driver verbatim).
/// Order and duplication are preserved — rustc says both can matter.
LinkFlagGroups partitionLinkFlags(List<String> flags) {
  final frameworks = <String>[];
  final libraries = <String>[];
  final other = <String>[];
  for (var i = 0; i < flags.length; i++) {
    final f = flags[i];
    if (f == '-framework' && i + 1 < flags.length) {
      frameworks.add(flags[++i]);
    } else if (f.startsWith('-l') && f.length > 2) {
      libraries.add(f.substring(2));
    } else {
      other.add(f);
    }
  }
  return (frameworks: frameworks, libraries: libraries, other: other);
}
