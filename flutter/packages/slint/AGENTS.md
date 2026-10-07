# Agent notes — `slint` (core)

The backend-agnostic core every other package builds on. Read the root
`AGENTS.md` first; this file adds only what is specific here.

## What lives here

| Path | Role |
|---|---|
| `lib/slint_core.dart` | Flutter-free API: `SlintEngine`, `SlintComponentDefinition`, `SlintComponent`, render targets, input events. Tests of the pure layer run under `dart test`. |
| `lib/slint.dart` | `slint_core.dart` plus the `SlintView` widget (`lib/src/slint_view.dart`), which blits `SlintSoftwareRenderTarget.pixels` and forwards pointer/key events. |
| `lib/src/component.dart` | `SlintComponent.load` / `register` / `unregister` (the path registry). |
| `lib/src/slint_tree.dart` | `writeSlintTree`: writes an embedded source and the files it imports into a temp tree, so a runtime compiler resolves imports and images. |
| `lib/src/events.dart` | The FFI event encoding, mirrored by `rust/src/lib.rs`. |
| `rust/` | `slint-dart-core`: shared event mapping onto `slint::platform::WindowEvent`, and the `thread` module every FFI entry point checks first. No C ABI — the FFI crates own that. |

No FFI, no codegen, no interpreter: this package must stay usable by a
backend that has none of those. It depends on `flutter` only for `SlintView`.

## Commands

```bash
mise exec -- flutter test      # registry semantics + SlintView with a fake render target
mise exec -- dart analyze .
```

Or from the repo root: `mise exec -- dart run melos run test:flutter`.

## Invariants

- **`SlintComponent.load(path)` is a registry, and knows no generated
  code.** Wrappers register themselves per component
  (`TodoApp.register()`); `load` resolves a `.slint` path to whatever was
  registered, typed by the type argument. There is no scanning, no static
  initializer, no fallback to reading a file. Keep `load` synchronous — apps
  call it in `initState`.
- **Only `.slint` paths are accepted**, checked before the registry is
  consulted: `ArgumentError.value(path, 'path', 'not a .slint file')`. Both
  this class and the generated wrappers make the same check with the same
  message; `examples/todo/test/todo_load_test.dart` asserts it.
- **There is no untyped way in.** `load` returns the registered generated
  wrapper and nothing else; no path compiles a `.slint` nobody registered
  (root `AGENTS.md`, Product requirements). Don't add a
  `loadAsset`/`loader` hook back.
- **`writeSlintTree` keeps every file inside its temp tree.** It nests the
  entry under as many directories as the deepest leading `..` climbs, so
  `../../todo_shared/ui/x.slint` still lands inside, and throws
  `ArgumentError` for a path that would leave it. The tree is never
  deleted: one per interpreter factory per process.
- **Ambiguity is an error, not a guess.** A path that registered several
  components needs `component:` or a type argument; the messages list what
  is registered. The compiler returns components unordered (a `HashMap`), so
  "first" would be random.
- **The event encoding in `events.dart` and `rust/src/lib.rs` must agree
  byte for byte.** Change both or neither.
- **`SlintView` renders on a `Ticker` every frame**, so a widget tree
  containing one never settles. That is why `slint_patrol` bounds its
  pumping; don't add settling logic here to "help" tests.
- **`SlintView` multiplies by the device pixel ratio on the way in and never
  sets Slint's scale factor**, so Slint logical == physical. `slint_patrol`
  divides by the same ratio on the way out; change both together.
- **`SlintView` drops stale decodes and tolerates unbounded layout.** An
  in-flight `decodeImageFromPixels` that lands after the render target
  changed disposes its image instead of replacing the new target's frame
  (generation guard in `didUpdateWidget`). Under unbounded constraints
  (a `Row`, a scrollable, an unconstrained box) the wanted size is reported
  as 0 — the tick skips resize/render until the layout is bounded — instead
  of throwing in `toInt()` on infinity.
- **Frames go to `decodeImageFromPixels` untouched.** Slint's software
  renderer writes premultiplied RGBA and Flutter's `rgba8888` *is*
  premultiplied ("Premultiplied alpha is used", dart:ui `PixelFormat`), so
  there is no un-premultiply step — the one that used to be here lightened
  every anti-aliased edge and copied the frame per tick.
  `slint_view_test.dart` round-trips a half-transparent pixel to guard it.
- **`build` has no side effects.** The layout records the wanted size; the
  ticker applies `resize` before `render`. Resizing inside `LayoutBuilder`
  frees and reallocates the native buffer during build.
- **Text input is a mirror, not a text field, and it does not branch on the
  platform.** Like `EditableText`, a focused view attaches a
  `TextInputClient` everywhere: a soft keyboard on touch platforms, the
  platform's text input plugin behind a hardware keyboard on desktop (it
  interprets the key events the framework leaves unhandled and reports them
  as edits). The platform edits a mirror string padded with zero-width
  spaces (so backspace has something to delete on iOS) and `editsBetween`
  replays the difference into Slint as backspaces and inserted text. While
  the connection is open the hardware key path is ignored, or every
  character would arrive twice; it is the fallback for a connection the
  platform closed. The mirror is reset whenever its caret is not collapsed
  at the end, so a select-all never replays as deletes. Slint's caret is
  assumed to be at the end of its text; selection and cursor are not synced
  (`input_method_request` from the platform would be the real fix). A
  platform check here would also make `flutter test`, which reports
  Android, behave differently from the desktop it runs on.
- **Pointer events carry the button that went down**, read from
  `event.buttons` at the down event and remembered for the up; cancel is
  a release plus exit, so Slint never stays pressed after a scroll view
  steals the gesture. Hover and mouse exit are forwarded too.
- **`slint-dart-core::thread::check()` pins the first caller's thread.**
  Slint objects are `!Send` and every FFI crate's error slot is a
  thread-local, so each entry point calls it first and reports an error
  instead of touching state from another thread. The static lives in this
  crate but is per dylib (each FFI crate links its own copy).

## Traps

- Adding a dependency on any backend package here creates an import cycle
  (`slint_interpreter` → `slint_generator` → `slint`).
- `component_load_test.dart` uses fake components; it must keep passing
  without any native build.
