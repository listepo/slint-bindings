A Flutter plugin over Rust FFI that renders Slint components with Skia on the
GPU into a Flutter external texture.

## Architecture

- **Interpreter pipeline**: compilation and instantiation via
  `slint-dart-interpreter` (the shared interpreter crate, carried by
  `slint_build`).
- **C ABI bridge**: the `slint_skia_*` functions, with thread-local error
  handling and `catch_unwind` on every entry point.
- **Property bridge**: JSON getters, setters and invocation, consistent with
  `slint-dart-interpreter`.
- **Slint platform** (`rust/src/platform/mod.rs`): a `SkiaPlatform` that gives
  every instance a `SkiaWindowAdapter` (a Slint `Window` plus a
  `SkiaRenderer`). Size, pointer and key events go through `slint-dart-core`;
  `render` runs Slint's timers and renders through the attached surface, and
  fails with an error while none is attached.
- **Per-platform surfaces**, each rendering into a texture the platform
  plugin registers with Flutter:

| Platform | Texture (plugin) | Skia surface (Rust) |
|---|---|---|
| iOS, macOS | IOSurface-backed `CVPixelBuffer` → `CVMetalTextureCache` → `MTLTexture`, shown as a `FlutterTexture` (Swift, `darwin/`, SwiftPM + CocoaPods) | `platform/metal.rs`: wraps the `MTLTexture` with `skia_safe::gpu::mtl`, submits and waits |
| Android | `TextureRegistry.SurfaceProducer` → `Surface` → `ANativeWindow` through the JNI `nativeWindowFromSurface` (Java, `android/`) | Slint's own GL/EGL surface on that window (`platform/android.rs`); Flutter composites the queued buffers |
| Windows | `flutter::GpuSurfaceTexture` over a DXGI shared handle (C++, `windows/`) | `platform/d3d.rs`: a D3D12 device on Flutter's adapter (by LUID), a shared BGRA8 texture + NT handle, a Skia D3D context |
| Linux | `FlPixelBufferTexture` fed with each frame (C, `linux/`) | `platform/gl.rs`: a headless EGL pbuffer (surfaceless Mesa first) with Skia GL, read back with `read_pixels` |

Android uses Slint's GL surface because Slint 1.18.0's `VulkanSurface` has
no Android NDK arm. Linux loads `libEGL.so.1` at runtime, so a missing EGL is
an attach error rather than a failure to load the library.

### The `slint_skia` channel

`SkiaTextureRenderTarget` talks to the plugin over
`MethodChannel('slint_skia')` and to Rust over FFI:

| Call | Platforms | What |
|---|---|---|
| `create` → texture id | all | registers the texture |
| `allocate {textureId, width, height}` | Apple → `{device, queue, texture}`; Android → `{window}`; Windows → `{luidLow, luidHigh}` | the render target Rust attaches to (`slint_skia_instance_attach_*`) |
| `setHandle {textureId, handle, width, height}` | Windows | the NT handle `attach_d3d` returned; the plugin keeps a duplicate |
| `frame {textureId}` | Apple, Windows, Linux (+ `pixels, length, width, height`) | a frame is ready; on Linux the plugin copies the borrowed pixels before it replies |
| `dispose {textureId}` | all | unregisters the texture |
| `surfaceCleanup` / `surfaceAvailable {textureId}` (plugin → Dart) | Android | detach / allocate and attach again |

### Callback handler

**Current**: `setCallbackHandler()` throws `UnimplementedError`, and so do a
generated wrapper's `onX` members, which call it.

**Plan**: forward Slint callbacks to Dart closures. Needs event loop
integration (`slint_interpreter`'s software platform is the pattern).

---

## Building and CI

Building `slint-skia-ffi` compiles:
- `i-slint-renderer-skia` (Slint's Skia bindings)
- `skia-safe` (the full Skia library, 10+ GB of artifacts)

So no local check builds it:

- Default CI (`melos run check`) excludes `slint-skia-ffi` from
  `cargo clippy` / `cargo test` and `examples/todo_skia` from `flutter test`.
- The `skia-*` jobs in `.github/workflows/ci.yml` compile it, one per
  platform family: `skia-apple` (clippy, the GPU test on Metal, macOS + iOS
  simulator builds of `examples/todo_skia`), `skia-linux` (clippy, the GPU test
  on Mesa's headless EGL, Linux build), `skia-android` (arm64 APK build) and
  `skia-windows` (clippy, the GPU test on D3D12 or WARP, Windows build).
- The crate's one test compiles a single-colour component, attaches the
  platform's surface, renders, and reads the texture back. Without a usable
  GPU API it fails unless `SLINT_SKIA_NO_GPU=1` is set (then it says it
  skipped the frame check).

---

## Generating Bindings

After changing the C ABI:

```bash
# Generate the C header from the Rust source
cbindgen --config packages/slint_skia/rust/cbindgen.toml --crate slint-skia-ffi \
  --output packages/slint_skia/rust/include/slint_skia_ffi.h packages/slint_skia/rust

# Generate the Dart FFI bindings
cd packages/slint_skia && dart run ffigen --config ffigen.yaml
```

The attach entry points (and `slint_skia_instance_pixels`) exist on one
platform each. `cbindgen.toml`'s `[defines]` guards them with `#if` in the
header. ffigen parses that header for one host, so `ffigen.yaml` excludes
them, together with `slint_skia_instance_detach`, and
`lib/src/skia_native.dart` declares them by hand with `@Native`. The
committed `bindings.g.dart` predates the GPU work: it still declares the
removed `slint_skia_instance_texture_id`, which nothing calls, until ffigen
runs again.

---

## API Surface

### Dart

This backend has no `SlintComponentFactory`, so a generated wrapper has no
`load`/`register`/`defaultFactory` here. The app compiles through the engine
and passes the component to the wrapper's constructor, which takes any
backend's `SlintComponent`:

```dart
import 'package:slint/slint_core.dart' show writeSlintTree;
import 'package:slint_skia/slint_skia.dart';

import 'todo.g.dart'; // generated from ui/todo.slint

final engine = SkiaSlintEngine();
// The compiler resolves imports and @image-url from disk: write the tree the
// wrapper embeds and compile its entry.
final defs = engine.compile(
  TodoApp.slintSource,
  path: writeSlintTree(TodoApp.slintSource, TodoApp.slintFiles,
      name: 'todo.slint'),
);
final component = defs.single.instantiate() as SkiaSlintComponent; // one per compile

final app = TodoApp(component)
  ..todoModel = [const TodoItem(title: 'buy milk', checked: false)];

// Physical pixels. The plugin registers the texture; Rust attaches its GPU
// surface to it.
final target = await SkiaTextureRenderTarget.create(component, 800, 600);
// Texture(textureId: target.textureId), and once per frame (a Ticker):
target.render();
```

`create` is the one asynchronous step (a channel round trip). After it,
`textureId`, `render()`, `resize()` and the pointer/key dispatchers are
synchronous; `resize()` reallocates the texture in the background and
`render()` returns false until it lands. Sizes and pointer coordinates are
physical pixels: Slint's scale factor stays 1, as in `SlintView`.
`dispose()` detaches the surface, unregisters the texture and disposes the
component. On a platform without a surface `create` throws
`UnsupportedError`.

The wrapper's `renderTarget` throws `StateError` for a Skia component — it
renders to a texture, not a software target — so the frame goes through
`SkiaTextureRenderTarget`. The component's own
`getProperty`/`setProperty`/`invokeCallback` are the bridge the generated
members call; app code uses the members.

### C

```c
void *engine = slint_skia_engine_new();
void *def = slint_skia_engine_compile(engine, "export component App { }", "app.slint");
void *inst = slint_skia_instantiate(def);

// Linux shown; each platform has its own attach entry point.
slint_skia_instance_attach_gl(inst, 400, 300);
if (slint_skia_instance_render(inst)) {
  uintptr_t len;
  const uint8_t *rgba = slint_skia_instance_pixels(inst, &len);
}
const char *error = slint_skia_last_error();

slint_skia_instance_free(inst);
slint_skia_definitions_free(def);
slint_skia_engine_free(engine);
```

---

## File Structure

```
packages/slint_skia/
├── pubspec.yaml              # Dart package + plugin platforms
├── lib/
│   ├── slint_skia.dart       # Public exports
│   └── src/
│       ├── skia_engine.dart   # Engine, component, SkiaTextureRenderTarget
│       ├── skia_native.dart   # Hand-declared platform-only entry points
│       └── bindings.g.dart    # Generated (do not edit)
├── darwin/                   # Swift plugin (iOS + macOS): Metal / IOSurface
├── android/                  # Java plugin: SurfaceProducer + JNI
├── windows/                  # C++ plugin: GpuSurfaceTexture (DXGI handle)
├── linux/                    # C plugin: FlPixelBufferTexture
├── rust/
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs            # C ABI + the GPU test
│   │   └── platform/         # Slint platform + metal / android / d3d / gl surfaces
│   ├── cbindgen.toml         # C header generation config
│   └── include/
│       └── slint_skia_ffi.h  # Generated C header
└── ffigen.yaml               # Dart FFI binding generation config
```

---

## Shortcuts & Ceilings

| Item | Status | Upgrade Trigger |
|------|--------|-----------------|
| Definitions enumeration | One per compile; several exported components is an error naming them | Multiple root components |
| Callback handler | Throws `UnimplementedError` | Interactivity features (needs an event loop) |
| GPU rendering | Real on iOS, macOS, Android, Windows, Linux; built and tested only in CI (`skia-*` jobs) | — |
| Texture export | Real: `SkiaTextureRenderTarget.textureId` | — |
| Single-buffered texture | Flutter can sample a frame mid-render (tearing), and shows an empty texture right after a resize | Double buffering (two textures, swapped on `frame`) once it shows |
| CPU sync per frame | Every render waits for the GPU (Metal, D3D12, GL read-back) before Flutter hears of the frame | GPU fences / shared events |
| Linux read-back | GPU render, `read_pixels`, then one more copy in the plugin, every frame | A GL texture shared with Flutter's context |
| Linux EGL thread | The EGL context is made current on the Dart thread; if a GLX context is current there, libglvnd refuses (`EGL_BAD_ACCESS`, reported as such) | A dedicated render thread |
| Windows handle | Flutter's ANGLE (D3D11) opens a D3D12 NT handle without a keyed mutex; proven only in CI | A keyed mutex or a D3D11 texture if ANGLE rejects it |
| Android surface lifecycle | `onSurfaceCleanup` reaches Dart asynchronously, so a frame can target a surface being torn down; the `SurfaceProducer` callbacks need Flutter 3.27+ | A synchronous detach on the platform thread |
| Android renderer | Slint's GL/EGL surface: Slint 1.18.0's `VulkanSurface` has no Android NDK arm | A Slint release with Vulkan on Android |
| Keyboard in `examples/todo_skia` | Pointer only | `SlintView`'s focus + text input pattern, once typing matters |
| Dart bindings | Platform-only entry points hand-declared in `skia_native.dart`; `bindings.g.dart` stale until ffigen runs | Regenerate with ffigen |
| Scale factor | Stays 1; sizes and pointer coordinates are physical pixels | Wire `set_scale_factor` |

---

## Testing & Verification

**Default CI does not compile Skia; the `skia-*` jobs do.** Everyday local
checks for `examples/todo_skia`:

```bash
cd examples/todo_skia && dart run build_runner build
dart analyze .
```

A full `flutter run` / `flutter test` compiles Skia through this package's
hook — optional, slow, and not part of `melos run check`.

---

## Notes for Contributors

- Keep Rust code **simple and panic-safe** (no exotic dependencies).
- All Rust errors → thread-local string; Dart sees them in `_getLastError()`.
- C ABI prefix is `slint_skia_*` (not `slint_interpreter_*`; namespaces are separate).
- Pointer safety: `nullptr` checks are in FFI bindings (Dart side), Rust validates all inputs.
- The channel protocol has five ends (`skia_engine.dart` and the four
  plugins): change them together.

---

**Status**: interpreter plumbing and the GPU path are real on every
platform, verified in CI only; callbacks are the next step.
