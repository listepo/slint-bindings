import 'package:test/test.dart';
import 'package:todo_example/todo.aot.g.dart' as aot;
import 'package:todo_example/todo.g.dart';

/// The same generated wrapper as `todo_typed_test.dart`, driven by the AOT
/// backend instead. Its dylib is bundled only for release/profile builds, so
/// under `flutter test` (always debug) the code asset is absent and the first
/// FFI call throws — skip instead of failing; `flutter build --release`
/// covers this path.
TodoApp? _createOrSkip() {
  try {
    return TodoApp.create(aot.todoAppFactory);
  } on ArgumentError catch (e) {
    markTestSkipped('AOT dylib is bundled only in release/profile builds: $e');
    return null;
  }
}

void main() {
  test('creates TodoApp from the AOT-compiled component', () {
    final app = _createOrSkip();
    if (app == null) return;
    app.dispose();
  });

  test('todo-model roundtrips as generated struct values', () {
    final app = _createOrSkip();
    if (app == null) return;

    app.todoModel.replaceAll(const [
      TodoItem(title: 'buy milk', checked: false),
      TodoItem(title: 'ship demo', checked: true),
    ]);

    expect(app.todoModel, const [
      TodoItem(title: 'buy milk', checked: false),
      TodoItem(title: 'ship demo', checked: true),
    ]);

    app.dispose();
  });

  test('callbacks fire with typed, named arguments', () {
    final app = _createOrSkip();
    if (app == null) return;

    String? added;
    (int, bool)? toggled;
    var removedDone = false;
    app.onAddTodo((title) => added = title);
    app.onToggleTodo((index, checked) => toggled = (index, checked));
    app.onRemoveDone(() => removedDone = true);

    app.invokeAddTodo('write tests');
    expect(added, 'write tests');

    app.invokeToggleTodo(1, true);
    expect(toggled, (1, true));

    app.invokeRemoveDone();
    expect(removedDone, isTrue);

    app.dispose();
  });

  test('renders to pixels', () {
    final app = _createOrSkip();
    if (app == null) return;
    final target = app.renderTarget;

    app.todoModel.replaceAll(const [
      TodoItem(title: 'test todo', checked: false),
    ]);
    target.resize(400, 300);

    expect(target.render(), isTrue);
    expect(target.pixels.length, 400 * 300 * 4);
    expect(
      target.pixels.any((b) => b != 0),
      isTrue,
      reason: 'rendered frame should not be fully transparent black',
    );

    app.dispose();
  });
}
