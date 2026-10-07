# Agent notes — `slint_patrol`

Patrol finders over the **live** Slint component: `$.slint(...)` searches the
accessibility tree and acts through real Flutter gestures aimed at each
element's on-screen rect. Read the root `AGENTS.md` first.

## What lives here

| Path | Role |
|---|---|
| `lib/src/slint_finder.dart` | `SlintFinder`: lazy query, bounded waiting, `tap`, `enterText`, `resolve`, `first`/`at`. |
| `lib/src/patrol_tester_ext.dart` | The `$.slint*` methods and `slintSettle` on `PatrolTester`. |
| `test/slint_patrol_test.dart` | Live-component E2E tests against the interpreter backend. |

No Rust of its own. The element model (`SlintElementInfo`) comes from
`slint_testing`; the query entry point from `slint_interpreter`
(`SlintInspectableComponent`).

## Commands

```bash
mise exec -- flutter test      # builds slint-interpreter-ffi through its hook on first run
mise exec -- dart analyze .
```

## Invariants

- **Never `pumpAndSettle`.** `SlintView` renders on a `Ticker` every frame,
  so the tree never goes quiescent and settling times out. `slintSettle()`
  pumps a bounded number of frames; actions pump until the element exists
  *and* has a non-zero size, spending Patrol's `visibleTimeout` as frames
  (the test clock is fake, real waiting would hang).
- **Geometry → Flutter coordinates divides by the device pixel ratio**,
  because `SlintView` multiplies on the way in and Slint's scale factor is
  never set (logical == physical). If `set_scale_factor` is ever wired up,
  this mapping changes with it.
- **Input travels the user's path**: gesture → `SlintView`'s `Listener` →
  Slint. No test-only side door into the component; `enterText` taps to
  focus, then types through the text input connection a focused `SlintView`
  holds on every platform (`tester.testTextInput` under `flutter test`) —
  the same way a soft keyboard or the desktop text input plugin delivers
  text. Never send key events to type: `SlintView` ignores them while a
  connection is open, on purpose, or a device with a physical keyboard
  would get every character twice.
- **`resolve()` throws on several matches** rather than picking one; narrow
  with `first` or `at(index)`.
- **Interpreter backend only.** Element queries need
  `SlintInspectableComponent`, which AOT does not implement; finders throw a
  message saying so. `flutter test` and `patrol test` are debug, so they are
  fine.
- Element descriptions must match `slint_testing`'s field for field — both
  are produced by `elements.rs` in `slint-dart-interpreter`. Don't reshape
  them on one side only.

## Traps

- An element found before the first frame reports an empty rect; tapping it
  is a no-op. That is why waiting checks size, not just existence.
- `flutter test` here is a real native build (the interpreter crate); the
  first run takes minutes.
