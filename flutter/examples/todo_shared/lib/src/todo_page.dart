import 'package:flutter/material.dart';

import 'todo_store.dart';

/// The `MaterialApp` both example apps run; each passes its own [title] and
/// page.
class TodoExampleApp extends StatelessWidget {
  const TodoExampleApp({super.key, required this.title, required this.home});

  final String title;
  final Widget home;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: title,
    theme: ThemeData(useMaterial3: true),
    home: home,
  );
}

/// The backend-independent half of an example's todo page: owns the
/// [TodoStore], answers the three `.slint` callbacks, and re-pushes the model
/// after every change.
///
/// The app implements [pushTodos] — the Slint boundary, where entries become
/// its generated `TodoItem` — sets [loadError] if loading fails, and builds
/// through [buildTodoScaffold].
mixin TodoPageStateMixin<T extends StatefulWidget> on State<T> {
  final TodoStore store = TodoStore();

  /// Why the component failed to load; shown instead of the UI.
  Object? loadError;

  /// Hands [items] to the component, mapped to the app's generated type.
  void pushTodos(List<TodoEntry> items);

  /// Pushes the current list and rebuilds (the AppBar counts change too).
  void syncTodos() {
    pushTodos(store.items);
    setState(() {});
  }

  /// The `add-todo` callback.
  void addTodo(String title) {
    if (store.addTodo(title)) syncTodos();
  }

  /// The `toggle-todo` callback.
  void toggleTodo(int index, bool checked) {
    if (store.toggleTodo(index, checked)) syncTodos();
  }

  /// The `remove-done` callback.
  void removeDone() {
    store.removeDone();
    syncTodos();
  }

  /// The page chrome: the count title for [backend] over [loadError] if
  /// loading failed, else [body] (only called when there is no error).
  Widget buildTodoScaffold({
    required String backend,
    required Widget Function() body,
  }) => Scaffold(
    appBar: AppBar(title: Text(store.countTitle(backend))),
    body: loadError != null ? Center(child: Text('$loadError')) : body(),
  );
}
