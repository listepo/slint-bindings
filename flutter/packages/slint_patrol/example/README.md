# slint_patrol example

Finds elements in the live component's accessibility tree and acts through
real Flutter gestures, so one Patrol test can drive Flutter widgets and Slint
elements alike. State is read back through the generated wrapper, never by
Slint property name.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:slint/slint.dart';
import 'package:slint_patrol/slint_patrol.dart';

import 'package:my_app/main.dart';   // MyApp, which loads ui/todo.slint
import 'package:my_app/todo.g.dart'; // the wrapper generated from it

void main() {
  setUp(TodoApp.register); // what main() does before runApp
  tearDown(() => SlintComponent.unregister(TodoApp.assetPath));

  patrolWidgetTest('adding a todo', ($) async {
    await $.pumpWidget(const MyApp());
    await $.slintSettle(); // not pumpAndSettle: SlintView renders every frame

    await $.slintById('TodoView::edit').enterText('buy milk');
    await $.slint('Add').tap();
    await $.slintSettle();

    final app = TodoApp($.slintComponent());
    expect(app.todoModel.last.title, 'buy milk');
  });
}
```
