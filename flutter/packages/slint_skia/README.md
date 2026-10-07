# slint_skia

GPU Slint backend for Flutter via Rust FFI (`i-slint-renderer-skia`): Skia
renders a component on the GPU into a Flutter external texture — Metal on
iOS/macOS, EGL on Android, D3D12 on Windows, headless EGL with a read-back on
Linux. Compile, properties, rendering and pointer/key input work; callbacks
are not delivered yet.

```yaml
dependencies:
  slint_skia: ^0.0.1
```

**Full docs:** [slint_skia package page](https://listepo.github.io/slint_dart/packages/slint_skia/) (architecture, ceilings, upgrade path), [Backends guide](https://listepo.github.io/slint_dart/guides/backends/).
