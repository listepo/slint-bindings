# slint example

`slint` is the core every backend builds on: a `.slint` UI is loaded by its
path and shown in a `SlintView`. The typed `TodoApp` below is generated from
`ui/todo.slint` by `slint_generator`; the backend follows the build mode
(`slint_interpreter` in debug, `slint_compiler` in release). The full app is
[`examples/todo`](https://github.com/listepo/slint_dart/tree/main/examples/todo).

```dart
import 'package:flutter/material.dart';
import 'package:slint/slint.dart';

import 'todo.g.dart'; // generated from ui/todo.slint

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  TodoApp.register(); // once per component, at startup

  final TodoApp app = SlintComponent.load('ui/todo.slint')
    ..onAddTodo((title) => debugPrint('add $title'));

  runApp(MaterialApp(
    home: Scaffold(body: SlintView(target: app.renderTarget)),
  ));
}
```

`load` is synchronous in both modes, so it is safe in `initState` with no
loading state. `SlintView` forwards pointer, keyboard and text input to Slint.
