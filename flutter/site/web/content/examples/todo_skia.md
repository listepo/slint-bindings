The `examples/todo` UI on the `slint_skia` backend: its own `ui/todo.slint`
imports the same shared list (`examples/todo_shared/ui/todo_view.slint`) —
minus the AOT tree-shaking canary — compiled at runtime by `SkiaSlintEngine`,
rendered by Skia on the GPU and shown as a Flutter external texture.

The page creates a `SkiaTextureRenderTarget` at the laid-out size (physical
pixels), shows it with `Texture(textureId:)`, renders from a `Ticker` and
forwards pointer events. What the backend has not grown yet — callbacks — the
page reports on screen in the words of the backend's own
`UnimplementedError`, as it does any error from the GPU path. See the
[slint_skia package](/packages/slint_skia), "Shortcuts &
Ceilings", for what is still a shortcut.

## Building

`slint_skia`'s build hook compiles `slint-skia-ffi`, which pulls in all of
Skia (10+ GB of artifacts), and each platform build compiles the `slint_skia`
plugin. The default check does **not** build either; the `skia-*` jobs in
`.github/workflows/ci.yml` build the app for macOS, the iOS simulator,
Android (arm64), Linux and Windows. The example ships no Linux or Windows
runner: those jobs generate one with `flutter create --platforms=...` first.
Locally, the everyday checks are:

```bash
cd examples/todo_skia && dart run build_runner build   # ui/todo.slint → lib/todo.g.dart
dart analyze .
```

Both run without the native build.

## Codegen

`lib/todo.g.dart` comes from `slint_generator`'s builder, opted into `ui/`
by `build.yaml`. `slint_skia` has no `SlintComponentFactory`, so the wrapper
has no `load`/`register`/`defaultFactory`; the rest of the typed API is
there. `main.dart` writes the embedded tree to disk, so the import of the
shared list resolves, compiles its entry with `SkiaSlintEngine`, and hands
the component to the generated constructor:

```dart
final defs = engine.compile(
  TodoApp.slintSource,
  path: writeSlintTree(TodoApp.slintSource, TodoApp.slintFiles,
      name: 'todo.slint'),
);
final component = defs.single.instantiate() as SkiaSlintComponent;
final app = TodoApp(component);
app.todoModel = [
  for (final e in store.items) TodoItem(title: e.title, checked: e.checked),
];
```

The list itself lives in the shared `TodoStore` (`examples/todo_shared`,
same seed and rules as `examples/todo`) and reaches Slint only through
`app.todoModel`. `main.dart` registers `onAddTodo`/`onToggleTodo`/
`onRemoveDone` too; the backend throws `UnimplementedError` for callbacks
today, which the page reports as a ceiling. The wrapper's `renderTarget`
throws `StateError` for a Skia component — it renders to a texture, not a
software target — so the frame goes through `SkiaTextureRenderTarget`.

As in `examples/todo`, nothing under `flutter: assets:` — the source ships
only as the string the builder embedded.

## What differs from `examples/todo`

| | `todo` | `todo_skia` |
|---|---|---|
| Backend | interpreter (debug) / AOT (release) | `SkiaSlintEngine`, every mode |
| Entry point | `SlintComponent.load('ui/todo.slint')` | `SkiaSlintEngine().compile(...)` at a `writeSlintTree` path, then `TodoApp(component)` |
| Frame | `SlintView` over a software render target | `Texture(textureId:)` over `SkiaTextureRenderTarget` (GPU) |
| Input | pointer + keyboard / IME (`SlintView`) | pointer only |
| Callbacks | delivered | `onAddTodo` & co. throw `UnimplementedError`; the list stays Dart-owned |
| Hooks | app-level `hook/build.dart` + `hook/link.dart` | none — `slint_skia`'s own hook builds its crate |
| Tests | `flutter test` locally | `build_runner` + `dart analyze` locally; the builds run in CI's `skia-*` jobs |
