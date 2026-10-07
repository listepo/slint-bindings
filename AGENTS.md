# Slint Bindings: instructions for agents

**What this is.** Embedding Slint into native hosts (SwiftUI/AppKit, WinUI 3) through a
host-driven custom Slint platform and a C ABI. Weft rendering builds on it later.

If an `AGENTS.md` or `CLAUDE.md` exists higher in the tree, follow it too; on conflict, ask the creator.

## Read first

- `plan.md`: active tasks and their execution plans.
- `research.md`: what Slint offers for embedding and why this design.

## Rules

- **The host owns the run loop.** The core never spins an event loop or opens a window;
  hosts drive resize, input, `sb_tick` and `sb_host_render`.
- **One UI thread.** Every `sb_*` call comes from the thread that created the host.
  Swift types are `@MainActor`; C# calls stay on the dispatcher thread.
- **The FFI crate only forwards.** Logic goes into `slint-bindings-core`. Every exported
  function catches panics and reports errors through `sb_last_error`.
- **The header is generated.** After changing the C ABI run `just header` and update
  `windows/SlintBindings.WinUI/NativeMethods.cs` in the same commit; `just header-check`
  fails on drift.
- **Every `unsafe` block has a `// SAFETY:` comment**; every `unsafe fn` has a `# Safety` section.
- **Slint is pinned exactly** (`=1.18.x` for `slint`, `slint-build`, `i-slint-core`):
  `i-slint-core` is internal and must match. Bump all three together, with creator permission.
- **Shared code goes to `packages/`.** The embedding core overlaps slint_dart's
  `slint-dart-core` and `slint-skia-ffi`; do not grow a second copy, see T3.

## Commands

```sh
mise install
just check        # fmt-check, clippy -D warnings, nextest, header-check, swift build
just header       # regenerate swift/Sources/CSlintBindings/slint_bindings.h
just swift-run    # demo app
```
