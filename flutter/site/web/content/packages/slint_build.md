Shared plumbing for the repo's native-assets hooks: every `hook/build.dart`
drives cargo through this package instead of shelling out itself.

## API

- `runCargoBuild(...)` — build one crate for the hook's target and copy the
  artifact into the hook output directory. Parameters cover the crate name
  and manifest, the artifact kind (`cdylib` default, `staticlib` for the AOT
  link-hook path), extra env (e.g. `RUSTFLAGS=--print=native-static-libs`),
  and source dirs registered as hook dependencies. Returns the bundled
  artifact URI plus cargo's combined output — the AOT build hook parses
  rustc's `native-static-libs:` note out of it.
- `buildCargoCrate(...)` — the one-call convenience for FFI packages
  (`slint_interpreter`, `slint_skia`): `runCargoBuild` plus emitting the
  cdylib as a `DynamicLoadingBundled` code asset.
- Target-triple mapping (`rustTriple`) and cross-compile env for Android
  NDK / iOS / macOS. Cargo gets `CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER`
  (uppercased); the `cc` crate gets `CC_aarch64_linux_android` /
  `AR_aarch64_linux_android` (same underscores, original case).

## The staged Cargo workspace

The Rust crates inherit their dependencies from a Cargo workspace
(`workspace = true`) and reach each other by relative path
(`../../slint/rust`). From pub.dev, though, a package sits in the pub cache
as `slint-0.0.1/`, with no workspace above it and no sibling called `slint`.
So every build goes through a workspace this package stages next to the
package config, in `.dart_tool/slint_cargo/`:

- a link `packages/<name>` to each slint_dart package root the config lists;
- a generated `Cargo.toml` (marked GENERATED) listing their crates, with the
  pinned Slint version and the shared lint levels;
- the checkout's `Cargo.lock` as a seed, when there is one; a pub consumer
  resolves afresh.

`runCargoBuild` builds a package's `rust/` crate there by default, and the
`slint-introspect` tool and the generated AOT crate go through it too, so
`target/` and `Cargo.lock` never land in the pub cache.
`stageCargoWorkspace(packageConfig)` and `stagedCargoManifest(packageConfig,
package)` expose it.

The package also carries `slint-dart-interpreter` (`interpreter/`), the
crate that wraps `slint-interpreter` for the interpreter, testing and Skia
FFI crates. It lives here because `slint_build` is the one package all three
depend on, and a crate can only reach crates of packages its Dart package
depends on.

## The worker

Cargo runs inside a `bazel_worker` persistent worker
(`bin/cargo_worker.dart`), so repeated hook invocations reuse one process.
The request names the crate, manifest, triple, cargo profile, artifact kind,
and env; the response carries the artifact path and the full cargo output.

The cargo profile defaults to `release` (debug Slint rendering is unusably
slow) and is switched per package via pubspec user-defines — see the root
README's "Native assets build" section.
