# slint_testing example

Headless: no window, no renderer, no event loop. `SlintTestApp` is a
`SlintComponent`, so the wrapper `slint_generator` generated from your
`.slint` wraps it, and the test handles callbacks and reads properties
through typed members:

```dart
import 'package:slint_testing/slint_testing.dart';
import 'package:test/test.dart';
import 'package:todo_example/todo.g.dart';

void main() {
  test('adding a todo reaches the typed handler', () {
    final ui = SlintTestApp.compile(TodoApp.slintSource,
        component: TodoApp.componentName, files: TodoApp.slintFiles);
    final app = TodoApp(ui);
    addTearDown(app.dispose);

    final added = <String>[];
    app.onAddTodo(added.add);
    ui.findById('TodoView::edit').single.setValue('buy milk');
    ui.findByLabel('Add').single.click();

    expect(added, ['buy milk']);
  });
}
```

The wrapper embeds the source and everything it imports, so the test reads
no file. `examples/todo/test/todo_headless_test.dart` in the repository is
the full version.
