Code shared by `examples/todo` and `examples/todo_skia`, so the two apps
differ only in their backend:

- `ui/todo_view.slint` — the list UI: `struct TodoItem` and
  `component TodoView` (`todo-model`, `add-todo`, `toggle-todo`,
  `remove-done`, and the `edit` field a test finds as `TodoView::edit`).
  Each app's `ui/todo.slint` imports it, wraps it in a window of its own and
  forwards the property and callbacks. It is not a build_runner source of
  this package: each app's generated wrapper embeds it
  (`TodoApp.slintFiles`), and `examples/todo`'s AOT build compiles it.
- `TodoStore` and `TodoEntry`, the seed list and the AppBar title helper —
  framework-free, so the rules (trim-on-add, ignore-empty, bounds-checked
  toggle, drop-checked-on-remove) live here once.
- `TodoExampleApp` and `TodoPageStateMixin` — the Flutter page around the
  store: the callbacks, sync + rebuild, the Scaffold, the load error. Each
  app loads its backend and implements `pushTodos`, mapping `TodoEntry` to
  its generated `TodoItem` at the Slint boundary.
- `package:todo_shared/testing.dart` —
  `testWrapperEmbedsCurrentSlint(TodoApp.slintSource, TodoApp.slintFiles)`,
  which checks that a wrapper's embedded copies still match `ui/todo.slint`
  and the `todo_view.slint` it imports. The shared file is the easy one to
  miss: editing it rebuilds neither app.

No Slint wire format lives here: the apps set `todoModel` and register
`onAddTodo`/`onToggleTodo`/`onRemoveDone` through their generated wrappers.
Depends on no app and no generated code. Tested under `flutter test`.
