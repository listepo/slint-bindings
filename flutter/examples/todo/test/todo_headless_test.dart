import 'package:slint_testing/slint_testing.dart';
import 'package:test/test.dart';
import 'package:todo_example/todo.g.dart';

/// The generated `TodoApp` over `slint_testing`'s headless backend — no
/// window, no renderer: the UI is driven through its accessibility tree, and
/// everything the test reads or handles goes through the wrapper's typed
/// members, never a Slint name.
void main() {
  late SlintTestApp ui;
  late TodoApp app;

  setUp(() {
    ui = SlintTestApp.compile(
      TodoApp.slintSource,
      component: TodoApp.componentName,
      files: TodoApp.slintFiles,
    );
    app = TodoApp(ui);
  });
  tearDown(() => app.dispose());

  Map<String?, bool?> rows() => {
    for (final box in ui.findByType('CheckBox')) box.label: box.checked,
  };

  test('the typed model is what the list shows', () {
    app.todoModel.replaceAll(const [
      TodoItem(title: 'buy milk', checked: false),
      TodoItem(title: 'walk the dog', checked: true),
    ]);
    expect(rows(), {'buy milk': false, 'walk the dog': true});
    expect(
      app.todoModel.last,
      const TodoItem(title: 'walk the dog', checked: true),
    );
  });

  test('typing a title and pressing Add reaches onAddTodo', () {
    final added = <String>[];
    app.onAddTodo(added.add);
    ui.findById('TodoView::edit').single.setValue('buy milk');
    ui.findByLabel('Add').single.click();
    expect(added, ['buy milk']);
  });

  test('ticking a row reports its index and new state to onToggleTodo', () {
    app.todoModel.replaceAll(const [
      TodoItem(title: 'a', checked: false),
      TodoItem(title: 'b', checked: false),
    ]);
    final toggled = <(int, bool)>[];
    app.onToggleTodo((index, checked) => toggled.add((index, checked)));
    ui.findByType('CheckBox').firstWhere((box) => box.label == 'b').click();
    expect(toggled, [(1, true)]);
  });

  test('Remove done items reaches onRemoveDone', () {
    var removed = 0;
    app.onRemoveDone(() => removed++);
    ui.findByLabel('Remove done items').single.click();
    expect(removed, 1);
  });

  test('the wrapper has no render target over a headless backend', () {
    expect(() => app.renderTarget, throwsStateError);
  });
}
