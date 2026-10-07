Slint runtime for Flutter via Rust FFI — `slint-interpreter` + software renderer. Bindings generated with cbindgen (Rust → C header) and ffigen (C header → Dart).

## Layout

| Path | Crate | Role |
|---|---|---|
| `slint_build`'s `interpreter/` | `slint-dart-interpreter` | Renderer-agnostic wrapper over upstream `slint-interpreter`: compile, instantiate, JSON value bridge, callbacks. Shared with `slint_testing` and `slint_skia`, so it lives in `slint_build`, the one package all three depend on. |
| `rust/` | `slint-interpreter-ffi` | Adds the software renderer and the C ABI (`slint_interpreter_*` symbols) this package binds to. |

## Role

Provides software-rendered component instances through a C ABI:
- **Engine**: Compiles Slint `.slint` source into component definitions (wraps upstream `slint-interpreter`'s `Compiler`)
- **Component**: Instantiated, renderable scene (wraps its `ComponentInstance`)
- **RenderTarget**: Software renderer exposing frames as premultiplied RGBA8888 pixels (wraps `MinimalSoftwareWindow`)
- **`SlintInterpreterFactory`**: the `SlintComponentFactory` subclass
  (`slint_generator`) that backs the typed wrappers — compiles the source
  embedded in a generated `*.g.dart` and instantiates the named component:

```dart
final app = TodoApp.create(
    SlintInterpreterFactory(TodoApp.slintSource, files: TodoApp.slintFiles));
```

The factory owns the source and its files, and `instantiate` is synchronous —
compiling is one FFI call — so a generated wrapper mentions its embedded
source only where it constructs this factory, and a release build drops both
together. It selects the component by name: the compiler returns definitions
unordered.

In an app nothing names this factory: it is the wrapper's `defaultFactory`
in debug builds, so `SlintComponent.load(path)` after `TodoApp.register()`
lands here. This backend compiles only what a generated wrapper hands it —
there is no runtime path for a `.slint` no wrapper was generated from, and no
async entry point.

## Imports and images

The Slint compiler resolves `import`s and `@image-url`s from disk, relative
to the file it compiles. A generated wrapper embeds everything its `.slint`
reads besides itself as `slintFiles` (base64 by path relative to the entry)
and passes it as `files:`; on first use the factory writes source and files
into a fresh temporary directory with `writeSlintTree`
(`package:slint/slint_core.dart`) and compiles the entry there. Without
files it compiles at a nominal `<Component>.slint` path, which is enough for
a self-contained source. The directory is not cleaned up — one per factory.

## Inspecting the live component

Components implement `SlintInspectableComponent`: `queryElements(kind, needle)`
returns the accessibility tree — identity, accessible state, and each
element's geometry — as decoded JSON maps, over the
`slint_interpreter_instance_query_elements` entry point.

That is what makes a Slint UI testable from Flutter, which otherwise sees one
opaque widget: `slint_patrol` uses it to find an element and work out where on
screen to tap it. The query itself lives in `slint-dart-interpreter`
(`elements.rs`) and is shared with `slint-testing-ffi`, so headless and live
tests describe elements identically. It comes from `i-slint-backend-testing`'s
`search_api` only — reading the item tree needs no platform, and this crate
installs the shared `slint-embed` software platform.

## Binding Pipeline

```
packages/slint_build/interpreter/src/lib.rs (interpreter wrapper)
    ↓ used by
packages/slint_interpreter/rust/src/lib.rs (Rust FFI)
    ↓ cbindgen
packages/slint_interpreter/rust/include/slint_interpreter_ffi.h (C ABI)
    ↓ ffigen
packages/slint_interpreter/lib/src/bindings.g.dart (Dart FFI bindings)
    ↓ wrapped by
packages/slint_interpreter/lib/src/interpreter_engine.dart (Dart interface impls)
```

### Regenerate bindings after Rust ABI changes

```bash
cd packages/slint_interpreter/rust
cbindgen --output include/slint_interpreter_ffi.h
cd ../..
dart run ffigen --config packages/slint_interpreter/ffigen.yaml
```

## Status & Next Steps

Using a component or render target after `dispose()` never reaches native
code: property/callback/query calls on a disposed component throw
`StateError`, and render-target calls after either the target or its
component was disposed are no-ops (`false` for `render`).

- [x] Rust FFI layer (engine, definitions, instances, properties, events, rendering)
- [x] Rust→Dart callbacks (registered via `NativeCallable`)
- [x] `SlintView` widget (lives in the `slint` package, consumes `SlintSoftwareRenderTarget.pixels`)
- [x] Build glue: native-assets `hook/build.dart` (cargo via `slint_build`); bundled in debug builds, where the interpreter is the active path
- [x] Tests of its own (`test/`, `flutter test`): imports and images through `files`, disposal and callback lifecycle. They exercise the dynamic layer by Slint name with inline sources — the one place outside generated code that does
