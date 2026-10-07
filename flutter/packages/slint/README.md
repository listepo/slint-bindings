# slint

Abstract render-engine API for Slint on Flutter: `SlintEngine`,
`SlintComponent`, `SlintRenderTarget`, and input events. Pure Dart on the
surface; shared Rust lives in `rust/` (`slint-dart-core`). Implementations:
`slint_interpreter` (software) and `slint_skia` (Skia).

```yaml
dependencies:
  slint: ^0.0.1
```

**Full docs:** [slint package page](https://listepo.github.io/slint_dart/packages/slint/), [Backends guide](https://listepo.github.io/slint_dart/guides/backends/).
