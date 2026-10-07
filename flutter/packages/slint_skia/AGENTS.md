# Agent notes — `slint_skia`

The GPU backend: interpreter + `i-slint-renderer-skia`, rendering into a
Flutter external texture on iOS, macOS, Android, Windows and Linux. The
interpreter half and the GPU path are real; callbacks are not. The GPU path is
compiled and verified only in CI (the `skia-*` jobs). Read the root
`AGENTS.md` first.

## What lives here

| Path | Role |
|---|---|
| `rust/src/lib.rs` | `slint-skia-ffi`: the `slint_skia_*` C ABI — compile/instantiate/properties (via `slint-dart-interpreter`), size, render, detach, input, and one attach entry point per platform. Its one test renders a frame through the platform's surface and reads it back. |
| `rust/src/platform/` | `mod.rs`: the Slint platform and `SkiaWindowAdapter`; `metal.rs`, `android.rs`, `d3d.rs`, `gl.rs`: the per-platform surfaces. |
| `lib/src/skia_engine.dart` | `SkiaSlintEngine`, `SkiaSlintComponentDefinition`, `SkiaSlintComponent`, `SkiaTextureRenderTarget` (channel + FFI glue). |
| `lib/src/skia_native.dart` | Hand-declared `@Native`s: the platform-only entry points and detach. |
| `lib/src/bindings.g.dart` | ffigen output for the shared `slint_skia_*` ABI (platform attach/detach/pixels excluded; those live in `skia_native.dart`). Regenerated with `just bindings slint_skia`. |
| `darwin/`, `android/`, `windows/`, `linux/` | The platform plugins: register the texture and hand Rust its render target over the `slint_skia` channel. |
| `hook/build.dart` | Builds `slint-skia-ffi` via `slint_build` — which builds **all of Skia**. |

Consumer: `examples/todo_skia`, which shows the texture and the remaining
ceilings (callbacks) on screen.

## Commands — what runs locally

```bash
mise exec -- dart format --set-exit-if-changed lib/
mise exec -- dart analyze .
cd rust && cargo metadata --format-version 1 > /dev/null    # deps resolve
cbindgen --config rust/cbindgen.toml --crate slint-skia-ffi --output rust/include/slint_skia_ffi.h rust
```

**Never locally**: `cargo build/check/clippy` of this crate, or `flutter
run/build/test` of anything depending on it. Building `slint-skia-ffi`
compiles `skia-safe` (10+ GB of artifacts). Root `Cargo.toml` and the melos
`rust:clippy` script exclude it; the melos `test:flutter` script skips it and
`todo_skia_example`. CI's `skia-apple`, `skia-linux`, `skia-android` and
`skia-windows` jobs are where it is built: clippy, the GPU test, and a debug
build of `examples/todo_skia` per platform (which compiles the plugins).
`dart analyze .` runs here and must stay clean: `lib/src/bindings.g.dart` is
excluded in `analysis_options.yaml` and kept out of the published archive by
`.pubignore`, because over system headers it carries ~80 unused-field
warnings that pub.dev scores against.

**ffigen:** do not run it casually — regenerating pulls macOS system headers
into `bindings.g.dart` and needs a careful diff (shared ABI only; platform
symbols must stay solely in `skia_native.dart`). When the C ABI changes, use
`just bindings slint_skia` (cbindgen + ffigen). That does **not** compile
Skia. The standing ban is the Skia *build*, not a forever ban on the one-shot
bindings refresh after an ABI change.

## Invariants

- **`SlintComponentFactory.instantiate` must return a
  `SlintSoftwareComponent`**, and this backend renders to a texture, so it
  has no factory and the typed `TodoApp` wrapper cannot run on it. Don't
  fake a factory that returns a non-software component.
- **Ceilings are explicit.** Callbacks throw `UnimplementedError`, a platform
  without a surface throws `UnsupportedError`, `render` returns `false` with
  an error while no surface is attached — never a silent no-op that looks
  like success. `examples/todo_skia` relies on the exceptions to say what is
  missing. The site page's "Shortcuts & Ceilings" table is the status of
  record — update it when a ceiling lifts.
- **A file must export exactly one component.** `compile` returns the
  definitions in `HashMap` order, so "the first" would be random:
  `slint_skia_engine_compile` fails with the names when there are several,
  and the Dart `compile` reads the real name back
  (`slint_skia_definitions_name(def, 0)`). `SkiaSlintComponentDefinition
  .dispose` frees the Rust definition; instantiating after that throws.
- **Same rules as the other FFI crates**: `catch_unwind` on every entry
  point, `panic = "unwind"`, thread-local error string, `slint_skia_*` prefix
  (separate namespace from `slint_interpreter_*`). Rendering runs on the
  thread that created the instance (the Dart thread), on every platform.
- **The `slint_skia` channel has five ends**: `skia_engine.dart` and the four
  plugins. A method or argument changes in all five (the protocol table is on
  the site page).
- **Platform-only entry points are guarded in the header and hand-declared in
  Dart.** `cbindgen.toml`'s `[defines]` turns their `cfg`s into `#if`s
  (`__linux__` is also defined on Android); `ffigen.yaml` excludes them, and
  `lib/src/skia_native.dart` declares them with `@Native`, so bindings
  generated on any one host neither lose nor duplicate one. A new
  platform-only entry point goes in both places. `[export] exclude` keeps the
  system functions the platform modules import out of the header.
- **Borrowed buffers stay put until the plugin replies.**
  `slint_skia_instance_pixels` (Linux) is valid until the next render: Dart
  awaits the `frame` reply, and the plugin copies before replying. The NT
  handle from `attach_d3d` is valid until the next attach: the plugin
  duplicates it in `setHandle` before Dart can attach again.
- **Ownership across the boundary**: `attach_android` takes over the
  `ANativeWindow` reference `nativeWindowFromSurface` acquired, also when it
  fails. Skia retains the Metal device, queue and texture, and the darwin
  plugin keeps the `CVMetalTexture` backing until the next allocation.
  `SkiaTextureRenderTarget.dispose` detaches the surface before the plugin
  unregisters the texture, and disposes the component.
- **Sizes are physical pixels and the scale factor stays 1**, as in
  `SlintView`; pointer coordinates are physical too.
- **The Android plugin's Gradle file pins no AGP**: it has no `buildscript`
  classpath and takes the Android Gradle plugin from the app that includes
  it. Don't add one — that would be a second AGP version to keep in step.
- **`cargo machete` needs no ignores here**: `slint`, `i-slint-core`,
  `i-slint-renderer-skia`, `raw-window-handle` and (on Windows) `windows` are
  all referenced from `rust/src`.

## Upgrade path

- Callbacks: a callback channel needs an event loop; `slint_interpreter`'s
  software platform is the pattern to copy.
- Double-buffered textures and GPU fences instead of the CPU wait per frame.
- Linux without the read-back: a GL texture shared with Flutter's context.
- Android on Vulkan once Slint's `VulkanSurface` gets an Android NDK arm.
- Keyboard input in `examples/todo_skia` (`SlintView`'s pattern).
