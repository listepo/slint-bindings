# Done

### D1. Pub + Cargo workspaces, core API, FFI crates, cbindgen/ffigen pipeline

Pub + Cargo workspaces, core API, FFI crates, cbindgen/ffigen pipeline.

### D2. SlintView widget

`SlintView` widget (blits software frames; lives in the `slint` package).

### D3. Rust→Dart callbacks via NativeCallable

Rust→Dart callbacks via `NativeCallable`.

### D4. Interpreter path end-to-end

Interpreter path end-to-end (example todo app, smoke-tested).

### D5. Typed codegen (slint_generator)

Typed codegen (`slint_generator`): `.slint` → `*.g.dart`, one API over both backends via `SlintComponentFactory`.

### D6. Compiled path (slint_compiler)

Compiled path (`slint_compiler`): `*.aot.g.dart` + slint-build AOT staticlib; backend follows the build mode (debug → interpreter, release/profile → AOT).

### D7. Build glue: native assets hooks

Build glue: native assets `hook/build.dart` per package + `bazel_worker` cargo worker (`flutter build/run/test` compiles the Rust crates; debug/release via `profile` user-define).

### D8. Component tree-shaking

Component tree-shaking: app link hook relinks the AOT staticlib keeping only components with a recorded use (`@RecordUse` + `package:record_use` + `CLinker`; active behind `FLUTTER_RECORD_USE=true`, keep-all otherwise).

### D9. UI testing (slint_testing)

UI testing (`slint_testing`): accessibility-tree queries, clicks, property and callback assertions on `i-slint-backend-testing`, under plain `dart test`.

### D10. E2E testing (slint_patrol)

E2E testing (`slint_patrol`): Patrol finders over the live component, tapping and typing through real Flutter gestures (interpreter backend only).

### T1. Skia GPU surface plumbing per platform

Wire Skia GPU surfaces per platform (Metal / GL / Vulkan / D3D) and the Flutter `Texture` widget path. Interpreter and property bridge already worked; GPU surface plumbing and texture export were stubbed.

**Done criteria met:** code, plugins, `examples/todo_skia`, CI `skia-*` jobs, and docs landed. CI green on tip `90b6d17` ([run 35036050220](https://github.com/listepo/slint_dart/actions/runs/35036050220): skia-apple/linux/android/windows + check + release-macos) and on `main` after squash merge of [#6](https://github.com/listepo/slint_dart/pull/6) at `24807ba` (same tree; all skia-* + check success). Local `slint-skia-ffi` build ban stayed.

**Follow-up done as T2:** regenerated `bindings.g.dart` with ffigen (drops stale `texture_id`); platform `@Native`s stay in `skia_native.dart`.

### U1. Slint 1.18.0 bump + dead-weight trim

Bumped workspace Slint crates `=1.17.1` → `=1.18.0` (root `Cargo.toml`, staged `cargoWorkspaceShared`, `slintVersion`, Windows softbuffer override). Renamed introspect feature `software-renderer` → `renderer-software`. Dropped unused `slint` dep from `slint-dart-interpreter`, empty/`bundle-translations` introspect features, and redundant `software-renderer-systemfonts` (now an alias of `renderer-software`). Local `slint-skia-ffi` build stayed banned; skia-* remains CI-only. `skia-safe` jumped 0.99 → 0.153 with the bump — verify on skia CI. Apple(+Windows) enable softbuffer so `skia_windowed` compiles under `default-features = false` (Slint 1.18 `SkiaRenderer::new` / `default`).

### T2. Regenerate `slint_skia` ffigen bindings (drop stale `texture_id`)

Regenerated `packages/slint_skia/lib/src/bindings.g.dart` via `just bindings slint_skia` (cbindgen + ffigen) so the removed `slint_skia_instance_texture_id` C ABI is no longer declared. Platform attach/detach/pixels remain excluded in `ffigen.yaml` and hand-declared in `skia_native.dart`. `skia_engine.dart` uses `Pointer<Void>` (header has raw `void*`; old short bindings had hand-added typedef aliases). Local Skia build ban stayed. CI green on tip before merge ([run 35224242340](https://github.com/listepo/slint_dart/actions/runs/35224242340): check + release-macos + all skia-*). Squash-merged as [#9](https://github.com/listepo/slint_dart/pull/9) at `f05ae23`.
