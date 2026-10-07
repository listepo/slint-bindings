import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:slint/slint_core.dart';
import 'package:slint_interpreter/slint_interpreter.dart';

const _source = '''
export struct Pair { a: int, b: string }

export component T inherits Window {
    width: 200px;
    height: 200px;
    in-out property <int> taps: 0;
    callback hit();
    pure callback compute(int) -> int;
    pure callback label(int) -> string;
    callback make() -> Pair;
    out property <int> shown: compute(21);
    out property <string> text: label(1);

    TouchArea {
        x: 0; y: 0; width: 100px; height: 100px;
        clicked => { root.taps += 1; root.hit(); }
    }
}

export component U inherits Window {}
''';

List<InterpreterSlintComponentDefinition> _compile(
  InterpreterSlintEngine engine,
) => engine.compile(_source, path: 'test.slint');

InterpreterSlintComponent _instance() {
  final engine = InterpreterSlintEngine();
  final defs = _compile(engine);
  final c = defs.firstWhere((d) => d.name == 'T').instantiate();
  addTearDown(c.dispose);
  return c;
}

/// Clicks the TouchArea (0,0 100x100) through the render target.
void _checkDisposeOnSpawn((SendPort, Object) args) {
  try {
    checkSlintOwnerIsolate(args.$2, 'dispose');
    args.$1.send('ok');
  } on StateError catch (e) {
    args.$1.send(e.message);
  }
}

void _click(InterpreterSlintComponent c) {
  final target = c.renderTarget;
  target.resize(200, 200);
  target.render();
  for (final kind in [SlintPointerEventKind.down, SlintPointerEventKind.up]) {
    target.dispatchPointerEvent(
      SlintPointerEvent(
        kind: kind,
        x: 50,
        y: 50,
        button: SlintPointerButton.left,
      ),
    );
  }
}

void main() {
  group('engine and definition lifecycle', () {
    // Bug 3: a second engine dispose must not double-free.
    test('engine dispose is idempotent', () {
      final engine = InterpreterSlintEngine();
      _compile(engine);
      engine.dispose();
      engine.dispose();
    });

    // Bug 3: compile on a freed engine must throw, not FFI into freed memory.
    test('compile after dispose throws', () {
      final engine = InterpreterSlintEngine()..dispose();
      expect(
        () => _compile(engine),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Engine is disposed',
          ),
        ),
      );
    });

    // Bug 3: definitions and components outlive the engine that made them.
    test('definitions and components survive engine dispose', () {
      final engine = InterpreterSlintEngine();
      final defs = _compile(engine);
      final def = defs.firstWhere((d) => d.name == 'T');
      final early = def.instantiate();
      engine.dispose();

      final late = def.instantiate();
      expect(late.getProperty('taps'), 0);
      early.setProperty('taps', 3);
      expect(early.getProperty('taps'), 3);

      for (final d in defs) {
        d.dispose();
      }
      expect(
        late.getProperty('taps'),
        0,
        reason: 'a component outlives its definitions too',
      );
      early.dispose();
      late.dispose();
    });

    // Bug 3: name is read eagerly, so it answers after every sibling is freed.
    test('definition name survives disposal of the whole list', () {
      final engine = InterpreterSlintEngine();
      final defs = _compile(engine);
      engine.dispose();
      for (final d in defs) {
        d.dispose();
      }
      expect(defs.map((d) => d.name).toSet(), {'T', 'U'});
    });

    // Bug 3: instantiating a disposed definition throws StateError.
    test('instantiate after definition dispose throws', () {
      final def = _compile(
        InterpreterSlintEngine(),
      ).firstWhere((d) => d.name == 'T')..dispose();
      expect(def.instantiate, throwsStateError);
      def.dispose(); // idempotent
    });
  });

  group('dispose from inside a callback', () {
    // Bug 4: disposing inside invokeCallback's handler must not free the
    // instance under the native frame that is running it.
    test('during invokeCallback', () {
      final c = _instance();
      c.setCallbackHandler('compute', (args) {
        c.dispose();
        return 5;
      });
      expect(c.invokeCallback('compute', [1]), 5);
      expect(
        () => c.getProperty('taps'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Component is disposed',
          ),
        ),
      );
      c.dispose(); // double dispose is a no-op
    });

    // Bug 4: a click whose handler disposes the component must not crash;
    // afterwards the render target is inert.
    test('during a pointer click', () {
      final c = _instance();
      var hits = 0;
      c.setCallbackHandler('hit', (_) {
        hits++;
        c.dispose();
        return null;
      });
      _click(c);

      expect(hits, 1);
      expect(() => c.getProperty('taps'), throwsStateError);
      expect(c.renderTarget.render(), isFalse);
      c.renderTarget.dispatchPointerEvent(
        const SlintPointerEvent(kind: SlintPointerEventKind.down, x: 50, y: 50),
      );
      c.renderTarget.resize(10, 10); // no-op, not an FFI call
      expect(hits, 1);
    });

    // Bug 4: resizing (freeing the pixel buffer) from inside a callback throws.
    test('resize inside a callback throws StateError', () {
      final c = _instance();
      Object? caught;
      c.setCallbackHandler('hit', (_) {
        try {
          c.renderTarget.resize(10, 10);
        } catch (e) {
          caught = e;
        }
        return null;
      });
      _click(c);
      expect(c.getProperty('taps'), 1, reason: 'the click must have landed');
      expect(caught, isA<StateError>());
      expect(c.renderTarget.width, 200, reason: 'the buffer was not touched');
    });
  });

  group('re-entrant callback registration', () {
    test('setCallbackHandler from inside invokeCallback', () {
      final c = _instance();
      c.setCallbackHandler('compute', (args) {
        c.setCallbackHandler('compute', (_) => 99);
        return 1;
      });
      expect(c.invokeCallback('compute', [1]), 1);
      expect(c.invokeCallback('compute', [1]), 99);
    });
  });
  group('owner isolate', () {
    test('dispose from another isolate throws', () async {
      final c = _instance();
      final token = slintIsolateToken();
      final port = ReceivePort();
      await Isolate.spawn(_checkDisposeOnSpawn, (port.sendPort, token));
      expect(await port.first, contains('dispose'));
      expect(c.getProperty('taps'), 0);
      c.dispose();
    });
  });

  group('callback return values', () {
    // Bug 7: a Dart handler's return value is what invokeCallback returns.
    test('int result reaches invokeCallback', () {
      final c = _instance();
      c.setCallbackHandler('compute', (args) => (args[0] as int) * 2);
      expect(c.invokeCallback('compute', [21]), 42);
    });

    // Bug 7: a pure callback in a binding reads the handler's result.
    test('pure callback result reaches a property binding', () {
      final c = _instance();
      c.setCallbackHandler('compute', (args) => (args[0] as int) * 2);
      c.setCallbackHandler('label', (args) => 'n${args[0]}');
      expect(c.getProperty('shown'), 42);
      expect(c.getProperty('text'), 'n1');
    });

    // Bug 7: struct results cross as JSON objects.
    test('struct result', () {
      final c = _instance();
      c.setCallbackHandler('make', (_) => {'a': 7, 'b': 'x'});
      expect(c.invokeCallback('make', []), {'a': 7, 'b': 'x'});
    });

    // Bug 7: a null result reads as the declared type's default.
    test('null result reads as the type default', () {
      final c = _instance();
      c.setCallbackHandler('compute', (_) => null);
      c.setCallbackHandler('label', (_) => null);
      expect(c.getProperty('shown'), 0);
      expect(c.getProperty('text'), '');
    });

    // Bug 7: a throwing handler reports through the zone; Slint gets the
    // default instead of the exception unwinding through Rust.
    test('throwing handler reports to the zone and yields the default', () {
      final c = _instance();
      c.setCallbackHandler('compute', (_) => throw StateError('handler bug'));
      final errors = <Object>[];
      Object? shown;
      runZonedGuarded(
        () => shown = c.getProperty('shown'),
        (e, _) => errors.add(e),
      );
      expect(shown, 0);
      expect(errors, [
        isA<StateError>().having((e) => e.message, 'message', 'handler bug'),
      ]);
    });
  });
}
