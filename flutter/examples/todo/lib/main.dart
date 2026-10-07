import 'package:flutter/material.dart';
import 'package:slint/slint.dart';
import 'package:todo_shared/todo_shared.dart';

import 'todo.g.dart';

// The app names its UI by the `.slint` path and never a backend:
// `SlintComponent.load('ui/todo.slint')` returns the `TodoApp` registered
// below, built through the generated `defaultFactory`, which follows the
// build mode exactly like the hooks that decide which dylib ships —
// interpreter in debug, AOT in release/profile. Debug compiles the source
// todo.g.dart embeds; release has it compiled into the AOT dylib and carries
// no copy of the text. ui/todo.slint is not a Flutter asset, so the UI source
// stays out of the shipped bundle either way.

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Per component, on purpose: UnusedGadget is never registered, so it is
  // tree-shaken out of the release build.
  TodoApp.register();
  runApp(const TodoExampleApp(title: 'Slint Todo', home: TodoPage()));
}

class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

// The list, its callbacks and the page chrome live in examples/todo_shared;
// this page loads the component and maps entries to the generated TodoItem
// at the Slint boundary.
class _TodoPageState extends State<TodoPage> with TodoPageStateMixin {
  TodoApp? _app;

  @override
  void initState() {
    super.initState();
    // Synchronous in both modes: the interpreter compiles the embedded source
    // in one FFI call, and AOT only creates the instance — so the UI is
    // ready before the first build, with no loading state to render.
    try {
      _app = SlintComponent.load('ui/todo.slint')
        ..onAddTodo(addTodo)
        ..onToggleTodo(toggleTodo)
        ..onRemoveDone(removeDone);
      syncTodos();
    } catch (e) {
      loadError = e;
    }
  }

  @override
  void pushTodos(List<TodoEntry> items) {
    _app!.todoModel.replaceAll([
      for (final e in items) TodoItem(title: e.title, checked: e.checked),
    ]);
  }

  @override
  void dispose() {
    // The interpreter engine behind TodoApp.defaultFactory is process-wide and
    // shared, so it outlives this widget deliberately.
    _app?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildTodoScaffold(
    backend: '${TodoApp.defaultFactory.runtimeType}',
    body: () => SlintView(target: _app!.renderTarget),
  );
}
