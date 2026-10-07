import 'package:hooks/hooks.dart';
import 'package:slint_build/slint_build.dart';

void main(List<String> args) => build(args, (input, output) async {
  final config = findPackageConfig(input);
  await buildCargoCrate(
    input,
    output,
    crateName: 'slint-skia-ffi',
    sourceDirs: [
      input.packageRoot.resolve('rust/'),
      packageRootFromConfig(config, 'slint').resolve('rust/'),
      packageRootFromConfig(config, 'slint_build').resolve('interpreter/'),
    ],
  );
});
