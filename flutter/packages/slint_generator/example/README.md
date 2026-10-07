# slint_generator example

`build_runner` turns each `ui/<name>.slint` into `lib/<name>.g.dart`: one typed
class per exported component (properties, callbacks, render target) and one
value class per named struct. The full app is
[`examples/todo`](https://github.com/listepo/slint_dart/tree/main/examples/todo).

```yaml
# pubspec.yaml
dependencies:
  slint: ^0.0.1
  slint_generator: ^0.0.1
  slint_interpreter: ^0.0.1   # or slint_compiler for the AOT backend
dev_dependencies:
  build_runner: ^2.16.0
```

```yaml
# build.yaml — build_runner scans lib/ by default; .slint files live in ui/
targets:
  $default:
    sources:
      - lib/**
      - ui/**
      - pubspec.yaml
      - $package$
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

```dart
import 'package:slint/slint.dart';

import 'todo.g.dart';

void startup() {
  TodoApp.register();                                        // once, at startup
  final TodoApp app = SlintComponent.load('ui/todo.slint');  // or TodoApp.assetPath
  final same = TodoApp.load('ui/todo.slint');                // no registry needed
  final explicit = TodoApp.create(SlintInterpreterFactory(TodoApp.slintSource));
}
```
