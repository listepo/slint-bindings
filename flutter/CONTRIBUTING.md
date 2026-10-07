# Contributing

## Setup

- Flutter and Dart through [mise](https://mise.jdx.dev): `mise install` reads
  `mise.toml`. Every Dart/Flutter command below is `mise exec -- ...`.
- Rust through rustup, plus `cargo install cbindgen` (only for C ABI changes).
- A C toolchain (Xcode command line tools / NDK) for the app link step.

```bash
mise exec -- dart pub get        # resolves the whole workspace, melos included
```

## Repo shape

```
pubspec.yaml     pub workspace + melos config (`melos:` key)
Cargo.toml       Cargo workspace: every crate under packages/*/rust (and slint_build/interpreter)
packages/        the Dart packages, each with its Rust crate(s) inside
examples/        apps consuming the packages through the workspace
```

The root `README.md` describes each package. Full package/example docs live
under `site/content/` (`just docs-serve`). Package and example `README.md`
files are short pub.dev overviews. Each package also has an `AGENTS.md`
(invariants and traps, for humans and AI agents alike).

## Everyday commands

The short form is `just` (installed by mise): `just` lists the recipes,
`just check` runs what CI runs, `just bindings slint_testing` regenerates a
package's FFI bindings. `examples/todo/justfile` has the release builds and
the tree-shaking check (`just build-macos`, then `just verify-treeshake`);
`examples/todo_skia/justfile` the two things that run locally there.

Underneath, melos is a root dev dependency; run it with `dart run`:

```bash
mise exec -- dart run melos run analyze        # dart analyze, per package
mise exec -- dart run melos run test           # Dart packages, then Flutter packages and examples/todo
mise exec -- dart run melos run codegen        # ui/*.slint → lib/*.g.dart in the examples
mise exec -- dart run melos run rust:clippy    # every crate except slint-skia-ffi
mise exec -- dart run melos run rust:test      # cargo test, same exclusion
mise exec -- dart run melos run check          # everything CI runs
mise exec -- dart run melos list               # what's in the workspace
```

`melos run` with no script name lists the scripts and their descriptions.
Or go direct — `cd packages/<pkg> && mise exec -- dart test`, `cd examples/todo
&& mise exec -- flutter test`; see `AGENTS.md` for the full list.

First runs are slow: `flutter test` and `slint_testing`'s `dart test` build
their Rust crates through the native-assets hooks (release profile, minutes).
Nothing needs a manual `cargo build`.

## What default CI skips (Skia)

`slint_skia`'s crate pulls in all of Skia (10+ GB of artifacts). Default CI
(`melos run check`, `just check`) excludes `slint-skia-ffi` from
`cargo clippy` / `cargo test` and `examples/todo_skia` from `flutter test`.
The `skia-*` jobs in `.github/workflows/ci.yml` compile it instead, one per
platform family (`skia-apple`, `skia-linux`, `skia-android`, `skia-windows`):
clippy and the crate's GPU test (a frame rendered into the platform's texture
and read back) where the runner can run them, and a debug build of
`examples/todo_skia`, which compiles the `slint_skia` plugin too. They are
the only place the GPU path is built and checked; no local check builds it.

For `todo_skia` locally, `dart run build_runner build` and `dart analyze .`
are the everyday checks. `flutter run`, `flutter build`, and `flutter test`
there compile Skia through `slint_skia`'s hook — optional, slow, and not part
of the default check.

## Dead code and size

`dart analyze` already flags unused locals, fields, and imports. For
anything wider:

```bash
cargo install cargo-machete cargo-bloat
mise exec -- dart pub global activate dart_code_linter
mise exec -- dart run melos run deps:unused    # cargo machete: unused Rust dependencies
mise exec -- dart run melos run dart:unused    # dart_code_linter check-unused-code, per package
```

`dart:unused` reports the builders and hook entry points (`slintBuilder`,
`buildSlintAot`, ...) as unused — they are reached through `build.yaml` and
the apps' `hook/*.dart`, not by Dart imports. `cargo machete` lists
`slint-skia-ffi`'s Skia dependencies: the skeleton does not reference them
yet (see its `AGENTS.md`).

Release size is the AOT dylib; `site/content/packages/slint_compiler.md` has
the measured breakdown ("Where the bytes go") and the `cargo bloat` recipe.

## Before opening a PR

1. `mise exec -- dart run melos run check` is green.
2. A release build of the example still tree-shakes when the change touches
   codegen or hooks:
   `cd examples/todo && FLUTTER_RECORD_USE=true mise exec -- flutter build macos --release`
   (see `packages/slint_compiler/AGENTS.md` for what to verify in the bundle).
3. Generated files (`*.g.dart`, `*.aot.g.dart`, `bindings.g.dart`,
   `rust/include/*.h`) are regenerated, not hand-edited, and committed.
4. Docs in `site/content/` (and the short package/example README overview, if
   the blurb changed) are updated in the same change; a new invariant lands in
   that package's `AGENTS.md`.

Commit messages follow conventional-commit style (`feat:`, `fix:`, `test:`,
`docs:`, `refactor:`), imperative subject, body explaining the why. The
human is the only author: no `Co-Authored-By` trailer, "Generated with …"
line or AI agent as author on a commit, merge or PR, whatever a tool
defaults to.

## Adding a package

1. Create it under `packages/<name>/` with `publish_to: none` and
   `resolution: workspace`.
2. Add `packages/<name>` to the root `pubspec.yaml` `workspace:` list; a
   Rust crate goes into the root `Cargo.toml` `members` with
   `[lints] workspace = true` in its own `Cargo.toml`.
3. Write its short `README.md`, full docs under `site/content/packages/`, and
   `AGENTS.md`; add a row to the root README's
   layout table.
4. If it ships a native library: a `hook/build.dart` through `slint_build`,
   `ffigen.yaml` + `rust/cbindgen.toml`, and the generated bindings committed.

## Publishing to pub.dev

Packages under `packages/` share one version and publish from git tags `vX.Y.Z`
(see `.github/workflows/publish.yml`). Tag pattern on pub.dev: `v{{version}}`.

### First time (manual)

pub.dev allows automated publishing only **after** the package name exists.
Do this once per package, from a clean git tree, logged in as the pub.dev account:

```bash
cd /path/to/slint_dart
mise exec -- dart pub get
mise exec -- dart pub login   # opens browser; use the same Google account as pub.dev
```

Publish in dependency order (hosted deps must already be on pub.dev):

```bash
mise exec -- dart pub publish -C packages/slint
mise exec -- dart pub publish -C packages/slint_build
mise exec -- dart pub publish -C packages/slint_generator
mise exec -- dart pub publish -C packages/slint_testing
mise exec -- dart pub publish -C packages/slint_compiler
mise exec -- dart pub publish -C packages/slint_interpreter
mise exec -- dart pub publish -C packages/slint_skia
mise exec -- dart pub publish -C packages/slint_patrol
```

Dry-run without uploading: add `--dry-run` to any of those commands.

Then on each package page → **Admin** → **Automated publishing**:

1. Enable publishing from GitHub Actions
2. Repository: `listepo/slint_dart`
3. Tag pattern: `v{{version}}`
4. Require environment: `pub.dev` (create that environment in the GitHub repo settings)

### Later releases (from CI)

1. Bump `version:` (and changelog). While the packages are on `0.0.x`, bump
   **all of them together**, along with every `^0.0.x` constraint between
   them and in `examples/`: a caret on `0.0.x` admits that one patch only, so
   `slint: ^0.0.1` rejects `slint 0.0.2` and the workspace stops resolving.
   From `0.1.0` on, `^0.1.0` admits patches and a single package can go alone.
2. Merge to `main`.
3. Tag with the **new** version: `git tag v0.0.2 && git push origin v0.0.2`
4. The workflow publishes packages whose pubspec version equals the tag and is not already on pub.dev; unchanged packages are skipped.
