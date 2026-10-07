import 'package:slint_generator/slint_generator.dart';
import 'package:test/test.dart';

/// Slint spells names in kebab-case, Dart in camel/Pascal, Rust in snake, and
/// the C ABI in snake with a prefix. Every generated symbol runs through these,
/// so a change here silently renames the whole generated surface.
void main() {
  group('camelCase', () {
    test('joins kebab segments', () {
      expect(camelCase('todo-model'), 'todoModel');
      expect(camelCase('remove-done-items'), 'removeDoneItems');
    });

    test('leaves a single segment alone', () {
      expect(camelCase('title'), 'title');
    });

    test('ignores empty segments from stray dashes', () {
      expect(camelCase('todo--model'), 'todoModel');
      expect(camelCase('-leading'), 'leading');
      expect(camelCase('trailing-'), 'trailing');
    });

    test('returns the input when there is nothing to join', () {
      expect(camelCase(''), '');
      expect(camelCase('-'), '-');
    });
  });

  group('pascalCase', () {
    test('capitalises every segment', () {
      expect(pascalCase('add-todo'), 'AddTodo');
      expect(pascalCase('toggle'), 'Toggle');
    });

    test('ignores empty segments', () {
      expect(pascalCase('add--todo'), 'AddTodo');
    });
  });

  group('snakeFromPascal', () {
    test('splits on capitals', () {
      expect(snakeFromPascal('TodoApp'), 'todo_app');
      expect(snakeFromPascal('A'), 'a');
    });

    test('does not lead with an underscore', () {
      expect(snakeFromPascal('Todo').startsWith('_'), isFalse);
    });

    test('treats digits as non-capitals', () {
      expect(snakeFromPascal('Todo2App'), 'todo2_app');
    });

    test('normalises dashes to underscores', () {
      expect(snakeFromPascal('todo-app'), 'todo_app');
    });
  });

  test('rustIdent turns dashes into underscores', () {
    expect(rustIdent('todo-model'), 'todo_model');
    expect(rustIdent('title'), 'title');
  });

  group('aotFactoryName', () {
    test('names the factory slint_compiler generates', () {
      expect(aotFactoryName('TodoApp'), 'todoAppFactory');
      expect(aotFactoryName('Main'), 'mainFactory');
    });

    test('agrees with the C symbol prefix for the same component', () {
      // Both derive from snakeFromPascal; if one changes, the wrapper stops
      // referring to the factory the AOT backend actually declares.
      expect(
        aotFactoryName('TodoApp'),
        '${camelCase(snakeFromPascal('TodoApp').replaceAll('_', '-'))}Factory',
      );
    });
  });
}
