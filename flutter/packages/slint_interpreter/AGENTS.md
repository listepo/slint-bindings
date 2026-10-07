# Agent notes — `slint_interpreter`

The runtime backend: `slint-interpreter` plus the software renderer, behind
a C ABI. Active in debug builds and `flutter test`. Read the root `AGENTS.md`
first.

## What lives here

| Path | Crate / role |
|---|---|
| `rust/` | `slint-interpreter-ffi`, over `slint-dart-interpreter` (the renderer-agnostic interpreter wrapper, in `slint_build/interpreter/`): the software renderer (the shared `slint-embed` platform, `MinimalSoftwareWindow`) and the `slint_interpreter_*` C ABI. cbindgen → `rust/include/slint_interpreter_ffi.h`. |
| `lib/src/bindings.g.dart` | ffigen output (`@Native`, asset id `package:slint_interpreter/src/bindings.g.dart`). Generated — never hand-edit. |
| `lib/src/interpreter_engine.dart` | `SlintEngine`/`SlintComponent`/render-target implementations over the bindings; `SlintInspectableComponent.queryElements`. |
| `lib/src/factory.dart` | `SlintInterpreterFactory(source, files:)`: the `SlintComponentFactory` the generated wrappers construct in debug. |
| `hook/build.dart` | Builds `slint-interpreter-ffi` via `slint_build` — except in a release build of an app that also depends on `slint_compiler`, where AOT ships instead. Every source file under `rust/`, `slint`'s `rust/` and `slint_build`'s `interpreter/` is a cache dependency (`sourceDependencies`). |

## Commands

```bash
mise exec -- flutter test                               # lifecycle + the files a factory is handed
mise exec -- dart analyze .
cd ../../examples/todo && mise exec -- flutter test     # the backend behind a real app
cd rust && cbindgen --output include/slint_interpreter_ffi.h && cd .. && mise exec -- dart run ffigen --config ffigen.yaml   # after a C ABI change only
```

`test/` covers component lifecycle and imports/images; `examples/todo` and
`packages/slint_patrol` exercise it end to end. These tests call the
dynamic layer by name on purpose — it is what they test (root `AGENTS.md`,
Product requirements).

## Invariants

- **Everything is synchronous.** `compile` and `instantiate` are single
  FFI calls returning plain values.
- **With `files`, the factory compiles at a real path.** It writes the
  source and every file the wrapper embedded (`import`ed `.slint`,
  `@image-url`) into a temp tree with `writeSlintTree`, once per factory, so
  relative imports and images resolve. Without `files` it compiles at a
  made-up `<Component>.slint` — fine for a self-contained source, an import
  error otherwise. There is no loader hook and no runtime path to a `.slint`
  no wrapper was generated from.
- **`compile` returns components unordered** (`CompilationResult::components()`
  iterates a `HashMap`). Callers select by name; `defs.first` is a coin flip.
- **Element queries live in `slint_build/interpreter/src/elements.rs`**, not in
  `rust/`. Both this crate and `slint-testing-ffi` call `query_elements` /
  `describe_all` so headless and live tests read identical fields. The
  crate depends on `i-slint-backend-testing` for `search_api` only and never
  installs the testing platform — this crate installs the shared `slint-embed`
  software platform (`RepaintBufferType::NewBuffer`).
- **Every C entry point is `catch_unwind`-wrapped** and the crate keeps
  `panic = "unwind"`. Errors go to a thread-local string Dart reads back.
- **Callbacks come back through `NativeCallable`** — keep the Dart side
  alive for as long as the component is; dispose order matters. The
  trampolines set `keepIsolateAlive = false`, so a forgotten `dispose`
  cannot pin a test isolate. A handler that throws cannot unwind through
  Rust: the exception goes to `Zone.current.handleUncaughtError` (a failing
  test, `FlutterError` in an app) rather than being swallowed. An argument
  the JSON bridge cannot carry (image, brush) arrives as `null`; enums read
  as their value name.
- **Frames are premultiplied RGBA8888** at the size `setSize` was given,
  in physical pixels (`SlintView` applies the device pixel ratio). The
  render target starts at 0×0 with no buffer — the size a
  `MinimalSoftwareWindow` starts at — so `render()` before `resize()` is
  `false`, not a "buffer size mismatch" against a made-up default.
- **Every entry point checks `slint_dart_core::thread::check()`** (see
  `slint/AGENTS.md`) before anything else; off the owning thread it sets the
  error and returns the failure value, and the `free`s leak rather than drop
  an `Rc` on the wrong thread.
- **A disposed component or render target never touches native code.**
  Property/callback/query calls on a disposed component throw `StateError`;
  render-target `resize`/`render`/`dispatch*` after either the target or its
  component was disposed are no-ops (`false` for `render`) instead of FFI
  into freed memory. Same rule in the AOT runtime (`slint_compiler`).
- **Do not merge this crate with `slint-testing-ffi`.** Each dylib has its
  own statically linked Slint so their platforms don't collide
  (`init_no_event_loop()` panics if a platform already exists).

## Traps

- `bindings.g.dart` and `rust/include/*.h` are committed; regenerate
  both together after any `extern "C"` change and commit the result.
- The build hook runs on every `flutter run/build/test` of a dependent
  package; a first build takes minutes. Cargo profile defaults to release
  (see `slint_build`).
- `clippy::not_unsafe_ptr_arg_deref` is allowed at crate level on purpose:
  the C ABI is never called from Rust, and each deref is an explicit
  `unsafe` block.
