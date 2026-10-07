# Agent notes — `slint_build`

Shared plumbing for every `hook/build.dart` in the repo: cargo runs through
a `bazel_worker` persistent worker, in a Cargo workspace this package
stages, and the artifact becomes a code asset. It also carries
`slint-dart-interpreter`, the Rust crate three FFI crates share. Read the
root `AGENTS.md` first.

## What lives here

| Path | Role |
|---|---|
| `lib/src/cargo_builder.dart` | `runCargoBuild` (one crate → one artifact, `cdylib` or `staticlib`), `buildCargoCrate` (the one-call FFI-package form that also emits the `DynamicLoadingBundled` code asset), `rustTriple`, cross-compile env (Android NDK, iOS, macOS), `sourceDependencies`, `packageRootFromConfig`, `packageInConfig`. |
| `lib/src/cargo_workspace.dart` | `stageCargoWorkspace` / `stagedCargoManifest`: the workspace every crate builds in, `.dart_tool/slint_cargo/` next to the package config — a link per package root plus a generated manifest. `cargoCrates` (the members), `cargoWorkspaceShared` (pins and lints), `cargoLockSeed`. |
| `interpreter/` | `slint-dart-interpreter`: renderer-agnostic wrapper over upstream `slint-interpreter` — compile, instantiate, JSON value bridge, callbacks — and `elements.rs`, the accessibility-tree query. Used by `slint-interpreter-ffi`, `slint-testing-ffi` and `slint-skia-ffi`. |
| `bin/cargo_worker.dart` | The persistent worker. Request: crate, manifest, triple, profile, artifact kind, env. Response: artifact path plus cargo's full output. |

`test/` covers the cross-compile env keys, `sourceDependencies`,
`packageInConfig`, and a pub-cache layout that has to stage and resolve
(`cargo metadata`). The hooks are exercised end to end by `flutter test` in
`examples/todo` and `dart test` in `slint_testing`.

## Commands

```bash
mise exec -- dart test
mise exec -- dart analyze .
```

## Invariants

- **Cargo output is returned verbatim**, not just the exit code.
  `slint_compiler`'s build hook parses rustc's `native-static-libs:` note
  out of it to get the link line for the AOT relink. Don't filter or
  truncate the worker's stdout/stderr.
- **`packageRootFromConfig(packageConfig, name)` is how hooks find sibling
  packages** — through `.dart_tool/package_config.json`, because
  `Isolate.resolvePackageUri` is unavailable inside hooks and build_runner
  builders. It resolves the worker script (`bin/cargo_worker.dart`) too, so
  it works wherever the package is checked out, including under
  `packages/`.
- **Every crate builds in the staged workspace, not where it lies.** From
  pub.dev a package sits in the pub cache as `<name>-<version>/`, with no
  Cargo workspace above it, so `workspace = true` and `../../slint/rust`
  both fail there, and cargo would write `target/` and `Cargo.lock` into
  the cache. `stageCargoWorkspace` links `packages/<name>` to each package
  root the config lists, under a manifest it generates (GENERATED header);
  cargo walks paths lexically, so path deps and inheritance land inside it.
  `runCargoBuild` defaults to it; the introspect tool and the AOT crate's
  `slint-dart-core` path go through it. `cargo_workspace_test.dart` builds
  such a pub cache and runs `cargo metadata` on it.
- **A crate may path-depend only on crates of packages its Dart package
  depends on** — the staged workspace links only what the package config
  lists. That is why `slint-dart-interpreter` lives here: `slint_testing`
  and `slint_skia` do not depend on `slint_interpreter`, and every native
  package depends on `slint_build`.
- **`cargoWorkspaceShared` equals the root `Cargo.toml` from
  `[workspace.dependencies]` on**; a test compares them. Bump the Slint pin
  in both, and in `slint_compiler`'s `slintVersion`.
- **The staged `Cargo.lock` is seeded from the repo's** (`cargoLockSeed`,
  `slint_build/../../Cargo.lock` — present in a checkout or a git
  dependency) and seeded again whenever that changes (`Cargo.lock.seed`
  records the last seed). A pub consumer has none and resolves afresh.
- **Staging is safe to repeat and to race.** Hooks of several packages
  stage the same directory, possibly at once: files are rewritten only when
  their content differs, via a temp file and a rename; a link a concurrent
  hook created first is accepted.
- **Source dirs passed as `dependencies` are the hook's cache key.** A hook
  that forgets to list a crate its crate depends on (e.g. `slint`'s
  `rust/`) will not rebuild when that crate changes. The FFI hooks list
  every path dependency explicitly, by package-config root. `runCargoBuild` also registers the worker script
  (`bin/cargo_worker.dart`) itself, so edits to the worker rebuild.
- **The cargo profile defaults to `release`** (debug Slint rendering is
  unusably slow) and is switched per package via pubspec user-defines
  (`hooks.user_defines.<pkg>.profile`), read from the workspace root
  pubspec. User-defines are hook input, so changing them invalidates the
  cache correctly.
- **Cross-compile env keys: cargo uppercases, `cc` does not.**
  `CARGO_TARGET_<TRIPLE>_LINKER` uses the triple with `-`/`.` as `_` and
  UPPERCASE. `CC_<triple>` / `AR_<triple>` use the same underscore form but
  keep the target's own case (`CC_aarch64_linux_android`) — uppercasing
  them makes the `cc` crate miss both of its lookup forms and the NDK
  wrapper is never used.
- **Artifact copies, not symlinks.** The artifact is copied into the hook's
  output directory; Flutter bundles from there.

## Traps

- The worker script runs from source (`Process.start(dart, [...])`), so a
  syntax error in `bin/cargo_worker.dart` surfaces as a hook failure in
  whichever package builds first, not as an analyzer error here — run
  `dart analyze .` in this package before testing a hook change.
- A failing cargo build reports through the hook of the *consuming*
  package (`slint_interpreter`, `slint_testing`, the AOT app); read the
  cargo output the worker returned rather than re-running cargo by hand
  with guessed flags.
