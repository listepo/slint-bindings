# Agent notes — `slint_testing`

Headless UI tests: a component on `i-slint-backend-testing` — no window,
renderer, or event loop — exposed as findable, clickable elements under
plain `dart test`. Read the root `AGENTS.md` first.

## What lives here

| Path | Role |
|---|---|
| `rust/` | `slint-testing-ffi`: installs the testing platform (`init_no_event_loop`), compiles/instantiates through `slint-dart-interpreter`, exposes element queries, default-action click, set-value, `elapse`, properties, and host callbacks (`slint_testing_app_set_callback` + `slint_testing_callback_set_result`) over `slint_testing_*`. |
| `lib/src/testing.dart` | `SlintTestApp` (`compile`, `findBy*`, `elapse`; implements `SlintComponent`), `SlintElement`. |
| `lib/src/element_info.dart` | `SlintElementInfo` — the element model this package **owns** and `slint_patrol` reuses. |
| `lib/src/bindings.g.dart` | ffigen output. Generated — never hand-edit. |
| `hook/build.dart` | Builds the crate via `slint_build`; depends on `rust/` and `slint_build`'s `interpreter/` (the shared `slint-dart-interpreter` crate), found through the package config. |
| `test/slint_testing_test.dart` | Its own tests, against an inline `.slint`, by Slint name: that is the layer under test. App-level headless tests go through the generated wrapper instead — `examples/todo/test/todo_headless_test.dart`. |

## Commands

```bash
mise exec -- dart test        # builds slint-testing-ffi through the hook on first run (minutes)
mise exec -- dart analyze .
cd rust && cbindgen --output include/slint_testing_ffi.h && cd .. && mise exec -- dart run ffigen --config ffigen.yaml   # after a C ABI change only
```

## Invariants

- **Separate dylib, separate Slint.** `init_no_event_loop()` panics if a
  platform already exists; this is safe only because `slint-testing-ffi`
  statically links its own Slint, independent of the software platform
  `slint-interpreter-ffi` installs from `slint-embed`. Do not merge the two crates or make one depend
  on the other's platform.
- **The query implementation is not here.** `elements.rs` in
  `slint-dart-interpreter` fills `SlintElementInfo` for both this crate and
  the runtime one, so a headless test and a `slint_patrol` test read the
  same fields for the same element. Add fields there, then mirror them in
  `element_info.dart`.
- **Synchronous surface only.** `click()` is the accessible *default
  action* and `setValue` the accessible value — both sync. The async
  `single_click`/`double_click` pointer helpers need an event loop the
  testing backend doesn't run; they are deliberately not exposed.
- **Elements belong to the query that produced them.** Each query replaces
  the snapshot; acting on an element from an earlier query throws rather
  than acting on whatever now sits at that index.
- **`SlintTestApp` is a `SlintComponent`**, so a generated wrapper wraps it
  (`TodoApp(ui)`) and headless app tests read and handle everything through
  typed members — the product requirement in the root `AGENTS.md`. The
  package depends on `slint` for the interface only (`slint_core.dart`,
  Flutter-free), so `dart test` still runs here. Don't add by-name
  conveniences back (the old `record`/`takeCalls` call log): app tests would
  reach for them instead of the wrapper.
- **Callbacks are Dart handlers behind a `NativeCallable.isolateLocal`
  trampoline**, as in `slint_interpreter`: synchronous, the result reported
  through `slint_testing_callback_set_result` while the handler runs, a
  throwing handler reported to the zone. Every FFI call on the handle goes
  through `guardNative` (`SlintNativeDisposeGuard`), so a handler may
  dispose the app in the middle of the `click()` that fired it.
- **`compile(files:)` writes the embedded tree with `writeSlintTree`** from
  `slint`, the same helper `SlintInterpreterFactory` uses, so a wrapper's
  `slintSource` + `slintFiles` compile here exactly as in debug.
- **`component:` is required when the source exports several** — the
  compiler returns them unordered and `compile` names what it found instead
  of guessing.
- Geometry fields exist for `slint_patrol`; headless tests never lay out,
  so don't assert on `x`/`y`/`width`/`height` here.

## Traps

- `dart test` here is a native build; `melos run test:dart` includes it, so
  that script is slow on a cold cache.
- The tree is the *whole* item tree, widgets' internals included; prefer
  `findByLabel`/`findById` over `findByType`/`findAll` in assertions.
