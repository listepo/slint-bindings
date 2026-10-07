import 'package:slint_interpreter/slint_interpreter.dart';
import 'package:test/test.dart';
import 'package:todo_example/todo.g.dart';

/// The generated typed wrapper driven by the interpreter backend: the
/// `.slint` source embedded in `todo.g.dart` is compiled at runtime, so this
/// runs under plain `flutter test` (always debug).
void main() {
  late SlintInterpreterFactory factory;

  setUp(
    () => factory = SlintInterpreterFactory(
      TodoApp.slintSource,
      files: TodoApp.slintFiles,
    ),
  );
  tearDown(() => factory.dispose());

  test('create() defaults to the interpreter in debug builds', () {
    // No factory passed: the generated defaultFactory follows the build mode,
    // and `flutter test` is always debug. Do not dispose it — it is shared.
    expect(TodoApp.defaultFactory, isA<SlintInterpreterFactory>());
    final app = TodoApp.create();
    expect(app.component, isA<InterpreterSlintComponent>());
    app.dispose();
  });

  test('creates TodoApp from the embedded source', () {
    final app = TodoApp.create(factory);
    expect(app.component, isA<InterpreterSlintComponent>());
    app.dispose();
  });

  test('todo-model roundtrips as generated struct values', () {
    final app = TodoApp.create(factory);

    app.todoModel.replaceAll(const [
      TodoItem(title: 'buy milk', checked: false),
      TodoItem(title: 'ship demo', checked: true),
    ]);

    // The struct class carries value equality, so the whole list compares.
    expect(app.todoModel, const [
      TodoItem(title: 'buy milk', checked: false),
      TodoItem(title: 'ship demo', checked: true),
    ]);

    app.dispose();
  });

  test('callbacks fire with typed, named arguments', () {
    final app = TodoApp.create(factory);

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
    final app = TodoApp.create(factory);
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

  test('rejects a component the source does not export', () {
    expect(
      () => factory.instantiate('NoSuchComponent'),
      throwsA(isA<StateError>()),
    );
  });
}
