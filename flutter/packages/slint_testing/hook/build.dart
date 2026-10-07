import 'package:hooks/hooks.dart';
import 'package:slint_build/slint_build.dart';

void main(List<String> args) => build(args, (input, output) async {
  // Test-only backend: `dart test`/`flutter test` are always debug, and a
  // release app has no reason to ship the testing platform.
  if (input.config.linkingEnabled) return;
  final config = findPackageConfig(input);
  await buildCargoCrate(
    input,
    output,
    crateName: 'slint-testing-ffi',
    sourceDirs: [
      input.packageRoot.resolve('rust/'),
      packageRootFromConfig(config, 'slint_build').resolve('interpreter/'),
    ],
  );
});
