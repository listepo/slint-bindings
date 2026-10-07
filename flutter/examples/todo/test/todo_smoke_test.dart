import 'dart:io';

import 'package:slint_interpreter/slint_interpreter.dart';
import 'package:test/test.dart';
import 'package:todo_example/todo.g.dart';

/// The interpreter backend under the generated wrapper, against
/// `ui/todo.slint`: compile, instantiate, model round-trip, callbacks, pixels.
/// The raw instance goes straight into `TodoApp`; nothing here touches Slint
/// by property or callback name.
void main() {
  // Compiled at its real path, so its import of the shared list UI resolves.
  final file = File('ui/todo.slint').absolute;
  final source = file.readAsStringSync();
  late InterpreterSlintEngine engine;
  late List<InterpreterSlintComponentDefinition> defs;

  setUp(() {
    engine = InterpreterSlintEngine();
    defs = engine.compile(source, path: file.path);
  });
  tearDown(() {
    for (final d in defs) {
      d.dispose();
    }
    engine.dispose();
  });

  // The compiler hands components back unordered: select by name.
  TodoApp todoApp() => TodoApp(
    defs.firstWhere((d) => d.name == TodoApp.componentName).instantiate(),
  );

  test('compiles todo.slint', () {
    expect([
      for (final d in defs) d.name,
    ], containsAll(['TodoApp', 'UnusedGadget']));
  });

  test('instantiates and syncs model', () {
    final app = todoApp();
    addTearDown(app.dispose);

    const items = [
      TodoItem(title: 'buy milk', checked: false),
      TodoItem(title: 'ship demo', checked: true),
    ];
    app.todoModel.replaceAll(items);
    expect(app.todoModel, items);
  });

  test('invokes callbacks', () {
    final app = todoApp();
    addTearDown(app.dispose);

    final received = <String>[];
    app.onAddTodo(received.add);
    app.invokeAddTodo('from test');
    expect(received, ['from test']);
  });

  test('renders to pixels', () {
    final app = todoApp();
    addTearDown(app.dispose);

    final target = app.renderTarget;
    target.resize(400, 600);
    expect(target.render(), isTrue);

    final pixels = target.pixels;
    expect(pixels.length, 400 * 600 * 4);
    expect(
      pixels.any((b) => b != 0),
      isTrue,
      reason: 'frame should have content',
    );
  });
}
