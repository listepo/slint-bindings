# Slint Bindings

- GitHub: https://github.com/listepo/slint-bindings
- Embed Slint UIs in native hosts (SwiftUI/AppKit on macOS, WinUI 3 on Windows) through a
  host-driven custom Slint platform and a C ABI; then render Weft UI trees with it.

| # | Status | Priority | Complexity | Readiness | Agent |
| --- | --- | --- | --- | --- | --- |
| T3 | todo | P0 | 4 | 0% | |
| T4 | todo | P1 | 3 | 0% | |
| T5 | todo | P1 | 2 | 0% | |
| T6 | todo | P1 | 3 | 0% | |
| T7 | todo | P1 | 4 | 0% | |
| T8 | todo | P1 | 5 | 0% | |
| T9 | todo | P2 | 3 | 0% | |
| T10 | todo | P2 | 3 | 0% | |
| T11 | todo | P1 | 4 | 0% | |
| T12 | todo | P1 | 4 | 0% | |
| T13 | todo | P2 | 4 | 0% | |
| T14 | todo | P2 | 5 | 0% | |
| T15 | todo | P3 | 3 | 0% | |
| T16 | todo | P2 | 3 | 0% | |
| T17 | todo | P3 | 3 | 0% | |

## Milestones

Each milestone ends at a go/no-go checkpoint. A "no-go" stops the milestone's
remaining tasks until the creator decides how to proceed.

| Milestone | Goal | Tasks | Go/no-go checkpoint |
| --- | --- | --- | --- |
| M1: CPU spike | Pixels and input cross the boundary on macOS | T1 (done), T2 (done) | The demo runs at 60 fps at 2x scale for a 800×600 pt view with no visible input lag. No-go: frame time above 8 ms on Apple Silicon, which means go straight to M3. |
| M2: Both hosts, shared core | Same core on WinUI; no duplicated code with slint_dart | T3, T4, T5, T6 | WinUI demo builds and runs; text fields take typed text on both hosts; CI is green. |
| M3: GPU | GPU rendering into the host surface | T7, T8 | 4K view under 4 ms/frame; resize without tearing or black frames; no regressions in input. No-go on one OS keeps the CPU path there. |
| M4: Distribution | Consumable packages | T9 | An app outside this repo adds the package (SwiftPM binary target, NuGet) and runs the demo. |
| M5: Real components and Weft | Any `.slint` component and Weft trees, with typed host APIs | T11, T12, T13 | A Weft sample screen (login form) renders in both hosts from its Weft source, and edits flow both ways. |
| M6: Platform depth | Multiple views, accessibility, iOS, desktop app, web | T10, T14, T15, T16, T17 | VoiceOver and Narrator read the embedded UI; iOS demo runs on a device. |

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Slint has no public API to render into a foreign `NSView`/`HWND` from Rust; only the custom-platform hook. | Every host integration is ours to maintain. | Keep the platform layer small and shared (T3); follow Slint PRs (`ComponentContainer`, C++ platform API, Swift PR #11167). |
| Accessibility: Slint exposes its tree to the OS through the winit backend (AccessKit); a custom platform gets none of it. | Embedded UI is invisible to screen readers. | T14 spike early in M6, earlier if a user needs it; decide between AccessKit adapters per host and a native mirror tree. |
| GPU interop is unstable API (`unstable-wgpu-*`, Skia internals in `i-slint-renderer-skia`). | Breaks on Slint minor releases. | Exact pins; one crate owns the GPU code; slint_dart's `slint-skia-ffi` already solves Metal and D3D12 textures (T3, T7, T8). |
| IME and keyboard mapping differ per host. | CJK input and shortcuts break. | Dedicated tasks (T4, T6) with table-driven key tests. |
| WinUI 3 cannot host a child `HWND` (XAML composition draws over it). | Only `SwapChainPanel` or bitmaps work. | Design for `SwapChainPanel` from the start (T8). |
| `isolated deinit` and Swift 6 strict concurrency move quickly. | Build breaks on new Xcode. | CI on the newest Xcode (T5). |

### T3. Share the embedding core with slint_dart

`packages/slint_dart` already has the same building blocks: `slint-dart-core`
(UI-thread affinity check, FFI event encoding → `WindowEvent`),
`slint-interpreter-ffi` (software renderer → RGBA frames) and `slint-skia-ffi`
(Skia → Metal / D3D12 / EGL textures). `slint-flutter`'s `embedded.rs` is a
third copy of the software path. Extract a neutral crate (working name
`slint-embed`, in `packages/crates`) holding the custom platform, the software
frame path, the event mapping and the thread guard, and make both projects
depend on it. Needs creator approval because it changes slint_dart. Done when
`slint-bindings-core` keeps only host-specific glue and both projects' tests pass.

### T4. macOS keyboard, IME and focus

Adopt `NSTextInputClient` in `SlintNSView` so composition (CJK, dead keys,
emoji picker) reaches Slint as preedit and commit text; complete the AppKit →
Slint key map (function keys, Home/End, Page Up/Down, modifiers as separate
key events) with table-driven tests; make Tab move focus out of the Slint view
into SwiftUI when Slint has no next focus item. Done when a Japanese input
method commits text into the demo field and the key-map tests cover every
`slint::platform::Key`.

### T5. CI

GitHub Actions: `macos-26` (arm64) runs `just check`; `windows-latest` runs
`cargo build -p slint-bindings-ffi`, `cargo nextest run` and
`dotnet build windows/SlintDemo.WinUI`. Use the shared workflows from
`pyrlyn/ci` where they fit. Done when both jobs are required checks on `main`.

### T6. WinUI host builds and runs (M2)

Build the code-only skeleton on Windows and fix it; generate
`NativeMethods.cs` from the C header (evaluate csbindgen versus a small
cbindgen-driven generator) so it cannot drift; let the core render BGRA
directly so the C# swizzle goes away; map `VirtualKey` to Slint key text and
route `CharacterReceived`; IME via `CoreTextEditContext`. Done when the WinUI
demo behaves like the macOS one (T2 checklist).

### T7. GPU path on macOS (M3)

Two candidates, measured against the CPU path:
(a) Skia on Metal through `i-slint-renderer-skia`, reusing slint_dart's
`platform/metal.rs` (renders into an `MTLTexture` over an IOSurface-backed
`CVPixelBuffer`), presented through a `CAMetalLayer` or as IOSurface layer
contents; (b) `FemtoVGWGPURenderer::render_to_texture` (public, `slint::platform::femtovg_renderer`)
with a wgpu Metal surface created from the view's layer
(`SurfaceTargetUnsafe::CoreAnimationLayer`). Prefer (a) if T3 lands, since the
code exists. Done when the M3 checkpoint numbers are met on macOS and live
resize shows no stretched or black frames (`presentsWithTransaction` during resize).

### T8. GPU path on Windows (M3)

Replace the `Image` with a `SwapChainPanel`. Candidates: (a) wgpu D3D12 surface
from the panel (`SurfaceTargetUnsafe::SwapChainPanel`, wgpu PR #4191) plus
`FemtoVGWGPURenderer`; (b) Skia on D3D12 rendering into a shared texture
(slint_dart `platform/d3d.rs`) copied into a composition swap chain that the
host binds with `ISwapChainPanelNative::SetSwapChain` on the UI thread.
Handle `CompositionScaleChanged` for DPI. Done when the M3 checkpoint holds on
Windows.

### T9. Packaging (M4)

macOS/iOS: build `libslint_bindings_ffi.a` for `aarch64-apple-darwin`,
`aarch64-apple-ios` and `aarch64-apple-ios-sim`, wrap with the header and
module map into `SlintBindings.xcframework`, switch `Package.swift` to a
`binaryTarget` and attach the zip to GitHub releases. Windows: NuGet package
with `runtimes/win-x64/native` and `runtimes/win-arm64/native` DLLs plus the C#
control; MSIX for the demo app. Done when a fresh app consumes each package
from a release.

### T10. Multiple hosts and popups

`slint::platform::set_platform` is once per thread, and each component gets its
own `MinimalSoftwareWindow`. Verify two `SlintNSView`s in one window and two
windows; make Slint `PopupWindow` and menus render inside the host view (no
native child windows) and clip correctly. Done with a demo showing two views
and a combo-box popup in each.

### T11. Runtime components (generic API)

Replace the hard-coded demo with `slint-interpreter`: compile `.slint` source
at runtime, set and get properties and invoke or handle callbacks through a
JSON value bridge (the shape slint_dart's `slint-dart-interpreter` already
uses; reuse after T3). C ABI: `sb_compile`, `sb_component_new`,
`sb_set_property_json`, `sb_get_property_json`, `sb_on_callback`. Done when the
demo form is loaded from a file at runtime on both hosts.

### T12. Weft → Slint renderer

Map a validated Weft document (screen, form, field, button, stack, grid,
slots, states) to `.slint` source through the Weft Rust crates
(`weft-core`, `weft-catalog`), compile it with T11, and wire Weft actions to
host callbacks. Start with the Weft login sample. Keep the mapping in its own
crate (`slint-bindings-weft`) so this repository does not depend on Weft
unless that feature is on. Done when the login sample renders in both hosts
from its `.weft` file and its validation diagnostics surface in the host.

### T13. Typed host APIs

Generate Swift (`@Observable` model with two-way property sync through Slint
`changed` callbacks) and C# (INotifyPropertyChanged) wrappers from a `.slint`
file, the way slint_dart's `slint_generator` produces Dart. Done when the demo
uses only generated wrappers and SwiftUI edits and Slint edits stay in sync.

### T14. Accessibility spike

The custom platform exposes no accessibility tree. Prototype exporting Slint's
item tree through AccessKit adapters inside the host view
(`accesskit_macos` subclassing the `NSView`, `accesskit_windows` for UIA on the
panel's window), or a native mirror tree. Done with a recommendation and a
VoiceOver demo reading the form.

### T15. iOS host

`UIView`/`UIViewRepresentable` host over the same core (touch events,
safe-area insets, keyboard avoidance, `CADisplayLink`). Slint's own iOS port
runs whole apps through winit; this is the embedded variant. Done when the demo
form runs inside a SwiftUI iOS app on a device.

### T16. Slint desktop app for Weft

A plain Slint application (winit backend) that opens, validates and previews
Weft files, sharing T12's renderer. This is the "Slint-first" desktop app; the
native hosts embed the same views. Done when it opens the Weft samples.

### T17. Web build

Compile the core to `wasm32-unknown-unknown` with the software renderer
drawing into a canvas (`ImageData`), or Slint's own web backend, and render Weft
trees in the browser through the existing Weft WASM tooling. Done when the
login sample renders in a browser from its `.weft` file.
