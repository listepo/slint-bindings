# Agent notes — `slint_compiler`

The AOT backend: `.slint` compiled ahead of time by `slint-build` into the
app's own code asset, no interpreter at runtime. Read the root `AGENTS.md`
first — most of the tree-shaking and link invariants there are about this
package.

## What lives here

| Path | Role |
|---|---|
| `lib/src/generator.dart` | **The AOT ABI contract**: `aotComponentOps`, `aotSharedSymbols`, `aotComponentSymbols`, `aotNewExternName`, the manifest name. Emits `foo.aot.g.dart` (`@Native` externs + one `SlintCompilerFactory` per component). |
| `lib/src/rust_glue.dart` | Emits the Rust glue crate (Cargo.toml + JSON⇄typed C ABI) from the same contract. |
| `lib/src/runtime.dart` (`runtime.dart`) | Hand-written component, software render target, JSON marshalling, callback trampolines over that ABI. |
| `lib/aot_build.dart` | `buildSlintAot`: the app's build hook. Compiles `ui/**.slint` + glue into a *staticlib* through `slint_build`, writes `slint_aot_link.json`, routes to the link hook. Returns early unless `linkingEnabled`. |
| `lib/aot_link.dart` | `linkSlintAot`: the app's link hook. Relinks the staticlib with `CLinker`, keeping only components with a recorded use, strips, emits the code asset. |
| `lib/builder.dart`, `build.yaml` | build_runner builder `^ui/{{}}.slint` → `lib/{{}}.aot.g.dart`. |
| `bin/slint_compiler.dart` | One-off CLI: `dart run slint_compiler ui/todo.slint` writes both `.g.dart` files. |
| `test/generator_test.dart` | Asserts the manifest predicts exactly the symbols the glue exports. Keep it green. |
| `test/aot_link_test.dart` | Keep-all fallbacks and the `native-static-libs` note parsing. |

## Commands

```bash
mise exec -- dart test                  # unit tests, no cargo
mise exec -- dart analyze .
cd ../../examples/todo && FLUTTER_RECORD_USE=true mise exec -- flutter build macos --release   # the e2e check (minutes; background it)
```

Verify a release build the way the tests can't: the dylib
`slint_dart_aot.framework` in the app bundle must export
`slint_aot_todo_app_*` and no `slint_aot_unused_gadget_*` (`nm -gU`), and
the Dart snapshot (`App.framework/.../App`) must contain no `.slint` text
and no `SlintInterpreterFactory` (`grep -c -a`).

## Invariants

- **One source of truth for the ABI.** Dart codegen, Rust glue, build hook,
  and link hook all derive from `generator.dart`. Never hand-list a symbol
  in one of them.
- **Staticlib + relink, not cdylib.** The build hook must emit a staticlib
  with symbols intact so the link hook can `-u`/export-list tree-shake;
  stripping (`-S`, `-x`) happens in the link hook. Don't add
  `strip = "symbols"` to the generated `Cargo.toml`.
- **Keep-all fallbacks are deliberate.** No recordings (`recordedUses ==
  null`, a build without `FLUTTER_RECORD_USE=true`) or recordings that hit
  zero externs → keep every component. Dropping everything on that evidence
  would break the app.
- **`panic = "unwind"`** in the generated crate: every glue entry point is
  `catch_unwind`. `abort` turns Slint panics into process aborts.
- **The generated crate is seeded with the workspace `Cargo.lock`** when
  the build runs inside this repo (`emitAotCrate(lockfile:)`): the crate is
  its own `[workspace]`, so without a seed every machine resolves the
  dependency tree afresh. Cargo keeps whatever versions in the seed still
  satisfy the manifest, so the AOT build and the interpreter crates share a
  tree. A pub consumer has no seed and resolves as before.
- **`slintVersion` in `rust_glue.dart` must equal the root `Cargo.toml`
  `[workspace.dependencies]` pin.** The glue crate cannot inherit it (it is
  outside the workspace), so bump both; `test/slint_version_test.dart`
  fails until you do — e.g. on Dependabot's Slint PR, which bumps only the
  root file.
- **`opt-level = "z"` is rejected**: 2.7× slower full-frame renders for
  ~1 MB/arch. Size-tune with fat LTO + `codegen-units = 1` only.
- **`CLinker` needs `language: Language.objectiveC`** or it drops the
  `-framework` flags and the macOS link fails on CoreText/CoreFoundation.
- **The link line comes from rustc** (`RUSTFLAGS=--print=native-static-libs`)
  and is persisted as `native-link-flags.<triple>.txt` next to the generated
  crate. rustc prints it only on a real recompile — a missing, stale file
  means: delete that crate's `target/` and rebuild. The note is split with
  `splitLinkFlags` (quote- and backslash-aware, so SDK paths with spaces
  survive) and persisted as JSON for the same reason; pre-JSON
  space-joined files still read back.
- **Generated `.aot.g.dart` never mentions the `.slint` source.**
  `SlintCompilerFactory.instantiate` takes a component name only; the
  source reaches the binary as compiled code, not text.
- **Component names are unique per package** — all components share one
  glue dylib and one symbol namespace. So are AOT module stems: `a/b.slint`
  and `a_b.slint` map to the same stem, and the build hook fails loudly
  rather than letting one overwrite the other's generated sources.
- **A disposed component or render target never touches native code.**
  Property/callback calls on a disposed component throw `StateError`;
  render-target `resize`/`render`/`dispatch*` after either the target or its
  component was disposed are no-ops (`false` for `render`) instead of FFI
  into freed memory. Same rule in `slint_interpreter`.

## Traps

- `ui/` is the input tree in every path: the builder matches `^ui/`, the
  hook compiles `input.packageRoot/ui/**.slint`, the CLI refuses anything
  else. A `.slint` under `lib/` is silently ignored.
- A clean release build of the crate takes ~11 min (fat LTO). Cargo
  rebuilds it whenever a `.slint` changes. Run in the background.
- The build hook is skipped entirely in debug/`flutter test`; a bug here
  surfaces only in `--release`/`--profile` builds.
