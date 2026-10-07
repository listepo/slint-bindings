# slint

Backend-agnostic core for Slint on Flutter: engine, component, render targets,
input events, and the `SlintView` widget. Pure Dart on the surface; shared Rust
lives in `rust/` (`slint-dart-core`). Implementations:
[`slint_interpreter`](/packages/slint_interpreter) (software) and
[`slint_skia`](/packages/slint_skia) (Skia).

```yaml
dependencies:
  slint: ^0.0.1
```

## When to use it

Every app depends on `slint`. App code talks to UI through generated wrappers
that implement these types — never by inventing a second API layer.

## Library layout

| Path | Role |
|---|---|
| `lib/slint.dart` | Public barrel: core abstractions + `SlintView` |
| `lib/slint_core.dart` | Engine / component / render-target / events / models (no widget) |
| `lib/src/` | Implementations of those types |
| `rust/` | `slint-dart-core`: shared event mapping and thread checks for FFI crates (no C ABI here) |

## Core types (reference)

These names match the public Dart surface today. Prefer generated wrappers
(`app.message`, `app.onAddTodo(...)`) in app code; the stringly property /
callback methods exist for backends and tooling.

### `SlintComponent`

Live instance (mirrors `slint_interpreter::ComponentInstance`).

| Member | What it does |
|---|---|
| `SlintComponent.load<T>(path, {component})` | Returns the typed wrapper registered for that `.slint` path. Synchronous. Requires a prior `register()`. |
| `SlintComponent.register<T>(path, component, create)` | Makes `load` answer that path; generated wrappers expose this as `register()`. |
| `SlintComponent.unregister(path)` | Forgets registrations for that path. |
| `getProperty` / `setProperty` | Low-level property access by Slint name. |
| `setCallbackHandler` / `invokeCallback` | Low-level callbacks by Slint name. |
| `dispose()` | Releases the instance. |

`SlintCallbackHandler` is `Object? Function(List<Object?> arguments)`.

### `SlintComponentDefinition`

Compiled, instantiable definition (`instantiate()` / `dispose()`). Backends
produce these; app code usually never holds one directly.

### `SlintView`

Flutter `StatefulWidget` that paints a `SlintRenderTarget` and forwards
pointer / key input. Sizes the target from layout each frame (physical
pixels). In an unbounded layout (a bare `Row`, an unconstrained scrollable)
there is no size to report — give it an explicit size or it renders nothing.

### Render targets and engine

| Type | Role |
|---|---|
| `SlintEngine` | Backend entry that can compile / instantiate components |
| `SlintRenderTarget` | Pixel / texture surface a view paints |
| `SlintSoftwareRenderTarget` | Software-renderer path used by the interpreter (and AOT software path) |
| `SlintTextureRenderTarget` | Texture-backed target (GPU backends such as Skia) |

Exact constructors and factory types live in the backend packages.

### Component variants

| Type | Role |
|---|---|
| `SlintSoftwareComponent` | Component paired with a software render target |
| `SlintInspectableComponent` | Component exposing accessibility-tree queries (testing / Patrol) |

### Color, brush, lifecycle

| Type | Role |
|---|---|
| `SlintColor` / `SlintBrush` | Value types used by properties that cross the FFI boundary |
| `SlintNativeDisposeGuard` | Guards native dispose ordering for FFI-backed objects |

Exact constructors and factory types beyond these interfaces live in the backend packages.

### Input events

| Type | Role |
|---|---|
| `SlintPointerEventKind` | `move`, `down`, `up`, `scroll`, `exit` |
| `SlintPointerButton` | `none`, `left`, `right`, `middle` |
| Related event structs in `src/events.dart` | Mapped onto `slint::platform::WindowEvent` in Rust |

### Models and trees

| Type | Role |
|---|---|
| `SlintListModel<T>` | List model bridge used by generated wrappers |
| `SlintSourceTree` | Source + imported files for runtime compile (`writeSlintTree`) |

`writeSlintTree(source, files)` writes a wrapper's `slintSource` and
`slintFiles` into a temporary directory and returns the entry path — for
backends that compile at runtime so imports and `@image-url` resolve on disk.

## Loading pattern

```dart
HelloApp.register(); // once at startup
final app = SlintComponent.load<HelloApp>('ui/hello.slint')
  ..message = 'Hello from Flutter';
// …
SlintView(target: app.renderTarget);
```

`defaultFactory` inside the generated code follows the Flutter build mode
(interpreter in debug, AOT in release/profile). Passing a factory to
`create()` overrides it. See [Backends](/guides/backends) and
[Getting started](/guides/getting-started).

## See also

- [slint_generator](/packages/slint_generator) — typed wrappers
- [slint_interpreter](/packages/slint_interpreter) / [slint_compiler](/packages/slint_compiler) — backends
- [Todo example](/examples/todo) — end-to-end call sites
