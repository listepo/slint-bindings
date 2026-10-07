import 'package:test/test.dart';
import 'package:todo_shared/todo_shared.dart';

void main() {
  group('TodoEntry', () {
    test('carries value equality', () {
      expect(
        const TodoEntry(title: 'a', checked: false),
        const TodoEntry(title: 'a', checked: false),
      );
      expect(
        const TodoEntry(title: 'a', checked: false),
        isNot(const TodoEntry(title: 'a', checked: true)),
      );
    });
  });

  group('TodoStore', () {
    test('starts from the seed list', () {
      final store = TodoStore();
      expect(store.items, initialTodoEntries);
      expect(store.total, 2);
      expect(store.openCount, 1);
    });

    test('addTodo trims and ignores blank input', () {
      final store = TodoStore();
      expect(store.addTodo('  ship demo  '), isTrue);
      expect(
        store.items.last,
        const TodoEntry(title: 'ship demo', checked: false),
      );

      expect(store.addTodo('   '), isFalse);
      expect(store.total, 3);
    });

    test('toggleTodo bounds-checks', () {
      final store = TodoStore();
      expect(store.toggleTodo(1, true), isTrue);
      expect(store.items[1].checked, isTrue);
      expect(store.openCount, 0);

      expect(store.toggleTodo(-1, true), isFalse);
      expect(store.toggleTodo(store.total, true), isFalse);
      expect(store.total, 2);
    });

    test('removeDone drops only checked rows', () {
      final store = TodoStore();
      store.removeDone();
      expect(store.items, const [
        TodoEntry(title: 'Render this list', checked: false),
      ]);
    });

    test('countTitle formats the AppBar title', () {
      final store = TodoStore();
      expect(store.countTitle('TestBackend'), '1 open / 2 total — TestBackend');
      expect(
        todoCountTitle(open: 0, total: 0, backend: 'TestBackend'),
        '0 open / 0 total — TestBackend',
      );
    });

    test('items is a read-only view', () {
      final store = TodoStore();
      expect(
        () => store.items.add(initialTodoEntries.first),
        throwsUnsupportedError,
      );
    });
  });
}
