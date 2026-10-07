# Windows host (WinUI 3) — code-only skeleton

Not compiled yet: M1 had no Windows machine. Everything here mirrors the Swift
host and must be built and fixed on Windows in M2.

| Project | What it is |
| --- | --- |
| `SlintBindings.WinUI` | `SlintPanel` control, `SlintHost` (owns the Rust handle), P/Invoke declarations |
| `SlintDemo.WinUI` | Unpackaged demo app: a WinUI pane and a Slint pane sharing state |

## Build (on Windows, untested)

```powershell
mise install
just windows-dll
dotnet build windows/SlintDemo.WinUI -p:Platform=x64
```

## Rendering path

- **M1 (here):** CPU frames → `WriteableBitmap` → `Image`. Simple, no airspace
  issues, slow for large views.
- **M3:** `SwapChainPanel`. Rust creates the DXGI swap chain on the GPU (wgpu
  `SurfaceTargetUnsafe::SwapChainPanel`, or Skia on D3D12 like slint_dart's
  `slint-skia-ffi`) and calls `ISwapChainPanelNative::SetSwapChain` on the UI thread.
- **Not planned:** a child `HWND`. WinUI 3 has no supported control for hosting
  one, and composition draws XAML over child windows.

## TODO

- [ ] Build and run on Windows; fix compile errors (M2).
- [ ] Generate `NativeMethods.cs` from the header instead of hand-writing it (M2).
- [ ] Keyboard: `VirtualKey` → Slint key text; IME via `CoreTextEditContext` (M2).
- [ ] BGRA output from the core, drop the swizzle in `SlintHost.RenderBgra` (M2).
- [ ] GPU path via `SwapChainPanel` (M3).
- [ ] NuGet package with per-RID native DLLs; MSIX for the demo (M6).
