# Slint Bindings

Embed [Slint](https://slint.dev) UIs inside native apps: an `NSView` / SwiftUI
view on macOS and a WinUI 3 control on Windows, driven by the host's own run
loop. Later the same core renders Weft UI trees (the sibling `weft` project)
natively, and the web build reuses it through WebAssembly.

Slint has no official Swift or WinUI integration (see [research.md](research.md)).
Its supported embedding hook is a custom platform (`slint::platform`), which is
what this project builds on.

**Status:** M2. The core renders on the CPU into a buffer the host owns.
The macOS host builds and the demo path is covered by headless end-to-end tests,
including keyboard and IME composition. The WinUI host compiles in CI: virtual
keys, IME composition (where the OS provides `CoreTextEditContext`), and a
per-RID native DLL. The WinUI window itself has not been launched here.

## Layout

| Path | What it is |
| --- | --- |
| `crates/slint-bindings-core` | Host-driven Slint platform: software renderer into a caller-owned RGBA buffer, input forwarding, timers. Holds the demo component. |
| `crates/slint-bindings-ffi` | `sb_*` C ABI over the core (static library for Swift, DLL for WinUI). Forwards only. |
| `flutter/` | Copy of [slint_dart](https://github.com/listepo/slint_dart). Its `slint-embed` crate (`flutter/packages/slint/rust/embed`) is the software platform, Dart event map and UI-thread guard shared with the core. |
| `swift/` | SwiftPM package: `CSlintBindings` (C module over the generated header), `SlintBindings` (`SlintHost`, `SlintNSView`, `SlintDemoView`), `SlintDemo` app. |
| `windows/` | WinUI 3 `SlintPanel` control and demo app. |

```text
SwiftUI / AppKit ─┐                       ┌─ WinUI 3 (C#)
  SlintDemoView   │   sb_* C ABI          │   SlintPanel
  SlintNSView     ├──▶ slint-bindings-ffi ◀┤   SlintHost (P/Invoke)
  SlintHost       │         │             │
                  │   slint-bindings-core │
                  │   (slint-embed        │
                  │    SoftwareRenderer)  │
```

## How a frame happens

1. The host view tracks its size and backing scale and calls `sb_host_resize`.
2. On every display-link tick (`CADisplayLink` on macOS,
   `CompositionTarget.Rendering` on WinUI) the host calls `sb_tick` and then
   `sb_host_render`. Slint repaints only when something changed.
3. The host presents the frame (`CGImage` layer contents on macOS take RGBA8;
   WinUI `WriteableBitmap` takes BGRA8 from `sb_host_render_bgra`).
4. Mouse, scroll, keyboard and focus events go back through `sb_host_*` in
   logical points from the top-left corner.

All calls happen on the host's UI thread: Slint objects are single-threaded.

## Build and run (macOS, Apple Silicon)

```sh
mise install      # Rust 1.99, cargo-nextest, just; cbindgen via `cargo install cbindgen`
just check        # fmt, clippy, tests, header drift, P/Invoke drift, swift build, swift test
just swift-run    # opens the SwiftUI demo window
```

Windows: see [windows/README.md](windows/README.md).

## Docs

- [plan.md](plan.md): milestones and active tasks
- [research.md](research.md): how Slint can be embedded, with sources
- [toolchain.md](toolchain.md): programs and packages
- [Русский](docs/ru/README.md), [Українська](docs/uk/README.md)

## License

Apache-2.0. See [LICENSE](LICENSE).
