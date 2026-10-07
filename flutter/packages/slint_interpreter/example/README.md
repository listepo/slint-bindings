# slint_interpreter example

The interpreter is the debug-mode backend behind the typed wrappers that
`slint_generator` emits; the full app is
[`examples/todo`](https://github.com/listepo/slint_dart/tree/main/examples/todo).

```dart
// A generated wrapper, explicitly on the interpreter. `slintFiles` is what
// the source imports or loads through @image-url; the factory writes both
// into a temporary tree so the compiler resolves them.
final app = TodoApp.create(
  SlintInterpreterFactory(TodoApp.slintSource, files: TodoApp.slintFiles),
);
app.todoModel = [const TodoItem(title: 'buy milk', checked: false)];
```

An app does not name the factory: in debug builds the wrapper's
`defaultFactory` is this one, so `SlintComponent.load('ui/todo.slint')` after
`TodoApp.register()` lands here. A `.slint` is only ever loaded through its
generated wrapper — there is no runtime path for a file no wrapper was
generated from.
