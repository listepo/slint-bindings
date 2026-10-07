# Todo Example (Skia backend)

The `examples/todo` UI on the `slint_skia` backend: the same shared list UI,
compiled at runtime by `SkiaSlintEngine`, driven through the generated
`TodoApp` wrapper, and rendered by Skia on the GPU into a Flutter `Texture`.
The list UI, state and page scaffolding come from `examples/todo_shared`.
Callbacks are not delivered yet — the page says so on screen.
`flutter run`/`build`/`test` compile Skia (slow): the default check skips
them, CI's `skia-*` jobs build the app per platform.

```bash
cd examples/todo_skia && dart run build_runner build
dart analyze .
```

**Full docs:** [todo_skia example](https://listepo.github.io/slint_dart/examples/todo_skia/) and the [slint_skia](https://listepo.github.io/slint_dart/packages/slint_skia/) package page.
