import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:slint/slint.dart';
import 'package:slint_patrol/slint_patrol.dart';
import 'package:todo_example/main.dart';
import 'package:todo_example/todo.g.dart';
import 'package:todo_shared/todo_shared.dart';

/// End to end through the app's own page: taps and typing land on the shared
/// `TodoView` (examples/todo_shared/ui/todo_view.slint) the way a user's
/// would, and the state is read back through the generated `TodoApp` — typed,
/// never by property name.
void main() {
  setUp(TodoApp.register);
  tearDown(() => SlintComponent.unregister(TodoApp.assetPath));

  Future<TodoApp> pumpApp(PatrolTester $) async {
    await $.pumpWidget(const TodoExampleApp(title: 'test', home: TodoPage()));
    await $.slintSettle();
    return TodoApp($.slintComponent());
  }

  List<String> titles(TodoApp app) => [for (final t in app.todoModel) t.title];

  patrolWidgetTest('adds, checks and removes a todo through the real UI', (
    $,
  ) async {
    final app = await pumpApp($);
    final before = titles(app);

    await $.slintById('TodoView::edit').enterText('buy milk');
    await $.slint('Add').tap();
    await $.slintSettle();
    expect(titles(app), [...before, 'buy milk']);
    expect(app.todoModel.last.checked, isFalse);

    // The label matches the CheckBox and the Text inside it; the CheckBox
    // comes first.
    await $.slint('buy milk').first.tap();
    await $.slintSettle();
    expect(
      app.todoModel.last.checked,
      isTrue,
      reason: 'the checkbox toggled through the shared view',
    );

    await $.slint('Remove done items').tap();
    await $.slintSettle();
    expect(titles(app), isNot(contains('buy milk')));
    expect(app.todoModel.where((t) => t.checked), isEmpty);
  });

  patrolWidgetTest('an empty title adds nothing', ($) async {
    final app = await pumpApp($);
    final before = titles(app);

    await $.slint('Add').tap();
    await $.slintSettle();
    expect(titles(app), before);
  });
}
