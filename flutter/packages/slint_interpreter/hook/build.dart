import 'package:hooks/hooks.dart';
import 'package:slint_build/slint_build.dart';

void main(List<String> args) => build(args, (input, output) async {
  final config = findPackageConfig(input);
  // The interpreter is the debug-mode backend; release/profile builds
  // (linkingEnabled, in Flutter) ship the slint_compiler AOT dylib
  // instead — the two never share a build. An app without slint_compiler
  // has no AOT backend, so it keeps the interpreter in every mode rather
  // than shipping none.
  final appRoot = findBuildingPackageRoot(input, config);
  if (input.config.linkingEnabled &&
      packageDependsOn(appRoot, 'slint_compiler')) {
    return;
  }
  await buildCargoCrate(
    input,
    output,
    crateName: 'slint-interpreter-ffi',
    sourceDirs: [
      input.packageRoot.resolve('rust/'),
      packageRootFromConfig(config, 'slint').resolve('rust/'),
      packageRootFromConfig(config, 'slint_build').resolve('interpreter/'),
    ],
  );
});
