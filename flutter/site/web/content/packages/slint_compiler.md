The AOT backend for the wrappers `slint_generator` emits: `.slint` files
compiled ahead of time with `slint-build` into the app's own code asset —
**no slint-interpreter at runtime**. The interpreter path
(`slint_interpreter`) is untouched and independent.

## How it works

```
             ┌─ slint_generator ─▶ foo.g.dart (typed API, backend-agnostic)
foo.slint ──▶┼─ build_runner ────▶ foo.aot.g.dart (@Native bindings + factory)
             └─ app build hook ──▶ slint-build codegen + C ABI glue ──▶ staticlib
                app link hook ───▶ tree-shaken dylib code asset ◀──────────┘
```

- The typed API and the schema tool live in `slint_generator`; this package
  adds the AOT backend.
- Its build_runner builder turns each `ui/**.slint` into `lib/**.aot.g.dart`
  holding only what has to be per-file: the `@Native` externs
  for the glue crate's per-component C symbols (bound to the code asset
  `package:<app>/<path>.aot.g.dart`) and one `SlintCompilerFactory` per
  component (`todoAppFactory`) wiring them into a `SlintComponentOps` bundle.
- Everything downstream of that ABI — the component, the software render
  target, JSON marshalling, callback trampolines — is hand-written in
  `package:slint_compiler/runtime.dart`, which the generated file imports.
- The app's `hook/build.dart` calls `buildSlintAot`, which generates a Rust
  crate in hook scratch space (slint-build codegen of every `ui/**.slint`
  plus generated JSON⇄typed C ABI glue), builds it as a staticlib through
  slint_build's cargo worker, and routes it — plus a manifest of components,
  symbols, and rustc's `native-static-libs` linker line — to the app's link
  hook. The user-visible artifact stays Dart-only. The hook builds only for
  release/profile (`linkingEnabled`); debug builds — including
  `flutter test` — use the `slint_interpreter` package instead and ship no
  AOT dylib.
- The app's `hook/link.dart` calls `linkSlintAot`, which links the final
  dylib from that staticlib with `package:native_toolchain_c`'s `CLinker`,
  keeping only the components the app's Dart code actually uses (see
  [Component tree-shaking](#component-tree-shaking)) and emits it as the
  code assets the externs bind to.

## Usage

```yaml
# pubspec.yaml of the app
dependencies:
  hooks: ^2.2.0      # hook/{build,link}.dart run without dev deps
  meta: ^1.19.0      # @RecordUse in the generated *.aot.g.dart
  slint_compiler: ^0.0.1
  slint_generator: ^0.0.1

dev_dependencies:
  build_runner: ^2.16.0
```

```dart
// hook/build.dart
import 'package:hooks/hooks.dart';
import 'package:slint_compiler/aot_build.dart';

void main(List<String> args) => build(args, buildSlintAot);
```

```dart
// hook/link.dart
import 'package:hooks/hooks.dart';
import 'package:slint_compiler/aot_link.dart';

void main(List<String> args) => link(args, linkSlintAot);
```

Put `.slint` files under `ui/` and list that directory as a build_runner
source (see `slint_generator`'s README for the `build.yaml`), then:

```bash
dart run build_runner build   # ui/todo.slint → lib/todo.g.dart + lib/todo.aot.g.dart
```

`flutter run`/`build`/`test` compiles the native side automatically via the
hook. One-off CLI (writes both libraries into `lib/`; the input must be
under `ui/`, the tree the hook compiles):

```bash
dart run slint_compiler ui/todo.slint
```

```dart
import 'todo.g.dart';                    // typed API (slint_generator)

// The wrapper defaults to this backend in release/profile builds, so the app
// need not import `todo.aot.g.dart` itself.
final app = TodoApp.load('ui/todo.slint');
app.todoModel = [
  const TodoItem(title: 'Learn Slint', checked: false),
];
```

## Component tree-shaking

Every component in the package compiles into the one glue library — but an
app does not necessarily use them all, so the link hook drops the ones it can
prove dead:

- The generated `_new` extern of each component carries `@RecordUse()` (from
  `package:meta`). When the toolchain compiles the app, tear-offs of it that
  survive Dart tree-shaking are recorded — exactly the components whose
  factory is reachable.
- `linkSlintAot` reads those recordings with `package:record_use` and links
  the final dylib with `CLinker` (`package:native_toolchain_c`) using
  `LinkerOptions.treeshake`: only the C symbols of live components (plus the
  two shared ones) are kept; `-dead_strip` / `--gc-sections` discards the
  rest, including each dead component's slint-build generated code.
- Flutter records usages behind its `record use experiment` flag — enable it
  per build with `FLUTTER_RECORD_USE=true flutter build ...` or persistently
  with `flutter config --enable-record-use`. The example's `UnusedGadget`
  component exists to prove the mechanism: exported and compiled like any
  other, referenced by no Dart code, and absent from the shipped dylib when
  the flag is on (`slint_aot_unused_gadget_*` resolves to nothing).
- When the toolchain provides no recordings (`recordedUses == null`, a
  `flutter build` without the flag), every component is kept — the output
  then matches what a plain cdylib build produced. Same if a recording
  references none of the externs, which would mean the recording missed the
  FFI tear-offs; dropping everything on that evidence would break the app.

The linker line for the relink (frameworks, system libs) is not guessed: the
build hook runs cargo with `RUSTFLAGS=--print=native-static-libs` and passes
rustc's own answer along in the manifest. The note is split quote-aware, so
SDK paths containing spaces survive, and persisted as JSON next to the
generated crate (`native-link-flags.<triple>.txt`).

## Release size

The linked dylib ships inside the app bundle, so the generated crate sets a
size-tuned release profile and the link hook strips the result (`-S` debug
info, `-x` local symbols — cargo's `strip = "symbols"` equivalent, applied at
the final link because the staticlib must keep symbols for tree-shaking).
Measured on `examples/todo/` (per architecture, aarch64, Slint 1.18.0):

| configuration                                  | dylib | full 800×600 repaint |
| ---------------------------------------------- | ----- | -------------------- |
| cargo default                                  | 13 MB | —                    |
| stripped                                       | 11 MB | —                    |
| … `+ lto = "fat"`, `codegen-units = 1` ← used  | 9.3 MB | 399 µs              |
| … `+ opt-level = "z"`                          | 7.2 MB | 1075 µs (2.7× slower) |

`opt-level` deliberately stays at the release default of `3`. `"z"` is 2.1 MB
smaller but de-vectorises the software renderer's pixel loops, which are the
hot path. The cost is `lto = "fat"` plus `codegen-units = 1`: a clean release
build of the crate takes ~11 min on an M-series laptop, and cargo rebuilds it
whenever a `.slint` file changes.

`panic = "unwind"` is load-bearing, not a default — the glue wraps every entry
point in `catch_unwind` so a Slint panic surfaces as a Dart error instead of
killing the host process.

### Where the bytes go

`cargo bloat --crates` on the generated crate (arm64, LTO off so that crate
attribution is meaningful; the shipped build is smaller in absolute terms
but the shares hold), `.text` = 5.2 MiB:

| share of `.text` | crates | why it is there |
| --- | --- | --- |
| 13 % | `i_slint_core` | the runtime itself |
| 10 % | `std` | |
| 23 % | `usvg`, `resvg`, `tiny_skia`, `rustybuzz`, `fontdb`, `roxmltree`, `svgtypes`, `simplecss` | SVG: the std-widgets' icons (check marks, arrows) are SVG files that slint-build always embeds (`OnlyBuiltinResources`), rasterised at runtime |
| 22 % | `harfrust`, `skrifa`, `read_fonts`, `parley`, `fontique`, `swash`, `zeno` | text shaping and glyph rendering (`software-renderer-systemfonts`) |
| 9 % | `image`, `image_webp`, `zune_jpeg`, `png`, `weezl`, `fdeflate`, `miniz_oxide` | image decoders |
| 7 % | `i_slint_renderer_software` | the software renderer |
| 5 % | `slint_dart_aot` | the generated glue (per component; unused components are tree-shaken by the link hook) |

Every one of those subsystems is switched on by Slint's `std` feature
(`std` implies `svg`, `image-decoders`, `path`, and system fonts), and the
widget set reaches all of them at runtime, so none can be removed by a
feature flag without changing what renders. `cargo machete` reports no
unused dependencies in the generated crate or the repo's crates. What is
left are trade-offs, not dead code:

- **No system fonts** (`software-renderer-systemfonts` off, fonts embedded
  with `EmbedForSoftwareRenderer`): drops the shaping stack but pre-renders
  glyphs at fixed sizes — MCU-style text.
- **`opt-level = "s"`**: not measured. `"z"` was 2.1 MB smaller and 2.7×
  slower; `"s"` keeps loop vectorisation and may sit in between. Needs two
  release builds and a repaint benchmark to decide.
- **One architecture** (`ARCHS` in the Xcode project, `--target-platform`
  on Android): halves the universal binary.

To repeat the measurement: copy the generated crate out of
`.dart_tool/hooks_runner/shared/<app>/build/slint_aot/` (`Cargo.toml`,
`Cargo.lock`, `build.rs`, `src/`, `ui/`), switch `crate-type` to `cdylib`,
set `lto = false`, and run `cargo bloat --release --crates` there.

Two things this package deliberately does *not* decide for you:

- **Architectures.** `flutter build macos` produces a universal binary, so the
  19 MB framework in the bundle is two 9.3 MB slices. Restricting `ARCHS` in
  `macos/Runner.xcodeproj` roughly halves it (and about halves the 29 MB
  `FlutterMacOS.framework` too), at the cost of dropping Intel support.
- **Slint features.** The crate enables `renderer-software` and
  `software-renderer-systemfonts`. Dropping system fonts would shrink the
  dylib further but changes what text renders.

Debug builds are unaffected: the dylib is not built or bundled at all, since
`hook/build.dart` returns early when `linkingEnabled` is false and the app
falls back to `slint_interpreter`. The interpreter's Dart code — and the
`.slint` source the wrapper embeds for it, which only that branch mentions —
is tree-shaken out of release snapshots by the const `_useCompiled` branch in
the generated wrapper: both verified absent from `App.framework` in a
release build.

## Limits

- Supported property/callback types: numbers, string, bool, named structs,
  arrays. Color/brush/image/enum properties fail generation with a clear
  error.
- Component names must be unique across the package (all components share
  one glue dylib). AOT module stems must be unique too: `a/b.slint` and
  `a_b.slint` collide, and the build hook fails loudly rather than letting
  one overwrite the other's generated sources.
- A Rust toolchain is required at generation and build time (the schema tool
  and the glue crate are compiled with cargo), and a C toolchain
  (clang / MSVC) at app link time — the link hook drives it via
  `package:native_toolchain_c`.
