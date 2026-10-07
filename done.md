# Done

### T1. Scaffold and M1 CPU spike

Rust workspace with `slint-bindings-core` (custom Slint platform, software
renderer into a caller-owned RGBA8 buffer, input, timers, demo form compiled
with `slint-build`) and `slint-bindings-ffi` (`sb_*` C ABI, cbindgen header);
SwiftPM package with `SlintHost`, `SlintNSView` (CGImage layer contents,
`CADisplayLink`, mouse, scroll, keys, focus), `SlintDemoView`
(`NSViewRepresentable`) and a SwiftUI demo app; WinUI 3 skeleton (code only);
`research.md` with sources. `just check` passes on macOS (fmt, clippy, 9 tests,
header drift, `swift build`). The demo window itself was not opened (T2).

### T2. Run and verify the macOS demo

Headless end-to-end tests drive the demo form through the C ABI and through
`SlintHost`: the form paints, ASCII input lands in the name field, Continue and
Enter submit that name, and a repeated resize does not repaint. `SlintNSView`
presents the new frame inside `setFrameSize` and pins it to the top-left, so a
live resize does not stretch the previous image. A non-positive scale is
rejected, a null host is reported through `sb_last_error`, and the WinUI host
publishes a size only after the core accepts it. Replacing the pixel buffer
forces a full repaint; the reused-buffer renderer would otherwise leave the new
storage transparent.

`sb_host_render` at 800×600 pt, 2× (1600×1200), Apple Silicon. The first frame
includes font setup and a full raster; the dirty frame is a later paint after
the name changes. Wall time around the render call:

| Build | First frame | Dirty frame |
| --- | --- | --- |
| debug (what `just swift-run` links) | 14.8 ms | 6.2 ms |
| release | 8.4 ms | 1.0 ms |

The steady frame is under the 8 ms M1 bar in both builds. The demo process
started and stayed up. A captured frame shows the sign-in form at the top-left
of the 2× buffer.

### T3. Vendor slint_dart and share the embedding core

`slint_dart` (https://github.com/listepo/slint_dart) lives in this repo under
`flutter/`. The checkout at `packages/slint_dart` is not modified. Shared
embedding — the process-wide software platform, the Dart FFI event encoding,
and the UI-thread guard — lives in `slint-embed`
(`flutter/packages/slint/rust/embed`). `slint-dart-core` re-exports it, so the
interpreter, the generated AOT glue and Skia keep calling `slint_dart_core::`.
`slint-bindings-core` uses the same platform (reused buffer, host-owned
pixels). The copy's Slint pin matches this repo (`=1.18.1`). Intel macOS
(`x86_64-apple-darwin`) is not a build target.

`just check` passes. `cargo test` for `slint-embed`, `slint-dart-core` and
`slint-interpreter-ffi` passes in `flutter/`.
