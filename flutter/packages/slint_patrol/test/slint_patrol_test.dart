import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:slint/slint.dart';
import 'package:slint_interpreter/slint_interpreter.dart';
import 'package:slint_patrol/slint_patrol.dart';

const _source = '''
import { Button, CheckBox, LineEdit } from "std-widgets.slint";

export component Form inherits Window {
    in-out property <string> typed: "";
    in-out property <int> taps: 0;

    VerticalLayout {
        edit := LineEdit {
            placeholder-text: "Name it";
            edited => { root.typed = self.text; }
        }
        agree := CheckBox { text: "I agree"; }
        Button {
            text: "Save";
            clicked => { root.taps += 1; }
        }
    }
}
''';

/// Compiles the source with the interpreter backend and returns the live
/// component — the same one a debug build of a real app would run.
SlintSoftwareComponent _liveComponent([
  String source = _source,
  String name = 'Form',
]) {
  final engine = InterpreterSlintEngine();
  final defs = engine.compile(source, path: 'test.slint');
  final def = defs.firstWhere((d) => d.name == name);
  return def.instantiate() as SlintSoftwareComponent;
}

void main() {
  late SlintSoftwareComponent component;

  setUp(() => component = _liveComponent());
  tearDown(() => component.dispose());

  Widget app() => MaterialApp(
    home: Scaffold(body: SlintView(target: component.renderTarget)),
  );

  patrolWidgetTest('finds a Slint element by its label', ($) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    final save = await $.slint('Save').resolve();
    expect(save.role, 'Button');
    expect(
      save.hasSize,
      isTrue,
      reason: 'geometry comes from layout, so it must be non-zero',
    );
  });

  patrolWidgetTest('tapping drives the real component', ($) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    expect(component.getProperty('taps'), 0);
    await $.slint('Save').tap();
    expect(
      component.getProperty('taps'),
      1,
      reason: 'a Flutter gesture at the element should reach Slint',
    );
  });
  patrolWidgetTest('tapping still hits at device pixel ratio 2', ($) async {
    await $.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2.0),
          child: Scaffold(body: SlintView(target: component.renderTarget)),
        ),
      ),
    );
    await $.slintSettle();

    expect(component.getProperty('taps'), 0);
    await $.slint('Save').tap();
    expect(
      component.getProperty('taps'),
      1,
      reason: 'patrol divides Slint geometry by DPR; taps must still land',
    );
  });

  patrolWidgetTest('a tap lands on the element it names, not a neighbour', (
    $,
  ) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    expect($.slintById('Form::agree').current.single.checked, isFalse);
    await $.slintById('Form::agree').tap();

    expect($.slintById('Form::agree').current.single.checked, isTrue);
    expect(
      component.getProperty('taps'),
      0,
      reason: 'the button must not have been hit instead',
    );
  });

  patrolWidgetTest('typing goes through the widget input path', ($) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    await $.slintById('Form::edit').enterText('milk');

    expect(component.getProperty('typed'), 'milk');
    expect($.slintById('Form::edit').current.single.value, 'milk');

    await $.slintById('Form::edit').enterText('bread');
    expect(component.getProperty('typed'), 'bread');
    expect($.slintById('Form::edit').current.single.value, 'bread');
  });

  patrolWidgetTest('queries by id, type, and role', ($) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    expect($.slintById('Form::agree').count, 1);
    expect($.slintByType('Button').count, 1);
    expect($.slintByRole('Button').current.single.label, 'Save');
    expect(
      $.slintAll().count,
      greaterThan(4),
      reason: 'the tree includes the widgets own internals',
    );
  });

  patrolWidgetTest('component properties are readable through the tester', (
    $,
  ) async {
    await $.pumpWidget(app());
    await $.slintSettle();

    $.slintComponent().setProperty('taps', 7);
    expect($.slintComponent().getProperty('taps'), 7);
  });

  group('failure messages', () {
    patrolWidgetTest('a missing element says so', ($) async {
      await $.pumpWidget(app());
      await $.slintSettle();

      // Caught rather than matched with `throwsA`: resolving pumps frames,
      // and those pumps have to run in the test's own async flow.
      Object? caught;
      try {
        await $.slint('Nope').resolve(timeout: const Duration(seconds: 1));
      } catch (error) {
        caught = error;
      }
      expect(
        caught,
        isA<SlintPatrolException>().having(
          (e) => e.message,
          'message',
          contains('Nope'),
        ),
      );
    });

    patrolWidgetTest('an ambiguous match asks you to narrow it', ($) async {
      await $.pumpWidget(app());
      await $.slintSettle();

      // `Text` shows up repeatedly inside the widgets themselves.
      final all = $.slintByType('Text');
      expect(all.count, greaterThan(1));
      await expectLater(
        all.resolve(),
        throwsA(
          isA<SlintPatrolException>().having(
            (e) => e.message,
            'message',
            contains('narrow'),
          ),
        ),
      );
      // ...and narrowing resolves it.
      expect((await all.first.resolve()).typeName, 'Text');
    });

    patrolWidgetTest('no SlintView is a clear error, not a crash', ($) async {
      await $.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(
        () => $.slint('Save').current,
        throwsA(
          isA<SlintPatrolException>().having(
            (e) => e.message,
            'message',
            contains('no SlintView'),
          ),
        ),
      );
    });
  });

  group('callbacks', () {
    Widget viewOf(SlintSoftwareComponent c) => MaterialApp(
      home: Scaffold(body: SlintView(target: c.renderTarget)),
    );

    SlintSoftwareComponent live(String source, String name) {
      final c = _liveComponent(source, name);
      addTearDown(c.dispose); // a second dispose must be a no-op
      return c;
    }

    // Bug 4: a clicked handler that disposes its own component must not free
    // it under the native click, and the view must keep ticking afterwards.
    patrolWidgetTest('a click that disposes the component does not crash', (
      $,
    ) async {
      final c = live('''
import { Button } from "std-widgets.slint";
export component Closer inherits Window {
    callback close();
    Button { text: "Close"; clicked => { root.close(); } }
}
''', 'Closer');
      var closed = 0;
      c.setCallbackHandler('close', (_) {
        closed++;
        c.dispose();
        return null;
      });
      await $.pumpWidget(viewOf(c));
      await $.slintSettle();

      await $.slint('Close').tap();
      await $.slintSettle();

      expect(closed, 1);
      expect(find.byType(SlintView), findsOneWidget);
      expect(() => c.getProperty('x'), throwsStateError);
      expect(c.renderTarget.render(), isFalse);
    });

    // Bug 7: a pure callback's Dart return value is what the UI renders.
    patrolWidgetTest('a pure callback result is rendered', ($) async {
      final c = live('''
export component Fmt inherits Window {
    pure callback format(int) -> string;
    Text { text: format(7); }
}
''', 'Fmt');
      c.setCallbackHandler('format', (args) => args[0] == 7 ? 'seven' : '?');
      await $.pumpWidget(viewOf(c));
      await $.slintSettle();

      expect((await $.slint('seven').resolve()).typeName, 'Text');
    });

    // Bug 7: a clicked handler's value returned through a non-void callback
    // updates the property it is assigned to, and the UI bound to it.
    patrolWidgetTest('a click stores a callback result', ($) async {
      final c = live('''
import { Button } from "std-widgets.slint";
export component Counter inherits Window {
    callback next(int) -> int;
    in-out property <int> value: 1;
    VerticalLayout {
        Text { text: "Value \\{root.value}"; }
        Button { text: "Step"; clicked => { root.value = root.next(root.value); } }
    }
}
''', 'Counter');
      c.setCallbackHandler('next', (args) => (args[0] as int) * 10);
      await $.pumpWidget(viewOf(c));
      await $.slintSettle();

      await $.slint('Step').tap();

      expect(c.getProperty('value'), 10);
      expect((await $.slint('Value 10').resolve()).typeName, 'Text');
    });
  });
}
