# slint_build

Shared plumbing for native-assets hooks: every `hook/build.dart` drives cargo
through this package (persistent `bazel_worker`) instead of shelling out
itself. Used by the FFI packages and the AOT build/link hooks.

Crates build in a Cargo workspace this package stages next to the app's
package config (`.dart_tool/slint_cargo/`): a link to each slint_dart package
plus a generated manifest with the pinned Slint version. That is what lets
the crates build the same from the pub cache as from a checkout, where
`workspace = true` and `../../slint/rust` would otherwise have nothing to
resolve against. The package also carries `slint-dart-interpreter`
(`interpreter/`), the Rust crate the interpreter, testing and Skia FFI crates
share.

```yaml
dependencies:
  slint_build: ^0.0.1
```

**Full docs:** [slint_build package page](https://listepo.github.io/slint_dart/packages/slint_build/). Cargo profile defaults and user-defines are also covered in the
root README.
