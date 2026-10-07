# slint_dart

[Slint](https://slint.dev) UI toolkit ↔ Flutter integration.

**Docs site:** [listepo.github.io/slint_dart](https://listepo.github.io/slint_dart/) (Jaspr; deployed from `main`).

## Layout

A melos monorepo: a pub workspace (root `pubspec.yaml`, which also holds the
melos config) plus a Cargo workspace (root `Cargo.toml`). Packages live under
`packages/`, apps under `examples/`.

| Folder | Dart package | Rust crate | Role |
|---|---|---|---|
| `packages/slint/` | `slint` | `slint-dart-core` | Backend-agnostic core: Dart API (engine, component, render targets, input events), the `SlintView` widget, and a shared Rust events module mapping the FFI event encoding onto `slint::platform::WindowEvent`. No interpreter, no codegen. |
| `packages/slint_interpreter/` | `slint_interpreter` | `slint-interpreter-ffi` (`rust/`) | Runtime `.slint` path: `rust/` adds the software renderer (`slint::platform::software_renderer`) and the C ABI → RGBA frames on top of `slint-dart-interpreter` (carried by `slint_build`), which wraps `slint-interpreter` (compile, instantiate, JSON value bridge, callbacks) behind a renderer-agnostic API. |
| `packages/slint_generator/` | `slint_generator` | `slint-introspect` | Shared codegen: `slint-introspect` extracts the typed schema from a `.slint` file, and a build_runner builder emits `foo.g.dart` next to each `foo.slint` — one typed class per component (properties, callbacks, render target), one value class per named struct, plus the embedded `.slint` source. Owns the `SlintComponentFactory` base class (`runtime.dart`) that makes the generated API backend-agnostic. |
| `packages/slint_compiler/` | `slint_compiler` | — | AOT backend, no interpreter: a build_runner builder emits `foo.aot.g.dart` — only the `@Native` externs and a `SlintCompilerFactory` per component, with the component/render-target plumbing hand-written in `runtime.dart`. The app's build hook (`buildSlintAot`) AOT-compiles the `.slint` files with `slint-build` plus generated C ABI glue into a staticlib; the app's link hook (`linkSlintAot`) links it into the one code asset those externs bind to, tree-shaking components no reachable Dart code uses (`@RecordUse` + `package:record_use` + `CLinker`). |
| `packages/slint_skia/` | `slint_skia` | `slint-skia-ffi` | Interpreter + `i-slint-renderer-skia` (GPU) → Flutter external texture: Metal (iOS/macOS), EGL (Android), D3D12 (Windows), headless EGL + read-back (Linux), with a small platform plugin per OS. Built and tested only in CI's `skia-*` jobs; callbacks not delivered yet. |
| `packages/slint_testing/` | `slint_testing` | `slint-testing-ffi` | Testing backend (`i-slint-backend-testing`): instantiates a component with no window, renderer, or event loop and exposes its accessibility tree, so tests find elements by label/id/type/role, click them, and fill them in. `SlintTestApp` is a `SlintComponent`, so the generated wrapper wraps it and headless tests stay typed. Runs under plain `dart test`. |
| `packages/slint_patrol/` | `slint_patrol` | — | Patrol (E2E) support: `$.slint(...)` finders over the **live** component's accessibility tree, tapping and typing through real Flutter gestures aimed at each element's on-screen rect. Extends `PatrolTester`, so one test can drive Flutter widgets, Slint elements, and native UI. |
| `packages/slint_build/` | `slint_build` | `slint-dart-interpreter` (`interpreter/`) | Shared hook plumbing: stages the Cargo workspace every crate builds in (so they build the same from the pub cache as from this repo), cargo builds through a `bazel_worker` persistent worker, target-triple mapping, cross-compile env, cache invalidation. Used by every `hook/build.dart`. Also carries the interpreter wrapper crate that the interpreter, testing and Skia FFI crates share — the one package all three depend on. |
| `examples/todo/` | `todo_example` | — | Todo demo: one typed API (`TodoApp`) over both backends, the app's `hook/build.dart` + `hook/link.dart`, and the `UnusedGadget` tree-shaking canary. |
| `examples/todo_shared/` | `todo_shared` | — | Shared by the example apps: the list UI (`ui/todo_view.slint`, imported by each app's `ui/todo.slint`), the list state (`TodoStore`), the page scaffolding, and the codegen-up-to-date test. |
| `examples/todo_skia/` | `todo_skia_example` | — | The same shared list UI on the `slint_skia` backend: compiled by `SkiaSlintEngine` at runtime and driven through the generated `TodoApp`, rendered by Skia on the GPU into a `Texture` widget. Compiles all of Skia — excluded from default CI, built per platform by CI's `skia-*` jobs; local checks are `build_runner` + `dart analyze`. |

One typed API, two independent backends behind it:

```
                    ┌─ slint_generator ──▶ foo.g.dart (typed API + embedded source)
.slint file ──▶ ────┤
                    ├─ runtime:      SlintInterpreterFactory ──────────────────────────┐
                    └─ compile-time: slint_compiler ──▶ foo.aot.g.dart (factory)       ├──▶ SlintView
                                     + app hooks: slint-build AOT staticlib, link hook
                                       tree-shakes unused components into the dylib ───┘
```

`SlintComponent.load('ui/todo.slint')` is the whole call site — synchronous, since either backend instantiates in a single FFI call — after one `TodoApp.register()` at startup (per component, so an unregistered one still tree-shakes away). A UI is named by its `.slint` path in every build mode, and the generated wrapper resolves that name to whatever the build compiled: the interpreter compiling the embedded source in debug, the AOT-compiled component in release and profile. The split is generated, not looked up: `defaultFactory` branches on a `const`, so a release binary carries no interpreter path and no copy of the `.slint` text either — the embedded source is referenced only where the interpreter factory is constructed, inside the branch the tree shaker drops. App code names neither backend; passing a factory to `create()` overrides it. `.slint` files live in `ui/`, outside `lib/`, and are never bundled: the builder embeds the source it compiled into `lib/*.g.dart` — with every file it imports or references through `@image-url`, as `slintFiles` — and release compiles it into the AOT dylib, so neither mode reads the file. Loading a `.slint` always gives back its generated wrapper; nothing compiles a `.slint` no wrapper was generated from. App code talks to Slint only through the wrapper's typed members (`app.todoModel`, `app.onAddTodo(...)`), never by property or callback name. Both factories extend the `SlintComponentFactory` base class in `slint_generator`. Both paths feed the same `SlintView` widget via `SlintSoftwareRenderTarget`. The runtime path compiles the embedded `.slint` source with `slint-interpreter` inside the `slint_interpreter` package; the compiled path ships slint-build-generated components in the app's own code asset and involves no interpreter at all.

The path follows the Flutter build mode, and only the matching dylib is bundled: debug builds (including `flutter test`) ship the interpreter (`slint_interpreter_ffi`), release/profile builds ship the AOT dylib (`slint_dart_aot`). The hooks branch on `linkingEnabled`, which Flutter sets exactly for the non-debug modes.

## Bindings pipeline

```
Rust extern "C"  →  cbindgen  →  rust/include/<crate>.h  →  ffigen  →  lib/src/bindings.g.dart  →  hand-written wrappers implementing the `slint` package interfaces
```

Regenerate after changing the Rust ABI:

```bash
cd <plugin>/rust && cbindgen --output include/$(basename $PWD).h && cd .. && dart run ffigen --config ffigen.yaml
```

Bindings are generated in `ffi-native` mode: top-level `@Native` functions
resolved against the code asset `package:<pkg>/src/bindings.g.dart` — no
`DynamicLibrary.open`, no load paths.

## Native assets build

The FFI packages (`slint_interpreter`, `slint_skia`, `slint_testing`) ship a
`hook/build.dart` (Dart native assets). During
`flutter run` / `flutter build` / `flutter test` — or `dart test`, for
`slint_testing` — the hook builds the
package's crate with cargo — driven through a `bazel_worker` persistent
worker (`packages/slint_build/bin/cargo_worker.dart`) — and bundles the produced
cdylib as a code asset. Shared plumbing lives in the `slint_build` package
(target-triple mapping, Android NDK/iOS/macOS cross-compile env, cache
invalidation over the Rust sources).

Cargo profile defaults to `release`; switch via pubspec user-defines — read
from the workspace-root `pubspec.yaml` in this repo (an app outside a pub
workspace uses its own pubspec). They are part of the hook input, so changing
them correctly invalidates the hook cache:

```yaml
hooks:
  user_defines:
    slint_interpreter:
      profile: debug   # or release (default)
```

## Platforms

macOS, iOS, and Android build and run today (verified on device simulators
for both mobile platforms, in both backends). The hooks derive everything
per-platform from the build input — Rust target triple, Android NDK clang
wrapper and API level, Apple deployment targets — so no platform-specific
configuration lives in the app. Linux and Windows have target-triple
mappings but are untested.

Per-platform build commands and a measured size comparison live in
[`examples/todo/README.md`](examples/todo/README.md).

## Toolchain and workflow

- Flutter via mise: `mise exec -- flutter ...`
- Rust via rustup (`cargo`), plus `cargo install cbindgen`
- `just` (via mise) for the short form: `just` lists recipes, `just check`
  runs what CI runs; `examples/todo/justfile` has the release builds and the
  tree-shaking check. Melos does the package iteration underneath, as a root
  dev dependency — nothing to activate globally:

```bash
mise exec -- dart pub get                       # the whole workspace
mise exec -- dart run melos run analyze         # dart analyze, per package
mise exec -- dart run melos run test            # Dart packages, then Flutter packages and examples/todo
mise exec -- dart run melos run codegen         # ui/*.slint → lib/*.g.dart in the examples
mise exec -- dart run melos run rust:clippy     # every crate except slint-skia-ffi
mise exec -- dart run melos run rust:test       # cargo test, same exclusion
mise exec -- dart run melos run check           # analyze, Dart+Rust format, clippy, tests — what CI runs
```

`melos run` alone lists the scripts. Rust formatting and linting use rustfmt
defaults and the lint levels in the root `Cargo.toml` `[workspace.lints.*]`
tables (`cargo fmt --all`, `cargo clippy --workspace --exclude slint-skia-ffi
--all-targets`). See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full
workflow and [`AGENTS.md`](AGENTS.md) — plus each package's own `AGENTS.md`
— for the invariants a change must respect.

## Testing UIs

`slint_testing` runs a component on Slint's testing backend — no window,
renderer, or event loop — and exposes its accessibility tree, so a test finds
elements by label, id, type, or role and clicks them or fills them in.
`SlintTestApp` is a `SlintComponent`, so the generated wrapper wraps it and
the test reads properties and handles callbacks through typed members:

```dart
final ui = SlintTestApp.compile(TodoApp.slintSource,
    component: TodoApp.componentName, files: TodoApp.slintFiles);
final app = TodoApp(ui);
final added = <String>[];
app.onAddTodo(added.add);
ui.findById('TodoView::edit').single.setValue('buy milk');
ui.findByLabel('Add').single.click();
expect(added, ['buy milk']);
```

No device and no window; the crate builds through the same native-assets
hook. See the package page.

`slint_patrol` covers the other half — the app a user actually touches.
Slint draws its whole UI into one Flutter widget, so Patrol's `$(...)` sees a
single opaque box; `$.slint(...)` searches the **live** component's tree and
acts through real Flutter gestures aimed at the element's on-screen rect:

```dart
await $.slintById('TodoView::edit').enterText('buy milk');
await $.slint('Add').tap();
await $.slintSettle();
expect(TodoApp($.slintComponent()).todoModel.last.title, 'buy milk');
```

State is read through the generated wrapper, which takes the live component
from any backend.

Both describe elements identically, because both come from one query
implementation in `slint-dart-interpreter` that the testing and runtime FFI
crates each expose. Element queries need the interpreter backend, so they work
in debug builds — including `flutter test` and `patrol test` — and not in the
AOT backend of release and profile builds.

## Status / next steps

- [x] Pub + Cargo workspaces, core API, FFI crates, cbindgen/ffigen pipeline
- [x] `SlintView` widget (blits software frames; lives in the `slint` package)
- [x] Rust→Dart callbacks via `NativeCallable`
- [x] Interpreter path end-to-end (example todo app, smoke-tested)
- [x] Typed codegen (`slint_generator`): `.slint` → `*.g.dart`, one API over both backends via `SlintComponentFactory`
- [x] Compiled path (`slint_compiler`): `*.aot.g.dart` + slint-build AOT staticlib; backend follows the build mode (debug → interpreter, release/profile → AOT)
- [x] Build glue: native assets `hook/build.dart` per package + `bazel_worker` cargo worker (`flutter build/run/test` compiles the Rust crates; debug/release via `profile` user-define)
- [x] Component tree-shaking: app link hook relinks the AOT staticlib keeping only components with a recorded use (`@RecordUse` + `package:record_use` + `CLinker`; active behind `FLUTTER_RECORD_USE=true`, keep-all otherwise)
- [x] UI testing (`slint_testing`): accessibility-tree queries, clicks, property and callback assertions on `i-slint-backend-testing`, under plain `dart test`
- [x] E2E testing (`slint_patrol`): Patrol finders over the live component, tapping and typing through real Flutter gestures (interpreter backend only)
- [ ] Skia GPU surface plumbing per platform (Metal / GL / Vulkan / D3D); `Texture` widget path
