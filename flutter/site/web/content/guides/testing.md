Two halves, one element model. Both describe elements identically because
both descriptors come from one Rust implementation in
`slint-dart-interpreter`.

## Headless: slint_testing

A component on Slint's testing backend — no window, renderer, or event
loop — wrapped in its generated wrapper like any other backend's instance:

```dart
final ui = SlintTestApp.compile(TodoApp.slintSource,
    component: TodoApp.componentName, files: TodoApp.slintFiles);
final app = TodoApp(ui);
addTearDown(app.dispose);

final added = <String>[];
app.onAddTodo(added.add);
ui.findById('TodoView::edit').single.setValue('buy milk');
ui.findByLabel('Add').single.click();

expect(added, ['buy milk']);
```

Elements are found through the test app; properties and callbacks go
through the wrapper, so nothing names a Slint property. No device, no
window. Reach for it to check a component's logic fast.
`examples/todo/test/todo_headless_test.dart` drives `TodoApp` this way. See
the [testing package](/packages/slint_testing).

## Live: slint_patrol

Patrol finders over the live component in a real widget tree, tapping and
typing through real Flutter gestures:

```dart
await $.slintById('TodoView::edit').enterText('buy milk');
await $.slint('Add').tap();
await $.slintSettle();
expect(TodoApp($.slintComponent()).todoModel.last.title, 'buy milk');
```

Elements are found by label or id — accessibility queries — and state is read
through the generated wrapper, which takes the live component from any
backend; nothing names a Slint property. `examples/todo/test/todo_patrol_test.dart`
drives the real `TodoPage` this way.

`SlintView` renders on a `Ticker` every frame, so the tree never settles —
use `slintSettle()` (a bounded handful of frames) where a Flutter-only test
would call `pumpAndSettle`. Element queries need the interpreter backend
(debug builds, including `flutter test` and `patrol test`). See the
[Patrol package](/packages/slint_patrol).
