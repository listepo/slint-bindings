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
