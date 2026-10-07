# slint_skia example

Experimental: compiling, instantiating, the property bridge and rendering into
a Flutter external texture work; callbacks are not delivered yet. The
on-screen demo is [`examples/todo_skia`](https://github.com/listepo/slint_dart/tree/main/examples/todo_skia).

`slint_skia` has no `SlintComponentFactory`, so its generated wrapper has no
`load`/`register`: the app compiles through the Skia engine and hands the
component to the wrapper's constructor.

```dart
import 'package:slint/slint_core.dart' show writeSlintTree;
import 'package:slint_skia/slint_skia.dart';

import 'todo.g.dart'; // generated from ui/todo.slint

/// [width] x [height] in physical pixels (logical size x device pixel ratio).
Future<SkiaTextureRenderTarget> run(int width, int height) {
  final engine = SkiaSlintEngine();
  // The compiler resolves imports and @image-url from disk: write the tree
  // the wrapper embeds and compile its entry.
  final defs = engine.compile(
    TodoApp.slintSource,
    path: writeSlintTree(TodoApp.slintSource, TodoApp.slintFiles,
        name: 'todo.slint'),
  );
  // One definition per compile on this backend.
  final component = defs.single.instantiate() as SkiaSlintComponent;

  TodoApp(component).todoModel = [
    const TodoItem(title: 'buy milk', checked: false),
  ];

  // The platform plugin registers the texture; Rust attaches its GPU
  // surface to it. Show it with `Texture(textureId: target.textureId)` and
  // call `target.render()` once per frame (a Ticker).
  return SkiaTextureRenderTarget.create(component, width, height);
}
```

The wrapper's `renderTarget` throws `StateError` here — Skia renders to a
texture, not a software target — so the frame goes through
`SkiaTextureRenderTarget`.
