import 'dart:isolate';

import 'package:slint/slint_core.dart';
import 'package:test/test.dart';

/// Counts releases instead of freeing anything native.
class _Guarded with SlintNativeDisposeGuard {
  var releases = 0;
  @override
  void releaseNative() => releases++;
}

void main() {
  late _Guarded g;
  setUp(() => g = _Guarded());

  // Guards: disposing an idle component must free it at once, not leak it.
  test('idle dispose releases immediately', () {
    g.disposeNative();
    expect(g.releases, 1);
  });

  // Guards: a dispose from inside a native call must not free under the
  // native frame; it runs when the call returns.
  test('dispose inside guardNative waits for the call to return', () {
    g.guardNative(() {
      g.disposeNative();
      expect(g.releases, 0);
    });
    expect(g.releases, 1);
  });

  // Guards: only the outermost return releases, and exactly once.
  test('nested calls release once, when the outermost returns', () {
    g.guardNative(() {
      g.guardNative(() => g.disposeNative());
      expect(g.releases, 0, reason: 'the outer call is still on the stack');
      g.disposeNative();
    });
    expect(g.releases, 1);
  });

  // Guards: a throwing call must not strand a pending release.
  test('a pending release still runs when the call throws', () {
    expect(
      () => g.guardNative<void>(() {
        g.disposeNative();
        throw StateError('boom');
      }),
      throwsStateError,
    );
    expect(g.releases, 1);
    expect(g.inNativeCall, isFalse);
  });

  // Guards: inNativeCall tracks nesting depth (resize relies on it).
  test('inNativeCall reflects the depth', () {
    expect(g.inNativeCall, isFalse);
    g.guardNative(() {
      expect(g.inNativeCall, isTrue);
      g.guardNative(() => expect(g.inNativeCall, isTrue));
      expect(g.inNativeCall, isTrue);
    });
    expect(g.inNativeCall, isFalse);
  });

  // Guards: double dispose must not double-free.
  test('disposing twice releases once', () {
    g.disposeNative();
    g.disposeNative();
    g.guardNative(() => g.disposeNative());
    expect(g.releases, 1);
  });

  // Guards: guardNative passes the call's result through.
  test('guardNative returns the call result', () {
    expect(g.guardNative(() => 42), 42);
  });

  // Guards: deferRelease must not run while a native call is still active.
  test('deferRelease inside guardNative waits for the call to return', () {
    var released = false;
    g.guardNative(() {
      g.deferRelease(() => released = true);
      expect(released, isFalse);
    });
    expect(released, isTrue);
  });

  test('checkSlintOwnerIsolate rejects another isolate', () async {
    final token = slintIsolateToken();
    final port = ReceivePort();
    await Isolate.spawn(_checkDisposeOnSpawn, (port.sendPort, token));
    expect(await port.first, contains('dispose'));
  });
}

void _checkDisposeOnSpawn((SendPort, Object) args) {
  try {
    checkSlintOwnerIsolate(args.$2, 'dispose');
    args.$1.send('ok');
  } on StateError catch (e) {
    args.$1.send(e.message);
  }
}
