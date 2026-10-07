# slint_build example

A package that ships a Rust crate builds it from its native-assets build hook
through `slint_build`: cargo runs in a persistent `bazel_worker`, the target
triple and cross-compile environment come from the hook input, and the
resulting library is emitted as the package's code asset.

```dart
// hook/build.dart
import 'package:hooks/hooks.dart';
import 'package:slint_build/slint_build.dart';

void main(List<String> args) => build(args, (input, output) async {
      await buildCargoCrate(
        input,
        output,
        crateName: 'my-slint-ffi',                 // [package] name in rust/Cargo.toml
        assetName: 'src/bindings.g.dart',          // the Dart file whose @Native externs bind to it
        sourceDirs: [input.packageRoot.resolve('rust/')], // edits here rebuild
      );
    });
```

The Rust profile is a user-define in the app's pubspec:

```yaml
hooks:
  user_defines:
    my_package:
      profile: release   # or debug
```
