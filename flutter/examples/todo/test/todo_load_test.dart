import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slint/slint.dart';
import 'package:todo_example/todo.g.dart';

/// `SlintComponent.load('ui/todo.slint')` is the one-call path from a `.slint`
/// file to something on screen once `TodoApp.register()` has run: synchronous,
/// and backed by the source the builder captured, so nothing has to be bundled
/// — see the `flutter:` section of `pubspec.yaml`. What it returns is always
/// the generated wrapper, never an untyped component.
void main() {
  setUp(TodoApp.register);

  Future<void> pumpTarget(WidgetTester tester, SlintSoftwareRenderTarget t) =>
      tester.pumpWidget(MaterialApp(home: SlintView(target: t)));

  // SlintView renders every frame off a Ticker, so the tree is never
  // quiescent and pumpAndSettle would spin until it times out.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets(
    'SlintComponent.load renders a TodoApp without naming a backend',
    (tester) async {
      final TodoApp app = SlintComponent.load('ui/todo.slint');
      addTearDown(app.dispose);

      await pumpTarget(tester, app.renderTarget);
      await pumpFrames(tester);

      expect(find.byType(SlintView), findsOneWidget);
      expect(
        app.renderTarget.pixels.any((b) => b != 0),
        isTrue,
        reason: 'the loaded component should have drawn something',
      );
    },
  );

  testWidgets('the loaded component is live, not just pixels', (tester) async {
    final app = SlintComponent.load<TodoApp>(TodoApp.assetPath);
    addTearDown(app.dispose);

    final added = <String>[];
    app.onAddTodo(added.add);
    app.todoModel.replaceAll(const [
      TodoItem(title: 'from the source', checked: false),
    ]);

    await pumpTarget(tester, app.renderTarget);
    await pumpFrames(tester);

    expect(app.todoModel.single.title, 'from the source');
    app.invokeAddTodo('buy milk');
    expect(added, ['buy milk']);
  });

  test('registration is per component: UnusedGadget stays out', () {
    // Registering the file's every wrapper would give UnusedGadget's AOT
    // factory a recorded use and defeat tree-shaking — so only TodoApp is
    // registered, and the path resolves to it without naming a component.
    expect(SlintComponent.load('ui/todo.slint'), isA<TodoApp>());
    expect(
      () => SlintComponent.load('ui/todo.slint', component: 'UnusedGadget'),
      throwsArgumentError,
    );

    SlintComponent.unregister('ui/todo.slint');
    expect(() => SlintComponent.load('ui/todo.slint'), throwsStateError);
  });

  test('TodoApp.load answers to the ui/ path it was generated from', () {
    expect(TodoApp.assetPath, 'ui/todo.slint');
    expect(
      () => TodoApp.load('ui/other.slint'),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('generated from'),
        ),
      ),
    );
  });

  test('either load accepts only a .slint file', () {
    for (final notSlint in [
      'ui/todo.txt',
      'ui/todo.slint.bak',
      'ui/todo',
      'ui/',
      '',
    ]) {
      expect(
        () => TodoApp.load(notSlint),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.message, 'message', 'not a .slint file')
              .having((e) => e.invalidValue, 'value', notSlint),
        ),
        reason: notSlint,
      );
      expect(
        () => SlintComponent.load(notSlint),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'not a .slint file',
          ),
        ),
        reason: notSlint,
      );
    }
    TodoApp.load('ui/todo.slint').dispose();
    SlintComponent.load('ui/todo.slint').dispose();
  });

  testWidgets('nothing reads the bundle unless a path says so', (tester) async {
    // The whole point of the default: no asset is declared, so a wrapper that
    // reached for one would fail here rather than in someone's release build.
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (message) async {
        reads++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        null,
      ),
    );

    SlintComponent.load('ui/todo.slint').dispose();
    TodoApp.load('ui/todo.slint').dispose();
    expect(reads, 0);
  });
}
