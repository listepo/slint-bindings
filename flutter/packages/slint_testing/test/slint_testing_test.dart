import 'dart:async';
import 'dart:convert';

import 'package:slint/slint_core.dart';
import 'package:slint_testing/slint_testing.dart';
import 'package:test/test.dart';

// The dynamic layer under test is keyed by Slint name, so these tests are
// too. App code never is: it wraps a SlintTestApp in its generated wrapper
// (examples/todo/test/todo_headless_test.dart).
const _source = '''
import { Button, CheckBox, LineEdit } from "std-widgets.slint";

export component Form inherits Window {
    in-out property <string> title-text: "untitled";
    in property <bool> saved: false;
    callback save(name: string);
    callback reset();
    callback shout(text: string) -> string;

    VerticalLayout {
        edit := LineEdit {
            placeholder-text: "Name it";
            text: root.title-text;
        }
        agree := CheckBox {
            text: "I agree";
            checked: false;
        }
        Button {
            text: "Save";
            clicked => { root.save(edit.text); }
        }
        Button {
            text: "Reset";
            clicked => { root.reset(); }
        }
    }
}

export component Other inherits Window {
    Text { text: "other"; }
}
''';

void main() {
  late SlintTestApp app;

  setUp(() => app = SlintTestApp.compile(_source, component: 'Form'));
  tearDown(() => app.dispose());

  group('compile', () {
    test('a lone exported component needs no name', () {
      final only = SlintTestApp.compile(
        'export component Only inherits Window { Text { text: "hi"; } }',
      );
      addTearDown(only.dispose);
      expect(only.findAll(), isNotEmpty);
    });

    test('asks which component to test when the source exports several', () {
      expect(
        () => SlintTestApp.compile(_source),
        throwsA(
          isA<SlintTestException>().having(
            (e) => e.message,
            'message',
            contains('Form, Other'),
          ),
        ),
      );
    });

    test('names the components it did find when the wanted one is missing', () {
      expect(
        () => SlintTestApp.compile(_source, component: 'Nope'),
        throwsA(
          isA<SlintTestException>().having(
            (e) => e.message,
            'message',
            contains('Form'),
          ),
        ),
      );
    });

    test('reports compile errors', () {
      expect(
        () => SlintTestApp.compile('export component Broken { syntax('),
        throwsA(isA<SlintTestException>()),
      );
    });

    test('imports resolve through files, as a generated wrapper embeds them', () {
      final imported = SlintTestApp.compile(
        'import { Greeting } from "../parts/greeting.slint";\n'
        'export component Main inherits Window { Greeting {} }',
        files: {
          '../parts/greeting.slint': base64Encode(
            utf8.encode(
              'export component Greeting { Text { text: "from an import"; } }',
            ),
          ),
        },
      );
      addTearDown(imported.dispose);
      expect(imported.findByLabel('from an import'), isNotEmpty);
    });
  });

  group('queries', () {
    test('findByLabel matches the user-visible text', () {
      final save = app.findByLabel('Save');
      expect(save, hasLength(1));
      expect(save.single.role, 'Button');
    });

    test('findById uses component-qualified ids', () {
      expect(app.findById('Form::agree'), hasLength(1));
      expect(app.findById('Form::nonexistent'), isEmpty);
    });

    test('findByType matches the widget type', () {
      expect(app.findByType('Button'), hasLength(2));
    });

    test('findByRole filters the whole tree', () {
      expect(
        app.findByRole('Button').map((e) => e.label),
        containsAll(['Save', 'Reset']),
      );
      // A widget repeats its role on the inner elements that implement it, so
      // match the checkbox itself rather than counting the hits.
      expect(
        app.findByRole('Checkbox').map((e) => e.id),
        contains('Form::agree'),
      );
    });

    test('findAll descends into the widgets themselves', () {
      final all = app.findAll();
      expect(all.map((e) => e.typeName), contains('LineEdit'));
      // Not only the elements the component wrote: the tree continues into
      // each widget's own implementation.
      expect(all.map((e) => e.id), contains('LineEditBase::text-input'));
    });

    test('elements expose accessible state', () {
      final agree = app.findById('Form::agree').single;
      expect(agree.label, 'I agree');
      expect(agree.checked, isFalse);
      expect(agree.checkable, isTrue);
      expect(agree.enabled, isTrue);
      expect(app.findById('Form::edit').single.placeholder, 'Name it');
    });
  });

  group('interaction', () {
    test('click toggles a checkbox', () {
      expect(app.findById('Form::agree').single.checked, isFalse);
      app.findById('Form::agree').single.click();
      expect(app.findById('Form::agree').single.checked, isTrue);
    });

    test('click runs the handler of the callback the button is wired to', () {
      var resets = 0;
      app.setCallbackHandler('reset', (_) {
        resets++;
        return null;
      });
      app.findByLabel('Reset').single.click();
      expect(resets, 1);
    });

    test('setValue types into a text input, and the handler sees it', () {
      final saved = <List<Object?>>[];
      app.setCallbackHandler('save', (args) {
        saved.add(args);
        return null;
      });
      app.findById('Form::edit').single.setValue('a title');
      app.findByLabel('Save').single.click();
      expect(saved, [
        ['a title'],
      ]);
    });

    test('an element from a superseded query refuses to act', () {
      final save = app.findByLabel('Save').single;
      app.findByLabel('Reset'); // replaces the snapshot `save` indexes into
      expect(save.click, throwsA(isA<SlintTestException>()));
    });
  });

  group('SlintComponent', () {
    test('is one, so a generated wrapper can wrap it', () {
      expect(app, isA<SlintComponent>());
    });

    test('properties round-trip through the JSON bridge', () {
      app.setProperty('title-text', 'from the test');
      expect(app.getProperty('title-text'), 'from the test');
      expect(app.findById('Form::edit').single.value, 'from the test');
    });

    test("a handler's result is the callback's result", () {
      app.setCallbackHandler(
        'shout',
        (args) => (args.single as String).toUpperCase(),
      );
      expect(app.invokeCallback('shout', ['hi']), 'HI');
    });

    test('a handler without a result yields the declared default', () {
      app.setCallbackHandler('shout', (_) => null);
      expect(app.invokeCallback('shout', ['hi']), '');
    });

    test('a throwing handler reports to the zone and yields the default', () {
      app.setCallbackHandler('shout', (_) => throw StateError('handler bug'));
      final errors = <Object>[];
      Object? result;
      runZonedGuarded(
        () => result = app.invokeCallback('shout', ['hi']),
        (e, _) => errors.add(e),
      );
      expect(result, '');
      expect(errors, [
        isA<StateError>().having((e) => e.message, 'message', 'handler bug'),
      ]);
    });

    test('a later handler replaces the earlier one', () {
      app.setCallbackHandler('shout', (_) => 'first');
      app.setCallbackHandler('shout', (_) => 'second');
      expect(app.invokeCallback('shout', ['hi']), 'second');
    });

    test('setCallbackHandler from inside invokeCallback', () {
      app.setCallbackHandler('shout', (args) {
        app.setCallbackHandler('shout', (_) => 'NEW');
        return (args.single as String).toUpperCase();
      });
      expect(app.invokeCallback('shout', ['hi']), 'HI');
      expect(app.invokeCallback('shout', ['hi']), 'NEW');
    });

    test('an unknown property is an error, not a silent null', () {
      expect(() => app.getProperty('nope'), throwsA(isA<SlintTestException>()));
    });

    test('an unknown callback is an error', () {
      expect(
        () => app.setCallbackHandler('nope', (_) => null),
        throwsA(isA<SlintTestException>()),
      );
    });
  });

  group('lifecycle', () {
    test('dispose is idempotent and blocks later use', () {
      final other = SlintTestApp.compile(_source, component: 'Other');
      other.dispose();
      other.dispose();
      expect(other.findAll, throwsA(isA<SlintTestException>()));
    });

    test('a handler that disposes the app mid-click does not crash', () {
      final form = SlintTestApp.compile(_source, component: 'Form');
      form.setCallbackHandler('reset', (_) {
        form.dispose();
        return null;
      });
      form.findByLabel('Reset').single.click();
      expect(form.findAll, throwsA(isA<SlintTestException>()));
    });

    test('mock time advances without real waiting', () {
      // No animation to observe here; the point is that it is callable and
      // does not wall-clock wait.
      final start = DateTime.now();
      app.elapse(const Duration(seconds: 5));
      expect(
        DateTime.now().difference(start),
        lessThan(const Duration(seconds: 1)),
      );
    });
  });
}
