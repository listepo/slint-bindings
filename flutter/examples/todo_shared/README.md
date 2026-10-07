# todo_shared

Code shared by `examples/todo` and `examples/todo_skia`:

- `ui/todo_view.slint` — the list UI (`TodoItem`, `TodoView`), imported by
  each app's `ui/todo.slint` and embedded by each app's generated wrapper.
- `TodoStore`, `TodoEntry`, the seed data and the AppBar title helper —
  framework-free, so the list rules live in one place.
- `TodoExampleApp` and `TodoPageStateMixin` — the Flutter page around the
  store: callbacks, sync + rebuild, Scaffold, load error. Each app loads its
  backend and implements `pushTodos`, its mapping to the generated
  `TodoItem`.
- `package:todo_shared/testing.dart` — the "generated wrapper embeds the
  current `ui/todo.slint` and `todo_view.slint`" test, for the apps' test
  suites.

Depends on no app and no generated code. Tested under `flutter test`.

**Full docs:** see the docs site (`just docs-serve`) — Examples → todo_shared.
