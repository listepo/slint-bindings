import 'package:slint/slint.dart';
import 'package:test/test.dart';
import 'package:todo_example/todo.g.dart';

/// Behaviour of the software render target and the property/callback bridge,
/// beyond the happy path in `todo_typed_test.dart`. Runs on whichever backend
/// the build defaults to — the interpreter under `flutter test`.
void main() {
  late TodoApp app;

  setUp(() => app = TodoApp.create());
  tearDown(() => app.dispose());

  group('render target', () {
    test('starts at 0×0, like the Slint window, until resized', () {
      // A default 800×600 buffer would not match the window's size and the
      // renderer would reject it; before resize() there is simply no frame.
      final target = app.renderTarget;
      expect((target.width, target.height), (0, 0));
      expect(target.pixels, isEmpty);
      expect(target.render(), isFalse);
    });

    test('resize reallocates the pixel buffer to match', () {
      final target = app.renderTarget;

      target.resize(320, 240);
      expect(target.width, 320);
      expect(target.height, 240);
      expect(target.pixels.length, 320 * 240 * 4);

      target.resize(64, 48);
      expect(target.width, 64);
      expect(target.height, 48);
      expect(target.pixels.length, 64 * 48 * 4);
    });

    test('resizing to the current size is a no-op', () {
      final target = app.renderTarget..resize(200, 100);
      final before = target.pixels;
      target.resize(200, 100);
      expect(
        identical(target.pixels, before),
        isTrue,
        reason: 'an unchanged size should not reallocate',
      );
    });

    test('render reports whether a frame was actually drawn', () {
      // The software window only redraws when the scene is dirty, so render()
      // is a "did I draw" answer, not a "did it work" one. Callers driving a
      // Flutter repaint depend on the difference.
      final target = app.renderTarget..resize(200, 100);
      expect(target.render(), isTrue, reason: 'first frame is always dirty');
      expect(
        target.render(),
        isFalse,
        reason: 'nothing changed, so nothing is redrawn',
      );
      expect(target.pixels.any((b) => b != 0), isTrue);
    });

    test('a property change makes the next render draw again', () {
      final target = app.renderTarget..resize(200, 100);
      target.render();
      expect(target.render(), isFalse);

      app.todoModel.replaceAll(const [
        TodoItem(title: 'newly added', checked: false),
      ]);
      expect(target.render(), isTrue);
    });

    test('render after dispose reports failure instead of crashing', () {
      final target = app.renderTarget..resize(100, 100);
      target.dispose();
      expect(target.render(), isFalse);
    });

    test('dispose is idempotent', () {
      final target = app.renderTarget;
      target.dispose();
      expect(target.dispose, returnsNormally);
    });
  });

  group('input events', () {
    test('accepts pointer events and keeps rendering', () {
      final target = app.renderTarget..resize(300, 400);
      expect(target.render(), isTrue);

      for (final kind in SlintPointerEventKind.values) {
        target.dispatchPointerEvent(
          SlintPointerEvent(
            kind: kind,
            x: 20,
            y: 30,
            button: SlintPointerButton.left,
          ),
        );
      }

      expect(target.render(), isTrue);
    });

    test('accepts key press and release', () {
      final target = app.renderTarget..resize(300, 400);
      target.dispatchKeyEvent(const SlintKeyEvent(text: 'a', pressed: true));
      target.dispatchKeyEvent(const SlintKeyEvent(text: 'a', pressed: false));
      expect(target.render(), isTrue);
    });

    test('carries scroll deltas', () {
      final target = app.renderTarget..resize(300, 400);
      target.dispatchPointerEvent(
        const SlintPointerEvent(
          kind: SlintPointerEventKind.scroll,
          x: 10,
          y: 10,
          scrollDeltaY: -40,
        ),
      );
      expect(target.render(), isTrue);
    });
  });

  group('property bridge', () {
    test('an empty model roundtrips', () {
      app.todoModel.replaceAll([]);
      expect(app.todoModel, isEmpty);
    });

    test('preserves unicode and quotes in titles', () {
      app.todoModel.replaceAll(const [
        TodoItem(title: r'Slint ♥ "Flutter" \ $5', checked: false),
      ]);
      expect(app.todoModel.single.title, r'Slint ♥ "Flutter" \ $5');
    });

    test('replacing the model drops the previous items', () {
      app.todoModel.replaceAll(const [
        TodoItem(title: 'first', checked: false),
        TodoItem(title: 'second', checked: false),
      ]);
      app.todoModel.replaceAll(const [TodoItem(title: 'only', checked: true)]);

      expect(app.todoModel, const [TodoItem(title: 'only', checked: true)]);
    });

    test('a replaced callback handler supersedes the old one', () {
      var first = 0;
      var second = 0;
      app.onAddTodo((_) => first++);
      app.onAddTodo((_) => second++);

      app.invokeAddTodo('x');
      expect(first, 0, reason: 'the superseded handler should not fire');
      expect(second, 1);
    });

    test('component dispose is idempotent', () {
      app.dispose();
      expect(app.dispose, returnsNormally);
    });
  });
}
