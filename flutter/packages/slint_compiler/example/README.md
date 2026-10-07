# slint_compiler example

Release and profile builds compile every `ui/*.slint` ahead of time into the
app's own native code asset; debug keeps the interpreter. The full app is
[`examples/todo`](https://github.com/listepo/slint_dart/tree/main/examples/todo).

```yaml
# pubspec.yaml of the app
dependencies:
  hooks: ^2.2.0      # hook/{build,link}.dart run without dev deps
  meta: ^1.19.0      # @RecordUse in the generated *.aot.g.dart
  slint: ^0.0.1
  slint_compiler: ^0.0.1
  slint_generator: ^0.0.1
  slint_interpreter: ^0.0.1   # the debug-mode backend

dev_dependencies:
  build_runner: ^2.16.0
```

```dart
// hook/build.dart — AOT-compiles ui/**.slint with slint-build
import 'package:hooks/hooks.dart';
import 'package:slint_compiler/aot_build.dart';

void main(List<String> args) => build(args, buildSlintAot);
```

```dart
// hook/link.dart — links only the components Dart code actually uses
import 'package:hooks/hooks.dart';
import 'package:slint_compiler/aot_link.dart';

void main(List<String> args) => link(args, linkSlintAot);
```

```bash
dart run build_runner build          # ui/todo.slint → lib/todo.g.dart + lib/todo.aot.g.dart
FLUTTER_RECORD_USE=true flutter build macos --release   # tree-shakes unused components
```

App code does not change between modes: `SlintComponent.load('ui/todo.slint')`
returns the AOT-compiled component in release and the interpreted one in debug.
